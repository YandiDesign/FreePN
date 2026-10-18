import XCTest
import SwiftUI
import AppKit
@testable import FreePNApp

/// Membandingkan glyph ikon dengan render SVG aslinya, piksel demi piksel.
///
/// Ini satu-satunya cara benar-benar membuktikan `DeadNodeMark` (dan
/// `GitHubMark`) sama dengan SVG yang diberikan. Membandingkan "jumlah
/// koordinat" atau "ukuran kotak pembatas" hanya menangkap sebagian kesalahan:
/// satu busur yang terbalik arah tetap menghasilkan kotak yang sama persis
/// dan segalanya terlihat "benar", padahal bentuknya bukan ikon yang
/// dimaksud.
///
/// Cara kerjanya: `ImageRenderer` adalah jalur render yang PERSIS sama dengan
/// yang dipakai app di layar (SwiftUI `Shape` -> `Path` -> CoreGraphics), jadi
/// yang diuji bukan tiruan, tapi kode yang benar-benar shipped.
final class IconRenderTests: XCTestCase {

    /// Render shape ke PNG grayscale di ukuran tertentu.
    ///
    /// `@MainActor`: `ImageRenderer` terisolasi ke main actor, dan test
    /// class ini tidak — tanpa anotasi ini build gagal, bukan test-nya.
    @MainActor
    private func render(_ shape: some Shape, side: Int) throws -> [[Double]] {
        // Dua hal yang WAJIB di sini, keduanya sudah bikin test ini diam-diam
        // bohong kalau dikesize:
        //
        // 1. `.fill(...)` — `Shape` belum View. Tanpa itu `ImageRenderer`
        //    memakai warna bawaan dan seluruh kotak jadi tinta.
        // 2. Latar putih di belakang — `ImageRenderer` menghasilkan alfa
        //    transparan, dan `colorAt` membaca RGB *premultiplied*, jadi piksel
        //    kosong terbaca sebagai (0,0,0) alias hitam. Tanpa latar putih,
        //    setiap piksel dihitung tinta dan IoU selalu nonsense.
        let view = ZStack {
            Color.white
            shape.fill(Color.black)
        }
        .frame(width: CGFloat(side), height: CGFloat(side))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        guard let cg = renderer.cgImage else {
            throw XCTSkip("ImageRenderer tidak menghasilkan CGImage di lingkungan ini")
        }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let data = rep.representation(using: .png, properties: [:]),
              let img = NSImage(data: data),
              let tiff = img.tiffRepresentation,
              let bmp = NSBitmapImageRep(data: tiff) else {
            throw XCTSkip("gagal membaca hasil render")
        }
        var rows: [[Double]] = []
        for y in 0..<bmp.pixelsHigh {
            var row: [Double] = []
            for x in 0..<bmp.pixelsWide {
                // Nilai gelap = tinta. Kita hanya butuh "ada tinta atau tidak".
                let c = bmp.colorAt(x: x, y: y) ?? .white
                let lum = (0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent)
                row.append(1.0 - lum)
            }
            rows.append(row)
        }
        return rows
    }

    /// Tulis render shape ke PNG untuk diperiksa di luar Xcode.
    @MainActor
    private func write(_ shape: some Shape, to url: URL, side: Int) throws {
        let renderer = ImageRenderer(content: ZStack {
            Color.white
            shape.fill(Color.black)
        }.frame(width: CGFloat(side), height: CGFloat(side)))
        renderer.scale = 1
        guard let cg = renderer.cgImage else { return }
        let rep = NSBitmapImageRep(cgImage: cg)
        try rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    /// Hitung IoU render terhadap PNG referensi.
    @MainActor
    private func compare(_ shape: some Shape, reference label: String, side: Int,
                         minIoU: Double, name: String) throws {
        let mine = try render(shape, side: side)
        guard let ref = Self.referenceBitmap(label: label, side: side) else {
            throw XCTSkip("referensi SVG \(label) tidak ditemukan")
        }
        let n = min(mine.count, ref.count)
        var inter = 0.0, union = 0.0
        for y in 0..<n {
            for x in 0..<n {
                let a = mine[y][x] > 0.5
                let b = ref[y][x] > 0.5
                if a && b { inter += 1 }
                else if a || b { union += 1 }
            }
        }
        union += inter
        let iou = union > 0 ? inter / union : 0
        print("\n=== \(name) @\(side)px — IoU=\(String(format: "%.4f", iou)) ===")
        if let env = ProcessInfo.processInfo.environment["FREEPN_ICON_DUMP"] {
            try? write(shape, to: URL(fileURLWithPath: env).appendingPathComponent("\(name).png"), side: side)
        }
        XCTAssertGreaterThanOrEqual(iou, minIoU,
            "glyph tidak cocok dengan SVG asal (IoU \(String(format: "%.4f", iou)) < \(minIoU))")
    }

    /// PNG referensi hasil render SVG asli, disimpan di
    /// `FreePNTests/Fixtures/`. Dicari lewat `#filePath`, bukan lewat
    /// environment variable, supaya test ini benar-benar jalan di CI —
    /// kalau referensinya hanya ada di /tmp, testnya diam-diam `skip` dan
    /// tidak pernah mengunci apa pun.
    private static func referenceBitmap(label: String, side: Int) -> [[Double]]? {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
        let url = dir.appendingPathComponent("\(label)_\(side).png")
        guard let data = try? Data(contentsOf: url),
              let img = NSImage(data: data),
              let tiff = img.tiffRepresentation,
              let bmp = NSBitmapImageRep(data: tiff) else { return nil }
        var rows: [[Double]] = []
        for y in 0..<bmp.pixelsHigh {
            var row: [Double] = []
            for x in 0..<bmp.pixelsWide {
                let c = bmp.colorAt(x: x, y: y) ?? .white
                let lum = 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent
                row.append(1.0 - lum)
            }
            rows.append(row)
        }
        return rows
    }

    /// `16` dan `32` bukanDecor: 16px viewBox adalah ukuran glyph yang
    /// benar-benar tampil di toolbar. Bentuk yang benar di 512px masih bisa
    /// berantakan di 16px kalau ada detail yang terlalu rapat.
    @MainActor
    func testDeadNodeMarkMatchesSourceSVG() throws {
        for side in [16, 32, 128, 512] {
            try compare(DeadNodeMark(), reference: "deadnode", side: side,
                        minIoU: side <= 32 ? 0.95 : 0.98, name: "DeadNodeMark")
        }
    }

    @MainActor
    func testGitHubMarkMatchesSourceSVG() throws {
        // Ambang 16px lebih rendah untuk GitHubMark karena glyph-nya terisi
        // penuh, bukan garis: di 16px disagreement antialiasing pada tepi
        // jauh lebih besar proporsinya dibanding glyph ber-outline seperti
        // DeadNodeMark. Bentuknya sendiri terkunci di 128/512px.
        for side in [16, 128, 512] {
            try compare(GitHubMark(), reference: "github", side: side,
                        minIoU: side <= 32 ? 0.85 : 0.97, name: "GitHubMark")
        }
    }
}