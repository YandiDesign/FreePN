import XCTest
@testable import FreePNApp

/// Mode ping cepat tidak boleh mengukur ukuran yang tidak diambilnya.
///
/// Handshake TCP membuktikan ada yang menjawab di port itu. Ia tidak
/// membuktikan apa pun soal apakah node itu bisa memproksi. Menandai hasilnya
/// `internetOK = true` membuat ping mengatakan "sehat" untuk node yang connect-nya
/// pasti gagal — persis laporan user: "ping normal semua, tapi tidak bisa
/// konek".
final class FastPingHonestyTests: XCTestCase {

    private func node(_ id: String) -> ProxyNode {
        ProxyNode(id: id, name: id, proto: .trojan, host: "\(id).example.com", port: 443,
                  credential: "pw", tls: TLSOptions(enabled: true, sni: "\(id).example.com"),
                  sourceID: "g1")
    }

    // MARK: - PingResult

    /// `aliveUpperBound` = port terbuka. Itu BUKAN bukti internet working.
    func testPortOpenIsNotReportedAsVerifiedInternet() {
        let r = PingResult(nodeID: "a").applying(ServerPingOutcome.aliveUpperBound(80))
        XCTAssertNil(r.internetOK, "port terbuka != terbukti bisa akses internet")
        XCTAssertTrue(r.approximate)
        XCTAssertEqual(r.webLatencyMs, 80, "angka batas atas tetap berguna untuk mengurutkan")
    }

    /// Port tertutup tetap bukti mati yang sah — TCP yang ditolak memang
    /// mengatakan sesuatu. Jangan jadi "belum diverifikasi" juga.
    func testClosedPortIsStillADeathSentence() {
        let r = PingResult(nodeID: "a").applying(ServerPingOutcome.dead)
        XCTAssertEqual(r.internetOK, false)
        XCTAssertTrue(r.isDeadEnd)
    }

    /// Balasan sungguhan dari probe end-to-end tetap `true`. Jalur jujur tidak
    /// boleh ikut melemah gara-gara perbaikan ini.
    func testRealProbeReplyStillCountsAsVerified() {
        let r = PingResult(nodeID: "a").applying(ServerPingOutcome.replied(120))
        XCTAssertEqual(r.internetOK, true)
        XCTAssertFalse(r.approximate)
        XCTAssertFalse(r.isDeadEnd)
    }

    /// `isDeadEnd` harus tetap salah: node dengan port terbuka tidak boleh
    /// diblokir dari connect — kita hanya tidak boleh MENYATAKAN ia sehat.
    func testPortOpenNodeIsStillConnectable() {
        let r = PingResult(nodeID: "a").applying(ServerPingOutcome.aliveUpperBound(80))
        XCTAssertFalse(r.isDeadEnd)
    }

    /// `bestMs` tetap mengembalikan angka supaya urutan tidak kehilangan
    /// informasi, tapi `tier` tidak boleh menganggapnya seolah-olah terukur.
    func testBestMsStillAvailableForSorting() {
        let r = PingResult(nodeID: "a").applying(ServerPingOutcome.aliveUpperBound(80))
        XCTAssertEqual(r.bestMs, 80)
    }

    // MARK: - Quick Connect

    /// Yang paling merusak: `quickConnectChoice` memakai `internetOK == true`
    /// sebagai tier "verified". Dengan perbaikan ini node port-terbuka TIDAK
    /// lagi masuk tier itu, jadi Quick Connect tidak lagi memilih yang
    /// tercepat-antinya-tidak-bisa-dipakai.
    @MainActor
    func testQuickConnectNeverTreatsPortOpenAsVerified() {
        let nodes = [node("a"), node("b")]
        var ping: [String: PingResult] = [:]
        ping["a"] = PingResult(nodeID: "a").applying(ServerPingOutcome.aliveUpperBound(40))
        ping["b"] = PingResult(nodeID: "b").applying(ServerPingOutcome.replied(900))
        let picked = AppState.quickConnectChoice(among: nodes, ping: ping)
        XCTAssertEqual(picked?.id, "b",
                       "node terukur sungguhan harus mengalahkan port-terbuka yang lebih cepat")
    }

    /// Kalau tidak ada yang terukur sungguhan, node port-terbuka TETAP boleh
    /// dipilih — lebih baik daripada tidak ada pilihan sama sekali.
    @MainActor
    func testPortOpenNodeIsStillSelectableWhenNothingIsVerified() {
        let nodes = [node("a")]
        let ping = ["a": PingResult(nodeID: "a").applying(ServerPingOutcome.aliveUpperBound(40))]
        XCTAssertEqual(AppState.quickConnectChoice(among: nodes, ping: ping)?.id, "a")
    }

    // MARK: - Top by latency

    /// Angka `approximate` tidak boleh menempati tier yang sama dengan RTT
    /// terukur. Kalau tidak, daftar "terbaik" diisi node yang paling tidak
    /// berguna — persis kebalikan dari nama fiturnya.
    func testApproximateLatencyRanksBelowMeasuredOne() {
        let nodes = [node("port"), node("real")]
        let ping: [String: PingResult] = [
            "port": PingResult(nodeID: "port").applying(ServerPingOutcome.aliveUpperBound(40)),
            "real": PingResult(nodeID: "real").applying(ServerPingOutcome.replied(300))
        ]
        let top = AppState.topByLatency(nodes, ping: ping, count: 2)
        XCTAssertEqual(top.map(\.id), ["real", "port"],
                       "node terukur harus mendahului yang cuma port terbuka, walau lebih lambat")
    }

    func testDeadNodeStillRanksLastRegardlessOfNumber() {
        let nodes = [node("dead"), node("real")]
        let ping: [String: PingResult] = [
            "dead": PingResult(nodeID: "dead").applying(ServerPingOutcome.dead),
            "real": PingResult(nodeID: "real").applying(ServerPingOutcome.replied(300))
        ]
        XCTAssertEqual(AppState.topByLatency(nodes, ping: ping, count: 2).map(\.id),
                       ["real", "dead"])
    }

    /// Zona abu-abu tidak boleh dihapus: node dengan port terbuka tapi tanpa
    /// verifikasi masih boleh mendahului node yang belum pernah diuji.
    func testPortOpenOutranksUntested() {
        let nodes = [node("port"), node("none")]
        let ping: [String: PingResult] = [
            "port": PingResult(nodeID: "port").applying(ServerPingOutcome.aliveUpperBound(400))
        ]
        XCTAssertEqual(AppState.topByLatency(nodes, ping: ping, count: 2).map(\.id),
                       ["port", "none"])
    }
}
