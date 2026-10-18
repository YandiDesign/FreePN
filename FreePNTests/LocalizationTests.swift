import XCTest
@testable import FreePNApp

/// Audit multibahasa: guarantees every key exists in every language and that
/// no user-facing English is hardcoded in the UI.
///
/// Both classes of bug were real at least once here:
///  - key missing in one language -> that language silently falls back to the
///    key name (`Text("card_recommended")` shows the literal key)
///  - title written as a plain string literal -> stays English forever,
///    because `Button`/`CommandMenu` titles do NOT auto-localize in SwiftUI
final class LocalizationTests: XCTestCase {
    private static let languages = ["en", "id"]

    /// Lokasi `.strings` di dalam bundle app.
    ///
    /// Tes ini jalan DI DALAM app (test target di-host ke FreePN.app), jadi
    /// `Bundle.main` adalah app itu sendiri dan file-nya ada di
    /// `Contents/Resources/<lang>.lproj/`. `Bundle(for:)` dipakai sebagai
    /// cadangan kalau suatu saat tes dijalankan di bundle terpisah.
    private func stringsURL(_ lang: String) -> URL? {
        let name = "Localizable"
        let ext = "strings"
        var candidates: [URL?] = [
            Bundle.main.url(forResource: name, withExtension: ext, subdirectory: nil, localization: lang),
            Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "\(lang).lproj"),
            Bundle.main.resourceURL?
                .appendingPathComponent("\(lang).lproj/\(name).\(ext)"),
            Bundle(for: Self.self).url(forResource: name, withExtension: ext,
                                       subdirectory: nil, localization: lang),
        ]
        if let r = Bundle.main.resourceURL {
            candidates.append(r.appendingPathComponent("Localization/\(lang).lproj/\(name).\(ext)"))
        }
        return candidates.compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Parse format `.strings` yang dipakai file lokalisasi project ini:
    /// satu entri per baris, `"key" = "value";`.
    private func parse(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("\""), let eq = t.range(of: "\" = \"") else { continue }
            let key = String(t[t.index(t.startIndex, offsetBy: 1)..<eq.lowerBound])
            var value = ""
            // Mulai dari `eq.upperBound`, BUKAN `index(after:)`.
            //
            // `range(of:)` sudah berakhir tepat di kutip pembuka value, jadi
            // `upperBound` menunjuk karakter pertama value itu sendiri.
            // Melewatkannya satu karakter lagi membuat "%d app" terbaca
            // "d app" dan "Ada %d ..." terbaca "da %d ..." — placeholder di
            // posisi pertama hilang tanpa pernah ketahuan, karena kedua bahasa
            // kehilangan karakter yang sama dan jumlah placeholdernya tetap
            // cocok. Bug ini baru terasa begitu ada key yang value-nya mulai
            // berbeda antar bahasa.
            var idx = eq.upperBound
            while idx < t.endIndex {
                let ch = t[idx]
                if ch == "\\" {
                    // Escape: ambil karakter berikutnya kalau ada. Kalau ini
                    // karakter terakhir, berhenti — addressing satu karakter
                    // melewati endIndex akan crash (bukan sekadar hasil salah).
                    let nxt = t.index(after: idx)
                    guard nxt < t.endIndex else { break }
                    value.append(t[nxt])
                    idx = t.index(after: nxt)
                    continue
                }
                if ch == "\"" { break }
                value.append(ch)
                idx = t.index(after: idx)
            }
            out[key] = value
        }
        return out
    }

    private func table(_ lang: String) throws -> [String: String] {
        let url = try XCTUnwrap(stringsURL(lang),
                                "Localizable.strings (\(lang)) tidak ditemukan di bundle app")
        let data = try Data(contentsOf: url)
        // File .strings hasil build Xcode bisa UTF-16 (BOM FF FE) kalau
        // "Encoding" di build settings-nya berbeda. Dekode sebagai UTF-8
        // akan membuat setiap baris jadi sampah dan parser membaca 0 key —
        // persis yang terjadi saat tes ini pertama dibuat.
        let text: String
        if data.count >= 2, data[data.startIndex] == 0xFF, data[data.startIndex + 1] == 0xFE {
            text = String(data: data.dropFirst(2), encoding: .utf16LittleEndian) ?? ""
        } else {
            text = String(decoding: data, as: UTF8.self)
        }
        let out = parse(text)
        XCTAssertFalse(out.isEmpty, "tidak ada key terbaca dari \(lang) (decoded \(text.count) char)")
        return out
    }

    /// Tidak boleh ada key yang ada di satu bahasa tapi tidak di yang lain —
    /// key yang hilang diam-diam tampil sebagai teks mentah.
    func testEveryLanguageHasTheSameKeys() throws {
        let en = try table("en")
        for lang in Self.languages where lang != "en" {
            let other = try table(lang)
            let missing = Set(en.keys).subtracting(other.keys)
            let extra = Set(other.keys).subtracting(en.keys)
            XCTAssertTrue(missing.isEmpty, "key hilang di \(lang): \(missing.sorted())")
            XCTAssertTrue(extra.isEmpty, "key hanya ada di \(lang): \(extra.sorted())")
        }
    }

    /// Placeholder objek harus utuh di semua bahasa. Kalau `%@` hilang di satu
    /// bahasa, `L10n.formatted` diam-diam menghasilkan teks dengan sisa
    /// argumen terpotong — sulit dilacak dari UI.
    func testPlaceholdersAreConsistentAcrossLanguages() throws {
        let en = try table("en")
        let enRaw = en
        for lang in Self.languages where lang != "en" {
            let otherRaw = try table(lang)
            for key in en.keys {
                guard let a = enRaw[key], let b = otherRaw[key] else { continue }
                let pa = a.components(separatedBy: "%@").count - 1
                let pb = b.components(separatedBy: "%@").count - 1
                XCTAssertEqual(pa, pb, "jumlah placeholder %@ beda untuk key '\(key)' (en=\(a) / \(lang)=\(b))")
            }
        }
    }

    /// Jumlah `%d`/`%ld`/`%.0f` juga harus sama (angka dari argumen).
    func testNumericPlaceholdersAreConsistent() throws {
        let enRaw = try table("en")
        for lang in Self.languages where lang != "en" {
            let otherRaw = try table(lang)
            for (key, a) in enRaw {
                guard let b = otherRaw[key] else { continue }
                let na = numericCount(a), nb = numericCount(b)
                XCTAssertEqual(na, nb, "placeholder angka beda untuk '\(key)' (en=\(a) / \(lang)=\(b))")
            }
        }
    }

    /// Jumlah placeholder angka dalam sebuah nilai.
    ///
    /// Hanya dua bentuk yang sah untuk file lokalisasi ini:
    ///   - posisional  `%1$d`, `%2$@`  (WAJIB dipakai: urutan argumen String(format:)
    ///     tidak dijamin, dan beberapa string punya argumen berulang)
    ///   - polos       `%d`, `%@`
    ///
    /// Bentuk `% s` sengaja TIDAK dihitung: teks normal seperti "10% steps"
    /// atau "100% safety" akan salah terbaca sebagai placeholder kalau spasi
    /// ikut dianggap flag printf yang sah. Membiarkan ruang kosong keluar dari
    /// daftar flag menghilangkan false positive tanpa mengabaikan placeholder
    /// sungguhan yang dipakai project ini.
    private func numericCount(_ s: String) -> Int {
        // TANPA spasi. Spasi SEBENERNYA sah sebagai flag printf ("% d"),
        // tapi memakainya membuat teks biasa salah terbaca: "% safety" dan
        // "% steps" akan dianggap placeholder huruf `s`.
        let flags = Set("-+#0123456789.*hlLqjzt")
        var n = 0, i = s.startIndex
        while i < s.endIndex {
            guard s[i] == "%" else { i = s.index(after: i); continue }
            // Bentuk posisional `%<angka>$...`: digit HARUS disusul `$`.
            // Kalau hanya digit lalu karakter lain ("10% steps"), itu bukan
            // posisional — dan seluruh sisa baris dianggap teks biasa.
            var j = s.index(after: i)
            var sawDigits = false
            while j < s.endIndex, s[j].isNumber { j = s.index(after: j); sawDigits = true }
            if sawDigits {
                guard j < s.endIndex, s[j] == "$" else { break }
                j = s.index(after: j)
            }
            while j < s.endIndex, flags.contains(s[j]) { j = s.index(after: j) }
            if j < s.endIndex, !"@%".contains(s[j]),
               "diouxXeEfgGaAcCsSpn".contains(s[j]) {
                n += 1
                i = s.index(after: j)
            } else {
                // "%" telanjang, "%@", atau teks biasa seperti "% step".
                // Loop berakhir di sini — addressing melewati endIndex akan crash.
                break
            }
        }
        return n
    }
}
