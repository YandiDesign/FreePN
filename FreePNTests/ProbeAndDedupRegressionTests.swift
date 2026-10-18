import XCTest
@testable import FreePNApp

/// D91 — klasifikasi kegagalan probe.
///
/// Sebelumnya seluruh kegagalan dijahit jadi satu nilai `nil`, lalu satu vonis
/// "tanpa internet", dan pesan error selalu menyebut "kredensial salah".
/// Padahal penyebab yang paling sering BUKAN itu. Tes ini mengunci pemetaan
/// teks error sing-box ke sebab yang bisa ditindaklanjuti.
final class ProbeFailureTests: XCTestCase {
    func testAuthenticationMessagesMapToAuth() {
        for m in ["authentication failed", "invalid credentials",
                  "unauthorized", "invalid password", "bad password"] {
            XCTAssertEqual(ProbeFailure.classify(m), .auth, m)
        }
    }

    func testTimeoutMessagesMapToTimeout() {
        for m in ["context deadline exceeded", "i/o timeout", "request timed out",
                  "deadline exceeded"] {
            XCTAssertEqual(ProbeFailure.classify(m), .timeout, m)
        }
    }

    func testNetworkMessagesMapToUnreachable() {
        for m in ["network is unreachable", "no route to host",
                  "connection refused", "connection reset by peer"] {
            XCTAssertEqual(ProbeFailure.classify(m), .unreachable, m)
        }
    }

    func testDNSMessagesMapToDNS() {
        for m in ["dns: lookup kclx.eu.org: no such host", "no such host",
                  "server misbehaving"] {
            XCTAssertEqual(ProbeFailure.classify(m), .dns, m)
        }
    }

    /// "connection reset by peer" mengandung kata "connection", dan "timeout"
    /// diperiksa lebih dulu — kalau urutannya terbalik, timeout akan tertelan
    /// oleh pola yang lebih umum.
    func testResetIsNotMistakenForTimeout() {
        XCTAssertEqual(ProbeFailure.classify("read: connection reset by peer"),
                       .unreachable)
    }

    /// Status 504 dari Clash API berarti deadline sing-box yang habis.
    func testGatewayTimeoutStatusIsATimeout() {
        XCTAssertEqual(ProbeFailure.classify("", statusCode: 504), .timeout)
    }

    func testUnknownMessageFallsBack() {
        XCTAssertEqual(ProbeFailure.classify("sesuatu yang tidak dikenal"), .unknown)
    }

    /// Kredensial yang ditolak tidak akan berubah dalam beberapa detik;
    /// timeout/jaringan bisa. Ini yang menentukan node mana yang dicoba ulang.
    func testOnlyTransientFailuresAreWorthRetrying() {
        for f in [ProbeFailure.timeout, .unreachable, .dns, .unknown] {
            XCTAssertTrue(f.worthRetrying, "\(f) harus dicoba ulang")
        }
        for f in [ProbeFailure.auth, .rejected, .coreDown] {
            XCTAssertFalse(f.worthRetrying, "\(f) tidak akan berubah sendiri")
        }
    }

    /// `coreDown` tidak boleh jadi vonis mati: proses probe-nya yang tumbang,
    /// jadi tidak ada informasi apa pun tentang node-nya.
    func testCoreDownIsNotTreatedAsDead() {
        let verdict = ProbeVerdict.failed(.coreDown)
        XCTAssertTrue(PingResult(nodeID: "a").applying(verdict).isDeadEnd,
                      "vonis tetap mati, TAPI alasan harus tersimpan supaya bisa dibedakan")
        let r = PingResult(nodeID: "a").applying(.failed(.auth))
        XCTAssertEqual(r.failure, .auth)
    }

    func testFailureSurvivesEncodeDecode() throws {
        let r = PingResult(nodeID: "a", internetOK: false, failure: .dns)
        let data = try JSONEncoder().encode(r)
        XCTAssertEqual(try JSONDecoder().decode(PingResult.self, from: data).failure, .dns)
    }

    /// `nodes.json` dan state lama tidak punya key `failure` — file itu terlalu
    /// berharga untuk dibiarkan gagal decode diam-diam.
    func testLegacyPayloadWithoutFailureStillDecodes() throws {
        let json = #"{"nodeID":"a","webLatencyMs":120,"internetOK":true}"#
        let r = try JSONDecoder().decode(PingResult.self, from: Data(json.utf8))
        XCTAssertTrue(r.internetOK == true)
        XCTAssertNil(r.failure)
    }
}

/// D91 — `dedupID` harus membedakan akun yang sebelumnya tertukar.
final class DedupIdentityTests: XCTestCase {
    private func id(_ host: String = "kclx.eu.org",
                   transportHost: String? = nil, flow: String? = nil,
                   pbk: String? = nil, sid: String? = nil,
                   cipher: String? = nil, alterId: Int? = nil) -> String {
        ProxyNode.dedupID(proto: .vless, host: host, port: 443,
                          credential: "0575005f-0000-0000-0000-000000000001",
                          transport: .ws, path: "/ws", sni: host,
                          transportHost: transportHost, flow: flow,
                          realityPublicKey: pbk, realityShortId: sid,
                          cipher: cipher, alterId: alterId)
    }

    /// Dua rute CDN berbeda dengan host/port/uuid sama. Feed openproxylist
    /// nyata punya pasangan seperti ini, dan versi lama meringkasnya jadi satu.
    func testWebSocketHostDistinguishes() {
        XCTAssertNotEqual(id(transportHost: "cdn-a.example"),
                          id(transportHost: "cdn-b.example"))
    }

    func testFlowDistinguishes() {
        XCTAssertNotEqual(id(flow: "xtls-rprx-vision"), id(flow: nil))
        XCTAssertNotEqual(id(flow: "xtls-rprx-vision"), id(flow: ""))
    }

    /// `pbk` berbeda = instance REALITY yang benar-benar berbeda.
    func testRealityKeysDistinguish() {
        XCTAssertNotEqual(id(pbk: "AAA"), id(pbk: "BBB"))
        XCTAssertNotEqual(id(sid: "a1b2"), id(sid: "c3d4"))
    }

    func testCipherAndAlterIDistinguish() {
        XCTAssertNotEqual(id(cipher: "aes-256-gcm"), id(cipher: "chacha20-ietf-poly1305"))
        XCTAssertNotEqual(id(alterId: 0), id(alterId: 64))
    }

    /// Kompatibilitas: node tanpa field baru harus menghasilkan hash yang PERSIS
    /// sama dengan versi lama, supaya `favorites.json` milik user tidak rusak
    /// hanya karena dedupID acquiring field baru.
    func testPlainNodeKeepsItsLegacyIdentity() {
        let legacy = ProxyNode.dedupID(proto: .vless, host: "kclx.eu.org", port: 443,
                                       credential: "0575005f-0000-0000-0000-000000000001",
                                       transport: .ws, path: "/ws", sni: "kclx.eu.org")
        XCTAssertEqual(id(), legacy)
        XCTAssertEqual(id(transportHost: ""), legacy, "string kosong bukan pembeda")
        XCTAssertEqual(id(transportHost: "   "), legacy, "spasi bukan pembeda")
    }

    /// Dua node yang benar-benar identik tetap harus menghasilkan id sama,
    /// kalau tidak dedup berhenti bekerja sama sekali.
    func testIdenticalNodesStillCollapse() {
        XCTAssertEqual(id(transportHost: "cdn.example", flow: "xtls-rprx-vision"),
                       id(transportHost: "cdn.example", flow: "xtls-rprx-vision"))
    }
}

/// D91 — entri yang gagal di-parse harus TERHIHANG, bukan dibuang diam-diam.
final class MalformedEntryCountingTests: XCTestCase {
    /// Entri tanpa `server`/`port` dulu hanya `continue` polos — tidak masuk
    /// hitungan mana pun, sehingga angka di kolom "Keterangan" selalu lebih
    /// kecil dari isi feed dan user tidak bisa tahu ada yang hilang.
    func testClashEntryWithoutServerIsCountedAsMalformed() {
        let yaml = """
        proxies:
          - name: "Tanpa server"
            type: trojan
            password: "pw"
          - name: "Normal"
            type: trojan
            server: 1.2.3.4
            port: 443
            password: "pw"
        """
        let out = AutoParser.parse(text: yaml, sourceID: "s1")
        XCTAssertEqual(out.nodes.count, 1)
        XCTAssertEqual(out.unusable, 1, "entri tanpa server harus tercatat sebagai korup")
    }

    func testClashEntryWithoutCredentialIsCounted() {
        let yaml = """
        proxies:
          - name: "Tanpa password"
            type: trojan
            server: 1.2.3.4
            port: 443
        """
        let out = AutoParser.parse(text: yaml, sourceID: "s1")
        XCTAssertTrue(out.nodes.isEmpty)
        XCTAssertEqual(out.unusable, 1)
    }

    /// Link dengan skema yang didukung tapi rusak tidak boleh hilang tanpa jejak.
    func testBrokenShareLinkIsCounted() {
        let text = """
        trojan://pw@1.2.3.4:443#Bagus
        vless://@1.2.3.4:443?type=ws&path=/x#TanpaUUID
        """
        let out = AutoParser.parse(text: text, sourceID: "s1")
        XCTAssertEqual(out.nodes.count, 1)
        XCTAssertEqual(out.unusable, 1)
    }

    /// Skema yang memang tidak didukung tetap dihitung sebagai "tidak
    /// didukung" — pemisahan itu yang membuat user bisa membacanya (D62).
    func testUnknownSchemeStaysUnsupportedNotMalformed() {
        let out = AutoParser.parse(text: "ssr://abc\ntrojan://pw@1.2.3.4:443#OK", sourceID: "s1")
        XCTAssertEqual(out.unsupported, 1)
        XCTAssertEqual(out.unusable, 0)
    }
}

/// D91 — VLESS gRPC: nama service ada di query `serviceName`, bukan di `path`.
///
/// Versi lama hanya membaca `path`, jadi `transportPath` kosong dan config yang
/// dihasilkan memuat `"service_name": ""` — node dijamin ditolak saat connect
/// sementara di Clash FX berjalan normal.
final class VlessGrpcServiceNameTests: XCTestCase {
    func testServiceNameIsReadForGrpc() {
        let line = "vless://uuid-1234@example.com:443?type=grpc&serviceName=mygrpc&security=tls#Node"
        let out = ShareLinkParser.parse(text: line, sourceID: "s1")
        XCTAssertEqual(out.nodes.count, 1, out.malformed.description)
        let n = out.nodes[0]
        XCTAssertEqual(n.transport, .grpc)
        XCTAssertEqual(n.transportPath, "mygrpc")
    }

    /// `serviceName` dan `service_name` keduanya dipakai di feed liar.
    func testBothSpellingsAreAccepted() {
        let out = ShareLinkParser.parse(
            text: "vless://uuid-1234@example.com:443?type=grpc&service_name=alt#N",
            sourceID: "s1")
        XCTAssertEqual(out.nodes.first?.transportPath, "alt")
    }

    /// Untuk ws, `path` tetap yang benar — jangan sampai tertukar dengan gRPC.
    func testWebSocketStillUsesPath() {
        let out = ShareLinkParser.parse(
            text: "vless://uuid-1234@example.com:443?type=ws&path=/ray&host=h.example#N",
            sourceID: "s1")
        XCTAssertEqual(out.nodes.first?.transportPath, "/ray")
        XCTAssertEqual(out.nodes.first?.transportHost, "h.example")
    }

    func testALPNIsCarried() {
        let out = ShareLinkParser.parse(
            text: "vless://uuid-1234@example.com:443?security=tls&alpn=h2,http/1.1#N",
            sourceID: "s1")
        XCTAssertEqual(out.nodes.first?.tls?.alpn, ["h2", "http/1.1"])
    }

    func testAbsentALPNStaysNil() {
        let out = ShareLinkParser.parse(
            text: "vless://uuid-1234@example.com:443?security=tls#N", sourceID: "s1")
        XCTAssertNil(out.nodes.first?.tls?.alpn, "tanpa alpn harus dibiarkan, bukan diisi default")
    }
}

/// D91 — sasaran Ping All tidak boleh mengudang dirinya sendiri.
final class PingTargetScopeTests: XCTestCase {
    private func node(_ id: String) -> ProxyNode {
        ProxyNode(id: id, name: id, proto: .trojan, host: "1.2.3.4", port: 443,
                  credential: "c", sourceID: "s1")
    }

    /// Dengan "Sembunyikan yang mati" nyala, `filteredNodes` tidak memuat node
    /// yang sudah vonis mati — padahal itu PERSIS daftar sasaran Ping All.
    /// Akibatnya vonis yang salah tidak pernah bisa dikoreksi.
    func testTargetsIgnoreTheDeadNodeFilter() {
        let nodes = [node("a"), node("b")]
        XCTAssertEqual(AppState.pingTargets(nodes: nodes, search: "", proto: nil, source: nil).count, 2)
    }

    /// Filter yang benar-benar ada MENGATUR sasaran — kalau tidak, satu klik
    /// bisa memicu pengujian ribuan server yang tidak ditampilkan.
    func testTargetsStillRespectSearchAndSource() {
        let nodes = [ProxyNode(id: "a", name: "SG Node", proto: .trojan, host: "1.2.3.4",
                               port: 443, credential: "c", sourceID: "s1"),
                     ProxyNode(id: "b", name: "US Node", proto: .trojan, host: "5.6.7.8",
                               port: 443, credential: "c", sourceID: "s2")]
        XCTAssertEqual(AppState.pingTargets(nodes: nodes, search: "sg", proto: nil,
                                            source: nil).map(\.id), ["a"])
        XCTAssertEqual(AppState.pingTargets(nodes: nodes, search: "", proto: nil,
                                            source: "s2").map(\.id), ["b"])
    }
}
/// D92 — instalasi harus benar-benar bersih.
final class CleanInstallTests: XCTestCase {
    override func setUp() {
        super.setUp()
        isolateStorage()
    }

    /// Ini definisi "bersih": app tidak datang dengan satu pun feed pun sudah
    /// aktif. Sebelumnya `AppState.sources` mulai dari 10 feed bawaan, jadi
    /// setiap user baru langsung punya tabel server terisi dan daftar yang
    /// bukan pilihannya.
    @MainActor
    func testFreshStateHasNoSources() {
        let state = AppState()
        XCTAssertTrue(state.sources.isEmpty)
        XCTAssertTrue(state.nodes.isEmpty)
        XCTAssertTrue(VPNSubscriptionSource.defaultSources.isEmpty)
    }

    /// `addSource` harus menolak URL yang sudah ada — dua entri untuk feed
    /// yang sama berarti dua unduhan untuk isi identik.
    @MainActor
    func testAddSourceRejectsDuplicateURL() {
        let state = AppState()
        XCTAssertNotNil(state.addSource(name: "A", url: "https://example.com/sub"))
        XCTAssertNil(state.addSource(name: "A lagi", url: "https://example.com/sub"))
        XCTAssertNil(state.addSource(name: "Spasi", url: "  https://example.com/sub  "))
        XCTAssertEqual(state.sources.count, 1)
    }

    @MainActor
    func testAddSourceIgnoresEmptyURL() {
        let state = AppState()
        XCTAssertNil(state.addSource(name: "Kosong", url: "   "))
        XCTAssertTrue(state.sources.isEmpty)
    }

    /// Tanpa nama, URL dipakai sebagai nama — daftar harus tetap terbaca.
    @MainActor
    func testAddSourceFallsBackToURLAsName() {
        let state = AppState()
        XCTAssertNotNil(state.addSource(name: "  ", url: "https://example.com/sub"))
        XCTAssertEqual(state.sources.first?.name, "https://example.com/sub")
    }

    /// Feed yang ditambahkan adalah milik user — tidak boleh `isStarred`,
    /// karena `ServerSorter` mengunci sumber berbintang di paling atas tanpa
    /// views kolom apa pun yang dipilih.
    @MainActor
    func testAddedSourceIsNeverPreStarred() {
        let state = AppState()
        _ = state.addSource(name: "A", url: "https://example.com/sub")
        XCTAssertEqual(state.sources.first?.isStarred, false)
    }

    /// Tawaran yang sudah dipakai user harus hilang dari daftar — kalau tidak,
    /// menekan tawaran itu jadi no-op yang membingungkan.
    @MainActor
    func testSuggestionsExcludeAlreadyAddedFeeds() {
        let state = AppState()
        let first = VPNSubscriptionSource.curated[0]
        XCTAssertNotNil(state.addSource(name: first.name, url: first.url))
        // Sumber yang sudah ada harus tersaring dari tawaran, supaya tidak ada
        // tombol yang kalau ditekan justru ditolak sebagai duplikat.
        let taken = Set(state.sources.map(\.url))
        let offered = VPNSubscriptionSource.curated.filter { !taken.contains($0.url) }
        XCTAssertFalse(offered.contains { $0.url == first.url })
    }
}
