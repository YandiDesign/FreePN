import SwiftUI

/// Daftar server lengkap dengan pencarian, filter tipe, dan tabel bergaya
/// redesign.
struct ServersView: View {
    @EnvironmentObject var state: AppState
    @State private var showPingLog = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            filterBar
            table
            pingFooter
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheet(isPresented: $showPingLog) { pingLogSheet }
    }

    // MARK: - Kepala halaman

    private var header: some View {
        ScreenHeader("nav_servers", subtitle: "servers_subtitle") {
            HStack(spacing: 10) {
                Button {
                    Task { await state.pingAll() }
                } label: {
                    Label(state.pingProgress.isRunning ? "action_cancel" : "ping_all_action",
                          systemImage: "speedometer")
                }
                .buttonStyle(GhostButtonStyle())
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .help(pingScopeHelp)

                Button {
                    Task { await state.refreshAll() }
                } label: {
                    Label("action_refresh", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(state.isRefreshing)

                // D93 — log. Tanpa ini, "semua mati" dan "hanya 12 yang sempat
                // diuji" terlihat persis sama di layar.
                Button { showPingLog = true } label: {
                    Label("ping_log_open", systemImage: "list.bullet.rectangle")
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(state.pingLog.isEmpty)
                .help(L10n.string("ping_log_open"))
            }
        }
    }

    // MARK: - Log ping (D93)

    @ViewBuilder
    private var pingLogSheet: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("ping_log_title")
                        .font(Theme.screenTitle)
                        .foregroundColor(Palette.textPrimary)
                    if let s = state.pingSummary {
                        Text(s.headline)
                            .font(Theme.font(.callout))
                            .foregroundColor(Palette.textSecondary)
                    }
                }
                Spacer()
                Button("ping_log_clear") { state.clearPingLog() }
                    .buttonStyle(SecondaryButtonStyle())
                Button("action_close") { showPingLog = false }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            if let s = state.pingSummary, !s.failureChips.isEmpty
                || s.rejectedByCore > 0 || s.notTested > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ping_log_breakdown")
                        .font(Theme.font(.caption))
                        .foregroundColor(Palette.textTertiary)
                    // Ringkasan per sebab. Ini yang menjawab "kenapa semua
                    // mati": 300 timeout ≠ 300 kredensial salah.
                    HStack(spacing: 8) {
                        ForEach(s.failureChips, id: \.0) { why, count in
                            HStack(spacing: 5) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(Palette.danger)
                                Text(verbatim: "\(count)")
                                    .font(Theme.font(.caption).monospacedDigit())
                                    .foregroundColor(Palette.textPrimary)
                                Text(L10n.string("ping_log_failed_\(why.rawValue)"))
                                    .font(Theme.font(.caption))
                                    .foregroundColor(Palette.textSecondary)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                Capsule().fill(Palette.danger.opacity(0.10))
                            )
                        }
                    }
                    if s.rejectedByCore > 0 {
                        Text(L10n.formatted("ping_log_rejected_by_core", s.rejectedByCore))
                            .font(Theme.font(.caption))
                            .foregroundColor(Palette.warning)
                    }
                    if s.notTested > 0 {
                        Text(L10n.formatted("ping_log_not_tested", s.notTested))
                            .font(Theme.font(.caption))
                            .foregroundColor(Palette.warning)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }

            Divider()

            if state.pingLog.isEmpty {
                Text("ping_log_empty")
                    .font(Theme.font(.callout))
                    .foregroundColor(Palette.textTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // terbaru dulu — yang gerade user pedangikan
                List(Array(state.pingLog.reversed())) { e in
                    HStack(spacing: 10) {
                        Text(RelativeDate.string(for: e.at, language: state.settings.language))
                            .font(Theme.font(.caption).monospacedDigit())
                            .foregroundColor(Palette.textTertiary)
                            .frame(width: 96, alignment: .leading)
                        VStack(alignment: .leading, spacing: 1) {
                            // Baris `.session` TIDAK punya nama node — isinya
                            // pesan. Menampilkannya dua kali (sekali sebagai
                            // nama, sekali sebagai detail) terlihat seperti
                            // bug, jadi di sini pesan itu jadi TEKS UTAMA.
                            if e.kind == .session {
                                Text(verbatim: e.nodeName)
                                    .font(Theme.font(.caption))
                                    .foregroundColor(Palette.info)
                                    .lineLimit(2)
                            } else {
                                Text(verbatim: e.nodeName)
                                    .font(Theme.font(.callout))
                                    .foregroundColor(Palette.textPrimary)
                                    .lineLimit(1)
                                Text(verbatim: "\(e.proto) · \(e.host)")
                                    .font(Theme.font(.caption))
                                    .foregroundColor(Palette.textTertiary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 8)
                        if e.kind != .session {
                            Text(verbatim: e.summary)
                                .font(Theme.font(.caption))
                                .foregroundColor(e.ok ? Palette.success
                                              : (e.skipped ? Palette.textTertiary : Palette.danger))
                                .lineLimit(2)
                                .frame(maxWidth: 260, alignment: .trailing)
                        }
                        if let t = e.targetHost, e.kind != .session {
                            Text(verbatim: t)
                                .font(Theme.font(.caption))
                                .foregroundColor(Palette.textTertiary)
                                .frame(width: 130, alignment: .trailing)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 760, minHeight: 480)
    }

    // MARK: - Filter

    /// Toolbar filter.
    ///
    /// Dua baris, bukan satu. Chip protokol grew dari 4 jadi 8 (ada
    /// `.http` dan `.socks` sekarang), dan semuanya diletakkan sebaris
    /// dengan pencarian, dropdown sumber, tombol clear, dan toggle — totalnya
    /// melebihi lebar window sehingga SwiftUI sempat-sempat memampatkan
    /// toggle sampai label "hide_dead" pecah jadi beberapa baris dan angka
    /// jumlah server ikut tergencet. Memecahnya jadi dua baris membuat tiap
    /// kelompok punya lebar sendiri, dan tidak ada lagi yang perlu saling
    /// berebut ruang.
    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                SearchField("search_placeholder", text: $state.searchText)
                    .frame(maxWidth: 280)

                sourceDropdown

                if state.hasActiveFilter {
                    Button("action_clear_filter") {
                        state.searchText = ""
                        state.protoFilter = nil
                        state.sourceFilter = nil
                    }
                    .font(Theme.font(.caption))
                    .foregroundColor(Palette.mint)
                }

                Spacer(minLength: 0)

                deadNodesToggle

                // Pengayaan negara berjalan diam-diam setelah refresh.
                //
                // D68: TAMPILANNYA HANYA spinner. Sebelumnya ada teks
                // "Resolving locations…" yang berkedip di toolbar setiap kali
                // app dibuka — dan karena teks itu memakai `LocalizedStringKey`
                // dengan escape `\u2026`, yang kadang tampil literal
                // sebagai "lokasiu2026".
                //
                // Teksnya dihapus atas permintaan user, tapi spinner-nya TETAP
                // dipertahankan: tanpa penanda apa pun, kolom Country yang
                // kosong selama ~1 detik akan terbaca sebagai "kolom ini memang
                // tidak berfungsi", bukan "pekerjaan sedang jalan". Penjelasan
                // dipindah ke tooltip, yang muncul hanya kalau user memang
                // menanyakan.
                if state.isEnrichingCountries {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.7)
                        .fixedSize()
                        .help(Text("resolving_countries_help"))
                }

                Text(L10n.formatted("servers_count", state.filteredNodes.count))
                    .font(Theme.font(.caption))
                    .foregroundColor(Palette.textTertiary)
                    .monospacedDigit()
                    // Angka 4 digit melebar saat live refresh; tanpa ini label
                    // ikut bergeser tiap detachik.
                    .fixedSize(horizontal: true, vertical: false)
            }

            protoChips
        }
    }

    /// Toggle sembunyikan node mati.
    ///
    /// Labelnya diganti ikon `DeadNodeMark` (SVG dari user) — teks
    /// "Sembunyikan yang mati" adalah kalimat panjang, dan di toolbar yang
    /// sudah padat ia mengambil ruang lebih dari yang layak untuk satu
    /// sakelar. Makna ikonnya sekarang ada di tooltip, jadi tidak hilang.
    private var deadNodesToggle: some View {
        Toggle(isOn: $state.settings.hideDeadNodes) {
            DeadNodeMark()
                .fill(Palette.textSecondary)
                .frame(width: 15, height: 15)
                .help(Text("hide_dead"))
        }
        .toggleStyle(.switch)
        .tint(Palette.mint)
        .help(Text("hide_dead"))
        .fixedSize(horizontal: true, vertical: false)
        .onChange(of: state.settings.hideDeadNodes) { _ in state.persist(onlySettings: true) }
    }

    // MARK: - Dropdown sumber

    /// Filter per sumber, isi langsung dari daftar di menu Sumber.
    ///
    /// Chip protokol cuma punya 4 pilihan, jadi cukup di baris. Sumber berbeda
    /// kasusnya: bisa 7 sumber dengan 12.721 node di satu dan 92 di yang lain —
    /// jadi butuh daftar yang bisa dibuka, bukan deretan chip yang memenuhi
    /// seluruh baris filter.
    private var sourceDropdown: some View {
        let active = state.activeSourceFilter
        return Menu {
            Button { state.sourceFilter = nil } label: {
                Label {
                    Text("filter_all_sources")
                } icon: {
                    Image(systemName: active == nil ? "checkmark" : "")
                }
            }
            // Hanya sumber yang benar-benar punya node. Sumber mati (0 node)
            // tidak dicantumkan: memilihnya cuma menghasilkan tabel kosong,
            // dan itu terlihat seperti filter-nya rusak.
            if !liveSources.isEmpty { Divider() }
            ForEach(liveSources) { s in
                Button { state.sourceFilter = s.id } label: {
                    Label {
                        Text(verbatim: s.name)
                    } icon: {
                        Image(systemName: active == s.id ? "checkmark" : "")
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                if let id = active, let s = state.sources.first(where: { $0.id == id }) {
                    if s.isStarred {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                            .foregroundColor(Palette.warning)
                    }
                    Text(verbatim: s.name)
                } else {
                    Text("filter_all_sources")
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                }
            }
            .font(Theme.font(.callout))
            .foregroundColor(active == nil ? Palette.textSecondary : Palette.abyss)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 15)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(active == nil
                          ? AnyShapeStyle(Palette.navyDeep.opacity(0.6))
                          : AnyShapeStyle(Palette.mint))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(active == nil ? Palette.border
                                  : Color.white.opacity(0.32), lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize(horizontal: true, vertical: false)
        .help(Text("filter_source_help"))
    }

    /// Sumber yang punya node, berbintang dulu lalu menurut nama.
    ///
    /// D66: penentuan "punya node" WAJIB memakai node yang benar-benar termuat,
    /// bukan `keptCount`/`nodeCount` dari `sources.json`. Kedua angka itu bisa
    /// basi (mis. setelah sumber dihapus, atau `keptCount` masih 0 karena
    /// `resort` belum jalan) — dan dropdown yang menampilkan sumber tanpa satu
    /// pun node menghasilkan tabel kosong, yang terlihat persis seperti filter
    /// rusak.
    private var liveSources: [VPNSubscriptionSource] {
        let present = state.sourceIDsPresentInNodes
        return state.sources
            .filter { present.contains($0.id) }
            .sorted { a, b in
                if a.isStarred != b.isStarred { return a.isStarred }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
    }

    private var protoChips: some View {
        HStack(spacing: 7) {
            FilterChip("filter_all", selected: state.protoFilter == nil) {
                state.protoFilter = nil
            }
            ForEach(NodeProtocol.allCases, id: \.self) { p in
                FilterChip(title: p.badgeTitle, selected: state.protoFilter == p) {
                    state.protoFilter = (state.protoFilter == p) ? nil : p
                }
            }
        }
    }

    // MARK: - Tabel

    /// Lebar kolom tabel Server — SATU sumber kebenaran untuk header dan baris.
    ///
    /// Sebelumnya tiap lebar ditulis dua kali (satu di `tableHeader`, satu di
    /// `row(_:)`) dan keduanya sudah pernah melenceng: header memberi kolom
    /// Name `maxWidth: .infinity` sementara baris cuma `minWidth`, jadi
    /// Name di header memakan semua ruang sisa dan seluruh kolom di
    /// sebelah kanannya (Tipe / Latensi / Beban / Aksi) melenceng jauh ke
    /// kanan dibanding selnya. Sekarang keduanya baca konstanta yang sama,
    /// jadi tidak mungkin lagi tidak rata.
    private enum Col {
        static let spacing: CGFloat = 10
        static let star: CGFloat = 34
        static let country: CGFloat = 44
        static let source: CGFloat = 104
        /// Kolom Name = satu-satunya yang menyerap sisa ruang.
        static let nameMin: CGFloat = 120
        static let proto: CGFloat = 84
        static let latency: CGFloat = 104
        static let load: CGFloat = 92
        // Lebar tombol + ruang kosong di kiri/kanan. Mengecilkan kolom ini
        // sekaligus memperkecil jarak antar kolom, jadi tabel terasa lebih
        // rapat tanpa harus mengorbankan lebar kolom lain.
        static let action: CGFloat = 46
    }

    private var table: some View {
        TableCard {
            tableHeader
        } content: {
            if state.filteredNodes.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: state.isRefreshing ? "arrow.triangle.2.circlepath" : "magnifyingglass")
                        .font(.system(size: 20))
                        .foregroundColor(Palette.textTertiary)
                    Text(state.isRefreshing ? "refreshing_sources" : "empty_no_servers")
                        .font(Theme.font(.callout))
                        .foregroundColor(Palette.textTertiary)
                    if !state.isRefreshing {
                        Text("empty_hint_sources")
                            .font(Theme.font(.caption))
                            .foregroundColor(Palette.textTertiary)
                        Button("action_refresh") { Task { await state.refreshAll() } }
                            .buttonStyle(SecondaryButtonStyle(active: true))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            } else {
                // Angka ini sudah di-cache di `AppState` (turun dari
                // `filteredNodes`). Sebelumnya `compactMap` + `min` atas
                // 16.000 node DI DALAM `body` — O(n) tiap 2 detik selama
                // terhubung (D61).
                let best = state.bestLatency
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(state.filteredNodes) { n in
                            TableRowView(selected: state.selectedNodeID == n.id) {
                                row(n, best: best)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var tableHeader: some View {
        // Lebar + spacing harus PERSIS sama dengan `row(_:)` di bawah; keduanya
        // membaca `Col`. Baris Risiko kernel offset pakai `TableRowView`
        // (padding horizontal 14) di dalam LazyVStack yang sudah diberi
        // padding 8 — header jadi diberi lapisan 8 tambahan supaya sejajar
        // vertikal, bukan bergeser.
        HStack(spacing: Col.spacing) {
            // Kolom bintang tidak diberi judul: lebarnya cuma 34pt, jadi
            // "Favorit" akan terpotong jadi "Fa…".
            ColumnLabel("").frame(width: Col.star)
            // Bendera, bukan "Negara / Kota": isinya cuma emoji flag, jadi
            // judul panjang hanya jadi ellipsis ("N…") di kolom 44pt.
            SortableColumn("col_country", key: .country,
                          isActive: state.sort.key == .country,
                          arrow: state.sort.arrow,
                          toggle: { state.toggleSort(.country) }, width: Col.country)
            SortableColumn("col_source", key: .source,
                          isActive: state.sort.key == .source,
                          arrow: state.sort.arrow,
                          toggle: { state.toggleSort(.source) }, width: Col.source)
            SortableColumn("col_name", key: .name,
                          isActive: state.sort.key == .name,
                          arrow: state.sort.arrow,
                          toggle: { state.toggleSort(.name) }, minWidth: Col.nameMin)
            SortableColumn("col_proto", key: .proto,
                          isActive: state.sort.key == .proto,
                          arrow: state.sort.arrow,
                          toggle: { state.toggleSort(.proto) }, width: Col.proto)
            SortableColumn("col_latency", key: .latency,
                          isActive: state.sort.key == .latency,
                          arrow: state.sort.arrow,
                          toggle: { state.toggleSort(.latency) }, width: Col.latency)
            SortableColumn("col_load", key: .load,
                          isActive: state.sort.key == .load,
                          arrow: state.sort.arrow,
                          toggle: { state.toggleSort(.load) }, width: Col.load)
            Spacer(minLength: 0)
            ColumnLabel("col_action").frame(width: Col.action)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
    }

    /// Judul kolom yang bisa diklik untuk mengurutkan.
    ///
    /// Panah hanya muncul pada kolom yang sedang aktif — SHOW semua panah di
    /// setiap kolom membuat tabel terlihat seperti spreadsheet Excel dan
    /// tidak ada artinya: user tidak bisa tahu mana yang sedang berlaku.
    private struct SortableColumn: View {
        // Menerima HANYA apa yang dibutuhkannya, bukan `@EnvironmentObject
        // AppState`. Tujuh `SortableColumn` = tujuh subscriber ke objek
        // raksasa itu, jadi setiap perubahan apa pun pada AppState (termasuk
        // tiap flush verdict ping) mengevaluasi ulang seluruh header (D61).
        let isActive: Bool
        let arrow: String
        let toggle: () -> Void
        let title: LocalizedStringKey
        let key: ServerSortKey
        var width: CGFloat? = nil
        var minWidth: CGFloat? = nil

        init(_ title: LocalizedStringKey, key: ServerSortKey,
             isActive: Bool, arrow: String, toggle: @escaping () -> Void,
             width: CGFloat? = nil, minWidth: CGFloat? = nil) {
            self.title = title
            self.key = key
            self.isActive = isActive
            self.arrow = arrow
            self.toggle = toggle
            self.width = width
            self.minWidth = minWidth
        }

        var body: some View {
            let active = isActive
            Button { toggle() } label: {
                HStack(spacing: 3) {
                    Text(title)
                        .font(Theme.columnLabel)
                        .foregroundColor(active ? Palette.mint : Palette.textTertiary)
                        .lineLimit(1)
                    Image(systemName: active ? arrow : "arrow.up.arrow.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(active ? Palette.mint : Palette.textTertiary.opacity(0.45))
                }
                // Kolom bertetap lebarnya terkunci di `width`; kolom Name
                // (tanpa `width`) yang menyerap sisa ruang dan jadi satu-
                // satunya kolom yang menyusut kalau jendela dikecilkan.
                .frame(minWidth: width == nil ? minWidth : nil,
                       maxWidth: width ?? .infinity,
                       alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(Text(active ? "sort_toggle_help" : "sort_click_help"))
        }
    }

    private func row(_ n: ProxyNode, best: Int?) -> some View {
        HStack(spacing: Col.spacing) {
            FavoriteStar(active: state.favorites.contains(n.id)) { toggleFav(n) }
                .frame(width: Col.star)

            // Kolom ini Bendera, bukan tulisan (permintaan user): di tabel
            // 16.000 baris, nama negara memakan ruang yang jauh lebih mahal
            // daripada dua glyph, dan memindainya lebih lambat.
            // Nama negara tetap ada sebagai tooltip, jadi informasi tidak
            // hilang — hanya tidak lagi jadi bacaan utama.
            Text(CountryInfer.flagEmoji(for: n.countryCode))
                .font(Theme.font(.callout))
                .help(CountryInfer.displayName(for: n.countryCode) ?? n.name)
                .frame(width: Col.country, alignment: .leading)

            Text(state.sourceName(for: n.sourceID))
                .font(Theme.font(.caption))
                .foregroundColor(Palette.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(sourceURL(for: n))
                .frame(width: Col.source, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                Text(n.name)
                    .font(Theme.font(.subheadline))
                    .foregroundColor(Palette.textPrimary)
                    .lineLimit(1)
                // Ikuti toggle yang sama dengan kartu node di menu Sambung —
                // node yang sama tidak boleh tampil beda di dua layar.
                Text(n.endpoint(includePort: state.settings.showNodePort))
                    .font(Theme.font(.caption2))
                    .foregroundColor(Palette.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(n.endpoint(includePort: true))
            }
            // WAJIB `maxWidth: .infinity` supaya kolom ini — dan hanya kolom
            // ini — yang menyerap ruang sisa. Tanpa itu VStack ini hanya
            // selebar teksnya, seluruh kolom di kanannya melenceng ke kiri
            // dibanding kolomnya di header.
            .frame(minWidth: Col.nameMin, maxWidth: .infinity, alignment: .leading)

            ProtocolBadge(n.proto).frame(width: Col.proto, alignment: .leading)

            // Sel latensi diberi lebar & satu baris: "1.313 ms" tidak lagi
            // bisa membungkus dua baris dan mendorong kolom sebelahnya.
            LatencyCell(ms: state.ping[n.id]?.webLatencyMs,
                        dead: state.ping[n.id]?.isDeadEnd == true,
                        approximate: state.ping[n.id]?.approximate == true)
                .lineLimit(1)
                .frame(width: Col.latency, alignment: .leading)

            LoadBar(fraction: ConnectView.load(ms: state.ping[n.id]?.webLatencyMs, best: best),
                    measured: state.ping[n.id]?.webLatencyMs != nil)
                .help(Text("load_help"))
                .frame(width: Col.load, alignment: .leading)

            connectButton(for: n)
        }
        .contextMenu {
            Button { connectPressed(n) } label: {
                Label(NodeConnectButton.help(connectState(for: n)), systemImage: "power")
            }
            Button { Task { await state.pingOne(n) } } label: {
                Label("action_ping", systemImage: "speedometer")
            }
            Button { toggleFav(n) } label: {
                Label(state.favorites.contains(n.id) ? "action_unfavorite" : "action_favorite",
                      systemImage: state.favorites.contains(n.id) ? "star.slash" : "star")
            }
            Divider()
            Text(n.endpoint(includePort: true))
        }
    }

    // MARK: - Footer progres Ping All

    @ViewBuilder
    private var pingFooter: some View {
        let pr = state.pingProgress
        if pr.isRunning {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L10n.formatted("ping_running", pr.done, pr.total))
                        .font(Theme.font(.callout))
                        .foregroundColor(Palette.textPrimary)
                        .monospacedDigit()
                    Spacer()
                    Button("action_cancel") { state.cancelPingAll() }
                        .buttonStyle(SecondaryButtonStyle())
                }
                ProgressView(value: Double(pr.done), total: Double(max(1, pr.total)))
                    .tint(Palette.mint)
                HStack(spacing: 14) {
                    Label(L10n.formatted("ping_online_count", pr.online), systemImage: "globe")
                        .font(Theme.font(.caption))
                        .foregroundColor(Palette.success)
                    if state.pingScopeFiltered {
                        Label(L10n.formatted("ping_scope_filtered", state.filteredNodes.count,
                                             state.nodes.count),
                              systemImage: "line.3.horizontal.decrease.circle")
                            .font(Theme.font(.caption))
                            .foregroundColor(Palette.info)
                    }
                    if let err = state.probe.lastError {
                        Text(err)
                            .font(Theme.font(.caption))
                            .foregroundColor(Palette.warning)
                            .lineLimit(1)
                    }
                }
            }
            .padding(14)
            .freepnCard(padding: 14)
        } else if let notice = state.pingNotice {
            footerNotice(notice, tint: Palette.warning, symbol: "exclamationmark.triangle.fill")
        } else if let err = state.probe.lastError {
            footerNotice(err, tint: Palette.warning, symbol: "exclamationmark.triangle.fill")
        }
    }

    private func footerNotice(_ text: String, tint: Color, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundColor(tint)
            Text(text).font(Theme.font(.caption)).foregroundColor(Palette.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tint.opacity(0.09))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(tint.opacity(0.30), lineWidth: 1)
        )
    }

    // MARK: - Bantuan

    /// Bunyi tombol Ping All: hanya yang tampil/filter yang akan diuji.
    private var pingScopeHelp: String {
        let shown = state.filteredNodes.count
        let total = state.nodes.count
        if state.hasActiveFilter {
            return L10n.formatted("ping_scope_help_filtered", shown, total)
        }
        return L10n.formatted("ping_scope_help_all", total)
    }

    /// URL feed untuk inspect tooltip (node ini datang dari mana).
    ///
    /// Pakai peta yang sudah ada di `AppState` (`sourceURLs`), bukan linear
    /// scan `sources` — yang ini dipanggil SEKALI PER BARIS yang terlihat,
    /// dan `.help(...)` dievaluasi walau tooltip-nya tidak pernah dibuka
    /// (D61).
    private func sourceURL(for n: ProxyNode) -> String {
        state.sourceURL(for: n.sourceID)
    }

    // MARK: - Tombol Sambung per baris

    /// Catatan: logika keadaan + ikon menetap di `NodeConnectButton`
    /// (DesignSystem) supaya menu Server dan menu Sambung tidak berbeda
    /// perilaku. Status tetap dibaca dari `ConnectionManager` — satu sumber
    /// kebenaran; `AppState` meneruskan perubahannya lewat `objectWillChange`
    /// (AppState.swift:138) sehingga tabel ikut rebuild.

    private func connectButton(for n: ProxyNode) -> some View {
        NodeConnectButton(status: connectState(for: n), size: 26) { connectPressed(n) }
            .frame(width: Col.action, alignment: .trailing)
    }

    /// Keadaan tombol untuk node ini.
    ///
    /// Hanya node yang SEDANG jadi target sambung yang menampilkan status.
    /// `lastNode` selalu diisi lebih dulu (ConnectionManager.swift:85), jadi
    /// begitu user menekan Sambung baris itu langsung berubah jadi spinner —
    /// bukan menunggu core benar-benar siap. Node lain tetap panah: status
    /// "tersambung" milik satu baris, bukan seluruh tabel.
    private func connectState(for n: ProxyNode) -> ConnectionStatus {
        let c = state.connection
        guard c.lastNode?.id == n.id else { return .disconnected }
        return c.status
    }

    /// Tekan = sambung, atau putus kalau node ini yang sedang tersambung.
    private func connectPressed(_ n: ProxyNode) {
        if state.isConnected,
           state.connection.lastNode?.id == n.id {
            state.disconnect()
        } else {
            state.connect(node: n)
        }
    }

    private func toggleFav(_ n: ProxyNode) {
        if state.favorites.contains(n.id) { state.favorites.remove(n.id) }
        else { state.favorites.insert(n.id) }
        state.persist(onlyFavorites: true)
    }
}