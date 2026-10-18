import XCTest
@testable import FreePNApp

final class ValidatorTests: XCTestCase {
    func testMACFormat() {
        XCTAssertTrue(Validators.isValidMACFormat("aa:bb:cc:dd:ee:ff"))
        XCTAssertTrue(Validators.isValidMACFormat("02:00:00:00:00:01"))
        XCTAssertFalse(Validators.isValidMACFormat("gg:bb:cc:dd:ee:ff"))
        XCTAssertFalse(Validators.isValidMACFormat("aa-bb-cc-dd-ee-ff"))
    }
    func testRandomMACBits() {
        for _ in 0..<50 {
            let m = Validators.randomMAC()
            XCTAssertTrue(Validators.isValidRandomMAC(m), m)
        }
        XCTAssertFalse(Validators.isValidRandomMAC("01:00:00:00:00:00")) // multicast
        XCTAssertFalse(Validators.isValidRandomMAC("00:00:00:00:00:00")) // not locally administered
    }
    func testIface() {
        XCTAssertTrue(Validators.isValidInterface("en0"))
        XCTAssertFalse(Validators.isValidInterface("eth0"))
        XCTAssertFalse(Validators.isValidInterface("en0; rm -rf"))
    }
    func testConfigPath() {
        // Temp user (kasus nyata dari log: helper root menolak path user).
        XCTAssertTrue(Validators.isAllowedConfigPath("/var/folders/gj/llwpymls0c30f84wtkdx_hp00000gn/T/freepn/config.json"))
        XCTAssertTrue(Validators.isAllowedConfigPath("/tmp/freepn/config.json"))
        XCTAssertTrue(Validators.isAllowedConfigPath("/Users/x/Library/Application Support/FreePN/config.json"))
        XCTAssertFalse(Validators.isAllowedConfigPath("/etc/passwd"))
        XCTAssertFalse(Validators.isAllowedConfigPath("/var/folders/gj/T/evil.sh"))
        XCTAssertFalse(Validators.isAllowedConfigPath("/tmp/freepn/config.json; rm -rf"))
    }
}

/// Ping = SATU pengukuran: request internet sungguhan lewat node tersebut.
final class PingResultTests: XCTestCase {
    /// Node yang belum pernah diuji harus tetap bisa direpresentasikan sebagai
    /// "belum ada verdict" — itu berbeda dari "terbukti tidak ada internet".
    func testFreshResultIsUntestedNotDead() {
        let r = PingResult(nodeID: "a")
        XCTAssertNil(r.internetOK)
        XCTAssertNil(r.webLatencyMs)
        XCTAssertFalse(r.isDeadEnd, "belum diuji = bukan bukti mati")
    }

    /// Regresi laporan user: "banyak server hidup tapi pas disambungkan tidak
    /// bisa internet". Node seperti ini harus terdeteksi, bukan lolos.
    func testNodeWithoutInternetIsDeadEnd() {
        let r = PingResult(nodeID: "a").applying(.noInternet)
        XCTAssertTrue(r.isDeadEnd)
        XCTAssertNil(r.bestMs, "tidak ada angka yang boleh ditampilkan seolah-olah end-to-end")
        XCTAssertNil(r.webLatencyMs)
    }

    func testVerifiedLatencyIsTheOnlyNumber() {
        let r = PingResult(nodeID: "a").applying(.ok(310))
        XCTAssertEqual(r.internetOK, true)
        XCTAssertFalse(r.isDeadEnd)
        XCTAssertEqual(r.webLatencyMs, 310)
        XCTAssertEqual(r.bestMs, 310, "latensi yang ditampilkan harus yang terukur end-to-end")
    }

    /// Ping ulang (node pindah server / subscription ulang) harus menimpa
    /// verdict lama dengan hasil baru.
    func testRetestReplacesPreviousVerdict() {
        let dead = PingResult(nodeID: "a").applying(.noInternet)
        XCTAssertTrue(dead.isDeadEnd)
        let back = dead.applying(.ok(95))
        XCTAssertFalse(back.isDeadEnd, "verdict baru harus menggantikan verdict lama")
        XCTAssertEqual(back.bestMs, 95)
        XCTAssertGreaterThanOrEqual(back.at, dead.at)
    }

    /// Probe yang tidak sempat jalan (core hilang / dibatalkan / sesi sedang
    /// dipakai) bukan bukti node mati. Kalau dicatat sebagai mati, connect ke
    /// node bagus ditolak — dan user kehilangan sebagian besar server gratis.
    func testSkippedProbeKeepsPreviousVerdict() {
        let fresh = PingResult(nodeID: "a")
        XCTAssertNil(fresh.applying(.skipped).internetOK)
        XCTAssertFalse(fresh.applying(.skipped).isDeadEnd)
        let known = PingResult(nodeID: "a").applying(.ok(200))
        XCTAssertEqual(known.applying(.skipped).webLatencyMs, 200)
        XCTAssertEqual(known.applying(.ok(120)).webLatencyMs, 120)
        XCTAssertTrue(known.applying(.noInternet).isDeadEnd)
    }

    /// Verdict mode ping cepat TIDAK boleh ikut mengubah jalur cek internet.
    ///
    /// `applying(_: ProbeVerdict)` dipakai `InternetProbe`, yang angkanya jujur
    /// (latensi end-to-end). Kalau `approximate` ikut nyantol di sana, UI akan
    /// menampilkan "≤" untuk hasil yang sebenarnya terukur.
    func testInternetVerdictNeverMarkedApproximate() {
        XCTAssertFalse(PingResult(nodeID: "a").applying(.ok(310)).approximate)
        XCTAssertFalse(PingResult(nodeID: "a").applying(.noInternet).approximate)
    }
}

/// Mode ping cepat: "server merespons", bukan "bisa menjangkau internet".
final class FastPingResultTests: XCTestCase {
    private let fresh = PingResult(nodeID: "a")

    /// TCP yang handshake-nya sukses = RTT sungguhan, boleh tampil polos.
    func testRepliedIsRealMeasurement() {
        let r = fresh.applying(.replied(42))
        XCTAssertEqual(r.webLatencyMs, 42)
        XCTAssertEqual(r.bestMs, 42)
        XCTAssertEqual(r.internetOK, true)
        XCTAssertFalse(r.approximate, "RTT terukur bukan perkiraan")
        XCTAssertFalse(r.isDeadEnd)
    }

    /// Timeout UDP = "tidak ada bukti kematian", BUKAN latensi terukur.
    ///
    /// Dua hal harus berlaku, dan keduanya dulu disatukan jadi satu klaim
    /// yang berlebihan. Menandainya `approximate` mencegah UI menampilkan batas
    /// atas 1.500 ms seolah-olah itu RTT Hysteria2 itu. Dan `internetOK` TIDAK
    /// lagi `true`: UDP yang timeout membuktikan apa pun tentang apakah proxy
    /// itu berfungsi, jadi status yang jujur adalah "belum diverifikasi"
    /// (D96) — bukan "terbukti ada internet".
    ///
    /// Yang TIDAK berubah dan tetap dijaga: bukan dead end, jadi connect ke
    /// sana tidak diblokir.
    func testAliveUpperBoundIsFlaggedNotMeasured() {
        let r = fresh.applying(.aliveUpperBound(1500))
        XCTAssertTrue(r.approximate, "batas atas harus ditandai, bukan ditampilkan polos")
        XCTAssertNil(r.internetOK,
                     "batas atas bukan bukti internet working — jangan diklaim `true`")
        XCTAssertFalse(r.isDeadEnd, "tidak ada bukti kematian = bukan dead end")
        XCTAssertEqual(r.webLatencyMs, 1500)
    }

    func testDeadIsDeadEnd() {
        let r = fresh.applying(.dead)
        XCTAssertTrue(r.isDeadEnd)
        XCTAssertNil(r.bestMs)
        XCTAssertFalse(r.approximate)
    }

    /// Beralih mode harus menimpa `approximate`, bukan menumpuknya.
    ///
    /// Kalau tidak, satu node yang pernah diuji lewat HY2 akan terus menampilkan
    /// "≤" walau kemudian diuji ulang dengan TCP dan menghasilkan RTT asli.
    func testModeSwitchClearsApproximateFlag() {
        let udp = fresh.applying(.aliveUpperBound(1500))
        XCTAssertTrue(udp.approximate)
        let tcp = udp.applying(.replied(60))
        XCTAssertFalse(tcp.approximate, "ping ulang lewat TCP wajib mengubahnya jadi terukur")
        XCTAssertEqual(tcp.webLatencyMs, 60)
    }
}

/// `PingResult` yang sudah tersimpan tanpa key `approximate` (semua versi lama)
/// harus tetap terbaca. Decoder sintesis akan menggagalkan SELURUH decode di
/// sini, dan itu artinya seluruh riwayat ping user hilang diam-diam.
final class PingResultLegacyDecodeTests: XCTestCase {
    private func decode(_ json: String) throws -> PingResult {
        try JSONDecoder().decode(PingResult.self, from: Data(json.utf8))
    }

    func testLegacyJSONWithoutApproximateDecodes() throws {
        let r = try decode("""
        {"nodeID":"a","webLatencyMs":120,"internetOK":true,
         "at":700000000}
        """)
        XCTAssertEqual(r.nodeID, "a")
        XCTAssertEqual(r.webLatencyMs, 120)
        XCTAssertEqual(r.internetOK, true)
        XCTAssertFalse(r.approximate, "file lama pasti hasil pengukuran end-to-end")
    }

    func testApproximateRoundTrips() throws {
        let r = PingResult(nodeID: "a", webLatencyMs: 1500, internetOK: true, approximate: true)
        let back = try JSONDecoder().decode(PingResult.self, from: JSONEncoder().encode(r))
        XCTAssertTrue(back.approximate, "penanda batas atas harus bertahan lewat encode/decode")
    }
}
