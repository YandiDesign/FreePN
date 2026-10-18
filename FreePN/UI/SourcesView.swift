import SwiftUI
import UniformTypeIdentifiers

/// Daftar subscription: nama, URL, status, jumlah node, dan aksi per baris.
struct SourcesView: View {
    @EnvironmentObject var state: AppState
    @State private var showAdd = false
    /// Grup manual yang sedang dibuka (D93).
    @State private var openManualGroup: String? = nil
    @State private var showNewGroup = false
    @State private var newGroupName = ""
    @State private var pendingDelete: VPNSubscriptionSource?
    /// Sumber yang form-nya terbuka untuk diedit (D58).
    @State private var pendingEdit: VPNSubscriptionSource?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScreenHeader("nav_sources", subtitle: "sources_subtitle") {
                HStack(spacing: 10) {
                    Button {
                        Task { await state.refreshAll() }
                    } label: {
                        Label("action_refresh", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(state.isRefreshing)

                    Button { showAdd = true } label: {
                        Label("action_add", systemImage: "plus")
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    // D93 — grup yang diisi tangan, bukan diunduh.
                    Button {
                        newGroupName = L10n.string("manual_group_default_name")
                        showNewGroup = true
                    } label: {
                        Label("manual_group_new", systemImage: "square.and.pencil")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }

            summaryBar
            table
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheet(isPresented: $showAdd) { AddSourceView() }
        .sheet(item: $pendingEdit) { AddSourceView(editing: $0) }
        .sheet(isPresented: $showNewGroup) { newGroupSheet }
        .sheet(item: Binding(
            get: { openManualGroup.map { ManualGroupRef(id: $0) } },
            set: { openManualGroup = $0?.id })) { ref in
            ManualGroupView(sourceID: ref.id)
        }
        // D91: overlay tidak lagi menelan seluruh input layar.
        //
        // `Color` di dalam `.overlay` bersifat hit-testable, jadi versi lama
        // memblokir navigasi, scrolling, dan SETIAP tombol selama refresh — dan
        // refresh-nya bisa berjalan 3 menit 45 detik. Satu klik, layar mati,
        // tidak ada tombol batal: satu-satunya jalan keluar adalah menutup app.
        //
        // Sekarang: spinner + progres + tombol batal, dan sisanya tetap hidup.
        .overlay(alignment: .bottom) {
            if state.isRefreshing {
                refreshBanner
                    .padding(.bottom, 18)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: state.isRefreshing)
        // Konfirmasi dulu: menghapus sumber berarti semua server dari feed itu
        // ikut hilang, jadi tidak boleh terjadi karena klik tak sengaja.
        .alert(L10n.string("delete_source_title"), isPresented: deleteAlertBinding) {
            Button(L10n.string("action_delete"), role: .destructive) {
                if let s = pendingDelete { state.removeSource(id: s.id) }
                pendingDelete = nil
            }
            Button(L10n.string("action_cancel"), role: .cancel) { pendingDelete = nil }
        } message: {
            Text(deleteMessage)
        }
    }

    /// Pita progres di bawah layar, dengan tombol batal.
    ///
    /// D91: indikator yang tidak bergerak bukan indikator. Kalau unduhannya
    /// sedang mencoba tautan ke-7 dari 15, itu harus terlihat — dan user harus
    /// bisa membatalkannya, bukan menunggu.
    private var refreshBanner: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text(state.refreshProgress ?? L10n.string("card_never_refreshed"))
                .font(Theme.font(.callout))
                .foregroundColor(Palette.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
            Spacer(minLength: 0)
            Button {
                state.cancelRefresh()
            } label: {
                Text(L10n.string("refresh_cancel"))
                    .font(Theme.font(.callout))
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Palette.card)
                .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 1)
        )
        .frame(maxWidth: 520)
    }

    /// Layar Sumber yang masih kosong (D92).
    ///
    /// App mulai dari nol sumber, jadi inilah yang pertama dilihat setiap user
    /// baru. Dua jalur: tempel URL sendiri, atau ambil dari daftar feed gratis
    /// yang dikumpulkan — satu ketukan, tanpa mengetik, tapi TIDAK ada yang
    /// ditambahkan sampai user menekan.
    private var emptySources: some View {
        VStack(spacing: 18) {
            Image(systemName: "tray")
                .font(.system(size: 26))
                .foregroundColor(Palette.textTertiary)
            Text("sources_empty")
                .font(Theme.font(.callout))
                .foregroundColor(Palette.textSecondary)
            Button { showAdd = true } label: {
                Label("sources_add_url", systemImage: "plus")
            }
            .buttonStyle(PrimaryButtonStyle())

            VStack(spacing: 8) {
                Text("sources_suggested")
                    .font(Theme.font(.caption))
                    .foregroundColor(Palette.textTertiary)
                // Grid, bukan `FlowRow`: yang itu API Layout macOS 13+ dan
                // project ini belum memakainya di mana pun.
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)],
                          alignment: .leading, spacing: 8) {
                    ForEach(suggestions, id: \.url) { s in
                        Button {
                            // Tambah DAN langsung unduh: user menekan
                            // "mulai dari feed ini", jadi ia harusnya
                            // berakhir dengan server, bukan baris "Menunggu"
                            // yang harus ia tekan sekali lagi.
                            if let made = state.addSource(name: s.name, url: s.url) {
                                Task { await state.refreshSource(id: made.id) }
                            }
                        } label: {
                            Text(verbatim: s.name)
                                .font(Theme.font(.caption))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Palette.navyDeep.opacity(0.7))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(Palette.border, lineWidth: 1)
                                )
                                .foregroundColor(Palette.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: 560)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    /// Kolom teks dengan label — dipakai sheet grup manual.
    private func field(_ label: LocalizedStringKey, text: Binding<String>,
                       prompt: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(Theme.font(.caption))
                .foregroundColor(Palette.textSecondary)
            TextField("", text: text, prompt: Text(prompt ?? String(repeating: " ", count: 1))
                .foregroundColor(Palette.textTertiary))
                .textFieldStyle(.plain)
                .foregroundColor(Palette.textPrimary)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Palette.well)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Palette.border, lineWidth: 1)
                )
        }
    }

    /// Sheet pembuatan grup manual baru (D93).
    private var newGroupSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("manual_group_new")
                .font(Theme.screenTitle)
                .foregroundColor(Palette.textPrimary)
            field("add_source_name", text: $newGroupName)
            Text("manual_group_hint")
                .font(Theme.font(.caption))
                .foregroundColor(Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("action_cancel") { showNewGroup = false }
                    .buttonStyle(SecondaryButtonStyle())
                Button("action_add") {
                    state.addManualGroup(name: newGroupName)
                    openManualGroup = state.sources.last?.id
                    showNewGroup = false
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    /// Daftar feed gratis untuk DITAWARKAN — bukan di-seed ke state (D92).
    /// Yang sudah dipakai user difilter, supaya tidak ada tawaran yang
    /// otomatis ditolak.
    private var suggestions: [(name: String, url: String)] {
        let taken = Set(state.sources.map(\.url))
        return VPNSubscriptionSource.curated.filter { !taken.contains($0.url) }
    }

/// Ringkasan di atas tabel: berapa sumber hidup, berapa server terpakai.
    private var summaryBar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(Palette.success)
                Text(L10n.formatted("sources_summary", onlineCount, state.sources.count))
                    .font(Theme.font(.callout))
                    .foregroundColor(Palette.textPrimary)
            }
            HStack(spacing: 8) {
                Image(systemName: "server.rack")
                    .foregroundColor(Palette.mint)
                Text(L10n.formatted("sources_nodes_total", totalNodes))
                    .font(Theme.font(.callout))
                    .foregroundColor(Palette.textPrimary)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
            Text(lastRefreshText)
                .font(Theme.font(.caption))
                .foregroundColor(Palette.textTertiary)
        }
        .padding(14)
        .freepnCard(padding: 14)
    }

    private var onlineCount: Int {
        state.sources.filter { $0.status == .ok }.count
    }

    private var totalNodes: Int {
        state.sources.reduce(0) { $0 + $1.keptCount }
    }

    private var lastRefreshText: String {
        let dates = state.sources.compactMap(\.lastUpdated)
        guard let newest = dates.max() else {
            return NSLocalizedString("card_never_refreshed", comment: "")
        }
        return L10n.formatted("card_refreshed_ago",
                              RelativeDate.string(for: newest, language: state.settings.language))
    }

    private var table: some View {
        TableCard {
            // Lebar kolom + spacing 10 HARUS identik dengan baris di bawah,
            // dan offset horizontal header harus sama dengan offset baris
            // (TableRowView memakai padding horizontal 14, sedangkan LazyVStack
            // di dalamnya sudah diberi padding 8 — header pun harus +8).
            // Ketidakcocokan offset inilah penyebab header dan isi kolom
            // tidak sejajar vertikal.
            HStack(spacing: 10) {
                ColumnLabel("").frame(width: 34)
                ColumnLabel("col_source").frame(width: 230, alignment: .leading)
                ColumnLabel("col_status").frame(width: 110, alignment: .leading)
                // Kolom fleksibel: lebar ideal 210 (cukup untuk
                // "12824 dipakai · 8 tidak didukung"), sisanya diserap
                // spacer di baris header — tombol aksi tetap menempel
                // di kanan.
                ColumnLabel("col_detail").frame(minWidth: 210, maxWidth: 290, alignment: .leading)
                ColumnLabel("col_updated").frame(width: 110, alignment: .trailing)
                ColumnLabel("col_enabled").frame(width: 46)
                Spacer(minLength: 0)
                ColumnLabel("")
                    .frame(width: 98)
                    .help(Text("action_edit_source"))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
        } content: {
            if state.sources.isEmpty {
                emptySources
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(state.sources) { s in
                            TableRowView { row(s) }
                                .contextMenu {
                                    Button("action_edit_source") { pendingEdit = s }
                                    Button(L10n.string("delete_source_action"), role: .destructive) {
                                        pendingDelete = s
                                    }
                                    Button("action_refresh") { Task { await state.refreshSource(id: s.id) } }
                                    Divider()
                                    Button(s.isStarred ? "action_unstar_source" : "action_star_source") {
                                        toggleStar(s)
                                    }
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

    private func row(_ s: VPNSubscriptionSource) -> some View {
        HStack(spacing: 10) {
            Button { toggleStar(s) } label: {
                Image(systemName: s.isStarred ? "star.fill" : "star")
                    .font(.system(size: 14 * Theme.uiScale, weight: .medium))
                    .foregroundColor(s.isStarred ? Palette.warning : Palette.textTertiary)
                    .frame(width: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(Text(s.isStarred ? "action_unstar_source" : "action_star_source"))

            HStack(spacing: 10) {
                IconTile("link", size: 30, tint: Palette.info)
                VStack(alignment: .leading, spacing: 1) {
                    Text(s.name)
                        .font(Theme.font(.subheadline))
                        .foregroundColor(Palette.textPrimary)
                        .lineLimit(1)
                    Text(s.url)
                        .font(Theme.font(.caption2))
                        .foregroundColor(Palette.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(s.url)
                }
            }
            .frame(width: 230, alignment: .leading)

            statusPill(s)
                .frame(width: 110, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                if s.status == .ok, let note = countNote(s) {
                    Text(note)
                        .font(Theme.font(.caption))
                        .foregroundColor(Palette.textSecondary)
                        .lineLimit(1)
                        .help(note)
                } else if let err = s.lastError, !err.isEmpty, s.status != .ok {
                    Text(err)
                        .font(Theme.font(.caption))
                        .foregroundColor(Palette.danger)
                        .lineLimit(1)
                        .help(err)
                } else {
                    Text("—").font(Theme.font(.caption)).foregroundColor(Palette.textTertiary)
                }
                Text(L10n.formatted("sources_node_count", s.nodeCount))
                    .font(Theme.font(.caption2))
                    .foregroundColor(Palette.textTertiary)
                    .monospacedDigit()
            }
            .frame(minWidth: 210, maxWidth: 290, alignment: .leading)

            HStack(spacing: 5) {
                Image(systemName: "clock")
                    .font(.system(size: 10 * Theme.uiScale))
                    .foregroundColor(Palette.textTertiary)
                Text(relative(s.lastUpdated))
                    .font(Theme.font(.caption))
                    .foregroundColor(Palette.textTertiary)
                    .lineLimit(1)
            }
            .frame(width: 110, alignment: .trailing)

            MintToggle(isOn: Binding(
                get: { s.isEnabled },
                set: { on in
                    guard let idx = state.sources.firstIndex(where: { $0.id == s.id }) else { return }
                    state.sources[idx].isEnabled = on
                    state.persist(onlySources: true)
                }
            ))
            .frame(width: 46)

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                if !s.isManualGroup {
                    rowIconButton("arrow.clockwise", help: "action_retry") {
                        Task { await state.refreshSource(id: s.id) }
                    }
                    .disabled(state.isRefreshing)
                }

                // Grup manual punya tombol buka sendiri: isinya diisi tangan,
                // jadi tidak ada yang perlu diunduh dan tombol refresh pada
                // sumber seperti ini hanya terlihat tidak berguna.
                if s.isManualGroup {
                    rowIconButton("square.and.pencil", help: "manual_group_title") {
                        openManualGroup = s.id
                    }
                }

                rowIconButton("pencil", help: "action_edit_source") {
                    pendingEdit = s
                }

                rowIconButton("trash", help: "delete_source_help") {
                    pendingDelete = s
                }
            }
            .frame(width: s.isManualGroup ? 124 : 98, alignment: .trailing)
        }
    }

    /// Tombol ikon kecil di baris (refresh / edit / hapus) — bentuk yang sama
    /// dengan tombol aksi di tabel Server supaya dua tabel terasa satu keluarga.
    private func rowIconButton(_ symbol: String, help: LocalizedStringKey,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11 * Theme.uiScale, weight: .semibold))
                .foregroundColor(Palette.textSecondary)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Palette.navyDeep.opacity(0.7)))
                .overlay(Circle().strokeBorder(Palette.border, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(Text(help))
    }

    @ViewBuilder
    private func statusPill(_ s: VPNSubscriptionSource) -> some View {
        switch s.status {
        case .ok:
            // Tidak ada lagi status "Cached": isi layar selalu hasil unduhan
            // terakhir, jadi tidak pernah menyesatkan (D90).
            StatusPill("status_active", tint: Palette.success)
        case .failed, .unavailable:
            StatusPill("status_unavailable", tint: Palette.warning, filled: false)
        default:
            StatusPill("status_pending", tint: Palette.textTertiary, filled: false)
        }
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } })
    }

    private var deleteMessage: String {
        guard let s = pendingDelete else { return "" }
        return L10n.formatted("delete_source_message", s.name, s.nodeCount)
    }

    /// "7523 dipakai · 11 protokol lain · 3 korup" — memberitahu angka yang jujur,
    /// dan memisahkan DUA hal yang tadinya tercampur jadi satu (D62).
    ///
    /// Sebelumnya semua yang tidak jadi node dijumlahkan jadi "tidak
    /// didukung": entri dengan protokol yang tidak bisa dipakai app, DAN entri
    /// yang korup sendiri. Untuk feed `ermaozi`, 224 dari 279 itu protokol
    /// (http/socks5/anytls) dan sisanya node korup — user tidak punya cara
    /// melihat pemisahannya, dan "tidak didukung" terdengar seperti salah app
    /// padahal 55 di antaranya memang sampah dari feed.
    ///
    /// Angka ditambahkan DUA baris di tooltip supaya konteksnya jelas tanpa
    /// membuat kolom jadi lebar.
    private func countNote(_ s: VPNSubscriptionSource) -> String? {
        var parts: [String] = []
        if s.keptCount == 0 && s.nodeCount > 0 {
            parts.append(L10n.formatted("source_all_dupes", s.nodeCount))
        } else if s.keptCount > 0 {
            parts.append(L10n.formatted("source_kept", s.keptCount))
        }
        if s.unsupportedCount > 0 {
            parts.append(L10n.formatted("source_unsupported", s.unsupportedCount))
        }
        if s.unusableCount > 0 {
            parts.append(L10n.formatted("source_unusable", s.unusableCount))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func relative(_ d: Date?) -> String {
        guard let d = d else { return "—" }
        return RelativeDate.string(for: d, language: state.settings.language)
    }

    private func toggleStar(_ s: VPNSubscriptionSource) {
        guard let idx = state.sources.firstIndex(where: { $0.id == s.id }) else { return }
        state.sources[idx].isStarred.toggle()
        state.persist(onlySources: true)
    }
}

/// Pembungkus `String` supaya `.sheet(item:)` bisa dipakai untuk ID grup.
struct ManualGroupRef: Identifiable {
    let id: String
}

struct AddSourceView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) var dismiss
    /// Sumber yang sedang diedit. `nil` = menambah baru.
    ///
    /// Antesnya sumber hanya bisa ditambah, dihapus, di-refresh, dan
    /// dibintangi — TIDAK bisa diganti namanya. Itu masalah nyata setelah
    /// D58: pemulihkan daftar sumber menulis nama hasil tebakan, dan user
    /// tidak punya cara memperbaikinya kecuali mengedit JSON manual.
    var editing: VPNSubscriptionSource? = nil
    @State private var name = ""
    @State private var url = ""
    @State private var isStared = false
    /// URL sudah ada di daftar (D66). Ditampilkan di bawah kolom URL, bukan
    /// dialog: menambah feed itu aksi berulang, jadi pesan yang bisa dibaca
    /// tanpa menutup form jauh lebih berguna daripada alert sekali-tutup.
    @State private var duplicateMessage: String? = nil

    private var isEditing: Bool { editing != nil }

    /// Grup manual tidak punya URL sama sekali — isinya node yang diketik
    /// tangan, bukan hasil unduhan feed.
    ///
    /// Facts ini bukan cuma untuk menyembunyikan kolom: `isValidURL("")` false,
    /// dan tombol Simpan punya `.disabled(!isValidURL(url))`. Jadi sebelum
    /// baris ini ada, membuka form edit untuk grup manual menghasilkan form
    /// yang tombol Simpannya **selalu mati** — satu-satunya jalan rename grup
    /// jadi tidak pernah bisa dipakai sama sekali.
    private var isManualGroup: Bool { editing?.isManualGroup ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isEditing ? "edit_source_title" : "add_source_title")
                .font(Theme.screenTitle)
                .foregroundColor(Palette.textPrimary)

            VStack(alignment: .leading, spacing: 6) {
                Text("add_source_name")
                    .font(Theme.font(.caption))
                    .foregroundColor(Palette.textSecondary)
                TextField("", text: $name, prompt: Text("add_source_name").foregroundColor(Palette.textTertiary))
                    .textFieldStyle(.plain)
                    .foregroundColor(Palette.textPrimary)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Palette.well)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Palette.border, lineWidth: 1)
                    )
            }

            // Kolom URL disembunyikan untuk grup manual, bukan hanya
            // dinonaktifkan: kolom yang selalu kosong dan tidak bisa diisi
            // cuma menambah pertanyaan ("kenapa tidak bisa saya ketik URL?")
            // untuk sesuatu yang memang tidak punya konsep URL.
            if !isManualGroup {
                VStack(alignment: .leading, spacing: 6) {
                    Text("add_source_url")
                        .font(Theme.font(.caption))
                        .foregroundColor(Palette.textSecondary)
                    TextField("", text: $url, prompt: Text("https://…").foregroundColor(Palette.textTertiary))
                        .textFieldStyle(.plain)
                        .foregroundColor(Palette.textPrimary)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Palette.well)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(duplicateMessage == nil
                                              ? Palette.border : Palette.warning, lineWidth: 1)
                        )
                    // Pesan duplikat. Dibersihkan begitu URL berubah supaya tidak
                    // mengganggu saat user sedang memperbaiki salah ketik.
                    if let duplicateMessage {
                        Text(verbatim: duplicateMessage)
                            .font(Theme.font(.caption))
                            .foregroundColor(Palette.warning)
                    }
                }
                .onChange(of: url) { _ in duplicateMessage = nil }
            } else {
                Text("edit_source_manual_group_hint")
                    .font(Theme.font(.caption))
                    .foregroundColor(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Toggle(isOn: $isStared) {
                Text("action_star_source")
                    .font(Theme.font(.callout))
                    .foregroundColor(Palette.textSecondary)
            }
            .toggleStyle(.switch)
            .tint(Palette.mint)

            HStack {
                Spacer()
                Button("action_cancel") { dismiss() }
                    .buttonStyle(GhostButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button(isEditing ? "action_save" : "action_add") {
                    if let src = editing {
                        // Pemeriksaan duplikat juga berlaku saat edit. Tanpa
                        // `ignoring:`, sumber yang sedang diedit akan selalu
                        // dianggap duplikat dirinya sendiri; tanpa baris ini
                        // sama sekali, user bisa menyimpan dua entri untuk
                        // satu feed yang sama persis — persis D66, tapi lewat
                        // pintu yang tidak dijaga.
                        if !isManualGroup {
                            let clash = state.hasSource(url: url, ignoring: src.id)
                            guard !clash else {
                                duplicateMessage = L10n.string("source_already_added")
                                return
                            }
                        }
                        // `isStarred` ikut diteruskan. Tanpa itu sakelar bintang
                        // di form edit dibaca ke state lalu dibuang: user
                        // menggesernya, menekan Simpan, dan tidak terjadi apa
                        // apa — padahal formnya terlihat persis sama dengan
                        // form tambah.
                        state.renameSource(id: src.id, name: name.isEmpty ? url : name,
                                           url: url, isStarred: isStared)
                    } else {
                        // D66: tanpa penjagaan ini, URL yang sama bisa ditambahkan
                        // berkali-kali. Tiap salinan dapat UUID BARU, jadi user
                        // berakhir dengan 3 entri untuk 1 feed — dan tiap entri
                        // punya cache sendiri (berkali-kali unduhan), serta kolom
                        // "Keterangan" yang berbunyi "semua duplikat" untuk
                        // semuanya kecuali yang pertama.
                        guard !state.hasSource(url: url) else {
                            duplicateMessage = L10n.string("source_already_added")
                            return
                        }
                        state.sources.append(
                            VPNSubscriptionSource(name: name.isEmpty ? url : name,
                                                  url: url,
                                                  isStarred: isStared,
                                                  isCustom: true))
                    }
                    state.persist(onlySources: true); dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
                // Grup manual tidak punya URL, jadi tidak boleh ikut
                // diperiksa dengan aturan URL — Simpan tetap harus hidup
                // selama namanya tidak kosong.
                .disabled(isManualGroup ? name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                        : !isValidURL(url))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
        .freepnBackdrop()
        // Nilai awal harus datang dari sumber yang diedit, bukan dari state
        // yang masih kosong — kalau tidak, form edit akan membuka dengan
        // kolom kosong dan Simpan menimpa nama aslinya dengan string kosong.
        .onAppear {
            guard let src = editing else { return }
            name = src.name
            url = src.url
            isStared = src.isStarred
        }    }

    /// URL kosong ditolak. Bentuknya divalidasi longgar (harus ada skema
    /// dan host) — validasi penuh URL ada di lapisan unduhan, dan menolak
    /// di sini dengan pesan yang membingungkan hanya menambah friksi.
    private func isValidURL(_ s: String) -> Bool {
        guard let u = URL(string: s),
              let scheme = u.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              u.host?.isEmpty == false else { return false }
        return true
    }
}