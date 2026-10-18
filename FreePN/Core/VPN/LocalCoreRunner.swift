import Foundation

/// Menjalankan sing-box langsung sebagai proses anak aplikasi (tanpa helper root).
/// Untuk pemakaian pribadi: cukup untuk mencoba config; inbound TUN butuh root,
/// jadi bila gagal akan ada pesan jelas yang menyarankan install-helper.sh.
public final class LocalCoreRunner {
    private var proc: Process?
    private var pending: Process?
    private var pendingErr: Pipe?
    private var pendingOut: Pipe?
    public var lastError: String = ""
    public var isRunning: Bool { proc?.isRunning == true }
    /// PID core yang sedang jalan — dipakai `TerminalSessionManager` untuk
    /// menulis pidfile, supaya proses yatim bisa dibersihkan saat app dibuka
    /// lagi tanpa ikut menyentil core milik helper yang juga bernama sing-box.
    public var processIdentifier: pid_t { proc?.processIdentifier ?? -1 }

    /// Lifespan dua pipe anak, dibaca di background SEJAK spawn.
    ///
    /// Dua masalah yang dulu ada di sini:
    /// 1. `p.standardOutput = Pipe()` yang TIDAK PERNAH dibaca. Kalau core
    ///    menulis lebih dari ~64 KB ke stdout, anak tertahan di `write()` dan
    ///    `isRunning` tetap `true` selamanya — `finish()` lalu menyatakan
    ///    BERHASIL untuk core yang sebenarnya macet. `CoreRunner` (versi
    ///    helper) sudah mengalirkan ke BERKAS justru untuk menghindari ini;
    ///    kelas ini mewarisi pola yang salah (D61).
    /// 2. Pipe baru dibaca di `finish()`, yaitu SETELAH `settleDelay`. Kalau
    ///    buffer sudah penuh dalam masa itu, anak sudah tersendat.
    private var drainTasks: [Task<Void, Never>] = []
    private var stdoutBuffer = Data()
    private var stderrBuffer = Data()
    private let bufferLock = NSLock()

    public init() {}

    /// Versi async dari `start`. WAJIB dipakai dari @MainActor: `Thread.sleep`
    /// memblokir thread pemanggil, dan di UI itu berarti layar beku 2 detik
    /// setiap kali core dinyalakan (mis. saat probe internet jalan).
    ///
    /// Ingat `start` (sinkron) TIDAK boleh dipanggil dari main actor — itu
    /// bug yang pernah membuat UI beku 2 detik tiap fallback ke core lokal.
    @discardableResult
    public func startAsync(configPath: String, binary: String) async -> Bool {
        guard spawn(configPath: configPath, binary: binary) else { return false }
        try? await Task.sleep(nanoseconds: UInt64(settleDelay * 1_000_000_000))
        return finish()
    }

    /// D91: 2,0 dtk -> 0,25 dtk.
    ///
    /// Angka ini diturunkan dari "kira-kira cukup buat sing-box parse config".
    /// Yang sebenarnya diukur: dengan 300 outbound, Clash API siap dalam
    /// **0,07 dtk** setelah `run`. Wait 2 detik itu bukan safety margin — itu
    /// 2 detik mati per sesi probe, dan daftar 20.000 node butuh 37–73 sesi,
    /// jadi hampir 2 menit utuh terbuang hanya untuk tidur.
    ///
    /// Keamanannya tetap utuh: `InternetProbe.startCore` sudah melakukan poll
    /// `apiHealthy()` sampai 10 dtk setelah `startAsync` selesai, jadi
    /// kesiapan API yang sebenarnya diperiksa dengan benar di sana.
    private var settleDelay: TimeInterval = 0.25

    /// Luncurkan proses, TANPA menunggu. Handle disimpan untuk `finish()`.
    private func spawn(configPath: String, binary: String) -> Bool {
        stop()
        lastError = ""
        guard FileManager.default.isExecutableFile(atPath: binary) else {
            lastError = "core binary missing"; return false
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: binary)
        p.arguments = ["run", "-c", configPath]
        let errPipe = Pipe()
        let outPipe = Pipe()
        p.standardError = errPipe
        p.standardOutput = outPipe
        do {
            try p.run()
        } catch {
            lastError = error.localizedDescription
            return false
        }
        pending = p
        pendingErr = errPipe
        pendingOut = outPipe
        startDraining(errPipe: errPipe, outPipe: outPipe)
        return true
    }

    /// Baca kedua pipe sampai habis, langsung sejak spawn.
    ///
    /// Buffer dibatasi (256 KB) supaya core yang berulang tidak menghabiskan
    /// memori; yang lebih dari itu tidak pernah dibaca untuk pesan error yang
    /// hanya mengambil 3 baris terakhir.
    private func startDraining(errPipe: Pipe, outPipe: Pipe) {
        bufferLock.lock(); stdoutBuffer = Data(); stderrBuffer = Data(); bufferLock.unlock()
        for pipe in [errPipe, outPipe] {
            let isErr = pipe === errPipe
            drainTasks.append(Task.detached(priority: .utility) { [weak self] in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                guard let self else { return }
                self.bufferLock.lock()
                if isErr {
                    self.stderrBuffer.append(data)
                    if self.stderrBuffer.count > Self.bufferCap {
                        self.stderrBuffer.removeFirst(self.stderrBuffer.count - Self.bufferCap)
                    }
                } else {
                    self.stdoutBuffer.append(data)
                    if self.stdoutBuffer.count > Self.bufferCap {
                        self.stdoutBuffer.removeFirst(self.stdoutBuffer.count - Self.bufferCap)
                    }
                }
                self.bufferLock.unlock()
            })
        }
    }

    private static let bufferCap = 256 * 1024

    /// Proses masih hidup setelah masa tenggang → jadikan core aktif.
    private func finish() -> Bool {
        guard let p = pending else { return false }
        pending = nil; pendingErr = nil; pendingOut = nil
        if !p.isRunning {
            let msg = currentErrorText()
            var lines = msg.components(separatedBy: .newlines).filter { !$0.isEmpty }
            // Inti exited/mati sebelum sempat hidup stabil. Bedakan "keluar
            // sendiri" dari "dibunuh sinyal": untuk kasus kedua, stderr hampir
            // selalu kosong — karena itu pesan stderr saja membuat user
            // mengira core-nya selesai start padahal tidak, dan restart
            // otomatis tidak akan pernah memperbaiki apa pun.
            if p.terminationReason == .uncaughtSignal {
                lines.append("core killed by signal \(p.terminationStatus)"
                             + " (\(signalName(p.terminationStatus)))")
            } else {
                lines.append("core exited (code \(p.terminationStatus))")
            }
            lastError = lines.suffix(4).joined(separator: "\n")
            if lastError.isEmpty { lastError = "core exited immediately" }
            return false
        }
        proc = p
        return true
    }

    private func signalName(_ number: Int32) -> String {
        switch number {
        case SIGTERM: return "SIGTERM"
        case SIGKILL: return "SIGKILL"
        case SIGINT: return "SIGINT"
        case SIGSEGV: return "SIGSEGV"
        case SIGABRT: return "SIGABRT"
        default: return "signal \(number)"
        }
    }

    /// Isi stderr + stdout yang sudah terkumpul, di-UTF-8-kan.
    private func currentErrorText() -> String {
        bufferLock.lock()
        let data = stderrBuffer.isEmpty ? stdoutBuffer : stderrBuffer
        bufferLock.unlock()
        return String(data: data, encoding: .utf8) ?? ""
    }

    public func stop() {
        if let p = pending, p.isRunning { p.terminate() }
        pending = nil; pendingErr = nil; pendingOut = nil
        if let p = proc, p.isRunning { p.terminate() }
        proc = nil
        // Task drain dibiarkan selesai sendiri: membatalkannya di tengah
        // `readDataToEndOfFile` bisa meninggalkan fd terbuka. Pipe akan
        // ke-EOF begitu prosesnya mati.
        drainTasks.removeAll()
    }
}