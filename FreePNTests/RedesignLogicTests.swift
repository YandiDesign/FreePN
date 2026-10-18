import XCTest
@testable import FreePNApp

/// Logika yang ditambahkan saat redesign (D53): sakelar utama Split
/// Tunneling, batas riwayat MAC, laju trafik untuk sparkline, nama negara
/// yang terbaca, dan pembantu UI.
///
/// Semuanya murni dan nonisolated supaya bisa diuji tanpa actor, tanpa
/// helper terpasang, dan tanpa menyentuh berkas milik user.
final class RedesignLogicTests: XCTestCase {

    // MARK: - Split Tunneling: sakelar utama

    /// split.json lawas tidak punya key `isEnabled`. Pakai `decode` biasa
    /// akan membuat SELURUH daftar aplikasi hilang hanya karena app
    /// diperbarui — termasuk-mode yang sedang aktif.
    func testLegacySplitFileWithoutIsEnabledKeepsAppsAndMode() throws {
        let legacy = """
        {"mode":"exclusive","inclusiveApps":[],"exclusiveApps":["/Applications/Safari.app"]}
        """
        let decoded = try JSONDecoder().decode(SplitTunnelConfig.self, from: Data(legacy.utf8))
        XCTAssertTrue(decoded.isEnabled, "split lama harus dianggap aktif")
        XCTAssertEqual(decoded.exclusiveApps, ["/Applications/Safari.app"])
        XCTAssertEqual(decoded.activeApps, ["/Applications/Safari.app"])
    }

    /// Sakelar mati = tidak ada aturan per-proses sama sekali.
    func testDisabledSplitHasNoActiveApps() {
        let split = SplitTunnelConfig(mode: .exclusive,
                                      exclusiveApps: ["/Applications/Safari.app"],
                                      isEnabled: false)
        XCTAssertTrue(split.activeApps.isEmpty)
    }

    /// Yang paling mudah salah: mode inklusif tersimpan + sakelar mati.
    /// Efektifnya harus VPN PENUH. Kalau `effectiveMode` mengembalikan mode
    /// apa adanya, `route.final` jadi "direct" dan semua trafik keluar tanpa
    /// VPN — tepat hal yang justru diminta user dengan mematikan split.
    func testDisabledSplitFallsBackToFullVPN() {
        let split = SplitTunnelConfig(mode: .inclusive,
                                      inclusiveApps: ["/Applications/Safari.app"],
                                      isEnabled: false)
        XCTAssertEqual(split.effectiveMode, .exclusive)
        XCTAssertFalse(SingBoxConfigBuilder.isBypassAll(split: split),
                       "split mati = VPN penuh, bukan bypass semua")
    }

    func testEnabledSplitKeepsItsMode() {
        let split = SplitTunnelConfig(mode: .inclusive, inclusiveApps: ["a"])
        XCTAssertEqual(split.effectiveMode, .inclusive)
        XCTAssertFalse(SingBoxConfigBuilder.isBypassAll(split: split))
    }

    /// Split mati tidak boleh menyisakan aturan proses di config.
    func testDisabledSplitWritesNoProcessRule() {
        let rules = SingBoxConfigBuilder().routingRules(
            split: SplitTunnelConfig(mode: .exclusive,
                                     exclusiveApps: ["/Applications/Safari.app"],
                                     isEnabled: false),
            serverIP: "9.9.9.9")
        XCTAssertFalse(rules.contains { $0["process_path_regex"] != nil },
                       "sakelar mati harus menghapus aturan per-aplikasi")
        XCTAssertTrue(SingBoxConfigBuilder().dnsRules(
            split: SplitTunnelConfig(mode: .exclusive,
                                     exclusiveApps: ["/Applications/Safari.app"],
                                     isEnabled: false)).isEmpty)
    }

    /// Config yang dihasilkan harus benar-benar `final=proxy` pada kasus itu.
    func testDisabledInclusiveSplitStillRoutesThroughProxy() throws {
        let json = SingBoxConfigBuilder().configJSON(
            node: ProxyNode(name: "T", proto: .trojan, host: "9.9.9.9", port: 443,
                            credential: "pw"),
            split: SplitTunnelConfig(mode: .inclusive,
                                     inclusiveApps: ["/Applications/Safari.app"],
                                     isEnabled: false))
        let o = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
        let route = o["route"] as! [String: Any]
        XCTAssertEqual(route["final"] as? String, "proxy",
                       "split mati = semua trafik lewat proxy")
    }

    /// `replaceActive` memindahkan daftar ke mode yang sedang dipilih dan
    /// membersihkan mode lama, supaya tidak ada daftar yatim yang Diam-diam
    /// masih ikut terbaca.
    func testReplaceActiveMovesListToCurrentMode() {
        var split = SplitTunnelConfig(mode: .inclusive, inclusiveApps: ["/a.app"])
        split.mode = .exclusive
        split.replaceActive(with: ["/b.app", "/c.app"])
        XCTAssertEqual(split.exclusiveApps, ["/b.app", "/c.app"])
        XCTAssertTrue(split.inclusiveApps.isEmpty)
        XCTAssertEqual(split.activeApps, ["/b.app", "/c.app"])
    }

    func testSplitRoundTripsThroughJSON() throws {
        var split = SplitTunnelConfig(mode: .inclusive, inclusiveApps: ["/a.app"], isEnabled: false)
        let data = try JSONEncoder().encode(split)
        let back = try JSONDecoder().decode(SplitTunnelConfig.self, from: data)
        XCTAssertEqual(back.mode, .inclusive)
        XCTAssertEqual(back.inclusiveApps, ["/a.app"])
        XCTAssertFalse(back.isEnabled)
    }

    /// Berkas milik user yang sudah pernah menyimpan daftar Terminal harus
    /// tetap terbaca utuh. Key `terminalApps` kini diabaikan (`Codable`
    /// membuang key asing), jadi kegagalan decode hanya mungkin kalau ada
    /// key/value yang TIDAK boleh hilang — dan daftar aplikasi TUN termasuk.
    func testSplitFileWithLegacyTerminalKeyKeepsItsApps() throws {
        let legacy = """
        {"mode":"exclusive","inclusiveApps":[],"exclusiveApps":["/Applications/Safari.app"],\
        "terminalApps":["/Applications/Ghostty.app"],"isEnabled":true}
        """
        let decoded = try JSONDecoder().decode(SplitTunnelConfig.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.mode, .exclusive)
        XCTAssertEqual(decoded.activeApps, ["/Applications/Safari.app"],
                       "daftar TUN user tidak boleh hilang hanya karena key lawas ada")
        XCTAssertTrue(decoded.isEnabled)
    }

    /// `split.json` dari versi yang pernah menulis `mode: "terminal"` harus
    /// tetap terbaca utuh. Decode enum secara langsung akan melempar error dan
    /// menghapus seluruh daftar app user.
    func testLegacyTerminalModeValueStillDecodes() throws {
        let legacy = """
        {"mode":"terminal","inclusiveApps":["/Applications/Safari.app"],\
        "terminalApps":["/Applications/Ghostty.app"],"isEnabled":true}
        """
        let decoded = try JSONDecoder().decode(SplitTunnelConfig.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.mode, .exclusive, "mode tak dikenal harus jatuh ke default")
        XCTAssertEqual(decoded.inclusiveApps, ["/Applications/Safari.app"])
    }

    /// Hanya ada dua mode. Mode ketiga yang pernah ada tidak boleh bisa
    /// dibangkitkan lagi dari mana pun — termasuk dari berkas milik user.
    func testOnlyInclusiveAndExclusiveExist() {
        XCTAssertEqual(SplitMode.allCases.map(\.rawValue).sorted(),
                       ["exclusive", "inclusive"])
    }

    // MARK: - Riwayat MAC

    func testMACHistoryKeepsNewestFirstAndTrimsOldest() {
        var history: [MACHistoryEntry] = []
        for i in 0..<5 {
            history = AppState.insertingMACChange(
                MACHistoryEntry(mac: "aa:bb:cc:dd:ee:0\(i)", kind: .custom, interface: "en0"),
                into: history, limit: 3)
        }
        XCTAssertEqual(history.count, 3)
        XCTAssertEqual(history.first?.mac, "aa:bb:cc:dd:ee:04", "entri terbaru harus di depan")
        XCTAssertEqual(history.last?.mac, "aa:bb:cc:dd:ee:02", "entri tertua harus terpotong")
    }

    func testMACHistoryKeepsEverythingBelowLimit() {
        var history: [MACHistoryEntry] = []
        for i in 0..<3 {
            history = AppState.insertingMACChange(
                MACHistoryEntry(mac: "m\(i)", kind: .random, interface: "en1"),
                into: history, limit: 100)
        }
        XCTAssertEqual(history.count, 3)
    }

    func testMACHistoryEntryRoundTrips() throws {
        let entry = MACHistoryEntry(mac: "da:60:3b:b6:c6:c1", kind: .restore,
                                    interface: "en0", at: Date(timeIntervalSince1970: 1_700_000_000))
        let data = try JSONEncoder().encode(entry)
        let back = try JSONDecoder().decode(MACHistoryEntry.self, from: data)
        XCTAssertEqual(back.mac, entry.mac)
        XCTAssertEqual(back.kind, .restore)
        XCTAssertEqual(back.interface, "en0")
        XCTAssertEqual(back.at.timeIntervalSince1970, entry.at.timeIntervalSince1970, accuracy: 0.001)
    }

    /// `auto` tidak punya chip filter sendiri, tapi tetap harus punya judul
    /// — kalau tidak, baris otomatis akan tampil mentah sebagai "mac_kind_auto".
    func testEveryMACKindHasTitleAndFilterMembership() {
        for kind in [MACHistoryEntry.Kind.custom, .random, .restore, .auto] {
            XCTAssertFalse(L10n.string("mac_kind_" + kind.rawValue).isEmpty,
                           "judul mac_kind_\(kind.rawValue) kosong")
        }
        XCTAssertFalse(MACHistoryEntry.Kind.allCasesForFilter.contains(.auto),
                       "kind auto sengaja tidak jadi chip")
        XCTAssertEqual(MACHistoryEntry.Kind.allCasesForFilter.count, 3)
    }

    // MARK: - Trafik (sparkline di kartu Trafik)

    /// Kontrak D73: pesan `/traffic` adalah DELTA per interval, bukan total
    /// kumulatif — `fetchStats()` membuka websocket baru tiap 2 detik dan
    /// membaca satu pesan. Test-test di sini sengaja memakai angka DELTA;
    /// memakai angka kumulatif (seperti versi lama test ini) justru akan
    /// menguji bug yang sama persis.
    @MainActor
    func testFirstSampleAccumulatesButHasNoRate() {
        let m = ConnectionManager()
        let t0 = Date()
        m.applySample(upDelta: 1000, downDelta: 2000, now: t0)
        // Sampel pertama TIDAK menghasilkan laju — `interval == 0`, jadi kita
        // belum tahu delta itu mencakup berapa lama. Menebak = angka liar.
        XCTAssertEqual(m.upRate, 0)
        XCTAssertEqual(m.downRate, 0)
        XCTAssertTrue(m.upHistory.isEmpty, "satu sampel tidak membentuk garis")
        // Tapi total TETAP bertambah: trafik itu nyata dan harus dihitung.
        XCTAssertEqual(m.upBytes, 1000)
        XCTAssertEqual(m.downBytes, 2000)
    }

    @MainActor
    func testRateComesFromDeltaOverInterval() {
        let m = ConnectionManager()
        let t0 = Date()
        m.applySample(upDelta: 0, downDelta: 0, now: t0)
        // 2 detik, delta up 2048 -> 1024 B/s; down 1024 -> 512 B/s.
        m.applySample(upDelta: 2048, downDelta: 1024, now: t0.addingTimeInterval(2))
        XCTAssertEqual(m.upRate, 1024, accuracy: 0.5)
        XCTAssertEqual(m.downRate, 512, accuracy: 0.5)
        XCTAssertEqual(m.upHistory.count, 1)
        XCTAssertEqual(m.downHistory.count, 1)
    }

    /// REGRESI UTAMA: "Total" tidak boleh kembali ke 0 setelah trafik berhenti.
    ///
    /// Bug yang dilaporkan: download ~1 MB/detik, lalu berhenti danDiam —
    /// angka Total turun kembali ke nol setiap detak. Itu terjadi karena
    /// `upBytes = up` menimpa total dengan delta 1 detik terakhir.
    @MainActor
    func testTotalSurvivesIdlePeriods() {
        let m = ConnectionManager()
        var t = Date()
        // 10 sampel aktif, 1 MB tiap 2 detik.
        for _ in 0..<10 {
            m.applySample(upDelta: 1_048_576, downDelta: 0, now: t)
            t = t.addingTimeInterval(2)
        }
        let afterTraffic = m.upBytes
        XCTAssertEqual(afterTraffic, 10 * 1_048_576)
        // Sekarang idle: delta 0 sebanyak 5 sampel.
        for _ in 0..<5 {
            m.applySample(upDelta: 0, downDelta: 0, now: t)
            t = t.addingTimeInterval(2)
        }
        XCTAssertEqual(m.upBytes, afterTraffic,
                       "idle tidak boleh mereset total — inilah bug yang dilaporkan")
        XCTAssertEqual(m.upRate, 0, "laju harus 0 saat idle")
    }

    /// Total harus BERJALAN, bukan melompat-lompat:iap delta dijumlahkan.
    @MainActor
    func testTotalAccumulatesAcrossManySamples() {
        let m = ConnectionManager()
        var t = Date()
        for _ in 0..<50 {
            m.applySample(upDelta: 1000, downDelta: 500, now: t)
            t = t.addingTimeInterval(2)
        }
        XCTAssertEqual(m.upBytes, 50_000)
        XCTAssertEqual(m.downBytes, 25_000)
    }

    /// Delta tidak mungkin negatif secara fisika. Data rusak dari core tidak
    /// boleh mengikis total maupun menggambar sparkline ke bawah sumbu.
    @MainActor
    func testNegativeDeltaIsIgnored() {
        let m = ConnectionManager()
        let t0 = Date()
        m.applySample(upDelta: 5_000, downDelta: 5_000, now: t0)
        m.applySample(upDelta: -999, downDelta: -999, now: t0.addingTimeInterval(2))
        XCTAssertEqual(m.upBytes, 5_000, "delta negatif tidak boleh mengurangi total")
        XCTAssertEqual(m.downBytes, 5_000)
        XCTAssertGreaterThanOrEqual(m.upRate, 0)
        XCTAssertGreaterThanOrEqual(m.downRate, 0)
    }

    /// Sesi panjang tidak boleh menambah riwayat tanpa batas.
    ///
    /// D76: batasannya kini buffer melingkar berkapasitas tetap
    /// (`TrafficSeries.capacity`), bukan `removeFirst` pada array — yang O(n)
    /// dan menggeser seluruh buffer tiap sampel baru.
    @MainActor
    func testHistoryIsCappedAcrossManySamples() {
        let m = ConnectionManager()
        var t = Date()
        for _ in 0..<400 {
            t = t.addingTimeInterval(1)
            m.applySample(upDelta: 100, downDelta: 50, now: t)
        }
        XCTAssertEqual(m.upHistory.count, m.upHistory.capacity,
                       "harus tepat sampai kapasitas")
        XCTAssertEqual(m.downHistory.count, m.downHistory.capacity)
    }

    /// Buffer melingkar harus menyisakan sampel TERBARU saja. Kalau ia
    /// menyimpan yang tertua, grafik menampilkan data 2 menit lalu yang sudah
    /// tak relevan.
    @MainActor
    func testRingBufferKeepsNewestSamples() {
        let m = ConnectionManager()
        let t0 = Date()
        let extra = 50
        for i in 0..<(m.upHistory.capacity + extra) {
            m.applySample(upDelta: Int64(i), downDelta: 0, now: t0.addingTimeInterval(Double(i)))
        }
        let n = m.upHistory.count
        XCTAssertEqual(n, m.upHistory.capacity)
        // Sampel terakhir = yang terakhir dimasukkan (indeks logis 0 = tertua).
        XCTAssertEqual(m.upHistory.value(at: n - 1), Double(n - 1 + extra))
        // Urutan waktu tetap menaik meski buffer berputar.
        for i in 1..<n {
            XCTAssertGreaterThan(m.upHistory.time(at: i), m.upHistory.time(at: i - 1))
        }
    }

    /// Trafik nol harus tercatat sebagai laju 0 — bukan "lewati sampel".
    ///
    /// Kalau sampel 0 dilewati, ada celah di garis tepat di saat trafik
    /// berhenti, dan kurva terlihat melompat. Ini syarat "tangani kondisi
    /// trafik nol dengan benar".
    ///
    /// Catatan: sampel PERTAMA memang tidak masuk riwayat karena interval-nya
    /// belum diketahui sehingga lajunya tidak bisa diturunkan — itu benar,
    /// bukan bug. Yang diuji di sini: setiap sampel SETELAH itu masuk,
    /// termasuk yang nol.
    @MainActor
    func testZeroTrafficIsRecordedAsZeroRate() {
        let m = ConnectionManager()
        let t0 = Date()
        m.applySample(upDelta: 1000, downDelta: 1000, now: t0)
        XCTAssertEqual(m.downHistory.count, 0, "sampel pertama tak punya interval -> tak ada laju")

        for i in 1...5 {
            m.applySample(upDelta: 0, downDelta: 0, now: t0.addingTimeInterval(Double(i)))
        }
        XCTAssertEqual(m.downRate, 0, "trafik nol harus menghasilkan laju 0")
        XCTAssertEqual(m.downHistory.count, 5,
                       "TIAP sampel idle harus masuk — kalau dilewati, garis berlubang")
        for i in 0..<5 {
            XCTAssertEqual(m.downHistory.value(at: i), 0, "sampel idle harus bernilai 0")
        }
    }

    /// Idle lalu traffic lagi: rate harus pulih dan riwayat tidak boleh
    ///mengandung nilai negativa/aneh di sela-selanya.
    @MainActor
    func testIdleThenTrafficResumesCleanly() {
        let m = ConnectionManager()
        let t0 = Date()
        m.applySample(upDelta: 0, downDelta: 0, now: t0)
        for i in 1...3 { m.applySample(upDelta: 0, downDelta: 0, now: t0.addingTimeInterval(Double(i))) }
        m.applySample(upDelta: 4096, downDelta: 4096, now: t0.addingTimeInterval(4))
        XCTAssertEqual(m.downRate, 4096, "laju harus pulih setelah idle")
        XCTAssertEqual(m.downBytes, 4096, "total hanya menghitung trafik nyata")
        for i in 0..<m.downHistory.count {
            XCTAssertGreaterThanOrEqual(m.downHistory.value(at: i), 0)
        }
    }


    // MARK: - Nama negara

    func testDisplayNameResolvesKnownCodeAndFallsBack() {
        XCTAssertEqual(CountryInfer.displayName(for: "SG"), "Singapore")
        XCTAssertEqual(CountryInfer.displayName(for: "jp"), "Japan")
        XCTAssertEqual(CountryInfer.displayName(for: "DE"), "Germany")
        // Kode tak dikenal / tidak ada kode: tampilkan apa adanya, jangan kosongkan.
        XCTAssertEqual(CountryInfer.displayName(for: "ZZ"), "ZZ")
        XCTAssertNil(CountryInfer.displayName(for: nil))
        XCTAssertNil(CountryInfer.displayName(for: ""))
    }

    /// Dipakai untuk pin peta DotMap. Kode tak dikenal harus `nil` — pin di
    /// tempat keliru lebih buruk daripada peta tanpa pin.
    func testCentroidOnlyForKnownCountry() {
        let sg = CountryInfer.centroid(for: "SG")
        XCTAssertNotNil(sg)
        XCTAssertEqual(sg!.lat, 1.35, accuracy: 0.5)
        XCTAssertEqual(sg!.lng, 103.82, accuracy: 0.5)
        XCTAssertNil(CountryInfer.centroid(for: "ZZ"))
        XCTAssertNil(CountryInfer.centroid(for: nil))
        XCTAssertNil(CountryInfer.centroid(for: ""))
    }

    /// Setiap negara yang punya nama TIDAK boleh punya centroid dan sebaliknya
    /// — kedua tabel dipakai bersama, dan selisih sekecil apa pun berarti
    /// negara yang tampil namanya tapi tidak punya pin (atau sebaliknya).
    func testEveryNamedCountryHasACentroid() {
        for code in CountryInfer.names.keys {
            XCTAssertNotNil(CountryInfer.centroid(for: code),
                            "negara \(code) punya nama tapi tidak punya centroid")
        }
    }

    /// Inferensi nama node: feed nyata menamai server dalam bahasa Mandarin,
    /// jadi nama non-Latin harus dikenali — tanpa ini semua node dari feed
    /// terbesar berbendera 🌐 dan peta tidak pernah dapat pin.
    func testInferFromChineseCountryNames() {
        XCTAssertEqual(CountryInfer.infer(from: "美国 001"), "US")
        XCTAssertEqual(CountryInfer.infer(from: "新加坡 01"), "SG")
        XCTAssertEqual(CountryInfer.infer(from: "日本 042"), "JP")
        XCTAssertEqual(CountryInfer.infer(from: "德国"), "DE")
        XCTAssertEqual(CountryInfer.infer(from: "中国 001"), "CN")
    }

    func testInferFromFlagEmojiAndBrackets() {
        XCTAssertEqual(CountryInfer.infer(from: "🇸🇬[www.v2ray.com]"), "SG")
        XCTAssertEqual(CountryInfer.infer(from: "US-01"), "US")
        XCTAssertEqual(CountryInfer.infer(from: "[DE] 3"), "DE")
    }

    /// Kode telanjang harus di batas kata DAN harus kode yang dikenal.
    /// Tanpa validasi tabel, hampir semua dua huruf akan dianggap negara.
    func testBareCodeRequiresWordBoundaryAndKnownCountry() {
        XCTAssertEqual(CountryInfer.infer(from: "CA 12"), "CA")
        // "ZZ" bukan negara -> jangan ditebak.
        XCTAssertNil(CountryInfer.infer(from: "ZZ-01"))
        // Dua huruf di tengah kata tidak boleh jadi kode.
        XCTAssertNil(CountryInfer.infer(from: "vlessXYZnode"))
    }

    /// Node tanpa informasi lokasi harus tetap `nil` — 77% feed bernama
    /// "By EbraSha ⌨️" dan nama seperti itu memang tidak menyatakan lokasi apa pun.
    func testInferReturnsNilWhenNameCarriesNoCountry() {
        XCTAssertNil(CountryInfer.infer(from: "By EbraSha ⌨️"))
        XCTAssertNil(CountryInfer.infer(from: "By DeltaKronec"))
        XCTAssertNil(CountryInfer.infer(from: "ProxyPool"))
    }

    // MARK: - Beban relatif (kolom Load)

    /// Kolom Load bukan metrik penyedia server. Yang dijamin hanya: 0 untuk
    /// node tercepat, naik proporsional, dan tidak pernah di luar 0…1.
    func testLoadIsRelativeAndBounded() {
        let best = 40
        XCTAssertEqual(ConnectView.load(ms: 40, best: best), 0, "node tercepat = nol beban")
        XCTAssertGreaterThan(ConnectView.load(ms: 80, best: best), 0)
        XCTAssertLessThan(ConnectView.load(ms: 60, best: best),
                          ConnectView.load(ms: 100, best: best))
        // Sangat lambat tidak boleh melompati 100%.
        XCTAssertEqual(ConnectView.load(ms: 10_000, best: best), 1)
    }

    func testLoadIsZeroWithoutMeasurements() {
        XCTAssertEqual(ConnectView.load(ms: nil, best: 100), 0)
        XCTAssertEqual(ConnectView.load(ms: 100, best: nil), 0)
        // best == 0 hanya mungkin kalau tidak ada node hidup; jangan bagi nol.
        XCTAssertEqual(ConnectView.load(ms: 100, best: 0), 0)
    }

    // MARK: - GeoIP

    /// Parser alamat IPv4 harus tegas: tanpa itu `1.2.3.4x` atau `1.2.3.256`
    /// bisa salah dibaca dan database dikonsultasi dengan angka sampah.
    func testIPv4ValueParsing() {
        XCTAssertEqual(GeoIP.ipv4Value("0.0.0.0"), 0)
        XCTAssertEqual(GeoIP.ipv4Value("1.2.3.4"), 0x01020304)
        XCTAssertEqual(GeoIP.ipv4Value("255.255.255.255"), 0xFFFFFFFF)
        XCTAssertEqual(GeoIP.ipv4Value("45.199.138.185"),
                       45 << 24 | 199 << 16 | 138 << 8 | 185)

        XCTAssertNil(GeoIP.ipv4Value("1.2.3"))
        XCTAssertNil(GeoIP.ipv4Value("1.2.3.4.5"))
        XCTAssertNil(GeoIP.ipv4Value("1.2.3.256"), "oktet > 255 harus ditolak")
        XCTAssertNil(GeoIP.ipv4Value("1.2.3.1000"), "lebih dari 3 digit ditolak")
        XCTAssertNil(GeoIP.ipv4Value("1.2..4"))
        XCTAssertNil(GeoIP.ipv4Value("1.2.3.x"))
        XCTAssertNil(GeoIP.ipv4Value("yh1.dtku41.xyz"), "domain bukan literal")
        XCTAssertNil(GeoIP.ipv4Value("2001:db8::1"), "IPv6 bukan literal v4")
        XCTAssertNil(GeoIP.ipv4Value(""))
    }

    func testIsIPv4Literal() {
        XCTAssertTrue(GeoIP.isIPv4Literal("45.199.138.185"))
        XCTAssertFalse(GeoIP.isIPv4Literal("yh1.dtku41.xyz"))
        XCTAssertFalse(GeoIP.isIPv4Literal("2001:db8::1"))
    }

    /// Membangun blob database dalam format yang SAMA PERSIS dengan berkas
    /// asli, supaya test melewati decoder yang sama dengan produksi — bukan
    /// jalur khusus test.
    private struct GeoRow {
        var start: UInt32; var span: UInt32
        var lat: Double; var lng: Double; var code: String
    }

    private func row(_ start: UInt32, _ span: UInt32,
                     _ lat: Double, _ lng: Double, _ code: String) -> GeoRow {
        GeoRow(start: start, span: span, lat: lat, lng: lng, code: code)
    }

    private func makeBlob(_ rows: [GeoRow]) -> Data {
        let codes = Array(Set(rows.map(\.code))).sorted()
        var out = Data(Array("FPNGEO02".utf8))
        func be32(_ v: UInt32) { for s in [24, 16, 8, 0] { out.append(UInt8((v >> UInt32(s)) & 0xFF)) } }
        func be16(_ v: UInt32) { for s in [8, 0] { out.append(UInt8((v >> UInt32(s)) & 0xFF)) } }
        be32(UInt32(rows.count))
        be16(UInt32(codes.count))
        for c in codes { out.append(contentsOf: Array(c.utf8)) }
        for r in rows {
            be32(r.start)
            be16(r.span)
            be16(UInt32(round((r.lat + 90) * 128)))
            be16(UInt32(round((r.lng + 180) * 128)))
            out.append(UInt8(codes.firstIndex(of: r.code) ?? 0))
        }
        return out
    }

    /// Pencarian biner: record terakhir dengan `start <= ip`, DAN `ip` masih
    /// di dalam span. Pemeriksaan span itulah yang mencegah IP privat salah
    /// mewarisi negara record sebelumnya.
    func testBinarySearchChecksSpanNotJustStart() {
        let blob = makeBlob([
            row(0x0A000000, 0x00FF, 1.0, 2.0, "XX"),   // 10.0.0.0/24
            row(0x64000000, 0xFFFF, 3.0, 4.0, "AA"),   // 100.0.0.0 – 100.0.255.255
        ])
        XCTAssertTrue(GeoIP.install(blob: blob))
        defer { GeoIP.reset() }

        XCTAssertEqual(GeoIP.countryCode(forIPv4: "10.0.0.0"), "XX")
        XCTAssertEqual(GeoIP.countryCode(forIPv4: "10.0.0.255"), "XX", "batas atas span")
        XCTAssertEqual(GeoIP.countryCode(forIPv4: "100.0.0.0"), "AA")
        XCTAssertEqual(GeoIP.countryCode(forIPv4: "100.0.255.255"), "AA",
                       "batas atas span kedua")
        XCTAssertNil(GeoIP.countryCode(forIPv4: "100.1.0.0"),
                     "sudah lewat span kedua (span berakhir di 100.0.255.255)")

        // Di DALAM start record AA tapi di LUAR span-nya -> tidak ada negara.
        XCTAssertNil(GeoIP.countryCode(forIPv4: "101.0.0.1"),
                     "IP di celah setelah span harus kosong, bukan mewarisi AA")
        // Sebelum record pertama.
        XCTAssertNil(GeoIP.countryCode(forIPv4: "9.255.255.255"))
    }

    /// Bug nyata yang tertangkap: tanpa span, blok privat "mewarisi" negara
    /// record sebelumnya (192.168.1.1 -> "ML"/Mali).
    func testPrivateRangesNeverInheritNeighbouringCountry() {
        let blob = makeBlob([
            row(0x2DC0_0000, 0x00FF, 0, 0, "SC"),  // 45.192.0.0/24  Seychelles
            row(0xC0A8_0000, 0x00FF, 0, 0, "BR"),  // 192.168.0.0/24 Brazil
        ])
        XCTAssertTrue(GeoIP.install(blob: blob))
        defer { GeoIP.reset() }

        XCTAssertNil(GeoIP.countryCode(forIPv4: "192.168.1.1"))
        XCTAssertNil(GeoIP.countryCode(forIPv4: "10.0.0.1"))
        XCTAssertNil(GeoIP.countryCode(forIPv4: "172.16.0.1"))
        XCTAssertEqual(GeoIP.countryCode(forIPv4: "192.168.0.5"), "BR")
    }

    /// Koordinat harus ikut record yang benar, bukan cuma kode negara — pin
    /// di peta memakai nilai ini.
    func testLookupReturnsCoordinatesOfMatchingRange() {
        let blob = makeBlob([
            row(10 << 24, 0xFFFF, 1.5, 2.5, "XX"),
            row(100 << 24, 0xFFFF, 35.75, 139.65, "AA"),
        ])
        XCTAssertTrue(GeoIP.install(blob: blob))
        defer { GeoIP.reset() }

        let a = GeoIP.lookup("10.0.1.2")
        XCTAssertEqual(a?.country, "XX")
        XCTAssertEqual(a?.latitude ?? 0, 1.5, accuracy: 0.02)
        XCTAssertEqual(a?.longitude ?? 0, 2.5, accuracy: 0.02)

        let b = GeoIP.lookup("100.0.1.2")
        XCTAssertEqual(b?.country, "AA")
        XCTAssertEqual(b?.latitude ?? 0, 35.75, accuracy: 0.02)
        XCTAssertEqual(b?.longitude ?? 0, 139.65, accuracy: 0.02)
    }

    /// Database asli harus terbaca dan menjawab IP yang sudah diketahui.
    /// Test ini juga menangkap "geoip-country.bin tidak masuk bundle".
    func testBundledDatabaseResolvesKnownAddresses() {
        GeoIP.reset()
        XCTAssertTrue(GeoIP.load(), "geoip-country.bin tidak termuat dari bundle")
        XCTAssertEqual(GeoIP.countryCode(forIPv4: "8.8.8.8"), "US")
        XCTAssertEqual(GeoIP.countryCode(forIPv4: "39.103.165.178"), "CN")
        XCTAssertEqual(GeoIP.countryCode(forIPv4: "154.90.39.63"), "MY")
        // Koordinat City harus masuk akal (Beijing ~39.91, 116.40).
        let bj = GeoIP.lookup("39.103.165.178")
        XCTAssertEqual(bj?.latitude ?? 0, 39.91, accuracy: 0.5)
        XCTAssertEqual(bj?.longitude ?? 0, 116.40, accuracy: 0.5)
    }

    func testPrivateAddressesHaveNoRecordInRealDatabase() {
        GeoIP.reset()
        XCTAssertTrue(GeoIP.load())
        for ip in ["10.0.0.1", "192.168.1.1", "172.16.0.1", "127.0.0.1"] {
            XCTAssertNil(GeoIP.lookup(ip)?.country, "\(ip) tidak punya negara")
        }
    }

    /// Node yang namanya tak berguna ("By EbraSha") tapi host-nya IP literal
    /// harus tetap ketemu negara lewat GeoIP — inilah gunanya database ini.
    func testGeoIPFindsCountryForAnonymousNodeName() {
        GeoIP.reset()
        XCTAssertTrue(GeoIP.load())
        let node = ProxyNode(name: "By EbraSha \u{232C}\u{FE0F}", proto: .vmess,
                             host: "39.103.165.178", port: 443, credential: "u")
        XCTAssertNil(CountryInfer.infer(from: node.name))
        XCTAssertEqual(GeoIPResolver.countryCode(for: node), "CN")
    }

    /// Urutan usaha: kode yang sudah ada menang, lalu nama, lalu GeoIP.
    func testResolverPrefersExistingThenName() {
        let saved = ProxyNode(name: "By EbraSha", proto: .vmess, host: "8.8.8.8",
                              port: 443, credential: "u", countryCode: "DE")
        XCTAssertEqual(GeoIPResolver.countryCode(for: saved), "DE",
                       "kode tersimpan harus menang, bukan GeoIP (US)")

        let byName = ProxyNode(name: "\u{65E5}\u{672C} 001", proto: .vmess,
                               host: "8.8.8.8", port: 443, credential: "u")
        XCTAssertEqual(GeoIPResolver.countryCode(for: byName), "JP",
                       "nama harus menang sebelum GeoIP")
    }

// MARK: - Pengayaan negara untuk host domain

    /// Target pengayaan hanya host yang belum punya negara.
    ///
    /// Node bersandi sudah selesai oleh parser; yang tersisa harus dipilah
    /// dua — literal Host diselesaikan tanpa jaringan, domain lewat DNS.
    func testEnrichmentSeparatesLiteralsFromDomains() {
        let nodes = [
            ProxyNode(name: "a", proto: .vmess, host: "Example-One.com",
                      port: 443, credential: "u"),
            ProxyNode(name: "b", proto: .vmess, host: "1.2.3.4",
                      port: 443, credential: "u"),
            ProxyNode(name: "c", proto: .vmess, host: "example-one.com",
                      port: 443, credential: "u"),
            ProxyNode(name: "d", proto: .vmess, host: "example-two.com",
                      port: 443, credential: "u", countryCode: "JP"),
            ProxyNode(name: "e", proto: .vmess, host: "5.6.7.8",
                      port: 443, credential: "u"),
            ProxyNode(name: "f", proto: .vmess, host: "",
                      port: 443, credential: "u")
        ]
        let domains = AppState.pendingHostsNeedingCountry(in: nodes, limit: 100,
                                                          domainsOnly: true)
        XCTAssertEqual(Array(domains.keys), ["example-one.com"],
                       "domain harus unik, lowercase, dan yang sudah bersandi dikeluarkan")

        let literals = AppState.pendingHostsNeedingCountry(in: nodes, limit: 100,
                                                           domainsOnly: false)
        XCTAssertEqual(Array(literals.keys).sorted(), ["1.2.3.4", "5.6.7.8"],
                       "host kosong harus diabaikan; literal host terpisah dari domain")
        XCTAssertEqual(literals["1.2.3.4"], "1.2.3.4",
                       "nilai balik harus host asli supaya bisa diparse GeoIP")
        XCTAssertNil(literals["example-one.com"],
                     "domain tidak boleh bocor ke jalur tanpa jaringan")
    }

    /// Batas `limit` menjaga satu putaran tidak mengurai ribuan host.
    func testEnrichmentRespectsLimit() {
        let nodes = (0..<50).map {
            ProxyNode(name: "n\($0)", proto: .vmess, host: "host\($0).example",
                      port: 443, credential: "u")
        }
        XCTAssertEqual(AppState.pendingHostsNeedingCountry(in: nodes, limit: 10,
                                                           domainsOnly: true).count, 10)
        XCTAssertEqual(AppState.pendingHostsNeedingCountry(in: nodes, limit: 10_000,
                                                           domainsOnly: true).count, 50)
    }

    /// Host literal tidak boleh menyentuh jaringan sama sekali.
    func testEnrichmentResolvesLiteralWithoutDNS() async {
        GeoIP.reset(); GeoIPResolver.resetCache()
        XCTAssertTrue(GeoIP.load())
        let cc = await GeoIPResolver.resolveCountry(host: "45.199.138.185")
        XCTAssertNotNil(cc, "IP literal harus ketemu negara tanpa DNS")
        XCTAssertNil(GeoIPResolver.cachedCoordinates(for: "45.199.138.185"),
                     "cache koordinat hanya diisi untuk jalur domain")
    }

    /// Jalur gratis (IP literal) harus menutup SELURUH daftar dalam sekali jalan.
    ///
    /// Regresi yang pernah terjadi: versi pakai kuota per putaran, dan host
    /// yang memang tak punya lokasi memenuhi kuota itu selamanya — hasilnya
    /// hanya 6.438 dari 8.213 node terisi dan tidak ada yang memberi tahu.
    func testLiteralPassFillsEverythingInOneSweep() {
        GeoIP.reset()
        XCTAssertTrue(GeoIP.load())
        // Host yang dipakai sengaja diambil dari data nyata, tapi negara
        // DATABASE GeoLite2 yang jadi acuan — bukan asumsi tester. GeoLite2
        // berubah tiap dua minggu, dan tes tidak boleh gagal hanya karena
        // MaxMind memindahkan satu blok.
        let host = "39.103.165.178"
        let expected = GeoIP.countryCode(for: host)
        XCTAssertNotNil(expected)

        var nodes: [ProxyNode] = []
        // 400 host yang TIDAK punya lokasi (privat/reservat) disisipkan di
        // depan: kalau ada kuota, host ini yang memakainya dan sisanya
        // tidak akan pernah tersentuh.
        for _ in 0..<400 {
            nodes.append(ProxyNode(name: "privat", proto: .vmess, host: "10.0.0.1",
                                   port: 443, credential: "u"))
        }
        for _ in 0..<50 {
            nodes.append(ProxyNode(name: "cn", proto: .vmess, host: host,
                                   port: 443, credential: "u"))
        }
        let changed = AppState.applyLiteralCountries(to: &nodes)
        XCTAssertTrue(changed)
        XCTAssertEqual(nodes.filter { $0.countryCode == expected }.count, 50,
                       "semua host yang punya lokasi harus terisi, bukan hanya yang duluan")
        XCTAssertTrue(nodes.prefix(400).allSatisfy { $0.countryCode == nil },
                      "IP privat memang tidak boleh dikasih negara karangan")
    }

    /// Sekali jalan: memanggilnya lagi tidak boleh mengubah apa pun.
    func testLiteralPassIsIdempotent() {
        GeoIP.reset()
        XCTAssertTrue(GeoIP.load())
        var nodes = [ProxyNode(name: "cn", proto: .vmess, host: "39.103.165.178",
                               port: 443, credential: "u")]
        XCTAssertTrue(AppState.applyLiteralCountries(to: &nodes))
        let after = nodes[0].countryCode
        XCTAssertNotNil(after)
        XCTAssertFalse(AppState.applyLiteralCountries(to: &nodes),
                       "pass kedua tidak boleh menimpa negara yang sudah ada")
        XCTAssertEqual(nodes[0].countryCode, after)
    }

/// Cache koordinat harus bersih setelah `resetCache` supaya test tidak
    /// bergantung pada urutan eksekusi.
    func testCoordinateCacheResetsCleanly() {
        GeoIPResolver.resetCache()
        XCTAssertNil(GeoIPResolver.cachedCoordinates(for: "apaun.example"))
        GeoIPResolver.resetCache()
        XCTAssertNil(GeoIPResolver.cachedCoordinates(for: "apaun.example"))
    }

    /// Domain tanpa koordinat harus tetap dapat pin lewat centroid negara —
    /// peta tanpa pin lebih jujur daripada pin di laut lepas.
    func testDomainFallsBackToCentroidPin() {
        let node = ProxyNode(name: "SG Node", proto: .vmess, host: "sg.example.com",
                             port: 443, credential: "u", countryCode: "SG")
        GeoIPResolver.resetCache()
        let pins = ServerWorldMap.pins(for: node, isConnected: false)
        XCTAssertEqual(pins.count, 1)
        XCTAssertEqual(pins[0].lat, 1.35, accuracy: 0.001)
    }

// MARK: - Urutan tabel Server

    private func node(_ name: String, src: String = "s1", cc: String? = nil,
                      proto: NodeProtocol = .vmess, ms: Int? = nil,
                      dead: Bool = false) -> ProxyNode {
        var n = ProxyNode(name: name, proto: proto, host: "1.2.3.4", port: 443,
                          credential: "u", sourceID: src, countryCode: cc)
        // ID SELALU = nama. Dulu hanya diberikan saat ms/dead terisi, jadi
        // node "belum diuji" tanpa ID punya ID kosong yang bikin urutan
        // tie-break (a.id < b.id) tidak stabil antar test.
        n.id = name
        return n
    }

    /// Persis keluhan user: server harus bisa dikelompokkan per sumber.
    func testSortBySourceGroupsFeeds() {
        let names = ["Zeta", "Alpha", "Mu", "Beta"]
        let srcs = ["b", "a", "b", "a"]
        let nodes = zip(names, srcs).map { node($0, src: $1) }
        let sorted = ServerSorter.sort(nodes, by: ServerSort(key: .source, ascending: true),
                                       ping: [:], sourceNames: ["a": "Anaer", "b": "EbraSha"])
        XCTAssertEqual(sorted.map { $0.sourceID }, ["a", "a", "b", "b"])
        XCTAssertEqual(sorted.map { $0.name }, ["Alpha", "Beta", "Mu", "Zeta"],
                       "tie-break nama harus menaik dan stabil")
    }

    /// Default app (D61): latensi, tercepat dulu — bukan lagi kolom Sumber.
    func testDefaultSortIsFastestLatency() {
        let s = ServerSort()
        XCTAssertEqual(s.key, .latency)
        XCTAssertTrue(s.ascending, "menaik pada kolom latensi = tercepat di atas")
    }

    /// Klik kolom yang sama membalik arah; kolom baru ganti kolom.
    func testSortToggleFlipsThenSwitches() {
        // Default sekarang latensi menaik (tercepat dulu). Klik pertama
        // pada kolom lain harus pindah kolom, bukan tidak terjadi apa-apa.
        var s = ServerSort()
        XCTAssertEqual(s.key, .latency)
        XCTAssertTrue(s.ascending)

        s.toggle(.name)
        XCTAssertEqual(s.key, .name)
        XCTAssertTrue(s.ascending, "kolom baru mulai dari A→Z")

        s.toggle(.name)
        XCTAssertFalse(s.ascending, "klik kedua pada kolom sama harus membalik arah")

        s.toggle(.country)
        XCTAssertEqual(s.key, .country)
        XCTAssertTrue(s.ascending, "kolom baru selalu mulai menaik")

        // Klik kolom latensi dari default: ascending.toggle() → terlama dulu.
        var t = ServerSort()
        t.toggle(.latency)
        XCTAssertFalse(t.ascending, "klik kolom yang sudah aktif membalik arah")

        // Klik kolom latensi dari kolom lain: mulai tercepat dulu.
        t.toggle(.name)
        t.toggle(.latency)
        XCTAssertTrue(t.ascending, "ganti ke kolom latensi mulai dari tercepat")
    }

    /// Minta user (D61): default harus latensi tercepat, bukan sumber.
    ///
    /// Ini menegaskan urutan NYATA yang tampil di layar: node tercepat yang
    /// SUDAH diuji paling atas, yang belum diuji tetap tenggelam ke bawah.
    func testFastestLatencyFirstOnScreen() {
        let nodes = [node("lambat", ms: 900), node("cepat", ms: 50),
                     node("belum", ms: nil), node("dead", dead: true)]
        var ping: [String: PingResult] = [:]
        ping["cepat"] = PingResult(nodeID: "cepat", webLatencyMs: 50, internetOK: true)
        ping["lambat"] = PingResult(nodeID: "lambat", webLatencyMs: 900, internetOK: true)
        ping["dead"] = PingResult(nodeID: "dead", webLatencyMs: nil, internetOK: false)

        let sorted = ServerSorter.sort(nodes, by: ServerSort(),   // = default
                                       ping: ping, sourceNames: [:])
        // Minta user: "sumber nyala (hijau)" = yang TERBUKTI online pertama.
        // Latensi terkecil = paling atas; yang belum diuji / dead-end
        // tenggelam.
        XCTAssertEqual(sorted.map { $0.name }, ["cepat", "lambat", "belum", "dead"])
    }

    /// Yang belum di-ping harus tenggelam, bukan dianggap "paling lambat".
    ///
    /// Kalau ikut terurut, daftar 16.000 node penuh baris "—" yang terlihat
    /// seperti hasil posisi terakhir yang sah — padahal itu "belum diketahui".
    func testUnknownLatencySinksToBottom() {
        let nodes = [node("belum", ms: nil), node("cepat", ms: 50),
                     node("lambat", ms: 900), node("dead", dead: true)]
        var ping: [String: PingResult] = [:]
        ping["cepat"] = PingResult(nodeID: "cepat", webLatencyMs: 50, internetOK: true)
        ping["lambat"] = PingResult(nodeID: "lambat", webLatencyMs: 900, internetOK: true)
        ping["dead"] = PingResult(nodeID: "dead", webLatencyMs: nil, internetOK: false)

        // Lambat→cepat: 900, 50, lalu yang belum diketahui.
        // Dead-end punya bestMs nil, jadi dia ikut kelompok "belum diketahui",
        // bukan "paling cepat".
        let desc = ServerSorter.sort(nodes, by: ServerSort(key: .latency, ascending: false),
                                     ping: ping, sourceNames: [:])
        XCTAssertEqual(desc.map { $0.name }, ["lambat", "cepat", "belum", "dead"])

        // Cepat→lambat: arah berubah, tapi kelompok "belum diketahui" tetap
        // di paling bawah. Inilah yang harus dijaga — kalau aturan nil ikut
        // dibalik, `ascending == false` akan melemparnya ke paling atas.
        let asc = ServerSorter.sort(nodes, by: ServerSort(key: .latency, ascending: true),
                                    ping: ping, sourceNames: [:])
        XCTAssertEqual(asc.map { $0.name }, ["cepat", "lambat", "belum", "dead"])
    }

    /// Sumber berbintang tetap di atas apa pun kolom yang dipilih.
    func testStarredSourcesStayOnTop() {
        let nodes = [node("a", src: "bintang"), node("z", src: "biasa")]
        let sorted = ServerSorter.sort(nodes, by: ServerSort(key: .name, ascending: true),
                                       ping: [:], sourceNames: [:],
                                       starredSources: ["bintang"])
        XCTAssertEqual(sorted.first?.sourceID, "bintang",
                       "mencentang sumber = 'ini yang saya pakai', jangan dikubur")
    }

    /// Urutan harus stabil: nilai seri tidak boleh "berganti tempat" tiap refresh.
    func testSortIsStable() {
        let nodes = ["c", "a", "b", "d"].map { node($0, src: "s", cc: "US") }
        let a = ServerSorter.sort(nodes, by: ServerSort(key: .country), ping: [:], sourceNames: [:])
        let b = ServerSorter.sort(nodes.shuffled(), by: ServerSort(key: .country),
                                  ping: [:], sourceNames: [:])
        XCTAssertEqual(a.map { $0.name }, b.map { $0.name })
        XCTAssertEqual(a.map { $0.name }, ["a", "b", "c", "d"])
    }

    // MARK: - Filter sumber

    /// Inti dropdown sumber: memilih satu sumber harus benar-benar menyaring.
    func testSourceFilterNarrowsToOneFeed() {
        let nodes = [node("a", src: "s1"), node("b", src: "s2"), node("c", src: "s1")]
        let only = AppState.applyFilters(nodes: nodes, search: "", proto: nil, source: "s2")
        XCTAssertEqual(only.map { $0.name }, ["b"])
        let all = AppState.applyFilters(nodes: nodes, search: "", proto: nil, source: nil)
        XCTAssertEqual(all.count, 3)
    }

    /// Sumber yang dihapus tidak boleh meninggalkan tabel terkunci kosong.
    ///
    /// Kalau `sourceFilter` tetap menunjuk id yang sudah tidak ada, tabel
    /// kosong tanpa alasan yang terlihat: label dropdown sudah kembali ke
    /// "Semua sumber" sementara filternya masih aktif — filter yang tidak
    /// bisa dibatalkan dari UI.
    @MainActor
    func testStaleSourceFilterDoesNotLockTableEmpty() {
        isolateStorage()
        let state = AppState()
        state.sources = [VPNSubscriptionSource(id: "hidup", name: "Anaer", url: "https://x/y.yaml", keptCount: 10)]

        state.sourceFilter = "hidup"
        XCTAssertEqual(state.activeSourceFilter, "hidup")
        XCTAssertTrue(state.hasActiveFilter)

        state.sources = [] // sumber dihapus (atau berganti dari sesi lain)
        XCTAssertNil(state.activeSourceFilter, "filter ke sumber yang sudah tiada harus diabaikan")
        XCTAssertFalse(state.hasActiveFilter)
    }

    /// Menghapus sumber harus melepas filter yang menunjuknya.
    @MainActor
    func testRemovingSourceClearsItsFilter() {
        isolateStorage()
        let state = AppState()
        state.sources = [VPNSubscriptionSource(id: "s1", name: "Anaer", url: "https://x/y.yaml", keptCount: 5)]
        state.nodes = [ProxyNode(name: "a", proto: .vmess, host: "1.2.3.4", port: 443,
                                 credential: "u", sourceID: "s1")]
        state.sourceFilter = "s1"

        state.removeSource(id: "s1")
        XCTAssertNil(state.sourceFilter, "hapus sumber harus melepas filternya, bukan meninggalkan tabel kosong")
        XCTAssertTrue(state.nodes.isEmpty, "node satu-satunya dari sumber itu harus ikut hilang")
    }

    /// Node, ping, dan favorit dari sumber LAIN harus utuh setelah penghapusan.
    ///
    /// Bug lama: `removeSource` memakai `nodesAfterRemovingSource` — yang
    /// mengembalikan node yang *tetap* — sebagai daftar node yang dihapus.
    /// Akibatnya menghapus satu feed akan menghapus seluruh favorit dan
    /// hasil ping milik feed lain.
    @MainActor
    func testRemovingSourceKeepsOtherSourcesIntact() {
        isolateStorage()
        let state = AppState()
        let a = ProxyNode(name: "a", proto: .vmess, host: "1.1.1.1", port: 443,
                          credential: "u", sourceID: "s1")
        let b = ProxyNode(name: "b", proto: .vmess, host: "2.2.2.2", port: 443,
                          credential: "u", sourceID: "s2")
        state.sources = [
            VPNSubscriptionSource(id: "s1", name: "Satu", url: "https://x/1", keptCount: 1),
            VPNSubscriptionSource(id: "s2", name: "Dua", url: "https://x/2", keptCount: 1)
        ]
        state.nodes = [a, b]
        state.favorites = [a.id, b.id]
        state.ping[a.id] = PingResult(nodeID: a.id, webLatencyMs: 100, internetOK: true)
        state.ping[b.id] = PingResult(nodeID: b.id, webLatencyMs: 120, internetOK: true)

        state.removeSource(id: "s1")

        XCTAssertEqual(state.nodes.map { $0.id }, [b.id])
        XCTAssertTrue(state.favorites.contains(b.id), "favorit sumber lain harus selamat")
        XCTAssertFalse(state.favorites.contains(a.id))
        XCTAssertNotNil(state.ping[b.id], "hasil ping sumber lain harus selamat")
        XCTAssertNil(state.ping[a.id])
    }

    /// Filter sumber harus menyatu dengan filter lain, bukan menggantikannya.
    func testSourceFilterCombinesWithSearchAndProto() {
        let nodes = [node("sg", src: "s1", cc: "SG", proto: .vmess),
                     node("sg2", src: "s1", cc: "SG", proto: .trojan),
                     node("de", src: "s1", cc: "DE", proto: .vmess),
                     node("sg3", src: "s2", cc: "SG", proto: .vmess)]
        let out = AppState.applyFilters(nodes: nodes, search: "sg",
                                        proto: .vmess, source: "s1")
        XCTAssertEqual(out.map { $0.name }, ["sg"])
    }

/// Mengubah nama harus benar-benar mengganti nama.
    @MainActor
    func testRenameSourceChangesName() {
        isolateStorage()
        let state = AppState()
        state.sources = [VPNSubscriptionSource(id: "s1", name: "Salah",
                                               url: "https://x/1.yaml", keptCount: 3)]
        state.renameSource(id: "s1", name: "  Nama Asli  ", url: "https://x/1.yaml")
        XCTAssertEqual(state.sources[0].name, "Nama Asli", "spasi harus dipangkas")
        XCTAssertEqual(state.sourceName(for: "s1"), "Nama Asli",
                       "cache nama harus ikut diperbarui, kalau tidak kolom Sumber masih menampilkan nama lama")
    }

    /// ID sumber TIDAK boleh berubah saat nama/URL diedit — cache feed di-key
    /// dengan UUID sumber. Kalau ID ikut berubah, seluruh node sumber itu
    /// hilang sampai feed diunduh ulang.
    @MainActor
    func testRenameSourceKeepsIDAndCache() {
        isolateStorage()
        let state = AppState()
        state.sources = [VPNSubscriptionSource(id: "s1", name: "Lama",
                                               url: "https://x/1.yaml", keptCount: 3)]
        let before = state.sources[0].id
        state.renameSource(id: "s1", name: "Baru", url: "https://y/2.yaml")
        XCTAssertEqual(state.sources[0].id, before, "ID sumber adalah kunci cache; mengubahnya membuang cache")
    }

    /// URL berubah = cache lama tidak boleh lagi dipakai. Kalau dibiarkan,
    /// user melihat node dari feed LAMA dengan nama sumber yang sudah baru.
    @MainActor
    func testRenameSourceResetsCountsWhenURLChanges() {
        isolateStorage()
        let state = AppState()
        var s = VPNSubscriptionSource(id: "s1", name: "X", url: "https://x/1.yaml",
                                     nodeCount: 500, keptCount: 400)
        s.status = .ok
        state.sources = [s]

        state.renameSource(id: "s1", name: "X", url: "https://x/1.yaml")
        XCTAssertEqual(state.sources[0].keptCount, 400,
                       "URL sama: hitungan lama masih relevan")

        state.renameSource(id: "s1", name: "X", url: "https://y/2.yaml")
        XCTAssertEqual(state.sources[0].keptCount, 0)
        XCTAssertEqual(state.sources[0].nodeCount, 0)
    }

    /// Nama/URL kosong tidak boleh menimpa nilai yang ada.
    @MainActor
    func testRenameSourceIgnoresBlankInput() {
        isolateStorage()
        let state = AppState()
        state.sources = [VPNSubscriptionSource(id: "s1", name: "Asli",
                                               url: "https://x/1.yaml")]
        state.renameSource(id: "s1", name: "   ", url: "")
        XCTAssertEqual(state.sources[0].name, "Asli")
        XCTAssertEqual(state.sources[0].url, "https://x/1.yaml",
                       "URL kosong akan membuat sumber tidak bisa di-refresh")
    }

    /// Bendera: kode tak dikenal harus 🌐, bukan regional indicator arbitrary.
    ///
    /// 🇿🇿 untuk "ZZ" dirender sebagai huruf "ZZ" — terlihat seperti bendera
    /// sungguhan padahal tidak ada negara seperti itu.
    func testFlagFallsBackToGlobeForUnknownCode() {
        XCTAssertEqual(CountryInfer.flagEmoji(for: "US"), "\u{1F1FA}\u{1F1F8}")
        XCTAssertEqual(CountryInfer.flagEmoji(for: "us"), "\u{1F1FA}\u{1F1F8}")
        XCTAssertEqual(CountryInfer.flagEmoji(for: "ZZ"), "\u{1F310}")
        XCTAssertEqual(CountryInfer.flagEmoji(for: nil), "\u{1F310}")
        XCTAssertEqual(CountryInfer.flagEmoji(for: "X"), "\u{1F310}")
    }

    /// Nama negara harus tetap ada untuk tooltip walau kolomnya bothera.
    func testCountryNameStillAvailableAsTooltip() {
        XCTAssertEqual(CountryInfer.displayName(for: "JP"), "Japan")
        XCTAssertEqual(CountryInfer.displayName(for: "jp"), "Japan")
    }

// MARK: - Peta DotMap

    /// Peta harus punya tepat satu pin untuk node yang negaranya diketahui.
    func testMapPinPlacedForKnownCountry() throws {
        let node = ProxyNode(name: "SG-01", proto: .vmess, host: "1.1.1.1", port: 443,
                             credential: "u", countryCode: "SG")
        let pins = ServerWorldMap.pins(for: node, isConnected: true)
        XCTAssertEqual(pins.count, 1)
        XCTAssertEqual(try XCTUnwrap(pins.first?.lat), 1.35, accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(pins.first?.lng), 103.82, accuracy: 0.5)
        XCTAssertEqual(pins.first?.label, "Singapore")
        XCTAssertTrue(pins.first?.isActive == true, "pin server aktif harus berdenyut")
    }

    /// D84 — denyut berarti "tunnel hidup", bukan "ada node".
    ///
    /// Node yang cuma sedang DIPILIH (belum ada sambungan) tetap dapat pin,
    /// karena peta harus menunjukkan lokasi server yang akan dipakai. Tapi ia
    /// tidak boleh berdenyut: denyut adalah sinyal "kamu sedang bandits di
    /// sini", dan menyalakannya saat idle memunculkan klaim yang salah.
    func testSelectedButNotConnectedPinDoesNotPulse() {
        let node = ProxyNode(name: "SG-01", proto: .vmess, host: "1.1.1.1", port: 443,
                             credential: "u", countryCode: "SG")
        let pins = ServerWorldMap.pins(for: node, isConnected: false)
        XCTAssertEqual(pins.count, 1, "node terpilih tetap dipetakan")
        XCTAssertEqual(pins.first?.isActive, false,
                       "node yang belum tersambung tidak boleh berdenyut")
    }

    /// D84 — ini bug yang dilaporkan user: peta menunjuk server yang
    /// DIREKOMENDASIKAN, bukan server yang DIPAKAI.
    ///
    /// `mapNode(connected:selected:)` adalah keputusan "mana yang dipetakan",
    /// dipisah jadi fungsi murni supaya bisa diuji tanpa `AppState`.
    func testMapNodePrefersTheServerInUseOverTheOneSelected() {
        let inUse = ProxyNode(name: "JP-01", proto: .vmess, host: "jp.example.com",
                              port: 443, credential: "u", countryCode: "JP")
        let selected = ProxyNode(name: "SG-01", proto: .vmess, host: "sg.example.com",
                                 port: 443, credential: "u", countryCode: "SG")

        // Terhubung: peta WAJIB menunjuk yang dipakai, walau yang dipilih /
        // yang direkomendasikan negara lain.
        XCTAssertEqual(ConnectView.mapNode(connected: inUse, selected: selected)?.id, inUse.id)

        // Belum sambung: peta pratinjau node yang dipilih, tanpa denyut.
        let idle = ConnectView.mapNode(connected: nil, selected: selected)
        XCTAssertEqual(idle?.id, selected.id)
        XCTAssertEqual(ServerWorldMap.pins(for: idle, isConnected: false).first?.isActive,
                       false, "node terpilih belum jadi server yang dipakai — jangan denyut")

        // Tidak ada apa-apa: peta kosong, bukan server tebakan.
        XCTAssertNil(ConnectView.mapNode(connected: nil, selected: nil))
    }

    /// Koordinat pin harus benar-benar milik node yang diberikan — guard
    /// tambahan supaya "pin di negara lain" mustahil lolos diam-diam.
    func testPinCoordinatesBelongToTheGivenNode() throws {
        let jp = ProxyNode(name: "JP-01", proto: .vmess, host: "jp.example.com",
                           port: 443, credential: "u", countryCode: "JP")
        let sg = ProxyNode(name: "SG-01", proto: .vmess, host: "sg.example.com",
                           port: 443, credential: "u", countryCode: "SG")
        let jpLat = try XCTUnwrap(ServerWorldMap.pins(for: jp, isConnected: true).first?.lat)
        let sgLat = try XCTUnwrap(ServerWorldMap.pins(for: sg, isConnected: false).first?.lat)
        XCTAssertGreaterThan(abs(jpLat - sgLat), 10,
                             "pin harus menunjuk negara node-nya sendiri")

        // Default `isConnected` = false: pemanggil yang lupa mengoper status
        // tidak boleh diam-diam menghasilkan pin berdenyut.
        XCTAssertEqual(ServerWorldMap.pins(for: jp).first?.isActive, false)
    }

    /// 92% node di feed gratis tidak menyebut negara sama sekali (banyak yang
    /// bernama "By EbraSha"). Peta tanpa pin jauh lebih jujur daripada pin di
    /// lokasi keliru.
    func testNoPinWhenCountryUnknown() {
        let unknown = ProxyNode(name: "By EbraSha", proto: .vmess, host: "1.1.1.1",
                                port: 443, credential: "u")
        XCTAssertTrue(ServerWorldMap.pins(for: unknown).isEmpty)
        XCTAssertTrue(ServerWorldMap.pins(for: nil).isEmpty)

        let badCode = ProxyNode(name: "x", proto: .vmess, host: "1.1.1.1", port: 443,
                                credential: "u", countryCode: "ZZ")
        XCTAssertTrue(ServerWorldMap.pins(for: badCode).isEmpty)
    }

    // MARK: - Urutan server

    private func node(_ id: String, _ name: String) -> ProxyNode {
        ProxyNode(id: id, name: name, proto: .vmess, host: "1.1.1.1", port: 443,
                  credential: "u-\(id)")
    }

    func testByLatencyPutsUntestedLast() {
        let a = node("a", "A"), b = node("b", "B"), c = node("c", "C")
        var ping: [String: PingResult] = [:]
        ping["a"] = PingResult(nodeID: "a", webLatencyMs: 120, internetOK: true)
        ping["b"] = PingResult(nodeID: "b", webLatencyMs: 60, internetOK: true)
        // "c" belum diuji sama sekali.
        let sorted = ConnectView.byLatency([a, b, c], ping: ping)
        XCTAssertEqual(sorted.map(\.id), ["b", "a", "c"])
    }

    /// Node terbukti tidak punya internet tidak pernah boleh dianggap
    /// "tercepat" — `bestMs` sudah mengembalikan nil untuknya.
    func testByLatencySendsDeadNodesLast() {
        let good = node("g", "G"), dead = node("d", "D"), fresh = node("f", "F")
        var ping: [String: PingResult] = [:]
        ping["g"] = PingResult(nodeID: "g", webLatencyMs: 200, internetOK: true)
        ping["d"] = PingResult(nodeID: "d", webLatencyMs: nil, internetOK: false)
        let sorted = ConnectView.byLatency([dead, fresh, good], ping: ping)
        XCTAssertEqual(sorted.first?.id, "g")
        XCTAssertEqual(sorted.last?.id, "d", "node mati harus di paling akhir")
    }

    func testBestLatencyIgnoresDeadNodes() {
        let good = node("g", "G"), dead = node("d", "D")
        var ping: [String: PingResult] = [:]
        ping["g"] = PingResult(nodeID: "g", webLatencyMs: 90, internetOK: true)
        ping["d"] = PingResult(nodeID: "d", webLatencyMs: 10, internetOK: false)
        XCTAssertEqual(ConnectView.bestLatency(in: [good, dead], ping: ping), 90)
        XCTAssertNil(ConnectView.bestLatency(in: [dead], ping: ping))
    }

    // MARK: - Slider jatah CPU

    /// Slider 25…100 harus selalu mendarat di kelipatan 25 yang tersimpan,
    /// supaya angka di slider dan angka yang dibaca governor sama.
    ///
    /// Yang diuji adalah `AppSettings.nearestCPUShare` — satu-satunya
    /// implementasi aturan ini; `SettingsView` memakai fungsi yang sama.
    func testNearestShareSnapsToQuarterSteps() {
        XCTAssertEqual(AppSettings.nearestCPUShare(0), 25)
        XCTAssertEqual(AppSettings.nearestCPUShare(38), 50)
        XCTAssertEqual(AppSettings.nearestCPUShare(62), 50)
        XCTAssertEqual(AppSettings.nearestCPUShare(63), 75)
        XCTAssertEqual(AppSettings.nearestCPUShare(200), 100)
        for raw in stride(from: 20, through: 105, by: 5) {
            XCTAssertTrue([25, 50, 75, 100].contains(AppSettings.nearestCPUShare(raw)))
        }
    }
}
/// Form Edit Source memang sudah ada sejak D59, tapi MEMBUANG salah satu
/// field yang ditampilkan formnya sendiri. Gejalanya persis "tidak bisa
/// edit": form terbuka, kelihatan benar, menekan Simpan tidak mengubah
/// apa pun untuk field itu.
final class SourceEditFormTests: XCTestCase {

    /// Sakelar bintang muncul di form edit — sama persis dengan form tambah —
    /// jadi nilainya harus ikut tersimpan.
    @MainActor
    func testEditFormStarValueIsActuallySaved() {
        isolateStorage()
        let state = AppState()
        state.sources = [VPNSubscriptionSource(id: "s1", name: "A",
                                               url: "https://x/1.yaml", isStarred: false)]
        state.renameSource(id: "s1", name: "A", url: "https://x/1.yaml", isStarred: true)
        XCTAssertTrue(state.sources[0].isStarred,
                      "sakelar bintang di form edit dibuang diam-diam")
    }

    /// Dan membalikannya juga harus berlaku, bukan hanya menyalakan.
    @MainActor
    func testEditFormCanUnstarToo() {
        isolateStorage()
        let state = AppState()
        state.sources = [VPNSubscriptionSource(id: "s1", name: "A",
                                               url: "https://x/1.yaml", isStarred: true)]
        state.renameSource(id: "s1", name: "A", url: "https://x/1.yaml", isStarred: false)
        XCTAssertFalse(state.sources[0].isStarred)
    }

    /// Pemanggil yang tidak Care soal bintang (semua pemanggil lama) tidak
    /// boleh ikut mengubahnya — makanya parameter-nya opsional, bukan `Bool`.
    @MainActor
    func testRenameWithoutStarArgumentLeavesStarUntouched() {
        isolateStorage()
        let state = AppState()
        state.sources = [VPNSubscriptionSource(id: "s1", name: "A",
                                               url: "https://x/1.yaml", isStarred: true)]
        state.renameSource(id: "s1", name: "B", url: "https://x/1.yaml")
        XCTAssertTrue(state.sources[0].isStarred)
        XCTAssertEqual(state.sources[0].name, "B")
    }

    /// Grup manual tidak punya URL. Form editnya sempat memakai aturan validasi
    /// URL yang sama dengan form tambah, sehingga tombol Simpan-nya selalu mati
    /// dan rename grup mustahil dilakukan. Di layer ini yang dijamin adalah
    /// rename tetap berlaku tanpa URL.
    @MainActor
    func testManualGroupCanBeRenamedWithoutURL() {
        isolateStorage()
        let state = AppState()
        state.sources = [VPNSubscriptionSource(id: "g1", name: "Lama",
                                               url: "", isManualGroup: true)]
        state.renameSource(id: "g1", name: "Nama Baru", url: "", isStarred: false)
        XCTAssertEqual(state.sources[0].name, "Nama Baru")
        XCTAssertTrue(state.sources[0].isManualGroup, "status manual tidak boleh hilang")
        XCTAssertTrue(state.sources[0].url.isEmpty, "URL kosong tidak boleh diisi diam-diam")
    }

    /// Menyimpan sumber yang diedit ke URL milik sumber LAIN akan membuat dua
    /// entri untuk satu feed — persis D66, lewat pintu yang tidak dijaga.
    /// `ignoring:` dipakai supaya sumber itu sendiri tidak dianggap duplikat.
    @MainActor
    func testDuplicateCheckWhileEditingIgnoresItselfButNotOthers() {
        isolateStorage()
        let state = AppState()
        state.sources = [
            VPNSubscriptionSource(id: "s1", name: "Satu", url: "https://x/1.yaml"),
            VPNSubscriptionSource(id: "s2", name: "Dua", url: "https://y/2.yaml")
        ]
        XCTAssertFalse(state.hasSource(url: "https://x/1.yaml", ignoring: "s1"),
                       "sumber yang sedang diedit bukan duplikat dirinya sendiri")
        XCTAssertTrue(state.hasSource(url: "https://y/2.yaml", ignoring: "s1"),
                      "URL milik sumber lain tetap harus terdeteksi duplikat")
    }

    /// Bentuk URL yang berbeda tetap dianggap sama, termasuk saat menihilkan
    /// sumber sendiri — kalau tidak, `ignoring:` hanya bekerja untuk string
    /// yang persis sama.
    @MainActor
    func testDuplicateCheckIgnoringUsesNormalizedURL() {
        isolateStorage()
        let state = AppState()
        state.sources = [VPNSubscriptionSource(id: "s1", name: "Satu",
                                               url: "https://x/1.yaml")]
        XCTAssertFalse(state.hasSource(url: "HTTPS://X/1.yaml/", ignoring: "s1"))
    }
}
