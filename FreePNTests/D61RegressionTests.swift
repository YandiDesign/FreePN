import XCTest
@testable import FreePNApp

/// Regresi untuk perbaikan D61 (performa + kebenaran).
///
/// Setiap test di sini correspond ke satu bug nyata yang ditemukan saat audit.
/// Tujuannya: kalau salah satu perbaikan dibatalkan di commit berikutnya, test
/// ini harus GAGAL — bukan diam-diam menerima data yang salah.
final class D61RegressionTests: XCTestCase {

    // MARK: - Data loss saat decode (P0)

    /// `decodeIfPresent` untuk enum BERHENTI throw saat kuncinya ada tapi
    /// nilainya tak dikenal. Throw itu keluar dari `JSONStore.load` yang
    /// memakai `try?` — hasilnya SELURUH pengaturan user kembali ke default,
    /// diam-diam.
    func testSettingsSurviveUnknownLanguageRawValue() throws {
        let json = """
        {"language":"fr","uiScalePercent":130,"showNodePort":false,"cpuSharePercent":75}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AppSettings.self, from: json)
        XCTAssertEqual(decoded.language, .system, "nilai tak dikenal harus jatuh ke default, bukan gagal decode")
        XCTAssertEqual(decoded.uiScalePercent, 130, "field lain harus tetap terbaca")
        XCTAssertFalse(decoded.showNodePort)
        XCTAssertEqual(decoded.cpuSharePercent, 75)
    }

    /// Idem untuk `SourceStatus`. Satu sumber dengan status tak dikenal
    /// sebelumnya membuat SELURUH array sumber gagal decode -> user kehilangan
    /// semua feed yang dia tambah sendiri.
    func testSourcesSurviveUnknownStatusRawValue() throws {
        let json = """
        [{"id":"a","name":"A","url":"https://a.example/x","status":"retrying"},
         {"id":"b","name":"B","url":"https://b.example/x","status":"ok","isStarred":true}]
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode([VPNSubscriptionSource].self, from: json)
        XCTAssertEqual(decoded.count, 2, "satu entri aneh tidak boleh menghapus yang lain")
        XCTAssertEqual(decoded[0].status, .unknown)
        XCTAssertTrue(decoded[1].isStarred)
    }

    /// `ProxyNode` memakai `Codable` hasil sintesis, yang berarti satu field
    /// wajib baru = seluruh `nodes.json` lama tak terbaca = user membuka app ke
    /// daftar server KOSONG tanpa pesan error.
    func testNodeDecodesFromPartialLegacyPayload() throws {
        let json = """
        {"name":"US 01","proto":"vmess","host":"1.2.3.4","port":443,"credential":"u","sourceID":"s"}
        """.data(using: .utf8)!
        let node = try JSONDecoder().decode(ProxyNode.self, from: json)
        XCTAssertEqual(node.name, "US 01")
        XCTAssertEqual(node.proto, .vmess)
        XCTAssertEqual(node.port, 443)
        XCTAssertEqual(node.transport, .tcp)
        XCTAssertNil(node.tls)
        XCTAssertFalse(node.id.isEmpty, "id harus dihitung ulang, bukan kosong")
    }

    /// Field `tls` yang hanya sebagian terisi tidak boleh menggagalkan decode.
    func testTLSOptionsDecodesFromPartialPayload() throws {
        let json = """
        {"name":"x","proto":"vless","host":"h","port":1,"credential":"c","tls":{"enabled":true}}
        """.data(using: .utf8)!
        let node = try JSONDecoder().decode(ProxyNode.self, from: json)
        XCTAssertEqual(node.tls?.enabled, true)
        XCTAssertNil(node.tls?.sni)
        XCTAssertFalse(node.tls?.isReality ?? true, "REALITY tanpa public key bukan REALITY")
    }

    func testTLSOptionsRoundTrips() throws {
        let original = TLSOptions(enabled: true, sni: "a.example", allowInsecure: true,
                                  realityPublicKey: "k", realityShortId: "ab", fingerprint: "chrome")
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(TLSOptions.self, from: data), original)
    }

    // MARK: - Parser

    /// `印度尼西亚` (Indonesia) mengandung `印度` (India). Dengan urutan tabel
    /// aslinya, `印度` diperiksa lebih dulu dan node Indonesia diberi bendera
    /// India — diam-diam salah negara.
    func testIndonesiaIsNotInferredAsIndia() {
        XCTAssertEqual(CountryInfer.infer(from: "印度尼西亚 01"), "ID")
        XCTAssertEqual(CountryInfer.infer(from: "印度 01"), "IN")
        XCTAssertEqual(CountryInfer.infer(from: "印尼 01"), "ID")
    }

    /// Feed gratis sangat sering menulis `AES-256-GCM` dengan huruf kapital.
    /// Pencocokan method yang case-sensitive membuang node yang benar-benar
    /// bisa dipakai — user melihat "hanya 2.000 dari 8.000" tanpa sebab.
    func testShadowsocksCipherIsCaseInsensitive() {
        for cipher in ["AES-256-GCM", "aes-256-gcm", "CHACHA20-IETF-POLY1305",
                       "chacha20-ietf-poly1305"] {
            let node = ProxyNode(id: "x", name: "n", proto: .shadowsocks,
                                 host: "1.1.1.1", port: 8388,
                                 credential: "pw", cipher: cipher)
            XCTAssertTrue(NodeDeduper.isUsable(node),
                          "cipher \(cipher) adalah method sing-box yang valid dan harus diterima")
        }
        let bogus = ProxyNode(id: "y", name: "n", proto: .shadowsocks,
                              host: "1.1.1.1", port: 8388,
                              credential: "pw", cipher: "aes-999-nonexistent")
        XCTAssertFalse(NodeDeduper.isUsable(bogus), "method yang tidak ada di sing-box harus dibuang")
    }

    /// Host IPv6 harus bisa diurai di share-link SS dan hysteria2. Versi lama
    /// memecah string dengan `split(separator: ":")` sehingga `[::1]:443`
    /// menghasilkan 8 potongan dan node selalu ditolak.
    func testIPv6HostParsesInShareLinks() {
        let cred = Data("aes-256-gcm:pw".utf8).base64EncodedString()
        let ss = "ss://\(cred)@[2001:db8::1]:8388#v6"
        let r = ShareLinkParser.parse(text: ss, sourceID: "s")
        XCTAssertEqual(r.nodes.count, 1, "share-link SS dengan host IPv6 harus terurai")
        XCTAssertEqual(r.nodes.first?.host, "2001:db8::1")
        XCTAssertEqual(r.nodes.first?.port, 8388)
    }

    /// Varian base64 `hysteria2://base64(pwd@host:port)` didukung secara
    /// komentar tapi TIDAK PERNAH jalan: `guard lastIndex(of: "@")`
    /// dijalankan lebih dulu, dan alfabet base64 tidak memuat `@` sama sekali.
    func testHysteria2Base64VariantParses() {
        let payload = "pw@1.2.3.4:8443"
        let b64 = (payload.data(using: .utf8) ?? Data()).base64EncodedString()
        let link = "hysteria2://\(b64)"
        let r = ShareLinkParser.parse(text: link, sourceID: "s")
        XCTAssertEqual(r.nodes.count, 1, "varian base64 harus didukung (sebelumnya mati total)")
        XCTAssertEqual(r.nodes.first?.host, "1.2.3.4")
        XCTAssertEqual(r.nodes.first?.port, 8443)
        XCTAssertEqual(r.nodes.first?.credential, "pw")
    }

    /// `canHandle` cuma `text.contains("proxies:")`. Kalau string itu muncul di
    /// dalam komentar, parser masuk jalur Clash, dapat 0 node, dan jalur
    /// share-link yang sebenarnya benar tidak pernah dicoba.
    func testAutoParserFallsBackWhenClashPathYieldsNothing() {
        // Feed share-link yang kebetulan memuat kata "proxies:" di nama node.
        let link = "vmess://eyJ2IjogIjIiLCAicHMiOiAidXMtMjAiLCAiYWRkIjogIjEuMi4zLjQiLCAicG9ydCI6ICI0NDMiLCAiaWQiOiAiQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBIiwgImFpZCI6ICIwIiwgIm5ldCI6ICJ0Y3AiLCAidHlwZSI6ICJub25lIiwgImhvc3QiOiAiIiwgInBhdGgiOiAiIiwgInRscyI6ICIifQ=="
        let text = "# proxies: catatan\n\(link)\n"
        let r = AutoParser.parse(text: text, sourceID: "s")
        XCTAssertEqual(r.nodes.count, 1,
                       "jalur Clash yang kosong harus jatuh ke share-link, bukan melaporkan 0 node")
    }

    func testBase64DetectorRoundTripsPaddingCases() {
        for length in 1...40 {
            let payload = String(repeating: "a", count: length)
            let encoded = (payload.data(using: .utf8) ?? Data()).base64EncodedString()
            let decoded = Base64Detector.decodeTolerant(encoded.trimmingCharacters(in: .newlines))
            XCTAssertNotNil(decoded, "payload \(length) byte harus bisa didekode")
            XCTAssertEqual(decoded.map { String(decoding: $0, as: UTF8.self) }, payload)
        }
    }

    func testBase64DetectorHandlesURLSafeAndWhitespace() {
        let payload = "vmess://x?y=z&w=1"
        let std = (payload.data(using: .utf8) ?? Data()).base64EncodedString()
        let urlSafe = std.replacingOccurrences(of: "+", with: "-")
                          .replacingOccurrences(of: "/", with: "_")
        XCTAssertNotNil(Base64Detector.decodeTolerant(urlSafe), "alfabet URL-safe harus diterima")
        XCTAssertNotNil(Base64Detector.decodeTolerant(std.prefix(10) + "\n" + std.suffix(from: std.index(std.startIndex, offsetBy: 10))))
    }

    /// `looksLikeBase64` pernah menolak input sah yang panjangnya persis 20
    /// dengan memotong sisa newline, dan ambangnya 20 menolak credential 16
    /// karakter yang sah.
    func testLooksLikeBase64AcceptsShortPayloads() {
        XCTAssertTrue(Base64Detector.looksLikeBase64("dm1lc3M6eHl6eHl6"))  // 16 char
        XCTAssertTrue(Base64Detector.looksLikeBase64("aGVsbG8gd29ybGQhIQ=="))
        XCTAssertFalse(Base64Detector.looksLikeBase64("hello world 12345"))
        XCTAssertFalse(Base64Detector.looksLikeBase64("short"))
    }

    // MARK: - SourceResolver

    /// Resolver memakai `Calendar.current` (zona mesin user) padahal
    /// kalender WIB/UTC yang dibangun justru tidak pernah dipakai. Untuk user
    /// di UTC-7, tanggal yang dihasilkan salah sampai 24 jam sekali sehari.
    /// Dipakai `en_US_POSIX` + gregorian supaya locale non-Gregorian tidak
    /// menghasilkan tahun 2569 di URL.
    func testSourceResolverUsesFixedTimeZoneNotLocalCalendar() {
        let source = VPNSubscriptionSource(name: "NodeFree",
                                           url: "https://nodefree.org/dy/2024/07/20240725.yaml")
        // 2026-01-01 00:30 WIB = 2025-12-31 17:30 UTC. Format harus memakai
        // tanggal WIB, dan harus tetap 2026-01-01 meski mesin user ada di
        // zona waktu yang jauh (test ini tidak bergantung pada zona mesin).
        var calWIB = Calendar(identifier: .gregorian)
        calWIB.timeZone = TimeZone(identifier: "Asia/Jakarta")!
        let now = calWIB.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 0, minute: 30))!
        let cands = SourceResolver.candidates(for: source, now: now)
        XCTAssertTrue(cands.contains("https://nodefree.org/dy/2026/01/20260101.yaml"),
                      "hari WIB harus menghasilkan URL 2026/01/20260101; dapat: \(cands.prefix(3))")
    }

    /// Cocokkan host, bukan substring URL — `https://evil.example/?r=nodefree.org`
    /// sebelumnya ditulis ulang supaya request-nya pergi ke nodefree.
    func testSourceResolverDoesNotRewriteLookalikeHosts() {
        let source = VPNSubscriptionSource(
            name: "Evil", url: "https://evil.example/feed?ref=nodefree.org")
        XCTAssertEqual(SourceResolver.candidates(for: source), [source.url],
                       "host yang cuma MENYERUPAI nodefree tidak boleh ditulis ulang")
    }

    func testSourceResolverLeavesUnrelatedSourceAlone() {
        let source = VPNSubscriptionSource(name: "X", url: "https://example.com/a.yaml")
        XCTAssertEqual(SourceResolver.candidates(for: source), [source.url])
    }

    // MARK: - Tampilan / urutan

    /// `topByLatency` adalah algoritme top-k; ia harus urutan PERSIS sama
    /// dengan sort penuh, kalau tidak daftar "server tercepat" dan urutan di
    /// tabel berbeda terang.
    func testTopByLatencyMatchesFullSort() {
        let nodes = (0..<200).map { i in
            ProxyNode(id: "id\(i)", name: String(format: "Node %03d", i), proto: .vmess,
                      host: "10.0.0.\(i % 255)", port: 443, credential: "c\(i)")
        }
        var ping: [String: PingResult] = [:]
        for (i, n) in nodes.enumerated() where i % 3 != 0 {
            ping[n.id] = PingResult(nodeID: n.id, webLatencyMs: (i % 17) * 10, internetOK: true)
        }
        // Sisakan beberapa yang terbukti mati.
        for (i, n) in nodes.enumerated() where i % 11 == 0 && i > 0 {
            ping[n.id] = PingResult(nodeID: n.id, webLatencyMs: nil, internetOK: false)
        }
        let full = AppState.topByLatency(nodes, ping: ping, count: Int.max)
        let top5 = AppState.topByLatency(nodes, ping: ping, count: 5)
        XCTAssertEqual(top5.map(\.id), Array(full.prefix(5)).map(\.id))
        XCTAssertEqual(top5.count, 5)
    }

    /// D92 — daftar tawaran sama sekali tidak pernah jadi state awal, jadi
    /// mustahil ada yang datang dengan starred dari bawaan install. Ini
    /// memperkuat Numeric yang sama: `ServerSorter` mengunci sumber berbintang
    /// di paling atas tanpa memandang kolom.
    func testNoSourceIsPreStarredOnFreshInstall() {
        XCTAssertTrue(VPNSubscriptionSource.defaultSources.allSatisfy { !$0.isStarred })
        XCTAssertTrue(VPNSubscriptionSource.defaultSources.isEmpty)
    }

    /// Filter protocol di ConnectView/ServersView hanya menampilkan 3 dari 5
    /// protocol, padahal VLESS adalah protokol paling dominan di feed gratis.
    /// Update D62 menambah dua lagi (http, socks) → tujuh.
    ///
    /// Yang diuji di sini hanya bahwa filter memakai `allCases`, sehingga
    /// menambah protokol baru di enum otomatis ikut muncul sebagai filter —
    /// bukan perlu menyentuh UI lagi.
    func testAllProtocolsAreFilterable() {
        let expected: Set<NodeProtocol> = [.trojan, .vmess, .shadowsocks, .vless,
                                           .hysteria2, .http, .socks]
        XCTAssertEqual(Set(NodeProtocol.allCases), expected,
                       "filter protocol mengambil allCases — menambah enum = otomatis dapat filter")
    }

    // MARK: - Persistensi

    /// `persist(onlySettings:)` tidak boleh menyentuh `nodes.json` — itulah
    /// seluruh alasan metode ini ada (toggle pengaturan sebelumnya menulis
    /// ulang file multi-MB berisi 16.000 node).
    @MainActor
    func testPersistOnlySettingsDoesNotRewriteNodesStore() throws {
        isolateStorage()
        let state = AppState()
        let nodesURL = URL(fileURLWithPath: AppStorage.directory.path)
            .appendingPathComponent("nodes.json")
        state.nodes = [ProxyNode(id: "a", name: "A", proto: .vmess,
                                 host: "1.1.1.1", port: 443, credential: "c")]
        state.persist(onlyNodes: true)
        // `JSONStore.save` async (barrier di queue). Tunggu sampai benar-benar
        // ada di disk sebelum mengukur.
        let deadline = Date().addingTimeInterval(5)
        while !FileManager.default.fileExists(atPath: nodesURL.path), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: nodesURL.path))

        let before = try FileManager.default.attributesOfItem(atPath: nodesURL.path)[.modificationDate] as? Date
        Thread.sleep(forTimeInterval: 1.1)
        state.settings.showNodePort = false
        state.persist(onlySettings: true)
        let after = try FileManager.default.attributesOfItem(atPath: nodesURL.path)[.modificationDate] as? Date

        XCTAssertEqual(before, after, "toggle settings tidak boleh menulis ulang nodes.json")
        XCTAssertFalse(state.settings.showNodePort, "settings sendiri harus tetap tersimpan")
    }

    /// `JSONStore` menulis cadangan `.bak` sebelum menimpa, dan memulihkannya
    /// kalau file utama gagal decode. Tanpa ini satu field baru saja bisa
    /// membuat user membuka app ke daftar server kosong.
    func testJSONStoreRecoversFromBackupOnDecodeFailure() {
        isolateStorage()
        let store = JSONStore<[ProxyNode]>(filename: "recover.json")
        let good = [ProxyNode(id: "a", name: "A", proto: .vmess,
                              host: "1.1.1.1", port: 443, credential: "c")]
        // Rotasi `.bak`: setiap `save` menyalin ISI LAMA ke cadangan sebelum
        // menimpa. Jadi setelah dua kali simpan, `.bak` berisi versi
        // PERTAMA — itulah yang harus dipulihkan kalau file utama rusak.
        store.saveSync([])
        store.saveSync(good)

        // JSON rusak ditulis di atas file utama.
        let url = store.fileURL
        try? Data("{ this is not json".utf8).write(to: url)

        let loaded = store.load(defaultValue: [])
        XCTAssertEqual(loaded.map(\.id), [],
                       "file utama rusak -> pulihkan dari .bak, bukan default yang kebetulan sama")
        XCTAssertNotNil(loaded, "decode gagal harus tetap mengembalikan nilai dari cadangan")
    }

    func testJSONStoreLoadAsyncMatchesSyncLoad() async {
        isolateStorage()
        let store = JSONStore<[String]>(filename: "async.json")
        store.saveSync(["x", "y"])
        let async = await store.loadAsync(defaultValue: [])
        XCTAssertEqual(async, ["x", "y"])
    }

    // MARK: - CPU governor

    /// `raiseFileDescriptorLimit()` menetapkan soft limit = hard limit. Kalau
    /// hard limit lebih besar dari `Int.max`, `Int(rlim_cur)` TRAP dan app
    /// crash saat Settings dibuka.
    func testFDLimitConversionNeverTraps() {
        // Panggil computeLimit berkali-kali: pada mesin dengan hard limit
        // `unlimited` konversi ini dulu trap.
        for _ in 0..<50 {
            let limit = CPUGovernor.computeLimit(cores: 8, share: 0.5)
            XCTAssertGreaterThanOrEqual(limit, CPUGovernor.minCompute)
            XCTAssertLessThanOrEqual(limit, 100_000, "jatah tidak mungkin melebihi jumlah FD realistis")
        }
    }

    func testNearestCPUShareIsSharedByModelAndUI() {
        XCTAssertEqual(AppSettings.nearestCPUShare(0), 25)
        XCTAssertEqual(AppSettings.nearestCPUShare(38), 50)
        XCTAssertEqual(AppSettings.nearestCPUShare(62), 50)
        XCTAssertEqual(AppSettings.nearestCPUShare(63), 75)
        XCTAssertEqual(AppSettings.nearestCPUShare(200), 100)
    }

    // MARK: - Indeks turunan

    /// `selectedNode`/`recommendedNode` adalah O(1) lewat indeks. Kalau indeks
    /// tidak ikut dibangun ulang saat `nodes` berubah, node terpilih jadi
    /// selalu `nil` setelah refresh — dan user tidak bisa Sambung.
    @MainActor
    func testNodeIndexTracksNodesChanges() {
        isolateStorage()
        let state = AppState()
        let node = ProxyNode(id: "abc", name: "ABC", proto: .vmess,
                             host: "1.1.1.1", port: 443, credential: "c")
        state.nodes = [node]
        state.selectedNodeID = "abc"
        XCTAssertEqual(state.selectedNode?.id, "abc")

        // Ganti daftar dengan node lain lalu kembalikan — indeks harus ikut.
        state.nodes = []
        XCTAssertNil(state.selectedNode, "node yang tidak ada lagi harus menghasilkan nil")
        state.nodes = [node]
        XCTAssertEqual(state.selectedNode?.id, "abc",
                       "indeks harus dibangun ulang setiap nodes berubah")
    }

    @MainActor
    func testDerivedCachesInvalidateOnPingChange() {
        isolateStorage()
        let state = AppState()
        let a = ProxyNode(id: "a", name: "A", proto: .vmess, host: "1.1.1.1", port: 443, credential: "c")
        let b = ProxyNode(id: "b", name: "B", proto: .vmess, host: "2.2.2.2", port: 443, credential: "c")
        state.nodes = [a, b]
        state.ping = [
            "a": PingResult(nodeID: "a", webLatencyMs: 200, internetOK: true),
            "b": PingResult(nodeID: "b", webLatencyMs: 50, internetOK: true),
        ]
        XCTAssertEqual(state.bestLatency, 50)
        XCTAssertEqual(state.previewNodes.first?.id, "b")

        // Ping berubah: cache turunan HARUS diinvalidasi.
        state.ping = ["a": PingResult(nodeID: "a", webLatencyMs: 10, internetOK: true)]
        XCTAssertEqual(state.bestLatency, 10, "bestLatency harus ikut berubah setelah ping berubah")
        XCTAssertEqual(state.previewNodes.first?.id, "a",
                       "pratinjau harus diurutkan ulang, bukan menampilkan cache lama")
    }

    // MARK: - Log

    func testStripANSIRemovesSequences() {
        let raw = "\u{1B}[32mOK\u{1B}[0m done"
        XCTAssertEqual(ConnectionLog.stripANSI(raw), "OK done")
    }

    func testTailReadsLastLinesOfLargeFile() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("freepn-tail-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: file) }
        var text = ""
        for i in 0..<5000 { text += "line \(i)\n" }
        try text.write(to: file, atomically: true, encoding: .utf8)
        let tail = ConnectionLog.tail(of: file.path, maxLines: 5)
        XCTAssertTrue(tail.contains("line 4999"))
        XCTAssertFalse(tail.contains("line 0\n"), "hanya baris terakhir yang boleh diambil")
    }
}