import XCTest
@testable import FreePNApp

final class ParserTests: XCTestCase {
    func testVmess() {
        // vmess JSON minimal -> base64
        let obj: [String: Any] = ["ps": "SG-Test", "add": "1.2.3.4", "port": "443",
                                  "id": "11111111-2222-3333-4444-555555555555",
                                  "aid": 0, "scy": "auto", "net": "ws",
                                  "path": "/x", "host": "h.example", "tls": "tls", "sni": "s.example"]
        let data = try! JSONSerialization.data(withJSONObject: obj)
        let link = "vmess://" + data.base64EncodedString()
        let r = ShareLinkParser.parse(text: link, sourceID: "t")
        XCTAssertEqual(r.nodes.count, 1)
        XCTAssertEqual(r.nodes[0].proto, .vmess)
        XCTAssertEqual(r.nodes[0].transport, .ws)
    }

    func testTrojan() {
        let r = ShareLinkParser.parse(text: "trojan://pass@9.9.9.9:443?sni=a.com&type=ws&path=%2Fq#MyNode", sourceID: "t")
        XCTAssertEqual(r.nodes.count, 1)
        XCTAssertEqual(r.nodes[0].proto, .trojan)
        XCTAssertEqual(r.nodes[0].name, "MyNode")
    }

    func testSSSIP002() {
        let cred = Data("aes-256-gcm:secret".utf8).base64EncodedString()
        let r = ShareLinkParser.parse(text: "ss://\(cred)@5.6.7.8:8388#SSNode", sourceID: "t")
        XCTAssertEqual(r.nodes.count, 1)
        XCTAssertEqual(r.nodes[0].proto, .shadowsocks)
    }

    func testSSLegacy() {
        let full = Data("aes-128-gcm:pw@1.1.1.1:8388".utf8).base64EncodedString()
        let r = ShareLinkParser.parse(text: "ss://\(full)", sourceID: "t")
        XCTAssertEqual(r.nodes.count, 1)
        XCTAssertEqual(r.nodes[0].host, "1.1.1.1")
    }

    /// REGRESI D51 — link ini diambil PERSIS dari feed `morpheusadam` yang
    /// dipakai user. Payload base64-nya byte mentah (`k\x1eu:N9\x7f~u\`),
    /// bukan `method:password`, tapi kebetulan punya tanda `:` dan UTF-8
    /// valid sehingga parser lama menerimanya.
    ///
    /// node seperti ini membuat `sing-box check` menolak SELURUH config probe
    /// (`unknown method: k`), jadi verifikasi internet mati untuk ratusan node
    /// sehat. `AutoParser` harus membuangnya.
    func testCorruptSSLinkIsDroppedByAutoParser() {
        let good = "ss://" + Data("aes-256-gcm:secret".utf8).base64EncodedString() + "@5.6.7.8:8388#Good"
        let junk = "ss://ax51Ok45f351XA@104.18.218.118:443#@DeltaKroneckerGithub"
        let r = AutoParser.parse(text: "\(good)\n\(junk)", sourceID: "t")

        XCTAssertEqual(r.nodes.count, 1, "hanya node yang sehat boleh masuk daftar")
        XCTAssertEqual(r.nodes[0].host, "5.6.7.8")
        // D62: node korup DILEPAS ke `unusable`, bukan `unsupported` —
        // keduanya tampil di kolom Keterangan tapi artinya berbeda.
        XCTAssertEqual(r.unsupported, 0, "tidak ada protokol yang tak didukung di sini")
        XCTAssertEqual(r.unusable, 1, "node korup harus tercatat sebagai korup, bukan 'tidak didukung'")
        for n in r.nodes {
            XCTAssertTrue(NodeDeduper.isUsable(n), "\(n.name) lolos ke daftar padahal korup")
        }
    }

    /// Method Shadowsocks di luar daftar sing-box pasti ditolak core, jadi
    /// membuangnya di pintu masuk lebih murah daripada membiarkannya menggagalkan
    /// seluruh sesi probe.
    func testUnknownShadowsocksMethodIsDropped() {
        let link = "ss://" + Data("chacha20-poly1305:pw".utf8).base64EncodedString() + "@5.6.7.8:8388#Old"
        XCTAssertTrue(AutoParser.parse(text: link, sourceID: "t").nodes.isEmpty)
        let modern = "ss://" + Data("chacha20-ietf-poly1305:pw".utf8).base64EncodedString() + "@5.6.7.8:8388#OK"
        XCTAssertEqual(AutoParser.parse(text: modern, sourceID: "t").nodes.count, 1)
    }

    func testClashFallback() {
        let yaml = """
        proxies:
          - {name: A, type: vmess, server: 1.1.1.1, port: 443, uuid: u1}
          - {name: B, type: trojan, server: 2.2.2.2, port: 443, password: p}
          - {name: C, type: ss, server: 3.3.3.3, port: 8388, cipher: aes-256-gcm, password: p}
          - {name: D, type: vless, server: 4.4.4.4, port: 443, uuid: u}
          - {name: E, type: tuic, server: 5.5.5.5, port: 443, uuid: u}
        """
        let r = ClashYAMLParser.parse(text: yaml, sourceID: "t")
        // 4 didukung (vmess/trojan/ss/vless) + 1 tidak didukung (tuic).
        XCTAssertEqual(r.nodes.count, 4)
        XCTAssertEqual(r.unsupported, 1)
    }

    // MARK: - VLESS + Hysteria2

    func testVlessRealityLink() {
        let link = "vless://b831381d-6324-4d53-ad4f-8cda48b30811@www.apple.com:443" +
        "?encryption=none&security=reality&sni=www.apple.com&fp=chrome&pbk=PBK123&sid=3ba91c0d&type=tcp&flow=xtls-rprx-vision#SG%20Singapore"
        let r = ShareLinkParser.parse(text: link, sourceID: "s")
        XCTAssertEqual(r.nodes.count, 1)
        let n = r.nodes[0]
        XCTAssertEqual(n.proto, .vless)
        XCTAssertEqual(n.credential, "b831381d-6324-4d53-ad4f-8cda48b30811")
        XCTAssertEqual(n.flow, "xtls-rprx-vision")
        XCTAssertEqual(n.name, "SG Singapore")
        XCTAssertEqual(n.tls?.realityPublicKey, "PBK123")
        XCTAssertEqual(n.tls?.realityShortId, "3ba91c0d")
        XCTAssertEqual(n.tls?.fingerprint, "chrome")
        XCTAssertTrue(n.tls?.isReality == true)
        XCTAssertEqual(r.unsupported, 0)
    }

    /// REALITY tanpa public key tidak akan pernah connect — buang, jangan simpan.
    func testVlessRealityWithoutPublicKeyIsDropped() {
        let link = "vless://uuid-x@1.2.3.4:443?security=reality&sni=s.com&type=tcp#noKey"
        let r = ShareLinkParser.parse(text: link, sourceID: "s")
        XCTAssertTrue(r.nodes.isEmpty)
    }

    func testVlessPlainTLSWithWS() {
        let link = "vless://11111111-2222-3333-4444-555555555555@cdn.example.com:8443" +
        "?security=tls&type=ws&path=%2Fray&host=cdn.example.com#WS"
        let n = ShareLinkParser.parse(text: link, sourceID: "s").nodes.first
        XCTAssertEqual(n?.proto, .vless)
        XCTAssertEqual(n?.transport, .ws)
        XCTAssertEqual(n?.transportPath, "/ray")
        XCTAssertEqual(n?.tls?.sni, "cdn.example.com")
        XCTAssertTrue(n?.tls?.isReality == false)
    }

    func testHysteria2Link() {
        let link = "hysteria2://mypassword@1.2.3.4:443?sni=hy.example.com&insecure=1" +
        "&obfs=salamander&obfs-password=obfs123&upmbps=50&downmbps=200#HY%20Node"
        let n = ShareLinkParser.parse(text: link, sourceID: "s").nodes.first
        XCTAssertEqual(n?.proto, .hysteria2)
        XCTAssertEqual(n?.credential, "mypassword")
        XCTAssertEqual(n?.obfsPassword, "obfs123")
        XCTAssertEqual(n?.upMbps, 50)
        XCTAssertEqual(n?.downMbps, 200)
        XCTAssertEqual(n?.tls?.allowInsecure, true)
        XCTAssertEqual(n?.name, "HY Node")
    }

    func testHy2AliasIsAccepted() {
        let n = ShareLinkParser.parse(text: "hy2://pw@9.9.9.9:8443?sni=a.com#alias", sourceID: "s").nodes.first
        XCTAssertEqual(n?.proto, .hysteria2)
        XCTAssertEqual(n?.port, 8443)
    }

    func testClashVlessRealityAndHysteria2() {
        let yaml = """
        proxies:
          - name: R
            type: vless
            server: 1.1.1.1
            port: 443
            uuid: uu
            network: tcp
            tls: true
            servername: www.apple.com
            client-fingerprint: chrome
            flow: xtls-rprx-vision
            reality-opts:
              public-key: PK
              short-id: ab12
          - {name: H, type: hysteria2, server: 2.2.2.2, port: 443, password: pw, sni: h.com, obfs: salamander, obfs-password: op, up: 50, down: 200, skip-cert-verify: true}
        """
        let r = ClashYAMLParser.parse(text: yaml, sourceID: "t")
        XCTAssertEqual(r.nodes.count, 2)
        let v = r.nodes.first { $0.proto == .vless }!
        XCTAssertEqual(v.tls?.realityPublicKey, "PK")
        XCTAssertEqual(v.tls?.realityShortId, "ab12")
        XCTAssertEqual(v.tls?.fingerprint, "chrome")
        XCTAssertEqual(v.flow, "xtls-rprx-vision")
        let h = r.nodes.first { $0.proto == .hysteria2 }!
        XCTAssertEqual(h.obfsPassword, "op")
        XCTAssertEqual(h.upMbps, 50)
        XCTAssertEqual(h.downMbps, 200)
    }

    func testDedup() {
        let a = ProxyNode(id: "x", name: "a", proto: .trojan, host: "h", port: 1, credential: "c", sourceID: "s")
        let b = ProxyNode(id: "x", name: "b", proto: .trojan, host: "h", port: 1, credential: "c", sourceID: "s")
        XCTAssertEqual(NodeDeduper.dedup([a, b]).count, 1)
    }


    // MARK: - Format provider JSON-in-YAML (satu baris, kunci berkutip)

    /// vzxiaov/free_proxies & banyak aggregator menulis tiap proxy sebagai
    /// objek JSON di dalam YAML: kunci BERKUTIP + escape `\u003e` + header
    /// `HOST` (kapital). Sebelum diperbaiki, feed ini menghasilkan 0 node.
    func testJsonStyleProviderFormat() {
        let yaml = """
        proxies:
          - {"name":"SS-美国\\u003e英国-NF-144.217.164.29:12000","type":"ss","server":"144.217.164.29","port":12000,"password":"8JCsPssfgS8tiRwiMlhARg==","cipher":"aes-256-gcm"}
          - {"name":"VMESS-未知\\u003e德国-547.rtxconfigz.shop:8080","type":"vmess","server":"547.rtxconfigz.shop","port":8080,"uuid":"44e57485-eccc-46ef-808f-cd17ac810018","alterId":0,"cipher":"auto","network":"ws","servername":"node4.rtxconfigz.com","http-opts":{},"h2-opts":{},"skip-cert-verify":true,"ws-opts":{"path":"/@Malinda6104","headers":{"HOST":"node4.rtxconfigz.com"}}}
          - {"name":"SSR-美国-107.151.182.253:8080","type":"ssr","server":"107.151.182.253","port":8080,"password":"14fFPrbezE3HDZzsMOr6","cipher":"rc4-md5","protocol":"origin","obfs":"plain"}
        """
        let r = ClashYAMLParser.parse(text: yaml, sourceID: "t")
        XCTAssertEqual(r.nodes.count, 2, "harus ada 2 node yang didukung")
        XCTAssertEqual(r.unsupported, 1, "SSR memang tidak didukung")
        let ss = r.nodes.first { $0.proto == .shadowsocks }!
        XCTAssertEqual(ss.host, "144.217.164.29")
        XCTAssertEqual(ss.port, 12000)
        XCTAssertEqual(ss.cipher, "aes-256-gcm")
        XCTAssertEqual(ss.credential, "8JCsPssfgS8tiRwiMlhARg==")
        XCTAssertFalse(ss.name.contains("\\u"), "escape unicode harus jadi karakter aslinya")
        XCTAssertTrue(ss.name.contains(">"), "\\u003e harus menjadi >")
        let vm = r.nodes.first { $0.proto == .vmess }!
        XCTAssertEqual(vm.transport, .ws)
        XCTAssertEqual(vm.transportPath, "/@Malinda6104")
        XCTAssertEqual(vm.transportHost, "node4.rtxconfigz.com", "header HOST (kapital) harus terbaca")
        XCTAssertEqual(vm.tls?.sni, "node4.rtxconfigz.com")
        XCTAssertEqual(vm.tls?.allowInsecure, true)
    }

    /// Key `Host` huruf besar-kecil campuran juga harus aman.
    func testWsHeaderHostCaseInsensitive() {
        let yaml = """
        proxies:
          - {"name":"A","type":"vmess","server":"a.com","port":443,"uuid":"u","network":"ws","tls":true,"ws-opts":{"path":"/p","headers":{"Host":"a.com"}}}
          - {"name":"B","type":"vmess","server":"b.com","port":443,"uuid":"u","network":"ws","tls":true,"ws-opts":{"path":"/p","headers":{"host":"b.com"}}}
        """
        let r = ClashYAMLParser.parse(text: yaml, sourceID: "t")
        XCTAssertEqual(r.nodes.count, 2)
        XCTAssertEqual(r.nodes.map { $0.transportHost }, ["a.com", "b.com"])
    }

    /// `proxy-groups` punya `type: select/reject` — bukan node. Kalau ikut
    /// diparse, tiap group dihitung protokol tak didukung dan mengotori UI.
    func testProxyGroupsAreNotCountedAsNodes() {
        let yaml = """
        proxies:
          - {name: A, type: ss, server: 1.1.1.1, port: 8388, cipher: aes-256-gcm, password: p}
        proxy-groups:
          - {name: PROXY, type: select, proxies: [A, DIRECT]}
          - {name: REJECT, type: reject}
        rules:
          - MATCH,PROXY
        """
        let r = ClashYAMLParser.parse(text: yaml, sourceID: "t")
        XCTAssertEqual(r.nodes.count, 1)
        XCTAssertEqual(r.unsupported, 0)
    }

    /// D48 — parser sekarang memakai `fastTrim` sendiri (bukan
    /// `trimmingCharacters(in:)`, yang lewat NSCharacterSet dan lambat) dan
    /// memecah baris dengan `split(on: "\n")`, bukan `components(separatedBy:
    /// .newlines)`. Test ini mengunci hasil parse tetap sama untuk berkas CRLF:
    /// kalau CR tidak dipangkas, host akan jadi "1.1.1.1\r" dan ditolak validator.
    func testWindowsLineEndingsStillParse() {
        let yaml = [
            "proxies:",
            "  - {name: A, type: ss, server: 1.1.1.1, port: 8388, cipher: aes-256-gcm, password: p}",
            "proxy-groups:",
            "  - {name: PROXY, type: select, proxies: [A]}",
        ].joined(separator: "\r\n")
        let r = ClashYAMLParser.parse(text: yaml, sourceID: "t")
        XCTAssertEqual(r.nodes.count, 1, "CRLF harus tetap menghasilkan 1 node")
        XCTAssertEqual(r.nodes.first?.host, "1.1.1.1", "CR tidak boleh ikut jadi bagian host")
        XCTAssertEqual(r.nodes.first?.port, 8388)
        XCTAssertEqual(r.nodes.first?.name, "A", "CR tidak boleh ikut jadi bagian nama")
        XCTAssertEqual(r.unsupported, 0)
    }

    /// Baris kosong berisi whitespace dan baris komentar harus tetap diabaikan
    /// setelah `fastTrim` + `indentWidth` menggantikannya.
    func testBlankAndCommentLinesAreIgnored() {
        let yaml = """
        proxies:
          	
          # komentar di tengah
          - {name: A, type: ss, server: 1.1.1.1, port: 8388, cipher: aes-256-gcm, password: p}

          - {name: B, type: ss, server: 2.2.2.2, port: 8389, cipher: aes-256-gcm, password: p}
        """
        let r = ClashYAMLParser.parse(text: yaml, sourceID: "t")
        XCTAssertEqual(r.nodes.count, 2)
        XCTAssertEqual(r.nodes.map(\.host), ["1.1.1.1", "2.2.2.2"])
    }

    /// Indentasi kini dihitung per BYTE UTF-8 (D48), bukan per "Character"
    /// — untuk indentasi ASCII hasilnya sama, tapi jalur ini harus tetap benar
    /// saat nama node berisi emoji / non-ASCII.
    func testNonASCIINamesStillParse() {
        let yaml = """
        proxies:
          - {name: 🇮🇩 Jakarta, type: ss, server: 1.1.1.1, port: 8388, cipher: aes-256-gcm, password: p}
        """
        let r = ClashYAMLParser.parse(text: yaml, sourceID: "t")
        XCTAssertEqual(r.nodes.count, 1)
        XCTAssertEqual(r.nodes.first?.port, 8388, "port harus tetap angka, bukan gagal parse")
        XCTAssertTrue(r.nodes.first?.name.contains("Jakarta") == true)
    }
}
