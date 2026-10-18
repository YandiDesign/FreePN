import Foundation

/// MAC spoofing HANYA di helper, array argumen (tanpa shell string).
final class MacSpoofer {
    var lastError: String = ""

    func current(of iface: String) -> String? {
        guard Validators.isValidInterface(iface) else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/sbin/ifconfig")
        p.arguments = [iface]
        let pipe = Pipe(); p.standardOutput = pipe
        do { try p.run(); p.waitUntilExit() } catch { return nil }
        let txt = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        for line in txt.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("ether ") { return t.replacingOccurrences(of: "ether ", with: "").components(separatedBy: " ").first }
        }
        return nil
    }

    /// ifconfig <iface> ether <mac>; Wi-Fi: matikan radio sebentar via networksetup.
    func set(iface: String, mac: String) -> Bool {
        guard Validators.isValidInterface(iface), Validators.isValidMACFormat(mac) else {
            lastError = "invalid input"; return false
        }
        // Coba matikan Wi-Fi bila interface adalah Wi-Fi (abaikan gagal untuk Ethernet).
        _ = run("/usr/sbin/networksetup", ["-setairportpower", iface, "off"])
        let ok = run("/sbin/ifconfig", [iface, "ether", mac])
        _ = run("/usr/sbin/networksetup", ["-setairportpower", iface, "on"])
        // Baca ulang & bandingkan — jangan diam-diam dianggap berhasil.
        Thread.sleep(forTimeInterval: 1.0)
        if let cur = current(of: iface), cur.lowercased() == mac.lowercased() { return true }
        if !ok { return false }
        lastError = "verify failed: got \(current(of: iface) ?? "?")"
        return false
    }

    @discardableResult
    private func run(_ path: String, _ args: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        do { try p.run(); p.waitUntilExit() } catch { lastError = error.localizedDescription; return false }
        return p.terminationStatus == 0
    }
}
