import XCTest
@testable import FreePNApp

/// Cara ping cepat memperlakukan tiap tipe node, dan apa yang ARTINYA verdict-nya.
///
/// Fokus test ini bukan pada jaringan (tidak ada soket sungguhan yang dibuka),
/// tapi pada aturan keputusannya — terutama aturan UDP "timeout = hidup" yang
/// jadi keputusan paling berisiko di fitur ini.
final class ServerPingerTests: XCTestCase {
    private func node(_ proto: NodeProtocol, host: String = "1.2.3.4",
                      port: Int = 443) -> ProxyNode {
        ProxyNode(name: "n", proto: proto, host: host, port: port, credential: "c")
    }

    /// Timeout UDP TIDAK boleh berarti mati.
    ///
    /// Server QUIC tidak pernah menjawab paket acak, jadi kalau timeout
    /// diartikan "mati" hampir semua Hysteria2 yang sehat akan ditandai mati —
    /// dan `connect()` ke node yang terbukti mati DITOLAK. User kehilangan
    /// sebagian besar HY2 tanpa jalan membukanya lagi.
    ///
    /// Diuji lewat KEBIJAKAN (`verdictOnTimeout`), bukan lewat jaringan nyata.
    /// Versi pertama memanggil `ServerPinger.ping` ke alamat publik dan
    /// mengharapkan diam; di jaringan tempat test itu dijalankan, alamatnya
    /// dijawab (proxy/captive portal) dan hasilnya `replied(4)` — test gagal
    /// tanpa alasan yang benar. `.blackhole` yang biasa dipakai untuk ini hanya
    /// ada di SDK macOS 14, sedangkan proyek ini target macOS 13. Aturannya
    /// murni kebijakan, jadi begitu juga cara mengujinya.
    func testUDPTimeoutVerdictIsAliveNotDead() {
        let v = ServerPinger.verdictOnTimeout(for: .hysteria2)
        guard case .aliveUpperBound = v else {
            return XCTFail("HY2 timeout harus jadi aliveUpperBound, bukan \(v)")
        }
        XCTAssertNotEqual(v, .dead,
                          "HY2 yang diam tidak boleh ditandai mati — itu menolak connect ke node sehat")
    }

    /// Sebaliknya, timeout TCP TETAP berarti mati: tidak ada handshake = tidak
    /// ada bukti server hidup. Inilah yang membuat mode cepat berguna untuk
    /// menyingkirkan server yang benar-benar sudah padam.
    func testTCPTimeoutVerdictIsDead() {
        for proto: NodeProtocol in [.trojan, .vmess, .vless, .shadowsocks, .http, .socks] {
            XCTAssertEqual(ServerPinger.verdictOnTimeout(for: proto), .dead,
                           "\(proto) timeout harus mati")
        }
    }

    /// TCP yang benar-benar hidup harus melaporkan RTT, dan RTT-nya bukan
    /// perkiraan — inilah yang membuat `approximate` hanya muncul di jalur UDP.
    func testTCPPathNeverReturnsAnUpperBound() async {
        // Loopback dengan port yang jelas-jelas tidak ada service: handshakenya
        // ditolak seketika (RST), jadi bukan timeout. Yang diuji di sini hanya
        // satu hal: jalur TCP tidak pernah boleh mengembalikan `aliveUpperBound`,
        // karena verdict itu bukan pengukuran sama sekali.
        let outcome = await ServerPinger.ping(node(.trojan, host: "127.0.0.1", port: 1),
                                              timeout: 1)
        switch outcome {
        case .replied(let ms):
            XCTAssertGreaterThan(ms, 0, "RTT harus positif")
        case .aliveUpperBound:
            XCTFail("jalur TCP tidak boleh mengembalikan batas atas")
        case .dead:
            break   // RST seketika juga benar: tidak ada service di port itu
        }
    }

    /// Node dengan host/port tidak valid harus ditolak SEBELUM ada soket dibuka.
    /// Menembak `NWConnection` ke host kosong Known gagal pelan-pelan dan
    /// membakar timeout penuh untuk tiap node korup di feed.
    func testInvalidEndpointIsRejectedImmediately() async {
        let start = Date()
        for n in [node(.trojan, host: "", port: 443),
                  node(.trojan, host: "1.2.3.4", port: 0),
                  node(.trojan, host: "1.2.3.4", port: 70000),
                  node(.hysteria2, host: "", port: 443)] {
            let outcome = await ServerPinger.ping(n, timeout: 3)
            XCTAssertEqual(outcome, .dead)
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.0,
                          "endpoint tidak valid harus gagal sekilas, bukan menunggu timeout")
    }

    /// Batas atas yang ditampilkan harus sama dengan deadline yang benar-benar
    /// dipakai — kalau tidak, angkanya tidak berarti apa-apa.
    func testUpperBoundMatchesConfiguredTimeout() {
        XCTAssertEqual(Int(AppConstants.serverPingUDPTimeout * 1000),
                       AppConstants.serverPingUDPTimeoutMs)
    }
}
