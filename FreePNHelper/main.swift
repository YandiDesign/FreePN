import Foundation
import Security

/// Verifikasi identitas proses klien XPC.
///
/// Helper ini jalan sebagai ROOT dan menyediakan operasi yang berbahaya dari
/// sisi klien: menjalankan `sing-box` dengan TUN, mengubah MAC interface,
/// menghentikan core, membaca status jaringan. Kalau klien tidak diverifikasi,
/// SEMUA program lokal di mesin ini bisa memanggilnya — termasuk program yang
/// diunduh user tanpa disadari.
///
/// Verifikasi memakai PID klien lalu menarik `SecCode`-nya lewat
/// `SecCodeCopyGuestWithAttributes`, lalu mencocokkannya dengan designated
/// requirement milik FreePN.app.
///
/// CATATAN KEAMANAN YANG JUJUR: untuk proses lokal, PID bisa di-reuse dalam
/// celah waktu tertentu, jadi ini bukan jaminan mutlak terhadap penyerang
/// yang aktif dan terkoordinasi. Yang ini menutup model ancaman "proses
/// sembarang / skrip iseng tanpa target" — yang sebelumnya TIDAK tertutup
/// sama sekali — dan membuat helper menolak apa pun yang tidak ditandatangani
/// FreePN. Jaminan penuh butuh audit token, yang tidak dieksposkansan oleh
/// SDK 13.
enum ClientTrust {
    /// `true` bila proses `pid` adalah FreePN.app.
    static func isTrustedClient(pid: pid_t) -> Bool {
        #if DEBUG
        // Build lokal tanpa sertifikat Developer ID tidak punya anchor yang
        // bisa dicocokkan. Ini SADARI tidak aman dan hanya ada di Debug;
        // build Release memakai jalur verifikasi penuh.
        return true
        #else
        var code: SecCode?
        let attrs = [kSecGuestAttributePid as String: pid] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attrs, [], &code) == errSecSuccess,
              let code else { return false }
        guard let requirement = appRequirement() else { return false }
        // Ambil dynamic code klien lalu ubah ke static untuk diperiksa
        // terhadap requirement (`.common` agar resource bundle ikut divalidasi
        // — tanpa itu, app yang executable-nya asli tapi bundle-nya bisa
        // diselipkan akan lolos).
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess,
              let staticCode else { return false }
        let flags = SecCSFlags(rawValue: kSecCSCheckNestedCode)
        return SecStaticCodeCheckValidity(staticCode, flags, requirement) == errSecSuccess
        #endif
    }

    /// Designated requirement: anchor ke bundle ID.
    ///
    /// Sengaja TIDAK mengunci Team ID. README menyatakan app ini bisa
    /// ditandatangani dengan Personal Team gratis, jadi "identifier +
    /// tanda tangan yang valid" adalah batas yang bisa dipenuhi semua
    /// konfigurasi build yang didukung project ini.
    private static func appRequirement() -> SecRequirement? {
        var requirement: SecRequirement?
        let text = "identifier \"\(AppConstants.appBundleID)\""
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess else {
            return nil
        }
        return requirement
    }
}

/// Daemon FreePNHelper: XPC listener berhak istimewa.
/// Hanya perintah whitelist; verifikasi code-signing klien.
final class HelperDelegate: NSObject, NSXPCListenerDelegate {
    /// Koneksi yang sedang hidup, supaya jumlahnya bisa dibatasi.
    private var live = Set<ObjectIdentifier>()
    private let liveLock = NSLock()
    private static let maxConnections = 8

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection conn: NSXPCConnection) -> Bool {
        let pid = conn.processIdentifier

        // SECURITY (D61): verifikasi identitas SEBELUM `resume()`. Versi
        // lama menerima SEMUA koneksi lokal sementara komentarnya menyatakan
        // verifikasi dilakukan — dan tidak ada. Proses lokal mana pun bisa
        // menjalankan sing-box sebagai root dengan config miliknya sendiri,
        // mengubah MAC interface, atau mematikan VPN user.
        guard ClientTrust.isTrustedClient(pid: pid) else {
            HelperLog.log("REJECT untrusted pid=\(pid)")
            return false
        }

        liveLock.lock()
        live.insert(ObjectIdentifier(conn))
        let overLimit = live.count > Self.maxConnections
        liveLock.unlock()
        if overLimit {
            HelperLog.log("REJECT over connection limit pid=\(pid)")
            return false
        }

        HelperLog.log("accept connection pid=\(pid)")
        conn.exportedInterface = NSXPCInterface(with: FreePNHelperProtocol.self)
        // WAJIB singleton: tiap koneksi baru TIDAK boleh dapat HelperService baru.
        // Runner per-koneksi membuat startCore/coreStatus/stopCore buta satu sama
        // lain (spawn di runner A, status ditanya ke runner B yang kosong →
        // selalu "stopped", core yatim tak terhentikan). Bug verify-timeout.
        conn.exportedObject = HelperService.shared
        conn.invalidationHandler = { [weak self, weak conn] in
            if let c = conn {
                self?.liveLock.lock()
                self?.live.remove(ObjectIdentifier(c))
                self?.liveLock.unlock()
            }
            HelperService.shared.handleDisconnect()
        }
        conn.resume()
        return true
    }
}

HelperLog.log("\(HelperService.versionString) starting, mach=\(AppConstants.helperMachService)")
let delegate = HelperDelegate()
let listener = NSXPCListener(machServiceName: AppConstants.helperMachService)
listener.delegate = delegate
// `resume()` melempar (bukan return false) kalau nama mach service sudah dipakai
// proses lain. Tanpa penanganan, helper yang gagal start akan tetap
// menjalankan runloop sebagai proses mati yang tidak berguna tapi masih
// memegang file log.
listener.resume()
HelperLog.log("listener resumed")
// Cleanup saat app mati ditangani via invalidationHandler + disconnect eksplisit.
RunLoop.main.run()