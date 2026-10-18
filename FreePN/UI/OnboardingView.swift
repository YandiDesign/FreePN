import SwiftUI
import ServiceManagement

/// Layar pertama: memakai bahasa desain yang sama supaya app tidak dibuka
/// dengan halaman bergaya sistem lalu berubah jadi redesign di tengah jalan.
struct OnboardingView: View {
    @EnvironmentObject var state: AppState
    @State private var step = 0
    @State private var installing = false
    @State private var installMessage = ""

    private let totalSteps = 2

    var body: some View {
        VStack(spacing: 0) {
            brand
            card
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var brand: some View {
        VStack(spacing: 12) {
            BrandMark(size: 72)
            Text("FreePN")
                .font(Theme.scaled(30, weight: .bold))
                .foregroundColor(Palette.textPrimary)
            Text("app_tagline")
                .font(Theme.font(.callout))
                .foregroundColor(Palette.textTertiary)
        }
        .padding(.top, 56)
        .padding(.bottom, 24)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepIndicator
            Hairline()
            stepContent
        }
        .padding(26)
        .frame(maxWidth: 560)
        .freepnCard()
    }

    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalSteps, id: \.self) { i in
                Capsule(style: .continuous)
                    .fill(i <= step ? Palette.mint : Palette.well)
                    .frame(height: 4)
            }
            Spacer(minLength: 0)
            Text(L10n.formatted("onboard_step", step + 1, totalSteps))
                .font(Theme.font(.caption))
                .foregroundColor(Palette.textTertiary)
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0:
            VStack(alignment: .leading, spacing: 14) {
                Text("onboard_welcome")
                    .font(Theme.font(.body))
                    .foregroundColor(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(Palette.warning)
                    Text("warn_free_nodes")
                        .font(Theme.font(.caption))
                        .foregroundColor(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Palette.warning.opacity(0.09))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Palette.warning.opacity(0.28), lineWidth: 1)
                )
            }

        case 1:
            VStack(alignment: .leading, spacing: 14) {
                Text("onboard_helper_title")
                    .font(Theme.screenTitle)
                    .foregroundColor(Palette.textPrimary)
                Text("onboard_helper_desc")
                    .font(Theme.font(.body))
                    .foregroundColor(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if installing {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("installing_helper")
                            .font(Theme.font(.callout))
                            .foregroundColor(Palette.textSecondary)
                    }
                } else {
                    Button("action_install_helper") { installHelper() }
                        .buttonStyle(PrimaryButtonStyle())
                }

                if !installMessage.isEmpty {
                    Text(installMessage)
                        .font(Theme.font(.callout))
                        .foregroundColor(Palette.textSecondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button { openLoginItems() } label: {
                    Label("onboard_open_settings", systemImage: "gearshape")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GhostButtonStyle())

                Text("onboard_helper_manual")
                    .font(Theme.font(.caption))
                    .foregroundColor(Palette.textTertiary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

        default:
            VStack(alignment: .leading, spacing: 14) {
                IconTile("checkmark.shield.fill", size: 46, tint: Palette.mint)
                Text("onboard_done")
                    .font(Theme.font(.body))
                    .foregroundColor(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if step > 0 {
                Button("action_back") { step -= 1 }
                    .buttonStyle(GhostButtonStyle())
            }
            Spacer(minLength: 0)
            if step < totalSteps {
                Button("action_next") { step += 1 }
                    .buttonStyle(PrimaryButtonStyle())
            } else {
                Button("action_start") {
                    state.hasOnboarded = true; state.persist(onlySettings: true)
                    state.startAutoRefreshIfNeeded()
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(.horizontal, 30)
        .padding(.top, 20)
        .padding(.bottom, 36)
        .frame(maxWidth: 560)
    }

    private func openLoginItems() {
        // macOS 13: buka System Settings > General > Login Items.
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Pasang helper via dialog password macOS (tanpa Terminal).
    private func installHelper() {
        installing = true
        installMessage = ""
        Task {
            do {
                let out = try await HelperInstaller.install()
                installMessage = "\(NSLocalizedString("install_helper_ok", comment: ""))\n\(out)"
                state.checkHealth()
            } catch {
                installMessage = (error as NSError).localizedDescription
            }
            installing = false
        }
    }
}