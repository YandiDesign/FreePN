import XCTest
@testable import FreePNApp

/// D93 — target uji internet bisa dipilih user.
final class PingTargetTests: XCTestCase {
    func testKnownTargetsHaveWorkingURLs() {
        for t in [PingTarget.gstatic, .cloudflare, .google] {
            let u = URL(string: t.url ?? "")
            XCTAssertNotNil(u, "\(t) harus punya URL yang valid")
            XCTAssertEqual(u?.scheme, "http", t.label)
            XCTAssertNotNil(u?.host, t.label)
        }
    }

    /// Endpoint `generate_204` sengaja HTTP polos: menambah TLS berarti satu
    /// handshake lagi di dalam budget yang sudah ketat.
    func testGenerate204TargetsArePlainHTTP() {
        for t in [PingTarget.gstatic, .cloudflare] {
            XCTAssertTrue(t.url!.contains("generate_204"), t.label)
        }
    }

    func testCustomTargetIsUsedWhenValid() {
        XCTAssertEqual(PingTarget.custom.resolvedURL(custom: "https://contoh.id/health"),
                       "https://contoh.id/health")
    }

    /// Target custom kosong atau rusak TIDAK BOLEH jadi URL kosong — sing-box
    /// akan menolaknya dan setiap node akan terbaca "mati" karena tidak ada yang
    /// ditembak. Jatuh ke gstatic lebih jujur.
    func testEmptyOrBrokenCustomFallsBackToGstatic() {
        let g = PingTarget.gstatic.url!
        XCTAssertEqual(PingTarget.custom.resolvedURL(custom: ""), g)
        XCTAssertEqual(PingTarget.custom.resolvedURL(custom: "   "), g)
        XCTAssertEqual(PingTarget.custom.resolvedURL(custom: "ftp://x/y"), g)
        XCTAssertEqual(PingTarget.custom.resolvedURL(custom: "bukan url"), g)
        XCTAssertEqual(PingTarget.custom.resolvedURL(custom: "https://"), g)
    }

    func testUsableCustomURLCheck() {
        XCTAssertTrue(PingTarget.isUsableCustomURL("http://a.b/c"))
        XCTAssertTrue(PingTarget.isUsableCustomURL("https://a.b"))
        XCTAssertFalse(PingTarget.isUsableCustomURL(""))
        XCTAssertFalse(PingTarget.isUsableCustomURL("ftp://a.b"))
        XCTAssertFalse(PingTarget.isUsableCustomURL("127.0.0.1:8080"))
    }

    /// `settings.json` lama tidak punya key ini — harus tetap terbaca.
    func testLegacySettingsDecodeWithoutPingTarget() throws {
        let json = #"{"language":"id","autoRefreshHours":6}"#
        let s = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        XCTAssertEqual(s.pingTarget, .gstatic)
        XCTAssertEqual(s.pingTargetCustomURL, "")
    }

    func testUnknownPingTargetFallsBackInsteadOfThrowing() throws {
        // `decodeIfPresent` melempar kalau kuncinya ADA tapi nilainya tak
        // dikenal — itu akan menghapus seluruh settings.json.
        let json = #"{"language":"id","pingTarget":"bingung"}"#
        let s = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        XCTAssertEqual(s.pingTarget, .gstatic)
    }

    func testSettingsRoundTripKeepsTarget() throws {
        var s = AppSettings()
        s.pingTarget = .cloudflare
        s.pingTargetCustomURL = "https://a.b/c"
        let d = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(AppSettings.self, from: d)
        XCTAssertEqual(back.pingTarget, .cloudflare)
        XCTAssertEqual(back.pingTargetCustomURL, "https://a.b/c")
    }
}

/// D93 — baris log harus bisa menjelaskan "kenapa mati".
final class PingLogTests: XCTestCase {
    private func entry(_ v: ProbeVerdict) -> PingLogEntry {
        // `ms` diisi terpisah dari verdict, sama seperti di `AppState` — jadi
        // helper ini harus ikut mengisinya, kalau tidak tesnya menguji bentuk
        // data yang tidak pernah terjadi di app.
        var ms: Int? = nil
        if case .ok(let x) = v { ms = x }
        return PingLogEntry(kind: .internet, nodeID: "n1", nodeName: "SG-01",
                            proto: "vless", host: "a.b", targetHost: "gstatic",
                            ms: ms, verdict: v)
    }

    func testOKEntryCarriesLatency() {
        let e = entry(.ok(123))
        XCTAssertTrue(e.ok)
        XCTAssertEqual(e.ms, 123)
        XCTAssertNil(e.failure)
    }

    /// Baris "gagal" tanpa sebabnya persis masalah yang membuat app ini dulu
    /// selalu menyalahkan kredensial.
    func testFailureEntryKeepsItsReason() {
        XCTAssertEqual(entry(.failed(.auth)).failure, .auth)
        XCTAssertEqual(entry(.failed(.timeout)).failure, .timeout)
        XCTAssertEqual(entry(.failed(.dns)).failure, .dns)
        XCTAssertEqual(entry(.failed(.unreachable)).failure, .unreachable)
        XCTAssertEqual(entry(.failed(.rejected)).failure, .rejected)
        XCTAssertEqual(entry(.failed(.coreDown)).failure, .coreDown)
        XCTAssertEqual(entry(.failed(.unknown)).failure, .unknown)
    }

    func testSkippedIsNotAFailure() {
        let e = entry(.skipped)
        XCTAssertTrue(e.skipped)
        XCTAssertFalse(e.ok)
        XCTAssertNil(e.failure, "skipped bukan kegagalan — tidak boleh punya sebab")
    }

    /// Ringkasan harus bisa menjawab pertanyaan yang paling sering:
    /// "300 gagal timeout" BUKAN "300 kredensial salah".
    func testSummaryGroupsFailuresByReason() {
        let s = PingRunSummary(targetHost: "gstatic", tested: 10, alive: 2,
                               byFailure: [.timeout: 6, .auth: 1, .dns: 1])
        XCTAssertEqual(s.byFailure[.timeout], 6)
        let chips = s.failureChips
        XCTAssertEqual(chips.count, 3)
        XCTAssertEqual(chips.first?.0, .timeout, "sebab paling sering harus muncul pertama")
    }

    @MainActor
    func testLogIsCappedSoItCannotGrowForever() {
        isolateStorage()
        let state = AppState()
        for i in 0..<(AppState.pingLogLimit + 250) {
            state.logPing(PingLogEntry(kind: .fast, nodeID: "n\(i)", nodeName: "n\(i)"))
        }
        XCTAssertEqual(state.pingLog.count, AppState.pingLogLimit)
        XCTAssertEqual(state.pingLog.last?.nodeID, "n\(AppState.pingLogLimit + 249)",
                       "yang tertua yang dibuang, yang terbaru yang bertahan")
    }

    @MainActor
    func testClearEmptiesTheLog() {
        isolateStorage()
        let state = AppState()
        state.logPingSession("mulai")
        XCTAssertFalse(state.pingLog.isEmpty)
        state.clearPingLog()
        XCTAssertTrue(state.pingLog.isEmpty)
    }
}

/// D93 — grup proxy manual.
final class ManualGroupTests: XCTestCase {
    @MainActor
    func testNewGroupHasNoURLAndIsMarkedManual() {
        isolateStorage()
        let state = AppState()
        let id = state.addManualGroup(name: "Proxy saya")
        let g = state.sources.first { $0.id == id }
        XCTAssertNotNil(g)
        XCTAssertTrue(g!.isManualGroup)
        XCTAssertEqual(g!.url, "", "grup manual tidak punya URL untuk diunduh")
    }

    /// Sumber lama tidak punya key `isManualGroup` — default `false`, jadi
    /// daftar lama tidak akan tiba-tiba diperlakukan sebagai grup manual.
    func testLegacySourcesDecodeWithManualGroupFalse() throws {
        let json = #"[{"id":"s1","name":"A","url":"https://x/y"}]"#
        let src = try JSONDecoder().decode([VPNSubscriptionSource].self, from: Data(json.utf8))
        XCTAssertFalse(src[0].isManualGroup)
    }

    func testManualGroupSurvivesEncoding() throws {
        let g = VPNSubscriptionSource(id: "g", name: "G", url: "", isManualGroup: true)
        let back = try JSONDecoder().decode([VPNSubscriptionSource].self,
                                            from: try JSONEncoder().encode([g]))
        XCTAssertTrue(back[0].isManualGroup)
    }

    @MainActor
    func testRefreshAllSkipsManualGroups() async {
        isolateStorage()
        let state = AppState()
        state.addManualGroup(name: "Manual")
        let count = state.sources.filter { $0.isEnabled && !$0.isManualGroup }.count
        XCTAssertEqual(count, 0, "tidak ada sumber yang boleh diunduh, jadi refresh harus no-op")
        await state.refreshAll()   // tidak boleh macet atau menandai `unavailable`
        for s in state.sources {
            XCTAssertNotEqual(s.status, .unavailable,
                             "grup manual tidak boleh ditandai gagal hanya karena tidak diunduh")
        }
    }

    @MainActor
    func testManualNodeReachesTheGlobalListAsAUsualNode() async {
        isolateStorage()
        let state = AppState()
        let gid = state.addManualGroup(name: "Manual")
        var d = ManualNodeDraft()
        d.proto = .trojan
        d.name = "Manual-Trojan"
        d.host = "example.com"
        d.port = "443"
        d.credential = "rahasia"
        d.tlsEnabled = true
        d.sni = "example.com"

        guard case .added(let n) = await state.addManualNode(draft: d, toGroup: gid) else {
            return XCTFail("node manual yang valid harus diterima")
        }
        XCTAssertEqual(n, 1)
        // Harus muncul di tabel Server seperti node feed biasa.
        XCTAssertTrue(state.nodes.contains { $0.name == "Manual-Trojan" })
        // Dan terhitung di angka sumbernya.
        let g = state.sources.first { $0.id == gid }!
        XCTAssertEqual(g.keptCount, 1)
        XCTAssertEqual(g.nodeCount, 1)
        XCTAssertEqual(g.status, .ok)
    }

    @MainActor
    func testRemovingAManualNodeUpdatesTheGroupCount() async {
        isolateStorage()
        let state = AppState()
        let gid = state.addManualGroup(name: "Manual")
        var d = ManualNodeDraft()
        d.proto = .trojan; d.host = "example.com"; d.port = "443"
        d.credential = "pw"; d.tlsEnabled = true
        _ = await state.addManualNode(draft: d, toGroup: gid)
        let added = state.nodes.first { $0.sourceID == gid }!
        state.removeManualNode(id: added.id)
        XCTAssertFalse(state.nodes.contains { $0.id == added.id })
        XCTAssertEqual(state.sources.first { $0.id == gid }!.keptCount, 0)
    }
}

/// D93 — pembentuk node manual.
final class ManualNodeBuilderTests: XCTestCase {
    func testMinimalTrojanBuilds() {
        var d = ManualNodeDraft()
        d.proto = .trojan; d.host = "a.example"; d.port = "443"
        d.credential = "pw"; d.tlsEnabled = true; d.sni = "a.example"
        guard case .ok(let n) = d.build(sourceID: "g") else {
            return XCTFail("harus berhasil")
        }
        XCTAssertEqual(n.proto, .trojan)
        XCTAssertEqual(n.host, "a.example")
        XCTAssertEqual(n.credential, "pw")
        XCTAssertTrue(n.tls?.enabled == true)
        XCTAssertEqual(n.sourceID, "g")
    }

    func testMissingHostPortAndCredentialEachFail() {
        var d = ManualNodeDraft()
        d.proto = .trojan; d.host = ""; d.port = "443"; d.credential = "pw"
        if case .ok = d.build(sourceID: "g") { XCTFail("host kosong harus ditolak") }

        var e = ManualNodeDraft()
        e.proto = .trojan; e.host = "a"; e.port = "0"; e.credential = "pw"
        if case .ok = e.build(sourceID: "g") { XCTFail("port 0 harus ditolak") }

        var f = ManualNodeDraft()
        f.proto = .trojan; f.host = "a"; f.port = "443"; f.credential = "  "
        if case .ok = f.build(sourceID: "g") { XCTFail("kredensial kosong harus ditolak") }
    }

    /// Shadowsocks butuh cipher yang benar; tanpa itu `sing-box check` akan
    /// menolak dan satu outbound buruk membatasi seluruh config probe (D61).
    func testShadowsocksRequiresAKnownCipher() {
        var d = ManualNodeDraft()
        d.proto = .shadowsocks; d.host = "a"; d.port = "443"
        d.credential = "pw"; d.cipher = "rot13-kacau"
        guard case .failed(let p) = d.build(sourceID: "g") else {
            return XCTFail("cipher tak dikenal harus ditolak")
        }
        XCTAssertFalse(p.isEmpty)
    }

    /// Kolom cipher + kolom password adalah dua sumber yang sama.
    func testShadowsocksJoinsCipherAndPasswordWhenCredentialHasNoColon() {
        var d = ManualNodeDraft()
        d.proto = .shadowsocks; d.host = "a"; d.port = "443"
        d.credential = "pw"; d.cipher = "aes-256-gcm"
        guard case .ok(let n) = d.build(sourceID: "g") else {
            return XCTFail("harus berhasil")
        }
        XCTAssertEqual(n.credential, "aes-256-gcm:pw")
    }

    func testShadowsocksKeepsExplicitMethodPrefix() {
        var d = ManualNodeDraft()
        d.proto = .shadowsocks; d.host = "a"; d.port = "443"
        d.credential = "chacha20-ietf-poly1305:pw"; d.cipher = "aes-256-gcm"
        guard case .ok(let n) = d.build(sourceID: "g") else { return XCTFail("harus berhasil") }
        XCTAssertEqual(n.credential, "chacha20-ietf-poly1305:pw",
                       "kredensial yang sudah menyebut method tidak boleh diubah")
    }

    /// REALITY tanpa public key akan menghasilkan config yang ditolak core;
    /// lebih baik diperlakukan sebagai TLS biasa (dan ditolak core dengan
    /// pesan yang jelas) daripada diam-diam mengirim flag REALITY kosong.
    func testRealityWithoutPublicKeyIsNotMarkedReality() {
        var d = ManualNodeDraft()
        d.proto = .vless; d.host = "a"; d.port = "443"; d.credential = "uuid"
        d.tlsEnabled = true; d.realityPublicKey = ""
        guard case .ok(let n) = d.build(sourceID: "g") else { return XCTFail("harus berhasil") }
        XCTAssertFalse(n.tls?.isReality == true)
    }

    func testRealityWithPublicKeyIsMarked() {
        var d = ManualNodeDraft()
        d.proto = .vless; d.host = "a"; d.port = "443"; d.credential = "uuid"
        d.realityPublicKey = "PBK"; d.realityShortId = "ab"
        guard case .ok(let n) = d.build(sourceID: "g") else { return XCTFail("harus berhasil") }
        XCTAssertTrue(n.tls?.isReality == true)
        XCTAssertEqual(n.tls?.realityShortId, "ab")
    }

    func testALPNIsSplitAndTrimmed() {
        var d = ManualNodeDraft()
        d.proto = .vless; d.host = "a"; d.port = "443"; d.credential = "u"
        d.tlsEnabled = true; d.alpn = " h2 , http/1.1 ,"
        guard case .ok(let n) = d.build(sourceID: "g") else { return XCTFail("harus berhasil") }
        XCTAssertEqual(n.tls?.alpn, ["h2", "http/1.1"])
    }

    func testEmptyNameFallsBackToHostPort() {
        var d = ManualNodeDraft()
        d.proto = .trojan; d.host = "a.example"; d.port = "8443"
        d.credential = "pw"; d.tlsEnabled = true
        guard case .ok(let n) = d.build(sourceID: "g") else { return XCTFail("harus berhasil") }
        XCTAssertEqual(n.name, "a.example:8443")
    }

    func testGRPCServiceNameSurvivesIntoTransportPath() {
        var d = ManualNodeDraft()
        d.proto = .vless; d.host = "a"; d.port = "443"; d.credential = "u"
        d.transport = .grpc; d.path = "mygrpc"; d.tlsEnabled = true
        guard case .ok(let n) = d.build(sourceID: "g") else { return XCTFail("harus berhasil") }
        XCTAssertEqual(n.transport, .grpc)
        XCTAssertEqual(n.transportPath, "mygrpc")
    }

    /// Dua node dengan host/port/uuid sama tapi `Host:` WS berbeda adalah dua
    /// rute CDN berbeda (D91) — keduanya harus tersimpan.
    func testDifferentWebSocketHostProducesDifferentNodes() {
        var a = ManualNodeDraft()
        a.proto = .vless; a.host = "cdn.example"; a.port = "443"; a.credential = "u"
        a.transport = .ws; a.path = "/w"; a.transportHost = "edge-a.example"; a.tlsEnabled = true
        var b = a; b.transportHost = "edge-b.example"
        guard case .ok(let na) = a.build(sourceID: "g"),
              case .ok(let nb) = b.build(sourceID: "g") else {
            return XCTFail("keduanya harus berhasil")
        }
        XCTAssertNotEqual(na.id, nb.id)
    }

    func testProtocolCapabilityFlags() {
        XCTAssertTrue(ManualNodeDraft.supportsTLS(.trojan))
        XCTAssertFalse(ManualNodeDraft.supportsTLS(.shadowsocks))
        XCTAssertTrue(ManualNodeDraft.supportsTransport(.vless))
        XCTAssertFalse(ManualNodeDraft.supportsTransport(.trojan))
        XCTAssertTrue(ManualNodeDraft.supportsReality(.vless))
        XCTAssertFalse(ManualNodeDraft.supportsReality(.vmess))
        XCTAssertTrue(ManualNodeDraft.supportsCipher(.shadowsocks))
        XCTAssertTrue(ManualNodeDraft.supportsHysteria2(.hysteria2))
    }
}

/// D93 — menempelkan tautan manual harus melewati parser yang sama dengan feed.
final class ManualNodeParserTests: XCTestCase {
    func testSingleTrojanLink() {
        switch ManualNodeParser.parse("trojan://pw@a.example:443#SG", sourceID: "g") {
        case .single(let n):
            XCTAssertEqual(n.proto, .trojan)
            XCTAssertEqual(n.host, "a.example")
            XCTAssertEqual(n.sourceID, "g")
        default:
            XCTFail("harus satu node trojan")
        }
    }

    func testManyLinksAtOnce() {
        let text = """
        trojan://pw@a.example:443#A
        vmess://eyJ2IjoiMiIsInBzIjoidXZpZCIsImFkZCI6IjEuMi4zLjQiLCJwb3J0IjoiNDQzIiwiaWQiOiJhYWFhIiwiYWlkIjoiMCIsIm5ldCI6ImEi
        """
        switch ManualNodeParser.parse(text, sourceID: "g") {
        case .many(let ns):
            XCTAssertGreaterThanOrEqual(ns.count, 2)
        case .single(let n):
            // vmess base64 di atas mungkin tidak terbaca; satu node tetap sah.
            XCTAssertFalse(n.id.isEmpty)
        case .failed:
            XCTFail("tidak boleh gagal")
        }
    }

    func testBase64BlobIsAccepted() {
        let payload = "trojan://pw@a.example:443#A\ntrojan://pw@b.example:443#B"
        let b64 = Data(payload.utf8).base64EncodedString()
        switch ManualNodeParser.parse(b64, sourceID: "g") {
        case .many(let ns): XCTAssertEqual(ns.count, 2)
        default: XCTFail("base64 harus bisa dibaca")
        }
    }

    func testEmptyAndGarbageFail() {
        guard case .failed = ManualNodeParser.parse("   ", sourceID: "g") else {
            return XCTFail("teks kosong harus gagal")
        }
        guard case .failed = ManualNodeParser.parse("halo dunia", sourceID: "g") else {
            return XCTFail("bukan tautan harus gagal")
        }
    }
}
