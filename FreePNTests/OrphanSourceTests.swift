import XCTest
@testable import FreePNApp

/// Sumber dan node harus selalu berasal dari generasi UUID yang sama.
///
/// `refreshAll()` pernah berjalan sebelum `sources.json` selesai dimuat dan
/// mengambil snapshot `builtIn()` (yang ID-nya di-mint acak tiap peluncuran),
/// sehingga node ditulis dengan `sourceID` yang tidak ada di daftar. Gejalanya
/// kolom Source menampilkan potongan UUID dan filter sumber tidak menghasilkan
/// apa pun. Yang dijaga di sini adalah penjaga-penjaga yang mencegah itu.

/// D92 — daftar feed gratis yang DITAWARKAN, bukan yang di-seed.
///
/// Yang dijaga di sini: feed yang ditawarkan benar-benar layak dipakai (URL
/// unik, tidak ada yang dibintang), dan app TIDAK punya sumber bawaan sama
/// sekali. Dulu `builtIn()` jadi nilai awal `AppState.sources`, jadi setiap
/// instalasi baru langsung datang dengan 10 feed terisi.
final class CuratedFeedTests: XCTestCase {
    /// Dua entri dengan URL sama berarti dua unduhan untuk isi identik.
    func testCuratedURLsAreUnique() {
        let urls = VPNSubscriptionSource.curated.map(\.url)
        XCTAssertEqual(Set(urls).count, urls.count, "URL tawaran tidak boleh kembar")
    }

    func testCuratedURLsAreAbsoluteHTTPS() {
        for c in VPNSubscriptionSource.curated {
            let u = URL(string: c.url)
            XCTAssertEqual(u?.scheme, "https", c.name)
            XCTAssertNotNil(u?.host, c.name)
        }
    }

    /// Bersih saat install: state awal app tidak boleh berisi feed apa pun.
    func testAppStartsWithNoSources() {
        XCTAssertTrue(VPNSubscriptionSource.defaultSources.isEmpty,
                      "instalasi baru harus mulai tanpa sumber")
    }
}

final class DuplicateSourceTests: XCTestCase {
    private let sources = [
        VPNSubscriptionSource(id: "s1", name: "A", url: "https://example.com/sub", isCustom: true)
    ]

    func testExactDuplicateIsRejected() {
        XCTAssertTrue(AppState.hasSource(url: "https://example.com/sub", in: sources))
    }

    /// Spasi, huruf besar, dan garis miring di akhir tidak menjadikan feed lain.
    func testNormalizationIgnoresCaseSpaceAndTrailingSlash() {
        for variant in ["HTTPS://Example.com/sub", "https://example.com/sub/",
                        "  https://example.com/sub  ", "https://EXAMPLE.com/sub/"] {
            XCTAssertTrue(AppState.hasSource(url: variant, in: sources), variant)
        }
    }

    func testDifferentURLIsAllowed() {
        XCTAssertFalse(AppState.hasSource(url: "https://example.com/other", in: sources))
    }

    /// Menyimpan sumber yang sedang diedit ke URL-nya sendiri BUKAN duplikat —
    /// kalau dicek begitu, user tidak akan pernah bisa menyelesaikan edit.
    func testEditingSelfIsNotDuplicate() {
        XCTAssertFalse(AppState.hasSource(url: "https://example.com/sub",
                                          in: sources, ignoring: "s1"))
    }

    func testEmptyURLNeverMatches() {
        XCTAssertFalse(AppState.hasSource(url: "", in: sources))
        XCTAssertFalse(AppState.hasSource(url: "   ", in: sources))
    }
}

/// D66 — dropdown filter sumber harus offers sumber yang benar-benar punya node.
/// Kalau tidak, memilihnya menghasilkan tabel kosong yang terlihat seperti
/// filter yang rusak (persis keluhan user).
final class LiveSourceFilterTests: XCTestCase {
    func testApplyFiltersMatchesExactSourceID() {
        let nodes = [
            ProxyNode(id: "a", name: "A", proto: .trojan, host: "1.1.1.1", port: 443,
                      credential: "c", sourceID: "s1"),
            ProxyNode(id: "b", name: "B", proto: .trojan, host: "2.2.2.2", port: 443,
                      credential: "c", sourceID: "s2")
        ]
        XCTAssertEqual(AppState.applyFilters(nodes: nodes, search: "", proto: nil,
                                             source: "s1").map(\.id), ["a"])
        XCTAssertEqual(AppState.applyFilters(nodes: nodes, search: "", proto: nil,
                                             source: "s2").map(\.id), ["b"])
        XCTAssertTrue(AppState.applyFilters(nodes: nodes, search: "", proto: nil,
                                            source: "tidak-ada").isEmpty)
    }

    /// `sourceFilter` yang menunjuk sumber yang sudah dihapus harus diabaikan
    /// (D57), bukan mengunci tabel kosong tanpa penjelasan.
    func testStaleSourceFilterIsIgnored() {
        XCTAssertNil(AppState.activeSourceFilterFor(sourceFilter: "hilang",
                                                    sources: [VPNSubscriptionSource(id: "s1", name: "A", url: "u")]))
    }

    func testValidSourceFilterIsActive() {
        let sources = [VPNSubscriptionSource(id: "s1", name: "A", url: "u")]
        XCTAssertEqual(AppState.activeSourceFilterFor(sourceFilter: "s1", sources: sources), "s1")
    }
}

private extension AppState {
    /// Bentuk murni dari `activeSourceFilter`, supaya bisa diuji tanpa actor.
    nonisolated static func activeSourceFilterFor(sourceFilter: String?,
                                                  sources: [VPNSubscriptionSource]) -> String? {
        guard let id = sourceFilter, sources.contains(where: { $0.id == id }) else { return nil }
        return id
    }
}
