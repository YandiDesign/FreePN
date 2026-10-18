import XCTest
import SwiftUI
@testable import FreePNApp

/// D78 — kartu Trafik menampilkan SATU grafik gabungan: download hijau dan
/// upload biru digambar di plot yang sama.
///
/// D77 sempat memisahkannya jadi dua grafik setengah lebar; permintaan
/// berikutnya adalah menyatukannya kembali.
///
/// Test ini memindai SOURCE, bukan merender: yang perlu dijaga adalah PASANGAN
/// grafik ↔ seri data ↔ warna. Tertukar satu baris (upload membaca
/// `downHistory`) akan terlihat sangat wajar — dua kurva di satu panel yang
/// isinya salah — dan sama sekali tidak ketahuan dari kode yang tetap compiles.
final class TrafficCardGraphPairingTests: XCTestCase {
    private func read(_ relPath: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // FreePNTests/
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent(relPath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Isi `TrafficCard` saja.
    ///
    /// Batas bawah dicari dari deklarasi top-level BERIKUTNYA, bukan dari
    /// penanda di dalam struct. Versi pertama memakai `public func bytes(` —
    /// anchor itu tidak pernah ada (method-nya `static`), jadi seluruh test di
    /// file ini **diam-diam ke-skip** dan terlihat hijau tanpa menguji apa
    /// pun. Test yang skip sama dengan test yang tidak ada.
    private func trafficCardBody(_ src: String) throws -> String {
        let lines = src.split(separator: "\n", omittingEmptySubsequences: false)
        guard let start = lines.firstIndex(where: { $0.contains("struct TrafficCard: View") })
        else { throw XCTSkip("tidak menemukan deklarasi TrafficCard") }

        var end = lines.endIndex
        var i = start + 1
        while i < lines.endIndex {
            let l = lines[i]
            let trimmed = l.trimmingCharacters(in: .whitespaces)
            let topLevel = !l.hasPrefix(" ") && !l.hasPrefix("\t")
                && !trimmed.isEmpty && !trimmed.hasPrefix("//")
            if topLevel { end = i; break }
            i += 1
        }
        return lines[start..<end].joined(separator: "\n")
    }

    /// Sanity check untuk test di file ini.
    ///
    /// Kalau helper pemotong blok diam-diam gagal, test lain akan ke-skip dan
    /// terlihat hijau tanpa menguji apa pun — persis yang terjadi pada versi
    /// pertama. Test ini membuat kegagalan itu terdengar.
    func testHelperActuallyFindsTheBody() throws {
        let body = try trafficCardBody(try read("FreePN/UI/ConnectView.swift"))
        XCTAssertGreaterThan(body.count, 500,
                             "helper tidak menemukan isi TrafficCard — test lain akan skip")
        XCTAssertTrue(body.contains("var body: some View"))
        XCTAssertTrue(body.contains("Sparkline"))
    }

    /// Permintaan aslinya: SATU plot, bukan dua. Kembalinya ke dua `Sparkline`
    /// berarti permintaan "satukan" diabaikan.
    func testBothDirectionsShareASingleGraph() throws {
        let body = try trafficCardBody(try read("FreePN/UI/ConnectView.swift"))
        let graphs = body.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("Sparkline(") }
        XCTAssertEqual(graphs.count, 1,
                       "harus ada tepat satu Sparkline (grafik gabungan), ada \(graphs.count)")
        XCTAssertFalse(body.contains("Sparkline(series: connection.upHistory"),
                       "upload harus jadi SERI KEDUA di plot yang sama, bukan Sparkline terpisah")
    }

    /// Pasangan seri ↔ warna di dalam satu panggilan.
    func testCombinedGraphPairsEachSeriesWithItsTint() throws {
        let body = try trafficCardBody(try read("FreePN/UI/ConnectView.swift"))
        XCTAssertTrue(body.contains("series: connection.downHistory, tint: Palette.mint"),
                      "download harus jadi seri utama: downHistory + mint")
        XCTAssertTrue(body.contains("secondary: connection.upHistory, secondaryTint: Palette.info"),
                      "upload harus jadi seri kedua: upHistory + Palette.info")
    }

    /// Larangan keras: tidak boleh ada seri milik arah lain yang "dipinjam".
    ///
    /// Mengganti `secondary:` dengan `downHistory` menghasilkan dua garis hijau
    /// yang persis tumpang tindih — sangat mungkin terlihat normal, dan
    /// faktanya upload tidak pernah digambar.
    func testNeitherSeriesBorrowsTheOtherDirection() throws {
        let body = try trafficCardBody(try read("FreePN/UI/ConnectView.swift"))
        let mainRef = body.range(of: "series: connection.downHistory")
        XCTAssertNotNil(mainRef, "seri utama harus downHistory")
        let secondaryRef = body.range(of: "secondary: connection.upHistory")
        XCTAssertNotNil(secondaryRef, "seri kedua harus upHistory")

        // Guard tambahan: seri utama tidak boleh upHistory dan sebaliknya.
        let call = try XCTUnwrap(body.split(separator: "\n")
            .first { $0.contains("Sparkline(") },
            "tidak menemukan panggilan Sparkline")
        XCTAssertFalse(call.contains("series: connection.upHistory"),
                       "seri utama salah arah: \(call)")
        XCTAssertFalse(call.contains("secondary: connection.downHistory"),
                       "seri kedua salah arah: \(call)")
    }

    /// Warna upload harus benar-benar BIRU, bukan sekadar "bukan mint".
    ///
    /// Dibaca dari SOURCE palet: komponen RGB `Color` hanya tersedia lewat
    /// bridge platform, yang tidak ada di unit test.
    func testUploadTintIsTheAppBlue() throws {
        let body = try trafficCardBody(try read("FreePN/UI/ConnectView.swift"))
        XCTAssertTrue(body.contains("secondaryTint: Palette.info"))

        let theme = try read("FreePN/DesignSystem/Theme.swift")
        guard let line = theme.split(separator: "\n").first(where: { $0.contains("static let info =") })
        else { return XCTFail("tidak menemukan definisi Palette.info") }

        guard let open = line.range(of: "Color(red: ") else {
            return XCTFail("bentuk Palette.info tak terduga: \(line)")
        }
        let inside = String(line[open.upperBound...])
        // Ambil semua bilangan desimal, abaikan label "green:"/"blue:".
        // Versi pertama memecah dengan `,` lalu `Double(...)` per bagian, dan
        // itu mengembalikan nil untuk dua bagian berlabel — jadi test gagal
        // dengan pesan "tidak bisa parse" yang tidak menunjuk ke masalahnya.
        let pattern = "[0-9]+\\.[0-9]+"
        let re = try NSRegularExpression(pattern: pattern)
        let ns = inside as NSString
        let nums = re.matches(in: inside, range: NSRange(location: 0, length: ns.length))
            .compactMap { m -> Double? in
                guard let r = Range(m.range, in: inside) else { return nil }
                return Double(inside[r])
            }
        guard nums.count == 3 else {
            return XCTFail("harus dapat 3 komponen warna dari \(line), dapat \(nums)")
        }

        let (r, g, b) = (nums[0], nums[1], nums[2])
        XCTAssertGreaterThan(b, r, "warna upload harus dominan BIRU, dapat r=\(r) b=\(b)")
        XCTAssertGreaterThan(b, g, "warna upload harus biru dibanding hijau, dapat g=\(g) b=\(b)")
    }
}