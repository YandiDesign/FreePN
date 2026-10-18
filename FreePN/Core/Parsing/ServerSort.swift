import Foundation

/// Urutan baris tabel Server.
///
/// Dulu tidak ada sama sekali: `resort` hanya mengurutkan "sumber berbintang
/// dulu, lalu nama", jadi user tidak pernah bisa mengelompokkan server menurut
/// sumber — padahal justru itu yang paling dibutuhkan saat membandingkan dua
/// feed. Sekarang setiap kolom bisa diklik.
public enum ServerSortKey: String, Codable, CaseIterable {
    case country, source, name, proto, latency, load
}

/// Arah urut + kolom aktif.
public struct ServerSort: Codable, Equatable {
    public var key: ServerSortKey
    public var ascending: Bool

    /// Default: **latensi tercepat lebih dulu** (D61).
    ///
    /// Dulu default-nya kolom Sumber menaik — warisan dari masa tabel belum
    /// bisa diurutkan sama sekali. User mengharapkan yang tercepat di atas
    /// begitu hasil Ping masuk, bukan daftar yang dikelompokkan per feed:
    /// yang dicarinya "server paling cepat istilah sekarang", bukan "server
    /// milik feed mana".
    ///
    /// `ascending = true` untuk kolom latensi berarti **nilai terkecil di
    /// atas** = milidetik paling rendah = tercepat.
    ///
    /// Versi lama memakai `ascending: false` dengan keyakinan bahwa "turun"
    /// berarti tercepat pada kolom latensi. Itu tidak pernah benar —
    /// `ServerSorter.sort` menerapkan arah apa adanya
    /// (`ascending ? order < 0 : order > 0`), jadi `false` benar-benar
    /// menaruh yang PALING LAMBAT di atas, persis kebalikan dari maksudnya.
    /// Konvensi itu juga merusak panah: untuk menampilkan yang tercepat di
    /// atas, panahnya harus menunjuk ke bawah, padahal user mengira panah
    /// bawah berarti nilai besar.
    public init(key: ServerSortKey = .latency, ascending: Bool = true) {
        self.key = key
        self.ascending = ascending
    }

    /// Klik kolom yang sama membalik arah; klik kolom lain selalu mulai dari
    /// arah menaik.
    ///
    /// "Menaik" untuk tiap kolom berarti hal yang paling berguna bagi user:
    /// teks A→Z, negara A→Z, dan — yang penting — kolom angka dari nilai
    /// terkecil: latensi tercepat dulu, beban paling ringan dulu.
    public mutating func toggle(_ newKey: ServerSortKey) {
        if key == newKey {
            ascending.toggle()
        } else {
            key = newKey
            ascending = true
        }
    }

    public var arrow: String { ascending ? "arrow.up" : "arrow.down" }
}

public enum ServerSorter {
    /// Urutkan node sesuai `sort`.
    ///
    /// Node tanpa nilai selalu turun ke bawah, apa pun arahnya. Alasannya:
    /// server yang belum di-ping atau lokasinya belum diketahui bukan
    /// "paling lambat" atau "terakhir" — dia belum punya nilai. Kalau ikut
    /// diurutkan, daftar 16.000 node akan penuh baris "—" yang terlihat
    /// seperti hasil posisi terakhir yang sah, padahal itu "belum
    /// diketahui".
    ///
    /// Murni & nonisolated supaya bisa diuji tanpa actor.
public static func sort(_ nodes: [ProxyNode], by sort: ServerSort,
                            ping: [String: PingResult],
                            sourceNames: [String: String],
                            starredSources: Set<String> = []) -> [ProxyNode] {
        let worst = ping.values.compactMap(\.webLatencyMs).max() ?? 0

        // Schwartzian transform (D61).
        //
        // Comparator lama memanggil `localizedCaseInsensitiveCompare` — yang
        // kolasi Foundation, ~50-100× lebih lambat dari perbandingan byte —
        // untuk setiap pasangan yang nilai utamanya seri, DAN
        // `String(a.sourceID.prefix(8))` (alokasi baru) untuk sumber yang
        // tak dikenal. Pada 16.000 node itu ratusan ribu pemanggilan
        // collation, DAN semuanya jalan di main thread.
        //
        // Semua kunci yang mahal dihitung SEKALI per node di sini; comparator
        // lalu hanya membandingkan `String` yang sudah di-lowercase dengan `<`.
        //
        // Untuk nama ASCII (mayoritas feed gratis) `lowercased()` memberi urutan
        // yang sama dengan `localizedCaseInsensitiveCompare`. Untuk nama
        // non-ASCII ada beda, dan itu memang tidak bisa dihindari tanpa
        // mengulang kolasi — yang justru jadi biaya yang sedang dihapus di
        // sini.
        var keys = [Key]()
        keys.reserveCapacity(nodes.count)
        for n in nodes {
            let srcName = sourceNames[n.sourceID] ?? String(n.sourceID.prefix(8))
            let result = ping[n.id]
            keys.append(Key(
                node: n,
                starred: starredSources.contains(n.sourceID),
                unknown: isUnknown(n, key: sort.key, ping: ping, worst: worst),
                lowerName: n.name.lowercased(),
                sourceName: srcName.lowercased(),
                countryCode: n.countryCode?.uppercased(),
                proto: n.proto.rawValue,
                bestMs: result?.bestMs,
                loadPct: (result?.webLatencyMs).flatMap { worst > 0 ? $0 * 100 / max(1, worst) : nil }
            ))
        }

        return keys.sorted { a, b in
            // Sumber berbintang selalu di kelompok atas. Ini perilaku lama
            // (`resort` lama memakai `isStarred` sebagai kunci pertama) dan
            // tidak bergantung pada kolom mana pun yang dipilih — mencentang
            // sumber di menu Sumber berarti "ini yang saya pakai", jadi
            // menaruhnya di bawah yang lain akan melawan niat user.
            if a.starred != b.starred { return a.starred }

            // Yang belum diketahui TIDAK ikut aturan arah. Ini harus dicek
            // sebelum `ascending` diterapkan: kalau "`nil` selalu di akhir"
            // hanya ditulis sebagai perbandingan biasa, `ascending == false`
            // akan membinverse dan justru melempar yang belum diketahui ke
            // paling atas — persis kebalikan dari yang diinginkan.
            if a.unknown != b.unknown { return b.unknown }

            if !a.unknown {
                let order = compareKeys(a, b, by: sort.key)
                if order != 0 { return sort.ascending ? order < 0 : order > 0 }
            }
            // Tie-break: nama selalu menaik, biar urutannya stabil dan tidak
            // "berganti tempat" tiap refresh.
            if a.lowerName != b.lowerName { return a.lowerName < b.lowerName }
            return a.node.id < b.node.id
        }.map(\.node)
    }

    /// Bandingkan dua kunci yang SUDAH dipre-komputasi.
    private static func compareKeys(_ a: Key, _ b: Key, by key: ServerSortKey) -> Int {
        switch key {
        case .name:
            return a.lowerName == b.lowerName ? 0 : (a.lowerName < b.lowerName ? -1 : 1)
        case .source:
            return a.sourceName == b.sourceName ? 0 : (a.sourceName < b.sourceName ? -1 : 1)
        case .country:
            return compareOptional(a.countryCode, b.countryCode)
        case .proto:
            return compareOptional(a.proto, b.proto)
        case .latency:
            return compareOptional(a.bestMs, b.bestMs)
        case .load:
            return compareOptional(a.loadPct, b.loadPct)
        }
    }

    /// Kunci yang sudah dipre-komputasi untuk setiap node (Schwartzian).
    ///
    /// Dipisah ke level tipe supaya `compareKeys` — yang Comparator-nya juga
    /// statis — bisa memakainya sebagai tipe.
    private struct Key {
        let node: ProxyNode
        let starred: Bool
        let unknown: Bool
        let lowerName: String
        let sourceName: String
        let countryCode: String?
        let proto: String
        let bestMs: Int?
        /// Persentase beban, sudah dihitung dari `webMs`/`worst` saat kunci
        /// dibuat — tidak ada lagi fungsi `load` yang dideklarasikan di dalam
        /// `case` switch.
        let loadPct: Int?
    }

    /// True kalau nilai node untuk kolom ini belum diketahui.
    ///
    /// Hanya tiga kolom yang bisa "belum diketahui": negara (node tanpa
    /// lokasi), latensi (belum di-ping / dead-end), dan beban (ikut latensi).
    static func isUnknown(_ n: ProxyNode, key: ServerSortKey,
                          ping: [String: PingResult], worst: Int) -> Bool {
        switch key {
        case .country:
            return (n.countryCode ?? "").isEmpty
        case .latency:
            return ping[n.id]?.bestMs == nil
        case .load:
            return ping[n.id]?.webLatencyMs == nil || worst <= 0
        case .name, .source, .proto:
            return false
        }
    }

    /// -1: `a` sebelum `b`. 0: seri. Hanya dipanggil untuk pasangan yang
    /// keduanya bernilaidiketahui.
    static func compare(_ a: ProxyNode, _ b: ProxyNode, by key: ServerSortKey,
                        ping: [String: PingResult],
                        sourceNames: [String: String], worst: Int = 0) -> Int {
        switch key {
        case .name:
            let c = a.name.localizedCaseInsensitiveCompare(b.name)
            return c == .orderedSame ? 0 : (c == .orderedAscending ? -1 : 1)
        case .source:
            let an = sourceNames[a.sourceID] ?? String(a.sourceID.prefix(8))
            let bn = sourceNames[b.sourceID] ?? String(b.sourceID.prefix(8))
            let c = an.localizedCaseInsensitiveCompare(bn)
            return c == .orderedSame ? 0 : (c == .orderedAscending ? -1 : 1)
        case .country:
            return compareOptional(a.countryCode?.uppercased(), b.countryCode?.uppercased())
        case .proto:
            return compareOptional(a.proto.rawValue, b.proto.rawValue)
        case .latency:
            return compareOptional(ping[a.id]?.bestMs, ping[b.id]?.bestMs)
        case .load:
            // Beban relatif: semakin kecil latency semakin ringan bebannya.
            func load(_ n: ProxyNode) -> Int? {
                guard let ms = ping[n.id]?.webLatencyMs, worst > 0 else { return nil }
                return ms * 100 / max(1, worst)
            }
            return compareOptional(load(a), load(b))
        }
    }

    /// `nil` selalu di paling bawah, apa pun arahnya (lihat catatan di atas).
    private static func compareOptional<T: Comparable>(_ a: T?, _ b: T?) -> Int {
        switch (a, b) {
        case (nil, nil): return 0
        case (nil, _): return 1
        case (_, nil): return -1
        case let (x?, y?): return x == y ? 0 : (x < y ? -1 : 1)
        }
    }
}