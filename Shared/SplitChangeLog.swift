import Foundation

/// Riwayat perubahan aturan split per aplikasi.
///
/// App ini menampilkan log ini di DUA tempat: panel riwayat di Split
/// Tunneling (tempat aksi itu terjadi), dan header panel Log di menu Sambung
/// (supaya ikut tersimpan/tersalin saat user menyalin log).
///
/// Seluruh deskripsi teksnya dibangkitkan oleh fungsi statis yang bisa diuji —
/// strings ber_localization dicampur di sini, jadi `describe` sengaja dibuat
/// `nonisolated` dan deterministik: input sama → output sama.
public enum SplitChangeLog {

    /// Apa yang terjadi pada satu aplikasi.
    public enum Action: String, Codable {
        /// Diaktifkan: app memakai VPN.
        case enable
        /// Dinonaktifkan: kembali ke koneksi biasa.
        case disable
    }

    public struct Entry: Codable, Identifiable, Equatable {
        public var id: UUID
        public var at: Date
        public var appName: String
        public var bundlePath: String
        public var mode: SplitMode
        public var action: Action
        /// Apakah entri ini untuk domain, bukan aplikasi?
        ///
        /// Default `false` supaya setiap pemanggil lama (dan setiap entri yang
        /// sudah tertulis di `split_changes.json` sebelum domain ada) tetap
        /// berarti "aplikasi". Pembacaan berkas lewat `decode(_:)` memakai
        /// `Row` yang mengabaikan key asing, jadi berkas lama tidak pernah
        /// rusak; yang berubah hanya isi berkas saat disimpan ulang, dan itu
        /// field boolean satu per entri.
        public var isDomain: Bool

        public init(id: UUID = UUID(), at: Date = Date(), appName: String,
                    bundlePath: String, mode: SplitMode = .exclusive,
                    action: Action, isDomain: Bool = false) {
            self.id = id
            self.at = at
            self.appName = appName
            self.bundlePath = bundlePath
            self.mode = mode
            self.action = action
            self.isDomain = isDomain
        }
    }

    /// Berapa banyak entri yang disimpan. Cukup untuk pesan "kapan saya salah
    /// klik", bukan arsip — file membengkak tidak ada gunanya.
    public static let limit = 100

    // MARK: - Deskripsi

    /// Baris-baris penjelasan untuk satu perubahan.
    ///
    /// Dua sisi harus dijawab, bukan hanya yang "berhasil":
    ///  - **APA** yang ditulis/dibuang (rule routing per proses), dan
    ///  - **KAPAN** benar-benar berlaku.
    ///
    /// Poin kedua sering jadi sumber kebingungan: mengubah daftar split tidak
    /// berlaku seketika. Aturan baru hanya aktif setelah reconnect. Kalau itu
    /// tidak ditulis, user akan menyimpulkan split tunnels-nya rusak padahal
    /// aturannya memang belum diperhitungkan ulang.
    public static func describe(_ e: Entry) -> [String] {
        let head = e.action == .enable
            ? L10n.string("splitlog_enable")
            : L10n.string("splitlog_disable")

        var out: [String] = ["\(head) — \(e.appName) [\(e.mode.rawValue)]"]
        out += e.isDomain ? domainLines(mode: e.mode, enabling: e.action == .enable)
                          : tunLines(mode: e.mode, enabling: e.action == .enable)
        out.append(e.action == .enable
                   ? L10n.string("splitlog_applies_after_reconnect")
                   : L10n.string("splitlog_applies_after_reconnect_off"))
        return out
    }

    /// Penjelasan untuk aturan per-domain.
    ///
    /// Harus berbeda dari `tunLines`, dan bukan hanya beda kalimat: matcher-nya
    /// memang berbeda (`domain_suffix`, bukan `process_path_regex`) dan cara
    /// sing-box mengetahuinya juga berbeda. Untuk app, sing-box bisa melihat
    /// prosesnya; untuk domain, nama hostnya harus datang dari SNI/HTTP Host
    /// yang di-sniff. Kalau log.domain memakai teks app, user akan mencari
    /// `process_path_regex` di log, tidak menemukannya, dan menyimpulkan
    /// domain split-nya tidak pernah ditulis.
    private static func domainLines(mode: SplitMode, enabling: Bool) -> [String] {
        let proxyTarget: String
        switch mode {
        case .inclusive:
            proxyTarget = enabling ? "proxy" : L10n.string("splitlog_out_direct")
        case .exclusive:
            proxyTarget = enabling ? L10n.string("splitlog_out_direct") : "proxy"
        }
        guard enabling else {
            return [
                L10n.string("splitlog_domain_rule_removed"),
                L10n.string("splitlog_env_none"),
                L10n.string("splitlog_follows_final")
            ]
        }
        return [
            L10n.string("splitlog_domain_rule_written").replacingOccurrences(of: "{out}", with: proxyTarget),
            L10n.string("splitlog_env_none"),
            L10n.string("splitlog_match_domain")
        ]
    }

    /// Penjelasan untuk dua mode TUN.
    ///
    /// Di mode ini TUN menyaring paket dan sing-box mencocokkan path proses.
    /// Yang penting disebut eksplisit: **tidak ada env proxy di sini** —
    /// user yang mencari `ALL_PROXY` di log akan menyimpulkan app ini rusak
    /// kalau tidak disebut.
    private static func tunLines(mode: SplitMode, enabling: Bool) -> [String] {
        let proxyTarget: String
        switch mode {
        case .inclusive:
            proxyTarget = enabling ? "proxy" : L10n.string("splitlog_out_direct")
        case .exclusive:
            proxyTarget = enabling ? L10n.string("splitlog_out_direct") : "proxy"
        }
        guard enabling else {
            return [
                L10n.string("splitlog_rule_removed"),
                L10n.string("splitlog_env_none"),
                L10n.string("splitlog_follows_final")
            ]
        }
        return [
            L10n.string("splitlog_rule_written").replacingOccurrences(of: "{out}", with: proxyTarget),
            L10n.string("splitlog_env_none"),
            L10n.string("splitlog_match_process")
        ]
    }

    /// Perubahan yang benar-benar mengubah arah traffic satu app ATAU satu
    /// domain.
    public struct Change: Equatable {
        public let bundlePath: String
        public let action: Action
        public let isDomain: Bool

        public init(bundlePath: String, action: Action, isDomain: Bool = false) {
            self.bundlePath = bundlePath
            self.action = action
            self.isDomain = isDomain
        }
    }

    /// Hitung perubahan antar dua keadaan split.
    ///
    /// Yang dibandingkan bukan "ada/tidak di daftar" melainkan **efek akhirnya**
    /// ("apakah trafiknya lewat VPN"). Untuk mode eksklusif keduanya
    /// berlawanan, jadi membandingkan daftar mentah akan mencatat perubahan
    /// yang tidak mengubah apa pun sekaligus melewatkan perubahan yang
    /// sebenarnya mengubah segalanya — termasuk saat mode diganti tanpa
    /// menyentuh satu pun app.
    ///
    /// Murni & nonisolated: bisa diuji tanpa AppState, tanpa view, tanpa disk.
    ///
    /// `isDomain` hanya menempelkan label ke entri hasilnya; logikanya sama,
    /// karena app dan domain berbagi mode yang sama. UI memanggil fungsi ini
    /// DUA KALI — sekali untuk app, sekali untuk domain — supaya perubahan
    /// domain tidak ikut dibaca sebagai perubahan aplikasi.
    public static func diff(listedBefore: Set<String>, listedAfter: Set<String>,
                            modeBefore: SplitMode, modeAfter: SplitMode,
                            isDomain: Bool = false) -> [Change] {
        var out: [Change] = []
        for path in listedBefore.union(listedAfter).sorted() {
            let was = modeBefore.usesVPN(appIsListed: listedBefore.contains(path))
            let now = modeAfter.usesVPN(appIsListed: listedAfter.contains(path))
            guard was != now else { continue }
            out.append(Change(bundlePath: path, action: now ? .enable : .disable,
                              isDomain: isDomain))
        }
        return out
    }

    // MARK: - Penyimpanan

    public static let fileName = "split_changes.json"

    /// Baca riwayat; berkas rusak/versi lama tidak boleh emptying app — jadi
    /// kegagalan baca menghasilkan daftar kosong, bukan crash.
    public static func load() -> [Entry] {
        let url = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("FreePN", isDirectory: true)
            .appendingPathComponent(fileName) ?? URL(fileURLWithPath: "/dev/null")
        guard let data = try? Data(contentsOf: url) else { return [] }
        return decode(data)
    }

    /// Decode satu per satu, bukan sekali untuk seluruh array.
    ///
    /// `split_changes.json` versi lama menyimpan entri tanda "Terminal"
    /// berdampingan dengan entri TUN, di field `kind`. Entri Terminal tidak
    /// bisa lagi dijelaskan apa pun (tanda itu sudah tidak ada di app), tapi
    /// membuangnya lewat decode biasa akan menghapus SELURUH riwayat —
    /// termasuk entri TUN yang masih relevan. Jadi baris yang tidak dikenal
    /// dilewati, sisanya tetap terbaca.
    static func decode(_ data: Data) -> [Entry] {
        struct Row: Decodable {
            var id: UUID
            var at: Date
            var appName: String
            var bundlePath: String
            /// `nil` = berkas versi lebih lama lagi, yang belum punya key ini.
            var kind: String?
            var mode: SplitMode?
            var action: Action
        }
        guard let rows = try? JSONDecoder().decode([Row].self, from: data) else { return [] }
        return rows.compactMap { row in
            guard row.kind == nil || row.kind == "vpn" else { return nil }
            return Entry(id: row.id, at: row.at, appName: row.appName,
                         bundlePath: row.bundlePath, mode: row.mode ?? .exclusive,
                         action: row.action)
        }
    }

    public static func save(_ entries: [Entry]) {
        let trimmed = Array(entries.suffix(limit))
        guard let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let folder = dir.appendingPathComponent("FreePN", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(fileName)
        guard let data = try? JSONEncoder().encode(trimmed) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
