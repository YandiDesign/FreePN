import XCTest
@testable import FreePNApp

/// Sandbox penyimpanan untuk unit test.
///
/// Setiap test yang menyentuh `AppState` / `JSONStore` WAJIB memanggil
/// `isolateStorage()` lebih dulu. Tanpa itu, `persist()` akan menulis ke
/// `~/Library/Application Support/FreePN/` dan menimpa data asli user —
/// persis yang terjadi sekali: sebuah tes "hapus sumber" menimpa
/// `sources.json`, `nodes.json`, dan `favorites.json`.
enum TestSupport {
    private static let created = FolderList()

    /// Folder sementara yang dipakai test yang sedang berjalan.
    ///
    /// Dulu ini array statis biasa yang di-mutate dari setiap
    /// `isolateStorage()` dan dibersihkan SEMUA oleh teardown test mana pun.
    /// Kalau XCTest menjalankan test secara paralel, teardown test A menghapus
    /// folder milik test B — lalu test B menulis ke folder yang sudah tidak ada
    /// (atau, lebih buruk, ke folder milik test C). Sekarang tiap test
    /// memegang foldernya sendiri lewat `addTeardownBlock` yang menutup
    /// closure-nya, dan daftar global dilindungi lock hanya untuk keperluan
    /// membersihkan sisa bila ada test yang crash sebelum teardown jalan.
    private final class FolderList: @unchecked Sendable {
        private let lock = NSLock()
        private var dirs: [URL] = []

        func add(_ dir: URL) {
            lock.lock(); dirs.append(dir); lock.unlock()
        }
        func drain() -> [URL] {
            lock.lock(); let d = dirs; dirs = []; lock.unlock(); return d
        }
    }

    /// Arahkan semua penyimpanan app ke folder sementara yang bersih.
    /// Kembalikan folder itu supaya pemanggil bisa membersihkannya sendiri.
    @discardableResult
    static func isolateStorage(file: StaticString = #filePath,
                               line: UInt = #line) -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FreePNTest-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        AppStorage.overrideDirectory = dir
        created.add(dir)
        return dir
    }

    /// Bersihkan SEMUA folder sementara yang masih tercatat.
    ///
    /// Dipakai hanya sebagai jaring pengaman; jalur normal adalah teardown
    /// per-test yang menutup folder miliknya sendiri.
    static func restoreStorage() {
        AppStorage.overrideDirectory = nil
        for dir in created.drain() { try? FileManager.default.removeItem(at: dir) }
    }

    /// Pulihkan override ke nilai SEBELUM test ini mulai.
    ///
    /// Penting: `overrideDirectory` adalah global. Kalau teardown hanya
    /// menghapus foldernya tapi TIDAK mengembalikan pointer-nya, test berikutnya
    /// diam-diam masih menulis ke folder test sebelumnya — dan test yang butuh
    /// folder produksi ikut terpengaruh.
    static func restoreOverride(to previous: URL?) {
        AppStorage.overrideDirectory = previous
    }
}

extension XCTestCase {
    /// Dipakai di `setUp` test yang menyentuh penyimpanan.
    ///
    /// Teardown menutup HANYA folder milik test ini — bukan folder test lain
    /// yang mungkin sedang berjalan bersamaan (D61) — dan mengembalikan
    /// pointer override ke nilai sebelumnya.
    func isolateStorage() {
        let previous = AppStorage.overrideDirectory
        let dir = TestSupport.isolateStorage()
        addTeardownBlock {
            TestSupport.restoreOverride(to: previous)
            try? FileManager.default.removeItem(at: dir)
        }
    }
}