import XCTest
import SwiftUI
@testable import FreePNApp

/// D82 — tombol Sambung/Putus dan Quick Connect HARUS diam di tempat saat
/// status koneksi berubah.
///
/// Gejala yang dilaporkan: "saat saya klik sambung atau putus, posisi
/// tombolnya tidak fix, kadang naik turun".
///
/// Penyebabnya BUKAN animasi tombol, tapi reflow: bagian yang isinya
/// berubah-ubah menurut status berada DI ATOMBOL, jadi saat bagian itu
/// muncul atau hilang, tombol ikut terdorong ke bawah atau ke atas.
///
/// Test ini memindai SOURCE, karena tinggi hasil tata letak SwiftUI tidak
/// bisa diukur di unit test tanpa merender view. Yang dijaga adalah
/// INVARIAN STRUKTURNYA: tidak boleh ada blok bersyarat di antara status
/// dan tombol.
final class ConnectViewLayoutStabilityTests: XCTestCase {

    private func read(_ relPath: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relPath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Potong dari `anchor` sampai anggota struct BERIKUTNYA.
    ///
    /// Versi pertama mencari baris ber-indentasi 0. Tapi anggota struct
    /// ber-indentasi 4 spasi, jadi tidak ada yang pernah cocok: potongannya
    /// melaju sampai AKHIR FILE. Test yang hanya mengecek "kunci ini ada"
    /// tetap hijau — tapi hijau karena salah alasan, dan bisa ditembus
    /// mutasi yang mengubah bagian lain file.
    private func slice(_ src: String, anchor: String) throws -> String {
        let start = try XCTUnwrap(src.range(of: anchor))
        // Mundur ke awal baris; kalau tidak, indentasi `lines[0]` hilang.
        let lineStart = src[..<start.lowerBound].lastIndex(of: "\n").map { src.index(after: $0) }
            ?? src.startIndex
        let lines = src[lineStart...].split(separator: "\n", omittingEmptySubsequences: false)
        let base = (lines[0].prefix { $0 == " " }).count
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

    private func powerCardBody(_ src: String) throws -> String {
        try slice(src, anchor: "private var powerCard: some View")
    }

    private func connectedInfoBody(_ src: String) throws -> String {
        try slice(src, anchor: "private var connectedInfo: some View")
    }

    /// Sanity check: helper harus benar-benar menemukan blok.
    func testHelperActuallyFindsTheBody() throws {
        let body = try powerCardBody(try read("FreePN/UI/ConnectView.swift"))
        XCTAssertGreaterThan(body.count, 500, "helper tidak menemukan powerCard")
        XCTAssertTrue(body.contains("PrimaryButtonStyle"))
        XCTAssertTrue(body.contains("connectedInfo"))
    }

    /// REGRESI UTAMA.
    ///
    /// Blok durasi + IP dulu ditulis sebagai `if status == .connected` yang
    /// diletakkan DI ATAS tombol. Setiap sambung berhasil menambah tinggi di
    /// atas tombol sehingga tombol melorot ke bawah; setiap putus menariknya
    /// ke atas. Itu persis gejala "kadang naik turun".
    ///
    /// Sekarang harus berupa view `connectedInfo` dengan tinggi terkunci.
    func testConnectedInfoIsNotConditionallyAddedAboveTheButton() throws {
        let body = try powerCardBody(try read("FreePN/UI/ConnectView.swift"))

        XCTAssertTrue(body.contains("connectedInfo"),
                      "powerCard harus memakai view connectedInfo")
        XCTAssertFalse(
            body.contains("if state.connection.status == .connected, let since"),
            "blok info tersambung tidak boleh lagi berupa `if` di powerCard — "
            + "itu yang mendorong tombol naik-turun")
    }

    /// Tinggi terkunci harus benar-benar DIPAKAI, bukan hanya dideklarasikan.
    ///
    /// Versi test pertama hanya mengecek konstantanya ADA. Mutasi yang
    /// menghapus `.frame(height:)` dari call site — perubahan yang justru
    /// mengembalikan bug aslinya — tetap LULUS. Hanya dideklarasikan saja tidak
    /// cukup: yang menentukan soal tata letak adalah call site-nya.
    func testLockedHeightsAreActuallyApplied() throws {
        let body = try powerCardBody(try read("FreePN/UI/ConnectView.swift"))
        for name in ["statusTitleHeight", "statusDetailHeight"] {
            XCTAssertTrue(
                body.contains(".frame(height: Self.\(name))"),
                "\(name) dideklarasikan tapi TIDAK dipakai di powerCard — "
                + "tingginya tidak terkunci dan tombol bisa bergeser")
        }
        // `connectedInfo` yang memakainya, jadi periksa di view itu.
        let info = try connectedInfoBody(try read("FreePN/UI/ConnectView.swift"))
        XCTAssertTrue(info.contains(".frame(height: Self.connectedInfoHeight)"),
                      "connectedInfoHeight tidak dipakai di connectedInfo")
    }

    /// Isi `connectedInfo` saja.
    
    /// D83 — tinggi terkunci HARUS ikut skala UI.
    ///
    /// Versi D82 memakai literal (24 / 32 / 35). Itu rusak: `Theme.uiScale`
    /// bisa diubah user lewat Pengaturan, jadi di 125% satu baris callout
    /// sudah lebih tinggi dari 32pt dan teks detail TERPOTONG — persis yang
    /// terlihat di tangkapan layar ("Internet Anda tidak terlindu...").
    ///
    /// Diuji secara NUMERIK, bukan memindai source: `Theme.uiScale` bisa
    /// langsung diset di test, jadi tidak perlu menebak regex.
    func testLockedHeightsScaleWithUIScale() {
        let original = Theme.uiScale
        defer { Theme.uiScale = original }

        Theme.uiScale = 1.0
        let baseTitle = ConnectView.statusTitleHeight
        let baseDetail = ConnectView.statusDetailHeight
        let baseInfo = ConnectView.connectedInfoHeight

        Theme.uiScale = 1.5
        let bigTitle = ConnectView.statusTitleHeight
        let bigDetail = ConnectView.statusDetailHeight
        let bigInfo = ConnectView.connectedInfoHeight

        XCTAssertGreaterThan(bigTitle, baseTitle, "tinggi judul harus ikut skala")
        XCTAssertGreaterThan(bigDetail, baseDetail, "tinggi detail harus ikut skala")
        XCTAssertGreaterThan(bigInfo, baseInfo, "tinggi info harus ikut skala")

        // Naiknya harus linear dengan uiScale, bukan melompat-lompat.
        XCTAssertEqual(bigTitle / baseTitle, 1.5, accuracy: 0.01)
        XCTAssertEqual(bigDetail / baseDetail, 1.5, accuracy: 0.01)
    }

    /// Tinggi detail harus cukup untuk DUA baris callout pada skala 1.0.
    /// Kalau tidak, teks panjang terpotong — bug yang terlihat di D82.
    func testDetailHeightFitsTwoLinesAtDefaultScale() {
        let original = Theme.uiScale
        defer { Theme.uiScale = original }
        Theme.uiScale = 1.0
        let oneLine = Theme.pointSize(.callout) * ConnectView.lineFactor
        XCTAssertGreaterThanOrEqual(
            ConnectView.statusDetailHeight, oneLine * 2 - 0.01,
            "ruang detail harus memuat dua baris callout")
    }

    /// Tinggi terkunci harus URUT dari atas ke bawah: judul, detail, info.
    func testLockedHeightsAreDeclaredInVisualOrder() throws {
        let src = try read("FreePN/UI/ConnectView.swift")
        let title = try XCTUnwrap(src.range(of: "static var statusTitleHeight"))
        let detail = try XCTUnwrap(src.range(of: "static var statusDetailHeight"))
        let info = try XCTUnwrap(src.range(of: "static var connectedInfoHeight"))
        XCTAssertLessThan(title.lowerBound, detail.lowerBound)
        XCTAssertLessThan(detail.lowerBound, info.lowerBound)
    }

    /// Checkbox auto-reconnect berada DI BAWAH tombol Sambung (menggantikan
    /// Quick Connect yang dihapus). Stability-nya otomatis ikut asal tidak
    /// ada blok bersyarat di antara keduanya.
    func testAutoReconnectCheckboxIsPresentAndBelowConnectButton() throws {
        let body = try powerCardBody(try read("FreePN/UI/ConnectView.swift"))
        let connect = try XCTUnwrap(body.range(of: "PrimaryButtonStyle()"))
        let toggle = try XCTUnwrap(body.range(of: "auto_reconnect_short"))
        XCTAssertLessThan(connect.lowerBound, toggle.lowerBound,
                          "checkbox auto-reconnect harus di bawah tombol Sambung")
        XCTAssertNil(body.range(of: "SecondaryButtonStyle()"),
                     "Quick Connect sudah dihapus dari kartu Daya")
    }
}