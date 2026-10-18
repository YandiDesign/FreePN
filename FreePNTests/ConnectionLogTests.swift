import XCTest
@testable import FreePNApp

/// Snapshot log murni (file temp, tanpa sentuh /tmp sistem).
final class ConnectionLogTests: XCTestCase {
    private func tempFile(_ content: String) -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("freepn-logtest-\(UUID().uuidString).log")
        try! content.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    func testTailLimitsLines() {
        let p = tempFile((1...10).map { "line\($0)" }.joined(separator: "\n"))
        let t = ConnectionLog.tail(of: p, maxLines: 3)
        XCTAssertEqual(t, "line8\nline9\nline10")
    }

    func testTailStripsANSIAndHandlesMissing() {
        let esc = "\u{1B}"
        let p = tempFile(esc + "[31mFATAL" + esc + "[0m boom")
        XCTAssertEqual(ConnectionLog.tail(of: p, maxLines: 10), "FATAL boom")
        XCTAssertFalse(ConnectionLog.tail(of: "/nonexistent/freepn.log", maxLines: 10).isEmpty)
    }

    func testSnapshotContainsBothSections() {
        let h = tempFile("h1")
        let c = tempFile("c1")
        // D75: path legacy ikut di-override ke file yang pasti tidak ada.
        // Tanpa ini `snapshot()` jatuh ke konstanta `/tmp/freepn-*.log` yang
        // bisa berisi apa saja di mesin ini — test jadi tidak hermetik dan
        // bisa gagal karena file nyata milik user.
        let absent = tempFile("tidak-ada-") + ".tidak-ada"
        let s = ConnectionLog.snapshot(header: "HDR", helperPath: h, corePath: c,
                                       legacyHelperPath: absent, legacyCorePath: absent)
        XCTAssertTrue(s.contains("HDR"))
        XCTAssertTrue(s.contains("h1"))
        XCTAssertTrue(s.contains("c1"))
    }
}
