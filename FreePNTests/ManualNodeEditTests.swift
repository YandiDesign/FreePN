import XCTest
@testable import FreePNApp

/// Edit node manual: draft -> node -> draft harus bolak-balik.
///
/// Ini yang menjaga form edit dari kehilangan field. Form kosong yang hanya
/// kelihatan "berisi" akan menghasilkan node tanpa SNI/credential — dan node
/// seperti itu gagal dengan pesan yang sama sekali tidak menunjuk ke form.
final class ManualNodeEditTests: XCTestCase {

    private func roundTrip(_ node: ProxyNode, file: StaticString = #filePath, line: UInt = 0) {
        let draft = ManualNodeDraft(node: node)
        guard case .ok(let rebuilt) = draft.build(sourceID: node.sourceID) else {
            XCTFail("draft hasil edit tidak bisa dibangun lagi", file: file, line: line)
            return
        }
        // `id` sengaja tidak dibandingkan: itu urusan AppState, dan membandingkan
        // di sini hanya mencampur dua hal yang berbeda.
        XCTAssertEqual(rebuilt.name, node.name, file: file, line: line)
        XCTAssertEqual(rebuilt.proto, node.proto, file: file, line: line)
        XCTAssertEqual(rebuilt.host, node.host, file: file, line: line)
        XCTAssertEqual(rebuilt.port, node.port, file: file, line: line)
        XCTAssertEqual(rebuilt.credential, node.credential, file: file, line: line)
        XCTAssertEqual(rebuilt.tls?.enabled, node.tls?.enabled, file: file, line: line)
        XCTAssertEqual(rebuilt.tls?.sni, node.tls?.sni, file: file, line: line)
        XCTAssertEqual(rebuilt.tls?.allowInsecure, node.tls?.allowInsecure, file: file, line: line)
        XCTAssertEqual(rebuilt.transport, node.transport, file: file, line: line)
        XCTAssertEqual(rebuilt.transportPath, node.transportPath, file: file, line: line)
        XCTAssertEqual(rebuilt.transportHost, node.transportHost, file: file, line: line)
    }

    /// Kasus nyata dari laporan user: trojan + WS + SNI CDN-fronting.
    func testTrojanWSWithCDNFrontingSurvivesRoundTrip() {
        roundTrip(ProxyNode(
            name: "trial-2112734873", proto: .trojan, host: "biznet.byxl.biz.id", port: 443,
            credential: "cf113faf-edbf-46eb-964d-39a392579c37",
            transport: .ws, transportPath: "/trojan", transportHost: "biznet.byxl.biz.id",
            tls: TLSOptions(enabled: true, sni: "opencode.ai", allowInsecure: false),
            sourceID: "g1"))
    }

    func testEveryProtocolSurvivesRoundTrip() {
        let tls = TLSOptions(enabled: true, sni: "a.example.com", allowInsecure: true, alpn: ["h2", "http/1.1"])
        let nodes: [ProxyNode] = [
            ProxyNode(name: "vmess", proto: .vmess, host: "a.com", port: 443,
                      credential: "11111111-2222-3333-4444-555555555555",
                      transport: .ws, transportPath: "/p", transportHost: "h.com",
                      tls: tls, sourceID: "g1"),
            ProxyNode(name: "vless", proto: .vless, host: "b.com", port: 8443,
                      credential: "11111111-2222-3333-4444-555555555555",
                      transport: .grpc, transportPath: "svc", tls: tls, sourceID: "g1"),
            ProxyNode(name: "ss", proto: .shadowsocks, host: "c.com", port: 8388,
                      credential: "aes-256-gcm:pw", cipher: "aes-256-gcm", sourceID: "g1"),
            ProxyNode(name: "ss-nouser", proto: .shadowsocks, host: "c2.com", port: 8388,
                      credential: "aes-128-gcm:secret", sourceID: "g1"),
            ProxyNode(name: "hy2", proto: .hysteria2, host: "d.com", port: 443,
                      credential: "pw", tls: tls, obfsPassword: "obfs",
                      upMbps: 30, downMbps: 120, sourceID: "g1")
        ]
        for n in nodes { roundTrip(n) }
    }

    /// ALPN masuk draft sebagai satu string ber-koma dan kembali jadi array.
    func testAlpnRoundTripsThroughCommaSeparatedString() {
        let n = ProxyNode(name: "a", proto: .trojan, host: "a.com", port: 443, credential: "pw",
                          tls: TLSOptions(enabled: true, sni: "a.com", alpn: ["h2", "http/1.1"]),
                          sourceID: "g1")
        roundTrip(n)
    }

    /// Mbps `nil` berarti "pakai default core". Kalau draft menyimpannya jadi
    /// "0", user yang tidak sengaja menyentuh field itu akan mengunci
    /// bandwidth node ke nol — node yang tadinya jalan menjadi tidak jalan,
    /// dan penyebabnya tidak terlihat di mana pun.
    func testDefaultBandwidthStaysEmptyNotZero() {
        let n = ProxyNode(name: "hy2", proto: .hysteria2, host: "d.com", port: 443,
                          credential: "pw", tls: TLSOptions(enabled: true, sni: "d.com"),
                          sourceID: "g1")
        let d = ManualNodeDraft(node: n)
        XCTAssertEqual(d.upMbps, "")
        XCTAssertEqual(d.downMbps, "")
        XCTAssertNil(n.upMbps)
        XCTAssertNil(n.downMbps)
    }

    func testExplicitBandwidthSurvivesRoundTrip() {
        roundTrip(ProxyNode(name: "hy2", proto: .hysteria2, host: "d.com", port: 443,
                            credential: "pw", tls: TLSOptions(enabled: true, sni: "d.com"),
                            upMbps: 30, downMbps: 120, sourceID: "g1"))
    }

    /// Menyunting draft harus mengubahnya, kalau tidak tombol Simpan tidak
    /// melakukan apa-apa — persis gejala "tidak bisa edit".
    func testEditedDraftProducesDifferentNode() {
        var d = ManualNodeDraft(node: ProxyNode(
            name: "lama", proto: .trojan, host: "a.com", port: 443, credential: "pw",
            tls: TLSOptions(enabled: true, sni: "salah.com"), sourceID: "g1"))
        d.name = "baru"
        d.credential = "password-baru"
        d.sni = "benar.com"
        guard case .ok(let n) = d.build(sourceID: "g1") else {
            return XCTFail("draft yang disunting harus tetap bisa dibangun")
        }
        XCTAssertEqual(n.name, "baru")
        XCTAssertEqual(n.credential, "password-baru")
        XCTAssertEqual(n.tls?.sni, "benar.com")
    }

    /// Menonaktifkan TLS harus benar-benar mematikan. Builder memakai
    /// `tlsOn ? tls : nil`, jadi hasil yang benar adalah `nil` — bukan
    /// `TLSOptions(enabled: false)` yang akan tetap menyertakan SNI tak
    /// terpakai di config.
    func testDisablingTLSRemovesTLSEntirely() {
        var d = ManualNodeDraft(node: ProxyNode(
            name: "x", proto: .trojan, host: "a.com", port: 443, credential: "pw",
            tls: TLSOptions(enabled: true, sni: "sni.com"), sourceID: "g1"))
        d.tlsEnabled = false
        guard case .ok(let n) = d.build(sourceID: "g1") else { return XCTFail("build gagal") }
        XCTAssertNil(n.tls, "TLS mati harus hilang, bukan jadi blok enabled:false")
    }

    /// `ProxyNode.id` dihitung dari isi node, jadi menyunting kredensial
    /// otomatis mengubahnya. `updateManualNode` obligated memaksa id asli
    /// kembali; kalau tidak, satu perbaikan SNI akan membuang ping, favorit,
    /// dan node terpilih milik user.
    func testChangingCredentialChangesTheDerivedID() {
        let n = ProxyNode(name: "a", proto: .trojan, host: "a.com", port: 443,
                          credential: "pw", tls: TLSOptions(enabled: true, sni: "a.com"),
                          sourceID: "g1")
        var d = ManualNodeDraft(node: n)
        d.credential = "berbeda"
        guard case .ok(let rebuilt) = d.build(sourceID: "g1") else { return XCTFail("build gagal") }
        XCTAssertNotEqual(rebuilt.id, n.id,
                          "dedupID harus ikut berubah — inilah alasan id dipaksa di updateManualNode")
    }

    // MARK: - AppState

    /// ID harus tetap sama: `ping`, `favorites`, dan `selectedNodeID` memakai
    /// id sebagai kunci. Node baru akan meninggalkan semuanya nyangkut.
    @MainActor
    func testUpdateKeepsNodeIDSoPingAndFavoritesSurvive() async {
        isolateStorage()
        let state = AppState()
        let gid = state.addManualGroup(name: "G")
        var d = ManualNodeDraft()
        d.proto = .trojan; d.host = "a.com"; d.port = "443"; d.credential = "pw"
        d.tlsEnabled = true; d.sni = "a.com"; d.transport = .tcp
        guard case .added = await state.addManualNode(draft: d, toGroup: gid) else {
            return XCTFail("node awal gagal ditambahkan")
        }
        guard let before = state.nodes.first(where: { $0.sourceID == gid }) else {
            return XCTFail("node tidak masuk daftar global")
        }
        state.favorites.insert(before.id)

        var d2 = ManualNodeDraft(node: before)
        d2.credential = "pw-baru"
        guard case .added = await state.updateManualNode(id: before.id, draft: d2) else {
            return XCTFail("update gagal")
        }
        let after = state.nodes.first { $0.id == before.id }
        XCTAssertNotNil(after, "node harus ada di tempat yang sama, bukan Exemplar baru")
        XCTAssertEqual(after?.credential, "pw-baru")
        XCTAssertTrue(state.favorites.contains(before.id), "favorit ikut nyangkut ke id yang sama")
        XCTAssertEqual(state.nodes.filter { $0.sourceID == gid }.count, 1,
                       "edit tidak boleh menambah node kedua")
    }

    /// Ping lama diukur untuk konfigurasi lama. Kredensial atau SNI yang
    /// berubah berarti angkanya tidak lagi menggambarkan node itu.
    @MainActor
    func testUpdateDropsStalePing() async {
        isolateStorage()
        let state = AppState()
        let gid = state.addManualGroup(name: "G")
        var d = ManualNodeDraft()
        d.proto = .trojan; d.host = "b.com"; d.port = "443"; d.credential = "pw"
        d.tlsEnabled = true; d.sni = "b.com"; d.transport = .tcp
        guard case .added = await state.addManualNode(draft: d, toGroup: gid) else {
            return XCTFail("tambah gagal")
        }
        let node = state.nodes.first { $0.sourceID == gid }!
        state.ping[node.id] = PingResult(nodeID: node.id, webLatencyMs: 93, internetOK: true)

        var d2 = ManualNodeDraft(node: node)
        d2.credential = "pw2"
        guard case .added = await state.updateManualNode(id: node.id, draft: d2) else {
            return XCTFail("update gagal")
        }
        XCTAssertNil(state.ping[node.id], "ping hasil ukur konfigurasi lama harus dibuang")
    }

    @MainActor
    func testUpdateRejectsInvalidDraftAndKeepsNodeIntact() async {
        isolateStorage()
        let state = AppState()
        let gid = state.addManualGroup(name: "G")
        var d = ManualNodeDraft()
        d.proto = .trojan; d.host = "c.com"; d.port = "443"; d.credential = "pw"
        d.tlsEnabled = true; d.sni = "c.com"; d.transport = .tcp
        guard case .added = await state.addManualNode(draft: d, toGroup: gid) else {
            return XCTFail("tambah gagal")
        }
        let node = state.nodes.first { $0.sourceID == gid }!
        var bad = ManualNodeDraft(node: node)
        bad.credential = ""            // kredensial kosong untuk trojan
        guard case .failed = await state.updateManualNode(id: node.id, draft: bad) else {
            return XCTFail("draft tak valid harus ditolak")
        }
        XCTAssertEqual(state.nodes.first { $0.id == node.id }?.credential, "pw",
                       "node lama harus utuh setelah edit gagal")
    }
}

/// Daftar akun di sheet grup manual: klik = ubah, klik kanan = hapus.
///
/// Chip yang memuat 2 tombol ikon (pensil + X) per akun adalah 10 target
/// kecil yang berisik untuk 5 akun — nama + badge proto sudah cukup.
/// Test ini mengunci strukturnya via source scan (gaya `MapNodeSourceTests`),
/// karena yang dijaga adalah invarian UI, bukan perilaku runtime.
final class ManualAccountListTests: XCTestCase {
    private func source() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("FreePN/UI/ManualGroupView.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testChipsHaveNoInlineEditOrDeleteButtons() throws {
        let src = try source()
        XCTAssertFalse(src.contains("\"pencil\""),
                       "tombol pensil inline dihapus — edit cukup klik chip")
        XCTAssertFalse(src.contains("xmark.circle.fill"),
                       "tombol X inline dihapus — hapus lewat klik kanan")
    }

    func testChipClickEditsAndContextMenuDeletes() throws {
        let src = try source()
        XCTAssertTrue(src.contains("Button { startEditing(n) }"),
                      "klik chip harus membuka form edit")
        XCTAssertTrue(src.contains(".contextMenu"),
                      "hapus harus lewat context menu (klik kanan)")
        XCTAssertTrue(src.contains("state.removeManualNode(id: n.id)"),
                      "context menu harus memanggil hapus akun")
        XCTAssertTrue(src.contains("manual_accounts_hint"),
                      "petunjuk klik/klik-kanan harus tampil di atas daftar")
    }

    /// 50 akun tidak boleh scroll menyamping: chip mengalir ke bawah via
    /// `FlowLayout` dalam scroll vertikal berbatas, tanpa potongan
    /// `prefix(24)`.
    func testAccountListWrapsVerticallyWithoutLimit() throws {
        let src = try source()
        XCTAssertTrue(src.contains("FlowLayout"),
                      "daftar akun harus memakai flow layout vertikal")
        XCTAssertFalse(src.contains("ScrollView(.horizontal"),
                       "tidak boleh ada scroll horizontal untuk daftar akun")
        XCTAssertFalse(src.contains("prefix(24)"),
                       "tidak boleh ada batas 24 akun + '+N lagi'")
    }

    /// Backup/Pulihkan wajib ada di sheet grup manual: cadangan hidup di
    /// file milik user (di luar nodes.json) supaya refresh gagal tidak bisa
    /// menghapusnya lagi. Backup memakai `ShareLinkEncoder` (format tab
    /// tautan), restore memakai `ManualNodeParser` yang sama.
    func testBackupRestoreButtonsAndWiringExist() throws {
        let src = try source()
        XCTAssertTrue(src.contains("manual_backup"),
                      "tombol Backup harus ada di sheet grup manual")
        XCTAssertTrue(src.contains("manual_restore"),
                      "tombol Pulihkan harus ada di sheet grup manual")
        XCTAssertTrue(src.contains("ShareLinkEncoder.document(for:"),
                      "backup harus lewat encoder (format tab tautan)")
        XCTAssertTrue(src.contains("ManualNodeParser.parse("),
                      "restore harus lewat parser yang sama")
        XCTAssertTrue(src.contains("NSSavePanel"),
                      "backup harus meminta lokasi file ke user")
        XCTAssertTrue(src.contains("NSOpenPanel"),
                      "restore harus meminta file ke user")
    }
}

/// Refresh sumber online TIDAK BOLEH menghapus akun manual.
///
/// Kasus nyata: user punya 13 akun di grup manual "Spesial", menambah sumber
/// online yang fetch-nya gagal → `nodes` diganti hasil fetch kosong →
/// akun manual hilang dari Server DAN dari disk (nodes.json + .bak kosong).
/// `refreshMerge` mengunci gabungannya sebagai unit murni.
final class RefreshKeepsManualNodesTests: XCTestCase {
    private func manual(id: String = "m1", source: String = "g-manual") -> ProxyNode {
        ProxyNode(id: id, name: "Manual", proto: .trojan, host: "h.example",
                  port: 443, credential: "pw", sourceID: source)
    }

    private func feed(id: String = "f1") -> ProxyNode {
        ProxyNode(id: id, name: "Feed", proto: .vless, host: "x.example",
                  port: 443, credential: "uuid", sourceID: "g-feed")
    }

    /// Kasus user persis: feed gagal total (kosong), manual harus utuh.
    func testEmptyFetchKeepsManual() {
        let m = manual()
        let out = AppState.refreshMerge(fetched: [], manualSnapshot: [m],
                                        liveManualIDs: ["g-manual"])
        XCTAssertEqual(out.map(\.id), [m.id])
    }

    func testFetchAndManualCombine() {
        let out = AppState.refreshMerge(fetched: [feed()], manualSnapshot: [manual()],
                                        liveManualIDs: ["g-manual"])
        XCTAssertEqual(out.count, 2)
    }

    /// Grup manual yang dihapus di tengah refresh tidak boleh bangkit lagi.
    func testRemovedManualGroupDoesNotResurrect() {
        let out = AppState.refreshMerge(fetched: [feed()], manualSnapshot: [manual()],
                                        liveManualIDs: [])
        XCTAssertEqual(out.map(\.id), ["f1"])
    }

    /// Node dari grup lain (bukan manual hidup) tidak ikut terbawa.
    func testOnlyLiveManualIDsSurvive() {
        let out = AppState.refreshMerge(
            fetched: [],
            manualSnapshot: [manual(id: "m1", source: "g-gone"), manual(id: "m2")],
            liveManualIDs: ["g-manual"])
        XCTAssertEqual(out.map(\.id), ["m2"])
    }
}
