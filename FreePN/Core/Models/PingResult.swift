import Foundation

/// Kenapa sebuah node gagal diuji.
///
/// DULU semua kegagalan dijahit jadi satu vonis: "tanpa internet". Padahal
/// "kredensial ditolak server" dan "jaringan tidak bisa menghubungi server"
/// punya perbaikannya yang sama sekali berbeda, dan hanya yang kedua yang
/// bisa hilang dengan sendirinya (sinyal, throttling, server yang overloaded).
/// Karena keduanya dicampur, pesan error selalu menyebut "kredensial salah"
/// — termasuk untuk semua node mati karena alasan lain.
///
/// `coreDown` punya arti khusus: proses probe-nya sendiri yang mati, jadi
/// hasilnya TIDAK membuktikan apa pun soal node dan harus diperlakukan seperti
/// "belum diuji", bukan "mati".
public enum ProbeFailure: String, Codable, Hashable, Equatable {
    /// Server menolak kredensial (auth failed / unauthorized).
    case auth
    /// Tidak merespons dalam budget waktu.
    case timeout
    /// Tidak bisa menghubungi server sama sekali.
    case unreachable
    /// Hostname tidak bisa di-resolve.
    case dns
    /// Core menolak outbound-nya (config tidak valid untuk protokol itu).
    case rejected
    /// Proses probe mati di tengah pengujian.
    case coreDown
    /// Gagal dengan sebab yang tidak dikenali.
    case unknown

    /// Layak dicoba lagi dalam beberapa detik? Credential dan config yang
    /// ditolak tidak akan berubah sendiri; sisanya bisa.
    public var worthRetrying: Bool {
        switch self {
        case .timeout, .unreachable, .dns, .unknown: return true
        case .auth, .rejected, .coreDown: return false
        }
    }

    /// Petakan pesan error sing-box ke sebab yang bisa ditindaklanjuti.
    ///
    /// `statusCode` dipakai sebagai petunjuk tambahan: Clash API memakai
    /// 504 untuk timeout dan 503 untuk kegagalan lain.
    public static func classify(_ raw: String, statusCode: Int = 0) -> ProbeFailure {
        let m = raw.lowercased()
        func has(_ needles: String...) -> Bool { needles.contains { m.contains($0) } }
        // Urutan dari paling spesifik: "connection reset by peer" mengandung
        // "connection", jadi pola timeout harus dicek lebih dulu.
        if has("authentication failed", "authentication required", "invalid credential",
               "unauthorized", "forbidden", "permission denied", "invalid password",
               "invalid uuid", "decrypt", "bad password") { return .auth }
        if has("no such host", "lookup ", "dns", "server misbehaving", "namer") { return .dns }
        if has("timeout", "deadline exceeded", "i/o timeout", "timed out") { return .timeout }
        if has("network is unreachable", "no route to host", "connection refused",
               "connection reset", "reset by peer", "broken pipe", "host is down",
               "eof", "unreachable") { return .unreachable }
        if has("unsupported", "not supported", "invalid config", "unknown field",
               "outbound") { return .rejected }
        if statusCode == 504 { return .timeout }
        return .unknown
    }
}

/// Hasil pemeriksaan sebuah node — SATU tahap, satu angka.
///
/// D50: dulu ada dua tahap. `latencyMs` (handshake TCP ke host:port) cuma
/// membuktikan **port terbuka**; `webLatencyMs` (request HTTP lewat node itu)
/// baru membuktikan node benar-benar bisa dipakai. Tahap-1 tidak pernah dipakai
/// untuk memutuskan apa pun — dia hanya mempersempit siapa yang perlu diuji
/// tahap-2, sehingga tiap node diproses DUA kali dan separuh hasil kerja
/// dibuang. Sekarang hanya ada satu pengukuran.
///
/// CARA MENGUKUR (mode bawaan): satu proses sing-box sementara (TANPA TUN, jadi
/// tanpa root dan tidak mengganggu sesi VPN yang sedang jalan) memuat node-node
/// kandidat sebagai outbound, lalu tiap outbound diuji lewat Clash API
/// `/proxies/<tag>/delay` yang benar-benar menembak `generate_204` di internet
/// **melalui node tersebut**. Sukses = ada internet, dan angkanya adalah
/// latensi end-to-end yang jujur.
///
/// MODE PING CEPAT: kalau `AppSettings.fastPing` aktif, pengukuran diganti
/// handshake TCP langsung (atau probe UDP untuk Hysteria2) — jauh lebih cepat,
/// tapi hanya membuktikan server merespons. Angka itu ditandai `approximate`
/// supaya UI tidak menampilkan batas atas seolah-olah RTT.
///
/// `internetOK == nil` berarti **belum diverifikasi** — probe tidak sempat jalan
/// (core hilang, dibatalkan, atau sedang dipakai operasi lain). Itu BUKAN bukti
/// node mati; membedakannya penting, kalau tidak connect ke node yang sebenarnya
/// bagus akan ditolak.
public struct PingResult: Codable, Hashable {
    public var nodeID: String
    /// Latensi end-to-end lewat node (ms); nil = gagal / tidak ada internet.
    public var webLatencyMs: Int?
    /// true = ada internet, false = terbukti tidak ada, nil = belum diuji.
    public var internetOK: Bool?
    /// Kapan verdict ini diambil (dipakai saat diagnose, bukan saat tampil).
    public var at: Date
    /// Angka ini BUKAN RTT terukur — batas atas dari probe UDP (Hysteria2) di
    /// mode ping cepat, atau hasil tidak adanya bukti kematian. Tampil dengan
    /// penanda "≤" supaya tidak dibaca sebagai latensi sebenarnya.
    public var approximate: Bool
    /// Kenapa gagal, kalau gagal. `nil` = berhasil atau belum diuji.
    ///
    /// Disimpan supaya pesan error bisa jujur ("kredensial ditolak" vs
    /// "tidak bisa menghubungi server") alih-alih selalu menyebut yang
    /// pertama. Tidak pernah ditampilkan sebagai vonis yang lebih halus:
    /// `isDeadEnd` tetap `internetOK == false`.
    public var failure: ProbeFailure?

    /// Terbukti tidak bisa dipakai — jangan tanya connect.
    public var isDeadEnd: Bool { internetOK == false }
    /// Angka yang ditampilkan / dasar urut. Tidak ada angka yang sah untuk
    /// node yang sudah diketahui tidak bisa internet.
    public var bestMs: Int? { internetOK == false ? nil : webLatencyMs }

    public init(nodeID: String, webLatencyMs: Int? = nil,
                internetOK: Bool? = nil, at: Date = Date(),
                approximate: Bool = false, failure: ProbeFailure? = nil) {
        self.nodeID = nodeID
        self.webLatencyMs = webLatencyMs
        self.internetOK = internetOK
        self.at = at
        self.approximate = approximate
        self.failure = failure
    }

    // Backward-compat: `ping.json`/state lama tanpa key `approximate` tetap
    // terbaca. Decoder eksplisit (bukan sintesis) karena `Codable` hasil
    // sintesis membuat satu field baru yang WAJIB membuat seluruh file lama
    // gagal decode — dan itu berarti semua riwayat ping user hilang diam-diam.
    private enum CodingKeys: String, CodingKey {
        case nodeID, webLatencyMs, internetOK, at, approximate, failure
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nodeID = try c.decodeIfPresent(String.self, forKey: .nodeID) ?? ""
        webLatencyMs = try c.decodeIfPresent(Int.self, forKey: .webLatencyMs)
        internetOK = try c.decodeIfPresent(Bool.self, forKey: .internetOK)
        at = try c.decodeIfPresent(Date.self, forKey: .at) ?? Date()
        approximate = try c.decodeIfPresent(Bool.self, forKey: .approximate) ?? false
        failure = try c.decodeIfPresent(ProbeFailure.self, forKey: .failure)
    }

    /// Terapkan verdict probe. `skipped` (probe tidak sempat jalan) HARUS
    /// mengembalikan hasil lama apa adanya — kalau tidak, node yang sebenarnya
    /// bagus ikut ditandai "tanpa internet" lalu connect ke sana ditolak.
    /// Verdict yang benar membesarkan ulang `at`, karena itu pengukuran baru.
    public func applying(_ verdict: ProbeVerdict) -> PingResult {
        switch verdict {
        case .ok(let ms):     return PingResult(nodeID: nodeID, webLatencyMs: ms, internetOK: true)
        case .noInternet:    return PingResult(nodeID: nodeID, webLatencyMs: nil, internetOK: false)
        case .failed(let why):
            return PingResult(nodeID: nodeID, webLatencyMs: nil, internetOK: false, failure: why)
        case .skipped:       return self
        }
    }

    /// Terapkan verdict dari mode ping cepat.
    ///
    /// `.aliveUpperBound` menghasilkan `internetOK == nil` — BUKAN `true`.
    ///
    /// Ini inti perbaikan D96. Handshake TCP membuktikan satu hal saja: ada
    /// yang menjawab di port itu.dan tidak ada apa pun tentang apakah node itu
    /// benar-benar bisa memproksi trafik. Menandai `internetOK = true`
    /// membelokkan:
    ///
    ///  - badge jadi hijau seolah-olah itu RTT terukur (user membacanya
    ///    "ping normal"),
    ///  - `quickConnectChoice` memasukkan node itu ke tier **verified**
    ///    (`internetOK == true`) lalu memilih yang tercepat — jadi Quick
    ///    Connect justru memilih node yang paling cepat tapi tidak bisa dipakai,
    ///  - `topByLatency` menghitungnya sama dengan node yang RTT-nya
    ///    benar-benar terukur.
    ///
    /// `nil` berarti "belum diverifikasi", dan itu memang status yang jujur:
    /// angka batas atas tetap disimpan untuk mengurutkan, tapi tidak pernah
    /// diklaim sebagai bukti internet working. `.dead` masih `false` karena
    /// port tertutup itu bukti yang sah.
    public func applying(_ outcome: ServerPingOutcome) -> PingResult {
        switch outcome {
        case .replied(let ms):
            return PingResult(nodeID: nodeID, webLatencyMs: ms, internetOK: true)
        case .aliveUpperBound(let ms):
            return PingResult(nodeID: nodeID, webLatencyMs: ms, internetOK: nil,
                              approximate: true)
        case .dead:
            return PingResult(nodeID: nodeID, webLatencyMs: nil, internetOK: false)
        }
    }
}
