import Foundation
import os.log

/// JSON store generik di ~/Library/Application Support/FreePN/. Thread-safe via queue.
public final class JSONStore<T: Codable> {
    private let url: URL
    private let queue = DispatchQueue(label: "com.freepn.store", attributes: .concurrent)
    private let log = Logger(subsystem: "com.freepn.app", category: "store")

    public init(filename: String) {
        let dir = AppStorage.directory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.url = dir.appendingPathComponent(filename)
    }

    /// Baca dari disk lalu decode. SINKRON — memanggil thread apa pun akan
    /// memblokir sampai selesai. Untuk pemuatan yang besar (`nodes.json` bisa
    /// ber-MB) jangan panggil ini dari main actor; pakai `loadAsync`.
    public func load(defaultValue: T) -> T {
        var out = defaultValue
        queue.sync {
            out = Self.decode(at: url, log: log) ?? defaultValue
        }
        return out
    }

    /// Versi `async` yang TIDAK memblokir: I/O + decode JSON dijalankan di
    /// luar main actor, jadi `AppState.init` tidak lagi menanggung stall
    /// launch selama deserialisasi 16.000 node (D61).
    public func loadAsync(defaultValue: T) async -> T {
        let target = url
        let logger = log
        return await withCheckedContinuation { cont in
            queue.async {
                let value = Self.decode(at: target, log: logger) ?? defaultValue
                cont.resume(returning: value)
            }
        }
    }

    /// Decode satu file, dengan pemulihan dari `.bak`.
    ///
    /// Kegagalan decode SELALU berarti "user kehilangan datanya tanpa tahu":
    /// `load` lamaDiam-diam mengembalikan default, jadi satu field baru di
    /// model saja bisa membuat seluruh `nodes.json` tak terbaca dan app
    /// membuka dengan daftar server KOSONG. Sekarang: (1) dicatat ke log,
    /// (2) dicoba berkas cadangan `.bak` yang ditulis setiap kali `save`
    /// berhasil.
    private static func decode(at url: URL, log: Logger) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            log.error("Gagal decode \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            let backup = url.appendingPathExtension("bak")
            if let bdata = try? Data(contentsOf: backup),
               let restored = try? JSONDecoder().decode(T.self, from: bdata) {
                log.notice("Dipulihkan dari \(backup.lastPathComponent, privacy: .public)")
                return restored
            }
            return nil
        }
    }

    public func save(_ value: T) {
        queue.async(flags: .barrier) { Self.write(value, at: self.url, log: self.log) }
    }

    public func saveSync(_ value: T) {
        queue.sync(flags: .barrier) { Self.write(value, at: url, log: log) }
    }

    /// Tulis + SUDAH pertahankan salinan cadangan.
    ///
    /// Urutannya penting: `.bak` diisi DULUH dari data lama yang masih valid,
    /// baru data baru ditulis. Kalau proses mati di tengah penulisan, `.bak`
    /// masih berisi versi terakhir yang bisa dibaca.
    private static func write(_ value: T, at url: URL, log: Logger) {
        do {
            let data = try JSONEncoder().encode(value)
            let backup = url.appendingPathExtension("bak")
            if let old = try? Data(contentsOf: url) { try? old.write(to: backup, options: .atomic) }
            try data.write(to: url, options: .atomic)
        } catch {
            // Kegagalan menulis SELALU berarti pengaturan user tidak menempel
            // tanpa penjelasan (disk penuh, izin berubah). Dulu `try?` membuat
            // ini benar-benar senyap.
            log.error("Gagal menulis \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    public var fileURL: URL { url }
}
