import XCTest
import Darwin
@testable import FreePNApp

/// Settings.json yang sudah ada milik user TIDAK boleh reset atau gagal decode
/// kalau ada key baru yang belum ada di file lamanya.
final class AppSettingsTests: XCTestCase {
    private func decode(_ json: String) throws -> AppSettings {
        try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
    }

    /// Regresi upgrade: settings lama (tanpa `uiScalePercent`) tetap utuh
    /// nilainya, skala kembali ke 100% — bukan gagal load / reset semua.
    func testLegacyJSONWithoutUIScaleDecodes() throws {
        let s = try decode("""
        {"language":"id","launchAtLogin":true,"autoRefreshHours":3,"pingConcurrency":64,
         "autoReconnect":false,"showPublicIP":true,"autoSortAfterPing":false,"hideDeadNodes":true}
        """)
        XCTAssertEqual(s.uiScalePercent, 100, "settings lama harus dapat skala default")
        XCTAssertEqual(s.language, .id)
        XCTAssertEqual(s.autoRefreshHours, 3)
        // `pingConcurrency` dihapus di D45 — key lama di settings.json HARUS
        // diabaikan diam-diam, bukan bikin seluruh pengaturan gagal load.
        XCTAssertEqual(s.autoRefreshHours, 3)
        XCTAssertFalse(s.autoReconnect)
        XCTAssertTrue(s.launchAtLogin)
        XCTAssertTrue(s.hideDeadNodes)
    }

    /// Regresi upgrade untuk D52: settings lama tidak punya `showNodePort`.
    /// Kalau pakai `decode` biasa, seluruh settings user akan gagal load dan
    /// kembali ke default — termasuk toggle privasi yang sudah dikonfigurasi.
    func testLegacyJSONWithoutShowNodePortDecodes() throws {
        let s = try decode("""
        {"language":"id","autoReconnect":false,"showPublicIP":true,"hideDeadNodes":true}
        """)
        XCTAssertTrue(s.showNodePort, "file lama harus dapat default (port tampil)")
        XCTAssertTrue(s.showPublicIP, "setting lain tidak boleh ikut ter-reset")
        XCTAssertFalse(s.autoReconnect)
    }

    /// Toggle harus benar-benar bertahan: encode → decode tidak boleh
    /// membalikkan nilainya.
    func testShowNodePortRoundTrips() throws {
        var s = AppSettings()
        s.showNodePort = false
        let data = try JSONEncoder().encode(s)
        XCTAssertFalse(try JSONDecoder().decode(AppSettings.self, from: data).showNodePort)
        s.showNodePort = true
        let data2 = try JSONEncoder().encode(s)
        XCTAssertTrue(try JSONDecoder().decode(AppSettings.self, from: data2).showNodePort)
    }

    /// Regresi upgrade saat mode ping cepat masuk: `settings.json` milik user
    /// yang sudah ada tidak punya key `fastPing`. Kalau `decode` biasa, seluruh
    /// pengaturan kembali ke default.
    func testLegacyJSONWithoutFastPingDecodes() throws {
        let s = try decode("""
        {"language":"id","autoReconnect":false,"showPublicIP":true,"hideDeadNodes":true,
         "showNodePort":false}
        """)
        XCTAssertFalse(s.fastPing, "file lama harus dapat default (cek internet, bukan ping cepat)")
        XCTAssertFalse(s.showNodePort, "setting lain tidak boleh ikut ter-reset")
        XCTAssertTrue(s.hideDeadNodes)
    }

    func testFastPingRoundTrips() throws {
        for v in [true, false] {
            var s = AppSettings()
            s.fastPing = v
            let data = try JSONEncoder().encode(s)
            XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: data).fastPing, v)
        }
    }

    /// Default app WAJIB cek internet, bukan ping cepat.
    ///
    /// Ini yang menjaga D27 tetap berlaku secara default: node dengan
    /// kredensial salah tetap saja lolos ping cepat, dan hanya cek internet
    /// yang bisa menangkapnya. Mengubah default diam-diam akan mengembalikan
    /// bug "connect sukses tapi tidak bisa memakai apa pun" tanpa user pernah
    /// menyalakan fitur apa pun.
    func testFastPingDefaultsToInternetCheck() {
        XCTAssertFalse(AppSettings().fastPing)
    }

    func testUIScaleRoundTrips() throws {        for pct in [100, 110, 120, 130, 140, 150] {
            var s = AppSettings()
            s.uiScalePercent = pct
            let data = try JSONEncoder().encode(s)
            XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: data).uiScalePercent, pct)
        }
    }

    /// Nilai aneh (file rusak / versi app lain) tidak boleh membuat seluruh
    /// settings gagal terbaca, dan skala tetap dibatasi 100…150 langkah 10.
    func testInvalidUIScaleFallsBackAndClamps() throws {
        XCTAssertEqual(try decode("{\"uiScalePercent\":\"gigantic\"}").uiScalePercent, 100)
        XCTAssertEqual(try decode("{\"uiScalePercent\":9999}").uiScalePercent, 150)
        XCTAssertEqual(try decode("{\"uiScalePercent\":10}").uiScalePercent, 100)
        XCTAssertEqual(try decode("{\"uiScalePercent\":117}").uiScalePercent, 120,
                       "harus dibulatkan ke langkah 10")
    }

    /// Skala harus benar-benar mengalikan ukuran teks: 150% = 1.5×, 100% = 1×.
    func testScaleFactorMath() {
        XCTAssertEqual(AppUIScale.factor(100), 1.0, accuracy: 0.001)
        XCTAssertEqual(AppUIScale.factor(110), 1.1, accuracy: 0.001)
        XCTAssertEqual(AppUIScale.factor(150), 1.5, accuracy: 0.001)
        XCTAssertEqual(AppUIScale.clamp(999), 150)
        XCTAssertEqual(AppUIScale.clamp(0), 100)
    }

    /// `Theme.font` mengikuti skala global — inilah yang membuat SELURUH UI
    /// membesar, karena semua text style melewati fungsi ini.
    ///
    /// Diuji sebagai RASIO (150% harus jadi 1.5 kali), bukan angka absolut:
    /// ukuran dasar berasal dari setelan teks Apple, bisa berbeda antar mesin.
    func testThemeFontScalesWithUIScale() {
        defer { Theme.uiScale = 1.0 }
        Theme.uiScale = 1.0
        _ = Theme.pointSize(.body)   // pemanasan NSFont.preferredFont
        let bodyNormal = Theme.pointSize(.body)
        let captionNormal = Theme.pointSize(.caption)
        XCTAssertGreaterThan(bodyNormal, 0)

        Theme.uiScale = 1.5
        XCTAssertEqual(Theme.pointSize(.body) / bodyNormal, 1.5, accuracy: 0.01,
                       "skala 150% harus jadi 1.5× ukuran teks")
        XCTAssertEqual(Theme.pointSize(.caption) / captionNormal, 1.5, accuracy: 0.01)

        Theme.uiScale = 1.1
        XCTAssertEqual(Theme.pointSize(.body) / bodyNormal, 1.1, accuracy: 0.01,
                       "skala 110% harus jadi 1.1×")
    }
}

/// Legacy `settings.json` yang masih menyimpan key knob ping yang sudah dihapus
/// harus tetap bisa dibaca tanpa error dan tanpa efek samping.
final class LegacySettingsPingTests: XCTestCase {
    /// D45 menghapus `pingConcurrency`, D48 menghapus "Node per batch",
    /// D50 menghapus seluruh jalur TCP. Key yang tidak dikenal diabaikan
    /// JSONDecoder — settings lama user tidak boleh gagal load karena itu.
    func testLegacyPingKeysAreIgnoredNotFatal() throws {
        let json = """
        {"pingBatchSize":500,"pingConcurrency":64,"cpuSharePercent":100,
         "adaptiveConcurrency":true,"hideDeadNodes":true}
        """
        let s = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        XCTAssertEqual(s.cpuSharePercent, 100, "key lain tak boleh ikut hilang")
        XCTAssertTrue(s.adaptiveConcurrency)
        XCTAssertTrue(s.hideDeadNodes)
    }
}

/// D50 — konkurensi Ping All kini 100% milik governor, dan hanya ada SATU
/// jatah: slot uji internet. Inilah yang membuat Settings "Performance" benar-
/// benar authoritative, karena tidak ada lagi pemotong di tempat lain.
final class PingConcurrencyOwnershipTests: XCTestCase {

    /// 6 core @100% = 6 × 4 × 2 = 48 slot uji.
    func testComputeBudgetComesOnlyFromGovernor() {
        for share in [25, 50, 75, 100] {
            XCTAssertGreaterThan(CPUGovernor.computeLimit(cores: 6, share: Double(share) / 100.0),
                                 CPUGovernor.minCompute)
        }
        XCTAssertEqual(CPUGovernor.computeLimit(cores: 6, share: 1.0), 48)
    }

    /// Jaring pengaman FD: kalau `raiseFileDescriptorLimit()` gagal (environment
    /// yang mengunci hard limit), governor harus tetap memotong jumlah slot.
    /// Tanpa itu, FD habis di tengah uji dan node hidup ikut ditandai mati.
    func testComputeLimitNeverExceedsFileDescriptorBudget() {
        var lim = rlimit()
        getrlimit(RLIMIT_NOFILE, &lim)
        let soft = Int(lim.rlim_cur)
        let budget = max(CPUGovernor.minCompute,
                         (soft - 32) / max(1, AppConstants.fileDescriptorsPerTest))
        let mau = CPUGovernor.computeLimit(cores: 64, share: 1.0)
        XCTAssertLessThanOrEqual(mau, max(budget, CPUGovernor.minCompute),
                                 "slot uji tidak boleh melebihi budget FD")
    }

    /// Menaikkan batas FD sendiri harus selalu berhasil di macOS (hard limit
    /// `unlimited`), dan idempoten — aman dipanggil berkali-kali.
    func testRaiseFileDescriptorLimitIsSafeAndIdempotent() {
        let first = AppConstants.raiseFileDescriptorLimit()
        let second = AppConstants.raiseFileDescriptorLimit()
        XCTAssertTrue(second, "panggilan kedua harus aman (idempoten)")

        var lim = rlimit()
        getrlimit(RLIMIT_NOFILE, &lim)
        XCTAssertGreaterThan(Int(lim.rlim_cur), 0)
        XCTAssertLessThanOrEqual(lim.rlim_cur, lim.rlim_max,
                                 "tidak boleh melewati hard limit")
        if first { XCTAssertEqual(lim.rlim_cur, lim.rlim_max) }
    }

    /// Governor yang turun (AIMD) tetap boleh mengurangi slot uji — sehingga
    /// Settings "Performance" bisa menjerat mesin yang sedang sibuk.
    func testGovernorCanStillThrottleDown() {
        let start = CPUGovernor.computeLimit(cores: 6, share: 1.0)
        let steps = stride(from: start, through: CPUGovernor.minCompute, by: -1)
            .map { CPUGovernor.nextLimit(current: $0, load: 0.9, share: 1.0, max: start) }
        XCTAssertEqual(steps.last, CPUGovernor.minCompute, "AIMD harus bisa turun sampai minimum")
    }
}

/// Rumus biaya restart sesi probe.
///
/// Setiap sesi = tulis config 300 outbound + jalankan subprocess
/// `sing-box check` + spawn sing-box + tunggu API siap. Jadi ini murni
/// BIAYA TETAP per sesi, dan hanya cara 하나 menguranginya: memperbesar
/// jendela sesi (dibatasi beratnya config sing-box).
final class ProbeSessionRestartTests: XCTestCase {

    /// D50: tidak ada lagi pemotong batch — jadi restart = ceil(total /
    /// sessionSize) dan tidak ada lagi parameter yang bisa mengubahnya diam-diam.
    ///
    /// D91: `sessionSize` 300 -> 600 (diukur: config 267 KB masih `sing-box
    /// check` dalam 0,66 dtk). Angka mutlak di bawah mengikuti nilai itu.
    func testRestartCountIsCeilingOfTotalOverSessionSize() {
        for total in [1, 599, 600, 601, 1200, 6000, 21965] {
            XCTAssertEqual(InternetProbe.sessionRestarts(total: total),
                           (total + InternetProbe.sessionSize - 1) / InternetProbe.sessionSize,
                           "total \(total)")
        }
        XCTAssertEqual(InternetProbe.sessionRestarts(total: 6000), 10)
        // Daftar 20.000+ node harus tetap bisa ditangani dalam jumlah sesi
        // yang masuk akal — inilah yang membuat Ping All terasa mustahil
        // sebelum D91.
        XCTAssertLessThanOrEqual(InternetProbe.sessionRestarts(total: 21965), 40)
    }

    /// cases kecil harus aman: nol node = nol sesi, dan tidak pernah negatif.
    func testEdgeCountsAreSafe() {
        XCTAssertGreaterThan(InternetProbe.sessionSize, 0)
        XCTAssertEqual(InternetProbe.sessionRestarts(total: 0), 0)
        XCTAssertEqual(InternetProbe.sessionRestarts(total: -5), 0)
        XCTAssertEqual(InternetProbe.sessionRestarts(total: 1), 1)
    }
}

/// Aturan konkurensi adaptif: harus menghormati jatah CPU dan tidak pernah
/// keluar dari batas keras (governor yang macet = app yang macet).
final class CPUGovernorTests: XCTestCase {
    func testComputeLimitGrowsWithCores() {
        let weak = CPUGovernor.computeLimit(cores: 4, share: 0.5)
        let strong = CPUGovernor.computeLimit(cores: 16, share: 0.5)
        XCTAssertGreaterThan(strong, weak, "mesin lebih kuat = boleh lebih banyak")
        XCTAssertGreaterThanOrEqual(weak, CPUGovernor.minCompute, "mesin kecil tetap dapat minimum")
    }

    /// D45: TIDAK ada plafon keras selain batas FD nyata. Mesin besar boleh
    /// membuka jauh lebih banyak slot; yang menghentikan adalah AIMD membaca
    /// beban CPU nyata.
    func testNoHardCeilingOnBigMachine() {
        XCTAssertGreaterThan(CPUGovernor.computeLimit(cores: 64, share: 1.0), 200)
    }

    /// AIMD tidak boleh keluar dari plafon yang dihitung dari core × porsi CPU.
    func testAdaptiveLimitStaysInsideCoreDerivedCeiling() {
        let ceiling = CPUGovernor.computeLimit(cores: 8, share: 0.5)
        for load in stride(from: 0.0, through: 1.0, by: 0.05) {
            let v = CPUGovernor.nextLimit(current: ceiling, load: load, share: 0.5, max: ceiling)
            XCTAssertLessThanOrEqual(v, ceiling, "load \(load)")
            XCTAssertGreaterThanOrEqual(v, 1, "load \(load)")
        }
    }

    func testShareScalesBudget() {
        XCTAssertLessThan(CPUGovernor.computeLimit(cores: 8, share: 0.25),
                          CPUGovernor.computeLimit(cores: 8, share: 1.0))
    }

    func testRaisesLimitOnIdleMachine() {
        let next = CPUGovernor.nextLimit(current: 40, load: 0.05, share: 0.5, max: 512)
        XCTAssertGreaterThan(next, 40, "mesin adem harus menambah tekanan")
    }

    func testHoldsLimitInsideBudget() {
        XCTAssertEqual(CPUGovernor.nextLimit(current: 40, load: 0.40, share: 0.5, max: 256), 40)
    }

    func testBacksOffWhenOverBudget() {
        // Di atas jatah -> turun; jauh di atas jatah -> turun drastis.
        XCTAssertLessThan(CPUGovernor.nextLimit(current: 64, load: 0.62, share: 0.5, max: 256), 64)
        let hot = CPUGovernor.nextLimit(current: 64, load: 0.95, share: 0.5, max: 256)
        XCTAssertLessThanOrEqual(hot, 32, "jenuh harus turun cepat")
    }

    func testNeverExceedsCeilingOrDropsBelowOne() {
        for load in stride(from: 0.0, through: 1.0, by: 0.05) {
            let v = CPUGovernor.nextLimit(current: 10, load: load, share: 0.5, max: 32)
            XCTAssertGreaterThanOrEqual(v, 1, "load \(load)")
            XCTAssertLessThanOrEqual(v, 32, "load \(load)")
        }
        // Nilai tak masuk akal (limit 0, ceiling < min) tidak boleh bikin crash.
        XCTAssertGreaterThanOrEqual(CPUGovernor.nextLimit(current: 0, load: 0.9, share: 0.5, max: 4), 1)
    }

    func testMeterProducesPlausibleLoad() {
        // Dua sampel berurutan: yang kedua harus mengembalikan nilai 0…1.
        _ = CPUMeter.load()
        if let l = CPUMeter.load() {
            XCTAssertGreaterThanOrEqual(l, 0)
            XCTAssertLessThanOrEqual(l, 1)
        }
        XCTAssertGreaterThanOrEqual(CPUMeter.performanceCores, 1)
    }
}

/// Keputusan hasil ping harus bisa diuji tanpa menjalankan core, jadi aturan
/// "mana yang layak dipakai" diekstrak jadi fungsi murni di `AppState`.
///
/// Ini penjaga utama D50: begitu tahap TCP dihapus, `latencyMs` tidak ada
/// lagi, jadi semua tempat yang dulu membedakan "port hidup" dari "bisa
/// internet" menjadi satu keadaan — dan itu tidak boleh berarti node yang
/// belum pernah diuji ikut tersingkir.
final class PingVerdictRoutingTests: XCTestCase {
    private let nodes: [ProxyNode] = ["ok1", "ok2", "dead", "fresh"].map {
        ProxyNode(id: $0, name: $0, proto: .trojan, host: "1.2.3.4", port: 443,
                  credential: "c", sourceID: "s")
    }

    /// "fresh" sengaja tidak punya entry — itu keadaan paling sering di app
    /// yang baru di-refresh.
    private var ping: [String: PingResult] {
        [
            "ok1": PingResult(nodeID: "ok1").applying(.ok(320)),
            "ok2": PingResult(nodeID: "ok2").applying(.ok(90)),
            "dead": PingResult(nodeID: "dead").applying(.noInternet),
        ]
    }

    /// "Sembunyikan yang mati" hanya boleh menyembunyikan yang TERBUKTI mati.
    func testHideDeadKeepsUntestedNodes() {
        XCTAssertTrue(AppState.isUsable(nil), "belum diuji bukan berarti mati")
        XCTAssertTrue(AppState.isUsable(PingResult(nodeID: "x")), "entry tanpa verdict = belum diuji")
        XCTAssertTrue(AppState.isUsable(PingResult(nodeID: "x").applying(.ok(120))))
        XCTAssertFalse(AppState.isUsable(PingResult(nodeID: "x").applying(.noInternet)))
    }

    /// Quick Connect selalu ambil yang paling cepat di antara node yang terbukti
    /// bisa internet — bukan yang paling cepat secara nama.
    func testQuickConnectPrefersFastestVerified() {
        XCTAssertEqual(AppState.quickConnectChoice(among: nodes, ping: ping)?.id, "ok2")
    }

    /// Node terbukti mati tidak boleh dipilih selama masih ada yang belum
    /// diuji — connect ke sana hanya membuang waktu.
    func testQuickConnectSkipsProvenDeadNodes() {
        let list = nodes.filter { ["dead", "fresh"].contains($0.id) }
        XCTAssertEqual(AppState.quickConnectChoice(among: list, ping: ping)?.id, "fresh")
    }

    /// Kalau tidak ada yang belum diuji dan semuanya terbukti mati, tetap
    /// mengembalikan sesuatu — UI tidak boleh diam tanpa alasan.
    func testQuickConnectFallsBackWhenEverythingIsKnown() {
        let allDead = nodes.filter { $0.id == "dead" }
        XCTAssertEqual(AppState.quickConnectChoice(among: allDead, ping: ping)?.id, "dead")
        XCTAssertNil(AppState.quickConnectChoice(among: [], ping: ping))
    }
}

/// Kolom IP di menu Server (D52) — `ip` atau `ip:port` sesuai toggle.
final class NodeEndpointTests: XCTestCase {
    private func node(_ host: String, _ port: Int) -> ProxyNode {
        ProxyNode(name: "n", proto: .trojan, host: host, port: port, credential: "c")
    }

    func testWithoutPortShowsBareHost() {
        XCTAssertEqual(node("1.2.3.4", 443).endpoint(includePort: false), "1.2.3.4")
    }

    func testWithPortShowsHostPort() {
        XCTAssertEqual(node("1.2.3.4", 8443).endpoint(includePort: true), "1.2.3.4:8443")
    }

    /// Host tidak selalu IP literal — feed gratis banyak yang pakai domain.
    /// Kolom ini tidak boleh menyembunyikan/mengganti bentuknya.
    func testDomainHostIsShownVerbatim() {
        XCTAssertEqual(node("node.example.com", 443).endpoint(includePort: false),
                       "node.example.com")
        XCTAssertEqual(node("node.example.com", 443).endpoint(includePort: true),
                       "node.example.com:443")
    }

    /// IPv6 mengandung tanda titik dua, jadi pemisah `host:port` bisa ambigu
    /// dibaca. Yang ditampilkan harus tetap apa adanya — tidak ada parsing
    /// ulang di sini, kolom ini cuma teks.
    func testIPv6HostIsNotRewritten() {
        XCTAssertEqual(node("2001:db8::1", 443).endpoint(includePort: false), "2001:db8::1")
        XCTAssertEqual(node("2001:db8::1", 443).endpoint(includePort: true), "2001:db8::1:443")
    }
}

/// Menghapus sumber harus ikut membuang server dari feed itu — kalau tidak,
/// server yatim tetap tampil dengan kolom Sumber berisi id yang tak dikenal.
final class RemoveSourceTests: XCTestCase {
    private func node(_ id: String, _ source: String) -> ProxyNode {
        ProxyNode(id: id, name: id, proto: .trojan, host: "1.2.3.4", port: 443,
                  credential: "c", sourceID: source)
    }

    func testRemovesOnlyNodesOfThatSource() {
        let nodes = [node("a", "s1"), node("b", "s2"), node("c", "s1"), node("d", "s3")]
        let after = AppState.nodesAfterRemovingSource(id: "s1", from: nodes)
        XCTAssertEqual(after.map(\.id), ["b", "d"])
    }

    func testKeepsEverythingWhenSourceHasNoNodes() {
        let nodes = [node("a", "s1"), node("b", "s2")]
        XCTAssertEqual(AppState.nodesAfterRemovingSource(id: "s3", from: nodes).count, 2)
        XCTAssertEqual(AppState.nodesAfterRemovingSource(id: "", from: nodes).count, 2)
    }

    func testEmptyInputIsSafe() {
        XCTAssertTrue(AppState.nodesAfterRemovingSource(id: "s1", from: []).isEmpty)
    }
}

/// Ping All harus memakai PERSIS yang tampil setelah filter (tipe/sumber/cari)
/// aktif — bukan seluruh daftar.
final class PingScopeFilterTests: XCTestCase {
    private let nodes: [ProxyNode] = [
        ProxyNode(id: "t1", name: "T1", proto: .trojan, host: "a.com", port: 443, credential: "c", sourceID: "s1"),
        ProxyNode(id: "t2", name: "T2", proto: .trojan, host: "b.com", port: 443, credential: "c", sourceID: "s2"),
        ProxyNode(id: "v1", name: "V1", proto: .vmess, host: "c.com", port: 443, credential: "c", sourceID: "s1"),
        ProxyNode(id: "s1x", name: "SS", proto: .shadowsocks, host: "d.com", port: 443, credential: "c", sourceID: "s1")
    ]

    func testNoFilterKeepsEverything() {
        XCTAssertEqual(AppState.applyFilters(nodes: nodes, search: "", proto: nil, source: nil).count, 4)
    }

    func testProtoFilterOnly() {
        let r = AppState.applyFilters(nodes: nodes, search: "", proto: .trojan, source: nil)
        XCTAssertEqual(r.map(\.id), ["t1", "t2"])
    }

    func testSourceFilterOnly() {
        let r = AppState.applyFilters(nodes: nodes, search: "", proto: nil, source: "s2")
        XCTAssertEqual(r.map(\.id), ["t2"])
    }

    func testBothFiltersCombined() {
        let r = AppState.applyFilters(nodes: nodes, search: "", proto: .trojan, source: "s1")
        XCTAssertEqual(r.map(\.id), ["t1"], "tipe + sumber harus digabung (AND)")
    }

    func testSearchCombinesWithFilters() {
        let r = AppState.applyFilters(nodes: nodes, search: "b.com", proto: .trojan, source: "s2")
        XCTAssertEqual(r.map(\.id), ["t2"])
        let none = AppState.applyFilters(nodes: nodes, search: "zzz", proto: nil, source: nil)
        XCTAssertTrue(none.isEmpty, "filter tanpa hasil harus kosong, bukan berarti 'semua'")
    }

    /// sources.json versi lama tidak punya keptCount/unsupportedCount —
    /// dua field baru itu wajib opsional supaya daftar sumber user tidak hilang.
    func testLegacySourcesJSONWithoutNewCountersDecodes() throws {
        let json = """
        [{"id":"x","name":"Lama","url":"https://a.example/y.yaml","isStarred":true,
          "isEnabled":true,"isCustom":true,"nodeCount":12,"status":"ok"}]
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let srcs = try JSONDecoder().decode([VPNSubscriptionSource].self, from: data)
        XCTAssertEqual(srcs.count, 1)
        XCTAssertEqual(srcs[0].nodeCount, 12)
        XCTAssertEqual(srcs[0].keptCount, 0)
        XCTAssertEqual(srcs[0].unsupportedCount, 0)
    }

    /// Dua sumber dengan node identik: hanya yang pertama yang dipakai —
    /// sumber kedua harus melaporkan keptCount 0, bukan 0 total.
    func testKeptCountReflectsDedup() {
        let a = ProxyNode(id: "dup", name: "A", proto: .trojan, host: "1.1.1.1", port: 443,
                          credential: "p", sourceID: "s1")
        let b = ProxyNode(id: "dup", name: "B", proto: .trojan, host: "1.1.1.1", port: 443,
                          credential: "p", sourceID: "s2")
        let c = ProxyNode(id: "unik", name: "C", proto: .trojan, host: "2.2.2.2", port: 443,
                          credential: "p", sourceID: "s2")
        let kept = NodeDeduper.dedup([a, b, c])
        var perSource: [String: Int] = [:]
        for n in kept { perSource[n.sourceID, default: 0] += 1 }
        XCTAssertEqual(perSource["s1"], 1)
        XCTAssertEqual(perSource["s2"], 1, "node duplikat tidak boleh dihitung dua kali")
        XCTAssertEqual(kept.count, 2)
    }
}
