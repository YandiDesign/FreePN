import Foundation

/// Implementasi perintah whitelist helper.
/// SINGLETON (lihat main.swift): satu runner untuk semua koneksi XPC agar
/// startCore/coreStatus/stopCore melihat core yang SAMA.
final class HelperService: NSObject, FreePNHelperProtocol {
    static let shared = HelperService()
    private override init() { super.init() }

    private let runner = CoreRunner()
    private let spoofer = MacSpoofer()

    func version(reply: @escaping (String) -> Void) {
        HelperLog.log("version()")
        reply(Self.versionString)
    }

    /// Versi helper, SATU sumber kebenaran.
    ///
    /// Dibaca dari `AppConstants.helperVersion` (file yang sama dipakai app),
    /// BUKAN literal di sini: dua angka yang ditulis terpisah di dua tempat
    /// akan menyimpang diam-diam, dan_panel kesehatan akan menilai build yang
    /// salah sebagai "OK".
    ///
    /// D69: 1.4 karena D61 memindahkan log helper & core dari `/tmp` ke
    /// `/var/log`. Helper 1.3 yang sudah terpasang masih menulis ke `/tmp`,
    /// sementara app versi ini membaca `/var/log` — panel log berbunyi "tak
    /// terbaca" padahal log-nya ada. Reported 1.3 juga membuat pemeriksaan
    /// kesehatan menyatakan helper "OK", jadi mismatch-nya tak terlihat.
    static let versionString = "FreePNHelper \(AppConstants.helperVersion)"

    func startCore(configPath: String, reply: @escaping (Bool, String) -> Void) {
        HelperLog.log("startCore(\(configPath))")
        // Validasi path ketat via whitelist bersama (lihat Validators).
        guard Validators.isAllowedConfigPath(configPath) else {
            HelperLog.log("startCore: invalid path")
            reply(false, "invalid path"); return
        }
        let ok = runner.start(configPath: configPath)
        HelperLog.log("startCore: ok=\(ok) err=\(runner.lastError)")
        reply(ok, ok ? "started" : runner.lastError)
    }

    func stopCore(reply: @escaping (Bool, String) -> Void) {
        HelperLog.log("stopCore()")
        runner.stop()
        reply(true, "stopped")
    }

    func coreStatus(reply: @escaping (Bool, String) -> Void) {
        if runner.isRunning {
            // Log TETAP dikembalikan walau core masih hidup (D97).
            //
            // Sebelumnya baris log hanya dikirim kalau core sudah berhenti.
            // Padahal kasus yang paling perlu penjelasan justru core hidup
            // tapi tidak ada trafik keluar — dan itu justru kasus yang paling
            // sering, karena sing-box tidak pernah keluar dari sana.
            //
            // Dampaknya: saat itu app menampilkan pesan generik ("server
            // mungkin mati, kredensial mungkin salah") padahal sing-box sudah
            // menulis sebab persisnya di baris terakhir. User tidak punya cara
            // bertindak, jadi iaebak mencoba hal yang sama berulang kali.
            //
            // Nilai `Bool` tidak berubah, jadi semua pemanggil yang memakai
            // nilai kedua sebagai "tail" (hanya dibaca saat core mati) tetap
            // berperilaku sama.
            let tail = runner.logTail(8)
            HelperLog.log("coreStatus: running tail=\(tail.prefix(200))")
            reply(true, tail)
        } else {
            let tail = runner.logTail()
            HelperLog.log("coreStatus: stopped tail=\(tail.prefix(200))")
            reply(false, tail.isEmpty ? "stopped" : tail)
        }
    }

    func setMAC(interface iface: String, mac: String, reply: @escaping (Bool, String) -> Void) {
        HelperLog.log("setMAC(\(iface))")
        guard Validators.isValidInterface(iface), Validators.isValidMACFormat(mac) else {
            reply(false, "invalid input"); return
        }
        let ok = spoofer.set(iface: iface, mac: mac.lowercased())
        HelperLog.log("setMAC: ok=\(ok) err=\(spoofer.lastError)")
        reply(ok, ok ? "ok" : spoofer.lastError)
    }

    func restoreMAC(interface iface: String, reply: @escaping (Bool, String) -> Void) {
        guard Validators.isValidInterface(iface) else { reply(false, "invalid input"); return }
        // Restore = baca hardware? Pada praktiknya butuh MAC asli tersimpan;
        // di sini verifikasi ulang current setelah upaya restore via sistem.
        // Untuk keamanan, tolak bila tidak ada data asli (jangan tebak).
        reply(false, "restore requires original MAC")
    }

    func currentMAC(interface iface: String, reply: @escaping (String) -> Void) {
        reply(spoofer.current(of: iface) ?? "")
    }

    func handleDisconnect() {
        // Dipanggil saat koneksi XPC app terputus: JANGAN kill core otomatis
        // agar tidak memutus tunnel saat restart UI; cleanup eksplisit via stopCore
        // atau saat daemon berhenti. (Keputusan dicatat di DECISIONS.md.)
    }
}
