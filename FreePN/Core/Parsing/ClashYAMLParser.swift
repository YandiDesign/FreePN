import Foundation

/// Parser YAML Clash dengan key `proxies:` (termasuk format provider).
///
/// SENGAJA tanpa pustaka YAML (Yams tidak pernah terpasang sebagai dependency —
/// `#if canImport(Yams)` selalu salah, jadi jalur "fallback" itulah yang
/// sebetulnya jalan di app). Parser ini karena itu harus.handle sendiri tiga
/// gaya penulisan yang sering muncul di feed liar:
///
/// 1. **Flow-map JSON satu baris** — `- {"name":"SS-…","type":"ss",…}`
///    (vzxiaov/free_proxies, banyak provider aggregator). Kunci BERKUTIP dan
///    nilai berisi escape JSON (`\u003e`), jadi harus di-unquote + di-decode.
/// 2. **Flow-map YAML** — `- {name: A, type: vmess, …}` (tanpa kutip).
/// 3. **Blok berindeks** — `- name: A` + `  type: vmess` + `  ws-opts:` lalu
///    anak-anaknya satu indentasi lebih dalam.
public enum ClashYAMLParser {
    public struct Outcome {
        public var nodes: [ProxyNode]
        public var unsupported: Int
        /// D91: entri yang SEHARUSNYA jadi node tapi gagal karena field wajib
        /// kosong / rusak. Sebelumnya `continue` polos tanpa penghitung, jadi
        /// angka di kolom "Keterangan" tidak pernah cocok dengan isi feed —
        /// dan user tidak bisa tahu ada yang hilang.
        public var malformed: Int
    }

    public static func canHandle(_ text: String) -> Bool {
        return text.contains("proxies:")
    }

    public static func parse(text: String, sourceID: String) -> Outcome {
        var nodes: [ProxyNode] = []
        var unsupported = 0
        // D91: dulu semua kegagalan field wajib hanya `continue` polos.
        var malformed = 0
        for e in entries(in: text) {
            let type = (e["type"] as? String ?? "").lowercased()
            guard let proto = NodeProtocol.fromClashType(type) else { unsupported += 1; continue }
            guard let server = e["server"] as? String, Validators.isValidHost(server),
                  let port = asInt(e["port"]), Validators.isValidPort(port)
            else { malformed += 1; continue }
            let name = (e["name"] as? String) ?? "\(server):\(port)"
            let cc = CountryInfer.resolveSync(name: name, host: server)
            // D91: semua key di `entries(in:)` disimpan `.lowercased()`, jadi
            // `e["alterId"]` SELALU nil — `alterId` tidak pernah terbaca sejak
            // dulu. Lookup harus memakai bentuk kecilnya, sama seperti key lain.
            let alterId = asInt(e["alterid"])
            switch proto {
            case .vmess:
                guard let uuid = str(e["uuid"]), !uuid.isEmpty else { malformed += 1; continue }
                let t = transportInfo(e)
                let tls = TLSOptions(enabled: (e["tls"] as? Bool) ?? false,
                                     sni: str(e["servername"]) ?? str(e["sni"]),
                                     allowInsecure: (e["skip-cert-verify"] as? Bool) ?? false)
                nodes.append(ProxyNode(
                    id: ProxyNode.dedupID(proto: .vmess, host: server, port: port, credential: uuid,
                                          transport: t.transport, path: t.path, sni: tls.sni,
                                          transportHost: t.host,
                                          cipher: str(e["cipher"]), alterId: alterId),
                    name: name, proto: .vmess, host: server, port: port, credential: uuid,
                    cipher: str(e["cipher"]), alterId: alterId,
                    transport: t.transport, transportPath: t.path, transportHost: t.host,
                    tls: tls, sourceID: sourceID, countryCode: cc))
            case .trojan:
                guard let pwd = str(e["password"]), !pwd.isEmpty else { malformed += 1; continue }
                let t = transportInfo(e)
                let tls = TLSOptions(enabled: true,
                                     sni: str(e["sni"]) ?? str(e["servername"]) ?? server,
                                     allowInsecure: (e["skip-cert-verify"] as? Bool) ?? false)
                nodes.append(ProxyNode(
                    id: ProxyNode.dedupID(proto: .trojan, host: server, port: port, credential: pwd,
                                          transport: t.transport, path: t.path, sni: tls.sni),
                    name: name, proto: .trojan, host: server, port: port, credential: pwd,
                    transport: t.transport, transportPath: t.path, transportHost: t.host,
                    tls: tls, sourceID: sourceID, countryCode: cc))
            case .shadowsocks:
                guard let pwd = str(e["password"]), !pwd.isEmpty else { malformed += 1; continue }
                nodes.append(ProxyNode(
                    id: ProxyNode.dedupID(proto: .shadowsocks, host: server, port: port, credential: pwd,
                                          transport: .tcp, path: nil, sni: nil,
                                          cipher: str(e["cipher"])),
                    name: name, proto: .shadowsocks, host: server, port: port, credential: pwd,
                    cipher: str(e["cipher"]), sourceID: sourceID, countryCode: cc))
            case .vless:
                guard let uuid = str(e["uuid"]), !uuid.isEmpty else { malformed += 1; continue }
                let t = transportInfo(e)
                let r = e["reality-opts"] as? [String: Any] ?? [:]
                let tls = TLSOptions(enabled: (e["tls"] as? Bool) ?? false,
                                     sni: str(e["servername"]) ?? str(e["sni"]),
                                     allowInsecure: (e["skip-cert-verify"] as? Bool) ?? false,
                                     realityPublicKey: str(r["public-key"]),
                                     realityShortId: str(r["short-id"]),
                                     fingerprint: str(e["client-fingerprint"]))
                nodes.append(ProxyNode(
                    id: ProxyNode.dedupID(proto: .vless, host: server, port: port, credential: uuid,
                                          transport: t.transport, path: t.path, sni: tls.sni,
                                          transportHost: t.host, flow: str(e["flow"]),
                                          realityPublicKey: tls.realityPublicKey,
                                          realityShortId: tls.realityShortId),
                    name: name, proto: .vless, host: server, port: port, credential: uuid,
                    transport: t.transport, transportPath: t.path, transportHost: t.host,
                    tls: tls, flow: str(e["flow"]), sourceID: sourceID, countryCode: cc))
            case .hysteria2:
                guard let pwd = str(e["password"]) ?? str(e["auth"]), !pwd.isEmpty
                else { malformed += 1; continue }
                // Dua gaya penulisan di feed: `obfs: salamander` + `obfs-password`,
                // atau map bersarang `obfs: {type: salamander, password: …}`.
                var obfsPwd: String?
                if let ob = e["obfs"] as? [String: Any],
                   (str(ob["type"]) ?? "").lowercased() == "salamander" {
                    obfsPwd = str(ob["password"])
                } else if (str(e["obfs"]) ?? "").lowercased() == "salamander" {
                    obfsPwd = str(e["obfs-password"])
                }
                let tls = TLSOptions(enabled: true,
                                     sni: str(e["sni"]) ?? str(e["servername"]) ?? server,
                                     allowInsecure: (e["skip-cert-verify"] as? Bool) ?? false)
                nodes.append(ProxyNode(
                    id: ProxyNode.dedupID(proto: .hysteria2, host: server, port: port, credential: pwd,
                                          transport: .tcp, path: obfsPwd, sni: tls.sni),
                    name: name, proto: .hysteria2, host: server, port: port, credential: pwd,
                    transport: .tcp, tls: tls, obfsPassword: obfsPwd,
                    upMbps: asInt(e["up"] ?? e["up-mbps"]),
                    downMbps: asInt(e["down"] ?? e["down-mbps"]),
                    sourceID: sourceID, countryCode: cc))
            case .http, .socks:
                // Proxy HTTP CONNECT / SOCKS5 (bukan VPN modern). Cukup banyak
                // di feed gratis — `ermaozi` punya 210 `http`, dan semuanya
                // sebelumnya dibuang sebagai "tidak didukung" padahal
                // sing-box 1.11+ menerimanya sebagai outbound `http`/`socks`.
                //
                // Bentuk kredensial: "username:password", atau password saja
                // kalau feed tidak menyebut `username`. Kosong = tanpa auth.
                let cred = Self.plainProxyCredential(e)
                let tls = TLSOptions(enabled: (e["tls"] as? Bool) ?? false,
                                     sni: str(e["sni"]) ?? str(e["servername"]) ?? server,
                                     allowInsecure: (e["skip-cert-verify"] as? Bool) ?? false)
                nodes.append(ProxyNode(
                    id: ProxyNode.dedupID(proto: proto, host: server, port: port, credential: cred,
                                          transport: .tcp, path: nil, sni: tls.sni),
                    name: name, proto: proto, host: server, port: port, credential: cred,
                    transport: .tcp, tls: tls, sourceID: sourceID, countryCode: cc))
            }
        }
        return Outcome(nodes: nodes, unsupported: unsupported, malformed: malformed)
    }

    /// Kredensial proxy HTTP/SOCKS: "username:password", atau `password`
    /// saja, atau kosong (tanpa autentikasi).
    ///
    /// Disimpan dalam satu `String` karena `ProxyNode` hanya punya satu slot
    /// `credential` — sama seperti cara Shadowsocks menyimpan
    /// "method:password". `SingBoxConfigBuilder` yang mengurai kembali.
    private static func plainProxyCredential(_ e: [String: Any]) -> String {
        let user = (str(e["username"]) ?? "").trimmingCharacters(in: .whitespaces)
        let pass = (str(e["password"]) ?? "").trimmingCharacters(in: .whitespaces)
        if !user.isEmpty && !pass.isEmpty { return "\(user):\(pass)" }
        if !pass.isEmpty { return pass }
        return user   // bisa kosong = tanpa autentikasi
    }

    // MARK: - Bentuk entri

    private struct TransportInfo {
        var transport: Transport = .tcp
        var path: String?
        var host: String?
    }

    private static func transportInfo(_ e: [String: Any]) -> TransportInfo {
        var out = TransportInfo()
        let net = (str(e["network"]) ?? "tcp").lowercased()
        out.transport = net == "ws" ? .ws : net == "grpc" ? .grpc
            : (net == "h2" || net == "http") ? .http : .tcp
        if let ws = e["ws-opts"] as? [String: Any] {
            out.path = str(ws["path"])
            out.host = headerHost(ws["headers"] as? [String: Any]) ?? str(e["servername"])
        }
        if let g = e["grpc-opts"] as? [String: Any] { out.path = str(g["grpc-service-name"]) }
        if let h = e["h2-opts"] as? [String: Any] {
            out.path = str(h["path"])
            out.host = headerHost(h["headers"] as? [String: Any])
        }
        return out
    }

    /// Feed tidak konsisten: satu menulis `Host`, yang lain `HOST`. Ambil
    /// apa adanya dengan comparisonsi case-insensitive.
    private static func headerHost(_ headers: [String: Any]?) -> String? {
        guard let headers else { return nil }
        for (k, v) in headers where k.lowercased() == "host" {
            if let s = str(v) { return s }
        }
        return nil
    }

    // MARK: - Skalar

/// D48 — pemecah baris.
        ///
        /// PENTING: `\r\n` adalah SATU grapheme cluster di Swift, jadi
        /// `split(separator: "\n")` TIDAK memotong akhir baris Windows —
        /// seluruh berkas jadi satu baris dan parse gagal total. Versi lama
        /// memakai `components(separatedBy: .newlines)` yang mencocokkan
        /// CharacterSet di level unicode scalar, jadi ini benar secara sengaja.
        ///
        /// Feed Linux (LF saja) tidak kena biaya apa pun: normalisasi hanya
    /// jalan kalau `\r\n` benar-benar ada. `CR` yatim yang tersisa dipangkas
    /// `fastTrim`.
    private static func lines(of text: String) -> [Substring] {
        let normalized = text.contains("\r\n")
            ? text.replacingOccurrences(of: "\r\n", with: "\n")
            : text
        return normalized.split(separator: "\n", omittingEmptySubsequences: false)
    }

    /// D48 — pemangkas ruang putih SUPER CEPAT.
    ///
    /// `trimmingCharacters(in: .whitespaces)` memverifikasi lewat
    /// `NSCharacterSet` dari Foundation; dipanggil puluhan kali per baris, dan
    /// pada feed 10 MB itu jadi salah satu hotspot terbesar di refresh. Versi
    /// ini cuma menyisir `String.Index` untuk space/tab/CR/LF. CR ikut
    /// dipangkas supaya berkas Windows (CRLF) tetap terpotong dengan benar.
    @inline(__always)
    private static func isBlank(_ u: Unicode.Scalar) -> Bool {
        u == " " || u == "\t" || u == "\r" || u == "\n"
    }

    private static func fastTrim(_ s: String) -> String {
        let sc = s.unicodeScalars
        var start = s.startIndex
        var end = s.endIndex
        while start < end, isBlank(sc[start]) { start = sc.index(after: start) }
        while start < end {
            let prev = sc.index(before: end)
            if isBlank(sc[prev]) { end = prev } else { break }
        }
        return start == s.startIndex && end == s.endIndex ? s : String(s[start..<end])
    }

    /// Lebar indentasi dalam BYTE UTF-8, bukan `Character` — indentasi YAML
    /// hanya spasi/tab ASCII, jadi hasilnya identik tapi tanpa grapheme
    /// breaking per karakter.
    private static func indentWidth(_ line: Substring) -> Int {
        var n = 0
        for b in line.utf8 {
            if b == 0x20 || b == 0x09 { n += 1 } else { break }
        }
        return n
    }

    private static func str(_ v: Any?) -> String? {
        if let s = v as? String { return s }
        if let i = v as? Int { return String(i) }
        return nil
    }

    private static func asInt(_ v: Any?) -> Int? {
        if let i = v as? Int { return i }
        if let d = v as? Double { return Int(d) }
        if let s = v as? String { return Int(s) }
        return nil
    }

    /// Lepas kutip (' atau ") kalau ada, lalu decode escape JSON/YAML.
    private static func scalar(_ raw: String) -> Any {
        var v = fastTrim(raw)
        if v.count >= 2 {
            // Tanpa force-unwrap: `first`/`last` pada `Character` bisa gagal
            // bila view Unicode berubah di tengah, dan `!` di sini berarti
            // crash, bukan fallback.
            if let first = v.first, let last = v.last,
               (first == "\"" && last == "\"") || (first == "'" && last == "'") {
                v = String(v.dropFirst().dropLast())
                if first == "\"" { v = decodeEscapes(v) }
            }
        }
        // Hanya scalar yang PENDEK dan non-ASCII yang perlu dicocokkan
        // case-insensitive. Scalar panjang (nama node, password) tidak akan
        // pernah bernilai true/false/null, jadi `lowercased()` di sana
        // berarti ratusan ribu alokasi sia-sia untuk feed 30.000 node (D61).
        if v.utf8.count <= 5, !v.isEmpty {
            switch v.lowercased() {
            case "true", "yes": return true
            case "false", "no": return false
            case "null", "~", "": return NSNull()
            default: break
            }
        } else if v == "~" {
            return NSNull()
        }
        if let i = Int(v) { return i }
        return v
    }

    /// `\u003e` → `>`, `\n`, `\"`, `\\`, dan pasangan surrogate.
    private static func decodeEscapes(_ s: String) -> String {
        guard s.contains("\\") else { return s }
        var out = ""
        var it = Array(s)
        var i = 0
        while i < it.count {
            guard it[i] == "\\", i + 1 < it.count else {
                out.append(it[i]); i += 1; continue
            }
            let n = it[i + 1]
            switch n {
            case "u":
                guard i + 5 < it.count,
                      let code = UInt32(String(it[(i + 2)...(i + 5)]), radix: 16)
                else { out.append(n); i += 2; continue }
                var scalarValue = code
                // Pasangan surrogate: \uD83D\uDE00 → satu emoji.
                if code >= 0xD800 && code <= 0xDBFF, i + 11 < it.count,
                   it[i + 6] == "\\", it[i + 7] == "u",
                   let low = UInt32(String(it[(i + 8)...(i + 11)]), radix: 16),
                   low >= 0xDC00, low <= 0xDFFF {
                    scalarValue = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                    i += 12
                } else {
                    i += 6
                }
                if let u = Unicode.Scalar(scalarValue) { out.append(Character(u)) }
            case "n": out.append("\n"); i += 2
            case "r": out.append("\r"); i += 2
            case "t": out.append("\t"); i += 2
            case "b": out.append("\u{08}"); i += 2
            case "f": out.append("\u{0C}"); i += 2
            case "\\", "\"", "/", "'": out.append(n); i += 2
            default: out.append(n); i += 2
            }
        }
        return out
    }

    // MARK: - Pemecah baris & map

    /// Pecah `a: 1, b: {c: 2}` tanpa memotong koma di dalam `{...}`/`[...]`.
    private static func splitTopLevel(_ s: String) -> [String] {
        var parts: [String] = []
        var depth = 0
        var cur = ""
        var quote: Character?
        for ch in s {
            if let q = quote {
                cur.append(ch)
                if ch == q { quote = nil }
                continue
            }
            switch ch {
            case "\"", "'": quote = ch; cur.append(ch)
            case "{", "[": depth += 1; cur.append(ch)
            case "}", "]": depth -= 1; cur.append(ch)
            case "," where depth == 0: parts.append(cur); cur = ""
            default: cur.append(ch)
            }
        }
        if !fastTrim(cur).isEmpty { parts.append(cur) }
        return parts.map { fastTrim($0) }.filter { !$0.isEmpty }
    }

    /// Ambil `key: value` pada tanda `:` pertama di luar kurung/kutip.
    private static func splitKeyValue(_ s: String) -> (key: String?, value: String?) {
        var depth = 0
        var quote: Character?
        for (i, ch) in s.enumerated() {
            if let q = quote {
                if ch == q { quote = nil }
                continue
            }
            switch ch {
            case "\"", "'": quote = ch
            case "{", "[": depth += 1
            case "}", "]": depth -= 1
            case ":" where depth == 0:
                let k = fastTrim(String(s[s.startIndex..<s.index(s.startIndex, offsetBy: i)]))
                let v = fastTrim(String(s[s.index(s.startIndex, offsetBy: i + 1)...]))
                return (k.isEmpty ? nil : k, v)
            default: break
            }
        }
        return (nil, nil)
    }

    private static func value(_ raw: String) -> Any {
        let v = fastTrim(raw)
        if v.hasPrefix("{"), v.hasSuffix("}"), v.count > 2 {
            return flowMap(String(v.dropFirst().dropLast()))
        }
        if v.hasPrefix("["), v.hasSuffix("]"), v.count > 2 {
            return splitTopLevel(String(v.dropFirst().dropLast())).map { scalar($0) }
        }
        return scalar(v)
    }

    private static func flowMap(_ inner: String) -> [String: Any] {
        var out: [String: Any] = [:]
        for part in splitTopLevel(inner) {
            let kv = splitKeyValue(part)
            guard let k = kv.key, let v = kv.value else { continue }
            // Kunci JSON BERKUTIP: `"type"` → `type`.
            out[unquote(k).lowercased()] = value(v)
        }
        return out
    }

    private static func unquote(_ s: String) -> String {
        var v = fastTrim(s)
        if v.count >= 2 {
            let f = v.first!, l = v.last!
            if (f == "\"" && l == "\"") || (f == "'" && l == "'") { v = String(v.dropFirst().dropLast()) }
        }
        return v
    }

    /// Kumpulkan seluruh entri di bawah `proxies:`.
    ///
    /// Baris di luar `proxies:` (mis. `proxy-groups:` dengan `type: select`)
    /// sengaja DIABAIKAN — kalau ikut diparse, tiap group akan terhitung
    /// sebagai "protokol tidak didukung" dan mengotori angka di UI.
    private static func entries(in text: String) -> [[String: Any]] {
        var out: [[String: Any]] = []
        var current: [String: Any] = [:]
        var inProxies = true          // belum ada key top-level → anggap proxies
        var parentKey: String? = nil  // blok anak yang sedang diisi (mis. "reality-opts")
        var parentIndent = 0

        func flush() {
            if !current.isEmpty { out.append(current) }
            current = [:]
        }

        for raw in lines(of: text) {
            let trimmed = fastTrim(String(raw))
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let indent = indentWidth(raw)

            // Key top-level baru → keluar dari seksi proxies.
            if indent == 0, !trimmed.hasPrefix("- ") {
                let kv = splitKeyValue(trimmed)
                flush()
                parentKey = nil
                inProxies = (kv.key ?? "").lowercased() == "proxies"
                if inProxies, let v = kv.value, !v.isEmpty {
                    // Bentuk inline: `proxies: [{...}, {...}]`
                    if v.hasPrefix("["), v.hasSuffix("]"), v.count > 2 {
                        for part in splitTopLevel(String(v.dropFirst().dropLast())) {
                            if part.hasPrefix("{") { out.append(flowMap(String(part.dropFirst().dropLast()))) }
                        }
                    }
                }
                continue
            }
            guard inProxies else { continue }

            var body = trimmed
            if body == "-" { flush(); parentKey = nil; continue }
            if body.hasPrefix("- ") { flush(); parentKey = nil; body = String(body.dropFirst(2)) }

            // Baris anak dari blok nilai kosong (`reality-opts:` lalu isinya).
            if let pk = parentKey, indent > parentIndent, !trimmed.hasPrefix("- ") {
                let kv = splitKeyValue(body)
                if let k = kv.key, let v = kv.value {
                    var block = (current[pk] as? [String: Any]) ?? [:]
                    block[unquote(k).lowercased()] = value(v)
                    current[pk] = block
                }
                continue
            }
            parentKey = nil

            // `- {…}` : satu baris = satu entri.
            if body.hasPrefix("{"), body.hasSuffix("}"), body.count > 2 {
                current = flowMap(String(body.dropFirst().dropLast()))
                continue
            }
            let kv = splitKeyValue(body)
            guard let k = kv.key, let v = kv.value else { continue }
            let key = unquote(k).lowercased()
            if v.isEmpty {
                // Nilai kosong → anak-anaknya menyusul (satu indentasi dalam).
                parentKey = key
                parentIndent = indent
                current[key] = [String: Any]()
            } else {
                current[key] = value(v)
            }
        }
        flush()
        return out
    }
}