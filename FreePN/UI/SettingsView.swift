import SwiftUI
import ServiceManagement

/// Pengaturan: kartu-kartu dalam dua kolom, masing-masing dengan kendali di
/// kanan baris.
struct SettingsView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader("nav_settings", subtitle: "settings_subtitle") {
                    Button { state.checkHealth() } label: {
                        Label("health_check", systemImage: "checkmark.shield")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }

                VStack(spacing: 14) {
                    grid {
                        appearanceCard
                        subscriptionCard
                        connectionCard
                        performanceCard
                        macCard
                        healthCard
                        securityCard
                        aboutCard
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Dua kolom yang menumpuk jadi satu saat jendela sempit.
    ///
    /// `Grid` dipakai, bukan `LazyVGrid`, karena jumlahnya kecil dan tetap
    /// perlu tahu tinggi baris yang lebih tinggi untuk menyamakan tinggi
    /// pasangan kartu.
    @ViewBuilder
    private func grid<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 14),
                            GridItem(.flexible(), spacing: 14)],
                  alignment: .leading, spacing: 14) {
            content()
        }
    }

    // MARK: - Tampilan

    private var appearanceCard: some View {
        SettingsCard("display", "sect_appearance") {
            SettingRow("ui_scale", detail: "ui_scale_note") {
                DropdownMenu(
                    options: Array(AppUIScale.range).filter { $0 % AppUIScale.step == 0 },
                    label: { Text(verbatim: "\($0)%") },
                    selection: Binding(
                        get: { state.settings.uiScalePercent },
                        set: { v in
                            state.settings.uiScalePercent = v
                            state.applyUIScale(); state.persist(onlySettings: true)
                        }))
            }
            Hairline()
            SettingRow("language", detail: "lang_restart_note") {
                DropdownMenu(
                    options: AppLanguage.allCases,
                    label: { lang in
                        switch lang {
                        case .system: return Text("lang_system")
                        case .id: return Text("lang_id")
                        case .en: return Text("lang_en")
                        }
                    },
                    selection: Binding(
                        get: { state.settings.language },
                        set: { v in
                            state.settings.language = v
                            state.applyLanguage(); state.persist(onlySettings: true)
                        }))
            }
        }
    }

    // MARK: - Langganan

    private var subscriptionCard: some View {
        SettingsCard("arrow.triangle.2.circlepath", "sect_subscription") {
            SettingRow("auto_refresh", detail: "auto_refresh_note") {
                DropdownMenu(
                    options: [0, 1, 3, 6, 12],
                    label: { hours in
                        hours == 0 ? Text("off") : Text(verbatim: "\(hours)h")
                    },
                    selection: Binding(
                        get: { state.settings.autoRefreshHours },
                        set: { v in state.settings.autoRefreshHours = v; state.persist(onlySettings: true) }))
            }
            Hairline()
            SettingRow("auto_sort", detail: "auto_sort_note") {
                MintToggle(isOn: Binding(
                    get: { state.settings.autoSortAfterPing },
                    set: { v in state.settings.autoSortAfterPing = v; state.persist(onlySettings: true) }))
            }
            Hairline()
            SettingRow("show_node_port", detail: "show_node_port_note") {
                MintToggle(isOn: Binding(
                    get: { state.settings.showNodePort },
                    set: { v in state.settings.showNodePort = v; state.persist(onlySettings: true) }))
            }
            Hairline()
            SettingRow("hide_dead", detail: "hide_dead_note") {
                MintToggle(isOn: Binding(
                    get: { state.settings.hideDeadNodes },
                    set: { v in state.settings.hideDeadNodes = v; state.persist(onlySettings: true) }))
            }
            Hairline()
            // Berdampingan dengan `auto_sort` di atas, bukan di Performance:
            // ini mengatur APA yang diukur ping, bukan berapa banyak workers.
            SettingRow("fast_ping", detail: "fast_ping_note") {
                MintToggle(isOn: Binding(
                    get: { state.settings.fastPing },
                    set: { v in state.settings.fastPing = v; state.persist(onlySettings: true) }))
            }
            pingTargetRows
        }
    }

    private var customTargetValid: Bool {
        PingTarget.isUsableCustomURL(state.settings.pingTargetCustomURL)
    }

    // MARK: - Target uji internet (D93)

    /// Baris pengaturan ke mana uji internet ditembak.
    ///
    /// Dipisah dari `subscriptionCard` karena isinya berupa kondisi, dan
    /// ViewBuilder yang isinya kondisi di dalam generic `SettingsCard<Content>`
    /// membuat inferensi tipe meledak jadi error yang sama sekali tidak
    /// menunjuk ke penyebabnya.
    private var pingTargetRows: some View {
        VStack(spacing: 0) {
            Hairline()
            // Poinnya: user yang gstatic-nya diblokir di jaringan tidak lagi
            // kehilangan daftar servernya, dan host yang sedang dipakai tampil di
            // log ping — jadi "semua mati" bisa dibuktikan atau disangkal.
            SettingRow("ping_target", detail: "ping_target_note") {
                Picker("ping_target", selection: Binding(
                    get: { state.settings.pingTarget },
                    set: { v in
                        state.settings.pingTarget = v
                        state.persist(onlySettings: true)
                    }
                )) {
                    ForEach(PingTarget.allCases) { t in
                        Text(verbatim: t.label).tag(t)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(Palette.mint)
            }
            if state.settings.pingTarget == .custom {
                Hairline()
                SettingRow("ping_target_custom", detail: "ping_target_custom_note") {
                    TextField("", text: Binding(
                        get: { state.settings.pingTargetCustomURL },
                        set: { v in state.settings.pingTargetCustomURL = v }
                    ), prompt: Text("http://…").foregroundColor(Palette.textTertiary))
                    .textFieldStyle(.plain)
                    .foregroundColor(Palette.textPrimary)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Palette.well)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(
                                customTargetValid ? Palette.border : Palette.danger,
                                lineWidth: 1)
                    )
                    .onSubmit { state.persist(onlySettings: true) }
                }
            }
        }
    }

    // MARK: - Koneksi

    private var connectionCard: some View {
        SettingsCard("bolt.horizontal", "sect_connection") {
            SettingRow("auto_reconnect", detail: "auto_reconnect_note") {
                MintToggle(isOn: Binding(
                    get: { state.settings.autoReconnect },
                    set: { v in
                        state.settings.autoReconnect = v
                        state.connection.autoReconnect = v
                        state.persist(onlySettings: true)
                    }))
            }
            Hairline()
            SettingRow("show_ip", detail: "show_ip_note") {
                MintToggle(isOn: Binding(
                    get: { state.settings.showPublicIP },
                    set: { v in state.settings.showPublicIP = v; state.persist(onlySettings: true) }))
            }
            Hairline()
            SettingRow("launch_login", detail: "launch_login_note") {
                MintToggle(isOn: Binding(
                    get: { state.settings.launchAtLogin },
                    set: { v in
                        state.settings.launchAtLogin = v
                        do {
                            if v { try SMAppService.mainApp.register() }
                            else { try SMAppService.mainApp.unregister() }
                        } catch { }
                        state.persist(onlySettings: true)
                    }))
            }
        }
    }

    // MARK: - Performa

    private var performanceCard: some View {
        SettingsCard("bolt.fill", "sect_performance") {
            SettingRow("adaptive_concurrency", detail: "adaptive_concurrency_note") {
                MintToggle(isOn: Binding(
                    get: { state.settings.adaptiveConcurrency },
                    set: { v in state.settings.adaptiveConcurrency = v; state.applyCPUPolicy(); state.persist(onlySettings: true) }))
            }
            Hairline()
            SettingRow("cpu_share", detail: "cpu_share_note") {
                HStack(spacing: 10) {
                    // Pakai init `onEditingChanged:` bawaan (bukan modifier
                    // terpisah) supaya penulisan disk hanya terjadi di AKHIR
                    // drag. `Binding.set` dipanggil tiap step slider — dozens
                    // kali per detik — dan `persist()` menulis ulang seluruh
                    // `nodes.json` (16.000 node). Writer-nya cukup satu (D61).
                    Slider(
                        value: Binding(
                            get: { Double(state.settings.cpuSharePercent) },
                            set: { v in
                                state.settings.cpuSharePercent = AppSettings.nearestCPUShare(Int(v.rounded()))
                                state.applyCPUPolicy()
                            }),
                        in: 25...100, step: 25,
                        onEditingChanged: { editing in
                            if !editing { state.persist(onlySettings: true) }
                        }
                    )
                    .tint(Palette.mint)
                    .disabled(!state.settings.adaptiveConcurrency)
                    Text("\(state.settings.cpuSharePercent)%")
                        .font(Theme.font(.caption, design: .monospaced))
                        .monospacedDigit()
                        .foregroundColor(Palette.textSecondary)
                        .frame(width: 42, alignment: .trailing)
                }
            }
            Hairline()
            systemStatusRow
        }
    }

    /// Ringkasan jatah kerja saat ini, supaya user bisa lihat efek pengaturannya.
    ///
    /// D50: yang ditampilkan adalah jatah yang benar-benar dipakai — jumlah slot
    /// uji internet (`cpu.computeLimit`). Tidak ada lagi jatah socket TCP,
    /// karena sweep TCP-nya sendiri sudah dihapus.
/// Baris ini observe `CPUGovernorMonitor` LANGSUNG lewat `@ObservedObject`
    /// (lihat `CPUSummary`), bukan lewat `AppState`.
    ///
    /// Kenapa: `cpu` sengaja tidak masuk `relayChildChanges()` — kalau ikut,
    /// tiap sampel beban CPU (tiap 1 detik saat probe jalan) akan menggambar
    /// ulang seluruh app. Tapi kalau TIDAK ikut relayed DAN tidak diamati
    /// langsung, teksnya jadi basi: user yang menggeser slider CPU tidak
    /// pernah melihat angkanya berubah (D61).
    private var systemStatusRow: some View {
        CPUSummary(cpu: state.cpu,
                   adaptive: state.settings.adaptiveConcurrency,
                   share: state.settings.cpuSharePercent)
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

    /// Ringkasan jatah kerja, terisolasi ke baris ini saja. Diekstrak jadi view
    /// terpisah supaya invalidasi tiap detik hanya menyentuh baris kecil ini,
    /// bukan seluruh kartu Performance.
    private struct CPUSummary: View {
        @ObservedObject var cpu: CPUGovernorMonitor
        let adaptive: Bool
        let share: Int

        var body: some View {
            HStack(spacing: 8) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 12 * Theme.uiScale))
                    .foregroundColor(Palette.mint)
                Text("mac_status_system")
                    .font(Theme.font(.callout))
                    .foregroundColor(Palette.textSecondary)
                Spacer(minLength: 8)
                Text(status)
                    .font(Theme.font(.caption, design: .monospaced))
                    .monospacedDigit()
                    .foregroundColor(Palette.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }

        private var status: String {
            let cores = CPUMeter.performanceCores
            let effective = adaptive ? share : 0
            let mode = adaptive ? L10n.string("cpu_adaptive") : L10n.string("cpu_fixed")
            let load = Int((cpu.load * 100).rounded())
            return "\(cores)\(L10n.string("cpu_cores")) · \(effective)% · "
                + "\(cpu.computeLimit)\(L10n.string("cpu_slots")) · "
                + "\(load)%\(L10n.string("cpu_load")) · \(mode)"
        }
    }

    // MARK: - MAC Address

    private var macCard: some View {
        SettingsCard("cpu", "sect_mac") {
            SettingRow("mac_random_connect", detail: "mac_random_connect_note") {
                MintToggle(isOn: Binding(
                    get: { state.settings.randomMACOnConnect },
                    set: { v in state.settings.randomMACOnConnect = v; state.persist(onlySettings: true) }))
            }
            Hairline()
            SettingRow("mac_restore_disconnect", detail: "mac_restore_disconnect_note") {
                MintToggle(isOn: Binding(
                    get: { state.settings.restoreMACOnDisconnect },
                    set: { v in state.settings.restoreMACOnDisconnect = v; state.persist(onlySettings: true) }))
            }
        }
    }

    // MARK: - Izin & kesehatan

    private var healthCard: some View {
        SettingsCard("checkmark.shield", "sect_health") {
            if state.health.isChecking {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.6).controlSize(.small)
                    Text("health_check")
                        .font(Theme.font(.callout))
                        .foregroundColor(Palette.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if state.health.items.isEmpty {
                Button("health_check") { state.checkHealth() }
                    .buttonStyle(SecondaryButtonStyle())
            } else {
                ForEach(state.health.items) { it in
                    healthRow(it)
                    if it.id != state.health.items.last?.id { Hairline() }
                }
                Button("health_recheck") { state.checkHealth() }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    private func healthRow(_ it: HealthItem) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Circle().fill(healthColor(it.level)).frame(width: 8, height: 8)
                Text(it.title)
                    .font(Theme.font(.callout))
                    .foregroundColor(Palette.textPrimary)
                Spacer(minLength: 0)
                if it.level != .ok {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10 * Theme.uiScale))
                        .foregroundColor(healthColor(it.level))
                }
            }
            Text(it.detail)
                .font(Theme.font(.caption))
                .foregroundColor(Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            if it.level != .ok {
                Text(it.fix)
                    .font(Theme.font(.caption))
                    .foregroundColor(Palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                if it.id == "split" && it.level == .fail {
                    Button("health_fix_split") {
                        state.split = SplitTunnelConfig(mode: .exclusive)
                        state.persist(onlySplit: true)
                        state.checkHealth()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                if it.id == "helper" && it.level != .ok {
                    HelperInstallButton()
                }
            }
        }
        .padding(.vertical, 3)
    }

    private func healthColor(_ level: HealthItem.Level) -> Color {
        switch level {
        case .ok: return Palette.success
        case .warn: return Palette.warning
        case .fail: return Palette.danger
        case .info: return Palette.info
        }
    }

    // MARK: - Keamanan & data

    private var securityCard: some View {
        SettingsCard("lock.shield", "sect_security") {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(Palette.warning)
                    Text("warn_free_nodes_short")
                        .font(Theme.font(.callout))
                        .foregroundColor(Palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("warn_legal")
                    .font(Theme.font(.caption))
                    .foregroundColor(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 3)
            Hairline()
            HStack {
                Button("action_reset", role: .destructive) { resetData() }
                    .buttonStyle(GhostButtonStyle())
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Tentang

    private var aboutCard: some View {
        SettingsCard("info.circle", "sect_about") {
            SettingRow("app_version", detail: "app_build_note") {
                Text("FreePN 1.0")
                    .font(Theme.font(.callout, design: .monospaced))
                    .foregroundColor(Palette.textSecondary)
            }
            Hairline()

            // D84 — lisensi app sendiri, bukan hanya dependensi.
            //
            // Sebelumnya kartu Tentang tidak pernah menyebut lisensi FreePN
            // sama sekali; yang ada hanya "Third-party licenses". Itu
            // membingungkan secara hukum: MIT mewajibkan PERINGATAN HAK CIPTA
            // ikut disertakan di setiap salinan, dan pembacaan "lisensi
            // app = yang ada di sheet itu" mudah terjadi.
            //
            // Karena itu lisensi app sendiri diberi baris sendiri, di ATAS
            // lisensi pihak ketiga, dan membuka teks MIT lengkap.
            Button { showAppLicense = true } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("app_license")
                            .font(Theme.font(.callout))
                            .foregroundColor(Palette.textPrimary)
                        Text("app_license_value")
                            .font(Theme.font(.caption))
                            .foregroundColor(Palette.textTertiary)
                    }
                    Spacer()
                    Text("MIT")
                        .font(Theme.font(.caption2, design: .monospaced).weight(.bold))
                        .foregroundColor(Palette.mint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Palette.mint.opacity(0.14)))
                        .overlay(Capsule().strokeBorder(Palette.mint.opacity(0.35), lineWidth: 1))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11 * Theme.uiScale, weight: .semibold))
                        .foregroundColor(Palette.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Hairline()

            githubRow
            Hairline()

            // Atribusi GitHub adalah bagian dari BERKAS LISENSI, jadi
            // ditambahkan kalimat eksplisit di bawah tautannya — bukan
            // sekadar URL di layar. Kalimat inilah yang membuat kewajiban
            // atribusi terbaca, bukan sekadar terpenuhi.
            Text("about_attribution_required")
                .font(Theme.font(.caption))
                .foregroundColor(Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Hairline()

            Button { showLicenses = true } label: {
                HStack {
                    Text("licenses")
                        .font(Theme.font(.callout))
                        .foregroundColor(Palette.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11 * Theme.uiScale, weight: .semibold))
                        .foregroundColor(Palette.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $showLicenses) { LicensesView() }
        .sheet(isPresented: $showAppLicense) { AppLicenseView() }
    }

    /// Tautan ke repositori, dibuat oleh orang yang sama dengan app ini.
    ///
    /// `Link` dipakai, bukan `Button` + `NSWorkspace`, supaya Safari jadi
    /// penangan default (menghormati user's browser pilihan) dan supaya
    /// Cmd-klik / klik kanan "Buka di Tab Baru" tetap bekerja seperti
    /// tautan web biasa.
    private var githubRow: some View {
        Link(destination: AppConstants.projectURL) {
            HStack(spacing: 9) {
                GitHubMark()
                    .fill(Palette.textPrimary)
                    .frame(width: 16, height: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text("about_github")
                        .font(Theme.font(.callout))
                    Text("about_github_note")
                        .font(Theme.font(.caption))
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 11 * Theme.uiScale))
            }
            .foregroundColor(Palette.textPrimary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Cincin fokus abu-abu macOS (D60b) — lihat catatan di
        // `licenseEntryLink`. Di screen ini tombol pertama sudah non-focusable,
        // jadi baris tautan ini boleh jadi fokus pertama tanpa memunculkan
        // cincin yang sama.
        .focusable(false)
    }

    @State private var showLicenses = false
    @State private var showAppLicense = false

    private func resetData() {
        // Reset menyentuh SEGALA store, jadi `persist()` penuh yang tepat di
        // sini — bukan varian per-store.
        state.nodes = []; state.ping = [:]; state.favorites = []
        state.persist()
    }
}

/// Kartu pengaturan: judul berikon + isi. Semua kartu pengaturan memakai
/// komponen ini supaya jarak dan garis pemisah identik di seluruh app.
struct SettingsCard<Content: View>: View {
    private let symbol: String
    private let title: LocalizedStringKey
    private let content: Content

    init(_ symbol: String, _ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.symbol = symbol
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(symbol, title)
            content
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .freepnCard()
    }
}

/// Tombol pasang helper satu-klik (dialog password macOS), dipakai ulang di
/// Settings dan Connect. Setelah sukses langsung cek ulang kesehatan.
struct HelperInstallButton: View {
    @EnvironmentObject var state: AppState
    @State private var installing = false
    @State private var message = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if installing {
                HStack(spacing: 7) {
                    ProgressView().scaleEffect(0.6).controlSize(.small)
                    Text("installing_helper")
                        .font(Theme.font(.caption))
                        .foregroundColor(Palette.textTertiary)
                }
            } else {
                Button("action_install_helper") {
                    installing = true
                    message = ""
                    Task {
                        do {
                            _ = try await HelperInstaller.install()
                            message = NSLocalizedString("install_helper_ok", comment: "")
                            state.checkHealth()
                        } catch {
                            message = (error as NSError).localizedDescription
                        }
                        installing = false
                    }
                }
                .buttonStyle(SecondaryButtonStyle(active: true))
            }
            if !message.isEmpty {
                Text(message)
                    .font(Theme.font(.caption))
                    .foregroundColor(Palette.textSecondary)
                    .textSelection(.enabled)
            }
        }
    }
}

/// Teks lisensi FreePN itu sendiri (D84).
///
/// Isinya teks MIT LENGKAP, bukan ringkasan. Persyaratan utama MIT adalah
/// "the above copyright notice and this permission notice shall be included
/// in all copies" — kalau app menampilkan versi ringkas, notice yang tampil
/// BUKAN notice yang diwajibkan, dan menyalin dari layar ini jadi tidak
/// memenuhi syarat.
///
/// `.textSelection(.enabled)` supaya notice bisa disalin utuh.
struct AppLicenseView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("app_license_title")
                    .font(Theme.screenTitle)
                    .foregroundColor(Palette.textPrimary)
                Spacer()
                Button("action_close") { dismiss() }
                    .buttonStyle(SecondaryButtonStyle())
                    // Sama seperti di `LicensesView`: cincin fokus macOS
                    // menempel di item pertama yang bisa difokus, dan di sheet
                    // ini item itu selalu "Close".
                    .focusable(false)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    licenseEntry("FreePN", "MIT", AppConstants.projectURLString)
                        .padding(.bottom, 2)

                    Rectangle()
                        .fill(Palette.border.opacity(0.7))
                        .frame(height: 1)

                    // Atribusi: kalimat yang WAJIB ikut travelling bersama
                    // app ini kalau diredistribusi. Ditampilkan sebagai
                    // blok kode supaya jelas itu kalimat siap tempel,
                    // bukan paragraf istilah.
                    Text("app_license_attribution_label")
                        .font(Theme.overline)
                        .foregroundColor(Palette.textTertiary)
                        .textCase(.uppercase)

                    Text("app_license_attribution_text")
                        .font(Theme.font(.callout, design: .monospaced))
                        .foregroundColor(Palette.mint)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Palette.navyDeep.opacity(0.8)))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Palette.mint.opacity(0.25), lineWidth: 1))

                    Text("app_license_attribution_note")
                        .font(Theme.font(.caption))
                        .foregroundColor(Palette.textTertiary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)

                    Rectangle()
                        .fill(Palette.border.opacity(0.7))
                        .frame(height: 1)

                    // Teks MIT LENGKAP.
                    Text(mitLicenseText)
                        .font(Theme.font(.caption, design: .monospaced))
                        .foregroundColor(Palette.textSecondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(24)
        .frame(minWidth: 560, minHeight: 420)
        .freepnBackdrop()
    }

    /// Teks MIT lengkap, persis seperti di berkas `LICENSE`.
    ///
    /// Disalin sebagai literal (bukan dibaca dari bundle) supaya sheet ini
    /// tidak bisa gagal diam-diam kalau berkas tidak ikut ter-bundle. Tes
    /// membandingkan isi ini dengan berkas `LICENSE` supaya keduanya tidak
    /// bisa melenceng.
    private var mitLicenseText: String {
        """
        MIT License

        Copyright (c) 2026 YandiDesign
        https://github.com/YandiDesign

        Permission is hereby granted, free of charge, to any person obtaining a copy
        of this software and associated documentation files (the "Software"), to deal
        in the Software without restriction, including without limitation the rights
        to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
        copies of the Software, and to permit persons to whom the Software is
        furnished to do so, subject to the following conditions:

        The above copyright notice and this permission notice shall be included in all
        copies or substantial portions of the Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
        IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
        FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
        AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
        LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
        OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
        SOFTWARE.
        """
    }
}

struct LicensesView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("licenses")
                    .font(Theme.screenTitle)
                    .foregroundColor(Palette.textPrimary)
                Spacer()
                Button("action_close") { dismiss() }
                    .buttonStyle(SecondaryButtonStyle())
                    // Cincin fokus abu-abu macOS muncul otomatis di item
                    // PERTAMA yang bisa difokus, dan di sheet ini item itu
                    // selalu "Close" — jadi setiap kali dialog dibuka tombolnya
                    // terlihat seperti sedang aktif, padahal tidak. Warna abu
                    // itu bukan dari `SecondaryButtonStyle` (yang border-nya
                    // mint), murni cincin fokus sistem.
                    //
                    // `.focusEffectDisabled()` hanya ada sejak macOS 14,
                    // sedangkan project ini memakai SDK macOS 13, jadi satu-
                    //-satunya cara yang tersedia adalah `.focusable(false)`.
                    // Membuka sheet tetap effortless lewat tombol ✕ di title
                    // bar dan tombol Escape.
                    .focusable(false)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // D84 — lisensi FreePN sendiri, di paling atas.
                    //
                    // Sheet ini sebelumnya HANYA berisi dependensi, jadi
                    // pembacaan paling wajar dari judulnya ("Third-party
                    // licenses") adalah "lisensi app ini ada di sini".
                    // Padahal lisensi app adalah MIT, terpisah dari
                    // ketiganya. Ditulis eksplisit supaya tidak disalahpahami.
                    Text("licenses_self_note")
                        .font(Theme.font(.caption))
                        .foregroundColor(Palette.textTertiary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    licenseEntry("FreePN", "MIT", AppConstants.projectURLString)

                    Rectangle()
                        .fill(Palette.border.opacity(0.7))
                        .frame(height: 1)

                    // Hanya dependensi yang benar-benar dipakai di build.
                    // Yams pernah dicatat di sini padahal tidak pernah
                    // terpasang sebagai SPM.
                    licenseEntry("sing-box", "GPL-3.0",
                                 "https://github.com/SagerNet/sing-box")
                    licenseEntry("DotMap", "MIT",
                                 "https://github.com/spilneo/DotMap")

                    // Atribusi MaxMind WAJIB oleh GeoLite2 EULA §3, dengan
                    // kalimat yang mereka tulis sebagai contoh. Ditulis
                    // persis, bukan paraphrase — EULA melarang menghilangkan
                    // pemberitahuan hak cipta (§3).
                    Text("licenses_geolite2_attribution")
                        .font(Theme.font(.callout))
                        .foregroundColor(Palette.textSecondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    licenseEntryLink("licenses_geolite2_eula",
                                     "https://www.maxmind.com/en/geolite/eula")

                    // GeoNames CC BY 4.0 — wajib karena MaxMind mewajibkan
                    // atribusi untuk data geografi di dalamnya.
                    Text("licenses_geonames_attribution")
                        .font(Theme.font(.caption))
                        .foregroundColor(Palette.textTertiary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    licenseEntryLink("licenses_geonames_license",
                                     "https://creativecommons.org/licenses/by/4.0/")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(24)
        .frame(minWidth: 520, minHeight: 320)
        .freepnBackdrop()
    }

    /// Label berbahasa lokal + URL yang bisa diklik (untuk ketentuan lisensi
    /// yang mewajibkan tautan, seperti GeoNames CC BY).
    private func licenseEntryLink(_ titleKey: LocalizedStringKey, _ url: String) -> some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: 6) {
                Text(titleKey)
                    .font(Theme.font(.caption))
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 9 * Theme.uiScale))
            }
            .foregroundColor(Palette.mint)
        }
        // Cincin fokus abu-abu macOS menempel di item PERTAMA yang bisa
        // difokus. Setelah tombol Close dimatikan fokusnya (SettingsView.swift
        // LicensesView), cincin itu pindah ke tautan lisensi pertama — jadi
        // memunculkan masalah yang sama di tempat lain, bukan menyelesaikannya.
        // Semua tautan lisensi hereby dimatikan agar sheet ini bersih dari
        // outset, bukan hanya setelah satu per satu ditemukan.
        //
        // Persyaratan lisensi (GeoNames CC BY 4.0) tetap terpenuhi: tautannya
        // ada dan bisa diklik, yang hilang hanya fokus papan ketik. Isi teks
        // di sheet ini bisa disalin lewat `.textSelection(.enabled)`.
        .focusable(false)
    }

}
/// Satu baris "k-dependensi + lisensinya + URL-nya".
///
/// D84: diangkat ke scope file (bukan `private` di dalam `LicensesView`)
/// karena `AppLicenseView` membutuhkannya juga. Menyalinnya berarti ada
/// dua definisi yang bisa melenceng - dan baris lisensi justru yang paling
/// harus akurat, jadi paling rawan dobel.
func licenseEntry(_ name: String, _ license: String, _ url: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 8) {
            Text(name)
                .font(Theme.font(.callout))
                .foregroundColor(Palette.textPrimary)
            Text(license)
                .font(Theme.overline)
                .foregroundColor(Palette.mint)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Capsule().fill(Palette.mint.opacity(0.14)))
            Spacer(minLength: 0)
        }
        Text(url)
            .font(Theme.font(.caption, design: .monospaced))
            .foregroundColor(Palette.textTertiary)
            .textSelection(.enabled)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
}
