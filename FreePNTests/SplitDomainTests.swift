import XCTest
@testable import FreePNApp

/// Split tunneling per-domain: model, normalisasi, dan backwards compatibility.
final class SplitDomainTests: XCTestCase {

    // MARK: - Normalisasi

    /// Bentuk yang diketik user diverse harus berakhir sebagai satu nilai yang
    /// sama. Kalau tidak, `*.Example.com` dan `example.com` jadi dua entri dan
    /// dua "aturan sama" yang tidak saling cocok.
    func testNormalizeCollapsesTheFormsAUserActuallyTypes() {
        let variants = ["example.com", "EXAMPLE.COM", "  Example.Com  ",
                        "*.example.com", ".example.com", "example.com.",
                        "https://example.com", "https://example.com/path?q=1",
                        "http://user:pass@example.com:8080"]
        for v in variants {
            XCTAssertEqual(SplitTunnelConfig.normalizeDomain(v), "example.com",
                           "varian \(v) harusnya berakhir sama")
        }
        // Path dibuang, bukan dianggap tidak valid: user yang menyalin URL dari
        // address bar harus tetap bisa memakainya sebagai split rule.
        XCTAssertEqual(SplitTunnelConfig.normalizeDomain("https://bank.com/login?next=1"),
                       "bank.com")
    }

    func testNormalizeRejectsNonDomains() {
        // Spasi di TENGAH nama host tetap ditolak: membuang spasi diam-diam
        // akan menghasilkan domain yang tidak pernah diketik user.
        for bad in ["", "   ", "notadomain", "http://", "*.", ".", "a b.com",
                    "http://exa mple.com", "bank .com"] {
            XCTAssertNil(SplitTunnelConfig.normalizeDomain(bad), "\(bad) seharusnya ditolak")
        }
    }

    func testNormalizeKeepsSubdomainDepth() {
        XCTAssertEqual(SplitTunnelConfig.normalizeDomain("a.b.c.example.co.id"),
                       "a.b.c.example.co.id")
    }

    func testNormalizeDomainsIsIdempotentAndDedupes() {
        let once = SplitTunnelConfig.normalizeDomains(
            ["Example.com", "*.example.com", "example.com.", "bank.com", "", "  "])
        XCTAssertEqual(once, ["example.com", "bank.com"])
        XCTAssertEqual(SplitTunnelConfig.normalizeDomains(once), once)
    }

    // MARK: - Active / replace

    func testActiveDomainsFollowsMode() {
        let inc = SplitTunnelConfig(mode: .inclusive, inclusiveDomains: ["video.com"])
        XCTAssertEqual(inc.activeDomains, ["video.com"])
        XCTAssertTrue(inc.exclusiveDomains.isEmpty)

        let exc = SplitTunnelConfig(mode: .exclusive, exclusiveDomains: ["bank.com"])
        XCTAssertEqual(exc.activeDomains, ["bank.com"])
    }

    func testDisabledSplitHasNoActiveDomains() {
        let s = SplitTunnelConfig(mode: .exclusive, isEnabled: false,
                                  exclusiveDomains: ["bank.com"])
        XCTAssertTrue(s.activeDomains.isEmpty)
    }

    /// `replaceActive` (untuk app) TIDAK boleh ikut menghapus domain.
    ///
    /// Ini regresi yang paling mungkin terjadi: `replaceActive` sengaja
    /// mengosongkan daftar lawannya, dan `commitStaged` memanggilnya setiap
    /// kali user menekan Save.
    func testReplacingAppsDoesNotWipeDomains() {
        var s = SplitTunnelConfig(mode: .exclusive, exclusiveDomains: ["bank.com"])
        s.replaceActive(with: ["/Applications/Safari.app"])
        XCTAssertEqual(s.exclusiveDomains, ["bank.com"], "Save app menghapus daftar domain")
    }

    /// Dan sebaliknya: `replaceActiveDomains` tidak boleh menyentuh app.
    func testReplacingDomainsDoesNotWipeApps() {
        var s = SplitTunnelConfig(mode: .exclusive,
                                  exclusiveApps: ["/Applications/Safari.app"])
        s.replaceActiveDomains(with: ["Bank.COM"])
        XCTAssertEqual(s.exclusiveApps, ["/Applications/Safari.app"])
        XCTAssertEqual(s.exclusiveDomains, ["bank.com"])
    }

    func testReplaceActiveDomainsMovesListToCurrentMode() {
        var s = SplitTunnelConfig(mode: .inclusive)
        s.mode = .exclusive
        s.replaceActiveDomains(with: ["bank.com", "*.bank.com"])
        XCTAssertEqual(s.exclusiveDomains, ["bank.com"], "duplikat hasil normalisasi harus hilang")
        XCTAssertTrue(s.inclusiveDomains.isEmpty)
    }

    func testHasAnyActiveSelection() {
        XCTAssertFalse(SplitTunnelConfig(mode: .inclusive).hasAnyActiveSelection)
        XCTAssertTrue(SplitTunnelConfig(mode: .inclusive,
                                        inclusiveApps: ["/a.app"]).hasAnyActiveSelection)
        XCTAssertTrue(SplitTunnelConfig(mode: .inclusive,
                                        inclusiveDomains: ["a.com"]).hasAnyActiveSelection)
        // Sakelar mati = tidak ada yang diputuskan.
        XCTAssertFalse(SplitTunnelConfig(mode: .exclusive,
                                         exclusiveApps: ["/a.app"],
                                         isEnabled: false,
                                         exclusiveDomains: ["a.com"]).hasAnyActiveSelection)
    }

    // MARK: - Persistensi

    /// `split.json` versi lama tidak punya key domain sama sekali. Membaca
    /// dengan `decode` (bukan `decodeIfPresent`) akan THROW dan menghapus
    /// seluruh pengaturan split user hanya karena app-nya versi lebih baru.
    func testLegacySplitFileWithoutDomainKeysStillDecodes() throws {
        let json = """
        {"mode":"exclusive","inclusiveApps":[],"exclusiveApps":["/Applications/Safari.app"]}
        """
        let s = try JSONDecoder().decode(SplitTunnelConfig.self, from: Data(json.utf8))
        XCTAssertTrue(s.isEnabled)
        XCTAssertEqual(s.activeApps, ["/Applications/Safari.app"])
        XCTAssertTrue(s.activeDomains.isEmpty)
    }

    func testSplitRoundTripsWithDomains() throws {
        let s = SplitTunnelConfig(mode: .exclusive,
                                  exclusiveApps: ["/Applications/Safari.app"],
                                  isEnabled: true,
                                  exclusiveDomains: ["BANK.com", "*.bank.com"])
        let back = try JSONDecoder().decode(
            SplitTunnelConfig.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back.exclusiveDomains, ["bank.com"], "duplikat tidak boleh dobel setelah encode")
        XCTAssertEqual(back.exclusiveApps, ["/Applications/Safari.app"])
        XCTAssertEqual(back.mode, SplitMode.exclusive)
        XCTAssertTrue(back.isEnabled)
    }

    /// Domain rusak di `split.json` tidak boleh menarik seluruh file.
    func testDomainWithInvalidCharactersIsDroppedNotFatal() throws {
        let json = """
        {"mode":"exclusive","isEnabled":true,"exclusiveDomains":["bank.com","not a domain","","x.com"]}
        """
        let s = try JSONDecoder().decode(SplitTunnelConfig.self, from: Data(json.utf8))
        XCTAssertEqual(s.exclusiveDomains, ["bank.com", "x.com"])
    }
}
