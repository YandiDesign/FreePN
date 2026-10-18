import Foundation
import Darwin

/// Cari port TCP bebas di 127.0.0.1 untuk clash API & mixed inbound.
/// Port statis lama (9090/1080) sering bentrok dengan ClashFX/ClashX/Zen
/// yang juga LISTEN di 9090 — berujung `bind: address already in use` dan
/// core mati diam-diam. Default baru 28909/28108 (di luar ekosistem Clash),
/// tetap di-probe agar 2 instance FreePN bisa berdampingan.
public enum FreePort {
    public static let defaultClashPort = 28909
    public static let defaultMixedPort = 28108

    /// Cek satu port spesifik (dipakai verifikasi pasca-start).
    public static func isPortFree(_ port: Int) -> Bool { isFree(port) }
    public static func tcp(from base: Int, count: Int = 20) -> Int {
        for p in base..<(base + count) {
            if isFree(p) { return p }
        }
        return base
    }

    private static func isFree(_ port: Int) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(port).bigEndian
        addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let r = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return r == 0
    }
}
