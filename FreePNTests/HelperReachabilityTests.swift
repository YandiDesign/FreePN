import XCTest
@testable import FreePNApp

/// Vonis "helper hilang" butuh bukti beruntun, bukan satu timeout.
///
/// Kasus nyata yang berulang: helper sehat (`never exited`, reply 1ms di
/// steady state) tapi app memvonis "tidak merespons (mungkin crash)" —
/// satu transaksi XPC yang tersendat (helper sedang stop/start core)
/// langsung membanting status. Aturannya dikunci di sini sebagai unit murni.
final class HelperReachabilityTests: XCTestCase {
    func testFreshInstanceIsNotDead() {
        XCTAssertFalse(HelperReachability().presumedDead)
    }

    func testSingleFailureIsForgiven() {
        var r = HelperReachability()
        r.record(success: false)
        XCTAssertFalse(r.presumedDead, "satu transient tidak boleh jadi vonis mati")
    }

    func testTwoConsecutiveFailuresMeanDead() {
        var r = HelperReachability()
        r.record(success: false)
        r.record(success: false)
        XCTAssertTrue(r.presumedDead)
    }

    func testSuccessResetsTheCount() {
        var r = HelperReachability()
        r.record(success: false)
        r.record(success: true)
        XCTAssertFalse(r.presumedDead)
        XCTAssertEqual(r.consecutiveFailures, 0)
        // Setelah reset, butuh dua gagal beruntun LAGI.
        r.record(success: false)
        XCTAssertFalse(r.presumedDead)
        r.record(success: false)
        XCTAssertTrue(r.presumedDead)
    }

    func testThresholdIsTwo() {
        XCTAssertEqual(HelperReachability.deathThreshold, 2)
    }
}

/// Target sambung ulang otomatis: node terakhir bila checkbox aktif.
///
/// Mengunci wiring watchdog: core crash + checkbox nyala → sambung ke node
/// terakhir; checkbox mati atau tidak ada node → biarkan error (tidak ada
/// reconnect hantu).
final class AutoReconnectTargetTests: XCTestCase {
    private func node() -> ProxyNode {
        ProxyNode(name: "n", proto: .trojan, host: "h.example", port: 443,
                  credential: "secret", sourceID: "s")
    }

    func testReturnsLastNodeWhenEnabled() {
        let n = node()
        XCTAssertEqual(ConnectionManager.reconnectTarget(autoReconnect: true, lastNode: n), n)
    }

    func testReturnsNilWhenDisabled() {
        XCTAssertNil(ConnectionManager.reconnectTarget(autoReconnect: false, lastNode: node()))
    }

    func testReturnsNilWithoutLastNode() {
        XCTAssertNil(ConnectionManager.reconnectTarget(autoReconnect: true, lastNode: nil))
    }

    /// Reconnect TIDAK PERNAH pindah akun: selalu node terakhir. Pindah akun
    /// mengganti exit IP dan memutus stream yang masih hidup (opencode) —
    /// user memakai akun pilihannya dengan alasan.
    func testNeverSwitchesAccount() {
        let n = node()
        // Tidak ada parameter failover: satu-satunya jawaban adalah node
        // terakhir atau tidak sama sekali.
        XCTAssertEqual(ConnectionManager.reconnectTarget(autoReconnect: true, lastNode: n), n)
    }
}

/// Kapan tunnel boleh di-restart (`ConnectionManager.needsRestart`).
///
/// Core tidak pernah crash (seluruh riwayat exit code=0), tapi restart
/// terjadi berulang: verdict proses/XPC bisa basi (daemon restart →
/// proc=nil, reply hilang sementara) sementara data plane sehat. Restart
/// buta di situ MEMBUAT putus. Kebijakannya: restart hanya bila data plane
/// ikut mati.
final class NeedsRestartTests: XCTestCase {
    func testAliveNeverNeedsRestart() {
        XCTAssertFalse(ConnectionManager.needsRestart(alive: true, apiHealthy: true, tunUp: true))
        XCTAssertFalse(ConnectionManager.needsRestart(alive: true, apiHealthy: false, tunUp: false))
    }

    func testDeadProcessWithHealthyDataPlaneStaysConnected() {
        // Kasus daemon restart: proc=nil ("stopped") padahal core yatim
        // masih meneruskan trafik — restart hanya memutus stream sehat.
        XCTAssertFalse(ConnectionManager.needsRestart(alive: false, apiHealthy: true, tunUp: true))
    }

    func testDeadProcessWithDeadDataPlaneRestarts() {
        XCTAssertTrue(ConnectionManager.needsRestart(alive: false, apiHealthy: false, tunUp: false))
        XCTAssertTrue(ConnectionManager.needsRestart(alive: false, apiHealthy: true, tunUp: false))
        XCTAssertTrue(ConnectionManager.needsRestart(alive: false, apiHealthy: false, tunUp: true))
    }
}
