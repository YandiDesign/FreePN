import Foundation

/// Parser share-link vmess:// trojan:// ss:// (SIP002 + legacy).
/// Entri rusak dilewati, tidak menghentikan parsing.
public enum ShareLinkParser {
    public struct Outcome {
        public var nodes: [ProxyNode]
        public var unsupported: Int
        /// D91: link ber-skema yang didukung FreePN tapi gagal di-parse (field
        /// wajib hilang atau rusak). Sebelumnya nilai `nil` diabaikan begitu
        /// saja, jadi link yang hilang tidak pernah muncul di angka mana pun.
        public var malformed: Int
    }

    /// Buang kurung siku dari hasil `URLComponents.host`.
    ///
    /// Foundation di SDK ini mengembalikan host IPv6 DALAM kurung siku
    /// (`[2001:db8::1]`), dan kurung itu tidak boleh ikut disimpan sebagai
    /// alamat — `sing-box` menolaknya, dan `GeoIP` tidak akan mengenali
    /// sebagai literal IPv6. Feed gratis punya bentuk `hysteria2://user@[::1]:443`
    /// yang tidak bisa di-“ok"-kan tanpa langkah ini.
    private static func bareHost(_ h: String) -> String {
        (h.hasPrefix("[") && h.hasSuffix("]")) ? String(h.dropFirst().dropLast()) : h
    }

    public static func parse(text: String, sourceID: String) -> Outcome {
        var nodes: [ProxyNode] = []
        var unsupported = 0
        var malformed = 0
        // Jika seluruh teks adalah base64 berisi share-link, dekode dulu.
        var lines: [String]
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.contains("://") && !trimmed.contains("proxies:") && Base64Detector.looksLikeBase64(trimmed),
           let data = Base64Detector.decodeTolerant(trimmed),
           let decoded = String(data: data, encoding: .utf8), decoded.contains("://") {
            lines = decoded.components(separatedBy: .newlines)
        } else {
            lines = text.components(separatedBy: .newlines)
        }
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("vmess://") {
                if let n = parseVmess(line, sourceID: sourceID) { nodes.append(n) } else { malformed += 1 }
            } else if line.hasPrefix("trojan://") {
                if let n = parseTrojan(line, sourceID: sourceID) { nodes.append(n) } else { malformed += 1 }
            } else if line.hasPrefix("ss://") {
                if let n = parseSS(line, sourceID: sourceID) { nodes.append(n) } else { malformed += 1 }
            } else if line.hasPrefix("vless://") {
                if let n = parseVless(line, sourceID: sourceID) { nodes.append(n) } else { malformed += 1 }
            } else if line.hasPrefix("hysteria2://") || line.hasPrefix("hy2://") {
                if let n = parseHysteria2(line, sourceID: sourceID) { nodes.append(n) } else { malformed += 1 }
            } else if let scheme = Self.linkScheme(of: line), Self.supportedSchemes.contains(scheme) {
                // `socks5://` / `http://` — proxy sederhana tapi sing-box
                // menerimanya, jadi node-nya dipakai, bukan dihitung "tidak
                // didukung".
                if let n = parsePlainProxy(line, sourceID: sourceID) { nodes.append(n) } else { malformed += 1 }
            } else if let scheme = Self.linkScheme(of: line) {
                // Protokol yang KITA tidak bisa pakai (ssr, tuic, anytls,
                // wireguard, naive, hysteria v1…). Dihitung sebagai "tidak
                // didukung" supaya user melihat angkanya.
                //
                // Dulu baris-berkas ini jatuh ke `else { continue }`: tidak
                // diparse DAN tidak dihitung — 34 `ssr://` di feed EbraSha
                // hilang tanpa jejak, dan kolom Keterangan melaporkan angka
                // yang lebih kecil dari kenyataan.
                //
                // `http://`/`https://` diabaikan: itu link web, bukan node.
                unsupported += Self.unsupportedSchemeLines.contains(scheme) ? 1 : 0
            }
        }
        return Outcome(nodes: nodes, unsupported: unsupported, malformed: malformed)
    }

    /// Skema share-link yang FreePN bisa pakai sebagai node.
    private static let supportedSchemes: Set<String> = [
        "vmess", "trojan", "ss", "vless", "hysteria2", "hy2", "socks", "socks5", "http",
    ]

    /// Skema yang DIETAHUI sebagai node tapi belum didukung. Hanya skema ini
    /// yang dihitung; `http`/`https` di luar daftar karena dipakai juga untuk
    /// link biasa di dalam feed.
    private static let unsupportedSchemeLines: Set<String> = [
        "ssr", "tuic", "anytls", "wireguard", "snell", "mieru", "ssh",
        "hysteria", "naive+https", "juicity", "brook", "shadowtls",
    ]

    /// Skema dari `foo://bar`, lowercase. `nil` kalau baris bukan link skema.
    private static func linkScheme(of line: String) -> String? {
        guard let sep = line.range(of: "://") else { return nil }
        let raw = line[..<sep.lowerBound]
        guard !raw.isEmpty, raw.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "+" }) else {
            return nil
        }
        return String(raw).lowercased()
    }

    /// `socks5://[user:pass@]host:port[#name]` — sama untuk `http://`.
    ///
    /// Sengaja tidak lewat `URLComponents` untuk parsing kredensial: pada
    /// `socks5://1.2.3.4:1080` komponen `user` dikembalikan sebagai
    /// `1.2.3.4` (bukan host) kalau ada port di host, jadi pemisahan manual
    /// di `@` lebih dapat diandalkan.
    private static func parsePlainProxy(_ line: String, sourceID: String) -> ProxyNode? {
        guard let sep = line.range(of: "://") else { return nil }
        let scheme = String(line[..<sep.lowerBound]).lowercased()
        var rest = String(line[sep.upperBound...])

        var name = ""
        if let h = rest.firstIndex(of: "#") {
            name = String(rest[rest.index(after: h)...]).removingPercentEncoding ?? ""
            rest = String(rest[..<h])
        }
        var query = ""
        if let qm = rest.firstIndex(of: "?") {
            query = String(rest[rest.index(after: qm)...])
            rest = String(rest[..<qm])
        }

        var credential = ""
        if let at = rest.lastIndex(of: "@") {
            let userinfo = String(rest[..<at]).removingPercentEncoding ?? String(rest[..<at])
            credential = userinfo
            rest = String(rest[rest.index(after: at)...])
        }

        // Braket siku wajib untuk IPv6; `URLComponents` yang melepaskannya.
        let authority = "ss://\(rest)"
        guard let comps = URLComponents(string: authority),
              let rawHost = comps.host,
              let port = comps.port, Validators.isValidPort(port) else { return nil }
        let host = bareHost(rawHost)
        guard Validators.isValidHost(host) else { return nil }

        let proto: NodeProtocol = (scheme == "http") ? .http : .socks
        let disp = name.isEmpty ? "\(host):\(port)" : name
        let nodeID = ProxyNode.dedupID(proto: proto, host: host, port: port,
                                       credential: credential, transport: .tcp,
                                       path: nil, sni: nil)
        return ProxyNode(id: nodeID, name: disp, proto: proto, host: host, port: port,
                         credential: credential, transport: .tcp,
                         tls: TLSOptions(enabled: false), sourceID: sourceID,
                         countryCode: CountryInfer.resolveSync(name: disp, host: host))
    }

    // MARK: - vmess://base64JSON
    private static func parseVmess(_ line: String, sourceID: String) -> ProxyNode? {
        let b64 = String(line.dropFirst("vmess://".count))
        guard let data = Base64Detector.decodeTolerant(b64),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        guard let host = obj["add"] as? String, Validators.isValidHost(host) else { return nil }
        let port: Int
        if let p = obj["port"] as? Int { port = p }
        else if let ps = obj["port"] as? String, let p = Int(ps) { port = p }
        else { return nil }
        guard Validators.isValidPort(port) else { return nil }
        guard let id = obj["id"] as? String, !id.isEmpty else { return nil }
        let name = (obj["ps"] as? String)?.isEmpty == false ? obj["ps"] as! String : "\(host):\(port)"
        let net = (obj["net"] as? String ?? "tcp").lowercased()
        let transport: Transport = net == "ws" ? .ws : net == "grpc" ? .grpc : net == "h2" || net == "http" ? .http : .tcp
        let tlsStr = (obj["tls"] as? String ?? "").lowercased()
        let tls = TLSOptions(enabled: tlsStr == "tls", sni: obj["sni"] as? String ?? obj["host"] as? String, allowInsecure: false)
        let aid: Int? = (obj["aid"] as? Int) ?? Int((obj["aid"] as? String) ?? "")
        // D91: cipher, alterId, dan header Host ikut membedakan — dua akun
        // VMess dengan uuid sama tapi `scy`/Host berbeda adalah akun berbeda.
        let nodeID = ProxyNode.dedupID(proto: .vmess, host: host, port: port, credential: id,
                                       transport: transport, path: obj["path"] as? String, sni: tls.sni,
                                       transportHost: obj["host"] as? String,
                                       cipher: obj["scy"] as? String, alterId: aid)
        return ProxyNode(id: nodeID, name: name, proto: .vmess, host: host, port: port,
                         credential: id, cipher: obj["scy"] as? String, alterId: aid,
                         transport: transport, transportPath: obj["path"] as? String,
                         transportHost: obj["host"] as? String, tls: tls,
                         sourceID: sourceID, countryCode: CountryInfer.resolveSync(name: name, host: host))
    }

    // MARK: - trojan://password@host:port?query#nama
    private static func parseTrojan(_ line: String, sourceID: String) -> ProxyNode? {
        guard let comps = URLComponents(string: line),
              let rawHost = comps.host, Validators.isValidHost(bareHost(rawHost)),
              let port = comps.port, Validators.isValidPort(port),
              let pwd = comps.user, !pwd.isEmpty else { return nil }
        // Kurung IPv6 dilepas di sini (bukan di validator): `sing-box`
        // menolak `[2001:db8::1]` dan GeoIP tidak mengenalinya — sama
        // seperti jalur hysteria2/ss (D61).
        let host = bareHost(rawHost)
        let q = comps.queryItems ?? []
        func qq(_ k: String) -> String? { q.first(where: { $0.name == k })?.value }
        let sni = qq("sni") ?? qq("peer")
        let typeStr = (qq("type") ?? "tcp").lowercased()
        let transport: Transport = typeStr == "ws" ? .ws : typeStr == "grpc" ? .grpc : .tcp
        let tls = TLSOptions(enabled: true, sni: sni ?? host,
                             allowInsecure: (qq("allowInsecure") ?? "0") == "1")
        let name = comps.fragment?.removingPercentEncoding ?? "\(host):\(port)"
        let nodeID = ProxyNode.dedupID(proto: .trojan, host: host, port: port, credential: pwd,
                                       transport: transport, path: qq("path"), sni: tls.sni)
        return ProxyNode(id: nodeID, name: name.isEmpty ? "\(host):\(port)" : name,
                         proto: .trojan, host: host, port: port, credential: pwd,
                         transport: transport, transportPath: qq("path"),
                         transportHost: qq("host"), tls: tls,
                         sourceID: sourceID, countryCode: CountryInfer.resolveSync(name: name, host: host))
    }

    // MARK: - vless://uuid@host:port?params#nama
    ///
    /// Bentuk paling umum di feed gratis. Yang perlu dijaga: `security=reality`
    /// (butuh `pbk`+`sid`+`fp`) vs TLS biasa, serta transport ws/grpc/tcp.
    private static func parseVless(_ line: String, sourceID: String) -> ProxyNode? {
        guard let comps = URLComponents(string: line),
              let rawHost = comps.host, Validators.isValidHost(bareHost(rawHost)),
              let port = comps.port, Validators.isValidPort(port) else { return nil }
        // UUID kadang percent-encoded; sebagian link membungkusnya base64.
        var uuid = comps.user?.removingPercentEncoding ?? comps.user
        if let cur = uuid, Base64Detector.looksLikeBase64(cur),
           let data = Base64Detector.decodeTolerant(cur),
           let decoded = String(data: data, encoding: .utf8),
           !decoded.contains(":"), decoded.count == 36 {
            uuid = decoded
        }
        guard let id = uuid, !id.isEmpty else { return nil }
        // Kurung IPv6 dilepas (alasan sama seperti trojan di atas).
        let host = bareHost(rawHost)

        let q = comps.queryItems ?? []
        func qq(_ k: String) -> String? { q.first(where: { $0.name.lowercased() == k })?.value }
        let security = (qq("security") ?? "none").lowercased()
        let typeStr = (qq("type") ?? "tcp").lowercased()
        let transport: Transport = typeStr == "ws" ? .ws : typeStr == "grpc" ? .grpc
            : (typeStr == "h2" || typeStr == "http") ? .http : .tcp
        let isReality = security == "reality"
        // D91: `alpn` WAJIB diteruskan. Tanpa itu sing-box memakai default
        // miliknya, dan server yang hanya menerima `h2` akan menolak koneksi
        // padahal link-nya sendiri sudah benar.
        let alpn = (qq("alpn") ?? "").split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let tls = TLSOptions(
            enabled: isReality || security == "tls",
            sni: qq("sni") ?? qq("host") ?? host,
            allowInsecure: (qq("allowinsecure") ?? qq("insecure") ?? "0") == "1",
            realityPublicKey: qq("pbk"),
            realityShortId: qq("sid"),
            fingerprint: qq("fp"),
            alpn: alpn.isEmpty ? nil : alpn
        )
        // REALITY tanpa public key tidak akan pernah bisa dipakai.
        if isReality && !tls.isReality { return nil }
        let name = comps.fragment?.removingPercentEncoding ?? "\(host):\(port)"
        let flow = qq("flow")
        // D91 — BUG YANG BIKIN NODE HILANG SECARA DIAM-DIAM: untuk gRPC,
        // nama service TIDAK ADA di `path`, tapi di query `serviceName`. Versi
        // lama hanya membaca `path`, jadi `transportPath` tetap `nil` dan
        // config yang dihasilkan memuat `"service_name": ""` — node itu
        // dijamin ditolak saat connect, sementara di Clash FX happily jalan.
        // Feed openproxylist sendiri banyak memakai `type=grpc&serviceName=…`.
        let path = qq("path")
        let serviceName = qq("servicename") ?? qq("service_name")
        let transportPath: String? = transport == .grpc ? (serviceName ?? path) : path
        let nodeID = ProxyNode.dedupID(proto: .vless, host: host, port: port, credential: id,
                                       transport: transport, path: transportPath, sni: tls.sni,
                                       transportHost: qq("host"), flow: flow,
                                       realityPublicKey: tls.realityPublicKey,
                                       realityShortId: tls.realityShortId)
        return ProxyNode(id: nodeID, name: name.isEmpty ? "\(host):\(port)" : name,
                         proto: .vless, host: host, port: port, credential: id,
                         transport: transport, transportPath: transportPath,
                         transportHost: qq("host"), tls: tls, flow: flow,
                         sourceID: sourceID, countryCode: CountryInfer.resolveSync(name: name, host: host))
    }

    // MARK: - hysteria2://password@host:port?params#nama (alias hy2://)
    private static func parseHysteria2(_ line: String, sourceID: String) -> ProxyNode? {
        // Buang prefiks skema ("hysteria2://" / "hy2://").
        var rest = line
        if let r = rest.range(of: "://") { rest = String(rest[r.upperBound...]) }
        var name = ""
        if let h = rest.firstIndex(of: "#") {
            name = String(rest[rest.index(after: h)...]).removingPercentEncoding ?? ""
            rest = String(rest[..<h])
        }
        // Varian base64: `hysteria2://base64(pwd@host:port)`.
        //
        // BUG LAMA (D61): `guard lastIndex(of: "@")` dijalankan DULU, dan
        // alfabet base64 tidak memuat `@` sama sekali — jadi untuk payload
        // base64, guard itu selalu gagal dan cabang base64 di bawah TIDAK
        // PERNAH dieksekusi. Dukungan yang dikomentari di sini tidak pernah
        // bekerja sama sekali. Urutannya dibalik: coba `@` dulu, kalau tidak
        // ada, baru coba base64.
        var pwd = ""
        var hostPort = ""
        if let at = rest.lastIndex(of: "@") {
            pwd = String(rest[..<at]).removingPercentEncoding ?? String(rest[..<at])
            hostPort = String(rest[rest.index(after: at)...])
        } else if let data = Base64Detector.decodeTolerant(rest),
                  let decoded = String(data: data, encoding: .utf8),
                  let at = decoded.lastIndex(of: "@") {
            pwd = String(decoded[..<at])
            hostPort = String(decoded[decoded.index(after: at)...])
        } else {
            return nil
        }
        var query = ""
        if let qm = hostPort.firstIndex(of: "?") {
            query = String(hostPort[hostPort.index(after: qm)...])
            hostPort = String(hostPort[..<qm])
        }
        guard !pwd.isEmpty else { return nil }
        let pwdFinal = pwd
        // `URLComponents` bukan `split(separator: ":")`: host IPv6
        // (`[2001:db8::1]:443`) terpecah jadi banyak bagian oleh split (D61).
        guard let comps = URLComponents(string: "hysteria2://\(hostPort)"),
              let rawHost = comps.host,
              let port = comps.port, Validators.isValidPort(port) else { return nil }
        let host = bareHost(rawHost)
        guard Validators.isValidHost(host) else { return nil }

        var q: [String: String] = [:]
        for pair in query.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2 else { continue }
            q[kv[0].lowercased()] = kv[1].removingPercentEncoding ?? kv[1]
        }
        let tls = TLSOptions(enabled: true, sni: q["sni"] ?? host,
                             allowInsecure: q["insecure"] == "1" || q["allowinsecure"] == "1")
        let disp = name.isEmpty ? "\(host):\(port)" : name
        let nodeID = ProxyNode.dedupID(proto: .hysteria2, host: host, port: port,
                                       credential: pwdFinal, transport: .tcp,
                                       path: q["obfs-password"], sni: tls.sni)
        return ProxyNode(id: nodeID, name: disp, proto: .hysteria2, host: host, port: port,
                         credential: pwdFinal, transport: .tcp, tls: tls,
                         obfsPassword: q["obfs"] == "salamander" ? q["obfs-password"] : nil,
                         upMbps: q["upmbps"].flatMap(Int.init) ?? q["up"].flatMap(Int.init),
                         downMbps: q["downmbps"].flatMap(Int.init) ?? q["down"].flatMap(Int.init),
                         sourceID: sourceID, countryCode: CountryInfer.resolveSync(name: disp, host: host))
    }

    // MARK: - ss:// SIP002 dan legacy
    private static func parseSS(_ line: String, sourceID: String) -> ProxyNode? {
        var rest = String(line.dropFirst("ss://".count))
        var name = ""
        if let h = rest.firstIndex(of: "#") {
            name = String(rest[rest.index(after: h)...]).removingPercentEncoding ?? ""
            rest = String(rest[..<h])
        }
        // SIP002: base64(method:password)@host:port
        if rest.contains("@") {
            let parts = rest.split(separator: "@", maxSplits: 1).map(String.init)
            guard parts.count == 2,
                  let credData = Base64Detector.decodeTolerant(parts[0]),
                  let cred = String(data: credData, encoding: .utf8),
                  let colon = cred.firstIndex(of: ":") else { return nil }
            let method = String(cred[..<colon]); let password = String(cred[cred.index(after: colon)...])
            guard let comps = URLComponents(string: "ss://\(parts[1])"),
                  let rawHost = comps.host,
                  let port = comps.port, Validators.isValidPort(port) else { return nil }
            let host = bareHost(rawHost)
            guard Validators.isValidHost(host) else { return nil }
            let disp = name.isEmpty ? "\(host):\(port)" : name
            let nodeID = ProxyNode.dedupID(proto: .shadowsocks, host: host, port: port,
                                           credential: password, transport: .tcp, path: nil, sni: nil,
                                           cipher: method)
            return ProxyNode(id: nodeID, name: disp, proto: .shadowsocks, host: host, port: port,
                             credential: password, cipher: method, sourceID: sourceID,
                             countryCode: CountryInfer.resolveSync(name: disp, host: host))
        } else {
            // Legacy: base64(method:password@host:port)
            guard let data = Base64Detector.decodeTolerant(rest),
                  let full = String(data: data, encoding: .utf8) else { return nil }
            // full = method:password@host:port
            guard let at = full.firstIndex(of: "@") else { return nil }
            let credPart = String(full[..<at]); let hostPart = String(full[full.index(after: at)...])
            guard let colon = credPart.firstIndex(of: ":") else { return nil }
            let method = String(credPart[..<colon]); let password = String(credPart[credPart.index(after: colon)...])
            // `split(separator: ":")` tanpa `maxSplits` menolak host IPv6
            // (`[2001:db8::1]:443` jadi 8 potongan). Pakai `URLComponents`,
            // yang sudah dipakai jalur SIP002 di atas dan memang paham IPv6
            // (D61).
            guard let comps = URLComponents(string: "ss://\(hostPart)"),
                  let rawHost = comps.host,
                  let port = comps.port, Validators.isValidPort(port) else { return nil }
            let host = bareHost(rawHost)
            guard Validators.isValidHost(host) else { return nil }
            let disp = name.isEmpty ? "\(host):\(port)" : name
            let nodeID = ProxyNode.dedupID(proto: .shadowsocks, host: host, port: port,
                                           credential: password, transport: .tcp, path: nil, sni: nil,
                                           cipher: method)
            return ProxyNode(id: nodeID, name: disp, proto: .shadowsocks, host: host, port: port,
                             credential: password, cipher: method, sourceID: sourceID,
                             countryCode: CountryInfer.resolveSync(name: disp, host: host))
        }
    }
}
