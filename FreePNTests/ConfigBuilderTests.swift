import XCTest
@testable import FreePNApp

final class ConfigBuilderTests: XCTestCase {
    private func node() -> ProxyNode {
        ProxyNode(name: "T", proto: .trojan, host: "9.9.9.9", port: 443,
                  credential: "pw", tls: TLSOptions(enabled: true, sni: "sni.com"), sourceID: "s")
    }

    func testInclusiveFinalIsDirect() throws {
        let b = SingBoxConfigBuilder()
        let json = b.configJSON(node: node(), split: SplitTunnelConfig(mode: .inclusive, inclusiveApps: ["/Applications/Safari.app"]), clashPort: 9090)
        let o = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
        let route = o["route"] as! [String: Any]
        XCTAssertEqual(route["final"] as? String, "direct")
        let rules = route["rules"] as! [[String: Any]]
        XCTAssertTrue(rules.contains { ($0["outbound"] as? String) == "proxy" })
    }

    func testExclusiveFinalIsProxy() throws {
        let b = SingBoxConfigBuilder()
        let json = b.configJSON(node: node(), split: SplitTunnelConfig(mode: .exclusive, exclusiveApps: ["/Applications/Safari.app"]), clashPort: 9090)
        let o = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
        let route = o["route"] as! [String: Any]
        XCTAssertEqual(route["final"] as? String, "proxy")
        let rules = route["rules"] as! [[String: Any]]
        XCTAssertTrue(rules.contains { ($0["outbound"] as? String) == "direct" && $0["process_path_regex"] != nil })
    }

    func testAlwaysDirectLocalAndServer() throws {
        let b = SingBoxConfigBuilder()
        let json = b.configJSON(node: node(), split: SplitTunnelConfig(), clashPort: 28909)
        // NB: JSONSerialization meng-escape "/" menjadi "\/", jadi asersi tanpa slash.
        XCTAssertTrue(json.contains("10.0.0.0"))
        XCTAssertTrue(json.contains("9.9.9.9"))
    }

    func testInclusiveEmptyIsBypassAll() {
        XCTAssertTrue(SingBoxConfigBuilder.isBypassAll(split: SplitTunnelConfig(mode: .inclusive)))
        XCTAssertFalse(SingBoxConfigBuilder.isBypassAll(split: SplitTunnelConfig(mode: .exclusive)))
        XCTAssertFalse(SingBoxConfigBuilder.isBypassAll(split: SplitTunnelConfig(mode: .inclusive, inclusiveApps: ["/Applications/Safari.app"])))
    }

    func testSocksOnlyHasNoTun() throws {
        // Varian SOCKS-only untuk mode System Extension: tanpa TUN, hanya mixed.
        let b = SingBoxConfigBuilder()
        let json = b.configJSON(node: node(), split: SplitTunnelConfig(), clashPort: 28909, mixedPort: 28108, tunEnabled: false)
        let o = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
        let ins = o["inbounds"] as! [[String: Any]]
        XCTAssertFalse(ins.contains { ($0["type"] as? String) == "tun" })
        XCTAssertTrue(ins.contains { ($0["type"] as? String) == "mixed" })
    }

    func testTunStrictRouteAndAutoInterface() throws {
        let b = SingBoxConfigBuilder()
        let json = b.configJSON(node: node(), split: SplitTunnelConfig(), clashPort: 28909, mixedPort: 28108)
        let o = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
        let ins = o["inbounds"] as! [[String: Any]]
        let tun = ins.first { ($0["type"] as? String) == "tun" }!
        // strict_route=true agar default route diambil alih (false = bocor via en0).
        XCTAssertEqual(tun["strict_route"] as? Bool, true)
        XCTAssertEqual(tun["auto_route"] as? Bool, true)
        // Jangan hardcode utun9 (bentrok bila sudah ada).
        XCTAssertNil(tun["interface_name"])
        XCTAssertNotNil(tun["mtu"])
        // Port baru di luar ekosistem Clash 9090/1080.
        let mixed = ins.first { ($0["type"] as? String) == "mixed" }!
        XCTAssertEqual(mixed["listen_port"] as? Int, 28108)
        let exp = o["experimental"] as! [String: Any]
        let api = exp["clash_api"] as! [String: Any]
        XCTAssertEqual(api["external_controller"] as? String, "127.0.0.1:28909")
    }

    /// REGRESI D83 — resolver hostname node TIDAK BOLEH `proxy-dns`.
    ///
    /// `proxy-dns` ber-`detour: "proxy"`, jadi me-resolve hostname node berarti
    /// membangun koneksi ke outbound yang butuh hostname itu ter-resolve dulu:
    /// `DNS query loopback in transport[proxy-dns]`, dan core tetap hidup
    /// (`sing-box check` lolos) sehingga tidak ada tes lama yang menangkapnya.
    ///
    /// Node ber-hostname + TUN `strict_route` = seluruh internet machine mati,
    /// karena default route sudah diambil alih sebelum outbound pernah berhasil.
    func testProxyOutboundResolvesNodeHostnameWithoutLoopback() throws {
        let b = SingBoxConfigBuilder()
        let json = b.configJSON(node: node(), split: SplitTunnelConfig(), clashPort: 28909)
        let o = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]

        let outs = o["outbounds"] as! [[String: Any]]
        let proxy = outs.first { ($0["tag"] as? String) == "proxy" }!
        XCTAssertEqual(proxy["domain_resolver"] as? String, "direct-dns",
                       "outbound proxy me-resolve hostname node lewat proxy-dns -> DNS loopback")

        // Server `proxy-dns` sendiri tetap ber-detour ke proxy (itu justru
        // mekanisme anti-bocor: query DNS user masuk lewat tunnel sehingga ISP
        // tidak bisa melihatnya). Yang dilarang hanya resolver outbound proxy
        // memakai server itu.
        let dns = o["dns"] as! [String: Any]
        let servers = dns["servers"] as! [[String: Any]]
        let proxyDNS = servers.first { ($0["tag"] as? String) == "proxy-dns" }!
        XCTAssertEqual(proxyDNS["detour"] as? String, "proxy")

        // Tapi domain milik user sendiri tetap lewat VPN (tidak bocor ke ISP).
        XCTAssertEqual(dns["final"] as? String, "proxy-dns")
        let route = o["route"] as! [String: Any]
        XCTAssertEqual(route["default_domain_resolver"] as? String, "proxy-dns")
    }

    // MARK: - Config probe (verifikasi akses internet)
    private func probeNodes(_ n: Int) -> [ProxyNode] {
        (0..<n).map { i in
            ProxyNode(name: "P\(i)", proto: .trojan, host: "1.1.1.\(i + 1)", port: 443,
                      credential: "pw\(i)", tls: TLSOptions(enabled: true, sni: "sni.com"), sourceID: "s")
        }
    }

    /// Config probe harus punya SATU outbound per node dengan tag yang cocok
    /// dengan yang dipanggil InternetProbe lewat `/proxies/<tag>/delay`.
    func testProbeConfigHasOneTaggedOutboundPerNode() throws {
        let b = SingBoxConfigBuilder()
        let json = b.probeConfigJSON(nodes: probeNodes(4), clashPort: 28909, mixedPort: 28108)
        let o = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
        let outs = o["outbounds"] as! [[String: Any]]
        for i in 0..<4 {
            let tag = SingBoxConfigBuilder.probeTag(i)
            XCTAssertTrue(outs.contains { ($0["tag"] as? String) == tag }, "outbound \(tag) hilang")
        }
        XCTAssertTrue(outs.contains { ($0["tag"] as? String) == "direct" })
    }

    /// Probe TANPA TUN: tidak butuh root dan tidak boleh mengganggu sesi VPN
    /// yang sedang jalan (TUN kedua akan merebut default route).
    func testProbeConfigHasNoTunAndMixedOnly() throws {
        let b = SingBoxConfigBuilder()
        let json = b.probeConfigJSON(nodes: probeNodes(2), clashPort: 28909, mixedPort: 28108)
        let o = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
        let ins = o["inbounds"] as! [[String: Any]]
        XCTAssertFalse(ins.contains { ($0["type"] as? String) == "tun" })
        XCTAssertTrue(ins.contains { $0["type"] as? String == "mixed" })
    }

    /// `route.final` WAJIB lewat proxy, bukan "direct" — kalau request bocor ke
    /// koneksi lokal, hasil ukur internet selalu "berhasil" palsu.
    func testProbeRouteFinalGoesThroughProxyNotDirect() throws {
        let b = SingBoxConfigBuilder()
        let json = b.probeConfigJSON(nodes: probeNodes(1), clashPort: 28909, mixedPort: 28108)
        let o = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
        let route = o["route"] as! [String: Any]
        XCTAssertEqual(route["final"] as? String, SingBoxConfigBuilder.probeTag(0))
        XCTAssertNotEqual(route["final"] as? String, "direct")
        // Resolver wajib: sing-box >=1.10 menolak outbound tanpa domain_resolver.
        let outs = o["outbounds"] as! [[String: Any]]
        let first = outs.first { ($0["tag"] as? String) == SingBoxConfigBuilder.probeTag(0) }!
        XCTAssertEqual(first["domain_resolver"] as? String, "probe-dns")
        // Port clash API harus ikut yang dipakai InternetProbe.
        let api = (o["experimental"] as! [String: Any])["clash_api"] as! [String: Any]
        XCTAssertEqual(api["external_controller"] as? String, "127.0.0.1:28909")
    }

    // MARK: - Split tunneling per domain

    private func rules(_ json: String) throws -> [[String: Any]] {
        let o = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
        return (o["route"] as! [String: Any])["rules"] as! [[String: Any]]
    }

    private func dnsRulesOf(_ json: String) throws -> [[String: Any]] {
        let o = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
        return (o["dns"] as! [String: Any])["rules"] as! [[String: Any]]
    }

    /// Tanpa domain, config harus PERSIS seperti sebelumnya: tidak ada rule
    /// sniff, tidak ada `domain_suffix`.
    ///
    /// Ini yang menjaga user yang tidak memakai fitur baru tidak ikut menanggung
    /// biaya sniff pada semua trafiknya. Rule `action: sniff` membaca paket
    /// pertama setiap koneksi sebelum routing bisa diputuskan — overhead nyata,
    /// dan tidak boleh imposition pada orang yang tidak men ticked satu pun
    /// domain.
    func testNoSniffAndNoDomainRuleWhenNoDomainConfigured() throws {
        let json = SingBoxConfigBuilder().configJSON(
            node: node(), split: SplitTunnelConfig(mode: .exclusive,
                                                   exclusiveApps: ["/Applications/Safari.app"]),
            clashPort: 28909)
        for r in try rules(json) {
            XCTAssertNil(r["action"], "sniff tidak boleh muncul tanpa domain")
            XCTAssertNil(r["domain_suffix"])
        }
    }

    /// Sniff WAJIB ada sebelum rule domain — tanpa itu tidak ada yang bisa
    /// memberi sing-box nama host di TUN.
    func testSniffActionPrecedesDomainRule() throws {
        let json = SingBoxConfigBuilder().configJSON(
            node: node(), split: SplitTunnelConfig(mode: .exclusive,
                                                   exclusiveDomains: ["bank.com"]),
            clashPort: 28909)
        let rs = try rules(json)
        let sniff = rs.firstIndex { $0["action"] as? String == "sniff" }
        let domain = rs.firstIndex { $0["domain_suffix"] != nil }
        XCTAssertNotNil(sniff, "rule sniff wajib ada kalau ada domain")
        XCTAssertNotNil(domain)
        if let s = sniff, let d = domain {
            XCTAssertLessThan(s, d, "sniff harus sebelum rule domain")
        }
    }

    /// Sniff harus SESUDAH rule anti-loop, supaya trafik FreePN sendiri dan
    /// koneksi core ke server proxy tidak pernah ikut membaca paket.
    func testSniffComesAfterAntiLoopRules() throws {
        let json = SingBoxConfigBuilder().configJSON(
            node: node(), split: SplitTunnelConfig(mode: .exclusive,
                                                   exclusiveDomains: ["bank.com"]),
            clashPort: 28909)
        let rs = try rules(json)
        let sniff = rs.firstIndex { $0["action"] as? String == "sniff" }
        let loop = rs.firstIndex { ($0["process_name"] as? [String])?.contains("sing-box") == true }
        XCTAssertNotNil(loop)
        if let s = sniff, let l = loop {
            XCTAssertGreaterThan(s, l, "sniff harus setelah anti-loop process_name")
        }
    }

    /// Arah rule domain mengikuti mode, sama seperti rule app.
    func testDomainRuleTargetFollowsMode() throws {
        let b = SingBoxConfigBuilder()
        let ex = b.configJSON(node: node(),
                              split: SplitTunnelConfig(mode: .exclusive,
                                                       exclusiveDomains: ["bank.com"]),
                              clashPort: 28909)
        let exRule = try rules(ex).first { $0["domain_suffix"] != nil }!
        XCTAssertEqual(exRule["outbound"] as? String, "direct", "terdaftar di eksklusif = bypass")

        let inc = b.configJSON(node: node(),
                               split: SplitTunnelConfig(mode: .inclusive,
                                                        inclusiveDomains: ["video.com"]),
                               clashPort: 28909)
        let incRule = try rules(inc).first { $0["domain_suffix"] != nil }!
        XCTAssertEqual(incRule["outbound"] as? String, "proxy", "terdaftar di inklusif = lewat VPN")
    }

    /// Domain harus TEPAK AKHIR: rule IP privat dan host server proxy harus
    /// tetap menang lebih dulu.
    ///
    /// Kalau tidak, domain yang didaftarkan user bisa ikut mencengkeram
    /// koneksi ke server VPN dan membuat routing loop — persis D94, yang
    /// mematikan seluruh internet mesin.
    func testDomainRuleIsLastSoProxyServerCannotBeHijacked() throws {
        let json = SingBoxConfigBuilder().configJSON(
            node: node(), split: SplitTunnelConfig(mode: .exclusive,
                                                   exclusiveDomains: ["bank.com"]),
            clashPort: 28909)
        let rs = try rules(json)
        let last = rs.count - 1
        XCTAssertNotNil(rs[last]["domain_suffix"], "rule domain harus yang terakhir")
        let server = rs.firstIndex { $0["ip_cidr"] != nil && ($0["ip_cidr"] as? [String])?.contains("9.9.9.9") == true }
        XCTAssertNotNil(server, "rule IP server proxy wajib masih ada")
        if let s = server { XCTAssertLessThan(s, last) }
    }

    /// Rule DNS untuk domain harus ikut mengarahkan resolver, kalau tidak
    /// domain itu di-routing direct tapi resolution-nya tetap lewat VPN.
    func testDomainDnsRuleFollowsMode() throws {
        let b = SingBoxConfigBuilder()
        let ex = try dnsRulesOf(b.configJSON(
            node: node(),
            split: SplitTunnelConfig(mode: .exclusive, exclusiveDomains: ["bank.com"]),
            clashPort: 28909))
        XCTAssertEqual(ex.first { $0["domain_suffix"] != nil }?["server"] as? String, "direct-dns")

        let inc = try dnsRulesOf(b.configJSON(
            node: node(),
            split: SplitTunnelConfig(mode: .inclusive, inclusiveDomains: ["video.com"]),
            clashPort: 28909))
        XCTAssertEqual(inc.first { $0["domain_suffix"] != nil }?["server"] as? String, "proxy-dns")
    }

    /// Sakelar split mati = daftar kosong = tidak ada sniff, tidak ada rule
    /// domain, tidak ada rule DNS sama sekali.
    func testDisabledSplitWritesNoDomainRule() throws {
        let split = SplitTunnelConfig(mode: .exclusive,
                                      isEnabled: false,
                                      exclusiveDomains: ["bank.com"])
        let json = SingBoxConfigBuilder().configJSON(node: node(), split: split, clashPort: 28909)
        for r in try rules(json) {
            XCTAssertNil(r["domain_suffix"])
            XCTAssertNil(r["action"])
        }
        XCTAssertTrue(try dnsRulesOf(json).isEmpty)
    }

    /// Inklusif + HANYA domain (tanpa app) tetap bukan bypass-all.
    ///
    /// `isBypassAll` dulu hanya melihat daftar app, jadi mode inklusif dengan
    /// satu domain akan divonis "bypass semua" dan UI menolak connect, padahal user justru sedang menyetel aturannya.
    func testInclusiveWithOnlyDomainsIsNotBypassAll() {
        let split = SplitTunnelConfig(mode: .inclusive, inclusiveDomains: ["video.com"])
        XCTAssertFalse(SingBoxConfigBuilder.isBypassAll(split: split))
    }

    func testInclusiveWithNothingAtAllIsStillBypassAll() {
        XCTAssertTrue(SingBoxConfigBuilder.isBypassAll(split: SplitTunnelConfig(mode: .inclusive)))
    }

    /// Domain harus ikut tertulis ke config sebagai `domain_suffix` polos —
    /// BUKAN ikut masuk ke `process_path_regex`.
    func testDomainIsNotEmittedAsProcessPathRegex() throws {
        let json = SingBoxConfigBuilder().configJSON(
            node: node(),
            split: SplitTunnelConfig(mode: .exclusive,
                                     exclusiveApps: ["/Applications/Safari.app"],
                                     exclusiveDomains: ["bank.com"]),
            clashPort: 28909)
        for r in try rules(json) {
            let regexes = r["process_path_regex"] as? [String] ?? []
            XCTAssertFalse(regexes.contains("bank.com"), "domain bocor ke rule proses")
        }
    }
}

/// D97 — connect gagal harus menyebut SEBENARNYA, bukan menebak.
///
/// Kasus yang memaksa perubahan ini: node Trojan+WS di belakang Cloudflare
/// yang menyajikan sertifikat `CN=Cloudflare` tanpa `subjectAltName` dan
/// tanpa intermediate. sing-box menulis sebabnya dengan tepat, tapi app
/// menampilkan "server mungkin mati, kredensial mungkin salah" — dan user
/// mencoba SNI berbeda berulang kali tanpa pernah mendapat informasi baru.
final class CoreFailureReasonTests: XCTestCase {

    /// Baris persis yang keluar dari core pada kasus itu.
    private let realLine = "ERROR[0000] [2087506959 52ms] connection: open connection to api.ipify.org:443 using outbound/trojan[proxy]: tls: failed to verify certificate: x509: “Cloudflare” certificate is not standards compliant"

    func testExtractsTheRealCertReason() {
        let reason = CoreFailureReason.from(realLine)
        XCTAssertNotNil(reason)
        XCTAssertTrue(reason!.contains("failed to verify certificate"),
                      "penyebab TLS harus ikut tampil, bukan cuma Rate")
        XCTAssertFalse(reason!.hasPrefix("ERROR"), "prefiks sing-box harus dibuang")
        XCTAssertFalse(reason!.hasPrefix("["),
                       "id koneksi + durasi harus dibuang, bukan jadi awalan: \(reason!)")
        XCTAssertTrue(reason!.hasPrefix("connection:"))
    }

    func testEmptyTailGivesNoReason() {
        XCTAssertNil(CoreFailureReason.from(""))
        XCTAssertNil(CoreFailureReason.from("stopped"))
        XCTAssertNil(CoreFailureReason.from("   \n  \n"))
    }

    /// Log penuh baris pembuka; yang tampil harus yang paling menunjuk aksi.
    func testPrefersActionableLineOverChatter() {
        let tail = """
        INFO sing-box started (0.00s)
        DEBUG router: match[0] inbound=tun-in => route(proxy)
        ERROR outbound/trojan[proxy]: authentication failed
        INFO connection: connection download finished
        """
        let reason = CoreFailureReason.from(tail)
        XCTAssertEqual(reason, "outbound/trojan[proxy]: authentication failed",
                       "baris sinyal harus dipilih, bukan baris info mana pun")
    }

    func testRecognisesAuthTimeoutAndDNSFailures() {
        XCTAssertTrue(CoreFailureReason.from("ERROR x: i/o timeout")!.contains("i/o timeout"))
        XCTAssertTrue(CoreFailureReason.from("ERROR x: no such host")!.contains("no such host"))
        XCTAssertTrue(CoreFailureReason.from("ERROR x: connection refused")!.contains("refused"))
        XCTAssertTrue(CoreFailureReason.from("ERROR x: TLS handshake timeout")!
            .contains("handshake"))
    }

    /// Baris panjang harus dipotong — pesan error setinggi dialog bukan
    /// tooltip, dan ini yang tampil di layar Hubung.
    func testVeryLongReasonIsTruncated() {
        let long = "ERROR x: " + String(repeating: "a", count: 900)
        let r = CoreFailureReason.from(long, maxLength: 120)!
        XCTAssertLessThanOrEqual(r.count, 121)
        XCTAssertTrue(r.hasSuffix("…"))
    }

    /// Escape codes tidak boleh sampai ke layar user.
    func testANSICodesAreStripped() {
        let withColor = "\u{1B}[31mERROR\u{1B}[0m[0000] [1ms] connection: tls: failed to verify certificate"
        let r = CoreFailureReason.from(withColor)!
        XCTAssertFalse(r.contains("\u{1B}"), "kode warna harus dibuang")
        XCTAssertTrue(r.contains("failed to verify certificate"))
    }

    /// Kalau tidak ada baris bersinyal, ERROR/FATAL terakhir tetap dipakai —
    /// lebih baik daripada kembali ke tebakan generik.
    func testFallsBackToLastErrorLine() {
        let tail = """
        INFO started
        ERROR something went wrong
        INFO finished
        """
        XCTAssertEqual(CoreFailureReason.from(tail), "something went wrong")
    }

    /// Log yang isinya cuma info TIDAK boleh dipakai sebagai "penyebab" —
    /// menampilkan "sing-box started" sebagai alasan gagal sama buruknya,
    /// dan lebih buruk lagi karena terlihat seperti jawaban.
    func testInfoOnlyLogYieldsNoReason() {
        XCTAssertNil(CoreFailureReason.from("INFO sing-box started\nINFO tcp server started"))
    }
}

/// TCP keepalive di outbound node (butuh sing-box ≥1.13).
///
/// Stream panjang (opencode thinking) mati tiap 10–30 menit karena server
/// trial membunuh sesi idle — keepalive membuat sesi tak pernah idle di
/// sisi server. Kunci: field HARUS ada di semua protokol node (satu tempat:
/// `outboundJSON`), dan nilainya TERKUNCI ke konstanta (bukan literal yang
/// bisa menyimpang diam-diam antara connect dan probe).
final class NodeKeepAliveTests: XCTestCase {
    private func node(_ proto: NodeProtocol) -> ProxyNode {
        ProxyNode(name: "K", proto: proto, host: "9.9.9.9", port: 443,
                  credential: "pw", cipher: "aes-256-gcm",
                  tls: TLSOptions(enabled: true, sni: "sni.com"), sourceID: "s")
    }

    func testAllNodeProtocolsCarryKeepAlive() {
        let b = SingBoxConfigBuilder()
        for proto: NodeProtocol in [.trojan, .vless, .vmess, .shadowsocks, .hysteria2, .http, .socks] {
            let o = b.outboundJSON(node: node(proto))
            XCTAssertEqual(o["tcp_keep_alive"] as? String, SingBoxConfigBuilder.nodeKeepAlive,
                           "\(proto.rawValue) kehilangan keepalive")
            XCTAssertEqual(o["tcp_keep_alive_interval"] as? String,
                           SingBoxConfigBuilder.nodeKeepAliveInterval,
                           "\(proto.rawValue) kehilangan interval keepalive")
        }
    }

    func testProbeOutboundsCarryKeepAliveToo() throws {
        let b = SingBoxConfigBuilder()
        let json = b.probeConfigJSON(
            nodes: [node(.trojan)], clashPort: 28909, mixedPort: 28108)
        let o = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
        let outs = o["outbounds"] as! [[String: Any]]
        let probe = outs.first { ($0["tag"] as? String) == SingBoxConfigBuilder.probeTag(0) }!
        XCTAssertEqual(probe["tcp_keep_alive"] as? String, SingBoxConfigBuilder.nodeKeepAlive)
    }
}
