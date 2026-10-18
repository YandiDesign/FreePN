import Foundation

/// Menjalankan sing-box (universal binary di Resources) + cleanup route/DNS.
/// STDOUT/STDERR dialihkan ke file (bukan Pipe tanpa pembaca — Pipe bisa deadlock
/// saat buffer penuh) sehingga penyebab mati tercatat dan bisa dibaca app.
final class CoreRunner {
    private var proc: Process?
    private let lock = NSLock()
    var lastError: String = ""
    var lastExitCode: Int32 = 0
    var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return proc?.isRunning == true
    }

    /// Log core juga pindah dari `/tmp` ke `/var/log` (D61). Di `/tmp`,
    /// proses lokal bisa membuat symlink ke file mana pun sebelum helper
    /// membuka `FileHandle` itu sebagai root — primitive LPE. Dengan
    /// `O_NOFOLLOW` + direktori root-only, symlink ditolak alih-alih ditulis.
    static let logPath = "/var/log/freepn-core-stderr.log"

    /// Buat/persiapkan log tanpa mengikuti symlink.
    private static func openLogForAppending() -> FileHandle? {
        // 0644 supaya app (user biasa) masih bisa menampilkan panel log;
        // yang dilindungi adalah ability MENULIS, dan itu sudah tertutup
        // oleh `/var/log` yang root-owned + `O_NOFOLLOW` di sini.
        let fd = open(logPath, O_WRONLY | O_CREAT | O_APPEND | O_NOFOLLOW, 0o644)
        guard fd >= 0 else { return nil }
        return FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    }

    var coreBinary: String {
        // Helper mencari sing-box di sebelah dirinya / Resources.
        var candidates: [String] = []
        let exeDir = (CommandLine.arguments.first as NSString?)?.deletingLastPathComponent ?? ""
        if !exeDir.isEmpty { candidates.append((exeDir as NSString).appendingPathComponent("sing-box")) }
        candidates += [
            Bundle.main.url(forResource: "sing-box", withExtension: nil)?.path,
            "/Library/PrivilegedHelperTools/sing-box",
            "/usr/local/bin/sing-box"
        ].compactMap { $0 }
        for c in candidates where FileManager.default.isExecutableFile(atPath: c) { return c }
        return "/Library/PrivilegedHelperTools/sing-box"
    }

    /// Simpan log sebelumnya sebagai `.1`, lalu mulai yang baru.
    private static func rotateLog() {
        let backup = logPath + ".1"
        try? FileManager.default.removeItem(atPath: backup)
        // `rename` menimpa secara atomik dan TIDAK mengikuti symlink.
        if rename(logPath, backup) != 0 {
            try? FileManager.default.removeItem(atPath: logPath)
        }
    }

    @discardableResult
    func start(configPath: String) -> Bool {
        // Ambil alih slot core di bawah lock (cepat), lalu LEPAS lock selama
        // operasi lambat. Versi lama menahan lock selama `stopLocked`
        // (terminate + tunggu sampai 3 detik) + `killLeftovers` (+0,5 detik)
        // — seluruhnya serial — sehingga `coreStatus`/`stop` yang datang
        // bersamaan ikut antre BERDETIK-DETIK dan melewati timeout XPC 3 detik
        // di app. App lalu memvonis "helper tidak merespons (mungkin crash)"
        // padahal helper sehat dan tidak pernah exit. Jendela itu terbuka di
        // SETIAP Sambung/Putus, jadi vonis palsunya muncul berulang.
        lock.lock()
        let old = proc
        proc = nil
        lock.unlock()
        if let p = old, p.isRunning { Self.terminateGracefully(p) }
        killLeftovers()
        guard FileManager.default.fileExists(atPath: configPath) else {
            lock.lock(); lastError = "config missing"; lock.unlock(); return false
        }
        let bin = coreBinary
        guard FileManager.default.isExecutableFile(atPath: bin) else {
            lock.lock(); lastError = "core binary missing: \(bin)"; lock.unlock(); return false
        }
        // Log diputar (bukan DITIMPA) tiap start: versi lama
        // `"".write(toFile:)` menghapus diagnostik yang justru sedang dibaca app di
        // panel log, dan dua penulis berebut file yang sama.
        Self.rotateLog()
        guard let logHandle = Self.openLogForAppending() else {
            lock.lock(); lastError = "cannot open log"; lock.unlock(); return false
        }
        logHandle.seekToEndOfFile()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: bin)
        p.arguments = ["run", "-c", configPath]
        p.standardOutput = logHandle
        p.standardError = logHandle
        p.terminationHandler = { [weak self] proc in
            guard let self = self else { try? logHandle.close(); return }
            self.lock.lock()
            self.lastExitCode = proc.terminationStatus
            self.lock.unlock()
            try? logHandle.close()
            HelperLog.log("core exited code=\(proc.terminationStatus)")
        }
        do {
            try p.run()
            lock.lock(); proc = p; lock.unlock()
            HelperLog.log("core spawned pid=\(p.processIdentifier)")
            return true
        } catch {
            lock.lock(); lastError = error.localizedDescription; lock.unlock()
            try? logHandle.close()
            return false
        }
    }

    /// Baris-baris akhir log core (untuk diagnosis via XPC).
    ///
    /// Baca mundur dari akhir file, bukan seluruhnya: log core di sesi panjang
    /// bisa berukuran besar dan pembacaan penuh membuat respons XPC melambat.
    func logTail(_ maxLines: Int = 6) -> String {
        guard maxLines > 0,
              let h = try? FileHandle(forReadingFrom: URL(fileURLWithPath: Self.logPath)) else {
            return lastError
        }
        defer { try? h.close() }

        let size = h.seekToEndOfFile()
        guard size > 0 else { return lastError }

        var chunk = min(UInt64(maxLines * 256 + 4096), UInt64(64 * 1024))
        while true {
            let start = size > chunk ? size - chunk : 0
            guard (try? h.seek(toOffset: start)) != nil,
                  let data = try? h.readToEnd() else { return lastError }
            // Buang baris pertama bila chunk mulai di tengah baris.
            var bytes = [UInt8](data)
            if start > 0 {
                guard let nl = bytes.firstIndex(of: 0x0A) else { return lastError }
                bytes.removeFirst(nl + 1)
            }
            guard let txt = String(bytes: bytes, encoding: .utf8) else { return lastError }
            let lines = txt.components(separatedBy: .newlines).filter { !$0.isEmpty }
            if lines.count >= maxLines || start == 0 {
                let tail = lines.suffix(maxLines).joined(separator: "\n")
                // Bersihkan kode warna ANSI agar terbaca di UI.
                return tail.replacingOccurrences(of: "\u{1B}\\[[0-9;]*m", with: "", options: .regularExpression)
            }
            chunk = min(chunk * 2, size)
        }
    }

    /// Bunuh sisa core milik HELPER dari percobaan gagal sebelumnya
    /// (port bentrok atau utun nyangkut = start berikutnya pasti mati).
    ///
    /// Sengaja mencocokkan BERDASARKAN config, bukan `-x sing-box`.
    ///
    /// `pkill -x sing-box` membunuh semua proses dengan nama itu di SELURUH
    /// mesin — termasuk sing-box milik tool VPN lain milik user (ClashX,
    /// Surge, mihomo, …). Akibatnya setiap kali VPN disambung ulang, core VPN
    /// milik tool lain ikut mati; dan karena sing-box memperlakukan SIGTERM
    /// sebagai shutdown rapi, ia keluar dengan **kode 0** setelah sempat
    /// mencetak "sing-box started" — sehingga tidak ada satu pun jejak yang
    /// terlihat sebagai kegagalan.
    ///
    /// Match per-config membuat helper hanya menyentuh core-nya sendiri.
    private func killLeftovers() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        p.arguments = ["-f", "freepn/config.json"]
        try? p.run(); p.waitUntilExit()
        if p.terminationStatus == 0 { Thread.sleep(forTimeInterval: 0.5) }
    }

    func stop() {
        lock.lock()
        let old = proc
        proc = nil
        lock.unlock()
        if let p = old, p.isRunning { Self.terminateGracefully(p) }
    }

    /// Hentikan core dengan anggun (SIGTERM, tunggu, lalu paksa).
    ///
    /// STATIC + tanpa lock, dan pemanggil WAJIB sudah mengosongkan slot
    /// `proc` sebelumnya (lihat `start`/`stop`): menunggu di sini sampai
    /// 3 detik, dan menunggu sambil memegang lock membuat `coreStatus`
    /// ikut macet melewati timeout XPC app.
    private static func terminateGracefully(_ p: Process) {
        p.terminate()
        // Beri waktu berhenti anggun, lalu paksa bila perlu.
        let deadline = Date().addingTimeInterval(3)
        while p.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
        if p.isRunning { p.interrupt() }
        // Cleanup: sing-box TUN auto_route umumnya memulihkan route/DNS sendiri.
        // Pastikan tidak ada config sementara tertinggal.
    }
}
