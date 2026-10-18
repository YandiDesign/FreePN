import Foundation

/// Cek IP keluar. PENTING: proses FreePN di-bypass dari tunnel (aturan direct),
/// jadi fetch langsung SELALU menunjukkan IP asli — tidak bisa dipakai memverifikasi VPN.
/// Untuk verifikasi, request dilewatkan ke SOCKS mixed-inbound core (127.0.0.1:<mixedPort>):
/// - Sukses + IP berubah → node valid & proxy path hidup.
/// - Gagal → node mati (atau core tidak jalan), BUKAN salah TUN.
/// - Sukses tapi IP sistem tetap → TUN tidak menangkap trafik (masalah routing).
public enum ExitIPChecker {
    public static func viaCore(port: Int = FreePort.defaultMixedPort, timeout: TimeInterval = 10) async -> String? {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = timeout
        cfg.timeoutIntervalForResource = timeout
        cfg.connectionProxyDictionary = [
            "SOCKSEnable": 1,
            "SOCKSProxy": "127.0.0.1",
            "SOCKSPort": port,
        ]
        return await fetchIP(session: URLSession(configuration: cfg))
    }

    public static func direct(timeout: TimeInterval = 10) async -> String? {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = timeout
        cfg.timeoutIntervalForResource = timeout
        return await fetchIP(session: URLSession(configuration: cfg))
    }

    private static func fetchIP(session: URLSession) async -> String? {
        guard let url = URL(string: "https://api.ipify.org?format=json") else { return nil }
        do {
            let (data, _) = try await session.data(from: url)
            if let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let ip = o["ip"] as? String, !ip.isEmpty { return ip }
            // Fallback format teks polos.
            if let ip = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !ip.isEmpty, ip.count < 64 { return ip }
            return nil
        } catch { return nil }
    }
}
