import Foundation

/// Real delay untuk server terpilih/terhubung via Clash API core.
/// Mengukur apakah node benar-benar bisa dipakai, bukan sekadar port terbuka.
public enum RealDelayTester {
    /// Session KHUSUS untuk probe, bukan `URLSession.shared`.
    ///
    /// BUG YANG INI PERBAIKI (D91): `URLSession.shared` dibangun dengan
    /// `httpMaximumConnectionsPerHost` bawaan **6**, dan setiap request probe
    /// menuju host yang sama — `127.0.0.1:<clashPort>`. Berapa pun konkurensi
    /// yang diminta `CPUGovernor` (bisa 32), paling banyak 6 yang benar-benar
    /// jalan; sisanya MENUNGGU di antrean koneksi sambil **memakan
    /// `timeoutIntervalRequest`-nya sendiri**. Ketika antrean itu penuh, request
    /// timeout sebelum sing-box pernah mencoba node itu — lalu dicatat sebagai
    /// "tanpa internet" padahal core-nya tidak pernah mencobanya.
    ///
    /// Itu sebab besarnya hasil probe yang kosong sementara sebagian node
    /// jelas hidup.
    /// Batas koneksi per host untuk sesi probe.
    ///
    /// HARUS jauh di atas jendela konkurensi governor (`CPUGovernor.computeLimit`,
    /// puluhan slot) karena SEMUA request probe menuju host yang sama —
    /// `127.0.0.1:<clashPort>`.
    ///
    /// Nilai 0 di sini FATAL: di macOS 13 `httpMaximumConnectionsPerHost = 0`
    /// berarti TIDAK ADA koneksi yang boleh dibuat (bukan "tanpa batas"),
    /// sehingga setiap request antre selamanya lalu timeout (`-1001`) —
    /// `sample` memetakannya jadi `.coreDown`, dan `verifyInSession`
    /// mengubahnya jadi `.skipped` untuk SEMUA node. Hasilnya: Ping All mode
    /// internet selalu "0 hidup, tidak ada ping" padahal node-nya sehat dan
    /// ping cepat normal. Diverifikasi empiris: shared→200, =0→timeout,
    /// =10→200.
    public static let maxProbeConnectionsPerHost = 512

    private static let probeSession: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        // Bukan 0 — lihat `maxProbeConnectionsPerHost`. Governor (`CPUGovernor`)
        // yang memutuskan berapa slot yang hidup; session tidak boleh jadi
        // pembatas kedua.
        cfg.httpMaximumConnectionsPerHost = maxProbeConnectionsPerHost
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 30
        cfg.waitsForConnectivity = false
        cfg.httpShouldUsePipelining = false
        return URLSession(configuration: cfg)
    }()

    /// Hasil satu percobaan: delay bila berhasil, atau sebab gagalnya.
    ///
    /// Dulu ini cuma `Int?`, jadi "gagal" tidak pernah membawa informasi apa
    /// pun. Sekarang kegagalan yang paling penting justru yang paling sering
    /// keliru dibaca: `coreDown` (proses probe mati) TIDAK sama dengan
    /// node-nya mati.
    public struct ProbeSample: Equatable {
        public var delayMs: Int?
        public var failure: ProbeFailure?

        public init(delayMs: Int? = nil, failure: ProbeFailure? = nil) {
            self.delayMs = delayMs
            self.failure = failure
        }
        public var ok: Bool { delayMs != nil }
    }

    public static func sample(proxyName: String, clashPort: Int,
                              testURL: String,
                              timeout: TimeInterval = AppConstants.internetCheckTimeout) async -> ProbeSample {
        let name = proxyName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? proxyName
        // `timeout` diteruskan ke sing-box (dia yang menentukan deadline uji),
        // sedangkan tambahan untuk HTTP-nya sendiri.
        let urlS = "http://127.0.0.1:\(clashPort)/proxies/\(name)/delay?timeout=\(Int(timeout*1000))&url=\(testURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? testURL)"
        guard let url = URL(string: urlS) else {
            return ProbeSample(failure: .rejected)
        }
        do {
            var req = URLRequest(url: url, timeoutInterval: timeout + 3)
            req.httpMethod = "GET"
            // D91: status code DAN body TIDAK lagi dibuang. Dulu `let (data, _)`
            // membuat "authentication failed" dan "network is unreachable"
            // jadi nilai yang sama persis — keduanya `nil`.
            let (data, resp) = try await probeSession.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let d = o["delay"] as? Int {
                return ProbeSample(delayMs: d, failure: nil)
            }
            let message = ((try? JSONSerialization.jsonObject(with: data) as? [String: Any])??["message"] as? String)
                ?? String(data: data.prefix(400), encoding: .utf8)
                ?? ""
            return ProbeSample(failure: .classify(message, statusCode: status))
        } catch let err as URLError {
            // Semua request probe menuju loopback. Jadi error lapisan
            // koneksi di sini berarti CORE-NYA yang mati atau belum siap —
            // bukan bukti apa pun tentang node-nya.
            switch err.code {
            case .cannotConnectToHost, .networkConnectionLost, .cannotFindHost,
                 .notConnectedToInternet, .timedOut:
                return ProbeSample(failure: .coreDown)
            case .cancelled:
                return ProbeSample(failure: .coreDown)
            default:
                return ProbeSample(failure: .coreDown)
            }
        } catch {
            return ProbeSample(failure: .unknown)
        }
    }

    /// Dipertahankan untuk pemanggil yang hanya peduli angka.
    public static func test(proxyName: String, testURL: String,
                            timeout: TimeInterval = AppConstants.internetCheckTimeout) async -> Int? {
        await sample(proxyName: proxyName, clashPort: FreePort.defaultClashPort,
                     testURL: testURL, timeout: timeout).delayMs
    }

    public static func test(proxyName: String, clashPort: Int,
                            testURL: String,
                            timeout: TimeInterval = AppConstants.internetCheckTimeout) async -> Int? {
        await sample(proxyName: proxyName, clashPort: clashPort,
                     testURL: testURL, timeout: timeout).delayMs
    }
}

/// Hasil uji satu node. PENTING: `skipped` BUKAN berarti node mati — itu berarti
/// probe tidak sempat jalan (core tak ada, sesi habis, dibatalkan). Mencatat
/// `skipped` sebagai "tanpa internet" akan membuat UI menolak connect ke node
/// yang sebenarnya bagus — jadi dua keadaan ini wajib dibedakan.
public enum ProbeVerdict: Equatable {
    case ok(Int)
    case noInternet
    /// Gagal dengan sebab yang diketahui. Tetap berarti "mati" untuk
    /// `isDeadEnd`, tapi alasannya tersimpan supaya pesan error bisa jujur.
    case failed(ProbeFailure)
    case skipped
}

/// Verifikasi "benar-benar bisa akses internet" untuk sekumpulan node.
///
/// MASALAH YANG DISELESAIKAN: ping TCP (handshake ke host:port) cuma membuktikan
/// port terbuka. Ribuan node gratis punya port hidup tapi proxy-nya mati —
/// kredensial salah, egress diblokir, atau upstream-nya down — sehingga user
/// connect succeeding tapi tidak bisa akses internet sama sekali.
///
/// CARA KERJA: satu proses sing-box sementara (TANPA TUN, jadi tanpa root dan
/// tidak mengganggu sesi VPN yang sedang jalan) memuat node-node kandidat
/// sebagai outbound. Lalu tiap outbound diuji lewat Clash API
/// `/proxies/<tag>/delay` yang benar-benar menembak `generate_204` di internet
/// MELALUI node tersebut. Sukses = ada internet, dan angkanya adalah latensi
/// end-to-end yang jujur.
///
/// MODEL SESI: outbound hanya bisa diuji kalau sudah ada di config core yang
/// sedang jalan. Karena itu core dihidupkan sebagai SESI yang memuat banyak node
/// sekaligus (`sessionSize`), lalu diuji dari dalam sesi itu. Menyalakan core
/// untuk tiap dozen node akan jauh lebih lambat (beberapa detik per sesi).
@MainActor
public final class InternetProbe: ObservableObject {
    /// Berapa node dimuat dalam SATU sesi core. Config berisi satu outbound per
    /// node dan ribuan outbound akan sangat berat untuk sing-box.
    /// `nonisolated` supaya rumus biayanya bisa diuji tanpa actor.
    ///
    /// D91: 300 -> 600. Diukur dengan node asli milik user: config 300
    /// outbound = 108 KB / 0,06 dtk untuk `sing-box check`, 600 outbound =
    /// 267 KB / 0,66 dtk. Dua kali outbound, biaya check naik ~0,6 dtk —
    /// sedangkan jumlah sesi untuk 20.000 node turun dari 73 ke 37, dan tiap
    /// sesi punya biaya tetap (spawn + tunggu API + parse config).
    public nonisolated static let sessionSize = 600

    /// Berapa kali core probe harus dinyalakan ulang untuk `total` node.
    ///
    /// Setiap sesi punya biaya tetap: tulis config 300 outbound, jalankan
    /// subprocess `sing-box check`, spawn core, lalu poll API sampai siap.
    /// Jadi ini pure overhead — dan **satu-satunya** cara menguranginya adalah
    /// memperbesar jendela sesi, yang sayangnya dibatasi beratnya config
    /// sing-box (lihat `sessionSize`).
    ///
    /// Jendela sesi = `sessionSize` node per sesi, berurutan. Jadi jumlahnya
    /// persis `ceil(total / sessionSize)` — tidak ada lagi efek samping dari
    /// besar batch karena tidak ada lagi pemotong batch (D50).
    ///
    /// Murni & nonisolated supaya bisa diuji tanpa menjalankan core.
    public nonisolated static func sessionRestarts(total: Int) -> Int {
        guard total > 0 else { return 0 }
        return (total + sessionSize - 1) / sessionSize
    }

    @Published public private(set) var isRunning = false
    @Published public private(set) var lastError: String? = nil

    /// Berapa node yang DITOLAK core pada sesi terakhir (D93).
    ///
    /// Ini penting: node yang ditolak config tidak akan pernah diuji, jadi
    /// absennya dari hasil akan terlihat sama dengan "gagal". Tanpa angka ini,
    /// "0 dari 300 hidup" tidak bisa dibedakan dari "0 dari 12 hidup, sisanya
    /// core tolak".
    @Published public private(set) var lastRejectedCount = 0

    private let runner = LocalCoreRunner()
    private var lastRejected = 0
    private var clashPort = 0
    private var cancelled = false
    /// nodeID -> indeks outbound di config sesi aktif.
    private var sessionIndex: [String: Int] = [:]

    public init() {}

    public func cancel() {
        cancelled = true
        endSession()
    }

    // MARK: - Sesi

    /// Sesi aktif? (node-node ini sudah punya outbound di core yang jalan)
    public func isInSession(_ node: ProxyNode) -> Bool {
        sessionIndex[node.id] != nil
    }

    /// Nyalakan sesi baru berisi `nodes` (ganti sesi sebelumnya).
    /// `false` = core tidak bisa dijalankan (binary hilang / config invalid).
    public func beginSession(nodes: [ProxyNode]) async -> Bool {
        endSession()
        cancelled = false
        isRunning = true
        guard !nodes.isEmpty else { isRunning = false; return false }

        // PENTING: `startCore` mengembalikan node yang BENAR-BENAR terpakai
        // setelah penyaringan `sing-box check`, dan `probeConfigJSON`
        // menomori tag berdasarkan POSISI DI DAFTAR ITU. Kalau `sessionIndex`
        // dibangun dari daftar asli (yang lebih panjang), setiap node sesudah
        // bagian yang terbuang akan dipetakan ke tag milik node LAIN — dan
        // angka latensi tampil untuk server yang tidak diuji sama sekali.
        // Inilah sumber "ping hasil ngawur" yang paling menyesatkan (D61).
        let candidate = Array(nodes.prefix(Self.sessionSize))
        lastRejected = 0
        guard let used = await startCore(nodes: candidate) else { isRunning = false; return false }
        clashPort = used.port
        lastError = nil
        lastRejectedCount = lastRejected

        var idx: [String: Int] = [:]
        idx.reserveCapacity(used.nodes.count)
        for (i, n) in used.nodes.enumerated() { idx[n.id] = i }
        sessionIndex = idx
        if idx.isEmpty { isRunning = false }
        return !idx.isEmpty
    }

    public func endSession() {
        stopCore()
        sessionIndex = [:]
        if isRunning { isRunning = false }
    }

    /// Uji satu potongan di dalam sesi yang sudah hidup. Node yang tidak ada di
    /// sesi ini otomatis `.skipped`.
    ///
    /// `limitProvider` membuat jumlah slot uji yang hidup SESUAI governor saat
    /// pengujian berjalan. Tanpa itu, angka dibekukan di awal dan Setting
    /// "Performance" tidak berpengaruh selama probe berjalan.
    @discardableResult
    public func verifyInSession(nodes: [ProxyNode], testURL: String,
                                concurrency: Int = 8,
                                timeout: TimeInterval = AppConstants.internetCheckTimeout,
                                limitProvider: (() -> Int)? = nil,
                                onResult: @escaping @MainActor (String, ProbeVerdict) -> Void) async -> Int {
        let testable = nodes.filter { sessionIndex[$0.id] != nil }
        for n in nodes where sessionIndex[n.id] == nil { onResult(n.id, .skipped) }
        guard !testable.isEmpty, clashPort != 0 else { return 0 }

        // Peta id->tag dihitung DI SINI (main actor). `withTaskGroup` menjalankan
        // closure-nya di luar actor, jadi `sessionIndex` tak boleh disentuh di dalam.
        let jobs: [(id: String, tag: String)] = testable.map {
            (id: $0.id, tag: SingBoxConfigBuilder.probeTag(sessionIndex[$0.id] ?? 0))
        }
        var online = 0
        let port = clashPort
        var next = 0
        // Sliding window, bukan gelombang — slot yang kosong langsung diisi
        // lagi, jadi jumlah uji yang hidup benar-benar = `window`. `window`
        // bisa berubah di tengah jalan mengikuti governor.
        var window = max(1, concurrency)
        var inflight = 0
        // D91: siapa saja yang sudah keluar dari group. Dipakai untuk melepas
        // sisa sebagai `.skipped` kalau core mati — `withTaskGroup` tidak bisa
        // jadi enumerasi sisa pekerjaan setelah `break`.
        var settled = Set<String>()
        await withTaskGroup(of: (String, RealDelayTester.ProbeSample).self) { group in
            func submit(_ job: (id: String, tag: String)) {
                group.addTask {
                    (job.id, await RealDelayTester.sample(proxyName: job.tag, clashPort: port,
                                                          testURL: testURL, timeout: timeout))
                }
                inflight += 1
            }
            while next < min(window, jobs.count) { submit(jobs[next]); next += 1 }
            while let (id, s) = await group.next() {
                inflight -= 1
                settled.insert(id)
                // D91 — PERBAIKAN PALING PENTING DI SINI. Kalau proses core
                // mati di tengah sesi, setiap `URLSession` berikutnya gagal
                // dengan "connection refused" dalam ~1 ms. Versi lama mencatat
                // semuanya sebagai `.noInternet`, jadi SATU core yang tumbang
                // menghasilkan vonis "mati" untuk ratusan node sekaligus.
                // Padahal setelah core mati, tidak ada hasil yang bisa dipercaya
                // — harus `.skipped`, yang tidak merusak verdict lama.
                guard runner.isRunning else {
                    onResult(id, .skipped)
                    group.cancelAll()
                    break
                }
                if let ms = s.delayMs {
                    online += 1
                    onResult(id, .ok(ms))
                } else {
                    // `coreDown` di sini berarti core-nya tumbang TEPAT SEBELUM
                    // hasil dibaca; sama seperti di atas, jangan sentuh verdict.
                    onResult(id, s.failure == .coreDown ? .skipped : .failed(s.failure ?? .unknown))
                }
                if cancelled { group.cancelAll(); break }
                if let lp = limitProvider {
                    let suggested = max(1, lp())
                    if suggested != window { window = suggested }
                }
                while !cancelled, inflight < window, next < jobs.count {
                    submit(jobs[next]); next += 1
                }
            }
            group.cancelAll()
        }
        // Sisa yang tidak pernah keluar (group dibatalkan karena core mati atau
        // user menekan batal) tidak boleh dihitung sebagai gagal.
        for job in jobs where !settled.contains(job.id) { onResult(job.id, .skipped) }
        return online
    }

    /// SATU-SATUNYA jalur masuk pengujian. Dipakai tombol Ping per baris
    /// maupun Ping All; keduanya identik dari ujung ke ujung, dan tidak ada lagi
    /// tahap TCP yang mendahuluinya.
    ///
    /// Outbound hanya bisa diuji kalau sudah ada di config core yang sedang
    /// hidup, jadi node dipotong per `sessionSize` dan tiap potongan mendapat
    /// sesinya sendiri. Tanpa ini, node di luar jendela sesi akan diam-diam
    /// berstatus "belum teruji" selamanya.
    ///
    /// Probe hanya boleh punya SATU sesi hidup pada satu waktu (ia menyimpan
    /// satu proses core). Karena itu kalau sesi sudah aktif dan node yang diminta
    /// tidak ada di dalamnya, jawabannya `.skipped` — bukan menyalakan core
    /// kedua yang akan menabrak sweep yang sedang jalan.
    @discardableResult
    public func verify(nodes: [ProxyNode], testURL: String,
                       concurrency: Int = 8,
                       timeout: TimeInterval = AppConstants.internetCheckTimeout,
                       retryTimeout: TimeInterval = AppConstants.internetCheckRetryTimeout,
                       deadline: Date? = nil,
                       limitProvider: (() -> Int)? = nil,
                       onResult: @escaping @MainActor (String, ProbeVerdict) -> Void) async -> Int {
        guard !nodes.isEmpty else { return 0 }
        // D91: habisnya waktu -> berhenti, dan sisa node dilepas sebagai
        // `skipped` (belum teruji), BUKAN "mati". Angka yang sudah didapat
        // tetap disimpan dan tetap ditampilkan.
        if let deadline, Date() >= deadline {
            for n in nodes { onResult(n.id, .skipped) }
            return 0
        }
        if isRunning {
            if nodes.allSatisfy({ isInSession($0) }) {
                return await verifyInSession(nodes: nodes, testURL: testURL,
                                             concurrency: concurrency,
                                             timeout: timeout, limitProvider: limitProvider,
                                             onResult: onResult)
            }
            for n in nodes { onResult(n.id, .skipped) }
            return 0
        }

        var online = 0
        var index = 0
        while index < nodes.count {
            // D91: sebelum menyalakan sesi berikutnya, cek sisa waktu. Sesi
            // berikutnya butuh spawn + parse config + probe utuh; memulainya
            // dengan sisa waktu 2 detik hanya menambah satu sesi tak berguna.
            if let deadline, Date() >= deadline {
                for n in nodes[index...] { onResult(n.id, .skipped) }
                break
            }
            let chunk = Array(nodes[index..<min(index + Self.sessionSize, nodes.count)])
            index += chunk.count
            guard await beginSession(nodes: chunk) else {
                lastError = lastError ?? L10n.string("probe_unavailable")
                for n in nodes[index...] { onResult(n.id, .skipped) }
                endSession()
                return online
            }
            // D91: dua tahap. Tahap 1 memakai budget pendek supaya ribuan
            // node selesai cepat; tahap 2 hanya untuk yang GAGAL dan masih
            // punya alasan yang bisa berubah sendiri (timeout / jaringan /
            // DNS), dengan budget jauh lebih besar.
            //
            // Kenapa perlu dua tahap, bukan satu timeout panjang saja: timeout
            // panjang untuk SEMUA node membuat satu putaran penuh mengambil
            // waktu tak masuk akal, sedangkan yang benar-benar hidup tetap
            // menjawab jauh di bawah itu. Timeout pendek untuk semua membuat
            // node lambat (QUIC/hysteria2, REALITY/uTLS, ws+TLS) vonis mati
            // permanen pada handshake dingin pertamanya.
            //
            // Kredensial yang ditolak dan config yang ditolak TIDAK dicoba
            // ulang — tidak akan berubah dalam beberapa detik.
            var retryable: [(id: String, node: ProxyNode)] = []
            online += await verifyInSession(nodes: chunk, testURL: testURL,
                                            concurrency: concurrency,
                                            timeout: timeout, limitProvider: limitProvider,
                                            onResult: { id, verdict in
                if case .failed(let why) = verdict, why.worthRetrying {
                    if let n = chunk.first(where: { $0.id == id }) { retryable.append((id, n)) }
                }
                onResult(id, verdict)
            })
            if cancelled { break }

            // Retry hanya kalau masih ada sisa waktu untuknya: sisa 3 dtk
            // tidak akan menolong node yang butuh 9 dtk, dan hanya menunda
            // sesi berikutnya.
            let canRetry = retryTimeout > timeout
                && (deadline.map { Date().addingTimeInterval(retryTimeout).addingTimeInterval(2) < $0 } ?? true)
            if !retryable.isEmpty, canRetry {
                for n in retryable.map(\.node) {
                    // Belum ada vonis baru selama jeda — jangan tandai apa pun.
                    onResult(n.id, .skipped)
                }
                online += await verifyInSession(nodes: retryable.map(\.node),
                                                testURL: testURL,
                                                concurrency: concurrency,
                                                timeout: retryTimeout,
                                                limitProvider: limitProvider,
                                                onResult: onResult)
            } else {
                for (id, _) in retryable { onResult(id, .failed(.unknown)) }
            }
            if cancelled { break }
        }
        endSession()
        return online
    }

    /// Uji satu node saja (tombol per baris).
    public func verifyOne(_ node: ProxyNode, testURL: String,
                          timeout: TimeInterval = AppConstants.internetCheckTimeout) async -> ProbeVerdict {
        var got: ProbeVerdict = .skipped
        await verify(nodes: [node], testURL: testURL, concurrency: 1, timeout: timeout) { _, v in got = v }
        return got
    }

    // MARK: - Inti

    /// Hasil start core probe: port clash API + node yang benar-benar jadi
    /// outbound (SETELAH penyaringan `sing-box check`).
    struct StartedCore {
        let port: Int
        let nodes: [ProxyNode]
    }

    /// Jalankan core probe lalu tunggu clash API siap. Nil bila tidak bisa.
    private func startCore(nodes: [ProxyNode]) async -> StartedCore? {
        let binary = CorePaths.singBox
        guard FileManager.default.isExecutableFile(atPath: binary) else {
            lastError = L10n.string("probe_unavailable"); return nil
        }
        let port = FreePort.tcp(from: FreePort.defaultClashPort)
        var mixed = FreePort.tcp(from: FreePort.defaultMixedPort)
        if mixed == port { mixed = FreePort.tcp(from: port + 1) }

        // D48: bangun JSON + tulis + `sing-box check` DI LUAR MainActor.
        // Ketiganya kerja murni & memblokir: config berisi ratusan outbound
        // (JSONSerialization `.prettyPrinted`) dan `validate` memanggil
        // `waitUntilExit()` pada proses anak. Semuanya di MainActor = UI beku
        // setiap kali sesi probe di-restart.
        let clashPort = port
        let mixedPort = mixed
        let prep = await Task.detached(priority: .userInitiated) {
            Self.prepareProbeConfig(nodes: nodes, clashPort: clashPort, mixedPort: mixedPort, binary: binary)
        }.value
        let cfgPath: String
        let used: [ProxyNode]
        switch prep {
        case .ok(let p, let kept):
            cfgPath = p
            used = kept
            lastRejected = max(0, nodes.count - kept.count)
        case .noUsableNode:
            lastRejected = nodes.count
            lastError = L10n.string("probe_all_nodes_invalid"); return nil
        case .ioFailed:
            return nil
        }

        // startAsync, JANGAN start: yang sinkron memanggil Thread.sleep dan
        // membekukan seluruh UI selama 2 detik.
        guard await runner.startAsync(configPath: cfgPath, binary: binary) else { return nil }

        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if cancelled { stopCore(); return nil }
            if runner.isRunning, await apiHealthy(port: port) {
                return StartedCore(port: port, nodes: used)
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
        stopCore()
        return nil
    }

    /// Hasil menyiapkan config probe, dipanggil dari luar actor.
    ///
    /// `internal` + bukan `private` supaya penyaringan ini bisa diuji dengan
    /// `sing-box` sungguhan — bug yang paling mahal kalau tidak diuji.
    enum ProbeConfigPrep: @unchecked Sendable {
        /// `path` config, plus node yang benar-benar terpakai (setelah penyaringan).
        case ok(String, [ProxyNode])
        /// TIDAK ADA node yang bisa dipakai — semua ditolak sing-box.
        case noUsableNode
        case ioFailed
    }

    /// Boleh dipanggil dari thread mana pun (tanpa state actor).
    nonisolated static func prepareProbeConfig(
        nodes: [ProxyNode], clashPort: Int, mixedPort: Int, binary: String
    ) -> ProbeConfigPrep {
        // Lapis-1: penyaring murah tanpa subprocess. Menangkap mayoritas node
        // korup sebelum kita membayar `sing-box check` sama sekali.
        let plausible = NodeDeduper.keepingUsable(nodes)
        guard !plausible.isEmpty else { return .noUsableNode }

        // Lapis-2: apa pun yang lolos lapis-1 tapi tetap ditolak sing-box.
        // Ini yang menyelamatkan verifikasi internet saat `nodes.json` user
        // masih berisi node rusak dari versi app lama — feed berubah terus,
        // jadi "sudah dibuang di parser" tidak boleh jadi jaminan.
        let kept = acceptedByCore(plausible, clashPort: clashPort, mixedPort: mixedPort, binary: binary)
        guard !kept.isEmpty else { return .noUsableNode }

        switch writeConfig(kept, clashPort: clashPort, mixedPort: mixedPort) {
        case .ok(let path): return .ok(path, kept)
        case .ioFailed: return .ioFailed
        }
    }

    /// Pisahkan node yang membuat `sing-box check` menolak dari yang aman.
    ///
    /// BUKAN sekadar menyerah pada config yang ditolak: `sing-box check`
    /// bersifat all-or-nothing, jadi satu outbound rusak mematikan UJI INTERNET
    /// untuk seluruh jendela sesi (ratusan node yang sebenarnya sehat).
    ///
    /// Bentuknya biner search: config ditolak → pecah dua → saring tiap
    /// separuh. Dengan `k` node rusak di antara `n` node, biayanya
    /// `O(k log n)` kali `sing-box check` (~50–200 ms per jalan pada 300
    /// outbound), dan itu HANYA terjadi saat confignya memang ditolak.
    private nonisolated static func acceptedByCore(
        _ nodes: [ProxyNode], clashPort: Int, mixedPort: Int, binary: String
    ) -> [ProxyNode] {
        guard !nodes.isEmpty else { return [] }
        switch writeAndValidate(nodes, clashPort: clashPort, mixedPort: mixedPort, binary: binary) {
        case .ok: return nodes
        case .invalid:
            guard nodes.count > 1 else { return [] }   // satu node ini penyebabnya
            let mid = nodes.count / 2
            return acceptedByCore(Array(nodes[..<mid]), clashPort: clashPort,
                                  mixedPort: mixedPort, binary: binary)
                 + acceptedByCore(Array(nodes[mid...]), clashPort: clashPort,
                                  mixedPort: mixedPort, binary: binary)
        case .ioFailed: return []
        }
    }

    /// Hasil `sing-box check` terhadap config probe.
    private enum ConfigCheck: @unchecked Sendable {
        case ok
        case invalid     // `sing-box check` menolak config
        case ioFailed
    }

    /// Tulis config probe lalu jalankan `sing-box check`.
    ///
    /// Path hasilnya sama setiap kali, jadi cukup satu file di temp.
    private nonisolated static func writeAndValidate(
        _ nodes: [ProxyNode], clashPort: Int, mixedPort: Int, binary: String
    ) -> ConfigCheck {
        switch writeConfig(nodes, clashPort: clashPort, mixedPort: mixedPort) {
        case .ioFailed: return .ioFailed
        case .ok(let path):
            return SingBoxConfigBuilder().validate(configPath: path, coreBinary: binary)
                ? .ok : .invalid
        }
    }

    private enum ConfigWrite: @unchecked Sendable {
        case ok(String)
        case ioFailed
    }

    private nonisolated static func writeConfig(
        _ nodes: [ProxyNode], clashPort: Int, mixedPort: Int
    ) -> ConfigWrite {
        let json = SingBoxConfigBuilder().probeConfigJSON(
            nodes: nodes, clashPort: clashPort, mixedPort: mixedPort)
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("freepn", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let cfg = dir.appendingPathComponent("probe.json")
        do { try json.write(to: cfg, atomically: true, encoding: .utf8) } catch { return .ioFailed }
        return .ok(cfg.path)
    }

    private func apiHealthy(port: Int) async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(port)/version") else { return false }
        var req = URLRequest(url: url)
        req.timeoutInterval = 2
        guard let (_, resp) = try? await URLSession.shared.data(for: req) else { return false }
        return (resp as? HTTPURLResponse)?.statusCode == 200
    }

    private func stopCore() {
        runner.stop()
        clashPort = 0
    }
}
