import Foundation

/// Isian form untuk satu node manual (D93).
///
/// Terpisah dari `ProxyNode` dengan sengaja: `ProxyNode` adalah hasil akhir
/// yang sudah dinormalisasi (id ter-hash, negara ditebak, dedup key lengkap),
/// sedangkan yang di sini adalah string mentah dari kolom form. Menyamakannya
/// berarti form harus ikut mengisi `id` dan `countryCode` — dua hal yang tidak
/// pernah diketik orang.
public struct ManualNodeDraft {
    public var name: String = ""
    public var proto: NodeProtocol = .vless
    public var host: String = ""
    public var port: String = ""
    /// UUID (vmess/vless) atau password (trojan/hysteria2) atau
    /// `method:password` (shadowsocks) atau `user:pass` (http/socks).
    public var credential: String = ""
    /// Shadowsocks saja.
    public var cipher: String = "aes-256-gcm"

    public var transport: Transport = .tcp
    /// Path WebSocket, atau nama service gRPC.
    public var path: String = ""
    /// Header `Host:` untuk WebSocket.
    public var transportHost: String = ""

    public var tlsEnabled: Bool = true
    public var sni: String = ""
    public var allowInsecure: Bool = false
    public var alpn: String = ""

    public var realityPublicKey: String = ""
    public var realityShortId: String = ""
    public var fingerprint: String = "chrome"
    /// VLESS: `xtls-rprx-vision`.
    public var flow: String = ""

    /// Hysteria2: password obfuscation `salamander`.
    public var obfsPassword: String = ""
    public var upMbps: String = ""
    public var downMbps: String = ""

    public init() {}

    /// Isi ulang draft dari node yang sudah ada, supaya form edit membuka dengan
    /// nilai yang sama persis — bukan form kosong yang membuat user mengetik
    /// ulang kredensial yang panjang dan riskannya salah ketik satu huruf.
    ///
    /// Kebalikannya (lupa satu field = data hilang diam-diam) dicegah oleh
    /// `ManualNodeEditTests`, yang membandingkan bolak-balik untuk tiap protokol.
    public init(node: ProxyNode) {
        self.name = node.name
        self.proto = node.proto
        self.host = node.host
        self.port = String(node.port)
        self.credential = node.credential
        self.cipher = node.cipher ?? "aes-256-gcm"
        self.transport = node.transport
        self.path = node.transportPath ?? ""
        self.transportHost = node.transportHost ?? ""
        self.tlsEnabled = node.tls?.enabled ?? false
        self.sni = node.tls?.sni ?? ""
        self.allowInsecure = node.tls?.allowInsecure ?? false
        self.alpn = (node.tls?.alpn ?? []).joined(separator: ",")
        self.realityPublicKey = node.tls?.realityPublicKey ?? ""
        self.realityShortId = node.tls?.realityShortId ?? ""
        self.fingerprint = node.tls?.fingerprint ?? "chrome"
        self.flow = node.flow ?? ""
        self.obfsPassword = node.obfsPassword ?? ""
        // Mbps disimpan sebagai String; `nil` berarti "pakai default core" dan
        // itu TIDAK sama dengan "0". Jadi kosong, bukan "0".
        self.upMbps = node.upMbps.map(String.init) ?? ""
        self.downMbps = node.downMbps.map(String.init) ?? ""
    }

    /// Hasil build + alasan kalau gagal.
    public enum BuildResult {
        case ok(ProxyNode)
        case failed([String])
    }

    /// Bangun `ProxyNode` dari isian form.
    ///
    /// `sourceID` dan `id` ditangani pemanggil supaya builder ini tetap murni
    /// dan bisa diuji tanpa actor.
    public func build(sourceID: String) -> BuildResult {
        var problems: [String] = []

        let h = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Validators.isValidHost(h), !h.isEmpty else {
            problems.append(L10n.string("manual_err_host"))
            return .failed(problems)
        }
        guard let p = Int(port.trimmingCharacters(in: .whitespacesAndNewlines)),
              Validators.isValidPort(p) else {
            problems.append(L10n.string("manual_err_port"))
            return .failed(problems)
        }

        let cred = credential.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cred.isEmpty else {
            problems.append(L10n.string("manual_err_credential"))
            return .failed(problems)
        }

        // `resolvedCipher`, bukan `cipher`: nama yang sama dengan properti draft
        // akan membayangi nilainya sendiri, dan baris pembersih yang harusnya
        // membaca kolom cipher malah membaca variabel yang belum diisi.
        var resolvedCipher: String? = nil
        var effectiveCred = cred
        switch proto {
        case .shadowsocks:
            let c = self.cipher.trimmingCharacters(in: .whitespacesAndNewlines)
            guard Validators.shadowsocksMethods.contains(c.lowercased()) else {
                problems.append(L10n.string("manual_err_cipher"))
                return .failed(problems)
            }
            resolvedCipher = c
            // Form menerima `method:password` (bentuk paling umum di luar
            // negeri) dan juga `password` saja kalau method di kolom cipher.
            if !cred.contains(":") {
                effectiveCred = "\(c):\(cred)"
            }
        case .http, .socks:
            // `user:pass` atau `pass` saja. Kosong sudah ditolak di atas.
            break
        default:
            break
        }

        let pbk = realityPublicKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let sid = realityShortId.trimmingCharacters(in: .whitespacesAndNewlines)
        let useReality = !pbk.isEmpty
        // REALITY aktif kalau ada public key. Tanpa `pbk`, flag TLS biasa akan
        // membuat config yang ditolak core — lebih baik bilang terus terang.
        let tlsOn = useReality || tlsEnabled
        let tls = TLSOptions(
            enabled: tlsOn,
            sni: clean(sni).isEmpty ? h : clean(sni),
            allowInsecure: allowInsecure,
            realityPublicKey: pbk.isEmpty ? nil : pbk,
            realityShortId: sid.isEmpty ? nil : sid,
            fingerprint: clean(fingerprint),
            alpn: splitALPN(alpn))

        let cleanPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let tHost = transportHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let flowVal = flow.trimmingCharacters(in: .whitespacesAndNewlines)
        let nodeID = ProxyNode.dedupID(
            proto: proto, host: h, port: p, credential: effectiveCred,
            transport: transport,
            path: cleanPath.isEmpty ? nil : cleanPath,
            sni: tls.sni, transportHost: tHost.isEmpty ? nil : tHost,
            flow: flowVal.isEmpty ? nil : flowVal,
            realityPublicKey: pbk.isEmpty ? nil : pbk,
            realityShortId: sid.isEmpty ? nil : sid,
            cipher: resolvedCipher)

        let obfs = obfsPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        let n = ProxyNode(
            id: nodeID,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "\(h):\(p)" :
                name.trimmingCharacters(in: .whitespacesAndNewlines),
            proto: proto, host: h, port: p, credential: effectiveCred,
            cipher: resolvedCipher,
            transport: transport,
            transportPath: cleanPath.isEmpty ? nil : cleanPath,
            transportHost: tHost.isEmpty ? nil : tHost,
            tls: tlsOn ? tls : nil,
            flow: flowVal.isEmpty ? nil : flowVal,
            obfsPassword: obfs.isEmpty ? nil : obfs,
            upMbps: Int(upMbps), downMbps: Int(downMbps),
            sourceID: sourceID,
            countryCode: CountryInfer.resolveSync(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines), host: h))

        // Lapis-1 penyaringan yang sama dengan parser feed, supaya form tidak
        // bisa membuat node yang core pastikan tolak.
        if NodeDeduper.keepingUsable([n]).isEmpty {
            problems.append(L10n.string("manual_err_unusable"))
            return .failed(problems)
        }
        return .ok(n)
    }

    private func clean(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func splitALPN(_ raw: String) -> [String]? {
        let parts = raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts
    }

    /// Protocol mana saja yang punya kolom-kolom form yang relevan.
    ///
    /// UI memakainya untuk menyembunyikan field yang tidak berlaku — formulario
    /// yang menampilkan "reality public key" untuk Shadowsocks terlihat seperti
    /// tidak tahu apa yang ia buat.
    public static func supportsTLS(_ p: NodeProtocol) -> Bool {
        switch p {
        case .trojan, .vmess, .vless: return true
        case .shadowsocks, .hysteria2, .http, .socks: return false
        }
    }

    public static func supportsTransport(_ p: NodeProtocol) -> Bool {
        switch p {
        case .vmess, .vless: return true
        case .trojan, .shadowsocks, .hysteria2, .http, .socks: return false
        }
    }

    public static func supportsReality(_ p: NodeProtocol) -> Bool { p == .vless }
    public static func supportsFlow(_ p: NodeProtocol) -> Bool { p == .vless }
    public static func supportsCipher(_ p: NodeProtocol) -> Bool { p == .shadowsocks }
    public static func supportsHysteria2(_ p: NodeProtocol) -> Bool { p == .hysteria2 }
}

public enum ManualNodeParser {
    /// Hasil mengurai satu share-link manual.
    public enum Result: Equatable {
        /// Satu node valid.
        case single(ProxyNode)
        /// Lebih dari satu — user menempelkan banyak link sekaligus.
        case many([ProxyNode])
        case failed(String)
    }

    /// Terjemahkan teks yang di-paste user menjadi node.
    ///
    /// Menghormati jalur base64 dan daftar multi-baris, jadi user boleh
    /// menempelkan 20 link sekaligus dari catatan atau pesan — bukan satu-satu.
    /// Format yang dipakai parser feed (`ShareLinkParser`) yang sama dipakai di
    /// sini, jadi apa yang berhasil dibaca dari tautan manual dan dari feed
    /// selalu sama.
    public static func parse(_ text: String, sourceID: String) -> Result {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return .failed(L10n.string("manual_err_empty")) }

        let out = ShareLinkParser.parse(text: t, sourceID: sourceID)
        guard !out.nodes.isEmpty else {
            if out.malformed > 0 {
                return .failed(L10n.formatted("manual_err_malformed", out.malformed))
            }
            return .failed(L10n.string("manual_err_unparsable"))
        }
        let usable = NodeDeduper.keepingUsable(out.nodes)
        guard !usable.isEmpty else {
            return .failed(L10n.string("manual_err_unusable"))
        }
        return usable.count == 1 ? .single(usable[0]) : .many(usable)
    }
}