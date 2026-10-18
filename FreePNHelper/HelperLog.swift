import Foundation
import Darwin

/// Log diagnosis helper.
///
/// PENTING (D61): log TIDAK lagi di `/tmp`.
///
/// `/tmp` world-writable, jadi proses lokal mana pun bisa membuat
/// `/tmp/freepn-helper.log` sebagai symlink ke file lain SEBELUM helper
/// menulis. Helper membuka `FileHandle(forWritingTo:)` lalu mengappend ke
/// target itu — sebagai ROOT. Itu primitive privilege-escalation lokal.
///
/// `/var/log` menutup serangan itu dari sisi direktori: miliknya root:wheel dengan
/// mode 755, jadi user biasa TIDAK BISA membuat file maupun symlink di sana.
/// Serangan symlink jadi mustahil secara struktural, bukan sekadar dicegat.
///
/// File-nya sendiri 0644 (bukan 0600) supaya app — yang jalan sebagai user
/// biasa — masih bisa membaca panel log. Itu trade-off yang disengaja:
/// kerahasiaan log diagnosa bukan perhatian utama di sini, sedangkan panel log yang
/// berhenti bekerja adalah kegagalan nyata yang dilihat user. Penyerang yang
/// bisa membaca log-mu juga sudah bisa membaca file miliknya sendiri.
public enum HelperLog {
    /// Lokasi log.
    public static let url = URL(fileURLWithPath: "/var/log/freepn-helper.log")
    private static let backupURL = URL(fileURLWithPath: "/var/log/freepn-helper.log.1")
    private static let lock = NSLock()

    /// Mode berkas: readable semua, writable hanya pemilik (root).
    private static let fileMode: mode_t = 0o644

    /// Batas ukuran log aktif sebelum diputar.
    public static let maxBytes = 1_048_576          // 1 MiB
    /// Seberapa sering cek ukuran (bukan tiap baris — `stat` itu mahal).
    private static let checkEvery = 64
    private static var writesSinceCheck = 0

    public static func log(_ msg: String) {
        lock.lock()
        defer { lock.unlock() }
        let line = "[\(timestamp.string(from: Date()))] \(msg)\n"
        guard let data = line.data(using: .utf8) else { return }

        // Pastikan mode benar SEBELUM menulis apa pun: kalau file sudah ada
        // dengan izin lain (mis. sisa versi lama), ini memperbaikinya.
        ensureLogFile()

        if writesSinceCheck >= checkEvery {
            writesSinceCheck = 0
            rotateIfNeeded(expectedGrowth: data.count)
        } else {
            writesSinceCheck += 1
        }

        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(data)
            try? h.close()
        } else {
            try? data.write(to: url, options: .atomic)
            ensureLogFile()
        }
    }

    /// Dipanggil dengan lock dipegang. Putar bila ukuran + pertumbuhan
    /// sudah melewati batas; sesi lama pindah ke `.1`, `.1` lama dibuang.
    private static func rotateIfNeeded(expectedGrowth: Int) {
        guard let size = currentSize(), size + expectedGrowth > maxBytes else { return }
        try? FileManager.default.removeItem(at: backupURL)
        try? FileManager.default.moveItem(at: url, to: backupURL)
        try? Data().write(to: url)
        ensureLogFile()
    }

    private static func currentSize() -> Int? {
        // Cukup satu `stat`; versi lama melakukan dua lookup (exists + attrs).
        var st = stat()
        guard stat(url.path, &st) == 0 else { return nil }
        return Int(st.st_size)
    }

    /// Buat berkas log dengan mode benar kalau belum ada.
    ///
    /// `O_NOFOLLOW` adalah lapisan kedua: kalau nama berkasnya ternyata
    /// symlink (mis. `/var/log` diganti mount, atau ada yang punya hak tulis
    /// di sana), open GAGAL alih-alih menulis ke target serangan. Lapisan
    /// pertama adalah `/var/log` sendiri yang root-only.
    private static func ensureLogFile() {
        let fd = open(url.path, O_WRONLY | O_CREAT | O_APPEND | O_NOFOLLOW, fileMode)
        if fd >= 0 { close(fd) }
    }

    /// Dipisah dari `log` supaya tidak membebani inisialisasi ICU pada
    /// setiap baris — `ISO8601DateFormatter` adalah salah satu objek
    /// Foundation termahal untuk dibuat (D61).
    private static let timestamp: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}