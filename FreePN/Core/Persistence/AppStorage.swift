import Foundation

/// Lokasi penyimpanan data aplikasi — satu pintu untuk SEMUA yang menyentuh
/// disk, supaya bisa dialihkan.
///
/// Kenapa ada enum ini: `JSONStore` dan cache feed dulunya menghitung
/// sendiri-sendiri `~/Library/Application Support/FreePN/`. Akibatnya unit test
/// yang membuat `AppState` ikut membaca — dan lewat `persist()` menulis —
/// **data asli user**. Ada tes yang menghapus satu sumber, dan `sources.json`,
/// `nodes.json`, serta `favorites.json` milik user tertimpa data uji coba.
///
/// `overrideDirectory` membuat test bisa menunjuk ke folder sementara, dan
/// membiarkan jalur produksi persis seperti sebelumnya.
public enum AppStorage {
    /// Kalau diisi, SEMUA penyimpanan app memakai folder ini.
    /// Hanya untuk test. `nil` di produksi.
    ///
    /// Sengaja `static var` biasa (bukan `nonisolated(unsafe)`, yang butuh
    /// Swift 5.10): project ini dibangun dengan Xcode 14.3.1 / Swift 5.8.
    public static var overrideDirectory: URL?

    /// Folder yang dipakai `JSONStore`.
    public static var directory: URL {
        if let overrideDirectory { return overrideDirectory }
        // BUKAN `.first!`: Application Support praktis selalu ada di desktop,
        // tapi di lingkungan terbatas (helper tanpa GUI, sandbox, home yang
        // tidak bisa ditulis) `urls(for:)` bisa kosong — dan force unwrap di
        // sini berarti CRASH di pemakaian store PERTAMA, termasuk `AppState.init`
        // saat app baru dibuka. Turun bertahap ke cache lalu temp lebih baik
        // daripada crash (D61).
        if let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                                in: .userDomainMask).first {
            return base.appendingPathComponent(AppConstants.supportDirName, isDirectory: true)
        }
        if let cache = FileManager.default.urls(for: .cachesDirectory,
                                               in: .userDomainMask).first {
            return cache.appendingPathComponent(AppConstants.supportDirName, isDirectory: true)
        }
        return FileManager.default.temporaryDirectory
            .appendingPathComponent(AppConstants.supportDirName, isDirectory: true)
    }

    /// Folder cache feed yang DIHAPUS app ini (D67).
    ///
    /// Tidak lagi dipakai untuk menulis apa pun — feed selalu diambil dari
    /// jaringan — tapi tetap ada di sini karena perlu dihapus sekali saat app
    /// start. Versi lama menumpuk 400+ berkas dari sumber yang sudah dihapus
    /// (±190 MB) dan tidak pernah membersihkannya.
    public static var legacyCacheDirectory: URL {
        directory.appendingPathComponent("subcache", isDirectory: true)
    }

    /// Buang seluruh cache feed lama. Aman dipanggil berulang kali: folder yang
    /// sudah tidak ada keluar langsung.
    ///
    /// Sengaja TIDAK menyentuh `directory` sendiri — di dalamnya ada
    /// `sources.json`, `nodes.json`, dan `favorites.json` milik user.
    ///
    /// URL dipakai sebagai parameter, bukan dibaca dari `directory` di dalam
    /// fungsi: pemanggil menyalinnya di actor utama, lalu penghapusan berjalan
    /// di luar sana tanpa membaca `overrideDirectory` (yang `static var` dan
    /// bisa diganti test kapan saja).
    public static func purgeLegacySubscriptionCache(at dir: URL) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir),
              isDir.boolValue else { return }
        try? FileManager.default.removeItem(at: dir)
    }

    /// Aman dipakai di bawah test runner: kalau `overrideDirectory` belum
    /// di-set, test sedekat ini bisa menimpa data user. Lebih baik gagal
    /// keras daripada menghapus daftar langganan orang.
    public static func assertIsolated(_ context: StaticString = #function) {
        precondition(overrideDirectory != nil,
                     """
                     AppStorage.overrideDirectory belum di-set — unit test ini \
                     akan membaca dan menulis data FreePN milik user asli. \
                     Set overrideDirectory ke folder sementara lebih dulu \
                     (lihat TestSupport.makeTemporaryStorage()).
                     """)
    }
}