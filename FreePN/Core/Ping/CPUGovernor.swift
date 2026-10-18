import Foundation
import Darwin

/// Pembacaan beban CPU mesin.
///
/// Kenapa perlu: konkurensi tetap (mis. 128 koneksi TCP + 10 uji delay) memaksa
/// semua mesin kerja sama keras. Di Mac lama itu bikin CPU 100% dan app ter Freeze,
/// di Mac baru masih longgar. Di sini beban CPU diukur sungguhan lalu jumlah
/// kerja paralel menyesuaikan — mesin lebih kuat = lebih banyak pekerjaan.
public enum CPUMeter {
    /// Jumlah core yang terlihat (P + E).
    public static var totalCores: Int { ProcessInfo.processInfo.activeProcessorCount }

    /// Core performa. Di Apple Silicon hanya P-core yang dipakai untuk crypto/TCP
    /// berat (E-core dibangun untuk efisiensi), jadi dihitung terpisah.
    public static var performanceCores: Int {
        var count: Int = 0
        var size = MemoryLayout<Int>.size
        if sysctlbyname("hw.perflevel0.physicalcpu", &count, &size, nil, 0) == 0, count > 0 {
            return count
        }
        return totalCores   // Intel / tanpa perflevel: semua core diperlakukan sama
    }

    /// Tick kumulatif CPU (user, system, idle, nice). Beban = 1 - idle.
    private static func ticks() -> (total: Double, idle: Double)? {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let kr = withUnsafeMutablePointer(to: &info) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, rebound, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        let t = Double(info.cpu_ticks.0) + Double(info.cpu_ticks.1)
            + Double(info.cpu_ticks.2) + Double(info.cpu_ticks.3)
        return (t, Double(info.cpu_ticks.2))
    }

    /// Beban CPU sistem (0...1) sejak panggilan sebelumnya. `nil` bila belum
    /// ada sampel pembanding atau host_statistics gagal.
    private static var lastSample: (total: Double, idle: Double)?

    public static func load() -> Double? {
        guard let now = ticks() else { return nil }
        defer { lastSample = now }
        guard let prev = lastSample, now.total > prev.total else { return nil }
        let totalDelta = now.total - prev.total
        let idleDelta = now.idle - prev.idle
        guard totalDelta > 0 else { return nil }
        return max(0, min(1, 1 - idleDelta / totalDelta))
    }
}

/// Aturan penentukan jumlah kerja paralel dari lisensi CPU.
///
/// D45: TIDAK ADA plafon keras lagi. Dulu `maxSockets = 256`/`maxCompute = 48`
/// muncul sebagai "pengaman", padahal justru membuat angka di Settings tidak
/// sesuai kenyataan di mesin besar. Sekarang jatah murni =
/// `jumlah core × jatah per core × porsi CPU`, dan pembatasnya adalah AIMD di
/// bawah (bacaan `host_statistics` sungguhan): mesin yang kuat naik sendiri,
/// mesin yang sedang sibuk turun sendiri. Tidak ada angka tebakan.
///
/// D50: tidak ada lagi jatah "socket TCP". Sweep TCP dihapus karena tahap itu
/// tidak pernah dipakai untuk memutuskan apa pun (lihat `PingResult`) — ia
/// cuma mempersempit siapa yang perlu diuji tahap berikutnya, jadi setiap node
/// diproses dua kali. Satu-satunya kerja paralel yang tersisa adalah uji
/// internet lewat core sing-box, jadi hanya `computeLimit` yang perlu diatur.
public enum CPUGovernor {
    /// Lantai safety: minimal 2 slot uji supaya operasi tetap jalan di mesin
    /// yang sangat kecil atau saat pembacaan CPU gagal.
    public static let minCompute = 2

    /// Slot untuk uji internet lewat core (TLS + enkripsi proxy + HTTP).
    /// 8 core & share 50% -> 32 slot uji (D46: 2 -> 4 per core).
    ///
    /// D46: pengukuran di feed 16k node menunjukkan uji internet adalah
    /// bottleneck Ping All, karena tiap slot memaksa sing-box melakukan TLS +
    /// handshake proxy. Angka per inti dinaikkan karena governor membaca
    /// `host_statistics` dan turun sendiri saat mesin benar-benar sibuk.
    ///
    /// D50: ini sekarang praktis SATU-SATUNYA angka konkurensi aplikasi, jadi
    /// Settings "Performance" mengatur seluruh beban — tidak ada lagi jatah
    /// kedua yang diam-diam mengambil sebagian angka.
    public static func computeLimit(cores: Int, share: Double) -> Int {
        let raw = Double(max(1, cores)) * 4 * (share / 0.5)
        return max(minCompute, min(fdSafeLimit(), Int(raw)))
    }

    /// Batas kerja paralel yang tidak akan melewati batas FD proses.
    ///
    /// Normally `rlim_cur` sudah dinaikkan ke batas keras (lihat
    /// `raiseFileDescriptorLimit`), jadi ini hanya jaring pengaman: kalau
    /// panggilan itu gagal, jumlah slot dipotong supaya permintaan uji tidak
    /// gagal dan menandai node yang sebenarnya hidup sebagai mati (D49).
    private static func fdSafeLimit() -> Int {
        var lim = rlimit()
        guard getrlimit(RLIMIT_NOFILE, &lim) == 0, lim.rlim_cur > 0 else { return minCompute }
        let headroom = 32   // FD milik app sendiri (UI, berkas, log)
        // `RLIM_INFINITY` adalah ((1<<63)-1). `Int(...)` dari nilai itu sendiri
        // kebetulan muat di 64-bit, TAPI `raiseFileDescriptorLimit` menetapkan
        // soft limit = hard limit, dan beberapa environment punya hard limit
        // yang lebih besar dari `Int.max` — konversi itu lalu TRAP
        // (arithmetic overflow) dan app langsung mati saat Settings dibuka.
        // Batasi dulu ke rentang `Int` yang aman (D61).
        let ceiling = UInt64(Int.max)
        let current = min(lim.rlim_cur, ceiling)
        let budget = max(Int64(minCompute), Int64(current) - Int64(headroom))
        return max(minCompute, Int(budget) / max(1, AppConstants.fileDescriptorsPerTest))
    }

    /// Konkurensi untuk langkah berikutnya (AIMD sederhana: naik pelan saat
    ///sezi masih adem, turun cepat saat mesin sibuk).
    ///
    /// `load` = beban CPU sistem 0...1, `share` = jatah yang boleh dipakai
    /// FreePN (0.5 = pakai maksimal setengah CPU).
    public static func nextLimit(current: Int, load: Double, share: Double,
                                 min lowerBound: Int = 1, max upperBound: Int) -> Int {
        let ceiling = max(lowerBound, upperBound)
        let now = min(ceiling, max(lowerBound, current))
        let target = max(0.05, min(1, share))

        let next: Int
        if load <= target * 0.5 {
            next = now + max(1, now / 4)              // adem -> naik 25%
        } else if load <= target {
            next = now                                // di dalam jatah -> tahan
        } else if load <= target * 1.5 {
            next = now - max(1, now / 8)              // sedikit lebih -> turun pelan
        } else {
            next = max(lowerBound, now / 2)           // jenuh -> turun cepat
        }
        return min(ceiling, max(lowerBound, next))
    }
}

/// Supervisor: mengukur beban CPU berkala dan menyimpan jatah konkurensi yang
/// sedang berlaku. `refreshIfNeeded()` dipanggil probe tiap kali mengisi
/// slot uji; internally di-throttle supaya tidak membanjiri `host_statistics`.
@MainActor
public final class CPUGovernorMonitor: ObservableObject {
    /// Beban CPU terakhir (0...1).
    @Published public private(set) var load: Double = 0
    /// Jatah uji internet yang boleh aktif sekarang.
    @Published public private(set) var computeLimit: Int = 8

    /// Porsi CPU yang boleh dipakai FreePN (0.25 / 0.5 / 0.75 / 1.0).
    public var share: Double = 0.5
    /// Kalau mati, konkurensi tetap (tanpa pengukuran).
    public var isAdaptive: Bool = true
    /// Jatah maksimum dari formula core × porsi CPU. AIMD bergerak di bawah
    /// angka ini; tidak ada plafon tambahan dari mana pun.
    public var computeCeiling: Int = CPUGovernor.minCompute

    private var timer: Timer?
    private var lastRefresh = Date.distantPast

    public init() { recalculateCeilings() }

    /// Hitung ulang batas atas (dipanggil saat pengaturan berubah).
    public func recalculateCeilings() {
        let cores = CPUMeter.performanceCores
        computeCeiling = CPUGovernor.computeLimit(cores: cores, share: share)
        // Batas atas turun harus langsung berlaku, naik boleh bertahap.
        computeLimit = min(computeLimit, computeCeiling)
    }

    public func start() {
        stop()
        guard isAdaptive else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            // Timer tidak berjalan di actor utama; lompat eksplisit ke
            // MainActor. `self` diambil ke konstanta dulu supaya tidak
            // menangkap `var self` di closure yang konkuren.
            let s = self
            Task { @MainActor in s?.refreshIfNeeded(force: true) }
        }
        // `.common`: timer `.default` dijeda saat window di-drag / menu
        // diblacak — governor ikut berhenti menyesuaikan tepat saat user
        // sedang membebani mesin (D61).
        if let t = timer { RunLoop.main.add(t, forMode: .common) }
        refreshIfNeeded(force: true)
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Ambil beban CPU + sesuaikan jatah. Dipanggil sering (tiap refill slot),
    /// jadi kerja nyata dibatasi maksimal sekali per 400 ms.
    public func refreshIfNeeded(force: Bool = false, minInterval: TimeInterval = 0.4) {
        if !isAdaptive {
            computeLimit = computeCeiling
            return
        }
        let now = Date()
        guard force || now.timeIntervalSince(lastRefresh) >= minInterval else { return }
        lastRefresh = now
        if let l = CPUMeter.load() { load = l }
        computeLimit = CPUGovernor.nextLimit(current: computeLimit, load: load,
                                              share: share, max: computeCeiling)
    }
}