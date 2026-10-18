import Foundation

/// Kebalikan `ShareLinkParser`: node → share-link (`vless://…`, `trojan://…`).
///
/// Dipakai Backup grup manual: satu akun satu baris, format yang SAMA PERSIS
/// dengan yang diterima tab "Dari tautan" — jadi file backup bisa dipulihkan
/// dengan tempel ulang, dan dijamin lolos parser sendiri (round-trip diuji).
///
/// Aturan cermin parser (jangan diubah sepihak — keduanya harus sepakat):
/// - vless: `security=tls|reality|none`, `sni`, `allowinsecure=1` bila perlu,
///   `pbk`/`sid`/`fp`/`alpn`, `type` ws|grpc|http|tcp, `path`/`host`,
///   `serviceName` untuk grpc, `flow`.
/// - vmess: JSON base64 `{v,ps,add,port,id,aid,net,host,path,tls,sni[,scy]}`.
/// - trojan: `password@host:port?sni=&allowInsecure=&type=&path=&host=`.
/// - ss: SIP002 `base64(method:password)@host:port`.
/// - hysteria2: `password@host:port?sni=&insecure=&obfs=&obfs-password=&
///   upmbps=&downmbps=` (hanya salamander yang didukung parser).
/// - http/socks: `scheme://[user:pass@]host:port`.
public enum ShareLinkEncoder {
    /// Satu node menjadi satu baris share-link. Tidak pernah `nil` — semua
    /// protokol yang disimpan app bisa diserialkan.
    public static func link(for n: ProxyNode) -> String {
        switch n.proto {
        case .vless: return vless(n)
        case .vmess: return vmess(n)
        case .trojan: return trojan(n)
        case .shadowsocks: return shadowsocks(n)
        case .hysteria2: return hysteria2(n)
        case .http, .socks: return plainProxy(n)
        }
    }

    /// Banyak node menjadi isi file backup (satu link per baris).
    public static func document(for nodes: [ProxyNode]) -> String {
        nodes.map { link(for: $0) }.joined(separator: "\n") + "\n"
    }

    // MARK: - Bantuan

    /// Host untuk URL: IPv6 dibungkus `[...]`, brackets ganda dicegah.
    static func urlHost(_ host: String) -> String {
        guard host.contains(":") else { return host }
        if host.hasPrefix("[") && host.hasSuffix("]") { return host }
        return "[\(host)]"
    }

    private static func query(_ pairs: [(String, String?)]) -> String {
        pairs.compactMap { k, v in
            guard let v, !v.isEmpty else { return nil }
            let ek = k.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? k
            let ev = v.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? v
            return "\(ek)=\(ev)"
        }.joined(separator: "&")
    }

    private static func fragment(_ name: String) -> String {
        "#" + (name.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? name)
    }

    private static func transportType(_ t: Transport) -> String {
        switch t {
        case .ws: return "ws"
        case .grpc: return "grpc"
        case .http: return "http"
        case .tcp: return "tcp"
        }
    }

    // MARK: - Per protokol

    private static func vless(_ n: ProxyNode) -> String {
        let tls = n.tls
        let security: String
        if tls?.isReality == true { security = "reality" }
        else if tls?.enabled == true { security = "tls" }
        else { security = "none" }
        var q: [(String, String?)] = [
            ("encryption", "none"),
            ("security", security),
            ("sni", tls?.sni ?? n.host),
        ]
        if tls?.allowInsecure == true { q.append(("allowinsecure", "1")) }
        q.append(("pbk", tls?.realityPublicKey))
        q.append(("sid", tls?.realityShortId))
        q.append(("fp", tls?.fingerprint))
        if let alpn = tls?.alpn, !alpn.isEmpty {
            q.append(("alpn", alpn.joined(separator: ",")))
        }
        q.append(("type", transportType(n.transport)))
        if n.transport == .grpc {
            q.append(("serviceName", n.transportPath))
        } else {
            q.append(("path", n.transportPath))
            q.append(("host", n.transportHost))
        }
        q.append(("flow", n.flow))
        let qs = query(q)
        return "vless://\(n.credential)@\(urlHost(n.host)):\(n.port)" +
            (qs.isEmpty ? "" : "?\(qs)") + fragment(n.name)
    }

    private static func vmess(_ n: ProxyNode) -> String {
        var obj: [String: Any] = [
            "v": "2",
            "ps": n.name,
            "add": n.host,
            "port": String(n.port),
            "id": n.credential,
            "aid": String(n.alterId ?? 0),
            "net": transportType(n.transport),
            "type": "none",
            "host": n.transportHost ?? "",
            "path": n.transportPath ?? "",
            "tls": (n.tls?.enabled == true) ? "tls" : "",
            "sni": n.tls?.sni ?? "",
        ]
        if let cipher = n.cipher, !cipher.isEmpty { obj["scy"] = cipher }
        let data = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
        return "vmess://" + data.base64EncodedString()
    }

    private static func trojan(_ n: ProxyNode) -> String {
        let tls = n.tls
        var q: [(String, String?)] = [
            ("sni", tls?.sni ?? n.host),
            ("type", transportType(n.transport)),
            ("path", n.transport == .grpc ? nil : n.transportPath),
            ("host", n.transportHost),
        ]
        if tls?.allowInsecure == true { q.append(("allowInsecure", "1")) }
        let pwd = n.credential.addingPercentEncoding(withAllowedCharacters: .urlUserAllowed) ?? n.credential
        let qs = query(q)
        return "trojan://\(pwd)@\(urlHost(n.host)):\(n.port)" +
            (qs.isEmpty ? "" : "?\(qs)") + fragment(n.name)
    }

    private static func shadowsocks(_ n: ProxyNode) -> String {
        let method = (n.cipher?.isEmpty == false) ? n.cipher! : "aes-256-gcm"
        let cred = "\(method):\(n.credential)".data(using: .utf8) ?? Data()
        return "ss://\(cred.base64EncodedString())@\(urlHost(n.host)):\(n.port)" + fragment(n.name)
    }

    private static func hysteria2(_ n: ProxyNode) -> String {
        // Parser hanya menerima salamander — jangan tulis obfs lain.
        var q: [(String, String?)] = [
            ("sni", n.tls?.sni ?? n.host),
        ]
        if n.tls?.allowInsecure == true { q.append(("insecure", "1")) }
        if let obfs = n.obfsPassword, !obfs.isEmpty {
            q.append(("obfs", "salamander"))
            q.append(("obfs-password", obfs))
        }
        if let up = n.upMbps { q.append(("upmbps", String(up))) }
        if let down = n.downMbps { q.append(("downmbps", String(down))) }
        let pwd = n.credential.addingPercentEncoding(withAllowedCharacters: .urlUserAllowed) ?? n.credential
        let qs = query(q)
        return "hysteria2://\(pwd)@\(urlHost(n.host)):\(n.port)" +
            (qs.isEmpty ? "" : "?\(qs)") + fragment(n.name)
    }

    private static func plainProxy(_ n: ProxyNode) -> String {
        let scheme = n.proto == .http ? "http" : "socks5"
        let userinfo: String
        if n.credential.isEmpty {
            userinfo = ""
        } else {
            userinfo = (n.credential.addingPercentEncoding(withAllowedCharacters: .urlUserAllowed)
                        ?? n.credential) + "@"
        }
        return "\(scheme)://\(userinfo)\(urlHost(n.host)):\(n.port)" + fragment(n.name)
    }
}
