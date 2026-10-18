import XCTest
@testable import FreePNApp

/// Backup grup manual = node → share-link (`ShareLinkEncoder`), yang harus
/// lolos parser sendiri (`ShareLinkParser`) tanpa kehilangan field.
///
/// Tanpa round-trip ini, file backup bisa berisi link yang saat dipulihkan
/// diam-diam kehilangan SNI/password/path — backup yang merusak data yang
/// katanya dilindunginya. Setiap protokol yang disimpan app diuji.
final class ShareLinkEncoderTests: XCTestCase {
    private func tls(sni: String = "sni.com") -> TLSOptions {
        TLSOptions(enabled: true, sni: sni, allowInsecure: false)
    }

    private func nodes() -> [ProxyNode] {
        [
            ProxyNode(name: "Trojan WS", proto: .trojan, host: "t.example.com", port: 443,
                      credential: "p@ss:word", transport: .ws,
                      transportPath: "/trojan", transportHost: "t.example.com",
                      tls: tls(), sourceID: "g"),
            ProxyNode(name: "VLESS REALITY", proto: .vless, host: "v.example.com", port: 443,
                      credential: "11111111-2222-3333-4444-555555555555",
                      transport: .tcp,
                      tls: TLSOptions(enabled: true, sni: "v.example.com",
                                      realityPublicKey: "pubkey", realityShortId: "sid",
                                      fingerprint: "chrome", alpn: ["h2"]),
                      flow: "xtls-rprx-vision", sourceID: "g"),
            ProxyNode(name: "VLESS WS", proto: .vless, host: "w.example.com", port: 443,
                      credential: "22222222-2222-3333-4444-555555555555",
                      transport: .ws, transportPath: "/p", transportHost: "w.example.com",
                      tls: tls(sni: "w.example.com"), sourceID: "g"),
            ProxyNode(name: "VMess", proto: .vmess, host: "m.example.com", port: 443,
                      credential: "33333333-2222-3333-4444-555555555555",
                      cipher: "auto", alterId: 0, transport: .ws,
                      transportPath: "/vm", transportHost: "m.example.com",
                      tls: tls(sni: "m.example.com"), sourceID: "g"),
            ProxyNode(name: "SS", proto: .shadowsocks, host: "s.example.com", port: 8388,
                      credential: "secret", cipher: "chacha20-ietf-poly1305", sourceID: "g"),
            ProxyNode(name: "HY2", proto: .hysteria2, host: "h.example.com", port: 443,
                      credential: "pw", tls: tls(sni: "h.example.com"),
                      obfsPassword: "obfs", upMbps: 30, downMbps: 120, sourceID: "g"),
            ProxyNode(name: "HTTP", proto: .http, host: "p.example.com", port: 8080,
                      credential: "user:pass", sourceID: "g"),
            ProxyNode(name: "SOCKS", proto: .socks, host: "k.example.com", port: 1080,
                      credential: "", sourceID: "g"),
        ]
    }

    /// Tiap node: encode → parse → semua field penting sama.
    func testRoundTripPreservesEveryField() {
        for n in nodes() {
            let line = ShareLinkEncoder.link(for: n)
            let out = ShareLinkParser.parse(text: line, sourceID: "g-restore")
            XCTAssertEqual(out.nodes.count, 1, "\(n.proto.rawValue): \(line.prefix(80))")
            guard let r = out.nodes.first else { continue }
            XCTAssertEqual(r.proto, n.proto, "proto \(n.name)")
            XCTAssertEqual(r.host, n.host, "host \(n.name)")
            XCTAssertEqual(r.port, n.port, "port \(n.name)")
            XCTAssertEqual(r.credential, n.credential, "credential \(n.name)")
            XCTAssertEqual(r.transport, n.transport, "transport \(n.name)")
            XCTAssertEqual(r.transportPath ?? "", n.transportPath ?? "", "path \(n.name)")
            XCTAssertEqual(r.transportHost ?? "", n.transportHost ?? "", "host-header \(n.name)")
            XCTAssertEqual(r.name, n.name, "nama \(n.name)")
            // `nil` vs `TLSOptions(enabled:false)` dianggap sama: parser
            // selalu membangun struct TLS eksplisit untuk http/socks.
            XCTAssertEqual(r.tls?.enabled ?? false, n.tls?.enabled ?? false, "tls \(n.name)")
            XCTAssertEqual(r.tls?.sni ?? "", n.tls?.sni ?? "", "sni \(n.name)")
            XCTAssertEqual(r.tls?.allowInsecure ?? false, n.tls?.allowInsecure ?? false,
                           "insecure \(n.name)")
            XCTAssertEqual(r.flow ?? "", n.flow ?? "", "flow \(n.name)")
            XCTAssertEqual(r.cipher ?? "", n.cipher ?? "", "cipher \(n.name)")
            XCTAssertEqual(r.alterId ?? 0, n.alterId ?? 0, "alterId \(n.name)")
            XCTAssertEqual(r.obfsPassword ?? "", n.obfsPassword ?? "", "obfs \(n.name)")
            XCTAssertEqual(r.upMbps ?? 0, n.upMbps ?? 0, "up \(n.name)")
            XCTAssertEqual(r.downMbps ?? 0, n.downMbps ?? 0, "down \(n.name)")
            XCTAssertEqual(r.tls?.realityPublicKey ?? "", n.tls?.realityPublicKey ?? "", "pbk \(n.name)")
            XCTAssertEqual(r.tls?.realityShortId ?? "", n.tls?.realityShortId ?? "", "sid \(n.name)")
            XCTAssertEqual(r.tls?.fingerprint ?? "", n.tls?.fingerprint ?? "", "fp \(n.name)")
            XCTAssertEqual(r.tls?.alpn ?? [], n.tls?.alpn ?? [], "alpn \(n.name)")
        }
    }

    /// Dokumen backup: satu baris per akun, semuanya lolos parser.
    func testDocumentParsesBackCompletely() {
        let all = nodes()
        let doc = ShareLinkEncoder.document(for: all)
        XCTAssertEqual(doc.components(separatedBy: .newlines).filter { !$0.isEmpty }.count, all.count)
        let out = ShareLinkParser.parse(text: doc, sourceID: "g-restore")
        XCTAssertEqual(out.nodes.count, all.count, "semua baris backup harus ter-parse")
        XCTAssertEqual(out.malformed, 0)
    }

    /// IPv6 tidak boleh merusak link (kurung siku tepat satu lapis).
    func testIPv6HostIsBracketedOnce() {
        let n = ProxyNode(name: "V6", proto: .trojan, host: "2001:db8::1", port: 443,
                          credential: "pw", tls: tls(sni: "h.com"), sourceID: "g")
        let line = ShareLinkEncoder.link(for: n)
        XCTAssertTrue(line.contains("[2001:db8::1]"), line)
        XCTAssertFalse(line.contains("[["))
        let out = ShareLinkParser.parse(text: line, sourceID: "g")
        XCTAssertEqual(out.nodes.first?.host, "2001:db8::1")
    }
}
