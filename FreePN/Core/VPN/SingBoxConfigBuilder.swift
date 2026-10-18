import Foundation

/// Builder config sing-box (outbound + TUN + routing proses + DNS anti-bocor).
/// Skema sesuai sing-box >=1.10. Selalu validasi `sing-box check -c` sebelum run.
public struct SingBoxConfigBuilder: VPNCore {
    public var name: String { "sing-box" }
    public init() {}

    public func configJSON(node: ProxyNode, split: SplitTunnelConfig, clashPort: Int = 28909, mixedPort: Int = 28108, tunEnabled: Bool = true) -> String {
        var outbound = outboundJSON(node: node)
        // REGRESI D83 (lihat DECISIONS.md): resolver hostname node HARUS
        // `direct-dns`, bukan `proxy-dns`.
        //
        // `proxy-dns` ber-`detour: "proxy"` (lihat baris server DNS di bawah).
        // Jadi me-resolve `svp.byxl.biz.id` berarti membangun koneksi ke
        // `svp.byxl.biz.id`, dan membangun koneksi itu harus lewat outbound
        // `proxy` yang butuh `svp.byxl.biz.id` ter-resolve dulu — lingkaran
        // tertutup yang tidak punya jalan keluar:
        //
        //     DNS query loopback in transport[proxy-dns]
        //
        // Config hasil builder tetap LOLOS `sing-box check` (loop itu bukan
        // kesalahan sintaks), core tetap hidup dan port tetap melayani — UI
        // menampilkan "sesi aktif" — tapi SETIAP koneksi gagal. Dan karena
        // TUN memakai `strict_route: true`, default route sudah diambil alih
        // sebelum outbound ini pernah berhasil: seluruh internet machine ikut
        // mati, bukan cuma trafik VPN. Buta juga perlu restart karena route
        // TUN yang yatim tidak dipulihkan.
        //
        // `dns.final` tetap `proxy-dns` supaya pencarian domain milik user
        // sendiri tetap lewat VPN dan tidak bocor ke ISP — hanya hostname node
        // sendiri yang boleh di-resolve lewat resolver sistem.
        outbound["domain_resolver"] = "direct-dns"
        let rules = routingRules(split: split, serverIP: node.host, tunEnabled: tunEnabled)
        // `effectiveMode`, bukan `mode`: sakelar split mati harus berarti VPN
        // penuh (final=proxy), bukan mengikuti mode inklusif yang tersimpan.
        let inclusive = split.effectiveMode == .inclusive
        let dnsFinal = inclusive ? "direct-dns" : "proxy-dns"
        // Varian SOCKS-only (tanpa TUN) untuk mode System Extension (VPN per-app):
        // TransparentProxyProvider yang meneruskan flow via SOCKS mixed-inbound.
        // Tanpa TUN = tanpa root = LocalCoreRunner cukup (user-space).
        var inbounds: [[String: Any]] = []
        if tunEnabled {
            // TUN: jangan hardcode interface_name (utun9 bisa bentrok).
            // Biarkan sistem auto-assign; strict_route=true agar default route
            // benar-benar diambil alih (false = trafik bocor via en0, "tersambung" tapi IP tak berubah).
            inbounds.append(["type": "tun", "tag": "tun-in",
                             "address": ["172.19.0.1/30"], "auto_route": true, "strict_route": true,
                             "stack": "system", "mtu": 9000])
        }
        inbounds.append(["type": "mixed", "tag": "mixed-in", "listen": "127.0.0.1", "listen_port": mixedPort])
        let cfg: [String: Any] = [
            "log": ["level": "warning"],
            "inbounds": inbounds,
            "outbounds": [
                outbound,
                ["type": "direct", "tag": "direct", "domain_resolver": "direct-dns"]
            ],
            "route": [
                "rules": rules,
                "final": inclusive ? "direct" : "proxy",
                "default_domain_resolver": dnsFinal,
                "auto_detect_interface": true
            ],
            "dns": [
                "servers": [
                    ["tag": "proxy-dns", "type": "https", "server": "8.8.8.8", "detour": "proxy"],
                    ["tag": "direct-dns", "type": "local"]
                ],
                "rules": dnsRules(split: split),
                "final": dnsFinal
            ],
            "experimental": [
                "clash_api": ["external_controller": "127.0.0.1:\(clashPort)"]
            ]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: cfg, options: [.prettyPrinted, .sortedKeys]),
           let s = String(data: data, encoding: .utf8) { return s }
        return "{}"
    }

    /// True bila config ini TIDAK mem-VPN-kan apa pun:
    /// mode inklusif + daftar app kosong + daftar domain kosong => final=direct,
    /// semua trafik bypass.
    /// UI wajib menolak Connect dalam keadaan ini (lihat ConnectionManager).
    ///
    /// Sakelar split mati TIDAK dihitung di sini: matinya split = VPN penuh,
    /// bukan bypass semua.
    public static func isBypassAll(split: SplitTunnelConfig) -> Bool {
        split.effectiveMode == .inclusive && !split.hasAnyActiveSelection
    }

    // MARK: - Config probe (verifikasi akses internet)

    /// Tag outbound untuk probe ke-i.WAJIB konsisten dengan `probeConfigJSON`
    /// karena InternetProbe memanggil `/proxies/<tag>/delay`.
    public static func probeTag(_ index: Int) -> String { "probe-\(index)" }

    /// Config untuk membuktikan node benar-benar bisa akses internet.
    ///
    /// Berbeda dengan `configJSON` (satu node + TUN), di sini SATU proses core
    /// memuat banyak outbound sekaligus, TANPA TUN — jadi tak butuh root dan
    /// tak mengganggu koneksi yang sedang jalan. Clash API lalu menguji tiap
    /// outbound satu per satu lewat `/proxies/<tag>/delay`, yang benar-benar
    /// menjangkau internet lewat node tersebut (bukan cuma handshake TCP).
    ///
    /// `route.final` diarahkan ke outbound probe pertama, bukan "direct":
    /// kalau ada request yang lolos ke routing, tetap lewat proxy — supaya
    /// hasil ukur tidak pernah bocor ke koneksi lokal.
    public func probeConfigJSON(nodes: [ProxyNode], clashPort: Int, mixedPort: Int) -> String {
        var outbounds: [[String: Any]] = []
        for (i, n) in nodes.enumerated() {
            var o = outboundJSON(node: n)
            o["tag"] = Self.probeTag(i)
            o["domain_resolver"] = "probe-dns"
            outbounds.append(o)
        }
        outbounds.append(["type": "direct", "tag": "direct", "domain_resolver": "direct-dns"])
        let inbounds: [[String: Any]] = [
            ["type": "mixed", "tag": "mixed-in", "listen": "127.0.0.1", "listen_port": mixedPort]
        ]
        // D91 — resolver host node memakai `local` (resolver sistem), bukan DoH
        // ke 8.8.8.8 lewat `detour: direct`.
        //
        // Config connect juga memakai resolver sistem (`direct-dns`) untuk
        // hostname node — lihat catatan regresi D83 di `configJSON`.
        //
        // Alasannya: resolver sistem (getaddrinfo) selalu bisa dipakai selama
        // mesinnya online, dan itu persis yang dipakai aplikasi lain di Mac
        // ini. DoH langsung ke 8.8.8.8 sering diblokir atau diperlambat oleh
        // jaringan (ISP Indonesia, kampus, tethering), sehingga setiap node
        // ber-hostname gagal diprobe tapi sebenarnya sehat: vonis mati palsu
        // untuk ~30% node.
        //
        // Resolver sistem (getaddrinfo) selalu bisa dipakai selama mesinnya
        // online, dan itu persis yang dipakai aplikasi lain di Mac ini.
        let cfg: [String: Any] = [
            "log": ["level": "error"],
            "inbounds": inbounds,
            "outbounds": outbounds,
            "route": [
                "rules": [["ip_cidr": ["127.0.0.0/8", "10.0.0.0/8", "172.16.0.0/12",
                                       "192.168.0.0/16", "169.254.0.0/16", "::1/128"],
                           "outbound": "direct"]],
                "final": Self.probeTag(0),
                "default_domain_resolver": "probe-dns",
                "auto_detect_interface": true
            ],
            "dns": [
                "servers": [
                    ["tag": "probe-dns", "type": "local"],
                    ["tag": "direct-dns", "type": "local"]
                ],
                "final": "probe-dns"
            ],
            "experimental": [
                "clash_api": ["external_controller": "127.0.0.1:\(clashPort)"]
            ]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: cfg, options: [.prettyPrinted, .sortedKeys]),
           let s = String(data: data, encoding: .utf8) { return s }
        return "{}"
    }

    /// True bila string adalah literal IP (v4/v6), bukan hostname.
    func isIPLiteral(_ s: String) -> Bool {
        var v4 = in_addr()
        var v6 = in6_addr()
        return s.withCString { inet_pton(AF_INET, $0, &v4) == 1 }
            || s.withCString { inet_pton(AF_INET6, $0, &v6) == 1 }
    }

    /// Jalankan `sing-box check` terhadap config.
    ///
    /// PERBAIKAN DEADLOCK: versi lama mengalirkan stdout DAN stderr ke satu
    /// `Pipe` lalu memanggil `waitUntilExit()` SEBELUM membaca pipe itu.
    /// Kalau `sing-box` menulis lebih dari ~64 KB diagnostik, anak proses
    /// tertahan di `write()` dan `waitUntilExit()` tidak pernah
    /// kembali — connect menggantung selamanya (dan di `ConnectionManager`
    /// pemanggilnya ada di main actor, jadi seluruh UI ikut beku).
    ///
    /// Sekarang: pipe DIBACA KONKUREN, dan hasilnya dikembalikan sebagai
    /// pesan supaya caller bisa menampilkan sebab penolakan yang SEBENARNYA
    /// alih-alih `error_invalid_config` generik. Timeout 10 detik supaya
    /// proses yang menggantung tidak membekukan UI selamanya.
    public func validate(configPath: String, coreBinary: String) -> Bool {
        if case .ok = validateDetailed(configPath: configPath, coreBinary: coreBinary) { return true }
        return false
    }

    public enum ValidationResult {
        case ok
        case rejected(String)     // ditolak core, pesan = diagnostik stderr
        case failed(String)      // gagal menjalankan / timeout
    }

    public func validateDetailed(configPath: String,
                                 coreBinary: String,
                                 timeout: TimeInterval = 10) -> ValidationResult {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: coreBinary)
        p.arguments = ["check", "-c", configPath]
        let out = Pipe()
        let err = Pipe()
        p.standardOutput = out
        p.standardError = err

        // Kumpulkan output di queue terpisah SELAGI proses berjalan.
        let collector = DispatchQueue(label: "freepn.singbox.validate", attributes: .concurrent)
        var outData = Data(), errData = Data()
        let group = DispatchGroup()
        for pipe in [out, err] {
            group.enter()
            collector.async {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if pipe === out { outData = data } else { errData = data }
                group.leave()
            }
        }

        do { try p.run() } catch {
            return .failed(error.localizedDescription)
        }

        // Tunggu proses dengan batas waktu. `waitUntilExit()` tidak punya
        // timeout, jadi batasnya lewat `terminationHandler` + `DispatchGroup`.
        let finished = DispatchGroup()
        finished.enter()
        var exitStatus: Int32 = -1
        var timedOut = false
        p.terminationHandler = { proc in
            exitStatus = proc.terminationStatus
            finished.leave()
        }
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            timedOut = true
            p.terminate()
            // Beri kesempatan singkat untuk benar-benar mati.
            _ = finished.wait(timeout: .now() + 1)
        }
        // Tunggu juga sampai pipe habis dibaca; tanpa ini `readDataToEndOfFile`
        // bisa menggantung bila anak masih memegang fd.
        _ = group.wait(timeout: .now() + 1)

        if timedOut { return .failed("timeout") }
        if exitStatus == 0 { return .ok }
        let diag = String(decoding: errData.isEmpty ? outData : errData, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return .rejected(diag.isEmpty ? "exit \(exitStatus)" : diag)
    }

    // MARK: - outbound per protokol

    /// TCP keepalive untuk koneksi ke server node.
    ///
    /// Stream panjang (opencode thinking = SSE menitan) mati tiap 10–30
    /// menit karena server trial membunuh sesi yang idle — keepalive level
    /// TCP membuat sesi tidak pernah terlihat idle di sisi server.
    /// Butuh sing-box ≥1.13 (`check` menolak field ini di 1.12).
    ///
    /// `2m`/`30s` (bukan default 1.13 `5m`/`75s`): biaya beberapa byte per
    /// 30 detik per koneksi idle tidak berarti apa-apa, sedangkan cut yang
    /// agresif (NAT kampus, trial 10-menit) butuh ambang di bawahnya.
    public static let nodeKeepAlive = "2m"
    public static let nodeKeepAliveInterval = "30s"

    func outboundJSON(node: ProxyNode) -> [String: Any] {
        var o: [String: Any] = ["tag": "proxy", "server": node.host, "server_port": node.port,
                                "tcp_keep_alive": Self.nodeKeepAlive,
                                "tcp_keep_alive_interval": Self.nodeKeepAliveInterval]
        switch node.proto {
        case .vmess:
            o["type"] = "vmess"
            o["uuid"] = node.credential
            o["security"] = node.cipher ?? "auto"
            o["alter_id"] = node.alterId ?? 0
            applyTransport(&o, node: node)
        case .trojan:
            o["type"] = "trojan"
            o["password"] = node.credential
            applyTransport(&o, node: node)
        case .shadowsocks:
            o["type"] = "shadowsocks"
            o["method"] = node.cipher ?? "aes-256-gcm"
            o["password"] = node.credential
        case .vless:
            o["type"] = "vless"
            o["uuid"] = node.credential
            if let flow = node.flow, !flow.isEmpty { o["flow"] = flow }
            applyTransport(&o, node: node)
        case .hysteria2:
            o["type"] = "hysteria2"
            o["password"] = node.credential
            // sing-box 1.11+ memakai up_mbps/down_mbps (up/down sudah dihapus).
            // Kosongkan bila feed tidak menyebutkannya → core pakai default BBR.
            o["up_mbps"] = node.upMbps ?? 50
            o["down_mbps"] = node.downMbps ?? 200
            if let obfsPwd = node.obfsPassword, !obfsPwd.isEmpty {
                o["obfs"] = ["type": "salamander", "password": obfsPwd]
            }
        case .http:
            o["type"] = "http"
            applyPlainProxyAuth(&o, credential: node.credential)
        case .socks:
            o["type"] = "socks"
            o["version"] = "5"
            applyPlainProxyAuth(&o, credential: node.credential)
        }
        // Outbound `socks` di sing-box 1.12 TIDAK punya field `tls` sama
        // sekali: `sing-box check` menolak SELURUH config dengan
        // `outbounds[0].tls: json: unknown field "tls"`. Karena `check`
        // bersifat all-or-nothing, satu node socks5 dengan `tls: true` di
        // feed akan menggagalkan verifikasi internet untuk ratusan node lain
        // yang sebenarnya sehat — persis kelas bug yang `acceptedByCore`
        // ada untuk mencegahnya.
        //
        // Node itu jadi SOCKS biasa (tanpa TLS). Kalau provider memang hanya
        // bisa lewat SOCKS-over-TLS, node-nya akan terbaca "mati" saat
        // diuji — yang memang jujur, dan jauh lebih murah daripada membuat
        // seluruh sesi probe gagal.
        let supportsTLS = node.proto != .socks
        if supportsTLS, let tls = node.tls, tls.enabled {
            var t: [String: Any] = ["enabled": true]
            if let sni = tls.sni, !sni.isEmpty { t["server_name"] = sni }
            t["insecure"] = tls.allowInsecure
            // REALITY (VLESS): butuh public key + short id + sidik uTLS.
            if tls.isReality {
                var reality: [String: Any] = [
                    "enabled": true,
                    "public_key": tls.realityPublicKey ?? ""
                ]
                if let sid = tls.realityShortId, !sid.isEmpty { reality["short_id"] = sid }
                t["reality"] = reality
                t["utls"] = ["enabled": true,
                             "fingerprint": tls.fingerprint ?? "chrome"]
            }
            o["tls"] = t
        }
        return o
    }

    /// Kredensial proxy HTTP/SOCKS, disimpan sebagai "username:password".
    ///
    /// Format sing-box memakai dua field terpisah, dan keduanya opsional —
    /// jadi proxy tanpa autentikasi TIDAK boleh menghasilkan `username: ""`,
    /// yang membuat `sing-box check` menolak config itu.
    private func applyPlainProxyAuth(_ o: inout [String: Any], credential: String) {
        guard !credential.isEmpty else { return }
        guard let sep = credential.firstIndex(of: ":") else {
            o["password"] = credential
            return
        }
        let user = String(credential[..<sep])
        let pass = String(credential[credential.index(after: sep)...])
        if !user.isEmpty { o["username"] = user }
        if !pass.isEmpty { o["password"] = pass }
    }

    private func applyTransport(_ o: inout [String: Any], node: ProxyNode) {
        switch node.transport {
        case .tcp: break
        case .ws:
            o["transport"] = ["type": "ws", "path": node.transportPath ?? "/",
                              "headers": node.transportHost.map { ["Host": $0] } ?? [:]]
        case .grpc:
            o["transport"] = ["type": "grpc", "service_name": node.transportPath ?? ""]
        case .http:
            o["transport"] = ["type": "http", "path": node.transportPath ?? "/",
                              "host": node.transportHost.map { [$0] } ?? []]
        }
    }

    /// Rules routing: selalu direct RFC1918/link-local/multicast, IP server, proses FreePN/core.
    func routingRules(split: SplitTunnelConfig, serverIP: String,
                       tunEnabled: Bool = true) -> [[String: Any]] {
        var rules: [[String: Any]] = [
            ["ip_cidr": ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16",
                         "127.0.0.0/8", "169.254.0.0/16", "::1/128", "fc00::/7", "fe80::/10"],
             "outbound": "direct"]
        ]
        // Cegah routing loop ke server proxy itu sendiri.
        // Route rule tidak punya field `server`; pakai ip_cidr untuk literal IP,
        // domain untuk hostname.
        if isIPLiteral(serverIP) {
            rules.append(["ip_cidr": [serverIP], "outbound": "direct"])
        } else if !serverIP.isEmpty {
            rules.append(["domain": [serverIP], "outbound": "direct"])
        }
        // Aturan `process_name: FreePN -> direct` di bawah wajib ada untuk
        // mencegah routing loop. Tapi `ExitIPChecker.viaCore` mengirim
        // request dari proses FreePN lewat SOCKS `mixed-in`, sehingga request
        // itu ikut kena aturan itu dan condong direct -- hasilnya "IP keluar"
        // selalu IP asli user, bukan IP exit VPN.
        //
        // Perbaikannya: traffic yang masuk lewat `mixed-in` dipaksa proxy
        // lebih dulu. Request lewat SOCKS proxy itu SADAR meminta diproxy,
        // dan request exit-IP khususnya harus lewat proxy supaya angka yang
        // ditampilkan benar-benar berasal dari VPN.
        //
        // Syaratnya `tunEnabled`, BUKAN mode split. Alasannya: kalau TUN
        // aktif, `mixed-in` hanya dipakai FreePN sendiri (cek exit-IP), jadi
        // memaksanya ke proxy tidak pernah menyentuh trafik user. Kalau TUN
        // MATI (mode System Extension / VPN per-app), `mixed-in` justru
        // dipakai TransparentProxyProvider untuk meneruskan trafik aplikasi
        // milik user -- memaksa semua trafik itu ke proxy akan membalik
        // aturan split yang sudah user pilih.
        if tunEnabled {
            rules.append(["inbound": ["mixed-in"], "outbound": "proxy"])
        }
        rules.append(["process_name": ["FreePN", "sing-box", "mihomo"], "outbound": "direct"])
        let apps = split.activeApps
        let domains = split.activeDomains
        let target = split.effectiveMode == .inclusive ? "proxy" : "direct"

        // Sniff WAJIB ada sebelum rule domain, dan hanya kalau ada domain.
        //
        // Tanpa sniff, `domain_suffix` nyaris tidak akan pernah match di TUN:
        // macOS sudah resolve nama host-nya sendiri lewat DNS router (yang
        // keluar `direct` di rule pertama), jadi yang sampai ke sing-box hanya
        // IP mentah — dan matcher domain tidak punya apa pun untuk
        // dicocokkan. Gejalanya persis kelas bug yang sering menghantui app
        // ini: config LOLOS `sing-box check`, core hidup, UI bilang aktif,
        // tapi aturannya tidak pernah menyala.
        //
        // Dua syarat agar tidak ada yang berubah untuk user yang tidak pakai
        // fitur ini:
        // 1. Hanya saat `domains` tidak kosong. Tanpa domain, tidak ada yang
        //    butuh sniff, jadi config byte-per-byte sama seperti sebelumnya.
        // 2. Diletakkan SETELAH rule anti-loop (`process_name ... direct`),
        //    jadi trafik FreePN sendiri dan koneksi core ke server proxy
        //    tidak pernah ikut menunggu hasil sniff.
        //
        // Bentuk `{"action":"sniff"}` bukan field `sniff: true` di inbound:
        // yang lama sudah deprecated dan memicu WARN, dan `SingBoxValidationTests`
        // memperlakukan WARN sebagai kegagalan.
        if !domains.isEmpty {
            rules.append(["action": "sniff"])
        }
        if !apps.isEmpty {
            let regexes = apps.map { NSRegularExpression.escapedPattern(for: $0) }
            rules.append(["process_path_regex": regexes, "outbound": target])
        }
        // Rule domain selalu TERAKHIR. Urutan ini penting, bukan soal
        // tampilan: rule di atas (IP privat, IP/host server proxy) harus
        // menang lebih dulu. Kalau domain didahulukan, domain yang user
        // daftarkan bisa ikut mencengkeram koneksi ke server VPN dan membuat
        // routing loop — persis D94.
        if !domains.isEmpty {
            rules.append(["domain_suffix": domains, "outbound": target])
        }
        return rules
    }

    /// Rules DNS mengikuti split yang sama: app per-proses, domain per-host.
    /// Kosong bila tidak ada app DAN tidak ada domain dipilih — `final` yang
    /// menentukan.
    ///
    /// Urutan app lalu domain sengaja. Keduanya menunjuk resolver yang sama
    /// (mode menentukan arahnya), jadi urutan tidak mengubah hasil. Yang
    /// menentukan adalah matcher mana yang paling spesifik untuk sebuah query:
    /// untuk query yang datang dari aplikasi, matcher proses itulah yang paling
    /// spesifik.
    func dnsRules(split: SplitTunnelConfig) -> [[String: Any]] {
        let apps = split.activeApps
        let domains = split.activeDomains
        guard !apps.isEmpty || !domains.isEmpty else { return [] }
        let server = split.effectiveMode == .inclusive ? "proxy-dns" : "direct-dns"
        var rules: [[String: Any]] = []
        if !apps.isEmpty {
            let regexes = apps.map { NSRegularExpression.escapedPattern(for: $0) }
            rules.append(["process_path_regex": regexes, "server": server])
        }
        if !domains.isEmpty {
            rules.append(["domain_suffix": domains, "server": server])
        }
        return rules
    }
}
