import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        Text(statusText)
        Divider()
        Button("action_connect") { quickConnect() }.disabled(state.nodes.isEmpty)
        Button("action_disconnect") { state.disconnect() }
            .disabled(!state.isConnected)
        Button("ping_all_action") { Task { await state.pingAll() } }
        Divider()
        // Hanya dua mode. Daftar app-nya diatur di tabel Split Tunneling,
        // bukan di sini.
        Picker("split_mode", selection: $state.split.mode) {
            Text("mode_inclusive").tag(SplitMode.inclusive)
            Text("mode_exclusive").tag(SplitMode.exclusive)
        }
        Divider()
        Button("action_quit") { NSApplication.shared.terminate(nil) }
    }

    private var statusText: String {
        switch state.connection.status {
        case .connected: return NSLocalizedString("status_connected", comment: "")
        case .connecting: return NSLocalizedString("status_connecting", comment: "")
        default: return NSLocalizedString("status_disconnected", comment: "")
        }
    }

    private func quickConnect() {
        guard let n = state.quickConnectNode() else { return }
        state.connect(node: n)
    }
}

/// Lokasi binary core (universal) di dalam bundle Resources.
///
/// `static let`, bukan computed property: `Bundle.url(forResource:)` melakukan
/// lookup di bundle setiap kali diakses, dan nilainya tidak pernah berubah
/// selama app hidup. Dipanggil dari `AppState.checkHealth` dan setiap connect.
public enum CorePaths {
    public static let singBox: String = {
        if let u = Bundle.main.url(forResource: "sing-box", withExtension: nil) { return u.path }
        return "/usr/local/bin/sing-box"
    }()
}
