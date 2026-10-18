import Foundation

/// Protokol XPC yang di-ekspos helper. HANYA perintah whitelist.
/// Tidak ada eksekusi shell bebas.
@objc(FreePNHelperProtocol)
public protocol FreePNHelperProtocol {
    func version(reply: @escaping (String) -> Void)
    func startCore(configPath: String, reply: @escaping (Bool, String) -> Void)
    func stopCore(reply: @escaping (Bool, String) -> Void)
    func coreStatus(reply: @escaping (Bool, String) -> Void)
    func setMAC(interface iface: String, mac: String, reply: @escaping (Bool, String) -> Void)
    func restoreMAC(interface iface: String, reply: @escaping (Bool, String) -> Void)
    func currentMAC(interface iface: String, reply: @escaping (String) -> Void)
}

/// Nama notifikasi internal.
public enum XPCNames {
    public static let machService = AppConstants.helperMachService
}
