import Foundation

public enum SplitMode: String, Codable, CaseIterable {
    case inclusive // hanya app terpilih lewat VPN
    case exclusive // app terpilih bypass VPN
}

/// Hanya dua mode, keduanya routing lewat TUN dan berbasis pencocokan path
/// proses. Tidak ada mode ketiga: semua keputusan "app ini lewat VPN atau
/// tidak" dijawab oleh mode + daftar app, jadi tidak ada lagi tanda atau
/// daftar terpisah yang bisa menduplikasi keputusan yang sama.
extension SplitMode {
    /// Apakah traffic app ini diarahkan ke proxy pada mode ini?
    ///
    /// Satu definisi untuk badge, menu, dan diff riwayat. Kalau ketiganya
    /// punya aturan sendiri, cepat atau lambat mereka akan berbeda — dan yang
    /// berbeda itu selalu berbohong ke user.
    ///
    /// Inklusif: yang DAFTAR memakai VPN. Eksklusif: yang TIDAK daftar.
    public func usesVPN(appIsListed: Bool) -> Bool {
        switch self {
        case .inclusive: return appIsListed
        case .exclusive: return !appIsListed
        }
    }
}

public struct SplitTunnelConfig: Codable {
    public var mode: SplitMode
    public var inclusiveApps: [String] // path .app / bundle id / executable
    public var exclusiveApps: [String]
    /// Domain yang ikut aturan mode yang sama dengan app, bukan daftar
    /// terpisah: user memilih "yang listed = lewat VPN / bypass VPN" sekali,
    /// lalu mengisinya dengan app DAN domain.
    ///
    /// Dua daftar (bukan satu daftar berisi keduanya) karena keduanya
    /// berubah dengan cara yang berbeda: path app dicocokkan ke executable
    /// (`process_path_regex`), domain dicocokkan ke nama host
    /// (`domain_suffix`). Satu daftar `[String]` tidak bisa mengeluarkan dua
    /// rule berbeda dari isinya tanpa menebak mana yang mana.
    public var inclusiveDomains: [String]
    public var exclusiveDomains: [String]
    /// Sakelar utama Split Tunneling. `false` = aturan split sama sekali
    /// tidak dipakai, jadi semua trafik lewat VPN (VPN penuh).
    ///
    /// Default `true`: berkas split.json yang sudah ada tidak pernah punya
    /// key ini, dan user yang sudah mengatur app TEPAK AKAN kehilangan
    /// pengaturannya kalau default-nya `false`.
    public var isEnabled: Bool

    public init(mode: SplitMode = .exclusive,
                inclusiveApps: [String] = [],
                exclusiveApps: [String] = [],
                isEnabled: Bool = true,
                inclusiveDomains: [String] = [],
                exclusiveDomains: [String] = []) {
        self.mode = mode
        self.inclusiveApps = inclusiveApps
        self.exclusiveApps = exclusiveApps
        self.isEnabled = isEnabled
        self.inclusiveDomains = Self.normalizeDomains(inclusiveDomains)
        self.exclusiveDomains = Self.normalizeDomains(exclusiveDomains)
    }

    /// Daftar app yang benar-benar berlaku.
    ///
    /// PENTING: sakelar dimatikan = daftar kosong. `SingBoxConfigBuilder`
    /// menulis aturan routing dari nilai inilah, jadi "split mati" otomatis
    /// berarti tidak ada aturan per-proses sama sekali — tidak perlu cabang
    /// terpisah di builder, dan tidak bisa ada "aturan tersisa" yang aktif
    /// padahal sakelarnya off.
    public var activeApps: [String] {
        guard isEnabled else { return [] }
        switch mode {
        case .inclusive: return inclusiveApps
        case .exclusive: return exclusiveApps
        }
    }

    /// Domain aktif untuk mode sekarang. Sakelar split mati = daftar kosong,
    /// persis seperti `activeApps` — tidak ada cabang terpisah di builder.
    public var activeDomains: [String] {
        guard isEnabled else { return [] }
        switch mode {
        case .inclusive: return inclusiveDomains
        case .exclusive: return exclusiveDomains
        }
    }

    /// Apakah mode + daftar yang aktif menyisakan SESUATU untuk diputuskan?
    ///
    /// Inklusif tanpa app DAN tanpa domain = semua trafik bypass, jadi
    /// `route.final` jadi `direct` dan tidak ada yang memakai VPN sama sekali.
    /// `SingBoxConfigBuilder.isBypassAll` memakai ini; UI Connect memakai
    /// fungsi itu untuk menolak sambung.
    public var hasAnyActiveSelection: Bool {
        !activeApps.isEmpty || !activeDomains.isEmpty
    }

    /// Mode yang benar-benar dipakai saat membangun config.
    ///
    /// Sakelar split mati = VPN PENUH, jadi effective mode selalu `.exclusive`.
    /// Ini bukan detail kecil: `configJSON` membaca mode ini untuk memilih
    /// `route.final`. Kalau sakelar mati tapi mode tersimpan masih `.inclusive`,
    /// tanpa baris ini `final` jadi `direct` — semua trafik keluar tanpa VPN
    /// padahal user mematikan split justru karena mau semua trafik lewat VPN.
    public var effectiveMode: SplitMode {
        isEnabled ? mode : .exclusive
    }

    /// Salin daftar aktif ke mode yang sedang dipilih, buang daftar lama.
    /// Dipakai UI saat mode diganti supaya daftar yang tampil sesuai mode.
    public mutating func replaceActive(with paths: [String]) {
        switch mode {
        case .inclusive:
            inclusiveApps = paths
            exclusiveApps = []
        case .exclusive:
            exclusiveApps = paths
            inclusiveApps = []
        }
    }

    /// Sama seperti `replaceActive`, tapi untuk daftar domain.
    ///
    /// WAJIB dipisah dari `replaceActive`, bukan digabung jadi satu fungsi.
    /// `replaceActive` sengaja MENGHAPUS daftar lawannya (`inclusiveApps = []`
    /// saat mode eksklusif), jadi kalau penyimpanan domain ikut lewat fungsi
    /// itu, satu `Save` di UI sudah menghapus seluruh pengaturan domain user
    /// tanpa jejak — persis kelas kehilangan-data yang `decodeIfPresent` di
    /// bawah ada untuk cegah.
    public mutating func replaceActiveDomains(with domains: [String]) {
        let clean = Self.normalizeDomains(domains)
        switch mode {
        case .inclusive:
            inclusiveDomains = clean
            exclusiveDomains = []
        case .exclusive:
            exclusiveDomains = clean
            inclusiveDomains = []
        }
    }

    /// Bersihkan daftar domain: buang kosong, duplikat, dan samakan bentuk.
    ///
    /// Idempoten, jadi aman dipanggil berulang pada nilai yang sama.
    public static func normalizeDomains(_ domains: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for d in domains {
            guard let n = normalizeDomain(d), !seen.contains(n) else { continue }
            seen.insert(n)
            out.append(n)
        }
        return out
    }

    /// Bentuk kanonik satu domain: `EXAMPLE.com.` -> `example.com`.
    ///
    /// User mengetik apa saja: `https://ads.example.com/path`, `*.example.com`,
    /// `.example.com`, atau `Example.COM.` Semuanya bermaksud satu hal yang
    /// sama, dan semua harus berakhir sebagai `example.com`. Kalau tidak,
    /// `ads.example.com` dan `*.ads.example.com` jadi dua entri berbeda,
    /// daftar cepat penuh, dan dua aturan yang ostensibly sama tidak saling
    /// cocok.
    ///
    /// Scheme, path, query, fragment, userinfo, dan port dibuang karena
    /// `domain_suffix` hanya menerima nama host.
    public static func normalizeDomain(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !s.isEmpty else { return nil }
        if let r = s.range(of: "://") { s = String(s[r.upperBound...]) }
        if let r = s.range(of: "@"), r.upperBound < s.endIndex {
            s = String(s[r.upperBound...])
        }
        if let i = s.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) {
            s = String(s[..<i])
        }
        if let i = s.firstIndex(of: ":") { s = String(s[..<i]) }
        while let f = s.first, f == "*" || f == "." { s.removeFirst() }
        while let l = s.last, l == "." { s.removeLast() }
        guard !s.isEmpty, s.contains(".") || s == "localhost" else { return nil }
        // Hanya karakter nama host yang sah. Menolak di sini memberi pesan di
        // form; menolak di `sing-box check` menggagalkan SELURUH config
        // (pemeriksaan itu all-or-nothing) karena satu domain salah ketik.
        //
        // Titik WAJIB ada di sini — tanpanya setiap domain ditolak, karena
        // satu-satunya tanda pengenal domain justru titik.
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-._")
        guard s.allSatisfy({ allowed.contains($0) }) else { return nil }
        return s
    }

    // split.json versi lama tidak punya `isEnabled` → decodeIfPresent, bukan
    // `decode` (yang akan membuat SELURUH pengaturan split hilang hanya karena
    // app diperbarui). Key `terminalApps` yang pernah ditulis versi lama
    // sengaja tidak lagi dibaca: `Codable` mengabaikan key asing, jadi
    // pengaturan TUN user tetap utuh.
    private enum CodingKeys: String, CodingKey {
        case mode, inclusiveApps, exclusiveApps, isEnabled
        case inclusiveDomains, exclusiveDomains
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Decode lewat String dulu, bukan langsung ke enum. `split.json` yang
        // pernah ditulis mode `terminal` (D80) akan gagal didecode kalau
        // enum-nya dibaca langsung, dan satu `throw` itu menghapus seluruh
        // pengaturan — persis kelas kehilangan-data yang `decodeIfPresent`
        // ada untuk cegah. Nilai tak dikenal jatuh ke default, daftar app
        // tetap utuh.
        let rawMode = (try? c.decodeIfPresent(String.self, forKey: .mode)) ?? nil
        mode = rawMode.flatMap(SplitMode.init(rawValue:)) ?? .exclusive
        inclusiveApps = try c.decodeIfPresent([String].self, forKey: .inclusiveApps) ?? []
        exclusiveApps = try c.decodeIfPresent([String].self, forKey: .exclusiveApps) ?? []
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        // Domain ditambahkan belakangan, jadi `split.json` versi lama tidak
        // punya key ini sama sekali. `decode` (bukan `decodeIfPresent`) akan
        // THROW dan menghapus seluruh pengaturan split yang sudah rapi, hanya
        // karena app-nya versi lebih baru.
        inclusiveDomains = Self.normalizeDomains(
            (try? c.decodeIfPresent([String].self, forKey: .inclusiveDomains)) ?? [])
        exclusiveDomains = Self.normalizeDomains(
            (try? c.decodeIfPresent([String].self, forKey: .exclusiveDomains)) ?? [])
    }
}

public struct DiscoveredApp: Identifiable, Hashable {
    public var id: String // bundle id atau path
    public var name: String
    public var bundleID: String?
    public var path: String
    public var iconData: Data?
    public init(id: String, name: String, bundleID: String?, path: String) {
        self.id = id; self.name = name; self.bundleID = bundleID; self.path = path
    }
}