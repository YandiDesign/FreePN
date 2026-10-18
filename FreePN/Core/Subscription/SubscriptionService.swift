import Foundation

/// Fetch paralel antar sumber (TaskGroup), timeout 15 dtk, limit 10MB, UA clash.meta.
///
/// D48 — BUKAN `actor` LAGI. Semula `fetchOne` adalah method actor, jadi
/// `AutoParser.parse` (pekerjaan CPU paling berat di seluruh app: YAML 10MB
/// di-parse karakter demi karakter) SELALU berjalan di satu eksekutor
/// cooperatif tunggal. `withTaskGroup` di callers tetap jalan tapi nol
/// paralelisme untuk parsing — semua sumber diantre satu per satu, dan hanya
/// satu core yang kerja padahal mesin punya enam.
///
/// Sekarang `final class` dengan state yang semuanya `let` dan aman dipakai
/// lintas thread (`URLSession` thread-safe). Hasilnya parsing beberapa feed
/// besar berjalan benar-benar paralel di semua core — seperti render yang
/// memakai semua core, bukan seperti satu thread yang menganggur.
///
/// TIDAK ADA cache feed (D90). Dulu `fetchOne` lebih dulu membaca salinan
/// teks feed yang tersimpan dan, selama TTL 6 jam, tidak menyentuh jaringan
/// sama sekali — jadi Refresh tidak pernah melihat entri baru yang ditambahkan
/// di sisi penyedia, dan sumber yang dihapus meninggalkan salinan yang tidak
/// pernah dibersihkan. Sekarang hasil SELALU dari jaringan: satu-satunya
/// sumber kebenaran adalah feed yang baru diunduh.
public final class SubscriptionService: @unchecked Sendable {
    public struct FetchOutcome {
        public var nodes: [ProxyNode]
        public var unsupported: Int
        /// Node korup yang dibuang jaring D51 (terpisah dari `unsupported`).
        public var unusable: Int
        public var usedURL: String
        public var fetchedAt: Date
    }

    private let session: URLSession

    public init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = AppConstants.fetchTimeout
        cfg.timeoutIntervalForResource = AppConstants.fetchTimeout
        self.session = URLSession(configuration: cfg)
    }

    /// Kemajuan unduhan satu sumber, untuk ditampilkan ke user.
    public struct FetchProgress {
        /// Kandidat yang sedang dicoba (1-based) dan totalnya.
        public var attempt: Int
        public var total: Int
        public var url: String
    }

    /// Plafon waktu per sumber. Setelah ini, sisa kandidat tidak dicoba lagi.
    ///
    /// D91: tanpa plafon ini, satu sumber bisa membekukan layar 15 kandidat x
    /// 15 dtk = 225 dtk (OpenRunner), dan tidak ada cara berhenti selain
    /// menutup app.
    public static let perSourceBudget: TimeInterval = 45

    /// Budget untuk kandidat SETELAH yang pertama.
    ///
    /// Kandidat pertama tetap dapat timeout penuh karena itu yang paling mungkin
    /// berhasil. Setelah itu yang dilalui hanyalah alternatif tanggal — kalau
    /// server hanya lambat, menunggu 15 dtk penuh untuk tiap tanggal cuma
    /// memperpanjang rasa macet tanpa mengubah hasilnya. Kode 4xx dijawab
    /// cepat; yang lambat biasanya sudah 502.
    public static let followupTimeout: TimeInterval = 5

    public func fetchOne(_ source: VPNSubscriptionSource,
                         progress: (@MainActor @Sendable (FetchProgress) -> Void)? = nil
                        ) async -> (FetchOutcome?, String?) {
        let cands = SourceResolver.candidates(for: source)
        var lastErr: String? = nil
        let started = Date()
        for (index, urlStr) in cands.enumerated() {
            // Batalnya refresh harus benar-benar menghentikan unduhan. Ini
            // bukan kode mati lagi: `AppState.refreshTask` sekarang bisa
            // dibatalkan user lewat tombol Batal.
            if Task.isCancelled { return (nil, "Cancelled") }
            // D91: plafon total. Berhenti lebih cepat daripada membekukan
            // layar, dan hasil yang sudah didapat tetap dipakai.
            if Date().timeIntervalSince(started) >= Self.perSourceBudget {
                lastErr = lastErr ?? "Timeout"
                break
            }
            await progress?(FetchProgress(attempt: index + 1, total: cands.count, url: urlStr))
            guard let url = URL(string: urlStr) else { continue }
            let timeout = index == 0 ? AppConstants.fetchTimeout : Self.followupTimeout
            do {
                var req = URLRequest(url: url, timeoutInterval: timeout)
                req.setValue(AppConstants.userAgent, forHTTPHeaderField: "User-Agent")
                let (data, resp) = try await session.data(for: req)
                guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                    let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
                    lastErr = "HTTP \(code)"
                    // 401/403/404/410 = path-nya memang salah; mencoba tanggal
                    // lain tidak akan mengubahnya. Berhenti di sini.
                    if [401, 403, 404, 410].contains(code) { break }
                    continue
                }
                guard data.count <= AppConstants.maxResponseBytes else { lastErr = "Response >10MB"; continue }
                // `String(data:encoding:.utf8)` mengembalikan nil untuk feed
                // Latin-1 atau yang ber-BOM — keduanya ada di dunia nyata dan
                // sebelumnya dilaporkan sebagai "Empty". Lossy UTF-8 +
                // pelepasan BOM lebih baik daripada membuang feed utuh.
                let text = Self.decodeText(data)
                guard !text.isEmpty else { lastErr = "Empty"; continue }
                guard let parsed = await parseOffMain(text, sourceID: source.id) else {
                    lastErr = "Parse failed"; continue
                }
                if parsed.nodes.isEmpty { lastErr = "0 node"; continue }
                return (FetchOutcome(nodes: parsed.nodes, unsupported: parsed.unsupported,
                                     unusable: parsed.unusable, usedURL: urlStr,
                                     fetchedAt: Date()), nil)
            } catch {
                lastErr = error.localizedDescription
                continue
            }
        }
        // Gagal total = sumber TIDAK punya data. Tidak ada salinan lokal yang
        // boleh menyelamatkannya: kalau dilepas, user melihat jumlah server
        // dari feed yang sudah dihapus atau sudah tidak berlaku. Nol itu jujur.
        return (nil, lastErr ?? "Unavailable")
    }

    /// Parse feed DI LUAR cooperative pool utama.
    ///
    /// `AutoParser.parse` adalah pekerjaan CPU terberat di app (YAML 10 MB
    /// karakter demi karakter) dan TIDAK punya titik suspensi di dalamnya —
    /// kalau dipanggil langsung dari fungsi `async`, dia memegang satu
    /// cooperative thread sampai selesai dan membuat task lain (termasuk hop
    /// ke MainActor) ikut antre.
    private func parseOffMain(_ text: String,
                              sourceID: String) async -> AutoParser.Outcome? {
        let outcome = await Task.detached(priority: .userInitiated) {
            AutoParser.parse(text: text, sourceID: sourceID)
        }.value
        return Task.isCancelled ? nil : outcome
    }

    /// UTF-8 dengan fallback lossy + pelepasan BOM.
    private static func decodeText(_ data: Data) -> String {
        let trimmed = data.first == 0xEF ? data.dropFirst(3) : data[...]
        return String(decoding: trimmed, as: UTF8.self)
    }

    public func fetchAll(_ sources: [VPNSubscriptionSource]) async -> [String: (FetchOutcome?, String?)] {
        var out: [String: (FetchOutcome?, String?)] = [:]
        await withTaskGroup(of: (String, (FetchOutcome?, String?)).self) { group in
            for s in sources where s.isEnabled {
                group.addTask { (s.id, await self.fetchOne(s)) }
            }
            for await (id, res) in group { out[id] = res }
        }
        return out
    }
}
