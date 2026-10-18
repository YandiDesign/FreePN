import Foundation
import Darwin

/// Konstanta global yang dipakai app + helper (Xcode 14 / Swift 5.8 compatible).
public enum AppConstants {
    /// Naikkan batas file descriptor (FD) proses ini sampai batas keras.
    ///
    /// App yang dijalankan dari Dock/Finder mewarisi `launchctl limit maxfiles`
    /// yang soft-nya cuma **256**. Ping All membuka banyak koneksi sekaligus —
    /// dulu ratusan koneksi TCP, sekarang puluhan slot uji internet — dan begitu
    /// batas soft terlampaui, permintaan gagal dan **node yang benar-benar
    /// hidup ikut ditandai mati**. Persis gejala "ping banyak server kok
    /// hasilnya dikit banget".
    ///
    /// Batas keras di macOS `unlimited`, jadi menaikkan soft limit sendiri
    /// selalu diperbolehkan dan tidak perlu root.
    ///
    /// Panggil sekali saat app launch. Mengembalikan true bila batas sudah
    /// cukup atau berhasil dinaikkan.
    @discardableResult
    public static func raiseFileDescriptorLimit() -> Bool {
        var current = rlimit()
        guard getrlimit(RLIMIT_NOFILE, &current) == 0 else { return false }
        if current.rlim_cur >= current.rlim_max { return true }
        current.rlim_cur = current.rlim_max
        return setrlimit(RLIMIT_NOFILE, &current) == 0
    }

    /// FD yang diperkirakan dibakar per slot uji internet yang hidup.
    ///
    /// Dipakai `CPUGovernor` untuk menjaga jumlah slot tetap di bawah batas FD
    /// — jaring pengaman kalau `raiseFileDescriptorLimit()` gagal (mis.
    /// environment yang mengunci hard limit).
    public static let fileDescriptorsPerTest = 2
    public static let appBundleID = "com.freepn.app"
    public static let helperBundleID = "com.freepn.helper"
    public static let helperMachService = "com.freepn.helper.xpc"
    public static let daemonPlistName = "com.freepn.helper.plist"
    public static let teamIDPlaceholder = "TEAMID"

    /// Versi helper yang DIHARAPKAN terpasang (D69).
    ///
    /// APP dan HELPER harus membaca angka yang sama — kalau tidak, pemeriksaan
    /// kesehatan diam-diam assessing build yang salah sebagai "OK". Jadi angka
    /// ini disalin ke `HelperService.versionString`; `HealthCheckTests`
    /// mengunci kedua sisi tetap sinkron lewat `stringify` yang sama.
    ///
    /// Naikkan ke 1.4 saat D61 memindahkan log dari `/tmp` ke `/var/log`.
    public static let helperVersion = "1.4"
    /// Versi helper yang masih dianggap bisa dipakai (tidak stale).
    public static let helperCompatibleVersions = ["1.3", "1.4"]

    public static let supportDirName = "FreePN"

    /// Repositori publik project ini.
    ///
    /// Satu konstanta supaya URL tidak ditulis ulang di beberapa tempat (kartu
    /// Tentang + kredit di sheet lisensi) dan tidak bisa melenceng jadi
    /// dua tautan yang berbeda.
    public static let projectURL = URL(string: "https://github.com/YandiDesign")!
    public static let projectURLString = "https://github.com/YandiDesign"
    public static let fetchTimeout: TimeInterval = 15
    public static let maxResponseBytes = 10 * 1024 * 1024
    public static let userAgent = "clash.meta"
    public static let clashAPIBase = "http://127.0.0.1:28909"
    /// Timeout SATU percobaan uji "benar-benar bisa internet" (D46: 6/5 dtk -> 4 dtk).
    ///
    /// D50: ini yang dipakai Ping All dan tombol Ping per baris, karena tidak
    /// ada lagi sweep TCP sebelumnya.
    ///
    /// D91: dinaikkan 4 -> 6 dtk. Seluruh rantai harus muat di sini: dial,
    /// handshake proxy, TLS (plus uTLS `chrome` untuk REALITY), baru request
    /// HTTP lewat tunnel. Empat detik terlalu sempit untuk handshake dingin
    /// Hysteria2/QUIC dan ws+TLS — dan node seperti itu langsung dapat vonis
    /// "tanpa internet" pada percobaan pertamanya, secara permanen.
    ///
    /// Angka ini TIDAK Sendiri yang diperbaiki: node yang gagal di sini masih
    /// dicoba sekali lagi dengan `internetCheckRetryTimeout` (lihat `InternetProbe.verify`).
    public static let internetCheckTimeout: TimeInterval = 6

    /// Budget untuk percobaan KEDUA, hanya untuk node yang gagal pada tahap
    /// pertama dengan alasan yang bisa berubah sendiri (timeout / jaringan / DNS).
    ///
    /// Tidak berlaku untuk kredensial atau config yang ditolak — tidak akan
    /// berubah dalam beberapa detik, jadi mengulang hanya membuang waktu.
    public static let internetCheckRetryTimeout: TimeInterval = 9

    /// Batas waktu SATU putaran Ping All dengan cek internet.
    ///
    /// D91: ini bukan sekadar angka, ini pengakuan bahwa operasi ini tidak
    /// bisa menyelesaikan semua node. Diukur di daftar milik user: 21.965 node,
    /// tiap sesi 600 outbound -> 37 sesi; tiap sesi punya spawn core, parse
    /// config 267 KB, dan probe ratusan node yang sebagian besar mati tapi
    /// tetap memakai timeout penuh. Totalnya jam-jaman — sehingga tidak pernah
    /// selesai, dan tabel Server menampilkan "—" untuk semua node karena
    /// pengurutan baru terjadi setelah SELURUH putaran beres.
    ///
    /// Jadi sekarang ada plafon. Setelah habis, pengujian berhenti bersih,
    /// sisa node dilepas sebagai **belum teruji** (bukan mati), dan UI
    /// memberi tahu berapa yang sempat diuji. Hasil yang sudah didapat tetap
    /// disimpan dan tetap ditampilkan.
    ///
    /// Ingin cakupan penuh untuk sekumpulan kecil? Saring dulu (sumber, tipe,
    /// atau pencarian) lalu Ping All — sasaran ikut mengikuti filter.
    public static let pingInternetBudget: TimeInterval = 300

    /// Timeout satu ping "biasa" (TCP handshake) — saat Setting "Ping cepat"
    /// aktif. Jauh lebih pendek dari `internetCheckTimeout`: yang diuji hanya
    /// apakah server menerima koneksi, bukan apakah ia bisa menjangkau internet.
    public static let serverPingTimeout: TimeInterval = 3
    /// Timeout probe UDP untuk Hysteria2. Sengaja lebih pendek dari TCP:
    /// hasil timeout di sini diartikan "tidak ada bukti kematian" (lihat
    /// `ServerPinger.udpProbe`), jadi menunggu lebih lama hanya menambah
    /// tertundanya hasil tanpa membuat verdict lebih akurat.
    public static let serverPingUDPTimeout: TimeInterval = 1.5
    /// Batas atas yang ditampilkan untuk hasil UDP — bukan RTT.
    public static let serverPingUDPTimeoutMs = 1500
}
