import XCTest
@testable import FreePNApp

/// Semantik inklusif/eksklusif ala Windscribe (daftar app dipakai app untuk pratinjau/test).
final class SplitDecisionTests: XCTestCase {
    func testInclusiveOnlyListed() {
        XCTAssertTrue(SplitDecision.shouldProxy(signingID: "com.apple.Safari", mode: .inclusive, appIDs: ["com.apple.Safari"]))
        XCTAssertFalse(SplitDecision.shouldProxy(signingID: "com.apple.Mail", mode: .inclusive, appIDs: ["com.apple.Safari"]))
    }

    func testExclusiveAllExceptListed() {
        XCTAssertFalse(SplitDecision.shouldProxy(signingID: "com.apple.Safari", mode: .exclusive, appIDs: ["com.apple.Safari"]))
        XCTAssertTrue(SplitDecision.shouldProxy(signingID: "com.apple.Mail", mode: .exclusive, appIDs: ["com.apple.Safari"]))
    }

    func testTeamPrefixMatch() {
        // Pihak ketiga: signing ID "TEAMID.com.example.app" cocok dengan entri bundle ID.
        XCTAssertTrue(SplitDecision.shouldProxy(signingID: "ABCDE12345.com.example.app", mode: .inclusive, appIDs: ["com.example.app"]))
        XCTAssertTrue(SplitDecision.shouldProxy(signingID: "ABCDE12345.COM.EXAMPLE.APP", mode: .inclusive, appIDs: ["com.example.app"]))
    }

    func testNilIdentityFollowsDefault() {
        XCTAssertTrue(SplitDecision.shouldProxy(signingID: nil, mode: .exclusive, appIDs: ["x"]))
        XCTAssertFalse(SplitDecision.shouldProxy(signingID: nil, mode: .inclusive, appIDs: ["x"]))
    }

    func testEmptyList() {
        // Eksklusif kosong = VPN penuh; inklusif kosong = bypass semua (ditolak UI).
        XCTAssertTrue(SplitDecision.shouldProxy(signingID: "com.apple.Safari", mode: .exclusive, appIDs: []))
        XCTAssertFalse(SplitDecision.shouldProxy(signingID: "com.apple.Safari", mode: .inclusive, appIDs: []))
    }
}
