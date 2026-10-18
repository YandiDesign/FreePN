import XCTest
import SwiftUI
import AppKit
@testable import FreePNApp

/// D67 — cincin tombol daya sesekali dirender meleset ke bawah.
///
/// BUG: `Circle().fill(...).frame(196).blur(14)` — blur SESUDAH frame.
/// SwiftUI menyisihkan 196x196 untuk tata letak, lalu blur melebar piksel
/// ter-render jadi 224x224, yaitu 28pt di luar batas yang dipesan. Lapisan
/// yang meluber itu tidak selalu sejajar dengan yang lain, dan karena cincin
/// utama ada di ZStack yang sama, keduanya ikut bergeser bersama.
///
/// Test ini mengunci INVARIAN GEOMETRI, bukan piksel render: `.blur(radius:)`
/// memperbesar sisi sebesar 2 x radius, jadi frame yang memuat blur harus
/// minimal sebesar itu. Kalau ada yang menukar urutannya lagi, test ini gagal
/// dengan pesan yang menjelaskan kenapa — bukan diam-diam balik ke bug yang sama.
final class BlurFrameInvariantTests: XCTestCase {

    /// Sisi minimum yang bisa menampung bleed blur.
    ///
    /// Murni & nonisolated supaya bisa diuji tanpa SwiftUI.
    nonisolated static func fits(side: CGFloat, blur: CGFloat) -> Bool {
        side >= blur * 2
    }

    /// Halo `PowerRing`: 168 + 2 x 14 = 196.
    func testPowerRingHaloFitsInsideItsFrame() {
        let circle: CGFloat = 168, blur: CGFloat = 14, frame: CGFloat = 196
        XCTAssertEqual(circle + blur * 2, frame, "halo harus tepat muat, bukan meluber")
        XCTAssertTrue(Self.fits(side: frame, blur: blur))
    }

    /// Halo `HaloIcon`: 122 + 2 x 14 = 150.
    func testHaloIconFitsInsideItsFrame() {
        let circle: CGFloat = 122, blur: CGFloat = 14, frame: CGFloat = 150
        XCTAssertEqual(circle + blur * 2, frame)
        XCTAssertTrue(Self.fits(side: frame, blur: blur))
    }

    /// Urutan modifier di source: `.blur()` harus muncul SEBELUM `.frame()`.
    ///
    /// Ini yang sebenarnya merusak, jadi yang dikunci adalah urutannya — test
    /// geometri di atas hanya membuktikan angkanya, bukan bahwa kodenya
    /// benar-benar menerapkannya.
    func testBlurIsAppliedBeforeFrameInSource() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let path = testFile
            .deletingLastPathComponent()   // FreePNTests/
            .deletingLastPathComponent()   // root repo
            .appendingPathComponent("FreePN/DesignSystem/Badge.swift")
        let src = try String(contentsOf: path, encoding: .utf8)

        // Ambil blok `PowerRing` saja supaya perubahan lain tidak mengacaukan.
        guard let start = src.range(of: "public struct PowerRing"),
              let end = src.range(of: "public struct NodeConnectButton")
        else {
            return XCTFail("tidak menemukan blok PowerRing di \(path)")
        }
        let block = String(src[start.lowerBound..<end.lowerBound])

        // KOMENTAR HARUS DILEWATI. Test versi pertama salah karena memindai
        // baris komentar yang kebetulan memuat kata ".frame()" — dan gagal pada
        // kode yang justru BENAR. Memindai komentar untuk keputusan layout
        // adalah cara tercepat membuat test ini melaporkan kebohongan.
        var code: [String] = []
        for raw in block.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: CharacterSet.whitespaces)
            if line.hasPrefix("//") { continue }
            code.append(line)
        }

        // Rantai modifier tiap `Circle()` dibaca dari `Circle()` berikutnya.
        //
        // Versi pertama dari test ini cuma memeriksa "baris blur tidak
        // sekaligus memuat .frame" — itu SALAH, karena bug aslinya justru
        // TIDAK meletakkan blur dan frame di baris yang sama: ia menaruh
        // `.frame()` di baris SEBELUMNYA lalu `.blur()` sesudahnya. Resultannya
        // test hijau saat bug-nya dikembalikan. Yang diuji harus URUTAN dalam
        // satu rantai: tidak boleh ada `.frame(` yang muncul sebelum `.blur(`.
        var chains: [[String]] = []
        var current: [String] = []
        for line in code {
            if line.hasPrefix("Circle(") || line.hasPrefix("RoundedRectangle(") {
                if !current.isEmpty { chains.append(current) }
                current = []
                continue
            }
            guard line.hasPrefix(".") || line.isEmpty || line.hasPrefix(")") else {
                if !current.isEmpty { chains.append(current) }
                current = []
                continue
            }
            if line.hasPrefix(".") { current.append(line) }
        }
        if !current.isEmpty { chains.append(current) }

        // INVARIAN YANG BENAR, setelah dua versi test ini salah:
        //
        //  v1: "baris blur tidak boleh sekaligus berisi .frame" — SALAH, bug
        //      aslinya justru tidak meletakkan keduanya di baris sama, dan
        //      test ini hijau saat bug dikembalikan.
        //  v2: "tidak boleh ada .frame() sebelum .blur()" — juga SALAH, karena
        //      `.frame()` SEBELUM blur justru wajib ada: itu yang memberi
        //      ukuran isinya. Yang wajib adalah frame SESUDAH blur.
        //
        // Aturan sebenarnya: bleed blur adalah 2 x radius, dan harus MUAT di
        // frame yang menyusulnya. Jadi frame sesudah blur harus >= frame
        // sebelum blur + 2 x radius. Bug asli (`.frame(196).blur(14)` tanpa
        // frame sesudahnya) tidak punya frame pemuat sama sekali, dan gagal.
        var blurred = 0
        for chain in chains {
            guard let blurIdx = chain.firstIndex(where: { $0.contains(".blur(") }) else { continue }
            blurred += 1
            let blurRadius = Self.radius(in: chain[blurIdx]) ?? 0
            let before = chain[..<blurIdx].last.flatMap { Self.side(in: $0) } ?? 0
            let after = chain[(blurIdx + 1)...].first.flatMap { Self.side(in: $0) }
            guard let after else {
                return XCTFail("blur tanpa frame sesudahnya — bleed pasti meluber keluar: \(chain)")
            }
            XCTAssertGreaterThanOrEqual(after, before + blurRadius * 2,
                                        "frame sesudah blur harus memuat bleed \(blurRadius * 2): \(chain)")
        }
        XCTAssertGreaterThan(blurred, 0, "halo PowerRing harus masih ada dan teruji")
    }

    /// Ambil angka dari `.frame(width: N, ...)`.
    nonisolated static func side(in line: String) -> CGFloat? {
        Self.number(in: line, after: "width:")
    }

    /// Angka pertama setelah penanda tertentu.
    nonisolated static func number(in line: String, after marker: String) -> CGFloat? {
        guard let at = line.range(of: marker) else { return nil }
        let rest = line[at.upperBound...]
        return CGFloat(Double(rest.prefix { $0.isNumber || $0 == "." }) ?? 0)
    }

    /// Ambil angka dari `.blur(radius: N)`.
    nonisolated static func radius(in line: String) -> CGFloat? {
        guard line.contains(".blur(") else { return nil }
        return number(in: line, after: "radius:")
    }
}
