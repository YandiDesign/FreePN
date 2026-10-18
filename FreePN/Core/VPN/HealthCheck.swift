import Foundation
import Combine

/// Hasil satu pemeriksaan izin/kesehatan.
public struct HealthItem: Identifiable {
    public enum Level { case ok, warn, fail, info }
    public var id: String
    public var level: Level
    public var titleKey: String
    public var detailKey: String
    public var fixKey: String
    public var detailArg: String = ""
    public init(id: String, level: Level, titleKey: String, detailKey: String, fixKey: String, detailArg: String = "") {
        self.id = id; self.level = level
        self.titleKey = titleKey; self.detailKey = detailKey; self.fixKey = fixKey
        self.detailArg = detailArg
    }
    public var title: String { L10n.string(titleKey) }
    public var detail: String {
        let base = L10n.string(detailKey)
        return detailArg.isEmpty ? base : "\(base) (\(detailArg))"
    }
    public var fix: String { L10n.string(fixKey) }
}

/// Pemeriksa izin & kesehatan saat app dibuka: helper root, core, mode split,
/// port, entri VPN, firewall. Yang belum beres diberi info cara membetulkan.
@MainActor
public final class HealthChecker: ObservableObject {
    @Published public var items: [HealthItem] = []
    @Published public var isChecking = false
    public var hasFailure: Bool { items.contains { $0.level == .fail } }
    public var hasWarning: Bool { items.contains { $0.level == .warn } }

    public init() {}

    public func check(split: SplitTunnelConfig, coreBinary: String) async {
        isChecking = true
        defer { isChecking = false }
        var out: [HealthItem] = []

        // 1. Helper root: harus terpasang (LaunchDaemon) + merespons XPC.
        // Tanpa ini TUN="operation not permitted" (verify-timeout → fallback lokal gagal).
        //
        // D69: versi 1.3 MASIH diterima (hanya beda lokasi log), tapi 1.4 yang
        // diharapkan. Yang penting: assessment ini dulu `contains("1.3")` —
        // satu string, dan helper versi 1.3 yang sudah terpasang juga melaporkan
        // 1.3, jadi mismatch "/tmp vs /var/log" tidak terdeteksi sama sekali.
        if let v = await helperVersion() {
            if Self.isHelperVersionAcceptable(v) {
                out.append(HealthItem(id: "helper", level: .ok,
                                      titleKey: "health_helper", detailKey: "health_helper_ok",
                                      fixKey: "health_fix_none", detailArg: v))
            } else {
                out.append(HealthItem(id: "helper", level: .fail,
                                      titleKey: "health_helper", detailKey: "health_helper_stale",
                                      fixKey: "health_helper_fix", detailArg: v))
            }
        } else {
            out.append(HealthItem(id: "helper", level: .fail,
                                  titleKey: "health_helper", detailKey: "health_helper_fail",
                                  fixKey: "health_helper_fix"))
        }

        // 2. Core sing-box di bundle: harus ada + executable.
        if !coreBinary.isEmpty && FileManager.default.isExecutableFile(atPath: coreBinary) {
            out.append(HealthItem(id: "core", level: .ok,
                                  titleKey: "health_core", detailKey: "health_core_ok",
                                  fixKey: "health_fix_none"))
        } else {
            out.append(HealthItem(id: "core", level: .fail,
                                  titleKey: "health_core", detailKey: "health_core_fail",
                                  fixKey: "health_core_fix"))
        }

        // 3. Mode split: inklusif-kosong = VPN tak mem-VPN-kan apa pun.
        if SingBoxConfigBuilder.isBypassAll(split: split) {
            out.append(HealthItem(id: "split", level: .fail,
                                  titleKey: "health_split", detailKey: "health_split_fail",
                                  fixKey: "health_split_fix"))
        } else {
            out.append(HealthItem(id: "split", level: .ok,
                                  titleKey: "health_split", detailKey: "health_split_ok",
                                  fixKey: "health_fix_none"))
        }

        // 4. Port clash/mixed default: bila terpakai (mis. ClashFX di port lama),
        // auto-probe menangani — tapi beri peringatan agar user paham.
        let cFree = FreePort.isPortFree(FreePort.defaultClashPort)
        let mFree = FreePort.isPortFree(FreePort.defaultMixedPort)
        if cFree && mFree {
            out.append(HealthItem(id: "ports", level: .ok,
                                  titleKey: "health_ports", detailKey: "health_ports_ok",
                                  fixKey: "health_fix_none"))
        } else {
            var busy: [String] = []
            if !cFree { busy.append(String(FreePort.defaultClashPort)) }
            if !mFree { busy.append(String(FreePort.defaultMixedPort)) }
            out.append(HealthItem(id: "ports", level: .warn,
                                  titleKey: "health_ports", detailKey: "health_ports_warn",
                                  fixKey: "health_ports_fix",
                                  detailArg: busy.joined(separator: ", ")))
        }


        // 5. Firewall/izin jaringan: info — macOS bertanya sekali per build.
        out.append(HealthItem(id: "firewall", level: .info,
                              titleKey: "health_firewall", detailKey: "health_firewall_info",
                              fixKey: "health_firewall_fix"))


        items = out
    }

    /// Tanya versi helper via XPC (timeout 3 dtk). Nil = belum terpasang/mati.
    /// Helper versi ini masih bisa dipakai?
    ///
    /// Murni & nonisolated supaya bisa diuji tanpa XPC.
    ///
    /// D69: pencocokan harus berupa TOKEN, bukan substring. Dua jebakan yang
    /// nyata di sini:
    /// - `contains("1.3")` menerima "1.30".
    /// - `\b` saja TIDAK cukup: dalam regex, `-` BUKAN karakter word, jadi
    ///   "1.4-beta" tetap dianggap punya batas setelah "4" dan akan diterima —
    ///   padahal helper ber-beta bukan helper yang menulis ke `/var/log`.
    /// Dipakai pola yang mengunci dari digit dan delimiter Versi.
    public nonisolated static func isHelperVersionAcceptable(_ reported: String) -> Bool {
        AppConstants.helperCompatibleVersions.contains { version in
            let escaped = NSRegularExpression.escapedPattern(for: version)
            // Depan: bukan digit. Belakang: bukan digit DAN bukan tanda baca
            // penghubung versi (`-`, `_`, `.`), supaya "1.4-beta" ditolak.
            let pattern = "(?<![0-9.])" + escaped + "(?![0-9._-])"
            return reported.range(of: pattern, options: .regularExpression) != nil
        }
    }

    private func helperVersion() async -> String? {        await withCheckedContinuation { cont in
            let c = NSXPCConnection(machServiceName: AppConstants.helperMachService, options: .privileged)
            c.remoteObjectInterface = NSXPCInterface(with: FreePNHelperProtocol.self)
            c.resume()
            var done = false
            let finish: (String?) -> Void = { v in
                if !done { done = true; c.invalidate(); cont.resume(returning: v) }
            }
            guard let proxy = c.remoteObjectProxyWithErrorHandler({ _ in finish(nil) }) as? FreePNHelperProtocol else {
                c.invalidate(); cont.resume(returning: nil); return
            }
            proxy.version { v in finish(v) }
            DispatchQueue.global().asyncAfter(deadline: .now() + 3) { finish(nil) }
        }
    }
}
