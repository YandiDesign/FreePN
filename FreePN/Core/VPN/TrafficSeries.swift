import Foundation

/// Satu sampel laju: waktu (detik sejak epoch) + nilai (byte/detik).
public struct TrafficSample: Equatable {
    public var time: TimeInterval
    public var value: Double
}

/// Riwayat laju trafik untuk sparkline, sebagai **circular buffer berkapasitas
/// tetap**.
///
/// KENAPA BUKAN `[Double]` biasa (D76):
///  - `append` + `removeFirst` pada Array adalah O(n) **dan** menggeser seluruh
///    buffer — tiap sampel baru menyalin puluhan elemen. Pada 60 fps dengan
///    jendela bergeser, ini jadi alokasi berulang yang persis yang harus
///    dihindari.
///  - Riwayat lama tidak pernah dibutuhkan lagi begitu keluar dari jendela.
///    Circular buffer menyimpan hanya `capacity` sampel terbaru dan menimpa
///    yang tertua — O(1), tanpa alokasi setelah inisialisasi.
///
/// Struktur backing di-alokasi SEKALI pada `init` dan tidak pernah berubah
/// ukurannya, jadi setelah stabil tidak ada alokasi per sampel sama sekali.
///
/// INI ADALAH CLASS, bukan struct, karena diedit in-place pada frame 60 Hz.
/// Kalau struct, setiap mutasi berarti salinan dan seluruh view yang
/// mengamatinya harus digambar ulang karena "nilai berubah".
public final class TrafficSeries {
    /// Kapasitas tetap. Dipilih 128: cukup untuk jendela 60 detik pada 1 Hz
    /// (lihat `Sparkline.window`), dengan sisa untuk menanggung core yang
    /// sempat lambat. Kapasitas lebih besar hanya menambah memori tanpa
    /// menambah informasi.
    public static let defaultCapacity = 128

    private var times: [TimeInterval]
    private var values: [Double]
    /// Indeks tulis berikutnya. Buffer penuh -> menimpa yang tertua.
    private var head: Int = 0
    private var filled: Int = 0

    public let capacity: Int

    public init(capacity: Int = TrafficSeries.defaultCapacity) {
        self.capacity = max(2, capacity)
        self.times = [Double](repeating: 0, count: self.capacity)
        self.values = [Double](repeating: 0, count: self.capacity)
    }

    /// Jumlah sampel yang tersimpan (<= capacity).
    public var count: Int { filled }

    public var isEmpty: Bool { filled == 0 }

    /// Masukkan sampel baru. Menimpa sampel tertua bila buffer penuh.
    ///
    /// O(1) dan tanpa alokasi. Sampel dengan waktu yang tidak maju (jarang,
    /// hanya bila dua pesan datang dalam milidetik yang sama) diabaikan —
    /// interpolation meng.Require urutan waktu yang menaik.
    public func append(time: TimeInterval, value: Double) {
        guard filled == 0 || time > times[(head - 1 + capacity) % capacity] else { return }
        times[head] = time
        values[head] = value
        head = (head + 1) % capacity
        if filled < capacity { filled += 1 }
    }

    /// Indeks logis 0 = sampel terlama yang masih tersimpan.
    private func physical(_ logical: Int) -> Int {
        (head - filled + logical + capacity) % capacity
    }

    public func time(at logical: Int) -> TimeInterval {
        guard logical >= 0, logical < filled else { return 0 }
        return times[physical(logical)]
    }

    public func value(at logical: Int) -> Double {
        guard logical >= 0, logical < filled else { return 0 }
        return values[physical(logical)]
    }

    public var latestTime: TimeInterval {
        filled == 0 ? 0 : time(at: filled - 1)
    }
    public var latestValue: Double {
        filled == 0 ? 0 : value(at: filled - 1)
    }

    /// Nilai pada waktu tertentu, diinterpolasi linear antar dua sampel.
    ///
    /// Penting untuk grafik: pada 1 Hz, sebagian besar frame jatuh DI ANTARA
    /// dua sampel. Tanpa interpolasi, garis hanya bisa digambar pada titik
    /// diskret dan akan terlihat "loncat-loncat".
    ///
    /// Di luar rentang sampel: nilai di luar TIDAK diekstrapolasi — sebelum
    /// sampel pertama dipakai nilai pertama, sesudah sampel terakhir dipakai
    /// nilai terakhir. Mengekstrapolasi berarti menampilkan laju yang tidak
    /// pernah terukur.
    public func interpolatedValue(at time: TimeInterval) -> Double {
        guard filled > 0 else { return 0 }
        guard filled > 1 else { return values[physical(0)] }

        let first = times[physical(0)]
        if time <= first { return values[physical(0)] }

        for i in 1..<filled {
            let t0 = times[physical(i - 1)]
            let t1 = times[physical(i)]
            if time <= t1 {
                let span = t1 - t0
                guard span > 0 else { return values[physical(i)] }
                let f = (time - t0) / span
                return values[physical(i - 1)] + (values[physical(i)] - values[physical(i - 1)]) * f
            }
        }
        return values[physical(filled - 1)]
    }

    /// Indeks logis pertama dengan waktu >= `time`, atau `filled` kalau
    /// tidak ada. Dipakai grafik untuk menggambar hanya bagian yang terlihat.
    public func firstIndex(atOrAfter time: TimeInterval) -> Int {
        guard filled > 0 else { return 0 }
        var lo = 0, hi = filled
        while lo < hi {
            let mid = (lo + hi) / 2
            if times[physical(mid)] < time { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    /// Puncak nilai dalam rentang waktu tertentu.
    ///
    /// Dipakai normalisasi tinggi grafik. Hanya menghitung rentang yang
    /// terlihat supaya puncak tidak dipengaruhi data lama yang sudah keluar
    /// jendela.
    public func peak(from startIndex: Int) -> Double {
        guard startIndex < filled else { return 0 }
        var m = 0.0
        for i in startIndex..<filled {
            let v = values[physical(i)]
            if v > m { m = v }
        }
        return m
    }

    /// Kosongkan (saat sesi baru dimulai).
    public func reset() {
        head = 0
        filled = 0
    }
}

/// Skala Y dengan **peak-hold di ruang LOGARITMA**: naik seketika, turun
/// perlahan.
///
/// Kenapa perlu (D79): sebelumnya `points()` menghitung ulang puncak dari
/// jendela bergeser **di setiap frame**. Jendela itu bergeser tiap detik,
/// jadi begitu satu sampel lama keluar dari layar, puncaknya berubah mendadak
/// dan SELURUH garis melompat vertikal dalam satu frame. Itulah yang bikin
/// kurva terlihat "tidak stabil" — bukan karena datanya salah, tapi karena
/// skalanya ikut berdenyut tiap detik.
///
/// Kenapa LOGARITMA (D80): trafik nyata melintasi **4 dekade** (idle ~8 KiB/s
/// sampai burst speed test ~100 MiB/s). Di sumbu linear, begitu ada satu
/// burst besar, semua trafik normal berikutnya tergambar gepeng di dasar —
/// persis laporan "curve jadi error".
///
/// Yang menentukan: pelepasan eksponensial di ruang linear butuh ~28
/// half-life untuk turun dari 100 MiB ke 8 KiB. Half-life yang masuk akal
/// pun tidak bisa menutup rentang itu. Di ruang log, jarak dari burst ke
/// trafik normal hanya ~4 "langkah", jadi pelepasan yang halus menutupnya
/// dalam hitungan detik.
///
/// Pelepasan dihitung dari **waktu**, bukan jumlah frame: kalau per frame,
/// hasilnya berbeda di 60 Hz dan 120 Hz, dan jadi tidak deterministik.
final class TrafficYScale {
    /// Half-life pelepasan, dalam detik.
    static let releaseHalfLife: TimeInterval = 2

    /// Luas rentsang yang ditampilkan grafik, dalam **dekade**.
    ///
    /// 3 dekade = rentang 1000x (misal 10 KiB/s sampai 10 MiB/s). Cukup
    /// untuk melihat bentuk kedua arah sekaligus, dan cukup sempit sehingga
    /// nilai di bawahnya tidak terlalu cepat menempel di dasar.
    static let decades: Double = 3

    /// Puncak dalam bentuk linear.
    var peak: Double { pow(10, logPeak) }

    /// Puncak sebenarnya disimpan sebagai `log10`. Inilah inti D80.
    private var logPeak: Double = 0
    private var lastUpdate: TimeInterval?

    /// Kembalikan **puncak** (linear) yang harus dipakai untuk frame ini.
    @discardableResult
    func update(observed: Double, now: TimeInterval) -> Double {
        let target = log10(max(observed, 1))

        if let last = lastUpdate {
            // Dijepit max 1 detik: kalau tab sempat tidak aktif lalu kembali,
            // elapsed bisa jauh lebih besar dan lompatan penskalaan setelahnya
            // akan terasa seperti glitch.
            let dt = min(max(now - last, 0), 1)
            if target >= logPeak {
                logPeak = target              // attack: seketika
            } else {
                let kept = logPeak * pow(0.5, dt / Self.releaseHalfLife)
                logPeak = max(target, kept)   // release: pelan
            }
        } else {
            logPeak = target                  // frame pertama
        }

        lastUpdate = now
        return pow(10, logPeak)
    }

    /// Dipanggil saat sesi direset, supaya grafik tidak mewarisi skala lama.
    func reset() {
        logPeak = 0
        lastUpdate = nil
    }
}
