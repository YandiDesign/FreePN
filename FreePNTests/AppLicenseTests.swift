import XCTest
import SwiftUI
@testable import FreePNApp

/// D84 — lisensi app harus MIT, dan kewajiban atribusi ke GitHub harus
/// terlihat di dalam aplikasi.
///
/// Ini bukan sekadar tampilan. MIT mewajibkan: "The above copyright notice
/// and this permission notice shall be included in all copies or substantial
/// portions of the Software." Kalau app menampilkan ringkasan, yang tampil
/// BUKAN notice yang diwajibkan, dan menyalin dari layar tidak memenuhi
/// syarat.
final class AppLicenseTests: XCTestCase {

    private func read(_ relPath: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relPath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private var settings: String { (try? read("FreePN/UI/SettingsView.swift")) ?? "" }

    /// Potong satu anggota struct, dari `anchor` sampai anggota berikutnya.
    ///
    /// Jendela karakter tetap TIDAK dipakai: `aboutCard` saja sudah 3.469
    /// karakter dari deklarasi ke baris `.sheet`-nya, jadi jendela 3.000 tidak
    /// sampai dan test gagal untuk alasan yang salah. Sebaliknya jendela yang
    /// terlalu besar membuat test bisa "lolos" karena blok jadi ikut menelan
    /// bagian struct lain yang kebetulan punya teksnya.
    private func member(_ anchor: String, in src: String) throws -> String {
        let start = try XCTUnwrap(src.range(of: anchor), "tidak menemukan \(anchor)")
        let lineStart = src[..<start.lowerBound].lastIndex(of: "\n").map { src.index(after: $0) }
            ?? src.startIndex
        let lines = src[lineStart...].split(separator: "\n", omittingEmptySubsequences: false)
        let base = lines[0].prefix { $0 == " " }.count
        var end = lines.endIndex
        for i in 1..<lines.endIndex {
            let t = lines[i].trimmingCharacters(in: .whitespaces)
            if t.isEmpty || t.hasPrefix("//") { continue }
            guard lines[i].prefix { $0 == " " }.count == base else { continue }
            for kw in ["private ", "static ", "public ", "internal ", "func ", "var ", "let ", "@"]
            where t.hasPrefix(kw) { end = i; break }
            if end != lines.endIndex { break }
        }
        return lines[0..<end].joined(separator: "\n")
    }

    /// Berkas LICENSE wajib ADA di root repo dan menyebut MIT.
    func testLicenseFileExistsAndIsMIT() throws {
        let license = try read("LICENSE")
        XCTAssertTrue(license.contains("MIT License"), "LICENSE harus menyebut MIT")
        XCTAssertTrue(license.contains("Copyright (c) 2026 YandiDesign"),
                      "LICENSE harus mencantumkan pemilik hak cipta")
        XCTAssertTrue(license.contains("https://github.com/YandiDesign"),
                      "LICENSE harus mencantumkan GitHub")
    }

    /// Kalimat wajib MIT, persis — ini yang membuat berkas LICENSE benar-benar
    /// berlaku, bukan sekadar bernama "MIT".
    func testLicenseContainsTheMandatoryMITClause() throws {
        let license = try read("LICENSE")
        let mandatory = "The above copyright notice and this permission notice shall be included in all"
        XCTAssertTrue(license.contains(mandatory),
                      "LICENSE harus memuat kalimat wajib MIT apa adanya")
    }

    /// Teks MIT di dalam app harus SAMA dengan berkas LICENSE.
    ///
    /// Keduanya adalah statement hukum. Kalau melenceng — satu paragraf diubah,
    /// satu kalimat hilang — tidak ada yang memberi tahu, dan tidak ada yang
    /// Salah: sheet-nya masih terbaca, berkasnya masih ada.
    func testInAppLicenseTextMatchesTheLicenseFile() throws {
        let file = try read("LICENSE")
        let view = try read("FreePN/UI/SettingsView.swift")

        guard let start = view.range(of: "private var mitLicenseText: String {")
        else { throw XCTSkip("tidak menemukan mitLicenseText") }
        let body = String(view[start.upperBound...].prefix(2400))

        // Bandingkan kalimat-kalimat kunci, bukan string utuh: indentasi
        // multiline literal di Swift berbeda dari berkas.
        let sentences = [
            "MIT License",
            "Copyright (c) 2026 YandiDesign",
            "https://github.com/YandiDesign",
            "Permission is hereby granted, free of charge",
            "The above copyright notice and this permission notice shall be included in all",
            "THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND",
        ]
        for s in sentences {
            XCTAssertTrue(file.contains(s), "LICENSE kehilangan: \(s)")
            XCTAssertTrue(body.contains(s), "teks lisensi di app kehilangan: \(s)")
        }
    }

    /// Kartu Tentang harus punya baris lisensi DAN sheet-nya benar-benar
    /// terpasang.
    ///
    /// Versi pertama hanya mengecek `showAppLicense` ADA. Tapi simbol itu juga
    /// muncul di `Button { showAppLicense = true }`, jadi mutasi yang
    /// MENGHAPUS `.sheet(...)`-nya tetap LULUS — tombolnya jadi tidak
    /// melakukan apa-apa dan tidak ada yang memberi tahu. Pola yang sama seperti
    /// D82: yang menentukan bukan keberadaan simbol, tapi call site-nya.
    func testAboutCardShowsTheAppLicenseNotOnlyDependencies() {
        let block = (try? member("private var aboutCard: some View", in: settings)) ?? ""

        XCTAssertTrue(block.contains("showAppLicense = true"),
                      "About harus punya baris yang membuka lisensi app")
        XCTAssertTrue(block.contains(".sheet(isPresented: $showAppLicense)"),
                      "sheet lisensi harus benar-benar DIPASANG di aboutCard — "
                      + "tanpa ini tombolnya tidak melakukan apa-apa")
        XCTAssertTrue(block.contains("AppLicenseView()"),
                      "aboutCard harus menampilkan AppLicenseView")
        XCTAssertTrue(block.contains("Text(\"MIT\")"),
                      "badge MIT harus terlihat di baris Lisensi")
    }

    /// `AppLicenseView` harus benar-benar menampilkan teks MIT lengkap.
    func testAppLicenseViewRendersTheFullText() {
        let block = (try? member("struct AppLicenseView: View", in: settings)) ?? ""

        XCTAssertTrue(block.contains("mitLicenseText"),
                      "AppLicenseView harus merender teks MIT")
        XCTAssertTrue(block.contains("Permission is hereby granted"),
                      "teks MIT harus lengkap, bukan ringkasan")
        XCTAssertTrue(block.contains("textSelection(.enabled)"),
                      "notis harus bisa disalin apa adanya")
        // Atribusi harus punya label dan blok kode, bukan cuma URL.
        XCTAssertTrue(block.contains("app_license_attribution_text"))
    }

    /// Atribusi harus berupa KALIMAT, bukan cuma URL di layar. Atribusi yang
    /// hanya tautan tidak memberi tahu apa kewajiban yang sebenarnya.
    func testAttributionIsStatedInWords() {
        XCTAssertTrue(settings.contains("about_attribution_required"),
                      "kalimat kewajiban atribusi harus ada di kartu Tentang")
    }

    /// Isi teks atribusi harus memuat pemilik hak cipta DAN URL GitHub, di
    /// kedua bahasa.
    ///
    /// Dicek di BERKAS .strings, bukan di SettingsView: nilai terjemahan
    /// hanya ada di sana. Versi pertama memindai call site SwiftUI dan
    /// mengambil potongan dari nama key-nya sendiri — jadi yang diuji cuma
    /// key-nya ada, bukan isinya.
    func testAttributionTextCarriesCopyrightAndGitHub() throws {
        for path in ["FreePN/Localization/en.lproj/Localizable.strings",
                     "FreePN/Localization/id.lproj/Localizable.strings"] {
            let file = try read(path)
            guard let start = file.range(of: "\"app_license_attribution_text\" = \""),
                  let end = file[start.upperBound...].firstIndex(of: "\"")
            else { return XCTFail("app_license_attribution_text tidak ada di \(path)") }

            let value = file[start.upperBound..<end]
            XCTAssertTrue(value.contains("YandiDesign"),
                          "atribusi di \(path) harus menyebut pemilik hak cipta")
            XCTAssertTrue(value.contains("github.com/YandiDesign"),
                          "atribusi di \(path) harus menyebut GitHub")
        }
    }

    /// Sheet lisensi pihak ketiga juga harus menyebut lisensi app, supaya
    /// pembacaan "lisensi app = isi sheet ini" tidak terjadi.
    func testThirdPartySheetAlsoNamesTheAppLicense() {
        XCTAssertTrue(settings.contains("licenses_self_note"),
                      "sheet pihak ketiga harus menegaskan lisensi FreePN sendiri")
        // Dan entri FreePN harus ada di sana.
        let idx = try? settings.range(of: "licenseEntry(\"FreePN\", \"MIT\"")
        XCTAssertNotNil(idx, "sheet lisensi harus memuat entri FreePN/MIT")
    }

    /// Semua kunci lisensi harus ada di kedua bahasa.
    func testLicenseKeysExistInBothLanguages() throws {
        let en = try read("FreePN/Localization/en.lproj/Localizable.strings")
        let id = try read("FreePN/Localization/id.lproj/Localizable.strings")
        for key in ["app_license", "app_license_value", "app_license_title",
                    "app_license_attribution_label", "app_license_attribution_text",
                    "app_license_attribution_note", "about_attribution_required",
                    "licenses_self_note"] {
            XCTAssertTrue(en.contains("\"\(key)\""), "\(key) hilang dari en.lproj")
            XCTAssertTrue(id.contains("\"\(key)\""), "\(key) hilang dari id.lproj")
        }
    }

    /// README harus menyatakan kewajiban atribusi — di.sinilah orang yang
    /// akan fork pertama kali membaca syaratnya.
    func testReadmeStatesTheAttributionRequirement() throws {
        let readme = try read("README.md")
        XCTAssertTrue(readme.contains("MIT"), "README harus menyebut MIT")
        XCTAssertTrue(readme.contains("github.com/YandiDesign"),
                      "README harus menyebut GitHub")
        XCTAssertTrue(readme.contains("may not** remove or replace") ||
                      readme.contains("tidak boleh** menghapus"),
                      "README harus menyatakan atribusi tidak boleh dihapus")
    }

    /// Owner dari app harus konsisten di semua tempat. Kalau URL GitHub
    /// berubah di satu tempat saja, notis lisensi jadi menunjuk yang salah.
    func testAttributionOwnerIsConsistent() throws {
        XCTAssertTrue(AppConstants.projectURLString.contains("YandiDesign"))
        let license = try read("LICENSE")
        let readme = try read("README.md")
        XCTAssertTrue(license.contains(AppConstants.projectURLString),
                      "LICENSE harus memakai URL dari AppConstants")
        XCTAssertTrue(readme.contains(AppConstants.projectURLString),
                      "README harus memakai URL dari AppConstants")
    }
}

/// D85 — ESCAPE `\u` KECIL TIDAK BERJALAN di `.strings` project ini.
///
/// Gejala yang dilaporkan: layar menampilkan literal `u00b7` dan `u2014`,
/// bukan `·` dan `—`.
///
/// Penyebabnya bukan salah ketik satu tempat. Parser `.strings` bergaya lama
/// yang dipakai bundle ini mengenali `\Uxxxx` dengan **U KAPITAL**;
/// `\uXXXX` dengan huruf kecil hanya menghasilkan teks harfiah `u00b7` —
/// backslash-nya hilang, sisanya tetap tampil. Tidak ada error, tidak ada
/// peringatan:build tetap sukses dan string-nya tetap "ada".
///
/// Yang membuatnya lolos sangat lama: string yang terkena dampaknya
/// (`licenses_dotmap_note`) adalah keterangan kecil di sheet lisensi, jadi
/// tidak pernah ada yangbenar-benar membacanya dengan saksama.
///
/// Test ini memindai BERKAS Localization, bukan memanggil NSLocalizedString,
/// supaya offending line langsung terlihat di pesan kegagalan beserta
/// nomornya — jauh lebih berguna daripada "nilai string tidak sesuai".
final class LocalizationEscapeTests: XCTestCase {

    private func stringsPath(_ lang: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("FreePN/Localization/\(lang).lproj/Localizable.strings")
        return url.path
    }

    func testNoLowercaseUnicodeEscapesRemain() throws {
        for lang in ["en", "id"] {
            let path = try stringsPath(lang)
            let text = try String(contentsOfFile: path, encoding: .utf8)
            let lines = text.components(separatedBy: "\n")

            var offenders: [String] = []
            for (i, line) in lines.enumerated() where line.contains(where: { $0 == "\\" }) {
                // `\u` huruf kecil.
                //
                // CATATAN kecil yang bikin TEST INI SEMULA NGGAK BISA
                // MENANGKAP APA PUN: polanya ditulis `"\\u..."`.-swift`
                // mengubah `\\` jadi satu backslash, jadi mesin regex
                // menerima `\u...` — dan di ICU itu berarti "karakter
                // unicode dengan digit heksadesimal", BUKAN "backslash lalu
                // huruf u". Hasilnya `range` selalu nil, test selalu hijau,
                // dan mutate-nya lolos.
                //
                // Backslash harus digandakan DUA KALI: satu untuk string
                // Swift, satu lagi untuk mesin regex.
                //
                // `\U` huruf besar sebenarnya benar di sini, dan `\n`
                // memang escape yang sah — keduanya tidak ikut kena.
                let lower = line.range(of: "\\\\u[0-9a-fA-F]{4}",
                                       options: .regularExpression)
                if lower != nil { offenders.append("\(lang).lproj baris \(i + 1)") }
            }
            XCTAssertTrue(offenders.isEmpty,
                          "escape \\u huruf kecil tidak di-parse di .strings project ini; "
                          + "tulis karakter aslinya (· — ' \" ) atau \\U kapital. "
                          + "Baris: \(offenders.joined(separator: ", "))")
        }
    }

    /// Pengaman nyata: nilai yang benar-benar dikembalikan runtime harus
    /// BERISI karakter, bukan teks `u2014`.
    func testResolvedStringsContainRealCharacters() {
        for key in ["app_license_value", "app_license_attribution_text",
                    "licenses_dotmap_note"] {
            let value = NSLocalizedString(key, comment: "")
            XCTAssertFalse(value.contains("\\u"),
                           "\(key) masih memuat escape literal: \(value.debugDescription)")
            XCTAssertFalse(value.contains("u2014"),
                           "\(key) menampilkan 'u2014' sebagai teks, bukan em dash")
            XCTAssertFalse(value.contains("u00b7"),
                           "\(key) menampilkan 'u00b7' sebagai teks, bukan middle dot")
        }
    }

    /// Teks atribusi lisensi harus benar-benar memuat em dash.
    func testAttributionShowsEmDashNotEscape() {
        let value = NSLocalizedString("app_license_attribution_text", comment: "")
        XCTAssertTrue(value.contains("\u{2014}"),
                      "atribusi harus memuat em dash; dapat \(value.debugDescription)")
        XCTAssertTrue(value.contains("YandiDesign"))
    }
}

