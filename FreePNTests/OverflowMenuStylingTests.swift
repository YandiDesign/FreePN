import XCTest
import SwiftUI
@testable import FreePNApp

/// D83 — tombol `…` di kanan atas harus membuka panel milik aplikasi, bukan
/// menu sistem macOS.
///
/// Gejalanya: "saat saya klik hanya menu kecil bawaan menu mac".
///
/// Penyebabnya `Menu { } label: { }` + `.menuStyle(.borderlessButton)`: di
/// macOS SwiftUI me-nyawakakan NSMenu apa adanya. Style hanya mengubah
/// pemicunya; isi menunya tetap milik sistem — tinggi baris ~22pt, system
/// font, warna terang, tidak nyambung dengan kartu dark navy di sekitarnya.
///
/// Test ini memindai SOURCE. Yang dijaga adalah invarian strukturalnya:
/// tidak boleh ada `Menu {` lagi di layar ini, dan isi panel harus memakai
/// komponen desain yang sama dengan kartu lain.
final class OverflowMenuStylingTests: XCTestCase {

    private func read(_ relPath: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relPath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private var src: String { (try? read("FreePN/UI/ConnectView.swift")) ?? "" }

    /// REGRESI UTAMA: `Menu` bawaan macOS tidak boleh dipakai untuk panel ini.
    ///
    /// Pengecualian: `Menu` boleh muncul di tempat lain (mis. app menu), jadi
    /// yang diperiksa adalah blok `overflowMenu` dan panelnya, bukan seluruh
    /// file.
    func testNoNativeMenuIsUsedForTheOverflowPanel() throws {
        let body = try overflowMenuBody()
        XCTAssertFalse(body.contains("Menu {"),
                       "Menu {} akan me-nyawakakan NSMenu sistem — itu sebab "
                       + "menu ini terlihat kecil dan asing")
        XCTAssertFalse(body.contains(".menuStyle"),
                       "menuStyle(.borderlessButton) hanya mengubah pemicunya; "
                       + "isi menunya tetap milik sistem")
        XCTAssertTrue(body.contains(".popover(isPresented:"),
                      "panel harus pakai .popover agar tutup saat klik luar / Esc "
                      + "dan posisi mengikuti tepi jendela")
    }

    /// Sanity check untuk helper pemotong blok.
    func testHelperFindsTheOverflowMenu() throws {
        let body = try overflowMenuBody()
        XCTAssertGreaterThan(body.count, 300, "helper tidak menemukan overflowMenu")
        XCTAssertTrue(body.contains("overflowPanel"))
    }

    /// Baris menu harus jauh lebih tinggi dari tinggi baris NSMenu (~22pt).
    /// Kalau dikembalikan ke ~22, panelnya kembali terasa "kecil".
    func testMenuRowsAreTallerThanTheNativeMenu() throws {
        // tinggi baris hidup di `overflowItem`, bukan di `overflowPanel`.
        let panel = try slice(try read("FreePN/UI/ConnectView.swift"),
                              anchor: "private func overflowItem(")
        XCTAssertTrue(panel.contains(".frame(height: 46)"),
                      "tinggi baris menu 46pt; <=22pt berarti kembali ke gaya NSMenu")
    }

    /// Lebar panel 300pt; NSMenu ~180pt.
    func testPanelIsWiderThanTheNativeMenu() throws {
        let panel = try overflowPanelBody()
        XCTAssertTrue(panel.contains(".frame(width: 300)"),
                      "panel 300pt; ~180pt berarti kembali ke gaya NSMenu")
    }

    /// Aksi yang dulu ada harus UTUH. Redesign tampilan tidak boleh diam-diam
    /// membuang atau salah menyambungkan aksi.
    func testAllOriginalActionsStillPresent() throws {
        let panel = try overflowPanelBody()
        XCTAssertTrue(panel.contains("state.refreshAll()"), "Refresh harus ada")
        XCTAssertTrue(panel.contains("state.pingAll()"), "Ping All harus ada")
        XCTAssertTrue(panel.contains("selection = \"servers\""), "Servers harus ada")
        XCTAssertTrue(panel.contains("selection = \"sources\""), "Sources harus ada")
    }

    /// `pingAll` harus tetap nonaktif saat belum ada server — seperti
    /// sebelumnya di `Menu`.
    func testPingRemainsDisabledWithoutServers() throws {
        let panel = try overflowPanelBody()
        XCTAssertTrue(panel.contains("disabled: state.nodes.isEmpty"),
                      "Ping All harus disabled saat nodes kosong")
    }

    /// Setiap baris harus menutup panel setelah dipakai. Kalau tidak, user
    /// menekan aksi lalu panel tetap terbuka di atas beranda.
    func testChoosingAnItemClosesThePanel() throws {
        let src = try read("FreePN/UI/ConnectView.swift")
        let item = try XCTUnwrap(src.range(of: "private func overflowItem("))
        let body = src[item.lowerBound...]
            .prefix(2500)
        XCTAssertTrue(body.contains("showOverflow = false"),
                      "baris menu harus menutup panel setelah aksi dijalankan")
    }

    /// Warna panel harus dari palet aplikasi, bukan warna sistem.
    func testPanelUsesAppPalette() throws {
        let panel = try overflowPanelBody()
        XCTAssertTrue(panel.contains("Palette.card"))
        XCTAssertTrue(panel.contains("Palette.border"))
    }

    /// Semua key yang dipakai panel harus benar-benar ada di Localization,
    /// di BAHASA KEDUA. Kalau tidak, `Text(LocalizedStringKey)` merender
    /// key mentah apa adanya — persis jebakan yang sudah pernah dialami di
    /// `qualityTags`.
    func testEveryMenuKeyExistsInBothLanguages() throws {
        let panel = try overflowPanelBody()
        let en = try read("FreePN/Localization/en.lproj/Localizable.strings")
        let id = try read("FreePN/Localization/id.lproj/Localizable.strings")

        // Kunci yang diteruskan ke helper menu.
        let keys = ["menu_section_actions", "menu_section_navigation",
                    "menu_refresh_all", "menu_refresh_all_sub",
                    "menu_ping_all", "menu_ping_all_sub",
                    "menu_servers_sub", "menu_sources_sub",
                    "nav_servers", "nav_sources"]
        for key in keys {
            XCTAssertTrue(panel.contains(key), "kunci \(key) dipakai panel tapi tidak ada di kode")
            XCTAssertTrue(en.contains("\"\(key)\""), "kunci \(key) hilang dari en.lproj")
            XCTAssertTrue(id.contains("\"\(key)\""), "kunci \(key) hilang dari id.lproj")
        }
    }

    // MARK: - Helper

    private func overflowMenuBody() throws -> String {
        let src = try read("FreePN/UI/ConnectView.swift")
        return try slice(src, anchor: "private var overflowMenu: some View")
    }

    private func overflowPanelBody() throws -> String {
        let src = try read("FreePN/UI/ConnectView.swift")
        return try slice(src, anchor: "private var overflowPanel: some View")
    }

    /// Potong dari `anchor` sampai anggota struct BERIKUTNYA.
    ///
    /// Versi pertama mencari baris ber-indentasi 0. Tapi anggota struct
    /// ber-indentasi 4 spasi, jadi tidak ada yang pernah cocok dan potongannya
    /// melaju sampai akhir file (1094 baris!). Itu tidak merusak test ini,
    /// tapi membuat `assertFalse(body.contains("Menu {"))` bisa tersandung
    /// `.contextMenu {` di bagian file yang lain — persis yang terjadi.
    private func slice(_ src: String, anchor: String) throws -> String {
        let start = try XCTUnwrap(src.range(of: anchor))
        // Mundur ke awal baris. Tanpa ini `lines[0]` diawali "private ..."
        // tanpa indentasi, jadi `base` bernilai 0 dan tidak ada anggota yang
        // bisa cocok — potongannya kembali melaju ke akhir file.
        let lineStart = src[..<start.lowerBound].lastIndex(of: "\n").map { src.index(after: $0) }
            ?? src.startIndex
        let lines = src[lineStart...].split(separator: "\n", omittingEmptySubsequences: false)
        let base = (lines[0].prefix { $0 == " " }).count
        var end = lines.endIndex
        for i in 1..<lines.endIndex {
            let l = lines[i]
            let t = l.trimmingCharacters(in: .whitespaces)
            if t.isEmpty || t.hasPrefix("//") { continue }
            let indent = l.prefix { $0 == " " }.count
            guard indent == base else { continue }
            for kw in ["private ", "static ", "public ", "internal ", "func ", "var ", "let ", "@"] where t.hasPrefix(kw) {
                end = i
                break
            }
            if end != lines.endIndex { break }
        }
        let block = lines[0..<end].joined(separator: "\n")
        // Komentar dibuang: komentar D83 sendiri menyebut "Menu { }" untuk
        // menjelaskan apa yang diganti, jadi tanpa ini test melaporkan dirinya
        // sendiri salah.
        return block
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }
}
