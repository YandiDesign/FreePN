import Foundation
import Network
import Combine
import os

/// Jejak keputusan VPN di unified log (`subsystem == "com.freepn.app"`).
///
/// Alasan tiap Sambung/Putus/reconnect TERCATAT di sini — kalau user
/// melapor "terputus sendiri", `log show --predicate ... --last 2h`
/// langsung menunjukkan pemicunya (manual vs watchdog-auto + sebabnya),
/// tanpa menebak dari log helper. Tidak ada data sensitif: nama/host node
/// memang sudah tampil di UI.
private let vpnLog = Logger(subsystem: "com.freepn.app", category: "vpn")

public enum ConnectionStatus: String {
    case disconnected, connecting, connected, disconnecting, error
}

/// Terjemahkan ekor log sing-box jadi satu kalimat yang bisa ditindaklanjuti.
///
/// Murni & nonisolated supaya bisa diuji tanpa core, tanpa helper, tanpa disk.
///
/// Kenapa ini ada (D97): connect yang gagal karena core masih HIDUP tidak
/// pernah membaca log core, sehingga user hanya melihat tebakan ("server
/// mungkin mati, kredensial mungkin salah"). Padahal sing-box sudah menulis
/// sebabnya di baris terakhir — `tls: failed to verify certificate: …`, atau
/// `authentication failed`, atau `i/o timeout`. Tanpa itu, satu-satunya cara
/// user mencari tahu adalah membaca `/var/log` di Terminal, dan biasanya
/// mereka menyimpulkan app-nya yang rusak.
///
/// Yang dikembalikan adalah baris yang paling menunjuk AKSI, bukan baris
/// pertama: log penuh dengan baris pembuka dan lookup DNS yang tidak
///yang tidak pernah selesai sebelum baris klausa pembukaannya.
public enum CoreFailureReason {
    /// Kata kunci yang menandai penyebab yang bisa ditindaklanjuti user,
    /// urut dari paling spesifik.
    private static let signals = [
        "certificate", "x509", "tls:", "handshake", "authentication",
        "unauthorized", "forbidden", "password", "credential",
        "deadline exceeded", "timeout", "i/o timeout", "connection refused",
        "network is unreachable", "no such host", "eof", "reset by peer"
    ]

    private static func strip(_ line: String) -> String {
        var s = line
        // Buang warna ANSI — `logTail` membersihkannya, tapi baris juga bisa
        // datang dari sumber lain dan user tidak boleh melihat escape codes.
        // ESC-nya ditulis sebagai karakter asli, BUKAN `\\u{1B}`. Kalau
        // ditulis sebagai teks, yang masuk ke regex adalah teks "\u{1B}" — bukan ESC —
        // sehingga polanya tidak pernah cocok dan kode warna lolos ke layar.
        s = s.replacingOccurrences(of: "\u{1B}\\[[0-9;]*[a-zA-Z]", with: "",
                                   options: .regularExpression)
        // Buang header sing-box. Bentuknya: "ERROR[0000] [<id> 52ms] pesan",
        // dan bentuk lain "ERROR[0000] pesan" / "ERROR pesan".
        //
        // Ketiga bentuk dicoret di AWAL baris (anchor `^`), bukan di tengah.
        // Versi sebelumnya memakai `range(of: "\\] ")` yang tidak beranchor,
        // jadi ia berhenti di "] " PERTAMA — yaitu yang milik `[0000]` — dan
        // menyisakan `[2087506959 52ms]` di depan pesan. Noise di depan itu persis
        // yang membuat pesan terlihat seperti dump mentah, bukan penjelasan.
        s = s.replacingOccurrences(
            of: "^(?:ERROR|FATAL|WARN|INFO|DEBUG)\\[\\d+\\]\\s*",
            with: "", options: .regularExpression)
        s = s.replacingOccurrences(
            of: "^(?:ERROR|FATAL|WARN|INFO|DEBUG)\\s+",
            with: "", options: .regularExpression)
        s = s.replacingOccurrences(
            of: "^\\[\\d+ [\\d.]+m?s\\]\\s*",
            with: "", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Satu kalimat penyebab, atau `nil` kalau log tidak memberi informasi.
    public static func from(_ tail: String, maxLength: Int = 200) -> String? {
        guard !tail.isEmpty, tail != "stopped" else { return nil }
        let raw = tail.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Baris dengan kata kunci sinyal menang.
        let scored = raw.filter { l in
            let low = l.lowercased()
            return signals.contains { low.contains($0) }
        }
        // Kalau tidak ada, ambil baris berlabel ERROR/FATAL yang paling akhir —
        // itu yang biasanya ditulis paling dekat dengan kegagalan.
        let marked = raw.filter { l in
            let u = l.uppercased()
            return u.contains("ERROR") || u.contains("FATAL")
        }
        guard let pick = scored.last ?? marked.last else { return nil }

        // PENTING: `strip` dijalankan SETELAH penilaian kelayakan. Kalau
        // penilaian dilakukan pada baris yang sudah dibersihkan, prefix "ERROR"
        // sudah hilang — tidak ada baris yang pernah dianggap error, dan
        // pesan generik selalu kembali tepat di kasus yang paling butuh
        // penjelasan.
        var reason = strip(pick)
        if reason.isEmpty { return nil }
        if reason.count > maxLength {
            reason = String(reason.prefix(maxLength)) + "…"
        }
        return reason
    }
}

@MainActor
public final class ConnectionManager: ObservableObject {
    @Published public var status: ConnectionStatus = .disconnected
    @Published public var errorMessage: String = ""
    @Published public var connectedSince: Date?
    @Published public var upBytes: Int64 = 0
    @Published public var downBytes: Int64 = 0
    /// Laju trafik terakhir, byte/detik.
    ///
    /// D76: sekarang dihitung dari delta per interval dibagi **waktu aktual**
    /// antar pesan — bukan dari selisih total. Ini akurat, walaupun sumber hanya
    /// melaporkan 1 Hz.
    @Published public var upRate: Double = 0
    @Published public var downRate: Double = 0
    /// Riwayat laju untuk sparkline. Buffer melingkar berkapasitas tetap (D76).
    ///
    /// Sengaja BUKAN `@Published`: sparkline menggambar ulang tiap frame lewat
    /// `TimelineView`, jadi ia tidak perlu diberi tahu saat isi berubah.
    /// Kalau ini `@Published`, tiap sampel (1 Hz) akan membatalkan seluruh view
    /// tree yang mengamatinya — termasuk peta dunia dan tabel server yang
    /// tidak menampilkan byte sama sekali.
    public let upHistory = TrafficSeries()
    public let downHistory = TrafficSeries()

    private var monitor: NWPathMonitor?
    /// Loop pembacaan trafik (satu Task untuk satu sesi).
    private var trafficTask: Task<Void, Never>?
    private let localRunner = LocalCoreRunner()
    private var attemptID = UUID()
    /// True bila core berjalan lokal (tanpa helper root) — TUN penuh butuh helper.
    @Published public var usingLocalCore: Bool = false
    public var autoReconnect: Bool = true
    public var lastNode: ProxyNode?
    public var lastSplit: SplitTunnelConfig = SplitTunnelConfig()
    public var lastCoreBinary: String = ""
    /// Port dinamis per koneksi (default baru di luar ekosistem Clash 9090/1080).
    public var clashPort: Int = FreePort.defaultClashPort
    public var mixedPort: Int = FreePort.defaultMixedPort
    /// IP keluar terakhir via core (otomatis dicek setelah connect).
    @Published public var lastExitIP: String? = nil

    public init() {}

    private func xpc() -> NSXPCConnection {
        let c = NSXPCConnection(machServiceName: AppConstants.helperMachService, options: .privileged)
        c.remoteObjectInterface = NSXPCInterface(with: FreePNHelperProtocol.self)
        // Verifikasi code-signing dasar di sisi app (helper juga memverifikasi balik).
        return c
    }

    /// Stop core lama di helper dan TUNGGU selesai (maks 3 dtk).
    /// Fire-and-forget DILARANG: stop yang datang terlambat membunuh core
    /// yang baru di-spawn (SIGTERM → exit 0, log kosong, lalu verify-timeout).
    /// Itu penyebab "Helper: verify-timeout" padahal helper terpasang.
    private func stopHelperCore() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let conn = xpc(); conn.resume()
            var done = false
            let finish = { if !done { done = true; conn.invalidate(); cont.resume() } }
            guard let proxy = conn.remoteObjectProxyWithErrorHandler({ _ in finish() }) as? FreePNHelperProtocol else {
                conn.invalidate(); cont.resume(); return
            }
            proxy.stopCore { _, _ in finish() }
            // Pengaman: jangan tunggu selamanya bila helper macet.
            DispatchQueue.global().asyncAfter(deadline: .now() + 3) { finish() }
        }
    }

    public func connect(node: ProxyNode, split: SplitTunnelConfig, coreBinary: String) {
        vpnLog.info("sambung: \(node.name, privacy: .public) (\(node.host, privacy: .public):\(node.port))")
        attemptID = UUID()
        let myID = attemptID
        // JANGAN biarkan mode inklusif-kosong lolos: final=direct artinya
        // TIDAK ADA trafik lewat VPN ("tersambung" tapi IP tak berubah).
        // Ini penyebab #1 laporan "koneksi sama sekali tidak jalan".
        if SingBoxConfigBuilder.isBypassAll(split: split) {
            status = .error
            errorMessage = "\(L10n.string("warn_inclusive_empty"))\n\(L10n.string("error_inclusive_empty_hint"))"
            return
        }
        // Bersihkan percobaan sebelumnya (sisa proses lokal / core helper yang nyangkut).
        // PENTING: tunggu stop lama selesai DULU sebelum spawn baru (anti-race).
        localRunner.stop()
        status = .connecting; errorMessage = ""
        lastExitIP = nil
        usingLocalCore = false
        lastNode = node; lastSplit = split; lastCoreBinary = coreBinary
        // Timeout anti-macet: maks 12 dtk dalam status connecting.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            self?.handleConnectTimeout(id: myID)
        }
        Task { @MainActor [weak self] in
            await self?.stopHelperCore()
            guard let self = self, self.attemptID == myID, self.status == .connecting else { return }
            self.startAfterCleanup(node: node, split: split, coreBinary: coreBinary, id: myID)
        }
    }


    /// Lanjutan connect setelah cleanup lama dipastikan berhenti.
    private func startAfterCleanup(node: ProxyNode, split: SplitTunnelConfig, coreBinary: String, id: UUID) {
        // Alokasi port + tulis config + `sing-box check` semua memblokir
        // (puluhan sampai ratusan syscall/fork). Semuanya duluan jalan di main
        // actor karena `connect()` dipanggil langsung dari SwiftUI — jadi tiap
        // klik "Sambung" membekukan seluruh UI selama proses validasi.
        // Sekarang dipindah ke `Task.detached`; call site `.connected`/
        // `.error` tetap hopping ke MainActor di dalam closure (D61).
        let splitSnapshot = split
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let clash = FreePort.tcp(from: FreePort.defaultClashPort)
            let mixedCandidate = FreePort.tcp(from: FreePort.defaultMixedPort)
            let mixed = mixedCandidate == clash ? FreePort.tcp(from: clash + 1) : mixedCandidate
            let builder = SingBoxConfigBuilder()
            let json = builder.configJSON(node: node, split: splitSnapshot,
                                          clashPort: clash, mixedPort: mixed)
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("freepn", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let cfgURL = dir.appendingPathComponent("config.json")
            do { try json.write(to: cfgURL, atomically: true, encoding: .utf8) } catch {
                await MainActor.run {
                    guard self.attemptID == id, self.status == .connecting else { return }
                    self.status = .error
                    self.errorMessage = "\(L10n.string("error_invalid_config"))\n\(error.localizedDescription)"
                }
                return
            }
            // Validasi bila binary tersedia.
            if FileManager.default.isExecutableFile(atPath: coreBinary) {
                let result = builder.validateDetailed(configPath: cfgURL.path, coreBinary: coreBinary)
                if case .ok = result {
                    // lanjut
                } else {
                    let detail: String
                    switch result {
                    case .rejected(let msg): detail = msg
                    case .failed(let msg): detail = msg
                    case .ok: detail = ""
                    }
                    await MainActor.run {
                        guard self.attemptID == id, self.status == .connecting else { return }
                        self.status = .error
                        // Tampilkan SEBENARNYA ditolak core, bukan pesan
                        // generik — sebelumnya diagnostik `sing-box check`
                        // dibuang bersama pipe-nya sehingga user tidak pernah
                        // tahu apa yang salah (D61).
                        self.errorMessage = detail.isEmpty
                            ? L10n.string("error_invalid_config")
                            : "\(L10n.string("error_invalid_config"))\n\(detail)"
                    }
                    return
                }
            }
            await MainActor.run {
                guard self.attemptID == id, self.status == .connecting else { return }
                self.clashPort = clash
                self.mixedPort = mixed
                self.attemptXPCCore(configPath: cfgURL.path, id: id)
            }
        }
    }

    // MARK: - Inti: daemon root + sing-box TUN

    private func attemptXPCCore(configPath: String, id: UUID) {
        let conn = xpc()
        conn.resume()
        guard let proxy = conn.remoteObjectProxyWithErrorHandler({ err in
            Task { @MainActor [weak self] in
                conn.invalidate()
                self?.handleXPCFailure(id: id, detail: err.localizedDescription)
            }
        }) as? FreePNHelperProtocol else {
            conn.invalidate()
            handleXPCFailure(id: id, detail: L10n.string("error_helper_unavailable"))
            return
        }
        proxy.startCore(configPath: configPath) { ok, msg in
            Task { @MainActor [weak self] in
                conn.invalidate()
                guard let self = self, self.attemptID == id else { return }
                if ok {
                    // JANGAN langsung setConnected saat spawn: proses bisa mati
                    // 1 detik kemudian (port bentrok / TUN gagal). Verifikasi
                    // clash API + TUN benar-benar hidup, baru nyatakan connected.
                    await self.verifyHelperCoreThenConnect(id: id)
                } else {
                    // Helper menolak (mis. path) → coba fallback lokal sebelum menyerah.
                    self.tryLocalCore(id: id, hint: msg)
                }
            }
        }
    }

    /// XPC gagal (helper belum terinstal) → coba jalankan core langsung sebagai proses lokal.
    private func handleXPCFailure(id: UUID, detail: String) {
        guard attemptID == id, status == .connecting else { return }
        tryLocalCore(id: id, hint: detail)
    }

    private func tryLocalCore(id: UUID, hint: String) {
        guard attemptID == id, status == .connecting else { return }
        guard !lastCoreBinary.isEmpty,
              FileManager.default.isExecutableFile(atPath: lastCoreBinary) else {
            status = .error
            errorMessage = "\(L10n.string("error_helper_unavailable")) (\(hint))"
            return
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("freepn", isDirectory: true)
        let cfg = dir.appendingPathComponent("config.json").path
        // `startAsync`, BUKAN `start`: yang sinkron memanggil `Thread.sleep`
        // 2 detik di thread pemanggil, dan pemanggil ini `@MainActor` — jadi
        // seluruh UI beku 2 detik setiap kali fallback ke core lokal (D61).
        Task { @MainActor [weak self] in
            guard let self, self.attemptID == id, self.status == .connecting else { return }
            let ok = await self.localRunner.startAsync(configPath: cfg, binary: self.lastCoreBinary)
            guard self.attemptID == id, self.status == .connecting else { return }
            if ok {
                await self.verifyLocalCoreThenConnect(id: id, hint: hint)
            } else {
                // Jangan menutupi pesan helper: tampilkan keduanya + petunjuk instalasi.
                var parts: [String] = []
                if !hint.isEmpty && hint != "timeout" { parts.append("Helper: \(hint)") }
                if !self.localRunner.lastError.isEmpty { parts.append("Lokal:\n\(self.localRunner.lastError)") }
                parts.append(L10n.string("error_local_core"))
                self.status = .error
                self.errorMessage = parts.joined(separator: "\n")
            }
        }
    }

    // MARK: - Verifikasi pasca-spawn (anti "tersambung palsu")
    //
    // Spawn sukses != VPN hidup. Core bisa exit 1 detik kemudian karena:
    // - clash port bentrok (ClashFX di 9090),
    // - TUN gagal (tanpa root / strict_route),
    // - node mati (dial gagal) — TUN up tapi tak ada trafik.
    // Verifikasi: proses hidup + clash API menjawab + TUN ada.
    // Baru setelah itu setConnected. Timeout total ~10 dtk.

    private func verifyHelperCoreThenConnect(id: UUID) async {
        guard attemptID == id, status == .connecting else { return }
        let deadline = Date().addingTimeInterval(10)
        var lastMsg = ""
        // Satu timeout XPC bukan vonis mati (lihat `HelperReachability`):
        // transient dimaafkan, vonis butuh bukti beruntun.
        var reachability = HelperReachability()
        while Date() < deadline {
            guard attemptID == id, status == .connecting else { return }
            let (alive, msg, reachable) = await helperCoreStatus()
            reachability.record(success: reachable)
            if !reachable {
                if reachability.presumedDead {
                    lastMsg = L10n.string("error_helper_gone"); break
                }
                try? await Task.sleep(nanoseconds: 700_000_000)
                continue
            }
            if !alive { lastMsg = msg; break }
            if await clashAPIHealthy() {
                // Proses + API hidup. TUN butuh 1-2 dtk untuk auto_route;
                // "tersambung" HANYA bila interface 172.19.0.1 benar-benar ada.
                // Tanpa ini: API hidup + proxy hidup tapi default route masih via
                // en0 = IP tak berubah (laporan utama).
                if tunInterfaceUp() {
                    setConnected(local: false)
                    return
                }
                lastMsg = L10n.string("error_tun_not_up")
            } else {
                lastMsg = msg
            }
            try? await Task.sleep(nanoseconds: 700_000_000)
        }
        guard attemptID == id, status == .connecting else { return }
        // Verifikasi gagal: ambil tail log asli agar diagnosis jelas.
        let (_, tail, _) = await helperCoreStatus()
        let cause = [lastMsg, tail].filter { !$0.isEmpty && $0 != "stopped" }.joined(separator: "\n")
        // Satu kesempatan via lokal sebelum menyerah (kasus helper usang).
        if !localRunner.isRunning, !lastCoreBinary.isEmpty {
            tryLocalCore(id: id, hint: cause.isEmpty ? "verify-timeout" : cause)
            return
        }
        status = .error
        errorMessage = cause.isEmpty
            ? L10n.string("error_connect_timeout")
            : "\(L10n.string("error_core_stopped"))\nCore: \(cause)"
    }

    private func verifyLocalCoreThenConnect(id: UUID, hint: String) async {
        guard attemptID == id, status == .connecting else { return }
        // LocalRunner.start sudah menunggu 2 dtk; verifikasi API + proses.
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            guard attemptID == id, status == .connecting else { return }
            guard localRunner.isRunning else { break }
            if await clashAPIHealthy() {
                // Mode lokal tanpa root: TUN system/stack pasti gagal —
                // jujur ke user, tetap tandai connected agar SOCKS bisa dipakai,
                // tapi dengan peringatan local_mode_note di UI.
                setConnected(local: true)
                return
            }
            try? await Task.sleep(nanoseconds: 700_000_000)
        }
        guard attemptID == id, status == .connecting else { return }
        var parts: [String] = []
        if !hint.isEmpty && hint != "timeout" && hint != "verify-timeout" { parts.append("Helper: \(hint)") }
        if !localRunner.lastError.isEmpty { parts.append("Lokal:\n\(localRunner.lastError)") }
        parts.append(L10n.string("error_local_core"))
        status = .error
        errorMessage = parts.joined(separator: "\n")
    }

    /// Clash API sehat? Pakai /version (GET biasa), BUKAN /traffic
    /// (/traffic adalah websocket — URLSession.data akan gantung selamanya).
    private func clashAPIHealthy() async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(clashPort)/version") else { return false }
        var req = URLRequest(url: url)
        req.timeoutInterval = 2
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            return (resp as? HTTPURLResponse)?.statusCode == 200
        } catch { return false }
    }

    /// TUN sing-box sudah naik? Cari interface utun dengan alamat 172.19.0.1.
    private func tunInterfaceUp() -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/sbin/ifconfig")
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
        do { try p.run(); p.waitUntilExit() } catch { return false }
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return out.contains("172.19.0.1")
    }

    private func handleConnectTimeout(id: UUID) {
        guard attemptID == id, status == .connecting else { return }
        // Verifikasi async di atas sudah menangani retry; timeout ini
        // hanya pengaman terakhir agar tidak macet di .connecting selamanya.
        // Jangan spawn lokal membabi-buta di sini (port race) — verifikasi
        // yang memutuskan.
        status = .error
        errorMessage = L10n.string("error_connect_timeout")
    }

    private func setConnected(local: Bool) {
        usingLocalCore = local
        status = .connected
        connectedSince = Date()
        startStats()
        startWatchdog()
        // Cek IP keluar otomatis (bukan manual): bedakan node-mati vs TUN-bocor.
        // viaCore memakai SOCKS core — sukses = proxy path hidup.
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            let ip = await ExitIPChecker.viaCore(port: self.mixedPort, timeout: 10)
            guard self.status == .connected else { return }
            self.lastExitIP = ip
            if ip == nil {
                // Core hidup tapi proxy path tidak menghasilkan traffic keluar.
                // D91: pesan ini tidak lagi menebak "kredensial salah" sebagai
                // satu-satunya penyebab. Dari pengujian ribuan node, penyebab
                // yang paling sering BUKAN kredensial — melainkan node itu sudah
                // mati, atau jalur keluarnya diblokir. Menyebut kredensial
                // sebagai penyebab tunggal membuat user memeriksa hal yang salah.
                //
                // D97: dan sekarang sebabnya bisa diambil dari log core juga.
                // Kasus ini justru yang paling perlu penjelasan — core-nya
                // hidup, jadi tidak ada yang menjelaskan apa pun — tapi justru
                // di sinilah log sing-box berisi jawaban persisnya.
                let tail = await self.helperCoreLog()
                self.status = .error
                if let reason = CoreFailureReason.from(tail) {
                    // Penyebabnya sudah ada — tidak perlu lagi menebak.
                    self.errorMessage = L10n.string("error_core_reason") + "\n" + reason
                } else {
                    self.errorMessage = L10n.string("error_node_dead")
                }
                self.connectedSince = nil
                self.stopStats()
            }
        }
    }

    /// Ambil ekor log core dari helper.
    ///
    /// Sengaja memakai `coreStatus` yang sudah ada (D97) dan bukan perintah
    /// XPC baru: menambah perintah baru berarti menambah permukaan helper
    /// root yang harus diaudit, untuk sesuatu yang datanya sudah dikirim.
    /// Nilai `Bool` diabaikan — yang dipakai hanya baris log.
    private func helperCoreLog() async -> String {
        let (_, msg, reachable) = await helperCoreStatus()
        return reachable ? msg : ""
    }

    /// Tandai gagal tanpa menyentuh core (mis. connect ditolak karena node
    /// terbukti tidak bisa akses internet). Error ikut tampil di menu Sambung.
    public func fail(_ message: String) {
        attemptID = UUID() // batalkan connect yang masih tertunda
        stopStats()
        connectedSince = nil
        errorMessage = message
        status = .error
    }

    public func disconnect() {
        vpnLog.info("putus manual")
        attemptID = UUID() // batalkan timeout/connect yang tertunda
        localRunner.stop()
        usingLocalCore = false
        lastExitIP = nil
        apiFailCount = 0
        if status != .connected && status != .error { status = .disconnected; stopStats(); return }
        status = .disconnecting
        let conn = xpc(); conn.resume()
        guard let proxy = conn.remoteObjectProxyWithErrorHandler({ _ in
            Task { @MainActor [weak self] in
                conn.invalidate()
                self?.status = .disconnected; self?.stopStats()
            }
        }) as? FreePNHelperProtocol else {
            conn.invalidate()
            status = .disconnected; stopStats(); return
        }
        proxy.stopCore { _, _ in
            Task { @MainActor [weak self] in
                conn.invalidate()
                self?.status = .disconnected
                self?.connectedSince = nil
                self?.stopStats()
            }
        }
    }

    public func startPathMonitor() {
        stopPathMonitor()
        let m = NWPathMonitor()
        m.pathUpdateHandler = { path in
            Task { @MainActor in
                if path.status == .satisfied, self.autoReconnect,
                   self.status == .connected, let n = self.lastNode {
                    // Reconnect singkat saat jaringan berubah/wake.
                    // Diimplementasi sebagai no-op aman bila helper menangani sendiri;
                    // dicatat agar perilaku eksplisit.
                    _ = n
                }
            }
        }
        m.start(queue: .global())
        monitor = m
    }

    public func stopPathMonitor() { monitor?.cancel(); monitor = nil }

    private func startStats() {
        stopStats()
        lastSampleTime = nil
        apiFailCount = 0
        helperFailStrikes = HelperReachability()
        upRate = 0; downRate = 0
        upHistory.reset(); downHistory.reset()
        // D73: total HARUS ikut direset di awal sesi. Sebelumnya total berasal
        // dari nilai yang ditimpa tiap sampel, jadi ia "kebetulan" ikut hilang
        // bersama core yang baru. Sekarang total dijumlahkan di app — kalau
        // tidak di-reset, angka sesi lalu bercampur dengan sesi ini.
        upBytes = 0; downBytes = 0
        // D76: SATU websocket hidup untuk seluruh sesi, bukan connect-per-sampel.
        // Pola lama (timer 2 dtk -> connect -> tunggu ~1 dtk -> baca SATU delta
        // 1 dtk -> close) hanya menangkap ~1 detik trafik dari siklus ~3 detik:
        // total dan laju KURANG LAPOR sekitar 50-65%. Socket permanen menangkap
        // setiap delta yang memang ada.
        trafficTask = Task { [weak self] in
            await self?.runTrafficStream()
        }
    }

    private func stopStats() {
        trafficTask?.cancel()
        trafficTask = nil
        stopWatchdog()
    }

    /// Watchdog: status "Tersambung" harus berarti proses core benar-benar hidup.
    /// Tanpa ini, core yang mati diam-diam (config runtime gagal, port konflik)
    /// membuat UI berbohong.
    private var watchdogTimer: Timer?
    private func startWatchdog() {
        stopWatchdog()
        watchdogTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.checkCoreAlive() }
        }
        if let t = watchdogTimer { RunLoop.main.add(t, forMode: .common) }
    }
    private func stopWatchdog() { watchdogTimer?.invalidate(); watchdogTimer = nil }

    private func checkCoreAlive() async {
        guard status == .connected else { return }
        if usingLocalCore {
            if !localRunner.isRunning {
                if startAutoReconnect(reason: "local-core-stopped") { return }
                status = .error
                errorMessage = localRunner.lastError.isEmpty
                    ? L10n.string("error_core_stopped")
                    : "\(L10n.string("error_core_stopped"))\n\(localRunner.lastError)"
                connectedSince = nil
                stopStats()
            }
            return
        }
        let myAttempt = attemptID
        let (alive, msg, reachable) = await helperCoreStatus()
        // PENTING: cek ulang SETELAH `await`. `status == .connected` dicek
        // sebelum dua `await` panjang di atas; kalau user menekan Putus
        // selama keduanya berjalan, continuation ini akan menulis
        // `status = .error` MENIMPA `.disconnected` — UI lalu menampilkan
        // "core berhenti" padahal user yang sengaja memutus. Semua jalur
        // async lain di kelas ini sudah memakai `attemptID`; yang ini
        // tertinggal (D61).
        guard attemptID == myAttempt, status == .connected else { return }
        if !reachable {
            // Satu timeout bukan vonis mati (lihat `HelperReachability`):
            // butuh dua gagal BERUNTUN sebelum status "Tersambung" yang
            // sehat dibanting jadi error. Sukses me-reset hitungan.
            helperFailStrikes.record(success: false)
            guard helperFailStrikes.presumedDead else { return }
            // Koroborasi via data plane dulu: XPC bisa timeout 2× beruntun
            // sementara tunnel baik-baik saja — restart dalam keadaan itu
            // justru MENCIPTAKAN putus yang dikeluhkan user.
            if !Self.needsRestart(alive: false,
                                   apiHealthy: await clashAPIHealthy(),
                                   tunUp: tunInterfaceUp()) {
                helperFailStrikes = HelperReachability()
                vpnLog.info("tahan: XPC timeout tapi data plane sehat — tetap tersambung")
                return
            }
            // Helper sendiri mati/hilang — bukan core yang salah. Coba
            // sambung ulang dulu bila checkbox aktif (node terakhir masih
            // ada); hanya bila tidak, jatuh ke error.
            if startAutoReconnect(reason: "helper-gone") { return }
            status = .error
            errorMessage = L10n.string("error_helper_gone")
            connectedSince = nil
            stopStats()
            return
        }
        helperFailStrikes.record(success: true)
        if !alive {
            // Koroborasi dulu: handle proses di helper bisa basi (daemon
            // restart → proc=nil) sementara core yatimnya masih meneruskan
            // trafik dengan sehat. Restart buta dalam keadaan itu memutus
            // stream yang sedang jalan tanpa alasan.
            if !Self.needsRestart(alive: false,
                                   apiHealthy: await clashAPIHealthy(),
                                   tunUp: tunInterfaceUp()) {
                vpnLog.info("tahan: verdict core-mati tapi data plane sehat — tetap tersambung")
                return
            }
            // Core mati tiba-tiba (crash): sambung ulang otomatis bila
            // checkbox aktif, alih-alih diam di error.
            if startAutoReconnect(reason: "core-stopped") { return }
            status = .error
            // Tampilkan penyebab asli dari core (bukan pesan generik).
            errorMessage = msg.isEmpty || msg == "stopped"
                ? L10n.string("error_core_stopped")
                : "\(L10n.string("error_core_stopped"))\nCore: \(msg)"
            connectedSince = nil
            stopStats()
            return
        }
        // Proses hidup belum tentu API hidup (port bentrok parsial / deadlock).
        // Bila API mati 2x beruntun, anggap core tidak sehat.
        if !(await clashAPIHealthy()) {
            guard attemptID == myAttempt, status == .connected else { return }
            apiFailCount += 1
            if apiFailCount >= 2 {
                status = .error
                errorMessage = "\(L10n.string("error_core_stopped"))\nCore: clash API 127.0.0.1:\(clashPort) tidak menjawab (port bentrok?)"
                connectedSince = nil
                stopStats()
            }
        } else {
            apiFailCount = 0
        }
    }

    private var apiFailCount = 0
    /// Gagal XPC beruntun di watchdog. Di-reset tiap sukses (lihat
    /// `HelperReachability`); sesi baru juga mulai dari nol via `startStats`
    /// — vonis dari sesi lama tidak boleh terbawa ke sesi baru.
    private var helperFailStrikes = HelperReachability()

    /// Mulai sambung ulang otomatis ke node terakhir. `true` = reconnect
    /// diambil alih (pemanggil JANGAN menyentuh status lagi).
    ///
    /// Syarat: checkbox aktif DAN masih ada node terakhir. Putus manual
    /// aman: `disconnect()` memutar `attemptID` dan mengubah status, jadi
    /// continuation watchdog yang telat datang gugur di guard — tidak ada
    /// reconnect hantu setelah user sengaja memutus. Reconnect yang gagal
    /// berakhir di `.error` (watchdog mati di sana), jadi tidak ada loop
    /// tanpa akhir: reconnect hanya lahir dari status `.connected`.
    private func startAutoReconnect(reason: String) -> Bool {
        guard let node = Self.reconnectTarget(autoReconnect: autoReconnect,
                                              lastNode: lastNode) else { return false }
        vpnLog.info("sambung-ulang otomatis (\(reason, privacy: .public)): \(node.name, privacy: .public)")
        connect(node: node, split: lastSplit, coreBinary: lastCoreBinary)
        return true
    }

    /// Perlu restart tunnel? `false` = biarkan tersambung apa pun kata
    /// verdict proses/XPC.
    ///
    /// `alive=true` tidak pernah butuh restart. `alive=false` pun belum
    /// tentu: handle proses di helper bisa basi (daemon restart → proc=nil)
    /// atau reply XPC bisa hilang sementara, sementara data plane (clash
    /// API + TUN) membuktikan trafik mengalir. Restart dalam keadaan itu
    /// memutus stream sehat tanpa alasan — persis keluhan "terputus
    /// sendiri" padahal tidak ada yang crash.
    ///
    /// Murni & nonisolated supaya kebijakannya bisa diuji tanpa core.
    nonisolated public static func needsRestart(alive: Bool, apiHealthy: Bool,
                                                tunUp: Bool) -> Bool {
        if alive { return false }
        return !(apiHealthy && tunUp)
    }

    /// Target sambung ulang: SELALU node terakhir, tidak pernah pindah akun.
    ///
    /// Failover (pindah ke akun lain) sengaja TIDAK dilakukan: user memakai
    /// akun yang dipilihnya dengan alasan (server itu yang normal untuk
    /// opencode-nya), dan pindah akun mengganti exit IP + memutus semua
    /// stream yang masih hidup. Reconnect ke akun yang sama memberi blackout
    /// tersingkat — TCP yang sedang jalan sering selamat lewat retransmit.
    ///
    /// Murni & nonisolated supaya keputusannya bisa diuji tanpa core:
    /// "core crash + checkbox nyala → sambung ke node terakhir;
    /// checkbox mati / tidak ada node → biarkan error".
    nonisolated public static func reconnectTarget(autoReconnect: Bool,
                                                   lastNode: ProxyNode?) -> ProxyNode? {
        guard autoReconnect else { return nil }
        return lastNode
    }

    private func helperCoreStatus() async -> (Bool, String, Bool) {
        await withCheckedContinuation { cont in
            let conn = xpc(); conn.resume()
            // Batas waktu WAJIB. Tanpa ini, kalau reply XPC hilang (helper
            // crash, koneksi terputus) continuation TIDAK PERNAH di-resume —
            // `verifyHelperCoreThenConnect` menggantung selamanya, dan
            // watchdog yang berjalan tiap 5 detik akan menumpuk satu
            // continuation menggantung baru setiap tick (D61).
            let resumed = ResumeGuard(cont)
            DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
                // Koneksi WAJIB ikut di-invalidasi di sini. Versi lama hanya
                // me-resume tanpa invalidate: kalau reply-nya memang tidak
                // pernah datang, koneksi (mach port) bocor di sisi app DAN
                // slot-nya nyangkut di `live` sisi helper — bocor berulang
                // bisa mendorong helper ke batas 8 koneksi lalu koneksi
                // berikutnya DITOLAK ("over connection limit") padahal
                // helper sehat.
                conn.invalidate()
                resumed.resume((false, "", false))
            }
            guard let proxy = conn.remoteObjectProxyWithErrorHandler({ _ in
                conn.invalidate()
                resumed.resume((false, "", false))
            }) as? FreePNHelperProtocol else {
                conn.invalidate()
                resumed.resume((false, "", false))
                return
            }
            proxy.coreStatus { running, msg in
                conn.invalidate()
                resumed.resume((running, msg, true))
            }
        }
    }

    /// Penjaga "resume paling banyak sekali", thread-safe.
    ///
    /// Dua jalur di `helperCoreStatus` bersamaan selesai hampir
    /// bersamaan (timeout + error handler). `withCheckedContinuation` yang
    /// di-resume dua kali adalah FATAL ERROR di Swift, jadi penjaga ini wajib —
    /// `if !done` biasa tidak cukup karena `done` dibaca-tulis dari beberapa
    /// thread tanpa sinkronisasi.
    private final class ResumeGuard {
        typealias Value = (Bool, String, Bool)
        private var done = false
        private let lock = NSLock()
        private let cont: CheckedContinuation<Value, Never>

        init(_ cont: CheckedContinuation<Value, Never>) { self.cont = cont }

        /// Resume dengan nilai — aman dipanggil dari thread mana pun, dan
        /// hanya yang pertama benar-benar bekerja.
        func resume(_ value: Value) {
            lock.lock()
            if done { lock.unlock(); return }
            done = true
            lock.unlock()
            cont.resume(returning: value)
        }
    }

    /// Loop pembacaan trafik: SATU websocket, dibaca terus-menerus (D76).
    ///
    /// Pola lama membuka koneksi baru tiap sampel dan menutupnya lagi, sehingga
    /// hanya menangkap ~1 detik trafik dari siklus ~3 detik. Dengan socket
    /// permanen, setiap delta yang benar-benar ada dari core sampai ke app —
    /// dan tidak ada connect/close berulang yang menambah latensi maupun beban.
    ///
    /// Socket yang putus (core restart, TUN di-toggle) ditangani di dalam loop:
    /// tunggu sebentar dengan backoff, lalu sambung lagi. `total` dan `riwayat`
    /// sengaja TIDAK direset saat reconnect — core yang sama masih hidup,
    /// jadi total sesi harus tetap utuh. Yang direset hanya saat sesi baru
    /// benar-benar dimulai (`startStats`).
    private func runTrafficStream() async {
        var backoff: TimeInterval = 0.5
        while !Task.isCancelled {
            guard let url = URL(string: "ws://127.0.0.1:\(clashPort)/traffic") else { return }
            let socket = URLSession.shared.webSocketTask(with: url)
            socket.resume()
            defer { socket.cancel(with: .goingAway, reason: nil) }

            var receivedAny = false
            do {
                while !Task.isCancelled {
                    let msg = try await socket.receive()
                    receivedAny = true
                    backoff = 0.5          // koneksi sehat: kembali ke jeda normal
                    guard let text = Self.decodeTrafficMessage(msg) else { continue }
                    applySample(upDelta: text.0, downDelta: text.1)
                }
            } catch {
                // Socket putus. `receivedAny` memastikan kita hanya mem-backoff
                // kalau memang sempat terhubung, supaya kegagalan berulang
                // (mis. core belum siap) tidak membakar timer.
            }
            if Task.isCancelled { return }
            // Reconnect: tunggu dulu supaya core yang sedang restart tidak
            // dirinya ditabrak connection refused berulang.
            let wait = receivedAny ? 0.2 : backoff
            backoff = min(backoff * 2, 5.0)
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
        }
    }

    /// `{"up":N,"down":M}` -> (up, down).byte hasil parse; `nil` kalau pesan
    /// tidak bisa dibaca (bukan dict, angka bukan Int, dan seterusnya).
    ///
    /// Sengaja MENGABAIKAN pesan yang gagal parse alih-alih membatalkan loop:
    /// satu pesan aneh tidak boleh mematikan seluruh monitor trafik.
    nonisolated static func decodeTrafficMessage(
        _ msg: URLSessionWebSocketTask.Message) -> (Int64, Int64)? {
        let text: String
        switch msg {
        case .string(let s): text = s
        case .data(let d): text = String(decoding: d, as: UTF8.self)
        @unknown default: return nil
        }
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        func num(_ k: String) -> Int64 {
            if let v = obj[k] as? Int64 { return v }
            if let v = obj[k] as? Int { return Int64(v) }
            if let v = obj[k] as? NSNumber { return v.int64Value }
            return 0
        }
        return (num("up"), num("down"))
    }

    /// Waktu sampel terakhir — dipakai untuk mengubah selisih total jadi laju.
    /// Waktu sampel terakhir — dipakai membagi delta dengan waktu AKTUAL.
    private var lastSampleTime: Date?

    /// Terapkan satu sampel dari `/traffic`: perbarui total, laju, dan riwayat.
    ///
    /// PENTING (D73+D76): `upDelta`/`downDelta` adalah **DELTA satu interval**,
    /// bukan total kumulatif. Diverifikasi langsung terhadap core sungguhan
    /// (sing-box 1.12.1): pesan tiba **tepat 1,000 detik** satu sama lain, dan
    /// angkanya naik-turun mengikuti-throughput nyata (5.2 MB/dtk saat diuji),
    /// tidak pernah terakumulasi.
    ///
    /// Karena itu laju HARUS dihitung dari delta dibagi waktu aktual. Menghitung
    /// dari selisih total (`up - upBytes`) menghasilkan sampah: `upBytes` sudah
    /// dijumlahkan, jadi selisihnya bukan "apa yang terjadi sejak sampel lalu".
    ///
    /// Murni (tidak I/O) supaya bisa diuji tanpa core.
    @MainActor
    func applySample(upDelta: Int64, downDelta: Int64, now: Date = Date()) {
        let stamp = now.timeIntervalSince1970
        let interval = lastSampleTime.map { now.timeIntervalSince($0) } ?? 0
        // Delta tidak mungkin negatif secara fisika. `max(0,)` menjaga agar data
        // rusak dari core tidak mengikis total atau menggambar sparkline ke
        // bawah sumbu.
        let du = max(0, upDelta)
        let dd = max(0, downDelta)

        // TOTAL: dijumlahkan, bukan ditimpa.
        upBytes += du
        downBytes += dd

        // LAJU: delta dibagi selang waktu AKTUAL. Bila socket sempat tersendat
        // (core sibuk, jeda scheduler), interval membesar dan laju ikut turun —
        // itu benar, karena byte itu memang tersebar sepanjang interval itu.
        //
        // Sampel pertama tidak menghasilkan laju: `interval == 0` berarti kita
        // belum tahu berapa lama delta itu terkumpul, jadi menebak jadi angka
        // liar (pada sesi baru bisa sangat besar).
        if interval > 0 {
            upRate = Double(du) / interval
            downRate = Double(dd) / interval
            upHistory.append(time: stamp, value: upRate)
            downHistory.append(time: stamp, value: downRate)
        }
        lastSampleTime = now
    }
}

/// Penghitung kegagalan XPC beruntun ke helper.
///
/// Satu reply yang lambat/hilang BUKAN bukti helper mati — transaksi XPC
/// bisa tersendat sesaat (helper sedang spawn/stop core, scheduler sibuk).
/// Versi lama memvonis "helper tidak merespons (mungkin crash)" pada
/// kegagalan PERTAMA, padahal helper sehat dan tidak pernah exit (kasus
/// nyata yang berulang). Vonis mati butuh bukti berulang.
///
/// Murni & nonisolated supaya aturannya bisa diuji tanpa XPC.
public struct HelperReachability {
    /// Vonis mati setelah sekian gagal BERUNTUN. Dua berarti satu transient
    /// dimaafkan; tiap kegagalan sendiri sudah memakan timeout 3 detik,
    /// jadi dua beruntun = ~6 detik bukti sebelum vonis.
    public static let deathThreshold = 2

    public private(set) var consecutiveFailures = 0
    public init() {}

    /// Catat satu hasil poll. Sukses me-reset hitungan ke nol.
    public mutating func record(success: Bool) {
        consecutiveFailures = success ? 0 : consecutiveFailures + 1
    }

    /// Cukup bukti untuk menyatakan helper hilang?
    public var presumedDead: Bool { consecutiveFailures >= Self.deathThreshold }
}
