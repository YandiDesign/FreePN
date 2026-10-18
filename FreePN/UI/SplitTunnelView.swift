import SwiftUI
import AppKit

/// Split Tunneling: pilih aplikasi yang memakai VPN dan yangdikecualikan.
struct SplitTunnelView: View {
    @EnvironmentObject var state: AppState
    @State private var apps: [DiscoveredApp] = []
    @State private var query = ""
    @State private var scanning = false
    /// Daftar pilihan yang BELUM disimpan.
    ///
    /// KONSEKUENSI YANG SENGAJA: perubahan tidak langsung ditulis ke
    /// `state.split`. Aturan split baru benar-benar berlaku setelah
    /// reconnect, jadi menyimpan di tengah jalan hanya memberi kesan
    /// "sudah berlaku" padahal belum — dan menyulitkan saat ada yang salah
    /// lalu dibatalkan. `Save` yang menjadi satu-satunya jalan keluar.
    @State private var staged: Set<String> = []
    /// Domain yang dipilih, ditahan dengan aturan yang sama seperti `staged`.
    ///
    /// Set terpisah, bukan satu set berisi keduanya, karena keduanya berakhir
    /// jadi rule sing-box yang berbeda (`process_path_regex` vs
    /// `domain_suffix`). Kalau dicampur, builder harus menebak tiap entri
    /// termasuk app atau domain — dan tebakan salah diam-diam.
    @State private var stagedDomains: Set<String> = []
    @State private var domainInput = ""
    /// Alasan input domain ditolak, untuk ditampilkan di bawah kolom.
    /// Bukan alert: menambah domain adalah aksi berulang, jadi pesan yang
    /// terbaca tanpa menutup form jauh lebih berguna.
    @State private var domainError: String? = nil
    /// Mode dan sakelar utama juga ditahan, supaya `Save` benar-benar
    /// menjadi satu transaksi.
    @State private var stagedMode: SplitMode = .exclusive
    @State private var stagedEnabled: Bool = true
    @State private var didLoad = false
    /// State di disk sudah terpasang? Semua operasi baca/tulis daftar app WAJIB
    /// menunggu ini — lihat catatan di `waitForHydration()`.
    @State private var hydrated = false

    private enum ListFilter: String, CaseIterable, Identifiable {
        case all, selected, excluded
        var id: String { rawValue }
        var titleKey: LocalizedStringKey {
            switch self {
            case .all: return "split_filter_all"
            case .selected: return "split_filter_vpn"
            case .excluded: return "split_filter_local"
            }
        }
        var symbol: String? {
            switch self {
            case .all: return nil
            case .selected: return "checkmark.shield.fill"
            case .excluded: return "globe"
            }
        }
    }
    @State private var listFilter: ListFilter = .all

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScreenHeader("nav_split", subtitle: "split_subtitle") {
                Button { rescan() } label: {
                    Label(scanning ? "scan_apps_running" : "scan_apps",
                          systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(scanning)
            }

            banner
            modeCards
            domainPanel
            changeLogPanel
            filterBar
            table
            footer
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            if apps.isEmpty { scan() }
        }
        .task {
            // Tunggu hidrasi dulu. `onAppear` bisa jalan sebelum store
            // sematan, dan tanpa tunggu ini buffer lokal menangkap daftar BAWAAN —
            // tabel sempat menampilkan "0 aplikasi dipilih" padahal file user
            // berisi dua. Kalau user menekan Save di celah itu, daftarnya
            // benar-benar tertimpa kosong: bukan tampilan yang salah, tapi data
            // yang hilang.
            await state.waitForHydration()
            loadFromStateIfNeeded()
            hydrated = true
        }
    }

    /// Terapkan nilai tersimpan ke buffer lokal satu kali saja.
    ///
    /// Hanya sekali: kalau setback tiap render, `Save` tidak akan pernah
    /// berarti apa-apa karena pilihan yang sedang diklik langsung tertimpa
    /// nilai lama.
    private func loadFromStateIfNeeded() {
        guard !didLoad else { return }
        staged = Set(state.split.activeApps)
        stagedDomains = Set(state.split.activeDomains)
        stagedMode = state.split.mode
        stagedEnabled = state.split.isEnabled
        didLoad = true
    }

    /// Ada perubahan yang belum disimpan?
    private var isDirty: Bool {
        staged != Set(state.split.activeApps)
            || stagedDomains != Set(state.split.activeDomains)
            || stagedMode != state.split.mode
            || stagedEnabled != state.split.isEnabled
    }

    // MARK: - Banner

    private var banner: some View {
        HStack(spacing: 14) {
            IconTile("lock.shield.fill", size: 42, tint: stagedEnabled ? Palette.mint : Palette.textTertiary)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("nav_split").font(Theme.font(.callout)).foregroundColor(Palette.textSecondary)
                    Text(stagedEnabled ? "split_banner_active" : "split_banner_off")
                        .font(Theme.cardTitle)
                        .foregroundColor(stagedEnabled ? Palette.mint : Palette.textTertiary)
                }
                Text(stagedEnabled ? "split_banner_detail_on" : "split_banner_detail_off")
                    .font(Theme.font(.caption))
                    .foregroundColor(Palette.textTertiary)
            }
            Spacer(minLength: 0)
            MintToggle(isOn: $stagedEnabled)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(stagedEnabled ? Palette.mint.opacity(0.07) : Palette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(stagedEnabled ? Palette.mint.opacity(0.35) : Palette.border,
                              lineWidth: 1)
        )
    }

    // MARK: - Kartu mode

    private var modeCards: some View {
        HStack(spacing: 12) {
            modeCard(.exclusive,
                     title: "mode_exclusive",
                     detail: "mode_exclusive_desc_short",
                     symbol: "globe")
            modeCard(.inclusive,
                     title: "mode_inclusive",
                     detail: "mode_inclusive_desc_short",
                     symbol: "checkmark.shield.fill")
        }
        .disabled(!stagedEnabled)
        .opacity(stagedEnabled ? 1 : 0.45)
    }

    private func modeCard(_ mode: SplitMode,
                          title: LocalizedStringKey,
                          detail: LocalizedStringKey,
                          symbol: String) -> some View {
        let selected = stagedMode == mode
        return Button {
            stagedMode = mode
        } label: {
            HStack(spacing: 13) {
                IconTile(symbol, size: 38,
                         tint: selected ? Palette.mint : Palette.textTertiary)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(Theme.font(.callout))
                        .foregroundColor(Palette.textPrimary)
                    Text(detail)
                        .font(Theme.font(.caption))
                        .foregroundColor(Palette.textTertiary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17 * Theme.uiScale))
                    .foregroundColor(selected ? Palette.info : Palette.textTertiary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? Palette.cardRaised : Palette.navyDeep.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? Palette.info.opacity(0.55) : Palette.border,
                                  lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Filter

    private var filterBar: some View {
        HStack(spacing: 12) {
            SearchField("split_search_apps", text: $query)
                .frame(maxWidth: 300)

            HStack(spacing: 7) {
                ForEach(ListFilter.allCases) { f in
                    Button { listFilter = f } label: {
                        HStack(spacing: 5) {
                            if let s = f.symbol {
                                Image(systemName: s)
                                    .font(.system(size: 10 * Theme.uiScale, weight: .semibold))
                            }
                            Text(f.titleKey)
                                .font(Theme.font(.caption))
                        }
                        .foregroundColor(listFilter == f ? Palette.abyss : Palette.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            Capsule(style: .continuous)
                                .fill(listFilter == f ? Palette.mint : Palette.navyDeep.opacity(0.6))
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(listFilter == f ? Color.white.opacity(0.3) : Palette.border,
                                              lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: 0)

            Text(L10n.formatted("split_apps_scanned", apps.count))
                .font(Theme.font(.caption))
                .foregroundColor(Palette.textTertiary)
                .monospacedDigit()
        }
    }

    // MARK: - Tabel aplikasi

    private var table: some View {
        TableCard {
            HStack(spacing: 10) {
                MintToggle(isOn: Binding(
                    get: { !filtered.isEmpty && filtered.allSatisfy { staged.contains($0.path) } },
                    set: { on in
                        for app in filtered { toggle(app, on: on) }
                    }
                ))
                .disabled(filtered.isEmpty)
                .frame(width: 42)

                ColumnLabel("col_app_name").frame(width: 190, alignment: .leading)
                ColumnLabel("col_path").frame(minWidth: 140, alignment: .leading)
                Spacer(minLength: 0)
                ColumnLabel("").frame(width: 30)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        } content: {
            if filtered.isEmpty {
                VStack(spacing: 10) {
                    if scanning {
                        ProgressView()
                        Text("scan_apps_running")
                            .font(Theme.font(.callout))
                            .foregroundColor(Palette.textTertiary)
                    } else {
                        Image(systemName: "questionmark.folder")
                            .font(.system(size: 20))
                            .foregroundColor(Palette.textTertiary)
                        Text(apps.isEmpty ? "split_no_apps" : "split_no_match")
                            .font(Theme.font(.callout))
                            .foregroundColor(Palette.textTertiary)
                        if apps.isEmpty {
                            Button("scan_apps") { scan() }
                                .buttonStyle(SecondaryButtonStyle(active: true))
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(filtered) { app in
                            TableRowView { appRow(app) }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                }
            }
        }
        // MINIMUM, bukan cuma `maxHeight: .infinity`.
        //
        // Tanpa minimum, `table` adalah satu-satunya view lentur di VStack ini
        // dan semua sibling-nya punya tinggi tetap. Begitu totalnya melewati
        // tinggi window, ScrollView-nya diremas ke 0 — daftar aplikasi lenyap
        // tanpa satu pesan pun, dan user menyimpulkan pemindaiannya gagal.
        // Ini yang terjadi setelah panel domain ditambahkan: panel itu menambah
        // tinggi tetap tanpa mengurangi apa pun.
        //
        // 240 = kira-kira 7-8 baris. Cukup untuk membuktikan pemindaian
        // bekerja, dan sisa ruang tetap milik tabel.
        .frame(minHeight: 240, maxHeight: .infinity)
    }

    private func appRow(_ app: DiscoveredApp) -> some View {
        let on = staged.contains(app.path)
        return HStack(spacing: 10) {
            MintToggle(isOn: Binding(get: { on }, set: { toggle(app, on: $0) }))
                .frame(width: 42)

            HStack(spacing: 10) {
                AppIconTile(path: app.path, name: app.name)
                Text(app.name)
                    .font(Theme.font(.subheadline))
                    .foregroundColor(Palette.textPrimary)
                    .lineLimit(1)
            }
            .frame(width: 190, alignment: .leading)

            Text(app.path)
                .font(Theme.font(.caption, design: .monospaced))
                .foregroundColor(Palette.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(app.path)
                .frame(minWidth: 140, alignment: .leading)

            Spacer(minLength: 0)

            // Menu per aplikasi. Dua aksi selalu aktif (bukan dibatasi mode):
            // "set sebagai VPN" berarti traffic app ini diarahkan ke proxy,
            // dan itu punya arti berbeda per mode — inklusif = masuk daftar,
            // eksklusif = KELUAR dari daftar bypass. Menyembunyikan salah
            // satunya demi mode tertentu hanya membuat user mencari-cari di
            // menu yang berbeda untuk setiap mode.
            Menu {
                Button { setUsesVPN(app, true) } label: {
                    Label("split_set_vpn", systemImage: "checkmark.shield")
                }
                Button { setUsesVPN(app, false) } label: {
                    Label("split_unset_vpn", systemImage: "globe")
                }
                Divider()
                Button("action_reveal_in_finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: app.path)])
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12 * Theme.uiScale, weight: .semibold))
                    .foregroundColor(Palette.textTertiary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .frame(width: 30)
        }
    }

    // MARK: - Riwayat perubahan

    /// Riwayat perubahan aturan split per aplikasi.
    ///
    /// Muncul tepat di bawah kartu mode, bukan di panel Log menu Sambung,
    /// karena aksi yang dia perjelas terjadi DI SINI. Panel Log tetap ikut
    /// menampilkan entri yang sama supaya jejaknya tersimpan dan bisa
    /// disalin saat user perlu melaporkannya.
    ///
    /// Yang ditampilkan bukan "Remote Chrome", tapi APA yang ditulis ke
    /// config (rule routing atau env proxy) dan KAPAN ia benar-benar berlaku
    /// — dua informasi yang paling sering disalahartikan user.
    private var changeLogPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                IconTile("list.bullet.rectangle", size: 34, tint: Palette.textSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("splitlog_title")
                        .font(Theme.cardTitle)
                        .foregroundColor(Palette.textPrimary)
                    Text("splitlog_subtitle")
                        .font(Theme.font(.caption))
                        .foregroundColor(Palette.textTertiary)
                }
                Spacer(minLength: 0)
                if !state.splitChanges.isEmpty {
                    Button {
                        state.splitChanges = []
                        SplitChangeLog.save([])
                    } label: {
                        Label("splitlog_clear", systemImage: "trash")
                    }
                    .buttonStyle(GhostButtonStyle())
                }
            }
            .padding(14)

            if state.splitChanges.isEmpty {
                Text("splitlog_empty")
                    .font(Theme.font(.callout))
                    .foregroundColor(Palette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
            } else {
                Divider().overlay(Palette.border)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(recentChanges) { entry in
                            changeRow(entry)
                            Divider().overlay(Palette.border.opacity(0.6))
                        }
                    }
                }
                .frame(maxHeight: 190)
            }
        }
        .freepnCard(padding: 0)
    }

    /// Hanya 6 entri terakhir: panel ini untuk "cek perubahan terakhir saya",
    /// bukan arsip. Riwayat penuh tetap ada di berkas dan di panel Log.
    private var recentChanges: [SplitChangeLog.Entry] {
        Array(state.splitChanges.suffix(6).reversed())
    }

    private func changeRow(_ entry: SplitChangeLog.Entry) -> some View {
        let enabling = entry.action == .enable
        let tint = enabling ? Palette.success : Palette.textTertiary
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: enabling ? "checkmark.shield.fill" : "globe")
                .font(.system(size: 11 * Theme.uiScale, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 18, height: 18)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(SplitChangeLog.describe(entry).enumerated()), id: \.offset) { idx, line in
                    Text(LocalizedStringKey(line))
                        .font(Theme.font(.caption))
                        .foregroundColor(idx == 0 ? Palette.textPrimary : Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(entry.at.formatted(date: .omitted, time: .standard))
                    .font(Theme.overline)
                    .foregroundColor(Palette.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Panel domain

    /// Kolom tambah domain + daftar domain yang dipilih.
    ///
    /// Diletakkan DI ATAS tabel app, bukan di bawah, karena daftar domain
    /// yang jauh lebih pendek dan justru yang paling sering dipakai: orang
    /// yang mau "video.com lewat VPN, bank.com bypass" tidak perlu menggulir
    /// ratusan baris aplikasi untuk menemukan kolomnya.
    private var domainPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            // SATU BARIS: ikon + label + kolom + tombol. Sebelumnya header-nya
            // dua baris (judul + subtitle panjang) dan input-nya baris sendiri,
            // jadi panel memakan ~134 pt.
            //
            // Itu cukup untuk membuat daftar aplikasi HILANG TOTAL. Layar ini
            // VStack berisi banyak section tinggi tetap (banner, modeCards,
            // changeLogPanel, filterBar, footer) dan `table` hanya punya
            // `maxHeight: .infinity` — tanpa minimum. begitu total tinggi
            // sibling melewati tinggi window, ScrollView di `table` diremas
            // sampai 0 dan user melihat "tidak ada aplikasi" padahal 114 app
            // ada di /Applications. Nowrap `·` dipakai sebagai pemisah supaya
            // subtitle tidak memakan lebar.
            HStack(spacing: 10) {
                Image(systemName: "globe")
                    .foregroundColor(Palette.mint)
                Text("split_domain_title")
                    .font(Theme.font(.callout))
                    .foregroundColor(Palette.textPrimary)
                    .fixedSize()

                TextField("", text: $domainInput,
                          prompt: Text("split_domain_placeholder").foregroundColor(Palette.textTertiary))
                    .textFieldStyle(.plain)
                    .foregroundColor(Palette.textPrimary)
                    .padding(7)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Palette.well)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(domainError == nil ? Palette.border : Palette.warning,
                                          lineWidth: 1)
                    )
                    .frame(maxWidth: 260)
                    .onSubmit(addDomain)

                Button(action: addDomain) {
                    Label("split_domain_add", systemImage: "plus")
                }
                .buttonStyle(SecondaryButtonStyle(active: true))
                .disabled(domainInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Text(L10n.formatted("split_domain_count", stagedDomains.count))
                    .font(Theme.font(.caption))
                    .foregroundColor(Palette.textTertiary)
                    .monospacedDigit()
                    .fixedSize()

                Spacer(minLength: 0)

                if let domainError {
                    Text(verbatim: domainError)
                        .font(Theme.font(.caption))
                        .foregroundColor(Palette.warning)
                        .lineLimit(1)
                }
            }
            .controlSize(.small)
            .disabled(!stagedEnabled)
            .opacity(stagedEnabled ? 1 : 0.45)

            if !stagedDomains.isEmpty {
                // `sorted` supaya urutannya tidak ikut bergantung pada urutan
                // Set, yang tidak dijamin. Daftar yang berubah urutan setiap
                // kali rule ditulis ulang bikin diff di `split.json` selalu
                // berisi perubahan palsu.
                WrapLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(stagedDomains.sorted(), id: \.self) { d in
                        domainChip(d)
                    }
                }
            }
        }
        .padding(12)
        .freepnCard(padding: 12)
    }

    /// Satu domain sebagai chip: nama host + tombol hapus.
    ///
    /// Label memakai arah mode yang sedang aktif, bukan "include/exclude" —
    /// user sudah membaca dua kartu mode di atas, jadi mengulang kosakata
    /// yang sama hanya menambah pekerjaan baca.
    private func domainChip(_ d: String) -> some View {
        let usesVPN = stagedMode.usesVPN(appIsListed: true)
        return HStack(spacing: 6) {
            Image(systemName: usesVPN ? "checkmark.shield.fill" : "globe")
                .font(Theme.font(.caption2))
                .foregroundColor(usesVPN ? Palette.mint : Palette.textSecondary)
            Text(verbatim: d)
                .font(Theme.font(.caption, design: .monospaced))
                .foregroundColor(Palette.textPrimary)
            Button {
                stagedDomains.remove(d)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(Theme.font(.caption))
            }
            .buttonStyle(.plain)
            .foregroundColor(Palette.textTertiary)
            .help(L10n.string("split_domain_remove"))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous).fill(Palette.well)
        )
        .overlay(
            Capsule(style: .continuous).strokeBorder(Palette.border, lineWidth: 1)
        )
    }

    /// Terima input domain, normalkan, lalu masukkan ke buffer.
    ///
    /// Normalisasi dilakukan di sini, bukan nanti saat `Save`: bentuk yang
    /// tampil di chip harus sama persis dengan bentuk yang akan ditulis ke
    /// `split.json`. Kalau normalisasi ditunda, user mengetik `*.Example.com`
    /// dan chip-nya berbunyi `*.Example.com`, lalu setelah Save berubah jadi
    /// `example.com` — seolah app salah.
    private func addDomain() {
        let typed = domainInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return }
        guard let clean = SplitTunnelConfig.normalizeDomain(typed) else {
            domainError = L10n.string("split_domain_invalid")
            return
        }
        guard !stagedDomains.contains(clean) else {
            domainError = L10n.string("split_domain_duplicate")
            return
        }
        stagedDomains.insert(clean)
        domainInput = ""
        domainError = nil
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(Palette.success)
                Text(L10n.formatted("split_selected_count", staged.count))
                    .font(Theme.font(.callout))
                    .foregroundColor(Palette.textPrimary)
                    .monospacedDigit()
            }
            // Domain ikut dihitung di footer, kalau tidak user tidak punya
            // cara tahu ada domain yang menunggu di buffer tapi belum
            // disimpan — dan `Save` tetap nonaktif karena daftar app saja
            // tidak berubah.
            if !stagedDomains.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "globe")
                        .foregroundColor(Palette.mint)
                    Text(L10n.formatted("split_domain_count", stagedDomains.count))
                        .font(Theme.font(.callout))
                        .foregroundColor(Palette.textSecondary)
                        .monospacedDigit()
                }
            }
            if isDirty {
                Text("split_unsaved_hint")
                    .font(Theme.font(.caption))
                    .foregroundColor(Palette.warning)
            }
            Spacer(minLength: 0)
            Button {
                staged.removeAll()
                stagedDomains.removeAll()
            } label: {
                Label("split_clear_all", systemImage: "trash")
            }
            .buttonStyle(GhostButtonStyle())
            .disabled(staged.isEmpty && stagedDomains.isEmpty)

            Button { save() } label: {
                Label("split_save", systemImage: "square_and.arrow.down")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!isDirty || !hydrated)
        }
        .padding(14)
        .freepnCard(padding: 14)
    }

    // MARK: - Aksi

    /// Arahkan traffic app ini lewat proxy — atau kembalikan ke koneksi biasa.
    ///
    /// Satu fungsi untuk dua arah supaya tidak ada tempat lain di UI yang
    /// bisa memakai definisi "memakai VPN" yang berbeda (bandingkan
    /// `AppState.usesVPN`). Dan ini bukan "masukkan ke daftar": di mode
    /// eksklusif, daftar justru berisi app yang **tidak** lewat VPN, jadi
    /// "set sebagai VPN" berarti mengeluarkan app dari daftar.
    private func setUsesVPN(_ app: DiscoveredApp, _ wants: Bool) {
        let isListed = staged.contains(app.path)
        // Exclusive berbalik arah: tidak terdaftar = lewat VPN.
        let shouldBeListed = stagedMode == .exclusive ? !wants : wants
        if isListed == shouldBeListed { return }
        if shouldBeListed { staged.insert(app.path) } else { staged.remove(app.path) }
    }

    private func toggle(_ app: DiscoveredApp, on: Bool) {
        if on { staged.insert(app.path) } else { staged.remove(app.path) }
    }

    /// Terapkan buffer lokal ke settings, lalu cek ulang kesehatan.
    ///
    /// Peringatan inclusive-kosong tetap muncul sebagai banner di atas —
    /// menyimpan keadaan itu tidak berarti app diam-diam mengizinkan VPN yang
    /// tidak mem-VPN-kan apa pun; `ConnectionManager` tetap menolak Connect.
    private func save() {
        // Menolak keras lebih baik daripada menimpa daftar user dengan buffer
        // yang belum pernah diisi dari disk.
        guard hydrated else { return }
        // Snapshot mode SEBELUM apa pun berubah — `logDiffs` membandingkan
        // efek app sebelum/sesudah, dan setelah mode ditulis nilai lamanya
        // sudah hilang.
        previousMode = state.split.mode
        commitStaged()
    }

    /// Terapkan buffer lokal (daftar + sakelar) ke settings.
    ///
    /// Peringatan inclusive-kosong tetap muncul sebagai banner di atas —
    /// menyimpan keadaan itu tidak berarti app diam-diam mengizinkan VPN yang
    /// tidak mem-VPN-kan apa pun; connect tetap ditolak.
    private func commitStaged() {
        // Snapshot DIBACA SEBELUM `replaceActive` menimpa daftar lama; setelah
        // itu tidak ada yang bisa tahu mana yang baru aktif.
        let listedBefore = Set(state.split.activeApps)
        let domainsBefore = Set(state.split.activeDomains)

        state.split.mode = stagedMode
        state.split.isEnabled = stagedEnabled
        // Dua pemanggilan terpisah, bukan satu. `replaceActive` sengaja
        // mengosongkan daftar lawannya, jadi kalau domain ikut lewat sana,
        // satu Save sudah menghapus seluruh pengaturan domain tanpa jejak.
        state.split.replaceActive(with: Array(staged))
        state.split.replaceActiveDomains(with: Array(stagedDomains))
        logDiffs(listedBefore: listedBefore, listedAfter: staged,
                 domainsBefore: domainsBefore, domainsAfter: stagedDomains)
        state.persist(onlySplit: true)
        state.checkHealth()
    }

    /// Tulis entri riwayat untuk setiap app DAN domain yang perannya berubah.
    ///
    /// Yang dibandingkan bukan "ada/tidak di daftar", tapi efek akhirnya
    /// ("apakah trafiknya lewat VPN"). Untuk mode eksklusif keduanya berlawanan,
    /// jadi membandingkan daftar mentah akan mencatat perubahan yang tidak
    /// mengubah apa pun, sekaligus melewatkan perubahan yang sebenarnya
    /// mengubah segalanya.
    ///
    /// Mengganti mode ikut tercatat selama efeknya benar-benar berbalik;
    /// mode yang diganti tanpa mengubah satu pun entri tidak menghasilkan apa
    /// pun, karena memang tidak ada yang berubah.
    private func logDiffs(listedBefore: Set<String>, listedAfter: Set<String>,
                          domainsBefore: Set<String>, domainsAfter: Set<String>) {
        for change in SplitChangeLog.diff(listedBefore: listedBefore,
                                          listedAfter: listedAfter,
                                          modeBefore: previousMode,
                                          modeAfter: state.split.mode) {
            state.recordSplitChange(appName: displayName(for: change.bundlePath),
                                    bundlePath: change.bundlePath,
                                    mode: state.split.mode,
                                    action: change.action)
        }
        // Diff terpisah untuk domain: satu panggilan gabungan akan menulis
        // `example.com` ke riwayat seolah itu path aplikasi, dan `describe`
        // akan menjelaskannya dengan `process_path_regex` yang salah besar.
        for change in SplitChangeLog.diff(listedBefore: domainsBefore,
                                          listedAfter: domainsAfter,
                                          modeBefore: previousMode,
                                          modeAfter: state.split.mode,
                                          isDomain: true) {
            state.recordSplitChange(appName: change.bundlePath,
                                    bundlePath: change.bundlePath,
                                    mode: state.split.mode,
                                    action: change.action,
                                    isDomain: true)
        }
    }

    /// Mode sebelum commit —diperbarui saat `save()` dipanggil.
    @State private var previousMode: SplitMode = .exclusive

    private func displayName(for path: String) -> String {
        apps.first { $0.path == path }?.name
            ?? ((path as NSString).lastPathComponent as NSString).deletingPathExtension
    }


    private var filtered: [DiscoveredApp] {
        var list = apps
        if !query.isEmpty {
            list = list.filter { $0.name.localizedCaseInsensitiveContains(query) }
        }
        switch listFilter {
        case .all: break
        case .selected: list = list.filter { staged.contains($0.path) }
        case .excluded: list = list.filter { !staged.contains($0.path) }
        }
        return list
    }

    private func scan() {
        scanning = true
        DispatchQueue.global().async {
            let fm = FileManager.default
            let dirs = ["/Applications", NSHomeDirectory() + "/Applications", "/System/Applications"]
            var found: [DiscoveredApp] = []
            for d in dirs {
                guard let items = try? fm.contentsOfDirectory(atPath: d) else { continue }
                for it in items where it.hasSuffix(".app") {
                    let full = (d as NSString).appendingPathComponent(it)
                    let plist = (full as NSString).appendingPathComponent("Contents/Info.plist")
                    var name = (it as NSString).deletingPathExtension
                    var bid: String? = nil
                    if let dict = NSDictionary(contentsOfFile: plist) as? [String: Any] {
                        if let n = dict["CFBundleName"] as? String, !n.isEmpty { name = n }
                        bid = dict["CFBundleIdentifier"] as? String
                    }
                    found.append(DiscoveredApp(id: full, name: name, bundleID: bid, path: full))
                    if found.count > 800 { break }
                }
            }
            found.sort { $0.name < $1.name }
            // Buang duplikat path yang sama (mis. symlink /Applications ganda).
            var seen = Set<String>()
            found.removeAll { !seen.insert($0.path).inserted }
            DispatchQueue.main.async { apps = found; scanning = false }
        }
    }

    private func rescan() {
        apps = []
        scan()
    }
}

/// Ikon aplikasi asli (`.icns` di dalam bundle), dengan fallback ke inisial
/// kalau ikon tidak bisa dibaca.
///
/// Ikon dibaca sekali lalu disimpan di cache statis: `NSWorkspace.icon(forFile:)`
/// menyentuh disk, dan dipanggil tiap baris tiap redraw akan terasa berat
/// saat daftar aplikasi panjang.
struct AppIconTile: View {
    let path: String
    let name: String

    private static var cache: [String: NSImage] = [:]
    private static let cacheLock = NSLock()

    private static func icon(for path: String) -> NSImage? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let hit = cache[path] { return hit }
        let image = NSWorkspace.shared.icon(forFile: path)
        cache[path] = image
        return image
    }

    var body: some View {
        Group {
            if let image = Self.icon(for: path) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 22, height: 22)
            } else {
                Text(initial)
                    .font(Theme.scaled(11, weight: .semibold))
                    .foregroundColor(Palette.mint)
            }
        }
        .frame(width: 26, height: 26)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Palette.navyDeep.opacity(0.8))
        )
    }

    private var initial: String {
        String(name.prefix(1)).uppercased()
    }
}
/// Baris yang membungkus sendiri saat penuh — dipakai untuk daftar chip
/// domain, yang panjangnya tidak bisa diketahui di depan.
///
/// `LazyVGrid` (yang dipakai `SourcesView` untuk pilihan feed) tidak bisa
/// dipakai di sini: grid memberi setiap sel lebar yang SAMA, sedangkan chip
/// domain lebarnya mengikuti nama hostnya. `GridItem(.adaptive)` membuat chip
/// pendek ikut selebar chip panjang, jadi daftarnya terlihat seperti tabel, bukan daftar.
///
/// Pakai `Layout` langsung (macOS 13+, sama dengan deployment target project
/// ini) alih-alih `HStack` di dalam `GeometryReader`: yang kedua harus
/// menghitung tinggi sendiri setelah anak-anaknya diletakkan, dan hampir
/// selalu berakhir salah saat zoom UI atau teks membesar.
struct WrapLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var widest: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            // Baris baru hanya kalau ada isi baris ini. Tanpa `x > 0`, subview
            // pertama yang lebih lebar dari Container membuat baris kosong
            // dijumlahkan dan tinggi keluar bertambah sia-sia.
            if x > 0, x + size.width > maxWidth {
                widest = max(widest, x - spacing)
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        widest = max(widest, x > 0 ? x - spacing : 0)
        return CGSize(width: min(widest, maxWidth), height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout Void) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            s.place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                    proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
