import Foundation

/// Snapshot log koneksi lengkap untuk ditampilkan di menu Sambung:
/// header sesi (dibuat app) + tail log helper (root, /var/log) +
/// tail log core sing-box. Murni Swift + path injeksi agar bisa di-unit-test.
///
/// PENTING (performa): `tail(of:maxLines:)` membaca dari AKHIR file saja.
/// Versi awal membaca seluruh file lalu `.suffix(maxLines)` — biayanya
/// O(ukuran file), jadi log 5 MB memakan ~78 ms per refresh padahal hanya
/// 300 baris yang dipakai. Sekarang biayanya O(maxLines), berapa pun ukuran file.
public enum ConnectionLog {
    /// Lokasi log. `/var/log`, bukan `/tmp` (D61).
    ///
    /// Di `/tmp` (world-writable) file ini bisa diganti symlink oleh proses
    /// lokal SEBELUM helper (yang root) membukanya — itu primitive LPE.
    /// `/var/log` milik root:wheel mode 755, jadi user biasa tidak bisa
    /// membuat file maupun symlink di sana: serangan terblokir secara
    /// struktural.
    ///
    /// Berkasnya 0644, jadi app yang berjalan sebagai user biasa masih bisa
    /// membaca panel log seperti sebelumnya.
    public static let helperLogPath = "/var/log/freepn-helper.log"
    public static let coreLogPath = "/var/log/freepn-core-stderr.log"

    /// Lokasi versi SEBELUM D61 (helper <= 1.3 masih menulis di sini).
    ///
    /// D69: bukan untuk dipakai selamanya — `/tmp` world-writable, dan
    /// menulis ke sana sebagai root adalah primitive LPE (lihat `HelperLog`).
    /// Ini HANYA supaya panel log tetap berguna saat helper lama belum
    /// diinstal ulang: tanpa ini user melihat "tak terbaca" padahal log-nya
    /// ada dan berisi puluhan KB, dan ia concludes helper rusak — padahal
    /// helper-nya sehat, cuma versinya lama.
    ///
    /// Membaca (bukan menulis) dari `/tmp` aman: file-nya milik root dan
    /// 0644, jadi user sudah bisa membacanya tanpa bantuan kita.
    public static let legacyHelperLogPath = "/tmp/freepn-helper.log"
    public static let legacyCoreLogPath = "/tmp/freepn-core-stderr.log"
    /// 200 baris, bukan 300: panel log kini selalu tampil dengan font lebih
    /// besar, dan baris ekstra hanya menambah pekerjaan layout tanpa menambah
    /// informasi yang berguna.
    public static let defaultMaxLines = 200

    /// Chunk awal untuk baca mundur. Cukup untuk 300 baris log normal
    /// (~190 byte/baris); digandakan sampai baris cukup atau file habis.
    static let initialChunkBytes = 64 * 1024

    /// Batas keras per iterasi agar file raksasa tidak terus dibaca penuh.
    ///
    /// 512 KB, bukan 4 MB. Chunk 4 MB hanya perlu kalau 200 baris log benaran
    /// butuh data sebesar itu; pada log normal satu iterasi 64 KB sudah cukup.
    /// Nilai ini adalah batas terburuk saat helper atau core sedang berteriak.
    static let maxChunkBytes = 512 * 1024

    /// Gabungan siap tampil. Header berisi info sesi dari app.
    ///
    /// D69: tiap sumber log punya LOKASI LAMA sebagai cadangan. Helper <= 1.3
    /// masih menulis ke `/tmp`, jadi kalau app diperbarui tanpa helper-nya,
    /// path baru tidak ada dan panel akan berbunyi "tak terbaca" — padahal
    /// log-nya ada. Fallback membuat panel tetap berguna, dan label path-nya
    /// sendiri membuat user (dan kita) langsung melihat bahwa helper perlu
    /// diinstal ulang.
    public static func snapshot(header: String,
                                helperPath: String = helperLogPath,
                                corePath: String = coreLogPath,
                                legacyHelperPath: String = legacyHelperLogPath,
                                legacyCorePath: String = legacyCoreLogPath,
                                maxLines: Int = defaultMaxLines) -> String {
        var parts: [String] = []
        if !header.isEmpty { parts.append(header) }

        let (helperOut, helperShown) = tailWithLegacyFallback(preferred: helperPath,
                                                              legacy: legacyHelperPath,
                                                              maxLines: maxLines)
        parts.append("===== \(L10n.string("log_helper")) (\(helperShown)) =====")
        parts.append(helperOut)
        parts.append("")

        let (coreOut, coreShown) = tailWithLegacyFallback(preferred: corePath,
                                                           legacy: legacyCorePath,
                                                           maxLines: maxLines)
        // D70: bagian core disembunyikan SAAT KOSONG, tidak dihapus permanen.
        //
        // Permintaan user: "log bawah hapus saja, kosong" — dan itu benar
        // untuk kondisi yang ia lihat: core yang start bersih tidak menulis apa
        // pun ke stderr, jadi panel menampilkan "(kosong)" dan bagian itu
        // hanya memboros ruang.
        //
        // Tapi log core bukan selalu kosong. Ia hanya SEPI saat sehat; begitu
        // ada masalah, isinya justru yang paling menentukan:
        //   ERROR[0086] connection: listen packet connection using tun...
        // Itu persis baris yang dibutuhkan saat connect gagal. Menghapus
        // bagiannya secara permanen berarti membuang satu-satunya bukti kenapa
        // core gagal — saat user paling butuh, panelnya justru paling sunyi.
        //
        // Jadi: sembunyikan saat kosong (permintaan terpenuhi, platter hilang),
        // tampilkan begitu ada isi (diagnostik utuh).
        if !Self.isBlank(coreOut) {
            parts.append("")
            parts.append("===== \(L10n.string("log_core")) (\(coreShown)) =====")
            parts.append(coreOut)
        }
        return parts.joined(separator: "\n")
    }

    /// Apakah isi log ini tidak membawa informasi apa pun?
    ///
    /// Dua keadaan yang harus dianggap sama: file kosong, dan file yang hanya
    /// berisi penanda "kosong"/"tak terbaca" yang sudah formatLocalized.
    nonisolated static func isBlank(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return true }
        return t == L10n.string("log_empty") || t == L10n.string("log_unreadable")
    }

    /// Tail dari `preferred`; kalau tidak ada, coba `legacy`.
    ///
    /// Mengembalikan teks + path yang benar-benar dipakai, supaya header
    /// tidak pernah berbohong tentang file mana yang dibaca.
    ///
    /// "Tidak ada" diartikan file tidak ADA. File yang ADA tapi kosong tetap
    /// dipakai — helper yang baru start memang menulis log kosong sesaat, dan
    /// mengembalikan "tak terbaca" di titik itu lebih membingungkan daripada
    /// "(kosong)".
    static func tailWithLegacyFallback(preferred: String, legacy: String,
                                       maxLines: Int) -> (text: String, path: String) {
        if FileManager.default.fileExists(atPath: preferred) {
            return (tail(of: preferred, maxLines: maxLines), preferred)
        }
        if FileManager.default.fileExists(atPath: legacy) {
            return (tail(of: legacy, maxLines: maxLines), legacy)
        }
        return (tail(of: preferred, maxLines: maxLines), preferred)
    }

    /// Baris-baris akhir file ("" bila tak terbaca) — ANSI dibersihkan.
    ///
    /// Hanya membaca potongan akhir file, bukan seluruhnya. Ukuran chunk
    /// digandakan bila potongan itu belum memuat cukup baris non-kosong.
    public static func tail(of path: String, maxLines: Int) -> String {
        guard maxLines > 0 else { return L10n.string("log_unreadable") }

        guard let lines = lastLines(of: path, maxLines: maxLines) else {
            return L10n.string("log_unreadable")
        }

        let out = lines.suffix(maxLines).joined(separator: "\n")
        if out.isEmpty { return L10n.string("log_empty") }
        return stripANSI(out)
    }

    /// `nil` bila file tidak bisa dibuka / tidak ada. Baris non-kosong saja,
    /// jadi pemanggil cukup `.suffix(maxLines)`.
    private static func lastLines(of path: String, maxLines: Int) -> [String]? {
        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else {
            return nil
        }
        defer { try? handle.close() }

        let fileSize = handle.seekToEndOfFile()
        guard fileSize > 0 else { return [] }

        // Perkiraan bytes yang dibutuhkan: maxLines baris, dilebihkan untuk
        // baris kosong yang dilewati, lalu dipotong agar tidak boros di awal.
        let desired = UInt64(maxLines * 256 + 4096)
        var chunk = min(desired, UInt64(initialChunkBytes))

        while true {
            // start == 0 berarti kita sudah membaca sampai awal file: selesai.
            let start = fileSize > chunk ? fileSize - chunk : 0
            guard let data = readChunk(handle: handle, from: start) else { return nil }
            guard let text = decodeChunk(data, dropFirstPartialLine: start > 0) else { return nil }

            let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
            if lines.count >= maxLines || start == 0 {
                return lines
            }
            // Chunk belum cukup baris -> baca lebih lebar (tetap bounded).
            chunk = min(chunk * 2, UInt64(maxChunkBytes))
            if chunk >= fileSize { chunk = fileSize }   // iterasi terakhir: dari byte 0
        }
    }

    /// Baca dari offset sampai akhir file tanpa memuat file penuh.
    private static func readChunk(handle: FileHandle, from offset: UInt64) -> Data? {
        do {
            try handle.seek(toOffset: offset)
            return try handle.readToEnd() ?? Data()
        } catch {
            return nil
        }
    }

    /// Chunk bisa mulai di tengah baris DAN memotong karakter UTF-8 multi-byte.
    /// Buang bytes sampai newline pertama sebelum decode agar hasil decode bersih.
    private static func decodeChunk(_ data: Data, dropFirstPartialLine: Bool) -> String? {
        if dropFirstPartialLine {
            // `dropFirst` menyalin seluruh sisa buffer; `index(after:)` tidak.
            // Untuk chunk 512 KB itu selisihnya nyata.
            guard let nl = data.firstIndex(of: 0x0A) else { return "" }
            return String(decoding: data[data.index(after: nl)...], as: UTF8.self)
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// Buang kode warna ANSI agar log core terbaca di UI.
    ///
    /// `NSRegularExpression` di-build SEKALI. `replacingOccurrences(options:
    /// .regularExpression)` adalah salah satu API Foundation termahal — ia
    /// mengompilasi polanya setiap pemanggilan, dan ini dipanggil dua kali
    /// per snapshot log, tiap 5 detik (D61).
    static func stripANSI(_ s: String) -> String {
        ansiRegex.stringByReplacingMatches(
            in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
    }

    private static let ansiRegex: NSRegularExpression = {
        // ESC [ 0-9 ; * m  (SGR — satu-satunya yang dipakai sing-box)
        try! NSRegularExpression(pattern: "\\u001B\\[[0-9;]*m")
    }()
}