import Foundation

/// Keputusan per-flow inklusif/eksklusif ala Windscribe (D42: tanpa sysext —
/// daftar ini hanya dipakai app untuk pratinjau & test; penetrated Routing-nya
/// dikerjakan sing-box lewat aturan `process_name` di dalam Daemon TUN).
///
/// - inclusive: HANYA app dalam daftar → proxy; lainnya direct.
/// - exclusive: app dalam daftar → direct (bypass); lainnya → proxy.
/// - Daftar berisi bundle ID (mis. "com.apple.Safari"); identitas sumber dari
///   sumber app pihak ketiga berbentuk "TEAMID.com.example.app" sehingga cocok
///   exact ATAU suffix.
/// - Flow DNS (port 53) diperlakukan SAMA mengikuti identitas app sumber.
public enum SplitDecision {
    public static func shouldProxy(signingID: String?, mode: SplitMode, appIDs: [String]) -> Bool {
        let inList = isListed(signingID: signingID, appIDs: appIDs)
        switch mode {
        case .inclusive: return inList
        case .exclusive: return !inList
        }
    }

    /// Tanpa identitas (nil/kosong): anggap sistem — ikut final default
    /// (exclusive=proxy/VPN penuh, inclusive=direct/bypass).
    public static func isListed(signingID: String?, appIDs: [String]) -> Bool {
        guard let raw = signingID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty, !appIDs.isEmpty else { return false }
        let id = raw.lowercased()
        for e in appIDs {
            let entry = e.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if entry.isEmpty { continue }
            if id == entry || id.hasSuffix("." + entry) { return true }
        }
        return false
    }
}
