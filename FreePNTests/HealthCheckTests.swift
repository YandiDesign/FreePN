import XCTest
@testable import FreePNApp

/// HealthChecker: inklusif-kosong wajib dilaporkan fail (tanpa tergantung helper/XPC).
@MainActor
final class HealthCheckTests: XCTestCase {
    func testInclusiveEmptyReportedAsFail() async {
        let h = HealthChecker()
        await h.check(split: SplitTunnelConfig(mode: .inclusive),
                      coreBinary: "/nonexistent/sing-box")
        let split = h.items.first { $0.id == "split" }
        XCTAssertEqual(split?.level, .fail)
        // 5 item selalu ada: helper, core, split, ports, firewall.
        XCTAssertEqual(h.items.count, 5)
        XCTAssertTrue(h.hasFailure)
    }

    func testExclusiveModeSplitOk() async {
        let h = HealthChecker()
        await h.check(split: SplitTunnelConfig(mode: .exclusive),
                      coreBinary: "/nonexistent/sing-box")
        XCTAssertEqual(h.items.first { $0.id == "split" }?.level, .ok)
    }
}
