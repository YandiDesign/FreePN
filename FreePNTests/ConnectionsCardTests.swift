import XCTest
@testable import FreePNApp

/// Kartu "Koneksi Aktif" (pengganti strip rekomendasi): parse body
/// `GET /connections` Clash API, nama app dari `processPath`, dan laju dari
/// selisih snapshot.
///
/// Tanpa ini, satu field tak terduga dari sing-box (mis. `download` jadi
/// Double, `host` kosong) bisa mengosongkan seluruh kartu — dan bug sesi
/// probe (semua verdict `skipped`, "0 hidup") tidak punya kunci regresi.
final class ConnectionsCardTests: XCTestCase {
    private func sampleJSON() -> Data {
        """
        {"connections": [
          {"id": "a1", "download": 2710, "upload": 10672, "chains": ["direct"],
           "metadata": {"host": "ws.chatgpt.com", "destinationIP": "104.18.39.21",
             "destinationPort": "443", "network": "TCP",
             "processPath": "/Applications/Arc.app/Contents/Frameworks/ArcCore.framework/Versions/A/Helpers/Browser Helper.app/Contents/MacOS/Browser Helper"}},
          {"id": "b2", "download": 23880, "upload": 10884,
           "metadata": {"host": "", "destinationIP": "8.8.8.8",
             "destinationPort": "443", "network": "udp",
             "processPath": "/Applications/Warp.app/Contents/MacOS/stable"}},
          {"id": "", "download": 1, "upload": 1, "metadata": {}},
          {"id": "c3", "metadata": {}}
        ]}
        """.data(using: .utf8)!
    }

    // MARK: - Decode

    func testDecodeKeepsValidEntries() {
        let rows = ConnectionsFetcher.decode(sampleJSON())
        XCTAssertEqual(rows.map(\.id), ["a1", "b2", "c3"])
    }

    func testDecodePrefersHostFallsBackToIP() {
        let rows = ConnectionsFetcher.decode(sampleJSON())
        XCTAssertEqual(rows[0].host, "ws.chatgpt.com")
        XCTAssertEqual(rows[1].host, "8.8.8.8")
        XCTAssertEqual(rows[2].host, "-")
    }

    func testDecodeNormalizesNetworkAndNumbers() {
        let rows = ConnectionsFetcher.decode(sampleJSON())
        XCTAssertEqual(rows[0].network, "tcp")
        XCTAssertEqual(rows[0].download, 2710)
        XCTAssertEqual(rows[0].upload, 10672)
        XCTAssertEqual(rows[2].download, 0)
    }

    func testDecodeRejectsGarbage() {
        XCTAssertTrue(ConnectionsFetcher.decode(Data("bukan json".utf8)).isEmpty)
        XCTAssertTrue(ConnectionsFetcher.decode(Data("{}".utf8)).isEmpty)
    }

    // MARK: - Nama app

    func testHelperProcessShowsBundleApp() {
        XCTAssertEqual(
            ConnectionsFetcher.appDisplayName(processPath:
                "/Applications/Arc.app/Contents/Frameworks/ArcCore.framework/Versions/A/Helpers/Browser Helper.app/Contents/MacOS/Browser Helper"),
            "Arc")
        XCTAssertEqual(
            ConnectionsFetcher.appDisplayName(processPath:
                "/Applications/Notion.app/Contents/Frameworks/Notion Helper.app/Contents/MacOS/Notion Helper"),
            "Notion")
    }

    func testPlainExecutableShowsItsName() {
        XCTAssertEqual(
            ConnectionsFetcher.appDisplayName(processPath: "/Applications/Warp.app/Contents/MacOS/stable"),
            "Warp")
        XCTAssertEqual(
            ConnectionsFetcher.appDisplayName(processPath: "/usr/sbin/mDNSResponder"),
            "mDNSResponder")
        XCTAssertEqual(ConnectionsFetcher.appDisplayName(processPath: ""), "-")
    }

    // MARK: - Laju

    func testFirstSnapshotHasZeroRate() {
        let rows = ConnectionsFetcher.decode(sampleJSON())
        let (entries, snap) = ConnectionsFetcher.withRates(current: rows, previous: [:])
        XCTAssertEqual(entries.count, 3)
        XCTAssertTrue(entries.allSatisfy { $0.rate == 0 })
        XCTAssertEqual(snap.count, 3)
    }

    func testRateComesFromDeltaOverTime() {
        let rows = ConnectionsFetcher.decode(sampleJSON())
        let t0 = Date()
        let (_, snap) = ConnectionsFetcher.withRates(current: rows, previous: [:], now: t0)
        // a1: +2000 down +1000 up dalam 2 detik = 1500 B/s
        var next = rows
        next[0] = ConnectionsFetcher.Raw(id: "a1", host: "h", appName: "a", network: "tcp",
                                          download: rows[0].download + 2000,
                                          upload: rows[0].upload + 1000,
                                          chains: ["proxy"])
        let (entries, _) = ConnectionsFetcher.withRates(current: next, previous: snap,
                                                        now: t0.addingTimeInterval(2))
        let a1 = entries.first { $0.id == "a1" }!
        XCTAssertEqual(a1.rate, 1500, accuracy: 0.001)
        // Urutan: yang berlaju dulu.
        XCTAssertEqual(entries.first?.id, "a1")
    }

    func testCounterResetNeverGoesNegative() {
        let rows = ConnectionsFetcher.decode(sampleJSON())
        let t0 = Date()
        let (_, snap) = ConnectionsFetcher.withRates(current: rows, previous: [:], now: t0)
        var next = rows
        next[0] = ConnectionsFetcher.Raw(id: "a1", host: "h", appName: "a", network: "tcp",
                                          download: 0, upload: 0, chains: ["proxy"])
        let (entries, _) = ConnectionsFetcher.withRates(current: next, previous: snap,
                                                        now: t0.addingTimeInterval(2))
        XCTAssertEqual(entries.first { $0.id == "a1" }?.rate, 0)
    }

    // MARK: - Hanya lewat VPN

    /// Dengan split tunnel, koneksi `direct` (bypass) tidak boleh tampil di
    /// kartu — kalau tidak user tidak bisa bedakan yang dilindungi VPN.
    func testVpnOnlyDropsDirectBlockAndDnsOut() {
        let rows = ConnectionsFetcher.decode(sampleJSON())
        // Sampel: a1 dan b2 direct, c3 tanpa chains.
        XCTAssertTrue(ConnectionsFetcher.vpnOnly(rows).isEmpty)
    }

    func testVpnOnlyKeepsProxyChains() {
        let rows = [
            ConnectionsFetcher.Raw(id: "p", host: "x.com", appName: "A", network: "tcp",
                                    download: 10, upload: 10, chains: ["proxy"]),
            ConnectionsFetcher.Raw(id: "d", host: "y.com", appName: "B", network: "tcp",
                                    download: 10, upload: 10, chains: ["direct"]),
            ConnectionsFetcher.Raw(id: "b", host: "z.com", appName: "C", network: "tcp",
                                    download: 10, upload: 10, chains: ["block"]),
            ConnectionsFetcher.Raw(id: "n", host: "w.com", appName: "D", network: "udp",
                                    download: 10, upload: 10, chains: ["dns-out"]),
            ConnectionsFetcher.Raw(id: "e", host: "v.com", appName: "E", network: "tcp",
                                    download: 10, upload: 10, chains: []),
        ]
        XCTAssertEqual(ConnectionsFetcher.vpnOnly(rows).map(\.id), ["p"])
    }

    // MARK: - Kunci regresi bug ping internet "0 hidup"

    /// `httpMaximumConnectionsPerHost = 0` berarti TIDAK ADA koneksi yang
    /// boleh dibuat (macOS 13, diverifikasi empiris: shared→200, =0→timeout,
    /// =10→200) — bukan "tanpa batas". Akibatnya setiap sampel probe timeout
    /// → `.coreDown` → `.skipped` untuk semua node → "0 hidup, tidak ada
    /// ping" padahal node sehat. Nilai ini harus selalu di atas jendela
    /// governor (puluhan slot ke host loopback yang sama).
    func testProbeSessionAllowsEnoughConnections() {
        XCTAssertGreaterThan(RealDelayTester.maxProbeConnectionsPerHost, 32)
    }
}
