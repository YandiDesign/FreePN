import Foundation

/// Validator ketat untuk MAC + host/port. Dipakai app & helper & unit test.
public enum Validators {
    /// Format xx:xx:xx:xx:xx:xx heksadesimal.
    private static let macRegex = try! NSRegularExpression(pattern: "^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$")
    private static let ifaceRegex = try! NSRegularExpression(pattern: "^en[0-9]+$")

    public static func isValidMACFormat(_ mac: String) -> Bool {
        let r = NSRange(mac.startIndex..<mac.endIndex, in: mac)
        return macRegex.firstMatch(in: mac, range: r) != nil
    }

    /// MAC acak valid: unicast (bit0 byte0 = 0) & locally administered (bit1 = 1).
    public static func isValidRandomMAC(_ mac: String) -> Bool {
        guard isValidMACFormat(mac) else { return false }
        let first = String(mac.prefix(2))
        guard let byte = UInt8(first, radix: 16) else { return false }
        return (byte & 0x01) == 0 && (byte & 0x02) == 0x02
    }

    public static func randomMAC() -> String {
        var bytes = [UInt8](repeating: 0, count: 6)
        for i in 0..<6 { bytes[i] = UInt8.random(in: 0...255) }
        bytes[0] = (bytes[0] & 0xFC) | 0x02 // unicast + locally administered
        return bytes.map { String(format: "%02x", $0) }.joined(separator: ":")
    }

    public static func isValidInterface(_ iface: String) -> Bool {
        let r = NSRange(iface.startIndex..<iface.endIndex, in: iface)
        return ifaceRegex.firstMatch(in: iface, range: r) != nil
    }

    public static func isValidHost(_ host: String) -> Bool {
        return !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public static func isValidPort(_ port: Int) -> Bool {
        return port >= 1 && port <= 65535
    }

    // MARK: - Kredensial (D51)

    /// Metode Shadowsocks yang benar-benar bisa dipakai sing-box.
    ///
    /// Di luar daftar ini sing-box menolak outbound-nya, dan penolakan itu
    /// berlaku untuk SELURUH config probe — bukan cuma satu node.
    public static let shadowsocksMethods: Set<String> = [
        "aes-256-gcm", "aes-128-gcm", "chacha20-ietf-poly1305",
        "aes-256-cfb", "aes-128-cfb", "rc4-md5", "chacha20-ietf",
        "none", "plain",
        "2022-blake3-aes-128-gcm", "2022-blake3-aes-256-gcm",
        "2022-blake3-chacha20-poly1305",
    ]

    /// Apakah string ini masuk akal sebagai kredensial, bukan byte sampah?
    ///
    /// D51 — bug nyata: feed `morpheusadam` memuat link
    /// `ss://ax51Ok45f351XA@104.18.218.118:443` yang payload base64-nya
    /// biner mentah (`k\x1eu:N9\x7f~u\`), bukan `method:password`. Parser
    /// ours menerimanya karena isinya kebetulan punya tanda `:` dan UTF-8
    /// valid — lalu `sing-box check` menolak SELURUH config probe karena
    /// `unknown method: k`, dan verifikasi internet dilewati untuk ratusan
    /// node lain yang sebenarnya sehat.
    ///
    /// Tanda tangan sampah delimiter/base64 adalah karakter kontrol
    /// (U+0000–U+001F, U+007F). Kredensial asli tidak pernah memakainya.
    public static func isPlausibleSecret(_ s: String) -> Bool {
        for scalar in s.unicodeScalars where scalar.value < 0x20 || scalar.value == 0x7F {
            return false
        }
        return true
    }

    /// Whitelist path config yang boleh dijalankan helper.
    /// App menulis di temp milik USER (/var/folders/...), helper jalan sebagai ROOT
    /// dengan temp berbeda — jadi validasi tidak boleh memakai temporaryDirectory
    /// milik proses helper, melainkan prefix yang mencakup semua user temp macOS.
    public static func isAllowedConfigPath(_ path: String) -> Bool {
        if path.contains(";") || path.contains("\n") || path.contains("..") { return false }
        guard path.hasSuffix(".json") else { return false }
        if path.hasPrefix("/tmp/") || path.hasPrefix("/private/tmp/") { return true }
        if path.hasPrefix("/var/folders/") { return true }
        if path.contains("Application Support/FreePN") { return true }
        return false
    }
}
