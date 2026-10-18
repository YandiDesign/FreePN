import Foundation
import Combine
import SwiftUI

/// Kemajuan Ping All. Satu tahap, satu bar.
public struct PingProgress: Equatable {
    public var isRunning: Bool = false
    /// Total node yang akan diuji pada putaran ini.
    public var total: Int = 0
    /// Node yang sudah selesai diuji akses internet.
    public var done: Int = 0
    /// Jumlah node yang terbukti benar-benar bisa akses internet.
    public var online: Int = 0
}

/// Satu perubahan alamat MAC yang tercatat.
///
/// Disimpan supaya layar MAC Address bisa menampilkan riwayat yang jujur.
/// Tanpa ini, kolom "Waktu" hanya bisa diisi timestamp sekarang — yang akan
/// terlihat benar padahal setiap baris selalu bilang "baru saja".
public struct MACHistoryEntry: Codable, Identifiable, Hashable {
    public enum Kind: String, Codable {
        case custom   // MAC kustom yang diketik user
        case random   // diacak
        case restore  // dikembalikan ke alamat keras
        case auto     // diubah otomatis (acak saat connect / restore saat disconnect)

        /// Urutan pilihan filter di layar MAC. `auto` tidak ditampilkan
        /// sebagai chip — perubahan otomatis tetap tercatat dan terlihat di
        /// daftar, jadi tidak hilang.
        public static var allCasesForFilter: [Kind] { [.custom, .random, .restore] }
    }
    public var id: UUID
    public var mac: String
    public var kind: Kind
    /// Nama interface, mis. "en0".
    public var interface: String
    public var at: Date

    public init(id: UUID = UUID(), mac: String, kind: Kind, interface: String, at: Date = Date()) {
        self.id = id; self.mac = mac; self.kind = kind; self.interface = interface; self.at = at
    }
}

@MainActor
public final class AppState: ObservableObject {
    // Performance: `filteredNodes` ialah hasil sort 16.000 node (O(n log n))
    // yang DULUNYA dihitung ulang di SETIAK render (computed property), dan
    // `filteredNodes` diakses beberapa kali per body view (kolom, footer,
    // Quick Connect) sehingga satu render = beberapa sort penuh. Sekarang
    // hasilnya di-cache dan cache hanya dibuang saat INPUT-nyanya berubah
    // (dep di bawah), bukan saat render.
    @Published public var nodes: [ProxyNode] = [] { didSet { invalidateNodeIndex() } }
    /// D92: KOSONG, bukan 10 feed bawaan. Instalasi baru harus benar-benar
    /// bersih — app yang sudah punya daftar server sebelum user memilih apa
    /// pun bukan "fresh install", dan feed mana pun yang otomatis aktif
    /// adalah keputusan yang diambil di belakang user. Daftar lengkap tersedia
    /// sebagai tawaran satu-klik di layar Sumber yang masih kosong.
    @Published public var sources: [VPNSubscriptionSource] = VPNSubscriptionSource.defaultSources {
        didSet { invalidateDerived() }
    }
    @Published public var ping: [String: PingResult] = [:] { didSet { invalidateDerived() } }
    @Published public var favorites: Set<String> = []
    @Published public var selectedNodeID: String? { didSet { invalidateDerived() } }
    @Published public var split: SplitTunnelConfig = SplitTunnelConfig()
    @Published public var settings: AppSettings = AppSettings() { didSet { invalidateDerived() } }
    // MARK: - Log ping (D93)

    /// Riwayat pengujian terakhir, dipotong oldest-first.
    ///
    /// Dipotong, bukan disimpan semua: satu putaran atas 20.000 node menulis
    /// 20.000 baris, dan log yang hanya muat satu putaran terakhir sudah cukup
    /// untuk menjawab "kenapa yang ini mati".
    @Published public private(set) var pingLog: [PingLogEntry] = []

    /// Ringkasan putaran ping yang sedang berjalan / terakhir selesai.
    @Published public private(set) var pingSummary: PingRunSummary? = nil

    /// Batas baris log. 1.000 cukup untuk satu putaran penuh tanpa membuat
    /// array tumbuh tanpa henti.
    nonisolated public static let pingLogLimit = 1_000

    /// Catat satu baris log, memotong yang paling lama kalau penuh.
    public func logPing(_ entry: PingLogEntry) {
        pingLog.append(entry)
        if pingLog.count > Self.pingLogLimit {
            pingLog.removeFirst(pingLog.count - Self.pingLogLimit)
        }
    }

    /// Catat peristiwa tingkat sesi — hal yang TIDAK terlihat di verdict per
    /// node. "Core gagal start" dan "semua node ditolak config" keduanya
    /// berakhir sebagai "tidak ada yang hidup", dan tanpa baris seperti ini
    /// keduanya terlihat sama saja.
    public func logPingSession(_ message: String) {
        logPing(PingLogEntry(kind: .session, nodeName: message))
    }

    public func clearPingLog() {
        pingLog.removeAll()
    }

    @Published public var isRefreshing: Bool = false
    @Published public var searchText: String = "" { didSet { invalidateDerived() } }
    @Published public var protoFilter: NodeProtocol? = nil { didSet { invalidateDerived() } }
    /// Urutan tabel Server. Default "sumber" — persis yang hilang setelah redesign.
    /// Layar aktif di sidebar.
    ///
    /// Dipindah ke sini (bukan `@State` di `ContentView`) karena menu
    /// Navigate ⌘1…⌘6 harus bisa mengubahnya, dan `.commands` hanya bisa
    /// dipasang pada `Scene` — bukan pada `View`.
    @Published public var navigation: String = "connect"

    @Published public var sort = ServerSort() { didSet { invalidateDerived() } }
    @Published public var sourceFilter: String? = nil { didSet { invalidateDerived() } }
    @Published public var hasOnboarded: Bool = false
    /// Riwayat perubahan alamat MAC (terbaru dulu, dibatasi `macHistoryLimit`).
    @Published public var macHistory: [MACHistoryEntry] = []
    /// Kemajuan Ping All per batch (lihat `pingAll`).
    @Published public var pingProgress = PingProgress()
    /// True kalau Ping All sedang menguji subset (filter aktif), bukan semua.
    @Published public var pingScopeFiltered = false
    /// Pesan singkat saat Ping All tidak bisa jalan (mis. filter tak kecocokan).
    @Published public var pingNotice: String? = nil
    /// Ditetakkan `cancelPingAll()`. Tidak `@Published` karena tidak pernah
    /// dibaca view — hanya oleh loop refill `pingAllFast`, yang berjalan di
    /// actor ini juga, jadi perubahan field biasa langsung terlihat.
    private var pingFastCancelled = false
    /// True selama pengayaan negara (resolusi DNS untuk host domain) berjalan.
    @Published public var isEnrichingCountries = false

    public let connection = ConnectionManager()
    public let health = HealthChecker()

    /// Riwayat perubahan aturan split, newest-last.
    ///
    /// Disimpan (bukan hanya di memori) karena gunanya justru untuk dicari
    /// belakangan: "kenapa app saya tidak lewat VPN tadi?" baru bisa dijawab
    /// kalau jejaknya masih ada setelah app ditutup.
    @Published public var splitChanges: [SplitChangeLog.Entry] = []

    /// Catat satu perubahan aturan split.
    ///
    /// `isDomain` menentukan ENTRI mana yang dipakai, bukan memodifikasi
    /// entri: satu perubahan domain dan satu perubahan app punya teks
    /// penjelasan berbeda, jadi keduanya harus dibedakan sejak awal.
    public func recordSplitChange(appName: String, bundlePath: String,
                                  mode: SplitMode = .exclusive,
                                  action: SplitChangeLog.Action,
                                  isDomain: Bool = false) {
        let entry = SplitChangeLog.Entry(appName: appName, bundlePath: bundlePath,
                                         mode: mode, action: action, isDomain: isDomain)
        splitChanges.append(entry)
        if splitChanges.count > SplitChangeLog.limit {
            splitChanges.removeFirst(splitChanges.count - SplitChangeLog.limit)
        }
        SplitChangeLog.save(splitChanges)
    }

    /// Wrapper tipis untuk `SplitMode.usesVPN` — definisi tunggal-nya
    /// hidup di Shared supaya bisa diuji tanpa actor.
    public nonisolated static func usesVPN(appIsListed: Bool, mode: SplitMode) -> Bool {
        mode.usesVPN(appIsListed: appIsListed)
    }
    private let service = SubscriptionService()
    /// Satu-satunya cara menguji node: benar-benar menembak `generate_204`
    /// lewat node tersebut. Tidak ada lagi tahap ping TCP sebelumnya (D50).
    public let probe = InternetProbe()
    /// Pengatur beban CPU: menentukan berapa banyak kerja paralel yang aman.
    public let cpu = CPUGovernorMonitor()

    private let nodesStore = JSONStore<[ProxyNode]>(filename: "nodes.json")
    private let sourcesStore = JSONStore<[VPNSubscriptionSource]>(filename: "sources.json")
    private let favStore = JSONStore<[String]>(filename: "favorites.json")
    private let settingsStore = JSONStore<AppSettings>(filename: "settings.json")
    private let splitStore = JSONStore<SplitTunnelConfig>(filename: "split.json")
    private let macHistoryStore = JSONStore<[MACHistoryEntry]>(filename: "mac_history.json")

    /// PERFORMA (D61): keenam store dibaca ASYNC lewat `JSONStore.loadAsync`.
    ///
    /// Sebelumnya enam `queue.sync` + decode JSON berjalan di `@MainActor init`:
    /// `nodes.json` untuk 16.000 node bisa beberapa MB, jadi app terlihat
    /// membeku saat dibuka sebelum jendela pertama sempat tampil. Sekarang
    /// `init` hanya menyiapkan state default dan selesai seketika; data masuk
    /// lewat `loadPersistedState()` dan setiap `@Published` yang berubah
    /// meng-invalidate dirinya sendiri seperti biasa.
    public init() {
        self.hasOnboarded = UserDefaults.standard.bool(forKey: "freepn.onboarded")
        applyUIScale()
        applyCPUPolicy()
        applyLanguage()
        relayChildChanges()
        // Riwayat split dibaca sinkron dan kecil (maks 100 entri, ~30 KB).
        // Tidak lewat `hydrationTask` seperti store lain karena panel log di
        // Split Tunneling bisa terbuka sebelum hidrasi selesai, dan log yang
        // setengah muncul lebih membingungkan daripada yang telat 1 frame.
        self.splitChanges = SplitChangeLog.load()
        purgeLegacyCache()
        loadPersistedState()
    }

    /// Buang cache feed lama (`subcache/`) sekali saja, di luar main actor.
    ///
    /// D90: app tidak pernah menulis folder itu lagi — feed selalu dari
    /// jaringan — tapi versi lama meninggalkan 400+ berkas dari sumber yang
    /// sudah dihapus (±190 MB) dan tidak pernah membersihkannya. Menghapus
    /// 400 berkas di `@MainActor init` akan menahan frame pertama, jadi
    /// jalannya dititipkan ke `Task.detached` dengan prioritas `.utility`.
    ///
    /// URL-nya disalin di sini (actor utama) supaya worker tidak membaca
    /// `AppStorage.overrideDirectory` — `static var` yang bisa diganti test
    /// kapan saja. Kegagalan sengaja diabaikan: tanpa cache, app tetap jalan;
    /// yang hilang cuma ±190 MB yang tidak pernah terpakai lagi.
    private func purgeLegacyCache() {
        let dir = AppStorage.legacyCacheDirectory
        Task.detached(priority: .utility) {
            AppStorage.purgeLegacySubscriptionCache(at: dir)
        }
    }

    /// Baca semua store dari disk di luar main actor, lalu pasang ke state.
    private func loadPersistedState() {
        hydrationTask = Task { [weak self] in
            guard let self else { return }
            async let savedNodes = nodesStore.loadAsync(defaultValue: [ProxyNode]())
            async let savedSources = sourcesStore.loadAsync(defaultValue: [VPNSubscriptionSource]())
            async let savedFavorites = favStore.loadAsync(defaultValue: [String]())
            async let savedSettings = settingsStore.loadAsync(defaultValue: AppSettings())
            async let savedSplit = splitStore.loadAsync(defaultValue: SplitTunnelConfig())
            async let savedMAC = macHistoryStore.loadAsync(defaultValue: [MACHistoryEntry]())

            let (n, src, fav, cfg, sp, mac) = await (savedNodes, savedSources, savedFavorites,
                                                      savedSettings, savedSplit, savedMAC)
            guard self.isHydrating == false else { return }
            self.isHydrating = true
            defer { self.isHydrating = false }

            self.nodes = n
            if !src.isEmpty { self.sources = src }
            self.favorites = Set(fav)
            self.settings = cfg
            // Migrasi: inklusif-kosong = tidak ada trafik lewat VPN (bug
            // laporan "tersambung tapi IP tak berubah"). Kembalikan ke
            // eksklusif (VPN penuh).
            var split = sp
            // `hasAnyActiveSelection`, bukan `activeApps.isEmpty`: sejak domain
            // jadi bagian split, daftar app kosong tidak lagi berarti bypass
            // semua. Tanpa baris ini, user yang sengaja memilih mode inklusif
            // HANYA untuk domain akan diminta startup lalu dikembalikan ke
            // eksklusif tanpa sebab — persis gejala "aturannya tidak nyala".
            if split.mode == .inclusive && !split.hasAnyActiveSelection {
                split = SplitTunnelConfig(mode: .exclusive)
                splitStore.save(split)
            }
            self.split = split
            self.macHistory = mac
            self.rebuildSourceNames()
            self.rebuildNodeIndex()
            self.connection.autoReconnect = cfg.autoReconnect
            self.applyUIScale()
            self.applyCPUPolicy()
            self.applyLanguage()
        }
    }

    /// Hitung ulang `keptCount` tanpa mengubah `nodes`.
    ///
    /// `resort(all:)` juga menulis ulang `nodes` (dedup + urutan), dan itu
    /// berlebihan untuk perbaikan label: yang perlu diperbarui cuma angka per
    /// sumber supaya kolom "Keterangan" dan filter dropdown tidak lagi
    /// menampilkan "0 / semua duplikat".
    private func resortCountsOnly() {
        var kept: [String: Int] = [:]
        for n in nodes { kept[n.sourceID, default: 0] += 1 }
        var srcs = sources
        for i in srcs.indices { srcs[i].keptCount = kept[srcs[i].id] ?? 0 }
        sources = srcs
    }

    /// Task pembacaan store yang sedang berjalan.
    ///
    /// INI YANG PERBAIKAN D66. Sebelumnya `isHydrating` hanya dibaca DI DALAM
    /// `loadPersistedState` sendiri, jadi tidak ada satu pun penulis lain yang
    /// pernah menunggu — komentar di dekatnya mengklaim `refreshAll` menunggu,
    /// dan itu tidak pernah terjadi.
    ///
    /// Akibatnya `refreshAll()` yang dipicu `.onAppear` bisa berjalan sebelum
    /// `sources`/`nodes` dari disk terpasang, lalu ia mengambil snapshot
    /// `builtIn()` — yang ID-nya di-mint acak TIAP PELUNCURAN. Node hasil
    /// refresh itu ditulis dengan ID yang tidak pernah ada di `sources.json`
    /// milik user. Gejalanya persis yang dilaporkan: kolom Source menampilkan
    /// `EA5A840F` (potongan UUID) dan filter sumber tidak menghasilkan apa pun,
    /// karena tidak ada satu pun node yang `sourceID`-nya cocok dengan ID
    /// sumber yang terdaftar.
    private var hydrationTask: Task<Void, Never>?

    /// Tunggu sampai state dari disk terpasang.
    ///
    /// WAJIB dipanggil sebelum operasi yang membaca atau menulis `sources`/
    /// `nodes`. Tanpa itu, operasi tersebut berjalan terhadap daftar bawaan
    /// dan menimpa data user dengan UUID baru.
    public func waitForHydration() async {
        await hydrationTask?.value
    }

    /// True selama `loadPersistedState` masih menempelkan hasil baca.
    /// Penulis lain (mis. `refreshAll`) menunggu agar tidak menimpa data yang
    /// baru saja dimuat.
    private var isHydrating = false

    private var cancellables = Set<AnyCancellable>()

    /// Teruskan perubahan ObservableObject anak ke diri sendiri.
    ///
    /// MASALAH "TIDAK REALTIME": semua view observing `AppState` lewat
    /// `@EnvironmentObject`, tapi `connection` (status, errorMessage, timer
    /// byte), `health`, dan `probe` adalah ObservableObject TERPISAH. SwiftUI
    /// hanya invalidated oleh objek yang diamati — jadi klik Sambung/Putus
    /// tidak mengubah apa-apa di layar sampai user pindah tab (barulah view
    /// dibangun ulang). Forward `objectWillChange` menutup celah itu.
    ///
    /// PERFORMA (D61): forwarding PENUH `objectWillChange` dari `connection`
    /// berarti SETIAP perubahan trafik (tiap 2 detik, selama terhubung)
    /// membatalkan seluruh pohon view — termasuk tabel 16.000 baris dan peta
    /// dunia yang sama sekali tidak bergantung pada angka byte. Jadi yang
    /// diteruskan hanya field yang benar-benar dibaca seluruh UI
    /// (`status`, `errorMessage`, `connectedSince`, `lastExitIP`); angka trafik
    /// BRITIS observe `ConnectionManager` langsung lewat `@ObservedObject`
    /// (lihat `TrafficCard`), jadi hanya kartu itu yang menggambar ulang.
    private func relayChildChanges() {
        relayConnection()
        relay(health)
        relay(probe)
    }
    private func relay<C: ObservableObject>(_ child: C) {
        child.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    /// Relay khusus `connection`: hanya perubahan status/error/ekspektasi yang
    /// dibaca seluruh UI, bukan angka trafik yang berubah tiap 2 detik.
    ///
    /// Pakai `@Published` projected value (`$status`), bukan
    /// `objectWillChange`: publisher latter terbit SEBELUM nilai baru terpasang
    /// sehingga tidak bisa dipakai memetakan "apa yang berubah".
    /// `removeDuplicates()` terjawab di sini, jadi trafik yang nilainya sama
    /// tidak pernah sampai ke SwiftUI sama sekali.
    private func relayConnection() {
        connection.$status
            .removeDuplicates()
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        connection.$errorMessage
            .removeDuplicates()
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        connection.$connectedSince
            .removeDuplicates()
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        connection.$lastExitIP
            .removeDuplicates()
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    public var selectedNode: ProxyNode? {
        nodeIndex[selectedNodeID ?? ""]
    }

    /// Indeks `id -> node` untuk pencarian O(1).
    ///
    /// `selectedNode` dipanggil dari dalam `body` (node yang direkomendasikan
    /// di kartu utama), jadi linear scan atas 16.000 node berjalan tiap frame —
    /// dan sekali lagi di `recommendedNode` (D61).
    private var nodeIndex: [String: ProxyNode] = [:]
    private func rebuildNodeIndex() {
        nodeIndex = Dictionary(nodes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// Nama sumber milik `sourceID` ("" / UUID asing = "Impor" / id mentah).
    /// Dipakai kolom Sumber di Server — jangan mencari linear per baris (7000+ baris).
    public func sourceName(for id: String) -> String {
        if id.isEmpty { return NSLocalizedString("source_imported", comment: "") }
        return sourceNames[id] ?? String(id.prefix(8))
    }
    private var sourceNames: [String: String] = [:]
    private var sourceURLs: [String: String] = [:]
    private func rebuildSourceNames() {
        sourceNames = Dictionary(sources.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        sourceURLs = Dictionary(sources.map { ($0.id, $0.url) }, uniquingKeysWith: { a, _ in a })
    }

    /// URL feed milik `sourceID`, untuk tooltip "node ini datang dari mana".
    ///
    /// Id asing (node yang diimpor sebelum sumbernya ada) jatuh ke id-nya
    /// sendiri — persis seperti `sourceName(for:)`.
    public func sourceURL(for id: String) -> String {
        sourceURLs[id] ?? id
    }

    /// Berapa banyak entri riwayat MAC yang disimpan. Cukup untuk melihat
    /// pola pemakaian tanpa membiarkan berkas tumbuh tanpa batas.
    public static let macHistoryLimit = 100

    /// Sisipkan satu entri di depan daftar lalu potong yang paling lama.
    ///
    /// Murni & nonisolated supaya bisa diuji tanpa actor dan tanpa menyentuh
    /// berkas. Mengembalikan daftar BARU — `AppState` yang memindahkan isinya.
    public nonisolated static func insertingMACChange(
        _ entry: MACHistoryEntry,
        into history: [MACHistoryEntry],
        limit: Int = macHistoryLimit) -> [MACHistoryEntry] {
        var out = history
        out.insert(entry, at: 0)
        if out.count > limit { out.removeLast(out.count - limit) }
        return out
    }

    /// Catat satu perubahan MAC yang benar-benar berhasil.
    public func recordMACChange(mac: String, kind: MACHistoryEntry.Kind, interface: String) {
        // Alamat kosong tidak dicatat: entri tanpa nilai tidak berguna dan
        // hanya menambah derau di daftar.
        guard !mac.isEmpty else { return }
        macHistory = Self.insertingMACChange(
            MACHistoryEntry(mac: mac, kind: kind, interface: interface), into: macHistory)
        macHistoryStore.save(macHistory)
    }

    /// Simpan SEMUA state ke disk.
    ///
    /// HANYA untuk peristiwa yang benar-benar bisa mengubah apa pun (mis. selesai
    /// refresh, selesai sort setelah ping). Untuk perubahan satu field —
    /// toggle pengaturan, ganti nama sumber, centang favorit — panggil
    /// `persist(settings:)` / `persist(split:)` / dst. supaya tidak
    /// menulis ulang `nodes.json` yang bisa ber-MB (D61).
    public func persist() {
        persistSettingsSideEffects()
        UserDefaults.standard.set(hasOnboarded, forKey: "freepn.onboarded")
        nodesStore.save(nodes); sourcesStore.save(sources)
        favStore.save(Array(favorites)); settingsStore.save(settings)
        splitStore.save(split); macHistoryStore.save(macHistory)
        rebuildSourceNames()
    }

    /// Simpan hanya `settings.json` + efek samping yang bergantung padanya
    /// (skala UI, jatah CPU, jadwal refresh, onboarding).
    ///
    /// Dipakai setiap toggle pengaturan. Sebelumnya semuanya lewat `persist()`
    /// penuh: satu centang "Tampilkan port" menulis ulang seluruh `nodes.json`
    /// (16.000 node) — dan slider CPU-share memanggilnya PULUHAN KALI per
    /// detik saat di-drag.
    public func persist(onlySettings: Bool) {
        guard onlySettings else { return }
        settingsStore.save(settings)
        persistSettingsSideEffects()
    }

    public func persist(onlySplit: Bool) {
        guard onlySplit else { return }
        splitStore.save(split)
    }

    public func persist(onlyNodes: Bool) {
        guard onlyNodes else { return }
        nodesStore.save(nodes)
    }

    public func persist(onlySources: Bool) {
        guard onlySources else { return }
        sourcesStore.save(sources)
        rebuildSourceNames()
    }

    public func persist(onlyFavorites: Bool) {
        guard onlyFavorites else { return }
        favStore.save(Array(favorites))
    }

    public func persist(onlyMACHistory: Bool) {
        guard onlyMACHistory else { return }
        macHistoryStore.save(macHistory)
    }

    /// Efek samping yang bergantung pada `settings` saja. Dipisah supaya
    /// `applyUIScale()`/`applyCPUPolicy()` tidak lagi jalan di setiap
    /// `persist()` — keduanya menulis state global dan memulai/menghentikan
    /// timer CPU, bukan hal yang perlu terjadi saat user centang favorit.
    private func persistSettingsSideEffects() {
        applyUIScale()
        applyCPUPolicy()
        if settings.autoRefreshHours != lastRefreshHours {
            lastRefreshHours = settings.autoRefreshHours
            scheduleAutoRefresh()
        }
        UserDefaults.standard.set(hasOnboarded, forKey: "freepn.onboarded")
    }

    /// Terapkan jatah CPU ke governor. Batas atas dihitung dari core performa
    /// mesin ini, jadi Mac weaker tetap aman, Mac kuat otomatis lebih banyak.
    public func applyCPUPolicy() {
        cpu.share = Double(settings.cpuSharePercent) / 100.0
        cpu.isAdaptive = settings.adaptiveConcurrency
        cpu.recalculateCeilings()
        if pingProgress.isRunning { cpu.start() } else { cpu.stop() }
    }

    /// Salin skala UI ke DesignSystem. Semua text app melewati `Theme.font(...)`,
    /// jadi satu angka ini yang mengatur besar teks di seluruh tampilan.
    public func applyUIScale() {
        Theme.uiScale = CGFloat(AppUIScale.factor(settings.uiScalePercent))
    }

    private var refreshTimer: Timer?
    private var lastRefreshHours: Int = -1

    /// Dipanggil sekali saat UI utama muncul: fetch otomatis bila kosong + timer berkala.
    public func startAutoRefreshIfNeeded() {
        lastRefreshHours = settings.autoRefreshHours
        scheduleAutoRefresh()
        // `nodes` masih kosong SELALU di titik ini — `loadPersistedState` baru
        // mulai dan baru selesai nanti. Tanpa await di sini, cabang "fetch
        // otomatis" selalu diambil dan berjalan melawan `builtIn()`.
        // Setelah hydration, keputusannya diulang dengan data yang benar.
        Task { [weak self] in
            guard let self else { return }
            await self.waitForHydration()
            if self.nodes.isEmpty {
                await self.refreshAll()
            } else if self.nodes.contains(where: { ($0.countryCode ?? "").isEmpty }) {
                // Naik versi: `nodes.json` yang sudah ada belum punya negara, dan
                // kolom Country akan kosong sampai user menekan Refresh sendiri.
                // Pengayaan jauh lebih murah daripada refresh — tanpa satu pun
                // unduhan feed — jadi jalankan saja diam-diam saat app dibuka.
                await self.enrichCountries()
            }
        }
    }

    public func scheduleAutoRefresh() {
        refreshTimer?.invalidate(); refreshTimer = nil
        let h = settings.autoRefreshHours
        guard h > 0 else { return }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(h) * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.refreshAll() }
        }
    }

    public func applyLanguage() {
        if let langs = L10n.appleLanguages(for: settings.language) {
            UserDefaults.standard.set(langs, forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
    }

    // MARK: - Refresh (inkremental: tiap sumber selesai langsung tampil)

    /// Refresh yang sedang berjalan, supaya bisa dibatalkan.
    ///
    /// D91: sebelumnya tidak ada handle sama sekali — `Task.isCancelled` di
    /// `SubscriptionService.fetchOne` adalah kode mati karena tidak ada yang
    /// pernah membatalkan task-nya. Satu-satunya jalan keluar user adalah
    /// menutup app.
    private var refreshTask: Task<Void, Never>?

    /// Progres unduhan yang tampil di layar: "3/15" per sumber.
    ///
    /// D91: tanpa ini, menekan segarkan per baris memberi tahu user persis
    /// nol selama bisa 3 menit 45 detik. Indikator yang tidak bergerak bukan
    /// indikator — dia cuma memberi tahu bahwa ada sesuatu yang salah.
    @Published public var refreshProgress: String? = nil

    /// Batalkan refresh yang sedang berjalan.
    public func cancelRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
        refreshProgress = nil
        isRefreshing = false
    }

    public func refreshAll() async {
        // WAJIB: tanpa ini, snapshot `sources` bisa diambil dari daftar
        // placeholder yang belum selesai dimuat dari disk (D66).
        await waitForHydration()
        // D92: tanpa sumber aktif, tidak ada yang bisa diunduh. Refresh kosong
        // hanya menjalankan satu putaran penuh `resort` + `enrichCountries`
        // atas nol node — dan di layar itu terbaca sebagai "sedang bekerja"
        // padahal tidak ada yang terjadi.
        guard sources.contains(where: { $0.isEnabled }) else { return }
        // Jangan tumpuk dua refresh bersamaan (mis. auto + manual).
        if isRefreshing { return }
        isRefreshing = true
        let work = Task { [weak self] in guard let self else { return }; await self.performRefreshAll() }
        refreshTask = work
        await work.value
        refreshTask = nil
        refreshProgress = nil
        isRefreshing = false
        persist()
    }

    private func performRefreshAll() async {
        // Mulai dari kosong agar hasil lama yang basi tidak menumpuk;
        // tiap sumber yang selesai langsung digabung + tampil.
        var all: [ProxyNode] = []
        let svc = self.service
        let snap = sources
        // Node MANUAL wajib selamat dari refresh. Grup manual dilewati
        // fetch (D93, url-nya kosong) TAPI `resort(all:)` di bawah mengganti
        // SELURUH `nodes` dengan `all` — jadi tanpa snapshot ini, setiap
        // refresh MENGHAPUS akun manual user dari daftar DAN dari disk
        // (persist menyimpan `nodes`). Kasus nyata: 13 akun grup "Spesial"
        // hilang total (nodes.json + .bak kosong) setelah tambah sumber
        // online yang fetch-nya gagal.
        let manualSnapshot = nodes.filter { n in
            snap.contains { $0.id == n.sourceID && $0.isManualGroup }
        }
        await withTaskGroup(of: (String, SubscriptionService.FetchOutcome?, String?).self) { group in
            // Yang dikembalikan ke loop adalah ID sumber, BUKAN indeks.
            // Sebelumnya `idx` dipakai untuk menulis `srcs[idx]` ke daftar yang
            // dibaca ULANG (`self.sources`) di dalam loop: kalau daftar itu
            // berubah selama await (sumber ditambah/diubah), angka/status
            // ditulis ke sumber yang SALAH, dan node tetap memakai ID basi.
            // Dicari by ID: kalau sumbernya hilang saat itu, hasil dibuang —
            // lebih baik daripada mengaitkan node ke sumber lain.
            // D93: grup manual dilewati. `url`-nya kosong, jadi `fetchOne`
            // akan mencoba lalu gagal dan menandainya `unavailable` — kontennya
            // baik-baik saja, cuma memang tidak ada yang perlu diunduh.
            for s in snap where s.isEnabled && !s.isManualGroup {
                group.addTask {
                    if Task.isCancelled { return (s.id, nil, "Cancelled") }
                    let r = await svc.fetchOne(s)
                    return (s.id, r.0, r.1)
                }
            }
            for await (sid, out, err) in group {
                if Task.isCancelled { group.cancelAll(); break }
                var srcs = self.sources
                guard let i = srcs.firstIndex(where: { $0.id == sid }) else { continue }
                if let out = out {
                    srcs[i].nodeCount = out.nodes.count
                    srcs[i].lastUpdated = out.fetchedAt
                    srcs[i].status = .ok
                    // "N tidak didukung" BUKAN kegagalan — jangan lagi dipakarkan
                    // ke lastError (UI menampilkannya merah seperti error).
                    srcs[i].unsupportedCount = out.unsupported
                    srcs[i].unusableCount = out.unusable
                    // Sukses = hasil dari jaringan, apa pun hasilnya. Tidak ada
                    // lagi jalur "dilayani dari salinan lokal", jadi tidak ada
                    // alasan menuliskan apa pun ke `lastError` (D90).
                    srcs[i].lastError = nil
                    all += out.nodes
                } else if err != "Cancelled" {
                    srcs[i].status = .unavailable
                    srcs[i].lastError = err
                }
                self.sources = srcs
                // Manual ikut di tiap putaran (bukan cuma di akhir) supaya
                // daftar tidak berkedip kehilangan akun manual selama fetch
                // berjalan. Hanya grup yang MASIH ADA yang dipertahankan —
                // user bisa menghapus grup manual di tengah refresh, dan
                // yang dihapus tidak boleh hidup lagi dari snapshot.
                let liveManualIDs = Set(self.sources.filter { $0.isManualGroup }.map(\.id))
                resort(all: Self.refreshMerge(fetched: all,
                                              manualSnapshot: manualSnapshot,
                                              liveManualIDs: liveManualIDs))
            }
        }
        // D91: `isRefreshing` sudah diturunkan oleh `refreshAll` SEBELUM
        // `enrichCountries` dipanggil. Sebelumnya `defer` di dalam fungsi ini
        // baru berjalan setelah enrichment selesai, jadi spinner tetap
        // berputar selama pekerjaan yang sama sekali bukan refresh.
        await enrichCountries()
    }

    /// Pengayaan negara untuk node yang countryCode-nya masih kosong.
    ///
    /// Parser sudah melakukan lookup sinkron (nama node lalu GeoIP atas IP
    /// literal), tapi ada dua kelompok yang tetap tertinggal:
    ///
    /// 1. **Host IP literal milik pengguna yang sudah ada.** `nodes.json`
    ///    versi lama terisi penuh node tanpa negara; menunggu refresh
    ///    pertama_artinya upgradeVisible kosong_country selama berhari-hari.
    ///    Jalur ini gratis — binary search, tanpa jaringan.
    /// 2. **Host domain** (~30% node). Satu-satunya jalan mendapatkan lokasi
    ///    yang jujur adalah resolve DNS lalu GeoIP atas IP hasilnya. Tetap
    ///    lokal: query ke resolver sistem, tidak ada API pihak ketiga, dan
    ///    tidak pernah mengirim IP tunnel user ke mana pun.
    ///
    /// Hasil disimpan ke `countryCode` (dan ke cache koordinat supaya pin
    /// peta ikut tepat) lalu dipersistensi — jadi hanya dibayar sekali.
    ///
    /// `budget` membatasi durasi: satu refresh tidak boleh menggantung. Sisa
    /// host yang belum sempat diselesaikan tidak hilang — refresh berikutnya
    /// melanjutkan dari situ karena hasil sebelumnya sudah tersimpan.
    public func enrichCountries(limit: Int = 1_500, budget: TimeInterval = 45) async {
        guard !isEnrichingCountries else { return }
        isEnrichingCountries = true
        defer { isEnrichingCountries = false }
        let deadline = Date().addingTimeInterval(budget)
        var changedAny = false

        // Putaran 1 — host IP literal: binary search murni, tanpa jaringan.
        //
        // Sekali jalan atas semua node, tanpa `limit` dan tanpa perulangan.
        // Batas tidak berguna di sini: kerja ini gratis (~22 langkah per
        // lookup di atas mmap), dan MORE yang penting — memakai `limit`
        // dengan target yang "belum bisa di-resolve" akan membuat host
        // tersebut memenuhi kuota selamanya, sedangkan host yang sebenarnya
        // punya negara di urutan berikutnya tidak pernah ikut diperiksa.
        if Self.applyLiteralCountries(to: &nodes) { changedAny = true }

        // Putaran 2+ — host domain, per batch, sampai habis atau kehabisan waktu.
        while Date() < deadline {
            let domains = Self.pendingHostsNeedingCountry(in: nodes, limit: limit, domainsOnly: true)
            guard !domains.isEmpty else { break }

            var resolved: [String: String] = [:]
            let hosts = Array(domains.values)
            var cursor = 0
            // 24 sekaligus. Host-nya milik user sendiri, jadi bebannya kecil,
            // tapi tetap perlu dibatasi supaya resolver sistem tidak kewalahan.
            let batch = 24
            while cursor < hosts.count, Date() < deadline {
                let end = min(cursor + batch, hosts.count)
                let chunk = hosts[cursor..<end]
                cursor = end
                await withTaskGroup(of: (String, String?).self) { group in
                    for h in chunk {
                        group.addTask { (h, await GeoIPResolver.resolveCountry(host: h)) }
                    }
                    for await (host, cc) in group {
                        if let cc, !cc.isEmpty { resolved[host] = cc }
                    }
                }
                // Terapkan tiap batch, bukan menunggu sampai akhir: user
                // melihat kolom Country terisi perlahan, bukan meledak sekaligus.
                if applyResolved(resolved) { changedAny = true }
                resolved.removeAll()
            }
            // Habis waktu dengan sisa host: berhenti. Hasil yang sudah
            // terimpan, sisanya dilanjutkan refresh berikutnya.
            if cursor < hosts.count { break }
        }
        if changedAny { persist() }
    }

    /// Isi negara untuk semua node berhost IP literal, sekali jalan.
    ///
    /// Tanpa `limit` dan tanpa perulangan, disengaja. Versi pertama memakai
    /// kuota per putaran, dan itu **salah**: host yang memang tidak punya
    /// lokasi (IP privat, ruang tanpa data) tidak pernah keluar dari daftar
    /// target, jadi mereka memenuhi kuota setiap putaran sementara host yang
    /// benar-benar punya negara di urutan berikutnya tidak pernah ikut
    /// diperiksa. Di data asli itu berarti 6.438 dari 8.213 node terisi —
    /// dan tidak ada yang memberi tahu user.
    ///
    /// Murni & nonisolated supaya bisa diuji.
    @discardableResult
    nonisolated static func applyLiteralCountries(to nodes: inout [ProxyNode]) -> Bool {
        var changed = false
        for i in nodes.indices where (nodes[i].countryCode ?? "").isEmpty {
            let host = nodes[i].host
            guard GeoIP.isIPv4Literal(host), let cc = GeoIP.countryCode(for: host) else { continue }
            nodes[i].countryCode = cc
            changed = true
        }
        return changed
    }

    /// Terapkan peta host → negara ke daftar node. True kalau ada yang berubah.
    private func applyResolved(_ resolved: [String: String]) -> Bool {
        guard !resolved.isEmpty else { return false }
        var changed = false
        for i in nodes.indices {
            if let cc = resolved[nodes[i].host.lowercased()], nodes[i].countryCode != cc {
                nodes[i].countryCode = cc
                changed = true
            }
        }
        if changed { nodes = nodes }
        return changed
    }

    /// Host unik yang belum punya negara — target pengayaan.
    ///
    /// `domainsOnly` memisahkan dua kelompok: literal Host diselesaikan tanpa
    /// jaringan, domain butuh DNS. Murni & nonisolated supaya bisa diuji.
    nonisolated static func pendingHostsNeedingCountry(in nodes: [ProxyNode],
                                                     limit: Int,
                                                     domainsOnly: Bool) -> [String: String] {
        var seen = Set<String>()
        var out: [String: String] = [:]
        for n in nodes {
            guard (n.countryCode ?? "").isEmpty else { continue }
            let h = n.host.lowercased()
            guard !h.isEmpty, !seen.contains(h) else { continue }
            let isDomain = !GeoIP.isIPv4Literal(h)
            guard isDomain == domainsOnly else { continue }
            seen.insert(h)
            out[h] = n.host
            if out.count >= limit { break }
        }
        return out
    }

    /// Refresh satu sumber saja (tombol retry per baris di SourcesView).
    public func refreshSource(id: String) async {
        // Sama seperti `refreshAll`: `sources` harus sudah dari disk, bukan
        // `builtIn()` (D66).
        await waitForHydration()
        guard let idx = sources.firstIndex(where: { $0.id == id }) else { return }
        if isRefreshing { return }
        isRefreshing = true
        let work = Task { [weak self] in guard let self else { return }; await self.performRefreshSource(id: id, idx: idx) }
        refreshTask = work
        await work.value
        refreshTask = nil
        refreshProgress = nil
        isRefreshing = false
        persist()
    }

    private func performRefreshSource(id: String, idx: Int) async {
        let src = sources[idx]
        if src.isManualGroup {
            // D93: tidak ada yang bisa diunduh. Yang perlu dihitung ulang cuma
            // angkanya — kalau node-nya dihapus dari tempat lain (mis. kolom
            // Sumber di tabel Server), angka di baris ini harus ikut benar.
            recountManualGroup(id)
            refreshProgress = nil
            isRefreshing = false
            refreshTask = nil
            persist()
            return
        }
        let (out, err) = await service.fetchOne(src) { [weak self] p in
            guard let self else { return }
            self.refreshProgress = L10n.formatted("refresh_progress", p.attempt, p.total)
        }
        guard !Task.isCancelled else { return }
        // `idx` bisa basi selama await (sumber dihapus/diubah). Cari ulang by ID
        // supaya angka tidak ditulis ke sumber yang salah.
        guard let i = sources.firstIndex(where: { $0.id == id }) else { return }
        if let out = out {
            sources[i].nodeCount = out.nodes.count
            sources[i].lastUpdated = out.fetchedAt
            sources[i].status = .ok
            sources[i].unsupportedCount = out.unsupported
            sources[i].unusableCount = out.unusable
            sources[i].lastError = nil
            var rest = nodes.filter { $0.sourceID != id }
            rest += out.nodes
            resort(all: rest)
        } else if err != "Cancelled" {
            sources[i].status = .unavailable
            sources[i].lastError = err
        }
        await enrichCountries()
    }

    /// Hapus satu sumber BESERTA server-server miliknya.
    ///
    /// Node harus ikut dibuang: kalau tidak, server dari feed yang dihapus masih
    /// nangkring di daftar (dan kolom Sumber akan menampilkan id asal yang sudah
    /// tak dikenal) sampai refresh berikutnya.
    ///
    /// Angka per sumber dihitung ULANG di akhir (D90). Tanpa itu, kolom
    /// "Keterangan" dan ringkasan "N server terpakai" masih memakai angka yang
    /// ditulis refresh terakhir — termasuk angka sumber yang TADI BARU dihapus,
    /// yang tidak pernah barusan ikut dihitung. Setelah operasi ini selesai,
    /// tidak ada angka di layar yang berasal dari keadaan sebelumnya.
    public func removeSource(id: String) {
        // YANG DIHAPUS harus dihitung dulu. Versi lama memakai
        // `nodesAfterRemovingSource` — yang mengembalikan node yang TETAP
        // (`!= id`) — lalu memakainya sebagai daftar yang terhapus. Akibatnya
        // dua bug sekaligus: hasil ping, favorit, dan node terpilih ikut
        // dihapus untuk semua node yang justru masih ada; dan kalau sumber
        // yang dihapus adalah satu-satunya sumber, node-nya tidak pernah
        // hilang sama sekali karena sisa nodenya kosong.
        let removed = nodes.filter { $0.sourceID == id }
        sources.removeAll { $0.id == id }
        // Filter yang menunjuk sumber ini harus ikut dilepas. Kalau tidak,
        // tabel Server terkunci kosong selamanya sementara pilihan di dropdown
        // sudah tidak ada — filter yang tidak bisa dibatalkan dari UI.
        if sourceFilter == id { sourceFilter = nil }

        detachNodes(removed)
        // Sumber yang tersisa: `keptCount` dihitung dari `nodes` yang baru,
        // bukan dari hasil refresh terakhir. Sumber yang dihapus tidak lagi
        // punya baris dan kontribusinya hilang dari total — jadi angkanya turun
        // tepat sebesar server yang benar-benar dibuang.
        resortCountsOnly()
        persist()
    }

    /// Buang node-node yang sudah tidak punya sumber, beserta semua jejak yang
    /// menunjuk mereka: hasil ping, favorit, dan pilihan aktif.
    ///
    /// Dipakai bersama oleh hapus sumber dan ganti URL — dua-duanya berarti
    /// "isi feed lama sudah tidak berlaku". Tanpa pembersihan ping/favorit,
    /// server yang sudah tidak ada masih punya "terbukti hidup" dan masih bisa
    /// terpilih.
    private func detachNodes(_ removed: [ProxyNode]) {
        guard !removed.isEmpty else { return }
        let gone = Set(removed.map { $0.id })
        nodes.removeAll { gone.contains($0.id) }
        // Buang juga hasil ping-nya supaya tidak ada sisa "terbukti hidup"
        // untuk server yang sudah tidak ada.
        for key in ping.keys where gone.contains(key) { ping.removeValue(forKey: key) }
        favorites.subtract(gone)
        if let sel = selectedNodeID, gone.contains(sel) { selectedNodeID = nil }
    }

    /// Tambah satu sumber ke daftar; kembalikan sumber yang dibuat, atau `nil`
    /// kalau URL-nya kosong atau sudah ada.
    ///
    /// D92: dipakai oleh sheet Tambah DAN oleh tawaran satu-klik di layar
    /// Sumber yang kosong. Duplikat URL ditolak — dua entri untuk feed yang
    /// sama berarti dua unduhan untuk isi identik.
    ///
    /// ID dikembalikan supaya pemanggil bisa langsung me-refresh sumber itu:
    /// user menekan "mulai dari feed ini", dan jawaban yang ia terima bukan
    /// baris berstatus "Menunggu" yang harus ditekan lagi.
    @discardableResult
    public func addSource(name: String, url: String) -> VPNSubscriptionSource? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty, !hasSource(url: trimmedURL) else { return nil }
        let made = VPNSubscriptionSource(
            id: UUID().uuidString,
            name: trimmedName.isEmpty ? trimmedURL : trimmedName,
            url: trimmedURL, isCustom: true)
        sources.append(made)
        persist(onlySources: true)
        return made
    }

    // MARK: - Grup proxy manual (D93)

    /// Buat grup proxy baru yang diisi tangan.
    ///
    /// `url` sengaja KOSONG dan `isManualGroup` menyala: tidak ada yang perlu
    /// diunduh, dan refresh harus melewatinya — kalau tidak, grup yang isinya
    /// baik-baik saja akan tampil sebagai `unavailable` karena "HTTP 0".
    @discardableResult
    public func addManualGroup(name: String) -> String {
        let id = UUID().uuidString
        sources.append(VPNSubscriptionSource(
            id: id, name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            url: "", isCustom: true, status: .ok, isManualGroup: true))
        persist(onlySources: true)
        return id
    }

    /// Hasil menambah satu node manual, lengkap dengan alasan kegagalan.
    public enum ManualAddResult: Equatable {
        case added(Int)                 // jumlah node yang ditambahkan
        case failed([String])
    }

    /// Tambahkan node manual ke sebuah grup, setelah DIVALIDASI core.
    ///
    /// Validasi lewat `sing-box check` itu wajib, bukan tambahan biar saja:
    /// config yang ditolak core tidak hanya membuat node itu gagal — satu
    /// outbound buruk membatasi SELURUH config probe, jadi satu node yang
    /// diketik dengan salah bisa mematikan pengujian internet untuk ratusan
    /// node lain di jendela sesi yang sama (D61).
    public func addManualNode(draft: ManualNodeDraft, toGroup sourceID: String) async -> ManualAddResult {
        switch draft.build(sourceID: sourceID) {
        case .failed(let p):
            return .failed(p)
        case .ok(let node):
            return await addManualNodes([node], toGroup: sourceID)
        }
    }

    /// Tambahkan beberapa node sekaligus (tempel banyak tautan).
    ///
    /// Nodes yang satu-satunya anggota grup ini tetap ikut di-`attach` ke
    /// daftar global lewat `resort` — kalau tidak, node itu ada di
    /// `sources.json` tapi tidak pernah muncul di tabel Server.
    public func addManualNodes(_ incoming: [ProxyNode], toGroup sourceID: String) async -> ManualAddResult {
        guard !incoming.isEmpty else { return .failed([L10n.string("manual_err_unparsable")]) }
        guard let idx = sources.firstIndex(where: { $0.id == sourceID }),
              sources[idx].isManualGroup else {
            return .failed([L10n.string("manual_err_no_group")])
        }

        // Validasi BERSAMA, bukan satu per satu: `sing-box check` bersifat
        // all-or-nothing, jadi yang perlu diuji adalah node-node-nya
        // sekalian, bukan satu-satu.
        let binary = CorePaths.singBox
        guard FileManager.default.isExecutableFile(atPath: binary) else {
            // Tanpa core tidak ada yang bisa memvalidasi. Tolak dengan jujur
            // daripada menerima apa saja yang diketik.
            return .failed([L10n.string("manual_err_no_core")])
        }
        if case .noUsableNode = InternetProbe.prepareProbeConfig(
            nodes: incoming, clashPort: 28909, mixedPort: 28108, binary: binary) {
            return .failed([L10n.string("manual_err_core_rejects")])
        }

        // Buang yang sudah ada. `resort` menghitung node per identitas, jadi
        // masukkan dua kali bukan tambahan — user mengira dapat dua server dan
        // berakhir dengan satu.
        let before = Set(nodes.map(\.id))
        var finalAdd: [ProxyNode] = []
        var seen = Set<String>()
        for n in incoming where !seen.contains(n.id) && !before.contains(n.id) {
            seen.insert(n.id); finalAdd.append(n)
        }
        guard !finalAdd.isEmpty else {
            return .failed([L10n.string("manual_err_duplicate")])
        }

        resort(all: nodes + finalAdd)
        // Angka sumber manual berasal dari node yang ada, bukan dari unduhan.
        recountManualGroup(sourceID)
        persist()
        return .added(finalAdd.count)
    }

    /// Hitung ulang angka sebuah grup manual.
    ///
    /// `lastUpdated` ikut disentuh: grup manual berubah setiap kali user
    /// menambah/menghapus, jadi "terakhir diperbarui" yang benar adalah waktu
    /// perubahan itu — bukan waktu feed fiktif yang tidak pernah diunduh.
    public func recountManualGroup(_ id: String) {
        guard let i = sources.firstIndex(where: { $0.id == id }) else { return }
        let owned = nodes.filter { $0.sourceID == id }
        sources[i].nodeCount = owned.count
        sources[i].keptCount = owned.count
        sources[i].unsupportedCount = 0
        sources[i].unusableCount = 0
        sources[i].status = .ok
        sources[i].lastError = nil
        sources[i].lastUpdated = Date()
    }

    /// Buang satu node manual dari grupnya.
    public func removeManualNode(id: String) {
        guard let n = nodeIndex[id] else { return }
        detachNodes([n])
        recountManualGroup(n.sourceID)
        persist()
    }

    /// Ganti isi satu node manual dengan hasil form edit.
    ///
    /// ID SENGAJA TETAP. `ProxyNode.id` adalah kunci di `ping`, di `favorites`,
    /// di `selectedNodeID`, dan di mana saja hasil probe disimpan. Kalau form
    /// edit membuat node baru, pengukuran ping lama ikut nyangkut ke node yang
    /// tidak ada lagi, favorit user hilang, dan node yang sedang tersambung
    /// kehilangan rujukan. Jadi ini replacing di tempat, bukan tambah-hapus.
    ///
    /// Ping lama DIBUANG, bukan dipertahankan: kredensial atau SNI yang berubah
    /// berarti hasil ukur yang lama diukur untuk konfigurasi yang berbeda, dan
    /// memakainya berarti menampilkan "93 ms" untuk node yang belum pernah
    /// diuji.
    public func updateManualNode(id: String, draft: ManualNodeDraft) async -> ManualAddResult {
        guard let idx = nodes.firstIndex(where: { $0.id == id }) else {
            return .failed([L10n.string("manual_err_no_group")])
        }
        // Group node TIDAK boleh pindah lewat form edit: `sourceID` ikut
        // menentukan node muncul di tabel Server dan ikut di-refresh saat grup
        // disegarkan.
        let original = nodes[idx]
        var built: ProxyNode
        switch draft.build(sourceID: original.sourceID) {
        case .failed(let p):
            return .failed(p)
        case .ok(let n):
            built = n
        }

        // ID node ini DIHITUNG dari isi node (`ProxyNode.dedupID`), jadi
        // mengganti password atau SNI otomatis mengubahnya. Itu berarti
        //urutannya yang penting: tanpa baris di bawah, `ping`, `favorites`,
        // dan `selectedNodeID` semuanya menunjuk id yang sudah tidak ada —
        // hasil ping lama nyangkut, favorit hilang, dan node yang sedang
        // tersambung kehilangan rujukan hanya karena user memperbaiki SNI.
        //
        // Jadi id ASLI dipaksakan kembali. Yang tetap dijaga: id itu tidak
        // boleh bertabrakan dengan node lain, karena dua node dengan id sama
        // membuat `first(where:)` ambigu di mana-mana.
        if nodes.contains(where: { $0.id == built.id && $0.id != id }) {
            return .failed([L10n.string("manual_err_duplicate")])
        }
        built.id = id

        let binary = CorePaths.singBox
        guard FileManager.default.isExecutableFile(atPath: binary) else {
            return .failed([L10n.string("manual_err_no_core")])
        }
        // Validasi dengan node SEBENARNYA di dalam config, bukan node hasil
        // edit saja. Kalau hanya node hasil edit yang diuji, node lain di grup
        // yang bermasalah tetap lolos — dan `sing-box check` yang all-or-nothing
        // akan menolak SELURUH config probe, mematikan pengujian internet untuk
        // semua node lain di sesi itu (D61).
        var probeSet = nodes.filter { $0.sourceID == original.sourceID && $0.id != id }
        probeSet.append(built)
        if case .noUsableNode = InternetProbe.prepareProbeConfig(
            nodes: probeSet, clashPort: 28909, mixedPort: 28108, binary: binary) {
            return .failed([L10n.string("manual_err_core_rejects")])
        }

        nodes[idx] = built
        ping.removeValue(forKey: built.id)
        rebuildNodeIndex()
        recountManualGroup(original.sourceID)
        persist()
        return .added(1)
    }

    /// Ganti nama + URL + status bintang satu sumber.
    ///
    /// ID sengaja tidak berubah: node yang sudah ada menunjuk sumber lewat
    /// `sourceID`. Kalau ID ikut berubah, semua node sumber itu langsung jadi
    /// yatim — kolom Sumber kosong dan filter sumber tidak menghasilkan apa pun
    /// sampai refresh berikutnya.
    ///
    /// `isStarred` opsional karena form edit menampilkan sakelar bintang yang
    /// sama persis dengan form tambah. Tanpa parameter ini, sakelar itu dibaca
    /// ke state tapi `renameSource` membuangnya: user menggeser sakelar,
    /// menekan Simpan, dan tidak terjadi apa-apa. Itu bentuk "tidak bisa
    /// edit" yang paling menyebalkan — form-nya ada dan kelihatan benar.
    public func renameSource(id: String, name: String, url: String, isStarred: Bool? = nil) {
        guard let idx = sources.firstIndex(where: { $0.id == id }) else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty { sources[idx].name = trimmedName }
        if let isStarred { sources[idx].isStarred = isStarred }
        if !trimmedURL.isEmpty, sources[idx].url != trimmedURL {
            sources[idx].url = trimmedURL
            // URL berubah = isi feed yang tampil sudah tidak berlaku. Angka
            // dikosongkan dan node lama ikut dibuang, supaya tidak ada server
            // dari URL lama yang masih memakai label sumber yang baru. Setelah
            // ini sumber itu benar-benar 0 sampai refresh mengunduh feed baru
            // (D90: tidak ada lagi salinan lokal yang masih bisa ditampilkan).
            sources[idx].nodeCount = 0
            sources[idx].keptCount = 0
            sources[idx].unsupportedCount = 0
            sources[idx].unusableCount = 0
            sources[idx].status = .unknown
            sources[idx].lastError = nil
            detachNodes(nodes.filter { $0.sourceID == id })
        }
        rebuildSourceNames()
    }

    /// Murni (tanpa I/O) supaya bisa diuji: buang node milik satu sumber.
    nonisolated public static func nodesAfterRemovingSource(id: String,
                                                            from nodes: [ProxyNode]) -> [ProxyNode] {
        nodes.filter { $0.sourceID != id }
    }

    /// Gabungkan hasil fetch feed dengan snapshot node manual.
    ///
    /// Inilah penjaga akun manual saat refresh: feed yang gagal/kosong
    /// (`fetched` kosong) TIDAK boleh menghapus manual. Grup manual yang
    /// sudah dihapus user (`liveManualIDs`) tidak ikut dibangkitkan.
    ///
    /// Murni & nonisolated supaya bisa diuji tanpa jaringan.
    nonisolated public static func refreshMerge(fetched: [ProxyNode],
                                                manualSnapshot: [ProxyNode],
                                                liveManualIDs: Set<String>) -> [ProxyNode] {
        fetched + manualSnapshot.filter { liveManualIDs.contains($0.sourceID) }
    }

    private func resort(all: [ProxyNode]) {        // Dedup lintas sumber. Urutan tampilan (termasuk sumber berbintang
        // paling atas) diurus `filteredNodes`, bukan di sini.
        let ded = NodeDeduper.dedup(all)
        // Hitung berapa node tiap sumber yang benar-benar tersisa. Tanpa ini
        // sumber aggregator terlihat "0" padahal 380 node terbaca — semuanya
        // duplikat sumber yang lebih besar.
        var kept: [String: Int] = [:]
        for n in ded { kept[n.sourceID, default: 0] += 1 }
        var srcs = sources
        for i in srcs.indices { srcs[i].keptCount = kept[srcs[i].id] ?? 0 }
        sources = srcs
        rebuildSourceNames()
        // `nodes` sendiri TIDAK diurutkan di sini. Urutan tampilan milik
        // `filteredNodes` (lewat `ServerSorter`), jadi perubahan filter atau
        // kolom urut tidak perlu menyalin ulang seluruh array 16.000 node.
        // Di sini hanya isi dan dedup yang menjadi urusan kita.
        nodes = ded
    }

    /// Cek izin & kesehatan (dipanggil saat app dibuka + tombol Periksa).
    public func checkHealth() {
        Task {
            await health.check(split: split, coreBinary: CorePaths.singBox)
        }
    }

    public func quickConnectNode() -> ProxyNode? {
        Self.quickConnectChoice(among: nodes, ping: ping)
    }

    /// Pilih node untuk Quick Connect dari hasil ping yang sudah ada.
    ///
    /// Urutan: (1) terbukti bisa akses internet, ambil yang tercepat; (2) belum
    /// pernah diuji; (3) apa pun yang tersisa. Node yang terbukti TIDAK bisa
    /// internet tidak pernah dipilih selama masih ada alternatif — connect ke
    /// sana hanya membuang waktu user.
    ///
    /// Murni & nonisolated supaya bisa diuji tanpa actor.
    public nonisolated static func quickConnectChoice(among nodes: [ProxyNode],
                                                      ping: [String: PingResult]) -> ProxyNode? {
        let byLatency: (ProxyNode, ProxyNode) -> Bool = {
            (ping[$0.id]?.bestMs ?? Int.max) < (ping[$1.id]?.bestMs ?? Int.max)
        }
        let verified = nodes.filter { ping[$0.id]?.internetOK == true }
        if !verified.isEmpty { return verified.min(by: byLatency) }
        let untested = nodes.filter { ping[$0.id]?.internetOK == nil }
        return (untested.isEmpty ? nodes : untested).min(by: byLatency)
    }

    /// Node yang sudah diuji dan TIDAK bisa akses internet.
    ///
    /// D91: sejak `connect()` tidak lagi memakai ini sebagai GERBANG, fungsi ini
    /// tinggal alat bantu yang dipakai lapisan UI untuk menandai node — bukan
    /// lagi alasan penolakan. Quick Connect sendiri sudah punya seleksinya sendiri
    /// (lihat `quickConnectChoice`) yang tidak pernah memilih node mati selama
    /// ada alternatif.
    public func isKnownDead(_ node: ProxyNode) -> Bool {
        ping[node.id]?.isDeadEnd == true
    }

    /// Alasan kegagalan terakhir yang diketahui, kalau ada.
    ///
    /// Inilah yang membuat pesan error bisa jujur: "kredensial ditolak" dan
    /// "tidak bisa menghubungi server" punya perbaikannya yang berbeda.
    public func failureReason(for node: ProxyNode) -> ProbeFailure? {
        let r = ping[node.id]
        guard r?.isDeadEnd == true else { return nil }
        return r?.failure
    }

    /// `sourceID` yang punya setidaknya satu node yang benar-benar termuat.
    ///
    /// D66: sumber untuk dropdown filter harus ditentukan dari node nyata,
    /// bukan dari angka metadata di `sources.json` (`keptCount`/`nodeCount`).
    /// Angka itu bisa basi — dan dropdown yang menunjuk sumber tanpa node
    /// memberi tabel kosong, yang terlihat seperti filter yang rusak.
    ///
    /// Di-cache bersama filter lain karena dihitung dari `nodes` yang bisa
    /// 16.000 entri; menyisirnya tiap render akan berat.
    public var sourceIDsPresentInNodes: Set<String> {
        ensureDerived()
        return presentSourceIDsCache
    }

    /// Sudah ada feed dengan URL ini di daftar? (D66)
    ///
    /// `ignoring` dipakai saat MENYIMPAN sumber yang sedang diedit, supaya
    /// sumber itu tidak dianggap duplikat dirinya sendiri.
    public func hasSource(url: String, ignoring id: String? = nil) -> Bool {
        Self.hasSource(url: url, in: sources, ignoring: id)
    }

    /// Varian murni & nonisolated supaya bisa diuji tanpa actor.
    public nonisolated static func hasSource(url: String,
                                            in sources: [VPNSubscriptionSource],
                                            ignoring id: String? = nil) -> Bool {
        let want = normalized(url)
        guard !want.isEmpty else { return false }
        return sources.contains { $0.id != id && normalized($0.url) == want }
    }

    /// Bentuk URL yang comparable: spasi dan huruf besar tidak berpengaruh,
    /// garis miring di akhir diabaikan.
    nonisolated static func normalized(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !t.isEmpty else { return "" }
        return t.hasSuffix("/") ? String(t.dropLast()) : t
    }

    /// Titik masuk tunggal untuk connect dari UI (Sambung / Quick Connect /
    /// klik baris / menu bar).
    ///
    /// D91 — VERSI INI TIDAK LAGI MENOLAK node yang vonis ping-nya "mati".
    /// Sebelumnya `isKnownDead` jadi GERBANG: satu klik langsung ditolak tanpa
    /// percobaan. Itu konyol karena dua alasan:
    ///
    /// 1. Vonis ping bisa salah (lihat alasan false-negative di
    ///    `RealDelayTester`), dan kalau salah, node yang sebenarnya hidup jadi
    ///    tidak bisa dipakai sama sekali — bukan cuma lambat dideteksi.
    /// 2. User yang menekan tombol SAMBUNG sudah memberikan persetujuan.
    ///    Menolak keputusan eksplisit user demi hemat beberapa detik adalah
    ///    kesombongan, bukan layanan.
    ///
    /// Vonis ping tetap berguna: Quick Connect tidak akan memilihnya duluan
    /// kalau ada alternatif, dan label di UI tetap menandainya. Hanya
    /// penolakan paksa yang dihapus.
    public func connect(node: ProxyNode) {
        connection.connect(node: node, split: split, coreBinary: CorePaths.singBox)
    }

    public func disconnect() {
        connection.disconnect()
    }

    /// "Sedang tersambung" menurut mesin TUN.
    public var isConnected: Bool { connection.status == .connected }

    // MARK: - Filtered

    /// Terapkan filter yang SEDANG AKTIF di toolbar Server (cari, tipe, sumber).
    /// Murni & nonisolated supaya bisa diuji tanpa menyentuh file settings.
    nonisolated public static func applyFilters(nodes: [ProxyNode],
                                               search: String,
                                               proto: NodeProtocol?,
                                               source: String?) -> [ProxyNode] {
        var list = nodes
        if !search.isEmpty {
            let q = search.lowercased()
            list = list.filter { $0.name.lowercased().contains(q) || $0.host.lowercased().contains(q) }
        }
        if let proto { list = list.filter { $0.proto == proto } }
        if let source { list = list.filter { $0.sourceID == source } }
        return list
    }

    /// Sasaran Ping All.
    ///
    /// Menghormati filter yang sedang aktif (cari / tipe / sumber) — kalau
    /// tidak, satu klik bisa memicu pengujian ribuan server. Tapi TIDAK
    /// menghormati "Sembunyikan yang mati", dan itu bukan detail kecil:
    ///
    /// D91 — dengan filter itu nyala, node yang sudah dinyatakan mati
    /// dikeluarkan dari `filteredNodes`, yang persis merupakan daftar sasaran
    /// Ping All. Artinya node mati tidak akan pernah diuji ulang selama app
    /// berjalan: vonis yang salah mengukuhkan dirinya sendiri. Lingkaran itu
    /// harus diputus di sini.
    ///
    /// Murni & nonisolated supaya bisa diuji tanpa actor.
    nonisolated public static func pingTargets(nodes: [ProxyNode],
                                              search: String,
                                              proto: NodeProtocol?,
                                              source: String?) -> [ProxyNode] {
        applyFilters(nodes: nodes, search: search, proto: proto, source: source)
    }

    /// "Mati" untuk filter "Sembunyikan yang mati" = SUDAH diuji dan terbukti
    /// tidak bisa akses internet. Hasil `nil` (belum pernah diuji) tetap
    /// ditampilkan — tidak ada verdict, jadi tidak boleh ikut disembunyikan.
    ///
    /// Murni & nonisolated supaya bisa diuji tanpa actor.
    public nonisolated static func isUsable(_ result: PingResult?) -> Bool {
        result?.isDeadEnd != true
    }

    /// Yang TAMPIL di tabel Server — persis ini yang jadi sasaran Ping All.
    ///
    /// Hasil di-cache: sort 16.000 node per render == jaud ("app lemot, CPU
    /// 8%": jenuh di main thread, bukan di CPU). Cache dibuang oleh didSet
    /// tiap input yang relevan, sehingga recompute maksimal sekali per
    /// perubahan data, bukan sekali per akses view.
    private var filteredNodesCache: [ProxyNode]? = nil
    /// Bukan computed property biasa: hitung sekali di tempat yang sama untuk
    /// semua turunan. Versi pertama menghitung `bestLatency`/`preview` di dalam
    /// getter `filteredNodes` — jadi kalau ada yang membaca `bestLatency`
    /// duluan (seperti `ServersView`), cache-nya masih `nil` dan kolom Load
    /// menampilkan "—" untuk semua baris (D61).
    private var derivedReady = false
    /// `sourceID` yang punya node nyata (lihat `sourceIDsPresentInNodes`).
    private var presentSourceIDsCache: Set<String> = []
    private func ensureDerived() {
        if derivedReady { return }
        computeFilteredNodes()
        let sorted = filteredNodesCache ?? []
        bestLatencyCache = sorted.compactMap { ping[$0.id]?.bestMs }.min()
        previewCache = Self.topByLatency(sorted, ping: ping, count: Self.previewCount)
        derivedReady = true
    }

    /// Hitung ulang `filteredNodesCache` saja (dipanggil oleh `ensureDerived`).
    private func computeFilteredNodes() {
        var list = Self.applyFilters(nodes: nodes, search: searchText,
                                     proto: protoFilter, source: activeSourceFilter)
        if settings.hideDeadNodes {
            list = list.filter { Self.isUsable(ping[$0.id]) }
        }
        // Dihitung dari `nodes` PENUH, bukan `list` — kalau dihitung dari list
        // yang sudah difilter sumber, sumber lain ikut hilang dari dropdown
        // begitu user memfilter, jadi memilih filter kedua jadi bom waktu.
        presentSourceIDsCache = Set(nodes.map(\.sourceID).filter { !$0.isEmpty })
        filteredNodesCache = ServerSorter.sort(
            list, by: sort, ping: ping, sourceNames: sourceNames,
            starredSources: Set(sources.filter { $0.isStarred }.map { $0.id }))
    }

    public var filteredNodes: [ProxyNode] {
        ensureDerived()
        return filteredNodesCache ?? []
    }

    // MARK: - Turunan yang di-cache
    //
    // Semuanya dihitung dari `filteredNodes`. Sebelumnya masing-masing
    // dihitung ULANG di dalam `body` view: `bestLatency` O(16.000) dipanggil
    // dari `ServersView`, dan `previewNodes` bahkan melakukan `sorted()` penuh
    // 16.000 node (ConnectView) — dua kali tiap 2 detik selama terhubung, di
    // main thread. Sekarang keduanya turun dari satu hasil sort yang sudah
    // ada. Di-reset bareng `filteredNodesCache`.

    /// Berapa node yang tampil di pratinjau "Available Servers".
    public static let previewCount = 5

    private var bestLatencyCache: Int? = nil
    private var previewCache: [ProxyNode] = []
    /// `nil` berarti "memang tidak ada node" dan itu perlu dibedakan dari
    /// "belum dihitung", jadi `nil` disimpan sebagai `.some(nil)`.
    private var recommendedCache: ProxyNode?? = nil

    /// Node yang ditawarkan di layar Sambung: terpilih kalau ada, kalau tidak
    /// yang tercepat dari hasil ping, kalau tidak node pertama yang tampil.
    ///
    /// Sebelumnya dihitung dari `body`: `selectedNode` = linear scan 16.000
    /// node, lalu `quickConnectNode()` = dua filter penuh + `min` lagi. Dua
    /// lintasan O(n) plus tiga alokasi array PER FRAME (D61).
    public var recommendedNode: ProxyNode? {
        ensureDerived()
        if let cached = recommendedCache { return cached }
        let value = selectedNode ?? quickConnectNode() ?? filteredNodes.first
        recommendedCache = .some(value)
        return value
    }

    /// Latensi terbaik di antara node yang sedang tampil — pembagi kolom Load.
    ///
    /// Mengembalikan `nil` kalau belum ada satu pun node yang terukur.
    public var bestLatency: Int? {
        ensureDerived()
        return bestLatencyCache
    }

    /// Lima server tercepat dari daftar yang sedang difilter.
    public var previewNodes: [ProxyNode] {
        ensureDerived()
        return previewCache
    }

    /// N node tercepat menurut tiga tingkat: terukur dulu (tercepat ke lambat),
    /// lalu belum pernah diuji, lalu terbukti mati.
    ///
    /// BUKAN `sorted().prefix(n)`: sort penuh 16.000 node hanya untuk mengambil
    /// 5 elemen adalah O(n log n) + alokasi array penuh. Yang dibutuhkan cuma
    /// 5 terbaik, jadi gunakan `min()` berulang — O(n·k) tanpa array besar.
    /// Murni & nonisolated supaya bisa diuji tanpa actor.
    public nonisolated static func topByLatency(_ nodes: [ProxyNode],
                                                ping: [String: PingResult],
                                                count: Int) -> [ProxyNode] {
        guard count > 0 else { return [] }
        func tier(_ n: ProxyNode) -> Int {
            guard let r = ping[n.id] else { return 1 }          // belum diuji
            if r.internetOK == false { return 2 }              // terbukti mati
            // D96: angka `approximate` (handshake TCP di mode ping cepat)
            // TIDAK boleh menempati tier yang sama dengan RTT terukur. Port
            // terbuka tidak memberi tahu apa-apa soal apakah proxy-nya
            // berfungsi, jadi node itu tidak boleh mendahului node yang
            // latensinya benar-benar diukur — itulah yang membuat daftar ini
            // menampilkan node terburuk sebagai "terbaik".
            if r.bestMs != nil && !r.approximate { return 0 }  // terukur sungguhan
            return 1                                           // ada angka, tapi belum terverifikasi
        }
        func isBetter(_ a: ProxyNode, _ b: ProxyNode) -> Bool {
            let (t1, t2) = (tier(a), tier(b))
            if t1 != t2 { return t1 < t2 }
            let x = ping[a.id]?.bestMs
            let y = ping[b.id]?.bestMs
            switch (x, y) {
            case let (p?, q?): return p == q ? a.name < b.name : p < q
            case (nil, _?): return false
            case (_?, nil): return true
            default: return a.name < b.name
            }
        }
        // Diminta semua (atau lebih dari yang ada) -> tidak perlu algoritme
        // top-k, urutkan saja. Jalur ini yang dipakai test yang memanggil
        // `ConnectView.byLatency`.
        if count >= nodes.count {
            return nodes.sorted(by: isBetter)
        }
        var top: [ProxyNode] = []
        top.reserveCapacity(count)
        for n in nodes {
            if top.count < count {
                top.append(n)
            } else if isBetter(n, top[top.count - 1]) {
                // `top` selalu terurut karena `isBetter` total-order: ganti
                // posisi terakhir lalu bubble ke depan. k = 5, jadi ini murah.
                top[top.count - 1] = n
                var i = top.count - 1
                while i > 0 && isBetter(top[i], top[i - 1]) {
                    top.swapAt(i, i - 1)
                    i -= 1
                }
            }
        }
        top.sort(by: isBetter)
        return top
    }

    /// Cache turunan yang dihitung dari `filteredNodes`. Satu titik invalidasi
    /// untuk semua input (nodes, filter, sort, ping) supaya tidak ada satu
    /// pun yang bisa "lupa" di-reset dan diam-diam menampilkan data basi.
    private func invalidateDerived() {
        filteredNodesCache = nil
        bestLatencyCache = nil
        previewCache = []
        recommendedCache = nil
        derivedReady = false
    }

    /// Hanya untuk perubahan `nodes` — bukan turunan lain.
    ///
    /// Dipisah dari `invalidateDerived` karena `ping` juga memanggil
    /// `invalidateDerived`, dan `apply(_:for:)` menulis satu key per node:
    /// membangun ulang indeks 16.000 entri untuk tiap verdict berarti
    /// 16.000 × O(n) dalam satu putaran Ping All. Indeks hanya bergantung
    /// pada `nodes`, jadi cukup di-reset saat `nodes` berubah (D61).
    private func invalidateNodeIndex() {
        rebuildNodeIndex()
        invalidateDerived()
    }

    /// Klik judul kolom: kolom sama membalik arah, kolom baru mengganti.
    public func toggleSort(_ key: ServerSortKey) {
        sort.toggle(key)
    }

    /// Filter sumber yang **benar-benar masih ada**.
    ///
    /// `sourceFilter` bisa menunjuk sumber yang sudah dihapus — dari sesi
    /// sebelumnya, atau dari `sources.json` yang diganti di luar app. Kalau
    /// tidak disaring begini, tabel terkunci kosong tanpa alasan yang
    /// terlihat: label dropdown jatuh kembali ke "Semua sumber" (karena
    /// sumbernya tidak ketemu) sementara filternya masih aktif.
    public var activeSourceFilter: String? {
        guard let id = sourceFilter, sources.contains(where: { $0.id == id }) else { return nil }
        return id
    }

    /// True kalau ada filter yang sedang aktif (bukan "semua").
    public var hasActiveFilter: Bool {
        !searchText.isEmpty || protoFilter != nil || activeSourceFilter != nil
    }

    // MARK: - Ping (satu tahap: uji akses internet end-to-end lewat node)

    /// Ping satu node. Menghormati Setting "Ping cepat": kalau aktif, hanya
    /// memastikan server merespons; kalau tidak, cek internet sungguhan.
    ///
    /// Satu-satunya alasan kedua jalur ini hidup berdampingan: keduanya menulis
    /// ke map `ping` yang sama dan dipakai UI yang sama, jadi tidak ada state
    /// ketiga yang harus disinkronkan.
    public func pingOne(_ node: ProxyNode) async {
        if settings.fastPing {
            apply(await fastPingOne(node), for: node.id)
        } else {
            apply(await probe.verifyOne(node, testURL: currentPingTargetURL),
                  for: node.id)
        }
    }

    /// URL uji yang sedang dipakai — D93. Satu tempat, supaya ping per baris
    /// dan Ping All tidak pernah menguji host yang berbeda dalam satu sesi.
    public var currentPingTargetURL: String {
        settings.pingTarget.resolvedURL(custom: settings.pingTargetCustomURL)
    }

    /// Host yang sedang diuji, untuk ditampilkan di log.
    public var currentPingTargetHost: String {
        settings.pingTarget.displayHost(custom: settings.pingTargetCustomURL)
    }

    /// Ping satu node lewat jalur cepat. Terpisah agar `pingOne` di atas tetap
    /// terbaca sebagai daftar pilihan, bukan dua implementasi yang saling
    /// menimpa.
    private func fastPingOne(_ node: ProxyNode) async -> ServerPingOutcome {
        let outcome = await ServerPinger.ping(node)
        // `pingNotice` dipakai untuk memberi tahu hal yang JADI terjadi pada
        // ping berjalan (mis. dibatalkan halfway), bukan untuk status biasa —
        // jadi verdict per node tidak pernah menyentuhnya.
        return outcome
    }

    /// Terapkan verdict probe ke satu node.
    ///
    /// Entry dibuat kalau belum ada: inilah satu-satunya jalur penulisan
    /// verdict sejak tahap TCP dihapus (D50), jadi node yang belum pernah diuji
    /// pun harus bisa menerima hasilnya.
    ///
    /// Sengaja method terpisah: closure yang dipanggil dari konteks async tak
    /// boleh memegang akses `inout` ke properti @MainActor secara langsung.
    private func apply(_ verdict: ProbeVerdict, for id: String) {
        let base = ping[id] ?? PingResult(nodeID: id)
        ping[id] = base.applying(verdict)
        logPingVerdict(verdict, for: id, kind: .internet)
    }

    /// Terapkan hasil ping cepat (lihat `ServerPinger`).
    private func apply(_ outcome: ServerPingOutcome, for id: String) {
        let base = ping[id] ?? PingResult(nodeID: id)
        ping[id] = base.applying(outcome)
        // Ping cepat punya bentuk verdict-nya sendiri; diterjemahkan ke yang
        // sama supaya log punya satu format, bukan dua.
        let v: ProbeVerdict
        switch outcome {
        case .replied(let ms):       v = .ok(ms)
        case .aliveUpperBound:       v = .ok(0)
        case .dead:                  v = .failed(.unreachable)
        }
        logPingVerdict(v, for: id, kind: .fast)
    }

    /// Penghitung untuk `PingRunSummary` yang sedang berjalan.
    private var currentRunAlive = 0
    private var currentRunFailures: [ProbeFailure: Int] = [:]
    private var currentRunSkipped = 0

    /// Tulis satu baris log untuk sebuah node, dan perbarui penghitung putaran.
    ///
    /// `.skipped` TIDAK ditulis sebagai baris: itu bukan hasil, itu "tidak
    /// sempat diuji" — bisa berarti core tumbang, bisa berarti node sedang di
    /// luar jendela sesi, dan bisa ribuan baris sekali puts. Yang dicatat
    /// hanyalah jumlahnya di ringkasan, karena itu yang menjawab "kenapa
    /// tidak semua ikut diuji".
    private func logPingVerdict(_ verdict: ProbeVerdict, for id: String,
                                kind: PingLogEntry.Kind) {
        if case .skipped = verdict {
            currentRunSkipped += 1
            return
        }
        // Pakai `nodeIndex`, bukan `nodes.first`: Apply dipanggil sekali per
        // node, dan pemindaian linear atas 20.000 node di setiap panggilan
        // berarti 400 juta perbandingan untuk satu putaran.
        let n = nodeIndex[id]
        var ms: Int? = nil
        if case .ok(let x) = verdict { ms = x }
        let entry = PingLogEntry(
            kind: kind, nodeID: id,
            nodeName: n?.name ?? id,
            proto: n?.proto.rawValue ?? "", host: n?.host ?? "",
            targetHost: currentPingTargetHost,
            ms: ms, verdict: verdict)
        logPing(entry)
        if entry.ok {
            currentRunAlive += 1
        } else if let why = entry.failure {
            currentRunFailures[why, default: 0] += 1
        }
    }

    /// Ping semua server SEKALI: tiap node diuji akses internet sungguhan
    /// (request `generate_204` menembak core sing-box, lewat node tersebut)
    /// dan angkanya langsung tampil.
    ///
    /// D50 — sebelumnya ada dua tahap: sweep TCP untuk melihat port hidup,
    /// baru tahap internet hanya untuk node yang lolos. Tahap pertama tidak
    /// pernah dipakai untuk memutuskan apa pun, hanya mempersempit siapa yang
    /// perlu diuji tahap kedua — jadi tiap node diproses dua kali dan satu
    /// putaran penuh kerja dibuang. Sekarang hanya ada pengukuran yang memang
    /// dipakai: satu core, satu request, satu verdict.
    ///
    /// Konkurensi mengikuti jatah Performance (`cpu.computeLimit`) yang AIMD
    /// sesuaikan dengan beban CPU nyata selama pengujian berjalan.
    public func pingAll() async {
        // Klik lagi saat sedang jalan = batalkan (tombol Cancel juga pakai ini).
        guard !pingProgress.isRunning else {
            cancelPingAll()
            return
        }
        // PENTING: sasaran Ping All = PERSIS yang tampil di tabel, KECUALI filter
        // "Sembunyikan yang mati". Kalau filter tipe/sumber/cari aktif, hanya
        // itu yang diuji — bukan seluruh daftar. Fallback ke `nodes` dulu ada
        // di sini dan itu salah: filter yang tidak kecocokannya akan memicu
        // ping ke ribuan server.
        let targets = Self.pingTargets(nodes: nodes, search: searchText,
                                       proto: protoFilter, source: activeSourceFilter)
        guard !targets.isEmpty else {
            pingNotice = L10n.string("ping_no_target")
            return
        }
        pingNotice = nil

        // D93: satu putaran = satu log baru dan satu ringkasan. Log lama
        // dibuang di sini, bukan diam-diam menumpuk — membandingkan dua
        // putaran dengan konfigurasi berbeda (mis. target ping yang baru
        // diganti) hanya menghasilkan kesimpulan yang salah.
        pingLog.removeAll()
        currentRunAlive = 0
        currentRunFailures = [:]
        currentRunSkipped = 0
        pingSummary = PingRunSummary(startedAt: Date(),
                                    targetHost: currentPingTargetHost,
                                    mode: settings.pingTarget)
        logPingSession(L10n.formatted("ping_log_run_start", currentPingTargetHost))

        // Tanpa `hideDeadNodes`, semua yang tampil memang sudah ikut teruji,
        // jadi flag "cakupan tersaring" hanya boleh menyala kalau ada filter
        // lain yang benar-benar mempersempit sasaran.
        pingProgress = PingProgress(isRunning: true, total: targets.count)
        pingScopeFiltered = targets.count < (settings.hideDeadNodes ? nodes.count : targets.count)
        // Governor tetap dijalankan di kedua mode: AIMD-nya bereaksi pada beban
        // CPU nyata, dan handshake thousands-of-sockets memang bisa membuat
        // mesin panas walau tidak ada kriptografi. Menjalankannya hanya di satu
        // mode akan membuat Setting Performance berperilaku berbeda tergantung
        // mode ping — persis kejutan yang tidak diinginkan user.
        let fast = settings.fastPing
        pingFastCancelled = false
        defer {
            cpu.stop()
            probe.endSession()
            pingProgress = PingProgress()
            pingScopeFiltered = false
        }

        cpu.start()
        // PERFORMANCE: tiap hasil ping DULUNYA langsung menulis ke @Published
        // (ping + pingProgress) -> satu invalidasi penuh UI + satu re-sort
        // 16.000 node PER NODE. Dengan 16.000 node ini = 16.000 render, itulah
        // "app lemot + sering loading" saat Ping All. Sekarang hasil ditampung
        // dan di-flush berkala (0.5 dtk) — UI tetap terasa live, render 99%
        // lebih sedikit.
        var batched: [String: ProbeVerdict] = [:]
        var batchedFast: [String: ServerPingOutcome] = [:]
        var done = 0
        var online = 0
        var lastFlush = Date()
        // Dua jalur, satu loop flush: menulis ulang flush di dua tempat berarti
        // perubahan throttle nanti hanya berlaku ke salah satunya.
        func flush(force: Bool) {
            guard !batched.isEmpty || !batchedFast.isEmpty else { return }
            let elapsed = Date().timeIntervalSince(lastFlush)
            guard force || elapsed >= 0.5 else { return }
            for (id, verdict) in batched { apply(verdict, for: id) }
            for (id, outcome) in batchedFast { apply(outcome, for: id) }
            batched.removeAll()
            batchedFast.removeAll()
            pingProgress.done = done
            pingProgress.online = online
            lastFlush = Date()
        }

        if fast {
            await pingAllFast(targets, concurrency: max(1, cpu.computeLimit)) { [weak self] id, outcome in
                guard self != nil else { return }
                batchedFast[id] = outcome
                done += 1
                if case .dead = outcome { /* tidak dihitung online */ }
                else { online += 1 }
                flush(force: false)
            }
            finalizePingSummary(tested: done, rejectedByCore: 0)
        } else {
            // D91 — plafon waktu. Cek internet sungguhan TIDAK bisa
            // menyelesaikan 20.000+ node: 37 sesi core, tiap sesi menjalankan
            // timeout penuh pada ratusan node yang sebagian besar mati. Versi
            // lama membiarkan itu berjalan tanpa henti, dan karena pengurutan
            // baru terjadi di akhir, tabel Server menampilkan "—" untuk
            // semua orang sepanjang acetone jam — persis gejala "ping tidak
            // muncul dan lama".
            //
            // Sekarang: berhenti bersih setelah `pingInternetBudget`, sisa
            // node tetap "belum teruji" (bukan mati), dan hasilnya diurutkan
            // serta disimpan BERKALA supaya angka yang sudah didapat langsung
            // terlihat di tabel.
            let deadline = Date().addingTimeInterval(AppConstants.pingInternetBudget)
            var lastSort = Date()
            func resortIfDue() {
                guard settings.autoSortAfterPing else { return }
                guard Date().timeIntervalSince(lastSort) >= 2 else { return }
                lastSort = Date()
                sortByMeasuredLatency()
            }
            await probe.verify(nodes: targets, testURL: currentPingTargetURL,
                               concurrency: max(1, cpu.computeLimit),
                               deadline: deadline,
                               limitProvider: { [weak self] in
                self?.cpu.refreshIfNeeded()
                return max(1, self?.cpu.computeLimit ?? 2)
            }) { [weak self] id, verdict in
                guard self != nil else { return }
                batched[id] = verdict
                done += 1
                if case .ok = verdict { online += 1 }
                flush(force: false)
                resortIfDue()
            }
            flush(force: true)
            if Date() >= deadline && done < targets.count {
                pingNotice = L10n.formatted("ping_budget_hit", done, targets.count)
                logPingSession(L10n.formatted("ping_log_budget_hit", done, targets.count))
            }
            finalizePingSummary(tested: done, rejectedByCore: probe.lastRejectedCount)
        }
        flush(force: true)

        if settings.autoSortAfterPing {
            sortByMeasuredLatency()
            persist()
        }
    }

    /// Letakkan node yang sudah terukur di depan, yang belum teruji di
    /// belakang.
    ///
    /// D91: dipakai BERKALA selama Ping All berjalan, bukan cuma di akhir.
    /// Kalau pengurutan hanya terjadi setelah semua selesai, user melihat
    /// tabel penuh "—" selama berjam-jam dan tidak punya cara memastikan
    /// pengujiannya sedang bekerja.
    /// Tutup ringkasan putaran yang sedang berjalan (D93).
    private func finalizePingSummary(tested: Int, rejectedByCore: Int) {
        let notTested = max(0, pingProgress.total - tested)
        pingSummary = PingRunSummary(
            startedAt: pingSummary?.startedAt ?? Date(),
            targetHost: currentPingTargetHost,
            mode: settings.pingTarget,
            tested: tested,
            alive: currentRunAlive,
            rejectedByCore: rejectedByCore,
            notTested: notTested,
            stoppedByBudget: notTested > 0,
            byFailure: currentRunFailures)
        if tested > 0 {
            logPingSession(L10n.formatted("ping_log_run_done", currentRunAlive, tested,
                                          currentPingTargetHost))
        }
    }

    private func sortByMeasuredLatency() {
        let ping = self.ping
        // `enumerated()` sebagai pengikat: tanpa itu pengurutan tidak stabil
        // dan daftar akan berlonjak tiap 2 detik.
        let ordered = nodes.enumerated().sorted { a, b in
            let la = ping[a.element.id]?.bestMs ?? Int.max
            let lb = ping[b.element.id]?.bestMs ?? Int.max
            return la == lb ? a.offset < b.offset : la < lb
        }.map(\.element)
        // Hanya tulis kalau urutannya benar-benar berubah: `nodes` punya
        // `didSet` yang membangun ulang index dan membuang semua cache turunan,
        // jadi menulis tanpa perubahan berarti menggambar ulang seluruh UI.
        if ordered.map(\.id) != nodes.map(\.id) { nodes = ordered }
    }

    /// Jalur cepat untuk Ping All: TCP/UDP langsung per node, tanpa core.
    ///
    /// Konkurensi mengikuti governor yang SAMA dengan mode internet, jadi
    /// Setting Performance berlaku di kedua mode dan user tidak perlu belajar
    /// jatah baru. Bedanya hanya di mechanical: probe ini tidak menghasilkan
    /// session core, jadi tidak ada `beginSession`/`endSession` per potongan.
    private func pingAllFast(_ targets: [ProxyNode], concurrency: Int,
                             onResult: @escaping @MainActor (String, ServerPingOutcome) -> Void) async {
        guard !targets.isEmpty else { return }
        var next = 0
        var window = max(1, concurrency)
        var inflight = 0
        await withTaskGroup(of: Void.self) { group in
            func submit(_ node: ProxyNode) {
                group.addTask {
                    let outcome = await ServerPinger.ping(node)
                    await MainActor.run { onResult(node.id, outcome) }
                }
                inflight += 1
            }
            while next < min(window, targets.count) { submit(targets[next]); next += 1 }
            while inflight > 0 {
                await group.next()
                inflight -= 1
                if pingFastCancelled { break }
                cpu.refreshIfNeeded()
                window = max(1, cpu.computeLimit)
                while !pingFastCancelled, inflight < window, next < targets.count {
                    submit(targets[next]); next += 1
                }
            }
            group.cancelAll()
        }
    }

    public func cancelPingAll() {
        // Menyentuh dua jalur: `InternetProbe` punya sesinya sendiri (dan
        // `cancel()` saat tidak ada sesi aktif adalah no-op), sedangkan jalur
        // cepat tidak pernah menyentuh probe sama sekali.
        pingFastCancelled = true
        probe.cancel()
    }
}
