import XCTest
@testable import FreePNApp

/// Builder skrip installer murni (tanpa menyentuh root/osascript).
final class HelperInstallerTests: XCTestCase {
    func testShQuote() {
        XCTAssertEqual(HelperInstaller.shQuote("/tmp/a b"), "'/tmp/a b'")
        XCTAssertEqual(HelperInstaller.shQuote("a'b"), "'a'\\''b'")
        XCTAssertEqual(HelperInstaller.shQuote(""), "''")
    }

    func testInstallScriptContainsSteps() {
        let s = HelperInstaller.installScript(
            helperSrc: "/A/My App/FreePNHelper", coreSrc: "/A/sing-box")
        // Path ber-spasi ter-quote.
        XCTAssertTrue(s.contains("'/A/My App/FreePNHelper'"))
        // Langkah kunci root.
        XCTAssertTrue(s.contains("mkdir -p"))
        XCTAssertTrue(s.contains("/Library/PrivilegedHelperTools/com.freepn.helper"))
        XCTAssertTrue(s.contains("chown root:wheel"))
        XCTAssertTrue(s.contains("launchctl bootstrap system"))
        XCTAssertTrue(s.contains("com.freepn.helper.xpc"))
        // Core dibunuh per-config, bukan per-nama-proses.
        XCTAssertTrue(s.contains("pkill -f 'freepn/config.json'"), s)
    }

    /// `pkill -x sing-box` mematikan SETIAP proses bernama sing-box di mesin,
    /// termasuk milik tool VPN lain milik user. Sing-box keluar dengan kode 0
    /// setelah SIGTERM, jadi tidak ada jejak kegagalan pun — core VPN milik
    /// tool lain mati dengan cara paling sunyi.
    ///
    /// Assertion sebelumnya hanya mengecek string `pkill -x sing-box` ADA di
    /// skrip, dan itu benar selama string itu masih muncul di baris komentar.
    /// Sekarang yang dijamin adalah sebaliknya: di badan skrip yang
    /// benar-benar dieksekusi, `pkill -x` tidak boleh ada sama sekali.
    func testInstallScriptNeverKillsSingBoxByProcessName() {
        let s = HelperInstaller.installScript(
            helperSrc: "/A/helper", coreSrc: "/A/sing-box")
        let executableLines = s.split(separator: "\n").filter { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            return !t.isEmpty && !t.hasPrefix("#")
        }
        for line in executableLines {
            XCTAssertFalse(line.contains("pkill -x"),
                           "skrip install tidak boleh memakai pkill -x: \(line)")
        }
    }
}
