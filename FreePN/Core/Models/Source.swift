import Foundation

public struct VPNSubscriptionSource: Identifiable, Codable, Hashable {
    public var id: String
    public var name: String
    public var url: String
    public var isStarred: Bool
    public var isEnabled: Bool
    public var isCustom: Bool
    public var nodeCount: Int
    public var lastUpdated: Date?
    public var status: SourceStatus
    public var lastError: String?
    /// Node dari sumber ini yang BENAR-BENAR terpakai setelah dedup. Bisa 0
    /// walau `nodeCount` besar kalau semuanya duplikat sumber lain (aggregator
    /// sering mengulang node yang sama) — angka ini yang jujur untuk user.
    public var keptCount: Int
    /// Entri yang formatnya dikenali tapi protokolnya tidak didukung app.
    /// Dipisahkan dari `lastError` karena ini BUKAN kegagalan.
    public var unsupportedCount: Int
    /// Node yang ter-parse tapi korup / tidak mungkin dipakai (jaring D51),
    /// dipisahkan dari `unsupportedCount` sejak D62. Kolom Keterangan
    /// menampilkan keduanya karena artinya berbeda: yang satu berarti "app ini
    /// tidak bisa pakai protokol itu", yang lain berarti "entri itu sendiri
    /// rusak".
    public var unusableCount: Int

    /// D93 — grup yang isinya diisi tangan, bukan diunduh.
    ///
    /// Bedanya nyata dan Operational, bukan kosmetik:
    /// - `url` kosong, jadi `SourceResolver` tidak punya apa-apa untuk
    ///   dicoba; mencoba tetap akan menandai sumber ini `unavailable` dan
    ///   terlihat rusak padahal isinya baik-baik saja.
    /// - `refreshSource` / `refreshAll` **harus melewatinya**, bukan mengunduh
    ///   URL kosong.
    /// - Angkanya dihitung dari node yang ada, bukan dari hasil unduhan.
    public var isManualGroup: Bool

    public init(id: String = UUID().uuidString, name: String, url: String,
                isStarred: Bool = false, isEnabled: Bool = true, isCustom: Bool = false,
                nodeCount: Int = 0, lastUpdated: Date? = nil,
                status: SourceStatus = .unknown, lastError: String? = nil,
                keptCount: Int = 0, unsupportedCount: Int = 0,
                unusableCount: Int = 0, isManualGroup: Bool = false) {
        self.id = id; self.name = name; self.url = url
        self.isStarred = isStarred; self.isEnabled = isEnabled; self.isCustom = isCustom
        self.nodeCount = nodeCount; self.lastUpdated = lastUpdated
        self.status = status; self.lastError = lastError
        self.keptCount = keptCount; self.unsupportedCount = unsupportedCount
        self.unusableCount = unusableCount
        self.isManualGroup = isManualGroup
    }

    /// sources.json lama tidak punya `keptCount`/`unsupportedCount` — decode
    /// dua field baru itu harus opsional, kalau tidak seluruh daftar sumber
    /// milik user hilang hanya karena app diperbarui.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Semua field wajib pun pakai fallback. Satu entri yang rusak (mis.
        // `url` hilang) akan THROW keluar dari decode seluruh array ->
        // `JSONStore.load` mengembalikan `[]` -> `AppState` diam-diam kembali
        // ke daftar bawaan dan SEMUA sumber yang user tambah/ubah hilang.
        // Lebih baik satu baris aneh menjadi default daripada kehilangan
        // seluruh daftar (D61).
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        name = (try? c.decode(String.self, forKey: .name)) ?? NSLocalizedString("source_imported", comment: "")
        url = (try? c.decode(String.self, forKey: .url)) ?? ""
        isStarred = try c.decodeIfPresent(Bool.self, forKey: .isStarred) ?? false
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        isCustom = try c.decodeIfPresent(Bool.self, forKey: .isCustom) ?? false
        nodeCount = try c.decodeIfPresent(Int.self, forKey: .nodeCount) ?? 0
        lastUpdated = try c.decodeIfPresent(Date.self, forKey: .lastUpdated)
        // Sama seperti `language` di AppSettings: `decodeIfPresent` THROW saat
        // nilai enum tak dikenal, dan itu menghapus seluruh daftar sumber.
        status = (try? c.decode(SourceStatus.self, forKey: .status)) ?? .unknown
        lastError = try c.decodeIfPresent(String.self, forKey: .lastError)
        // `sources.json` lama tidak punya key ini — default `false`, jadi daftar
        // lama tidak akan tiba-tiba diperlakukan sebagai grup manual.
        isManualGroup = try c.decodeIfPresent(Bool.self, forKey: .isManualGroup) ?? false
        keptCount = try c.decodeIfPresent(Int.self, forKey: .keptCount) ?? 0
        unsupportedCount = try c.decodeIfPresent(Int.self, forKey: .unsupportedCount) ?? 0
        unusableCount = try c.decodeIfPresent(Int.self, forKey: .unusableCount) ?? 0
    }

    /// Sumber yang dipakai app saat DIPERLAUKAN — D92: tidak ada.
    ///
    /// Satu-satunya definisi "instalasi bersih" di seluruh app, dan itu
    /// disengaja: `AppState` mengambil nilai ini, dan tes mengambil nilai yang
    /// sama. Kalau suatu saat daftar bawaan dikembalikan lagi, satu tempat ini
    /// yang berubah — dan `testAppStartsWithNoSources` langsung gagal.
    public static let defaultSources: [VPNSubscriptionSource] = []

    /// Feed gratis yang dikumpulkan — untuk DITAWARKAN satu-klik di layar Sumber
    /// yang masih kosong, BUKAN untuk di-seed ke state.
    ///
    /// D92: dulu ini juga jadi nilai awal `AppState.sources`, jadi setiap
    /// instalasi baru langsung datang dengan 10 feed dan tabel server terisi
    /// sebelum user memilih apa pun. Itu bukan "bersih" — user dipaksa menerima
    /// pilihan yang bukan miliknya, dan yang mencentang bintang pun bukan
    /// keputusan mereka.
    ///
    /// Sekarang app mulai dari `[]`. Feed di sini hanya muncul sebagai
    /// tawaran; tidak ada yang ditambahkan sampai user menekan.
    ///
    /// PENTING: TIDAK ADA yang `isStarred: true`. `ServerSorter` mengunci
    /// sumber berbintang di urutan paling atas tanpa memandang kolom apa pun
    /// yang dipilih — termasuk kolom latensi yang jadi default. Mencentang
    /// bintang adalah keputusan user, bukan bawaan app (D61).
    public static let curated: [(name: String, url: String)] = [
        ("OpenProxyList", "https://openproxylist.com/v2ray/rawlist/subscribe"),
        ("Au1rxx", "https://raw.githubusercontent.com/Au1rxx/free-vpn-subscriptions/main/output/clash.yaml"),
        ("EbraSha", "https://raw.githubusercontent.com/ebrasha/free-v2ray-public-list/refs/heads/main/V2Ray-Config-By-EbraSha-All-Type.txt"),
        ("NodeFree", "https://nodefree.org/dy/2024/07/20240725.yaml"),
        ("Mfuu", "https://raw.githubusercontent.com/mfuu/v2ray/master/clash.yaml"),
        ("Anaer", "https://raw.githubusercontent.com/anaer/Sub/main/clash.yaml"),
        ("Ermaozi", "https://raw.githubusercontent.com/ermaozi/get_subscribe/main/subscribe/clash.yml"),
        ("Learnhard-cn", "https://cdn.jsdelivr.net/gh/vxiaov/free_proxies@main/clash/clash.provider.yaml"),
        ("OpenRunner", "https://freenode.openrunner.net/uploads/20240617-clash.yaml"),
        ("Xrayfree", "https://tt.vg/freeclash"),
    ]
}

public enum SourceStatus: String, Codable {
    case unknown, ok, failed, unavailable
}
