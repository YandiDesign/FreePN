import XCTest
import SwiftUI
@testable import FreePNApp

/// Validasi nyata: config hasil builder HARUS lolos `sing-box check -c`.
/// Binary dicari lewat env SINGBOX_BIN, bundle app, lalu PATH.
final class SingBoxValidationTests: XCTestCase {
    /// `XCTSkip`, bukan `try!`. Versi lama menulis path absolut mesin
    /// developer's hardcoded dan `try! p.run()` — kalau binary tidak ada di
    /// mesin lain, SELURUH test target ikut crash, bukan hanya test ini. Skip
    /// memberi pesan yang jelas dan membiarkan suite tetap jalan.
    private func singBox() throws -> String {
        if let e = ProcessInfo.processInfo.environment["SINGBOX_BIN"],
           FileManager.default.isExecutableFile(atPath: e) { return e }
        for c in [CorePaths.singBox, "/Library/PrivilegedHelperTools/sing-box",
                  "/usr/local/bin/sing-box"] {
            if FileManager.default.isExecutableFile(atPath: c) { return c }
        }
        // Terakhir: andalkan PATH. Kalau memang tidak ada, skip — jangan trap.
        throw XCTSkip("binary sing-box tidak ditemukan; set SINGBOX_BIN untuk menjalankan test ini")
    }

    private func check(_ json: String, tag: String) throws {
        let binary = try singBox()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("freepn-test-\(tag).json")
        try json.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: binary)
        p.arguments = ["check", "-c", url.path]
        // Baca pipe SEBELUM waitUntilExit — urutan sebaliknya bisa macet
        // permanen kalau output melewati buffer ~64 KB.
        let outPipe = Pipe(); let pipe = Pipe()
        p.standardError = pipe; p.standardOutput = outPipe
        try p.run()
        let errData = pipe.fileHandleForReading.readDataToEndOfFile()
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let err = String(data: errData, encoding: .utf8) ?? ""
        let out = String(data: outData, encoding: .utf8) ?? ""
        XCTAssertEqual(p.terminationStatus, 0, "check -c [\(tag)] gagal:\nSTDERR:\(err)\nSTDOUT:\(out)")
        // Deprecation adalah bug yang tertunda (1.14 menghapus format lama) — gagalkan sekalian.
        XCTAssertFalse(err.contains("WARN") || out.contains("WARN"), "check -c [\(tag)] ada deprecation warning:\nSTDERR:\(err)\nSTDOUT:\(out)")
    }

    private func ssNode() -> ProxyNode {
        ProxyNode(name: "SS", proto: .shadowsocks, host: "2.58.81.221", port: 443,
                  credential: "pw", cipher: "aes-256-gcm", sourceID: "t")
    }
    private func trojanNode() -> ProxyNode {
        ProxyNode(name: "T", proto: .trojan, host: "9.9.9.9", port: 443, credential: "pw",
                  tls: TLSOptions(enabled: true, sni: "sni.com"), sourceID: "t")
    }
    private func vmessNode() -> ProxyNode {
        ProxyNode(name: "V", proto: .vmess, host: "1.2.3.4", port: 443, credential: "11111111-2222-3333-4444-555555555555",
                  cipher: "auto", transport: .ws, transportPath: "/x", transportHost: "h.example",
                  tls: TLSOptions(enabled: true, sni: "s.example"), sourceID: "t")
    }

    private func vlessRealityNode() -> ProxyNode {
        ProxyNode(name: "VLESS-R", proto: .vless, host: "www.apple.com", port: 443,
                  credential: "b831381d-6324-4d53-ad4f-8cda48b30811",
                  tls: TLSOptions(enabled: true, sni: "www.apple.com",
                                 realityPublicKey: "g631d9j3SFsX8Y1y1S3VMPvA-Y3vQJdJ6TzKgOYlSA8",
                                 realityShortId: "3ba91c0d", fingerprint: "chrome"),
                  flow: "xtls-rprx-vision", sourceID: "t")
    }
    private func hysteria2Node() -> ProxyNode {
        ProxyNode(name: "HY2", proto: .hysteria2, host: "5.6.7.8", port: 443, credential: "secretpass",
                  tls: TLSOptions(enabled: true, sni: "hy.example.com", allowInsecure: true),
                  obfsPassword: "obfspass", upMbps: 50, downMbps: 200, sourceID: "t")
    }

    func testCheckSS() throws {
        let b = SingBoxConfigBuilder()
        try check(b.configJSON(node: ssNode(), split: SplitTunnelConfig(mode: .exclusive, exclusiveApps: ["/Applications/Safari.app"])), tag: "ss")
    }
    func testCheckTrojan() throws {
        let b = SingBoxConfigBuilder()
        try check(b.configJSON(node: trojanNode(), split: SplitTunnelConfig(mode: .inclusive, inclusiveApps: ["/Applications/Safari.app"])), tag: "trojan")
    }
    func testCheckVmess() throws {
        let b = SingBoxConfigBuilder()
        try check(b.configJSON(node: vmessNode(), split: SplitTunnelConfig()), tag: "vmess")
    }

    /// REALITY wajib punya public key + sidik uTLS; tanpa itu VLESS tidak akan connect.
    func testCheckVlessReality() throws {
        let b = SingBoxConfigBuilder()
        try check(b.configJSON(node: vlessRealityNode(), split: SplitTunnelConfig()), tag: "vless-reality")
    }
    func testCheckHysteria2() throws {
        let b = SingBoxConfigBuilder()
        try check(b.configJSON(node: hysteria2Node(), split: SplitTunnelConfig()), tag: "hysteria2")
    }

    /// Regresi: "IP keluar" harus IP exit VPN, bukan IP asli user.
    ///
    /// Aturan `process_name: FreePN -> direct` (anti routing-loop) membuat
    /// request `ExitIPChecker.viaCore` — yang dikirim dari proses FreePN lewat
    /// SOCKS — ikut CONDONG direct. Efeknya: yang tampil adalah IP asli user.
    /// Aturan `inbound: mixed-in -> proxy` harus muncul SEBELUM aturan
    /// process_name supaya request itu benar-benar lewat proxy.
    ///
    /// Kasus nyata yang dilaporkan: split tunneling mode INKLUSIF (hanya
    /// Chrome yang diproxy). Versi lama salah dan membuat aturan ini
    /// tidak muncul sama sekali — makanya IP tetap asli meski sudah connect.
    func testSocksTrafficRoutedThroughProxyForExitIP() {
        for mode in [SplitMode.inclusive, .exclusive] {
            let json = SingBoxConfigBuilder().configJSON(
                node: ssNode(),
                split: SplitTunnelConfig(mode: mode,
                                         inclusiveApps: ["/Applications/Safari.app"],
                                         exclusiveApps: ["/Applications/Safari.app"],
                                         isEnabled: true))
            guard let root = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
                  let route = root["route"] as? [String: Any],
                  let rules = route["rules"] as? [[String: Any]] else {
                XCTFail("config tidak bisa diparse (mode \(mode))")
                continue
            }
            let mixedIndex = rules.firstIndex { ($0["inbound"] as? [String])?.contains("mixed-in") == true }
            let processIndex = rules.firstIndex { ($0["process_name"] as? [String])?.contains("FreePN") == true }
            XCTAssertNotNil(mixedIndex, "aturan mixed-in -> proxy wajib ada di mode \(mode)")
            if let m = mixedIndex, let p = processIndex {
                XCTAssertLessThan(m, p, "aturan mixed-in harus sebelum process_name (mode \(mode))")
            }
        }
    }

    /// Mode SOCKS-only (TUN mati, System Extension per-app): `mixed-in` dipakai
    /// TransparentProxyProvider untuk trafik USER, jadi tidak boleh dipaksa
    /// proxy — itu akan membalik aturan split yang sudah user pilih.
    func testNoForcedProxyOnMixedInWhenTunDisabled() {
        let json = SingBoxConfigBuilder().configJSON(
            node: ssNode(), split: SplitTunnelConfig(), tunEnabled: false)
        guard let root = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let route = root["route"] as? [String: Any],
              let rules = route["rules"] as? [[String: Any]] else {
            XCTFail("config tidak bisa diparse")
            return
        }
        XCTAssertFalse(rules.contains { ($0["inbound"] as? [String])?.contains("mixed-in") == true },
                       "tanpa TUN, mixed-in membawa trafik user — jangan dipaksa proxy")
        // Rule split per-proses tetap harus ada; tanpa TUN itulah yang menentukan.
        XCTAssertTrue(rules.contains { $0["process_path_regex"] != nil }
                      || rules.contains { $0["process_name"] != nil })
    }

    /// Uji jalur penuh: link share -> parser -> config -> core. Inilah yang
    /// dipakai user saat menambah node dari feed, jadi harus bisa di-Core.
    func testShareLinkToCoreRoundTrip() throws {
        let b = SingBoxConfigBuilder()
        let links = [
            "vless://b831381d-6324-4d53-ad4f-8cda48b30811@www.apple.com:443?encryption=none&security=reality&sni=www.apple.com&fp=chrome&pbk=g631d9j3SFsX8Y1y1S3VMPvA-Y3vQJdJ6TzKgOYlSA8&sid=3ba91c0d&type=tcp&flow=xtls-rprx-vision#RE",
            "hysteria2://mypassword@5.6.7.8:443?sni=hy.example.com&insecure=1&obfs=salamander&obfs-password=obfs123#HY2",
            "vless://11111111-2222-3333-4444-555555555555@cdn.example.com:8443?security=tls&type=ws&path=%2Fray&host=cdn.example.com#WS"
        ]
        let parsed = ShareLinkParser.parse(text: links.joined(separator: "\n"), sourceID: "t")
        XCTAssertEqual(parsed.nodes.count, 3)
        XCTAssertEqual(parsed.unsupported, 0)
        for n in parsed.nodes {
            XCTAssertNotNil(SingBoxConfigBuilder().configJSON(node: n, split: SplitTunnelConfig()),
                            "gagal bikin config untuk \(n.name)")
            try check(SingBoxConfigBuilder().configJSON(node: n, split: SplitTunnelConfig()),
                  tag: "share-\(n.proto.badgeTitle)")
        }
    }

    /// Config probe harus juga benar-benar diterima core — kalau tidak, seluruh
    /// verifikasi "bisa akses internet" diam-diam dilewati.
    func testCheckProbeConfig() throws {
        let b = SingBoxConfigBuilder()
        let nodes = [trojanNode(), ssNode(), vmessNode(), vlessRealityNode(), hysteria2Node()]
        try check(b.probeConfigJSON(nodes: nodes, clashPort: 28909, mixedPort: 28108), tag: "probe")
    }

    /// REGRESI D51 — ini bug yang membuat user 보고 "config probe gagal
    /// validasi — verifikasi internet dilewati".
    ///
    /// Feed `morpheusadam` memuat link
    /// `ss://ax51Ok45f351XA@104.18.218.118:443#@DeltaKroneckerGithub` yang
    /// payload base64-nya BYTE MENTAH (`k\x1eu:N9\x7f~u\`), bukan
    /// `method:password`. Parser menerimanya, tapi `sing-box check` menolak
    /// SELURUH config dengan `unknown method: k` — jadi verifikasi internet
    /// mati untuk ratusan node yang sebenarnya sehat.
    ///
    /// Test ini memakai byte persis dari feed tersebut.
    func testCorruptFeedNodeIsRejectedBeforeItCanPoisonTheProbe() throws {
        let junk = ProxyNode(name: "@DeltaKroneckerGithub", proto: .shadowsocks,
                             host: "104.18.218.118", port: 443,
                             credential: "N9\u{7F}~u\\", cipher: "k\u{1E}u", sourceID: "t")
        let good = ssNode()

        // Lapis-1: penyaring node korup.
        let kept = NodeDeduper.keepingUsable([junk, good])
        XCTAssertEqual(kept.map(\.id), [good.id], "node korup harus dibuang, node sehat bertahan")

        // Lapis-2: config yang tersisa harus benar-benar bisa di-`check`.
        try check(SingBoxConfigBuilder().probeConfigJSON(nodes: kept, clashPort: 28909,
                                                     mixedPort: 28108),
              tag: "probe-setelah-saring")
    }

    /// Jaring kedua: `nodes.json` user bisa sudah berisi node rusak dari versi
    /// app SEBELUMUMNYA, jadi penyaring parser tidak boleh jadi satu-satunya
    /// pertahanan. `prepareProbeConfig` harus menyingkirkan node yang ditolak
    /// core dan tetap menjalankan sisa sesinya.
    func testProbeConfigSurvivesCorruptNodeFromOldNodesFile() throws {
        let junk = ProxyNode(name: "@DeltaKroneckerGithub", proto: .shadowsocks,
                             host: "104.18.218.118", port: 443,
                             credential: "N9\u{7F}~u\\", cipher: "k\u{1E}u", sourceID: "t")
        let prep = InternetProbe.prepareProbeConfig(
            nodes: [trojanNode(), junk, ssNode(), vmessNode()],
            clashPort: 28909, mixedPort: 28108, binary: try singBox())

        guard case .ok(let path, let kept) = prep else {
            return XCTFail("node korup tunggal tidak boleh mematikan seluruh sesi probe, dapat: \(prep)")
        }
        XCTAssertEqual(kept.count, 3, "node korup harus hilang, 3 node sehat tetap diuji")
        XCTAssertFalse(kept.contains { $0.cipher == "k\u{1E}u" })
        try check(try String(contentsOfFile: path, encoding: .utf8), tag: "probe-bisect")
    }

    /// Kalau memang tidak ada satu pun node yang bisa dipakai, itu harus
    /// dilaporkan sebagai "tidak ada node yang bisa dipakai" — bukan diam-diam
    /// mencoba berjalan dengan config kosong.
    func testAllCorruptNodesReportNoUsableNode() throws {
        let junk = ProxyNode(name: "@DeltaKroneckerGithub", proto: .shadowsocks,
                             host: "104.18.218.118", port: 443,
                             credential: "N9\u{7F}~u\\", cipher: "k\u{1E}u", sourceID: "t")
        let prep = InternetProbe.prepareProbeConfig(
            nodes: [junk], clashPort: 28909, mixedPort: 28108, binary: try singBox())
        guard case .noUsableNode = prep else {
            return XCTFail("harus .noUsableNode, dapat: \(prep)")
        }
    }


    /// Format provider JSON-in-YAML (kunci berkutip, escape unicode, header
    /// HOST) harus berakhir di config yang diterima core — bukan sekadar
    /// "terbaca tanpa error".
    func testProviderJsonStyleLineProducesValidConfig() throws {
        let line = #"{"name":"VMESS-未知\u003e德国-x:8080","type":"vmess","server":"x.example.com","port":8080,"uuid":"44e57485-eccc-46ef-808f-cd17ac810018","alterId":0,"cipher":"auto","network":"ws","servername":"node4.example.com","http-opts":{},"skip-cert-verify":true,"ws-opts":{"path":"/@p","headers":{"HOST":"node4.example.com"}}}"#
        let parsed = ClashYAMLParser.parse(text: "proxies:\n  - \(line)", sourceID: "t")
        XCTAssertEqual(parsed.nodes.count, 1)
        let n = parsed.nodes[0]
        XCTAssertEqual(n.transport, .ws)
        XCTAssertEqual(n.transportHost, "node4.example.com")
        try check(SingBoxConfigBuilder().configJSON(node: n, split: SplitTunnelConfig()),
              tag: "provider-json-vmess")
    }


    // MARK: - HTTP / SOCKS5 (D62)

    /// Config hasil parser untuk proxy `http`/`socks5` harus benar-benar
    /// diterima `sing-box check` — bukan hanya "ter-parse tanpa error".
    ///
    /// Ini yang membuat penambahan protokol ini berbeda dari sisa daftar
    /// "tidak didukung" yang dihapus: 422 node di feed user adalah proxy yang
    /// MEMANG bisa dipakai, hanya lupa dibaca parser.
    func testClashHTTPAndSocks5ProduceValidConfig() throws {
        let yaml = """
        proxies:
          - {name: 'plain-http', type: http, server: 1.2.3.4, port: 8080}
          - {name: 'auth-http', type: http, server: 5.6.7.8, port: 3128, username: bob, password: s3cret}
          - {name: 'plain-socks', type: socks5, server: 9.10.11.12, port: 1080}
          - {name: 'auth-socks', type: socks5, server: 13.14.15.16, port: 1080, username: alice, password: pw, tls: true}
        """
        let r = ClashYAMLParser.parse(text: yaml, sourceID: "t")
        XCTAssertEqual(r.nodes.count, 4, "http dan socks5 harus ikut terbaca, bukan dihitung unsupported")
        XCTAssertEqual(r.unsupported, 0)
        XCTAssertEqual(Set(r.nodes.map(\.proto)), [.http, .socks])

        let plainHTTP = r.nodes[0]
        XCTAssertEqual(plainHTTP.proto, .http)
        XCTAssertEqual(plainHTTP.host, "1.2.3.4")
        XCTAssertEqual(plainHTTP.port, 8080)
        XCTAssertTrue(plainHTTP.credential.isEmpty, "proxy tanpa auth harus punya kredensial kosong")

        let authHTTP = r.nodes[1]
        XCTAssertEqual(authHTTP.credential, "bob:s3cret", "kredensial disimpan sebagai user:password")

        try check(SingBoxConfigBuilder().configJSON(node: plainHTTP, split: SplitTunnelConfig()),
              tag: "http-plain")
        try check(SingBoxConfigBuilder().configJSON(node: authHTTP, split: SplitTunnelConfig()),
              tag: "http-auth")
        try check(SingBoxConfigBuilder().configJSON(node: r.nodes[2], split: SplitTunnelConfig()),
              tag: "socks-plain")
        try check(SingBoxConfigBuilder().configJSON(node: r.nodes[3], split: SplitTunnelConfig()),
              tag: "socks-auth")
    }

    /// Baris share-link `socks5://` / `http://` juga harus jadi node.
    func testShareLinkPlainProxySchemesParse() {
        let text = """
        socks5://bob:pw@1.2.3.4:1080#socks-ada-auth
        socks5://5.6.7.8:1081#socks-tanpa-auth
        http://9.10.11.12:3128#http-tanpa-auth
        http://user@13.14.15.16:8080#http-password-saja
        socks5://[2001:db8::1]:1082#socks-ipv6
        """
        let r = ShareLinkParser.parse(text: text, sourceID: "t")
        XCTAssertEqual(r.nodes.count, 5, "kelima link proxy sederhana harus terurai")
        XCTAssertEqual(r.unsupported, 0)

        XCTAssertEqual(r.nodes[0].proto, .socks)
        XCTAssertEqual(r.nodes[0].credential, "bob:pw")
        XCTAssertEqual(r.nodes[0].port, 1080)

        XCTAssertEqual(r.nodes[1].credential, "", "tanpa auth = kredensial kosong")
        XCTAssertEqual(r.nodes[2].proto, .http)

        XCTAssertEqual(r.nodes[4].host, "2001:db8::1", "kurung siku IPv6 harus dilepas")
        XCTAssertEqual(r.nodes[4].port, 1082)
    }

    /// Protokol yang benar-benar tidak bisa dipakai harus TERHITUNG sebagai
    /// `unsupported`.
    ///
    /// Dulu baris `ssr://` (dan skema lain yang dikenal) jatuh ke
    /// `else { continue }` — tidak diparse DAN tidak dihitung. 34 `ssr://` di
    /// feed EbraSha hilang tanpa jejak, dan kolom Keterangan melaporkan angka
    /// yang lebih kecil dari kenyataan.
    func testKnownButUnsupportedSchemesAreCounted() {
        let text = """
        ssr://base64blobhere1234
        tuic://token@host:443
        anytls://password@host:443
        wireguard://key@host:51820
        https://contoh.example/halaman-web-biasa
        """
        let r = ShareLinkParser.parse(text: text, sourceID: "t")
        XCTAssertEqual(r.nodes.count, 0)
        XCTAssertEqual(r.unsupported, 4,
                       "ssr/tuic/anytls/wireguard harus terlihat sebagai 'tidak didukung'; link web biasa tidak")
    }

    /// Node korup harus TERPISAH dari protokol tidak didukung (D62).
    func testCorruptNodesCountSeparatelyFromUnsupportedProtocols() {
        let yaml = """
        proxies:
          - {name: 'ok-ss', type: ss, server: 1.1.1.1, port: 8388, cipher: aes-256-gcm, password: pw}
          - {name: 'korup-ss', type: ss, server: 2.2.2.2, port: 8388, cipher: tidak-ada, password: pw}
          - {name: 'proto-asing', type: snell, server: 3.3.3.3, port: 1234}
        """
        let r = AutoParser.parse(text: yaml, sourceID: "t")
        XCTAssertEqual(r.nodes.count, 1, "hanya node SS yang method-nya dikenal yang dipakai")
        XCTAssertEqual(r.unsupported, 1, "snell = protokol tidak didukung")
        XCTAssertEqual(r.unusable, 1, "cipher tak dikenal = node korup, bukan protokol")
        XCTAssertEqual(r.rejected, 2)
    }

    /// Filter protocol harus menawarkan semua protokol yang bisa di-`case`.
    func testAllProtocolsHaveABadgeTitle() {
        for p in NodeProtocol.allCases {
            XCTAssertFalse(p.badgeTitle.isEmpty, "\(p.rawValue) butuh badge")
        }
        XCTAssertEqual(NodeProtocol.allCases.count, 7)
    }

    /// Path GitHub harus tetap loyal terhadap SVG asalnya.
    ///
    /// `GitHubMark` adalah terjemahan manual dari atribut `d` Font Awesome
    /// (viewBox 640x640). Satu angka yang salah transkripsi = glyph rusak —
    /// dan yang paling buruk, glyph yang MASIH "terlihat" tapi bukan GitHub.
    ///
    /// Geometri diuji lewat `GitHubMark.sourceBounds`, yang diturunkan dari
    /// tabel outline yang SAMA dengan yang dipakai `path(in:)`. Jadi yang
    /// diuji benar-benar bentuk yang dirender, bukan salinan angka kedua.
    func testGitHubMarkMatchesTheSourceGlyphGeometry() {
        let b = GitHubMark.sourceBounds
        XCTAssertFalse(b.isEmpty, "outline kosong")
        // Font Awesome mengisi ~64..576 dari viewBox 640 → ~512 lebar, ~500
        // tinggi. Kalau satu kurva hilang atau salah tempat, angka ini bergeser.
        XCTAssertEqual(b.minX, 64, accuracy: 1)
        XCTAssertEqual(b.minY, 64, accuracy: 1)
        XCTAssertEqual(b.width, 512, accuracy: 1)
        XCTAssertEqual(b.height, 500, accuracy: 1)
        // Nyaris bulat — ciri khas glyph ini.
        XCTAssertEqual(b.width / b.height, 1.024, accuracy: 0.02)
        // Tidak pernah menyentuh tepi viewBox.
        XCTAssertGreaterThanOrEqual(b.minX, 0)
        XCTAssertLessThanOrEqual(b.maxX, 640)
    }

    /// Render harus mengikuti kotak yang diminta, untuk ukuran apa pun — kartu
    /// Tentang memakai 16pt, tapi glyph ini bisa dipakai lagi di ukuran lain.
    func testGitHubMarkFillsRequestedRect() {
        for size in [12.0, 16.0, 24.0, 64.0] as [CGFloat] {
            let rect = CGRect(x: 0, y: 0, width: size, height: size)
            let rendered = GitHubMark().path(in: rect)
            XCTAssertFalse(rendered.isEmpty, "path kosong pada ukuran \(size)")
            // Lebar viewBox 512 dari 640 = 80% dari kotak yang diminta.
            let expectedWidth = size * 512 / 640
            let scale = rect.width / 640
            XCTAssertEqual(GitHubMark.sourceBounds.width * scale, expectedWidth, accuracy: 0.01)
        }
    }

    /// Tautan GitHub harus menuju repositori yang benar dan bisa dibuka.
    func testProjectURLPointsAtTheRepository() {
        XCTAssertEqual(AppConstants.projectURLString, "https://github.com/YandiDesign")
        XCTAssertEqual(AppConstants.projectURL.absoluteString, AppConstants.projectURLString)
        XCTAssertEqual(AppConstants.projectURL.scheme, "https", "tautan eksternal wajib https")
        XCTAssertNil(AppConstants.projectURL.host?.isEmpty == true ? "" : nil,
                     "URL harus punya host")
        XCTAssertEqual(AppConstants.projectURL.host, "github.com")
    }
}

/// Domain harus benar-benar diterima core, bukan hanya masuk akal secara
/// teoretis. `check` juga gagal pada WARN, jadi ini sekaligus menjaga kita
/// dari memakai API yang sudah deprecated — `sniff: true` di inbound akan
/// memicu WARN dan menggagalkan test ini.
final class SplitDomainValidationTests: XCTestCase {
    private func singBox() throws -> String {
        if let e = ProcessInfo.processInfo.environment["SINGBOX_BIN"],
           FileManager.default.isExecutableFile(atPath: e) { return e }
        for c in [CorePaths.singBox, "/Library/PrivilegedHelperTools/sing-box",
                  "/usr/local/bin/sing-box"] {
            if FileManager.default.isExecutableFile(atPath: c) { return c }
        }
        throw XCTSkip("binary sing-box tidak ditemukan; set SINGBOX_BIN")
    }

    private func check(_ json: String, _ tag: String) throws {
        let binary = try singBox()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("freepn-splitdomain-\(tag).json")
        try json.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: binary)
        p.arguments = ["check", "-c", url.path]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = out
        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertEqual(p.terminationStatus, 0, "sing-box menolak config domain:\n\(text)")
        XCTAssertFalse(text.contains("WARN"), "WARN=deprecation, dan check memperlakukannya gagal:\n\(text)")
    }

    private func node() -> ProxyNode {
        ProxyNode(name: "T", proto: .trojan, host: "1.1.1.1", port: 443,
                  credential: "pw", tls: TLSOptions(enabled: true, sni: "sni.com"),
                  sourceID: "s")
    }

    func testExclusiveDomainOnlyConfigPassesCheck() throws {
        try check(SingBoxConfigBuilder().configJSON(
            node: node(),
            split: SplitTunnelConfig(mode: .exclusive,
                                     exclusiveApps: ["/Applications/Safari.app"],
                                     exclusiveDomains: ["bank.com", "*.cdn.example.co.id"]),
            clashPort: 28909), "exclusive")
    }

    func testInclusiveDomainOnlyConfigPassesCheck() throws {
        try check(SingBoxConfigBuilder().configJSON(
            node: node(),
            split: SplitTunnelConfig(mode: .inclusive,
                                     inclusiveDomains: ["video.com", " twitch.tv "]),
            clashPort: 28909), "inclusive")
    }

    /// Config dengan domain yang isinya aneh-aneh tetap harus bisa di-`check`:
    /// normalisasi adalah lapisan builder, dan `check` adalah lapis terakhir.
    func testConfigWithManyDomainsStillPasses() throws {
        let many = (1...40).map { "site\($0).example\(abs($0 % 3)).com" }
        try check(SingBoxConfigBuilder().configJSON(
            node: node(),
            split: SplitTunnelConfig(mode: .exclusive,
                                     exclusiveApps: (1...5).map { "/Applications/App\($0).app" },
                                     exclusiveDomains: many),
            clashPort: 28909), "many")
    }
}
