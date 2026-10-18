import SwiftUI
import AppKit

/// Sheet satu grup proxy manual (D93).
///
/// Dua jalur penambahan, karena keduanya benar-benar dipakai:
///
/// - **Dari tautan** — user punya `vmess://…` / `trojan://…` dari(provider,
///   dan menempelkannya jauh lebih cepat daripada mengisi 12 kolom. Menghormati
///   base64 dan tempel banyak link sekaligus, karena itulah yang benar-benar
///   keluar dari penyedia.
/// - **Form lengkap** — kasus di mana link-nya tidak ada sama sekali (server
///   purchased, atau tautannya sudah kedaluwarsa) dan semua parameter harus
///   diketik.
///
/// Keduanya melewati validasi core yang sama sebelum diterima, dan hasilnya
/// masuk ke daftar global sebagai node biasa — jadi tabel Server, ping, dan
/// connect tidak tahu bedanya dengan node dari feed.
struct ManualGroupView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) var dismiss

    let sourceID: String

    @State private var tab: Tab = .link
    @State private var linkText = ""
    @State private var draft = ManualNodeDraft()
    @State private var problems: [String] = []
    @State private var success: String? = nil
    @State private var busy = false
    /// Node yang SEDANG diedit, `nil` = menambah baru.
    ///
    /// Edit memakai form yang sama persis dengan tambah — bukan dialog kedua.
    /// Dua form berarti dua tempat untuk field bisa salah forgot, dan kredensial
    /// yang panjang lebih mudah diketik ulang dengan benar daripada
    /// disalin-salin di antara dua layout.
    @State private var editing: ProxyNode? = nil

    enum Tab { case link, form }

    private var source: VPNSubscriptionSource? {
        state.sources.first { $0.id == sourceID }
    }

    private var nodes: [ProxyNode] {
        state.nodes.filter { $0.sourceID == sourceID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            picker
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if tab == .link { linkPane } else { formPane }
                    if !problems.isEmpty { problemList }
                    if let s = success {
                        Text(s)
                            .font(Theme.font(.caption))
                            .foregroundColor(Palette.success)
                    }
                }
                .padding(.horizontal, 20)
            }
            Divider()
            footer
        }
        .frame(minWidth: 620, minHeight: 520)
    }

    // MARK: - Kepala

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(source?.name ?? L10n.string("manual_group_title"))
                    .font(Theme.screenTitle)
                    .foregroundColor(Palette.textPrimary)
                Text(L10n.formatted("manual_group_count", nodes.count))
                    .font(Theme.font(.caption))
                    .foregroundColor(Palette.textTertiary)
            }
            Spacer()
            Button("action_close") { dismiss() }
                .buttonStyle(SecondaryButtonStyle())
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private var picker: some View {
        Picker("", selection: $tab) {
            Text("manual_tab_link").tag(Tab.link)
            Text("manual_tab_form").tag(Tab.form)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 20)
    }

    // MARK: - Dari tautan

    private var linkPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("", text: $linkText, axis: .vertical)
                .textFieldStyle(.plain)
                .foregroundColor(Palette.textPrimary)
                .padding(10)
                .lineLimit(4...8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Palette.well)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Palette.border, lineWidth: 1)
                )
                .overlay(alignment: .topLeading) {
                    if linkText.isEmpty {
                        Text("manual_link_placeholder")
                            .font(Theme.font(.callout))
                            .foregroundColor(Palette.textTertiary)
                            .padding(12)
                            .allowsHitTesting(false)
                    }
                }
            Text("manual_link_hint")
                .font(Theme.font(.caption))
                .foregroundColor(Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Form lengkap

    private var formPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            row {
                labeled("manual_form_name") { TextField("", text: $draft.name).plainField() }
                labeled("manual_form_proto") { protoPicker }
            }
            row {
                labeled("manual_form_host") { TextField("", text: $draft.host).plainField() }
                labeled("manual_form_port") { TextField("", text: $draft.port).plainField() }
            }
            row {
                labeled(credentialLabel) { TextField("", text: $draft.credential).plainField() }
                if ManualNodeDraft.supportsCipher(draft.proto) {
                    labeled("manual_form_cipher") { cipherPicker }
                }
            }

            if ManualNodeDraft.supportsTransport(draft.proto) {
                Divider()
                row {
                    labeled("manual_form_transport") { transportPicker }
                    labeled("manual_form_path") { TextField("", text: $draft.path).plainField() }
                }
                if draft.transport == .ws {
                    row {
                        labeled("manual_form_host_header") {
                            TextField("", text: $draft.transportHost).plainField()
                        }
                        Spacer(minLength: 0)
                    }
                }
            }

            if ManualNodeDraft.supportsTLS(draft.proto) {
                Divider()
                HStack(spacing: 18) {
                    Toggle("manual_form_tls", isOn: $draft.tlsEnabled)
                        .toggleStyle(.switch)
                        .tint(Palette.mint)
                    Toggle("manual_form_insecure", isOn: $draft.allowInsecure)
                        .toggleStyle(.switch)
                        .tint(Palette.mint)
                }
                row {
                    labeled("manual_form_sni") { TextField("", text: $draft.sni).plainField() }
                    labeled("manual_form_alpn") { TextField("", text: $draft.alpn).plainField() }
                }
                // REALITY hanya bermakna untuk VLESS. Menampilkannya untuk
                // protokol lain membuat form terlihat tidak tahu apa isinya.
                if ManualNodeDraft.supportsReality(draft.proto) {
                    row {
                        labeled("manual_form_pbk") {
                            TextField("", text: $draft.realityPublicKey).plainField()
                        }
                        labeled("manual_form_sid") {
                            TextField("", text: $draft.realityShortId).plainField()
                        }
                    }
                    row {
                        labeled("manual_form_fp") {
                            TextField("", text: $draft.fingerprint).plainField()
                        }
                        if ManualNodeDraft.supportsFlow(draft.proto) {
                            labeled("manual_form_flow") {
                                TextField("", text: $draft.flow).plainField()
                            }
                        }
                    }
                }
            }

            if ManualNodeDraft.supportsHysteria2(draft.proto) {
                Divider()
                row {
                    labeled("manual_form_obfs") {
                        TextField("", text: $draft.obfsPassword).plainField()
                    }
                    Spacer(minLength: 0)
                }
                row {
                    labeled("manual_form_up") { TextField("", text: $draft.upMbps).plainField() }
                    labeled("manual_form_down") { TextField("", text: $draft.downMbps).plainField() }
                }
            }
        }
    }

    /// Satu baris label+kontrol yang lebarnya sama rata.
    ///
    /// `Grid` tidak dipakai: butuh macOS 14 untuk versi yang punya
    /// `GridRow` spans, dan proyek ini tidak pernah memakainya di tempat lain.
    private func row(@ViewBuilder content: () -> some View) -> some View {
        HStack(alignment: .bottom, spacing: 14) {
            content()
        }
    }

    private var protoPicker: some View {
        Picker("", selection: $draft.proto) {
            ForEach(NodeProtocol.allCases, id: \.self) { p in
                Text(verbatim: p.rawValue).tag(p)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .tint(Palette.mint)
    }

    private var cipherPicker: some View {
        Picker("", selection: $draft.cipher) {
            ForEach(Self.cipherChoices, id: \.self) { c in
                Text(verbatim: c).tag(c)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .tint(Palette.mint)
    }

    private var transportPicker: some View {
        Picker("", selection: $draft.transport) {
            Text(verbatim: "tcp").tag(Transport.tcp)
            Text(verbatim: "ws").tag(Transport.ws)
            Text(verbatim: "grpc").tag(Transport.grpc)
            Text(verbatim: "h2").tag(Transport.http)
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .tint(Palette.mint)
    }

    private var credentialLabel: LocalizedStringKey {
        switch draft.proto {
        case .shadowsocks: return "manual_form_credential_ss"
        case .http, .socks: return "manual_form_credential_proxy"
        default: return "manual_form_credential"
        }
    }

    static let cipherChoices = [
        "aes-256-gcm", "aes-128-gcm", "chacha20-ietf-poly1305", "xchacha20-ietf-poly1305",
    ]

    // MARK: - Daftar isi grup

    @ViewBuilder
    private var footer: some View {
        VStack(spacing: 8) {
            if nodes.isEmpty {
                Text("manual_group_empty")
                    .font(Theme.font(.caption))
                    .foregroundColor(Palette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                // Klik = ubah, klik kanan = hapus. Tanpa tombol pensil/X di
                // tiap chip: 5 akun × 2 ikon = 10 target kecil yang berisik —
                // nama + badge proto sudah cukup sebagai isi chip.
                Text("manual_accounts_hint")
                    .font(Theme.font(.caption2))
                    .foregroundColor(Palette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                // Mengalir ke bawah (bukan scroll menyamping): 50 akun dalam
                // satu baris horizontal tidak manusiawi. `FlowLayout` membungkus
                // chip ke baris baru; tingginya dibatasi ~4 baris supaya
                // tombol Tutup/Tambah di bawahnya tidak terdorong keluar.
                ScrollView(.vertical, showsIndicators: true) {
                    FlowLayout {
                        ForEach(nodes) { n in
                            Button { startEditing(n) } label: {
                                HStack(spacing: 7) {
                                    Text(verbatim: n.name)
                                        .font(Theme.font(.callout))
                                        .foregroundColor(Palette.textPrimary)
                                        .lineLimit(1)
                                    ProtocolBadge(n.proto)
                                }
                                .padding(.horizontal, 11)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(Palette.well))
                                .overlay(
                                    Capsule().strokeBorder(
                                        editing?.id == n.id ? Palette.mint : Palette.border.opacity(0.6),
                                        lineWidth: editing?.id == n.id ? 1.5 : 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: 300)
                            .help(L10n.string("manual_edit_node"))
                            .contextMenu {
                                Button(role: .destructive) {
                                    state.removeManualNode(id: n.id)
                                } label: {
                                    Label("action_remove_node", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 148)
            }
            HStack {
                if editing != nil {
                    Button("manual_edit_cancel") { cancelEditing() }
                        .buttonStyle(GhostButtonStyle())
                }
                // Backup = ekspor akun grup ini ke file teks (satu link per
                // baris, format yang sama dengan tab "Dari tautan"). Pulihkan
                // = impor kembali dari file itu. Cadangan hidup di tangan
                // user, di luar `nodes.json`, jadi refresh/gagal fetch apa
                // pun tidak bisa menghapusnya.
                Button { backupAccounts() } label: {
                    Label("manual_backup", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(GhostButtonStyle())
                .disabled(nodes.isEmpty || busy)
                .help(L10n.string("manual_backup_help"))
                Button { restoreAccounts() } label: {
                    Label("manual_restore", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(GhostButtonStyle())
                .disabled(busy)
                .help(L10n.string("manual_restore_help"))
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                Button("action_close") { dismiss() }
                    .buttonStyle(SecondaryButtonStyle())
                Button(editing == nil ? "manual_add_save" : "manual_edit_save") { submit() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(busy)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    private var problemList: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(problems, id: \.self) { p in
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(Palette.danger)
                    Text(verbatim: p)
                        .font(Theme.font(.caption))
                        .foregroundColor(Palette.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Palette.danger.opacity(0.10))
        )
    }

    // MARK: - Aksi

    /// Buka form edit untuk satu node: isi draft dari node itu dan pindah ke
    /// tab form.
    ///
    /// Pindah ke tab form WAJIB. Kalau tetap di tab tautan, user mengira
    /// formnya tidak terisi dan akan menempelkan tautan baru — yang membuat
    /// node kedua, bukan memperbaiki node yang salah.
    private func startEditing(_ node: ProxyNode) {
        problems = []
        success = nil
        editing = node
        draft = ManualNodeDraft(node: node)
        tab = .form
    }

    private func cancelEditing() {
        editing = nil
        draft = ManualNodeDraft()
    }

    /// Tulis semua akun grup ini ke file teks (satu share-link per baris).
    ///
    /// Formatnya identik dengan tab "Dari tautan", jadi file backup bisa
    /// dipulihkan lewat tombol Pulihkan MAUPUN tempel manual — dan isinya
    /// dijamin lolos parser sendiri (round-trip `ShareLinkEncoderTests`).
    private func backupAccounts() {
        problems = []
        success = nil
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(source?.name ?? "manual")-backup.txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ShareLinkEncoder.document(for: nodes).write(to: url, atomically: true, encoding: .utf8)
            success = L10n.formatted("manual_backup_saved", nodes.count)
        } catch {
            problems = [error.localizedDescription]
        }
    }

    /// Baca file backup (atau file link apa pun) kembali ke grup ini.
    /// Duplikat (akun yang sudah ada) dilewati `addManualNodes` by id —
    /// pulihkan dua kali tetap aman.
    private func restoreAccounts() {
        problems = []
        success = nil
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            problems = [L10n.string("manual_restore_unreadable")]
            return
        }
        busy = true
        let sid = sourceID
        Task {
            let result: AppState.ManualAddResult
            switch ManualNodeParser.parse(text, sourceID: sid) {
            case .single(let n):
                result = await state.addManualNodes([n], toGroup: sid)
            case .many(let ns):
                result = await state.addManualNodes(ns, toGroup: sid)
            case .failed(let m):
                busy = false
                problems = [m]
                return
            }
            busy = false
            switch result {
            case .added(let n):
                success = L10n.formatted("manual_add_added", n)
            case .failed(let ps):
                problems = ps
            }
        }
    }

    private func submit() {
        problems = []
        success = nil
        busy = true
        let sid = sourceID
        let target = editing
        Task {
            let result: AppState.ManualAddResult
            if let node = target {
                // Edit selalu lewat form, walau tab-nya sempat di tab tautan.
                // Menempelkan tautan bukan cara mengoreksi satu node.
                result = await state.updateManualNode(id: node.id, draft: draft)
            } else if tab == .link {
                switch ManualNodeParser.parse(linkText, sourceID: sid) {
                case .single(let n):
                    result = await state.addManualNodes([n], toGroup: sid)
                case .many(let ns):
                    result = await state.addManualNodes(ns, toGroup: sid)
                case .failed(let m):
                    busy = false
                    problems = [m]
                    return
                }
            } else {
                result = await state.addManualNode(draft: draft, toGroup: sid)
            }
            busy = false
            switch result {
            case .added(let n):
                if target != nil {
                    success = L10n.string("manual_edit_saved")
                    editing = nil
                    draft = ManualNodeDraft()
                    tab = .link
                } else {
                    success = L10n.formatted("manual_add_added", n)
                    linkText = ""
                    draft = ManualNodeDraft()
                }
            case .failed(let ps):
                problems = ps
            }
        }
    }

    // MARK: - Potongan tampilan

    private func labeled(_ label: LocalizedStringKey,
                         @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(Theme.font(.caption))
                .foregroundColor(Palette.textSecondary)
            content()
        }
    }
}

private extension View {
    /// Kolom teks polos dengan gaya yang sama di seluruh sheet ini.
    func plainField() -> some View {
        self
            .textFieldStyle(.plain)
            .foregroundColor(Palette.textPrimary)
            .padding(8)
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

/// Menyusun chip ke kanan lalu membungkus ke baris baru (tidak ada di
/// SwiftUI bawaan — `HStack`/`LazyHGrid` butuh jumlah kolom tetap, sedangkan
/// lebar chip akun berbeda-beda).
///
/// Murni layout (tanpa state) supaya deterministik: urutan dan posisi hanya
/// fungsi dari lebar container dan ukuran intrinsic tiap chip.
private struct FlowLayout: Layout {
    var horizontalSpacing: CGFloat = 8
    var verticalSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews,
                      cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                y += rowHeight + verticalSpacing
                widest = max(widest, x - horizontalSpacing)
                x = 0
                rowHeight = 0
            }
            x += size.width + horizontalSpacing
            rowHeight = max(rowHeight, size.height)
        }
        widest = max(widest, x > 0 ? x - horizontalSpacing : 0)
        return CGSize(width: width.isInfinite ? widest : width,
                      height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + verticalSpacing
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y),
                      proposal: ProposedViewSize(size))
            x += size.width + horizontalSpacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}