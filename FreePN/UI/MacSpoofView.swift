import SwiftUI

public struct MACInterface: Identifiable {
    public var id: String { name }
    public var name: String // en0
    public var device: String // Wi-Fi
    public var currentMAC: String
    public var hardwareMAC: String
}

/// MAC Address: kartu utama dengan alamat yang sedang dipakai, kartu info,
/// input MAC kustom, dan riwayat perubahan.
struct MacSpoofView: View {
    @EnvironmentObject var state: AppState
    @State private var ifaces: [MACInterface] = []
    @State private var customMAC = ""
    @State private var message = ""
    @State private var selected: String? = nil
    @State private var showCustom = false
    @State private var historyQuery = ""
    @State private var historyFilter: MACHistoryEntry.Kind? = nil
    @State private var historyCleared = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader("nav_mac", subtitle: "mac_subtitle") {
                    Button { loadInterfaces() } label: {
                        Label("action_refresh", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }

                topRow

                VStack(alignment: .leading, spacing: 12) {
                    CardHeader("clock.arrow.circlepath", "mac_history_title")
                    historyTable
                }
                .padding(16)
                .freepnCard()
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { loadInterfaces() }
    }

    // MARK: - Kartu utama + kartu info

    private var topRow: some View {
        HStack(alignment: .top, spacing: 14) {
            currentCard.frame(width: 330)
            VStack(spacing: 14) {
                aboutCard
                customCard
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Kartu utama: cincin ikon + alamat MAC yang sedang dipakai.
    private var currentCard: some View {
        VStack(spacing: 12) {
            HaloIcon("cpu")
                .padding(.top, 4)

            Text("mac_current_title")
                .font(Theme.font(.callout))
                .foregroundColor(Palette.textSecondary)

            Text(currentMAC)
                .font(Theme.scaled(24, weight: .semibold))
                .monospaced()
                .foregroundColor(Palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            HStack(spacing: 6) {
                Circle().fill(spoofActive ? Palette.success : Palette.textTertiary)
                    .frame(width: 7, height: 7)
                Text(spoofActive ? "mac_status_spoofed" : "mac_status_default")
                    .font(Theme.font(.caption))
                    .foregroundColor(spoofActive ? Palette.success : Palette.textTertiary)
            }

            Hairline()

            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "cpu")
                        .font(.system(size: 12 * Theme.uiScale))
                        .foregroundColor(Palette.mint)
                    Text("mac_hardware")
                        .font(Theme.font(.callout))
                        .foregroundColor(Palette.textSecondary)
                }
                Spacer(minLength: 10)
                Text(hardwareMAC)
                    .font(Theme.font(.callout, design: .monospaced))
                    .foregroundColor(Palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            interfaceList
        }
        .padding(18)
        .freepnCard(padding: 0)
    }

    /// Daftar interface: user perlu tahu Wi-Fi ATAU Ethernet mana yang
    /// diubah, jadi ini bukan detail teknis yang bisa disembunyikan.
    @ViewBuilder
    private var interfaceList: some View {
        if ifaces.isEmpty {
            HStack(spacing: 8) {
                ProgressView().scaleEffect(0.6).controlSize(.small)
                Text("mac_loading_interfaces")
                    .font(Theme.font(.caption))
                    .foregroundColor(Palette.textTertiary)
            }
        } else {
            VStack(spacing: 6) {
                ForEach(ifaces) { it in
                    HStack(spacing: 9) {
                        Image(systemName: "network")
                            .font(.system(size: 11 * Theme.uiScale))
                            .foregroundColor(Palette.textTertiary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(it.device)
                                .font(Theme.font(.caption))
                                .foregroundColor(Palette.textSecondary)
                                .lineLimit(1)
                            Text(it.currentMAC)
                                .font(Theme.font(.caption2, design: .monospaced))
                                .foregroundColor(Palette.textPrimary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer(minLength: 6)
                        Button { randomize(it) } label: {
                            Image(systemName: "dice")
                                .font(.system(size: 11 * Theme.uiScale, weight: .medium))
                                .foregroundColor(Palette.mint)
                                .frame(width: 24, height: 24)
                                .background(Circle().fill(Palette.mint.opacity(0.12)))
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help(Text("mac_random"))

                        Button { restore(it) } label: {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 10 * Theme.uiScale, weight: .semibold))
                                .foregroundColor(Palette.textSecondary)
                                .frame(width: 24, height: 24)
                                .background(Circle().fill(Palette.navyDeep.opacity(0.8)))
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help(Text("mac_restore"))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Palette.navyDeep.opacity(0.55))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(it.name == selected ? Palette.mint.opacity(0.45) : Color.clear,
                                          lineWidth: 1)
                    )
                    .onTapGesture { selected = it.name }
                }
            }
        }
    }

    private var aboutCard: some View {
        HStack(alignment: .top, spacing: 13) {
            IconTile("info", size: 38, tint: Palette.info)
            VStack(alignment: .leading, spacing: 6) {
                Text("mac_about_title")
                    .font(Theme.cardTitle)
                    .foregroundColor(Palette.textPrimary)
                Text("mac_about_detail")
                    .font(Theme.font(.callout))
                    .foregroundColor(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .freepnCard()
    }

    private var customCard: some View {
        VStack(spacing: 12) {
            Button {
                showCustom.toggle()
            } label: {
                HStack(spacing: 13) {
                    IconTile("cpu", size: 38, tint: Palette.mint)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("mac_custom_title")
                            .font(Theme.font(.callout))
                            .foregroundColor(Palette.textPrimary)
                        Text("mac_custom_detail")
                            .font(Theme.font(.caption))
                            .foregroundColor(Palette.textTertiary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: showCustom ? "chevron.up" : "chevron.right")
                        .font(.system(size: 12 * Theme.uiScale, weight: .semibold))
                        .foregroundColor(Palette.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showCustom {
                Hairline()
                customForm
            }
        }
        .padding(16)
        .freepnCard()
    }

    @ViewBuilder
    private var customForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text("mac_custom_label")
                    .font(Theme.font(.caption))
                    .foregroundColor(Palette.textSecondary)
                TextField("", text: $customMAC,
                          prompt: Text("xx:xx:xx:xx:xx:xx").foregroundColor(Palette.textTertiary))
                    .textFieldStyle(.plain)
                    .font(Theme.font(.callout, design: .monospaced))
                    .foregroundColor(Palette.textPrimary)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Palette.well)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Validators.isValidMACFormat(customMAC)
                                          ? Palette.mint.opacity(0.55) : Palette.border,
                                          lineWidth: 1)
                    )
            }

            if !customMAC.isEmpty && !Validators.isValidMACFormat(customMAC) {
                Text("mac_format_invalid")
                    .font(Theme.font(.caption))
                    .foregroundColor(Palette.danger)
            }

            if let interface = ifaces.first {
                Picker("mac_target_interface", selection: Binding(
                    get: { selected ?? interface.name },
                    set: { selected = $0 }
                )) {
                    ForEach(ifaces) { it in
                        Text("\(it.device) (\(it.name))").tag(it.name as String?)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(Palette.mint)
            } else {
                Text("mac_no_interface")
                    .font(Theme.font(.caption))
                    .foregroundColor(Palette.warning)
            }

            if !message.isEmpty {
                Text(message)
                    .font(Theme.font(.caption))
                    .foregroundColor(Palette.danger)
                    .textSelection(.enabled)
            }

            HStack {
                Spacer()
                Button("action_cancel") {
                    customMAC = ""
                    message = ""
                }
                .buttonStyle(GhostButtonStyle())

                Button("mac_set_custom") { setCustom() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!Validators.isValidMACFormat(customMAC)
                              || (selected ?? ifaces.first?.name) == nil)
            }
        }
    }

    // MARK: - Riwayat

    private var historyTable: some View {
        VStack(spacing: 12) {
            historyToolbar
            historyHeaderRow
            Hairline().padding(.horizontal, 14)
            historyBody
        }
        .alert(L10n.string("mac_clear_history_title"), isPresented: $historyCleared) {
            Button(L10n.string("action_delete"), role: .destructive) {
                state.macHistory = []
                state.persist(onlyMACHistory: true)
            }
            Button(L10n.string("action_cancel"), role: .cancel) { historyCleared = false }
        } message: {
            Text(L10n.formatted("mac_clear_history_message", state.macHistory.count))
        }
    }

    private var historyToolbar: some View {
        HStack(spacing: 12) {
            SearchField("mac_search_placeholder", text: $historyQuery)
                .frame(maxWidth: 260)
            FilterChip("mac_history_all", selected: historyFilter == nil) {
                historyFilter = nil
            }
            ForEach(MACHistoryEntry.Kind.allCasesForFilter, id: \.self) { k in
                FilterChip(title: kindTitle(k), selected: historyFilter == k) {
                    historyFilter = (historyFilter == k) ? nil : k
                }
            }
            Spacer(minLength: 0)
            Button { historyCleared = true } label: {
                Label("mac_clear_history", systemImage: "trash")
            }
            .buttonStyle(GhostButtonStyle())
            .disabled(filteredHistory.isEmpty)
        }
    }

    private var historyHeaderRow: some View {
        HStack(spacing: 10) {
            ColumnLabel("col_type").frame(width: 160, alignment: .leading)
            ColumnLabel("col_mac_address").frame(width: 180, alignment: .leading)
            ColumnLabel("col_interface").frame(width: 110, alignment: .leading)
            ColumnLabel("col_time").frame(minWidth: 140, alignment: .leading)
            ColumnLabel("").frame(width: 44)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var historyBody: some View {
        if filteredHistory.isEmpty {
            historyEmpty
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(filteredHistory) { entry in
                        TableRowView { historyRow(entry) }
                            .contextMenu { historyMenu(for: entry) }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .frame(maxHeight: 240)
        }
    }

    private var historyEmpty: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 20))
                .foregroundColor(Palette.textTertiary)
            Text(state.macHistory.isEmpty ? "mac_history_empty" : "mac_history_no_match")
                .font(Theme.font(.callout))
                .foregroundColor(Palette.textTertiary)
            if !state.macHistory.isEmpty {
                Button("mac_clear_history") { historyCleared = true }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }

    @ViewBuilder
    private func historyMenu(for entry: MACHistoryEntry) -> some View {
        Button("mac_copy_address") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(entry.mac, forType: .string)
        }
        Button("mac_apply_address") { applyFromHistory(entry) }
    }

    private func historyRow(_ entry: MACHistoryEntry) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 9) {
                IconTile(kindSymbol(entry.kind), size: 28, tint: kindTint(entry.kind))
                Text(kindTitle(entry.kind))
                    .font(Theme.font(.subheadline))
                    .foregroundColor(Palette.textPrimary)
                    .lineLimit(1)
            }
            .frame(width: 160, alignment: .leading)

            Text(entry.mac)
                .font(Theme.font(.callout, design: .monospaced))
                .foregroundColor(Palette.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(width: 180, alignment: .leading)

            Text(entry.interface)
                .font(Theme.font(.caption, design: .monospaced))
                .foregroundColor(Palette.textSecondary)
                .frame(width: 110, alignment: .leading)

            Text(relative(entry.at))
                .font(Theme.font(.caption))
                .foregroundColor(Palette.textTertiary)
                .lineLimit(1)
                .frame(minWidth: 140, alignment: .leading)

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.mac, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11 * Theme.uiScale, weight: .semibold))
                    .foregroundColor(Palette.textTertiary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(Text("mac_copy_address"))
            .frame(width: 44)
        }
    }

    private var filteredHistory: [MACHistoryEntry] {
        var list = state.macHistory
        if let f = historyFilter { list = list.filter { $0.kind == f } }
        if !historyQuery.isEmpty {
            let q = historyQuery.lowercased()
            list = list.filter { $0.mac.lowercased().contains(q) || $0.interface.lowercased().contains(q) }
        }
        return list
    }

    private func kindTitle(_ kind: MACHistoryEntry.Kind) -> String {
        L10n.string("mac_kind_" + kind.rawValue)
    }

    private func kindSymbol(_ kind: MACHistoryEntry.Kind) -> String {
        switch kind {
        case .custom: return "keyboard"
        case .random: return "dice"
        case .restore: return "arrow.uturn.backward"
        case .auto: return "wand.and.stars"
        }
    }

    private func kindTint(_ kind: MACHistoryEntry.Kind) -> Color {
        switch kind {
        case .custom: return Palette.info
        case .random: return Palette.mint
        case .restore: return Palette.textSecondary
        case .auto: return Palette.warning
        }
    }

    private func relative(_ d: Date) -> String {
        RelativeDate.stringFull(for: d, language: state.settings.language)
    }

    // MARK: - Status

    /// MAC aktif = berbeda dari alamat keras perangkat.
    ///
    /// Membandingkan dengan hardware MAC adalah satu-satunya definisi
    /// "di-spoof" yang jujur di sini; tidak ada state terpisah yang bisa
    /// berbohong.
    ///
    /// `hardwareMAC` kosong berarti macOS tidak mengungkap alamat keras
    /// (Apple Silicon / macOS baru). Interface seperti itu TIDAK boleh
    /// dihitung sebagai "di-spoof" — tanpa: `currentMAC != ""` selalu benar,
    /// jadi kartu akan menampilkan hijau padahal tidak ada yang bisa
    /// dipastikan (D61).
    private var spoofActive: Bool {
        ifaces.contains { iface in
            guard !iface.hardwareMAC.isEmpty else { return false }
            return iface.currentMAC != iface.hardwareMAC
        }
    }

    private var currentMAC: String {
        ifaces.first?.currentMAC ?? "—"
    }

    private var hardwareMAC: String {
        ifaces.first?.hardwareMAC ?? "—"
    }

    // MARK: - Aksi

    private func loadInterfaces() {
        DispatchQueue.global().async {
            let list = MacSpoofClient.listInterfaces()
            DispatchQueue.main.async {
                ifaces = list
                if selected == nil { selected = list.first?.name }
            }
        }
    }

    private func randomize(_ it: MACInterface) {
        let mac = Validators.randomMAC()
        MacSpoofClient.setMAC(iface: it.name, mac: mac) { ok, msg in
            message = ok ? "OK: \(mac)" : msg
            // Hanya dicatat kalau benar-benar berhasil — riwayat harus berisi
            // perubahan nyata, bukan niat.
            if ok { state.recordMACChange(mac: mac, kind: .random, interface: it.name) }
            loadInterfaces()
        }
    }

    private func restore(_ it: MACInterface) {
        MacSpoofClient.setMAC(iface: it.name, mac: it.hardwareMAC) { ok, msg in
            message = ok ? NSLocalizedString("mac_restored", comment: "") : msg
            if ok { state.recordMACChange(mac: it.hardwareMAC, kind: .restore, interface: it.name) }
            loadInterfaces()
        }
    }

    private func setCustom() {
        guard let target = selected ?? ifaces.first?.name else { message = "—"; return }
        let mac = customMAC.lowercased()
        MacSpoofClient.setMAC(iface: target, mac: mac) { ok, msg in
            message = ok ? NSLocalizedString("mac_set_ok", comment: "") : msg
            if ok {
                state.recordMACChange(mac: mac, kind: .custom, interface: target)
                customMAC = ""
            }
            loadInterfaces()
        }
    }

    /// Terapkan ulang MAC dari riwayat ke interface yang sama.
    private func applyFromHistory(_ entry: MACHistoryEntry) {
        customMAC = entry.mac
        selected = entry.interface
        showCustom = true
    }
}

/// Klien XPC untuk MAC (via helper). Daftar interface dibaca lokal via networksetup.
public enum MacSpoofClient {
    public static func listInterfaces() -> [MACInterface] {
        var out: [MACInterface] = []
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        p.arguments = ["-listallhardwareports"]
        let pipe = Pipe(); p.standardOutput = pipe
        do { try p.run() } catch { return [] }
        // Baca dulu, baru tunggu: `waitUntilExit()` sebelum membaca pipe bisa
        // macet permanen kalau output melewati buffer ~64 KB (D61).
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let txt = String(data: data, encoding: .utf8) ?? ""
        var port = "", device = ""
        for line in txt.components(separatedBy: .newlines) {
            if line.hasPrefix("Hardware Port:") { port = line.replacingOccurrences(of: "Hardware Port:", with: "").trimmingCharacters(in: .whitespaces) }
            else if line.hasPrefix("Device:") {
                device = line.replacingOccurrences(of: "Device:", with: "").trimmingCharacters(in: .whitespaces)
                if Validators.isValidInterface(device) {
                    let cur = currentMAC(of: device) ?? "—"
                    // BUG LAMA (D61): `hardwareMAC` diisi dengan nilai yang
                    // SAMA dengan `currentMAC`, sehingga `spoofActive`
                    // (`currentMAC != hardwareMAC`) secara struktural SELALU
                    // false — kartu ini tidak pernah bisa menampilkan status
                    // "dispoof" yang benar, dan riwayat yang disimpan ikut
                    // keliru.
                    //
                    // Alamat keras yang benar ada di system_profiler, di blok
                    // "Hardware Port:". Kalau macOS tidak memberi tahu
                    // (Apple Silicon memblokirnya), kita perlu tahu itu secara
                    // eksplisit — nilai kosong, bukan pen disinformation.
                    let hw = hardwareMAC(of: device) ?? ""
                    out.append(MACInterface(name: device, device: port,
                                            currentMAC: cur, hardwareMAC: hw))
                }
            }
        }
        return out
    }

    /// Alamat keras dari `Hardware Port` di system_profiler.
    ///
    /// Kosong berarti "tidak diketahui" (macOS baru / Apple Silicon) — bukan
    /// berarti sama dengan alamat sekarang. Teks "Default"/"—" disetir ulang
    /// ke `nil` supaya tidak disamakan dengan MAC asli.
    private static func hardwareMAC(of iface: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        p.arguments = ["SPNetworkDataType"]
        let pipe = Pipe(); p.standardOutput = pipe
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let txt = String(data: data, encoding: .utf8) ?? ""

        // Cari blok yang headed "Hardware Port: <iface>", lalu baris "MAC Address:".
        var inBlock = false
        for raw in txt.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("Hardware Port:") {
                let port = line.replacingOccurrences(of: "Hardware Port:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                inBlock = (port == iface)
                continue
            }
            guard inBlock, line.hasPrefix("MAC Address:") else { continue }
            let mac = line.replacingOccurrences(of: "MAC Address:", with: "")
                .trimmingCharacters(in: .whitespaces)
            if Validators.isValidMACFormat(mac) { return mac }
        }
        return nil
    }

    private static func currentMAC(of iface: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/sbin/ifconfig")
        p.arguments = [iface]
        let pipe = Pipe(); p.standardOutput = pipe
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let txt = String(data: data, encoding: .utf8) ?? ""
        for line in txt.components(separatedBy: .newlines) {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("ether ") {
                return line.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "ether ", with: "").components(separatedBy: " ").first
            }
        }
        return nil
    }

    public static func setMAC(iface: String, mac: String, reply: @escaping (Bool, String) -> Void) {
        guard Validators.isValidInterface(iface) else { reply(false, "iface"); return }
        guard Validators.isValidMACFormat(mac) else { reply(false, "mac"); return }
        let conn = NSXPCConnection(machServiceName: AppConstants.helperMachService, options: .privileged)
        conn.remoteObjectInterface = NSXPCInterface(with: FreePNHelperProtocol.self)
        conn.resume()
        guard let proxy = conn.remoteObjectProxyWithErrorHandler({ e in
            conn.invalidate(); reply(false, e.localizedDescription)
        }) as? FreePNHelperProtocol else { conn.invalidate(); reply(false, "xpc"); return }
        proxy.setMAC(interface: iface, mac: mac) { ok, msg in
            conn.invalidate(); reply(ok, msg)
        }
    }
}