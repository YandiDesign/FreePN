import Foundation

public enum NodeProtocol: String, Codable, CaseIterable {
    case trojan
    case vmess
    case shadowsocks
    /// VLESS + REALITY — protokol yang paling dominan di feed gratis sekarang.
    case vless
    /// Hysteria2 (QUIC/UDP).
    case hysteria2
    /// HTTP CONNECT proxy. Bukan VPN modern, tapi feed gratis memakainya
    /// cukup banyak dan sing-box mendukungnya sebagai outbound `http`.
    case http
    /// SOCKS5 proxy (dengan atau tanpa autentikasi).
    case socks

    public var badgeTitle: String {
        switch self {
        case .trojan: return "Trojan"
        case .vmess: return "VMess"
        case .shadowsocks: return "SS"
        case .vless: return "VLESS"
        case .hysteria2: return "HY2"
        case .http: return "HTTP"
        case .socks: return "SOCKS"
        }
    }

    /// Untuk Clash YAML `type:`.
    public static func fromClashType(_ s: String) -> NodeProtocol? {
        switch s.lowercased() {
        case "trojan": return .trojan
        case "vmess": return .vmess
        case "ss", "shadowsocks": return .shadowsocks
        case "vless": return .vless
        case "hysteria2", "hy2": return .hysteria2
        case "http": return .http
        case "socks", "socks5": return .socks
        default: return nil
        }
    }
}

public enum Transport: String, Codable {
    case tcp, ws, grpc, http
}

public struct TLSOptions: Codable, Hashable {
    public var enabled: Bool
    public var sni: String?
    public var allowInsecure: Bool
    /// REALITY (VLESS): public key dari server. Wajib kalau terisi.
    public var realityPublicKey: String?
    /// REALITY: short ID (hex, biasanya 0-16 karakter).
    public var realityShortId: String?
    /// uTLS fingerprint (chrome/firefox/safari/ios…) — wajib untuk REALITY.
    public var fingerprint: String?
    /// D91: ALPN yang ditawarkan ke server. Kosong = biarkan default sing-box.
    ///
    /// Tidak ada field ini sebelumnya, jadi link yang menentukan ALPN-nya
    /// (`alpn=h2`, `alpn=h3`) datang ke sini sama sekali tidak terbaca.
    public var alpn: [String]?

    public init(enabled: Bool = false, sni: String? = nil, allowInsecure: Bool = false,
                realityPublicKey: String? = nil, realityShortId: String? = nil,
                fingerprint: String? = nil, alpn: [String]? = nil) {
        self.enabled = enabled
        self.sni = sni
        self.allowInsecure = allowInsecure
        self.realityPublicKey = realityPublicKey
        self.realityShortId = realityShortId
        self.fingerprint = fingerprint
        self.alpn = alpn
    }

    /// Decoder toleran (D61).
    ///
    /// `Codable` hasil sintesis berarti satu field WAJIB yang baru ditambah
    /// di versi berikutnya membuat seluruh `nodes.json` lama tak terbaca. File
    /// itu yang paling besar dan paling berharga di app: user membuka app ke
    /// daftar server KOSONG, tanpa pesan error dan tanpa cadangan. Decoder
    /// eksplisit dengan default untuk setiap field menutup kelas bug itu.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        sni = try c.decodeIfPresent(String.self, forKey: .sni)
        allowInsecure = try c.decodeIfPresent(Bool.self, forKey: .allowInsecure) ?? false
        realityPublicKey = try c.decodeIfPresent(String.self, forKey: .realityPublicKey)
        realityShortId = try c.decodeIfPresent(String.self, forKey: .realityShortId)
        fingerprint = try c.decodeIfPresent(String.self, forKey: .fingerprint)
        alpn = try c.decodeIfPresent([String].self, forKey: .alpn)
    }

    /// TRUE kalau opsi ini memakai REALITY (bukan TLS biasa).
    public var isReality: Bool {
        enabled && !(realityPublicKey ?? "").isEmpty
    }
}

public struct ProxyNode: Identifiable, Codable, Hashable {
    public var id: String
    public var name: String
    public var proto: NodeProtocol
    public var host: String
    public var port: Int
    public var credential: String
    public var cipher: String?
    public var alterId: Int?
    public var transport: Transport
    public var transportPath: String?
    public var transportHost: String?
    public var tls: TLSOptions?
    /// VLESS: `xtls-rprx-vision` (wajib untuk flow REALITY + TCP).
    public var flow: String?
    /// Hysteria2: password obfs salamander.
    public var obfsPassword: String?
    /// Hysteria2: bandwidth (Mbps). Kosong = biarkan default sing-box.
    public var upMbps: Int?
    public var downMbps: Int?
    public var sourceID: String
    public var countryCode: String?

    public init(id: String = UUID().uuidString, name: String, proto: NodeProtocol,
                host: String, port: Int, credential: String, cipher: String? = nil,
                alterId: Int? = nil, transport: Transport = .tcp,
                transportPath: String? = nil, transportHost: String? = nil,
                tls: TLSOptions? = nil, flow: String? = nil, obfsPassword: String? = nil,
                upMbps: Int? = nil, downMbps: Int? = nil,
                sourceID: String = "", countryCode: String? = nil) {
        self.id = id; self.name = name; self.proto = proto
        self.host = host; self.port = port; self.credential = credential
        self.cipher = cipher; self.alterId = alterId; self.transport = transport
        self.transportPath = transportPath; self.transportHost = transportHost
        self.tls = tls; self.flow = flow; self.obfsPassword = obfsPassword
        self.upMbps = upMbps; self.downMbps = downMbps
        self.sourceID = sourceID; self.countryCode = countryCode
    }

    /// Decoder toleran (D61) — alasan yang sama seperti `TLSOptions`.
    ///
    /// Field yang tidak ada di `nodes.json` versi lama mendapat nilai
    /// default; field yang ADA tapi tak dikenal (mis. enum `proto` baru di
    /// versi lain) memakai `try? decode` agar tidak membuat seluruh file
    /// gagal decode dan daftar server user jadi kosong tanpa jejak.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // `id` di-recompute bila hilang, tapi kalau ada HARUS dipakai — ia
        // kunci `ping` dan `favorites`, jadi mengubahnya akan melumpuhkan
        // seluruh verdict lama untuk node itu.
        let decodedID = try? c.decode(String.self, forKey: .id)
        let protoDecoded = try? c.decode(NodeProtocol.self, forKey: .proto)
        let name = (try? c.decode(String.self, forKey: .name)) ?? "?"
        let host = (try? c.decode(String.self, forKey: .host)) ?? ""
        let port = (try? c.decode(Int.self, forKey: .port)) ?? 0
        let credential = (try? c.decode(String.self, forKey: .credential)) ?? ""
        self.id = decodedID ?? ProxyNode.dedupID(
            proto: protoDecoded ?? .vmess, host: host, port: port,
            credential: credential, transport: .tcp, path: nil, sni: nil)
        self.proto = protoDecoded ?? .vmess
        self.name = name
        self.host = host
        self.port = port
        self.credential = credential
        cipher = try c.decodeIfPresent(String.self, forKey: .cipher)
        alterId = try c.decodeIfPresent(Int.self, forKey: .alterId)
        transport = (try? c.decode(Transport.self, forKey: .transport)) ?? .tcp
        transportPath = try c.decodeIfPresent(String.self, forKey: .transportPath)
        transportHost = try c.decodeIfPresent(String.self, forKey: .transportHost)
        tls = try c.decodeIfPresent(TLSOptions.self, forKey: .tls)
        flow = try c.decodeIfPresent(String.self, forKey: .flow)
        obfsPassword = try c.decodeIfPresent(String.self, forKey: .obfsPassword)
        upMbps = try c.decodeIfPresent(Int.self, forKey: .upMbps)
        downMbps = try c.decodeIfPresent(Int.self, forKey: .downMbps)
        sourceID = (try? c.decode(String.self, forKey: .sourceID)) ?? ""
        countryCode = try c.decodeIfPresent(String.self, forKey: .countryCode)
    }

    // MARK: - Endpoint (tampilan)

    /// Alamat node seperti yang ditampilkan di kolom IP.
    ///
    /// Tiap akun dari feed subscription punya alamatnya sendiri, jadi ini cara
    /// tercepat user memeriksa "node ini nyasar ke mana" tanpa membuka
    /// share-link. Port tidak selalu relevan — beberapa host cuma punya satu
    /// port — jadi user yang memutuskan lewat `AppSettings.showNodePort`.
    ///
    /// Murni & nonisolated supaya bisa diuji tanpa actor.
    public func endpoint(includePort: Bool) -> String {
        includePort ? "\(host):\(port)" : host
    }

    /// Hash dedup.
    ///
    /// D91 — field pembeda yang dulu TIDAK ikut dihitung, dan itu membuat
    /// akun berbeda untuk dianggap satu:
    ///
    /// - `transportHost` (header `Host:` untuk WebSocket): dua link dengan
    ///   host/port/uuid sama tapi header Host berbeda menunjuk DUA rute CDN
    ///   yang berbeda. Diverifikasi langsung di feed openproxylist: dua link
    ///   `kclx.eu.org:443` dengan uuid sama diringkas jadi satu node.
    /// - `flow` (`xtls-rprx-vision`): tanpa ini, node bertflow vision bisa
    ///   hilang digantikan node tanpa flow pada host/port/uuid yang sama.
    /// - `realityPublicKey` / `realityShortId`: `pbk` berbeda menunjuk
    ///   instance REALITY yang benar-benar berbeda.
    /// - `cipher` / `alterId`: SS dengan cipher berbeda pada host/port/sandi
    ///   sama adalah akun yang berbeda.
    ///
    /// PENTING — kompatibilitas: field baru itu hanya masuk hash kalau
    /// terisi. Node yang tidak punya satellite field apa pun menghasilkan
    /// string hash yang **persis sama** dengan versi lama, sehingga
    /// `favorites.json` milik user yang menyimpan node id TIDAK ikut rusak.
    /// Hanya node yang memang sebelumnya salah tertukar yang mendapat id baru
    /// — dan pada node itu pun id lama sudah menunjuk entitas yang ambigu.
    public static func dedupID(proto: NodeProtocol, host: String, port: Int,
                               credential: String, transport: Transport,
                               path: String?, sni: String?,
                               transportHost: String? = nil,
                               flow: String? = nil,
                               realityPublicKey: String? = nil,
                               realityShortId: String? = nil,
                               cipher: String? = nil,
                               alterId: Int? = nil) -> String {
        var parts = [proto.rawValue, host.lowercased(), String(port), credential,
                   transport.rawValue, path ?? "", sni ?? ""]
        // Hanya field yang benar-benar terisi yang membedakan. `nil` dan `""`
        // dianggap sama supaya tidak memecah node yang tadinya identik.
        if let v = nonempty(transportHost) { parts.append("h=\(v.lowercased())") }
        if let v = nonempty(flow) { parts.append("f=\(v)") }
        if let v = nonempty(realityPublicKey) { parts.append("pbk=\(v)") }
        if let v = nonempty(realityShortId) { parts.append("sid=\(v)") }
        if let v = nonempty(cipher) { parts.append("c=\(v.lowercased())") }
        if let v = alterId { parts.append("aid=\(v)") }
        return SHA1Hex(parts.joined(separator: "|"))
    }

    private static func nonempty(_ s: String?) -> String? {
        guard let s, !s.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return s
    }

    /// SHA1 sederhana tanpa CryptoKit (kompatibel macOS 13 + Linux).
    private static func SHA1Hex(_ s: String) -> String {
        // FNV-1a 64-bit ganda sebagai hash stabil lokal (bukan kriptografis).
        // Cukup untuk dedup lokal; tidak dipakai untuk keamanan.
        var h1: UInt64 = 0xcbf29ce484222325
        var h2: UInt64 = 0x84222325cbf29ce4
        for b in s.utf8 {
            h1 ^= UInt64(b); h1 = h1 &* 0x100000001b3
            h2 ^= UInt64(b); h2 = h2 &* 0x10000000233
        }
        return String(format: "%016llx%016llx", h1, h2)
    }
}
