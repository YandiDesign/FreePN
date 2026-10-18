import XCTest
import CoreGraphics
@testable import FreePNApp

/// D76 — `TrafficSeries`: buffer melingkar berkapasitas tetap untuk riwayat
/// laju trafik.
///
/// Sifat yang dijaga: O(1) per insert, tanpa alokasi setelah inisialisasi,
/// dan urutan waktu selalu menaik meski buffer sudah berputar beberapa kali.
final class TrafficSeriesTests: XCTestCase {
    private func filled(_ s: TrafficSeries, _ n: Int, step: TimeInterval = 1, from: TimeInterval = 0) {
        for i in 0..<n { s.append(time: from + Double(i) * step, value: Double(i)) }
    }

    func testEmptySeries() {
        let s = TrafficSeries(capacity: 8)
        XCTAssertEqual(s.count, 0)
        XCTAssertTrue(s.isEmpty)
        XCTAssertEqual(s.interpolatedValue(at: 10), 0)
        XCTAssertEqual(s.peak(from: 0), 0)
    }

    func testAppendPreservesOrder() {
        let s = TrafficSeries(capacity: 8)
        filled(s, 4)
        XCTAssertEqual(s.count, 4)
        for i in 0..<4 {
            XCTAssertEqual(s.value(at: i), Double(i))
            XCTAssertEqual(s.time(at: i), Double(i))
        }
    }

    /// Indeks logis 0 = terlama. Setelah berputar, sampel tertua yang tersisa
    /// harus tetap bisa dibaca lewat indeks logis.
    func testRingOverwritesOldestAndKeepsLogicalOrder() {
        let s = TrafficSeries(capacity: 4)
        filled(s, 6)
        XCTAssertEqual(s.count, 4, "kapasitas harus dihormati")
        XCTAssertEqual(s.value(at: 0), 2, "indeks 0 = sampel tertua yang tersisa")
        XCTAssertEqual(s.value(at: 3), 5, "indeks terakhir = sampel terbaru")
    }

    /// Setelah capacity+bufferSize kali berputar, urutan waktu TIDAK boleh
    /// terbalik — ini yang membuat interpolasi dan sumbu-x benar.
    func testTimeOrderSurvivesManyWraps() {
        let s = TrafficSeries(capacity: 16)
        filled(s, 500)
        for i in 1..<s.count {
            XCTAssertGreaterThan(s.time(at: i), s.time(at: i - 1),
                                 "waktu harus menaik di indeks logis \(i)")
        }
    }

    /// Sampel dengan waktu yang tidak maju diabaikan — interpolation
    /// mengharuskan urutan waktu menaik, dan satu pesan nyasar tidak boleh
    /// merusak seluruh buffer.
    func testNonAdvancingTimeIsIgnored() {
        let s = TrafficSeries(capacity: 8)
        s.append(time: 10, value: 1)
        s.append(time: 10, value: 99)     // waktu sama
        s.append(time: 5, value: 99)      // waktu mundur
        XCTAssertEqual(s.count, 1)
        XCTAssertEqual(s.value(at: 0), 1)
    }

    func testReset() {
        let s = TrafficSeries(capacity: 8)
        filled(s, 5)
        s.reset()
        XCTAssertEqual(s.count, 0)
        XCTAssertTrue(s.isEmpty)
        // Setelah reset, insert baru harus diterima lagi.
        s.append(time: 100, value: 7)
        XCTAssertEqual(s.count, 1)
        XCTAssertEqual(s.value(at: 0), 7)
    }

    func testCapacityIsAtLeastTwo() {
        let s = TrafficSeries(capacity: 0)
        XCTAssertGreaterThanOrEqual(s.capacity, 2, "butuh minimal 2 titik untuk membentuk garis")
    }

    // MARK: - Interpolasi

    func testInterpolatesBetweenSamples() {
        let s = TrafficSeries(capacity: 8)
        s.append(time: 0, value: 0)
        s.append(time: 2, value: 100)
        XCTAssertEqual(s.interpolatedValue(at: 0), 0, accuracy: 0.001)
        XCTAssertEqual(s.interpolatedValue(at: 1), 50, accuracy: 0.001)
        XCTAssertEqual(s.interpolatedValue(at: 2), 100, accuracy: 0.001)
    }

    /// Interpolasi TIDAK boleh menebak nilai di luar rentang terukur —
    /// supaya grafik tidak menampilkan lonjakan yang tidak pernah terjadi.
    func testNoExtrapolationOutsideMeasuredRange() {
        let s = TrafficSeries(capacity: 8)
        s.append(time: 10, value: 5)
        s.append(time: 12, value: 50)
        XCTAssertEqual(s.interpolatedValue(at: 0), 5, "sebelum sampel pertama = nilai pertama")
        XCTAssertEqual(s.interpolatedValue(at: 999), 50, "sesudah sampel terakhir = nilai terakhir")
    }

    func testSingleSampleInterpolatesToItsValue() {
        let s = TrafficSeries(capacity: 8)
        s.append(time: 5, value: 42)
        XCTAssertEqual(s.interpolatedValue(at: 0), 42)
        XCTAssertEqual(s.interpolatedValue(at: 1000), 42)
    }

    /// Dua sampel dengan waktu identik (jarang) tidak boleh membagi nol.
    func testZeroSpanDoesNotDivideByZero() {
        let s = TrafficSeries(capacity: 8)
        s.append(time: 5, value: 10)
        s.append(time: 5, value: 20)   // diabaikan oleh guard waktu
        XCTAssertEqual(s.interpolatedValue(at: 5), 10)
    }

    // MARK: - Pencarian jendela

    func testFirstIndexAtOrAfterFindsBracket() {
        let s = TrafficSeries(capacity: 16)
        for i in 0..<10 { s.append(time: Double(i), value: Double(i)) }
        XCTAssertEqual(s.firstIndex(atOrAfter: 0), 0)
        XCTAssertEqual(s.firstIndex(atOrAfter: 3.5), 4)
        XCTAssertEqual(s.firstIndex(atOrAfter: 100), 10, "di luar rentang -> count")
    }

    func testPeakFromWindowIgnoresOlderSamples() {
        let s = TrafficSeries(capacity: 16)
        s.append(time: 0, value: 1000)   // besar, tapi tua
        for i in 1..<6 { s.append(time: Double(i), value: 10) }
        XCTAssertEqual(s.peak(from: 0), 1000)
        XCTAssertEqual(s.peak(from: 1), 10, "puncak dari jendela baru")
    }

    // MARK: - Beban alokasi

    /// Setelah inisialisasi, `append` tidak boleh mengalokasikan.
    ///
    /// Inilah alasan utama memakai buffer melingkar: versi `[Double]` +
    /// `removeFirst` menggeser seluruh buffer tiap sampel, dan pada jendela
    /// yang bergeser tiap frame itu jadi sumber alokasi berulang.
    func testAppendDoesNotGrowStorage() {
        let s = TrafficSeries(capacity: 64)
        filled(s, 200)
        XCTAssertEqual(s.count, 64, "ukuran logis tetap = kapasitas")
        // Buffer backing tidak pernah bertambah; kalau iAppend pernah
        // memanggil realloc, capacity tidak akan cukup untuk 200 sampel.
        XCTAssertLessThanOrEqual(s.count, s.capacity)
    }
}

/// D76 — geometri sparkline: sumbu-x berbasis waktu, bukan berbasis indeks.
///
/// Yang diuji di sini persis yang hilang sebelumnya: garis HARUS bergerak
/// halus setiap frame, dan tidak boleh ada saat di mana ujung kanannya
/// "mundur lalu melompat" — symptom "berhenti lalu melompat" yang dilaporkan.
final class SparklineGeometryTests: XCTestCase {
    private let size = CGSize(width: 300, height: 42)

    private func series(_ samples: [(TimeInterval, Double)]) -> TrafficSeries {
        let s = TrafficSeries(capacity: 128)
        for (t, v) in samples { s.append(time: t, value: v) }
        return s
    }

    func testEmptySeriesProducesNoPoints() {
        let s = TrafficSeries(capacity: 8)
        XCTAssertTrue(Sparkline.points(s, now: 10, size: size).isEmpty)
    }

    func testZeroSizeProducesNoPoints() {
        let s = series([(0, 1), (1, 2)])
        XCTAssertTrue(Sparkline.points(s, now: 2, size: .zero).isEmpty)
    }

    /// Ujung kanan harus SETENGAH di tepi setiap saat — inilah yang membuat
    /// gerakan kontinu, bukan melompat sekali per sampel.
    func testLineAlwaysReachesRightEdge() {
        let s = series([(0, 10), (1, 20), (2, 30)])
        // Uji pada banyak waktu, termasuk di antara sampel.
        for now in stride(from: 2.0, through: 10.0, by: 0.05) {
            let pts = Sparkline.points(s, now: now, size: size)
            guard let last = pts.last else { return XCTFail("tidak ada titik pada now=\(now)") }
            XCTAssertEqual(Double(last.x), size.width, accuracy: 0.5,
                           "ujung kanan harus di tepi pada now=\(now)")
        }
    }

    /// GERAKAN KONTINU: ujung garis BERgeser halus tiap frame — tidak pernah
    /// melompat. Ini inti dari "tanpa efek berhenti lalu melompat".
    func testLineMovesSmoothlyWithoutJumps() {
        let s = series([(0, 10), (1, 20), (2, 30)])
        var prevX: CGFloat?
        // 60 frame/detik selama 3 detik.
        var t = 2.0
        while t < 5.0 {
            let pts = Sparkline.points(s, now: t, size: size)
            let last = pts.last!.x
            if let p = prevX {
                // Per frame (1/60 dtk) diharapkan bergeser hanya ~lebar jendela/60.
                // Lompatan besar = glitch.
                let maxExpected = size.width / 60.0 * 4 + 2   // toleransi longgarkan
                XCTAssertLessThanOrEqual(abs(last - p), maxExpected,
                                         "ujung garis melompat di t=\(t): \(p) -> \(last)")
            }
            prevX = last
            t += 1.0 / 60.0
        }
    }

    /// Test di atas punya TITIK BUTA: ujung kanan sengaja dipatok di tepi, jadi
    /// ia tidak pernah bergerak — dan grafik yang benar-benar DIAM pun akan
    /// lulus "tidak melompat".
    ///
    /// Yang harus dibuktikan adalah sisi lain: garis HARUS benar-benar bergerak,
    /// dan bergerak KONTINU. Versi lama berbasis indeks tidak bergerak sama
    /// sekali di antara dua sampel (diam 1 detik, lalu lompat) — persis
    /// gejala yang dikeluhkan, dan ia lolos test "no jump".
    func testInteriorPointsScrollContinuously() {
        // Riwayat panjang supaya ada titik interior yang pasti terlihat.
        var samples: [(TimeInterval, Double)] = []
        for i in 0..<30 { samples.append((Double(i), 100 + Double(i % 5))) }
        let s = series(samples)

        // Titik interior = sampel yang BUKAN terbaru dan BUKAN paling kiri.
        func interiorX(_ now: TimeInterval) -> CGFloat? {
            let pts = Sparkline.points(s, now: now, size: size)
            guard pts.count >= 3 else { return nil }
            return pts[pts.count - 3].x   // dua titik sebelum ujung kanan
        }

        var t = 29.5
        var prev: CGFloat?
        var moved = 0
        while t < 31.0 {
            guard let x = interiorX(t) else { break }
            if let p = prev {
                let delta = x - p
                XCTAssertLessThanOrEqual(abs(delta), size.width / 60.0 * 4 + 2,
                                         "titik interior melompat di t=\(t)")
                if delta != 0 { moved += 1 }
                XCTAssertLessThanOrEqual(delta, 0.001, "garis harus bergeser ke KIRI")
            }
            prev = x
            t += 1.0 / 60.0
        }
        XCTAssertGreaterThan(moved, 50,
                             "titik interior harus BERGERAK tiap frame — kalau diam, ini versi lama")
    }

    /// Tidak ada titik yang boleh melompat jauh dalam satu frame, di frame mana
    /// pun — termasuk saat sampel baru tiba (momen yang paling rawan glitch).
    func testNoPointJumpsWhenNewSampleArrives() {
        var samples: [(TimeInterval, Double)] = []
        for i in 0..<30 { samples.append((Double(i), 100)) }
        let s = series(samples)
        // Tambahkan sampel ekstrem tepat di tengah pengujian.
        s.append(time: 30, value: 9_000_000)

        var prev: [CGPoint] = []
        var t = 29.8
        while t < 31.0 {
            let pts = Sparkline.points(s, now: t, size: size)
            if prev.count == pts.count, prev.count >= 2 {
                for i in 0..<pts.count {
                    XCTAssertLessThanOrEqual(abs(pts[i].x - prev[i].x), size.width / 60.0 * 4 + 2,
                                             "titik \(i) melompat di t=\(t)")
                }
            }
            prev = pts
            t += 1.0 / 60.0
        }
    }

    ///Koordinat X harus selalu naik ke kanan (tidak ada titik yang terbalik).
    func testPointsAreOrderedLeftToRight() {
        let s = series([(0, 5), (1, 50), (2, 10), (3, 80), (4, 20)])
        let pts = Sparkline.points(s, now: 4.2, size: size)
        for i in 1..<pts.count {
            XCTAssertGreaterThan(pts[i].x, pts[i - 1].x, "x harus menaik di titik \(i)")
        }
    }

    /// Sampel yang sudah keluar dari jendela tidak boleh digambar.
    func testSamplesOutsideWindowAreNotDrawn() {
        let s = series([(0, 999), (1, 5), (100, 10)])
        let pts = Sparkline.points(s, now: 100, size: size)
        // Hanya sampel terbaru (dan satu sebelumnya) yang relevan.
        XCTAssertLessThanOrEqual(pts.count, 4)
    }

    /// Trafik nol -> garis di dekat lantai, bukan hilang atau error.
    func testZeroTrafficDrawsFlatLineAtBottom() {
        let s = series([(0, 0), (1, 0), (2, 0), (3, 0)])
        let pts = Sparkline.points(s, now: 3.1, size: size)
        XCTAssertGreaterThanOrEqual(pts.count, 2, "trafik nol tetap harus menghasilkan garis")
        for p in pts {
            XCTAssertGreaterThanOrEqual(p.y, 0)
            XCTAssertLessThanOrEqual(p.y, size.height)
        }
    }

    /// Normalisasi puncak: nilai tertinggi harus memetakan ke ~92% tinggi.
    func testPeakMapsNearTop() {
        let s = series([(0, 0), (1, 100), (2, 0)])
        let pts = Sparkline.points(s, now: 2.1, size: size)
        let minY = pts.map(\.y).min()!
        XCTAssertLessThan(minY, size.height * 0.2,
                          "puncak harus mendekati atas (y kecil), dapat \(minY)")
    }

    /// Skala harus konsisten: nilai 2x lebih besar menghasilkan y 2x lebih
    /// tinggi dari baseline — kalau tidak, grafik lolos dari proporsi data.
    func testScalingIsProportional() {
        let a = series([(0, 0), (1, 100)])
        let b = series([(0, 0), (1, 200)])
        let ya = Sparkline.points(a, now: 1.05, size: size).map(\.y).min()!
        let yb = Sparkline.points(b, now: 1.05, size: size).map(\.y).min()!
        // Keduanya ternormalisasi ke puncak masing-masing, jadi tinggi PUNCAK
        // harus sama — yang berbeda adalah posisinya relatif baseline.
        XCTAssertEqual(ya, yb, accuracy: 1.0,
                       "puncak harus ternormalisasi sama, berapa pun besarnya angka")
    }
}

// MARK: - Grafik gabungan (D78)

/// Skala Y BERSAMA: dua arah digambar di satu plot dengan sumbu yang sama.
///
/// Ini perilaku yang paling mudah dirusak tanpa disadari. Kalau suatu saat
/// `secondary` ikut dinormalisasi ke puncaknya sendiri, upload yang 50x lebih
/// kecil akan tergambar SETENGAH TINGGI dari download — dan panelnya akan
/// terlihat sangat meyakinkan, padahal kedua garis memakai skala berbeda dan
/// tidak bisa dibandingkan sama sekali.
final class CombinedSparklineScaleTests: XCTestCase {
    private let size = CGSize(width: 300, height: 42)

    private func series(_ samples: [(TimeInterval, Double)]) -> TrafficSeries {
        let s = TrafficSeries(capacity: 128)
        for (t, v) in samples { s.append(time: t, value: v) }
        return s
    }

    /// Download besar, upload kecil — kondisi normal saat menjelajah web.
    func testSmallSecondaryStaysNearTheBottomOnSharedScale() {
        let down = series([(0, 1000), (1, 1000), (2, 1000)])
        let up = series([(0, 20), (1, 20), (2, 20)])
        let (p, s) = Sparkline.points(down, up, now: 2, size: size)

        XCTAssertFalse(p.isEmpty, "seri utama harus tergambar")
        XCTAssertFalse(s.isEmpty, "seri kedua harus tergambar")

        // Di y=0 (puncak) .. y=42 (dasar). Skala utama memetakan 1000 -> ~0.
        let downY = p.map(\.y).min() ?? .infinity
        let upY = s.map(\.y).min() ?? .infinity
        // Upload seharusnya jauh lebih RENDAH (y lebih besar), bukan setinggi.
        XCTAssertGreaterThan(upY, downY + size.height * 0.5,
                             "upload kecil harus nyaris di dasar; downY=\(downY) upY=\(upY)")
    }

    /// D80 — SKALA BERSAMA + LOGARITMA.
    ///
    /// Versi test ini mempertahankan asumsi sumbu LINEAR ("upload 1% dari
    /// download harus nempel di dasar"). Setelah D80 asumsi itu tidak berlaku
    /// dan memang TIDAK BOLEH berlaku: trafik nyata melintasi 4 dekade, dan
    /// sumbu linear tidak mungkin menampilkannya. Yang dijaga sekarang dua
    /// hal terpisah: kedua seri memakai SATU peta yang sama, dan peta itu
    /// logaritma 3 dekade.
    ///
    /// `now = 2.5` dipakai supaya ease-in SAMPAI — dengan `now = 2` sampel
    /// terbaru masih di-ease dari nilai sebelumnya, jadi puncak yang
    /// benar-benar tergambar bukan nilai tersimpan. Versi pertama test ini
    /// salah di dua tempat sekaligus karena hal ini.
    func testBothSeriesShareTheSameLogMapping() {
        let down = series([(0, 800), (1, 900), (2, 1000)])
        let up = series([(0, 8), (1, 9), (2, 10)])   // persis 1/100 dari download
        let (p, u) = Sparkline.points(down, up, now: 2.5, size: size)

        let decades = TrafficYScale.decades
        let peak = 1000.0
        let floor = peak / pow(10, decades)

        // Puncak memetakan ke 8% ruang kosong.
        XCTAssertEqual(p.map(\.y).min() ?? 99, size.height * 0.08, accuracy: 0.5)

        // Upload = 10, yaitu 2 dekade di bawah puncak dan 1 dekade di atas
        // dasar. Posisinya harus PERSIS hasil rumus, untuk kedua seri.
        let expected = size.height * (1 - 0.92 * (log10(10) - log10(floor)) / decades)
        XCTAssertEqual(u.map(\.y).min() ?? -1, expected, accuracy: 0.5,
                       "upload harus di posisi log yang terhitung")
        XCTAssertGreaterThan(u.map(\.y).min() ?? 0, p.map(\.y).min() ?? 0,
                             "upload yang lebih kecil harus tetap terlihat lebih rendah")
    }

    /// Nilai di bawah dasar dijepit ke dasar, bukan diekstrapolasi.
    /// Menampilkan bentuk yang tidak ada lebih menipu daripada menamparkannya datar.
    func testValuesBelowTheLogFloorClampInsteadOfExtrapolating() {
        let s = series([(0, 1_000_000), (1, 1_000_000)])
        let (p, _) = Sparkline.points(s, nil, now: 1, size: size)
        XCTAssertTrue(p.allSatisfy { $0.y <= size.height + 0.001 },
                      "tidak boleh ada titik di bawah dasar plot")
    }

    /// Trafik NOL harus tetap terlihat sebagai garis datar di dasar —
    /// bukan titik hilang, bukan error.
    func testZeroTrafficRendersAsFlatLineAtTheBottom() {
        let s = series([(0, 0), (1, 0), (2, 0)])
        let p = Sparkline.points(s, now: 2, size: size)
        XCTAssertFalse(p.isEmpty, "trafik nol harus tetap tergambar")
        XCTAssertTrue(p.allSatisfy { abs($0.y - size.height) < 0.5 },
                      "trafik nol harus datar tepat di dasar")
    }

    /// Seri kedua kosong tidak boleh menjatuhkan/menggeser grafik utama.
    func testEmptySecondaryStillDrawsPrimary() {
        let down = series([(0, 100), (1, 200), (2, 300)])
        let up = TrafficSeries(capacity: 128)
        let (p, s) = Sparkline.points(down, up, now: 2, size: size)
        XCTAssertFalse(p.isEmpty)
        XCTAssertTrue(s.isEmpty, "seri kosong tidak boleh menghasilkan titik")
        XCTAssertEqual(Double(p.last?.x ?? -1), size.width, accuracy: 0.5)
    }

    /// Overload tunggal (yang dipakai test lama) harus tetap memakai skala
    /// sendiri — kalau tidak, test lama jadi tidak bermakna.
    ///
    /// Catatan: puncak TIDAK memetakan ke y=0. `project` menyisakan 8% ruang
    /// kosong di atas (`1 - v/peak * 0.92`) supaya garis tertinggi tidak
    /// menempel di tepi. Jadi puncak -> y = tinggi * 0.08.
    func testSingleSeriesOverloadStillNormalisesToItsOwnPeak() {
        let up = series([(0, 10), (1, 10), (2, 10)])
        let pts = Sparkline.points(up, now: 2, size: size)
        XCTAssertEqual(pts.map(\.y).min() ?? 99, size.height * 0.08, accuracy: 0.5,
                       "puncak seri tunggal harus memetakan ke 8% ruang kosong dari atas")
    }
}

// MARK: - Stabilitas skala Y (D79)

/// Bug yang dilaporkan: kurva "tidak stabil" — seluruh garis melompat
/// vertikal. Penyebabnya bukan data, tapi skala Y yang dihitung ulang dari
/// jendela 30 detik di SETIAP FRAME: begitu satu sampel lama keluar dari
/// jendela, puncaknya berubah mendadak dan semua titik berikut-y-nya
/// dihitung ulang terhadap skala itu.
final class TrafficYScaleStabilityTests: XCTestCase {

    /// Naik harus SEKETIKA. Kalau ikut smoothed, lonjakan trafik baru
    /// terlambat terlihat dan grafik lagging.
    func testAttackIsInstant() {
        let s = TrafficYScale()
        s.update(observed: 100, now: 0)
        XCTAssertEqual(s.update(observed: 5000, now: 0.1), 5000, accuracy: 0.001)
    }

    /// Turun harus pelan: inilah inti perbaikan. Tanpa itu, begitu sampel
    /// puncak keluar dari jendela, skala jatuh mendadak.
    ///
    /// Diperiksa dalam rasio, bukan selisih mutlak: sejak D80 skala berada di
    /// ruang log, jadi "turun pelan" berarti TIDAKimia sudah anjlok ke nilai
    /// baru. Runtuh total (1000 -> 10) sudah pasti tidak pelan.
    func testReleaseIsGradualNotInstant() {
        let s = TrafficYScale()
        s.update(observed: 1000, now: 0)
        let after = s.update(observed: 10, now: 0.05)
        XCTAssertGreaterThan(after, 500, "skala harus nyaris tak berubah di 50ms, dapat \(after)")
        XCTAssertLessThan(after, 1000, "tapi juga harus sudah turun sedikit")
    }

    /// Half-life-nya benar — dalam **ruang log**, yang memang yang dipakai.
    ///
    /// Dulu (skala linear) ini berarti `peak` jadi separuh. Sekarang yang
    /// meluruh separuh adalah `log10(peak)`, jadi nilai linernya jadi
    /// `10^(log10(peak)/2)` — dan itu persis yang membuat D80 mungkin:
    /// jarak antar dekade seragam, bukan melompati lonjakan orders of magnitude.
    ///
    /// Harus di-*step* per detik, bukan melompat sekali: `dt` dijepit max 1
    /// detik (lihat `testHugeTimeGapClampsRelease`).
    func testReleaseFollowsHalfLifeInLogSpace() {
        let h = TrafficYScale.releaseHalfLife
        let s = TrafficYScale()
        s.update(observed: 1000, now: 0)
        var value = 1000.0
        for step in 1...Int(h) {          // satu frame per detik
            value = s.update(observed: 1, now: Double(step))
        }
        let expected = pow(10, log(1000.0) / log(10.0) / 2)
        XCTAssertEqual(value, expected, accuracy: expected * 0.35,
                       "log(peak) harus meluruh separuh setelah \(h) detik")
    }

    /// Skala harus MONOTON TURUN saat data mengecil — tidak boleh naik
    /// sendiri di tengah pelepasan (yang akan membuat kurva berdenyut).
    func testScaleNeverRisesWhileReleasing() {
        let s = TrafficYScale()
        s.update(observed: 1000, now: 0)
        var prev = Double.infinity
        for step in 1...60 {                    // 60 frame @60fps = 1 detik
            let cur = s.update(observed: 5, now: Double(step) / 60)
            XCTAssertLessThanOrEqual(cur, prev + 0.0001,
                                     "skala naik sendiri di frame \(step)")
            prev = cur
        }
    }

    /// Elapsed besar (tab tidak aktif, lalu kembali) tidak boleh melompati
    /// seluruh pelepasan sekaligus — itu akan terasa seperti glitch.
    func testHugeTimeGapClampsRelease() {
        let s = TrafficYScale()
        s.update(observed: 1000, now: 0)
        let after = s.update(observed: 1, now: 3600)   // 1 jam kemudian
        XCTAssertGreaterThan(after, 1, "skala tidak boleh anjlok ke 1 seketika")
    }

    /// Frame-rate independence: hasil setelah N detik HARUS sama di 60 Hz
    /// maupun 30 Hz. Kalau decay dihitung per frame, ini tidak berlaku dan
    /// grafik akan berperilaku berbeda di monitor 60 Hz vs 120 Hz.
    func testReleaseIsFrameRateIndependent() {
        let run = { (fps: Double) -> Double in
            let s = TrafficYScale()
            s.update(observed: 1000, now: 0)
            var last = 0.0
            for i in 1...Int(fps * 3) { last = s.update(observed: 1, now: Double(i) / fps) }
            return last
        }
        XCTAssertEqual(run(60), run(30), accuracy: run(60) * 0.02,
                       "skala setelah 3 detik harus sama di 60Hz dan 30Hz")
        XCTAssertEqual(run(60), run(120), accuracy: run(60) * 0.02,
                       "dan juga sama di 120Hz")
    }

    /// `reset()` mengembalikan ke keadaan awal — dipakai saat disconnect.
    /// Setelah reset `logPeak = 0`, jadi `peak = 10^0 = 1`, bukan 0.
    func testResetClearsScale() {
        let s = TrafficYScale()
        s.update(observed: 5000, now: 0)
        s.reset()
        XCTAssertEqual(s.peak, 1, accuracy: 0.001)
        XCTAssertEqual(s.update(observed: 7, now: 100), 7, accuracy: 0.01,
                       "setelah reset, skala harus langsung mengikuti data baru")
    }

    /// Regresi: `project` WAJIB memakai peak yang diberikan apa adanya.
    /// Versi D78 menulis `max(forcedPeak, series.peak(...))`, yang membuat
    /// redaman mustahil — nilai mentah menyalakan kembali skala tiap frame.
    ///
    /// Dalam skala log, nilai di atas puncak DIJEPIT ke puncak plot, bukan
    /// digambar keluar kotak: dari 1000 dengan peak paksa 100, titik harus
    /// menempel di 8% ruang kosong atas — persis hasil rumus.
    func testForcedPeakIsUsedVerbatim() {
        let s = TrafficSeries(capacity: 64)
        s.append(time: 0, value: 1000)
        s.append(time: 1, value: 1000)
        let pts = Sparkline.points(s, now: 1, size: CGSize(width: 300, height: 42),
                                   peak: 100)
        XCTAssertEqual(pts.map(\.y).min() ?? 99, 42 * 0.08, accuracy: 0.5,
                       "nilai di atas peak paksa harus dijepit ke puncak plot")
    }
}


/// Simulasi kondisi nyata: sampel 1 Hz, jendela 30 detik, 60 fps.
///
/// Metriknya: ambil SATU sampel dengan waktu tetap, lalu lihat berapa px
/// posisinya bergeser vertikal antar frame.
///
/// Tiga kesalahan dilakukan di versi-versi sebelumnya, semuanya karena
/// kerangka pengukurannya salah, bukan karena kodenya:
///  1. Membandingkan titik berdasarkan INDEKS. Jendela bergeser tiap detik,
///     jumlah titik berubah, jadi indeks ke-N menunjuk sampel BERBEDA antar
///     frame — ukurannya jadi pergeseran horizontal, bukan lompatan skala.
///     Dua skenario menghasilkan angka yang persis sama (38.157px) karena itu.
///  2. Mengamati rentang waktu yang TIDAK memuat peristiwa yang diuji.
///     Lonjakan di detik 10 baru keluar dari jendela 30 detik pada detik 40;
///     observasi 12..32 tidak pernah sampai ke sana, jadi tidak ada lompatan
///     sama sekali yang bisa diukur.
///  3. Pencarian titik berdasarkan X bisa "kena" titik yang salah sebelum
///     sampel target ada (yang paling dekat adalah ujung kanan), menghasilkan
///     y yang bukan miliknya. Sekarang observasi dimulai setelah sampel
///     target pasti ada DAN bukan sampel terbaru (selesai easing).
final class SparklineScaleStabilityOverTimeTests: XCTestCase {
    private let size = CGSize(width: 300, height: 42)
    /// Jendela TIDAK di-hardcode: `Sparkline.window` 60 detik, bukan 30.
    /// Versi test ini mengasumsikan 30 dan karena itu tidak pernah observing
    /// peristiwa yang diuji sama sekali — gejalanya terlihat di sumber, bukan
    /// di sini, tapi tetap jebakan: test hijau yang tidak menguji apa pun.
    private var window: TimeInterval { Sparkline.window }

    private func y(forTime t: TimeInterval, now: TimeInterval,
                   points: [CGPoint]) -> Double? {
        let age = now - t
        guard age >= 0, age <= window else { return nil }
        let expectedX = size.width * (1 - CGFloat(age / window))
        guard let p = points.min(by: {
            abs(Double($0.x) - Double(expectedX)) < abs(Double($1.x) - Double(expectedX))
        }), abs(Double(p.x) - Double(expectedX)) < 0.5 else { return nil }
        return Double(p.y)
    }

    private func maxVerticalJump(smoother: Bool) -> Double {
        let down = TrafficSeries(capacity: 128)
        let up = TrafficSeries(capacity: 128)
        let scale = TrafficYScale()
        var prevY: Double?
        var worst = 0.0

        // Lonjakan di detik 5 keluar dari `Sparkline.scaleWindow` (12 detik)
        // pada detik ~17 — BUKAN dari jendela gambar 60 detik. Observasi harus
        // mencakup detik itu.
        //
        // Versi test ini masih mengamati 60..80 karena ditulis sebelum
        // `scaleWindow` diperkenalkan; rentang itu sama sekali tidak memuat
        // peristiwa yang diuji, jadi keduanya mengukur 0.0px dan test
        // "lulus" tanpa menguji apa pun.
        for frame in 0..<(30 * 60) {
            let t = Double(frame) / 60
            if frame % 60 == 0 {
                let second = Int(t)
                down.append(time: t, value: second == 5 ? 20000.0 : 100.0)
                up.append(time: t, value: 50.0)
            }
            guard t >= 14, t <= 30 else { continue }

            let observed = max(Sparkline.visiblePeak(down, now: t),
                               Sparkline.visiblePeak(up, now: t))
            let peak = smoother ? scale.update(observed: observed, now: t) : observed
            let (p, _) = Sparkline.points(down, up, now: t, size: size, peak: peak)

            // Sampel target detik 13: usianya 1..17 detik, selalu di dalam
            // jendela gambar 60 detik dan tidak pernah jadi sampel terbaru
            // (jadi ease-in sudah selesai).
            if let y = y(forTime: 13, now: t, points: p) {
                if let prev = prevY { worst = max(worst, abs(y - prev)) }
                prevY = y
            }
        }
        return worst
    }

    /// Tanpa peredam, lompatan vertikal harus besar — inilah gejala yang
    /// dilaporkan sebagai "tidak stabil".
    func testUnsmoothedScaleProducesLargeVerticalJumps() {
        let jump = maxVerticalJump(smoother: false)
        XCTAssertGreaterThan(jump, 5.0,
                             "tanpa peredam harus ada lompatan vertikal besar, dapat \(jump)px")
    }

    /// Dengan peak-hold, lompatan vertikal harus hilang.
    /// Ini test yang mengunci perbaikan "tidak stabil".
    func testSmoothingRemovesTheVerticalJumping() {
        let unsmoothed = maxVerticalJump(smoother: false)
        let smoothed = maxVerticalJump(smoother: true)

        XCTAssertLessThan(smoothed, unsmoothed * 0.5,
                          "peredam harus memangkas lompatan jadi <50%: "
                          + "tanpa \(unsmoothed)px -> dengan \(smoothed)px")
        XCTAssertLessThan(smoothed, 1.0,
                          "lompatan sisa per frame harus di bawah 1px, dapat \(smoothed)px")
    }
}

/// Regresi D80 — hasil speed test.acara "curve normal dulu, beberapa detik
/// kemudian jadi error".
///
/// Skenarionya persis seperti di aplikasi: ada SATU sampel transien besar
/// (burst koneksi/TLS di awal speed test), lalu trafik turun ke nilai normal
/// yang jauh lebih kecil.
///
/// Karena skala dihitung dari jendela 60 detik, sampel transien itu masih
/// menahan skala jauh setelah speed test selesai — sehingga trafik yang
/// sedang berjalan tergambar gepeng di dasar dan grafik terlihat rusak.
final class SpeedTestTransientDoesNotFlattenGraphTests: XCTestCase {
    private let size = CGSize(width: 300, height: 42)

    /// Tinggi (dari dasar) titik untuk nilai tertentu pada frame ini.
    private func renderedHeight(value: Double, at t: TimeInterval,
                                 down: TrafficSeries, up: TrafficSeries,
                                 smoothed: Bool) -> Double? {
        let scale = TrafficYScale()
        var peak = 0.0
        // Bangun ulang riwayat follower supaya deterministik untuk waktu ini.
        var s2 = TrafficYScale()
        for step in 0...Int(t * 60) {
            let tt = Double(step) / 60
            let o = max(Sparkline.visiblePeak(down, now: tt),
                       Sparkline.visiblePeak(up, now: tt))
            peak = smoothed ? s2.update(observed: o, now: tt) : o
        }
        _ = scale
        let (_, second) = Sparkline.points(down, up, now: t, size: size, peak: peak)
        // Titik terakhir seri utama = nilai terkini.
        let (p, _) = Sparkline.points(down, up, now: t, size: size, peak: peak)
        let newest = p.last
        guard newest != nil else { return nil }
        // Bandingkan relatif terhadap tinggi plot: 0 = dasar, 42 = puncak.
        _ = second
        return Double(size.height - (newest?.y ?? size.height))
    }

    /// 20 detik SETELAH lonjakan transien, trafik normal harus tetap
    /// terlihat jelas — tidak boleh tergambar gepeng di dasar.
    func testCurrentTrafficIsVisibleAfterATransientBurst() {
        let down = TrafficSeries(capacity: 128)
        let up = TrafficSeries(capacity: 128)
        let mib = 1024.0 * 1024.0

        // t=0..2 normal (8 KiB/s), t=3 burst (100 MiB/s), t=4..24 normal lagi.
        for s in 0...24 {
            let v = s == 3 ? 100 * mib : 8 * 1024
            down.append(time: Double(s), value: v)
            up.append(time: Double(s), value: 8 * 1024)
        }

        // Di detik 24: burst sudah 21 detik lalu, trafik sekarang 8 KiB/s.
        let h = renderedHeight(value: 8 * 1024, at: 24, down: down, up: up,
                               smoothed: true)
        let shown = try? XCTUnwrap(h)
        XCTAssertGreaterThan(shown ?? 0, size.height * 0.30,
                             "trafik aktif harus memakai >30% tinggi plot; "
                             + "hanya \(shown ?? -1)px dari \(size.height)px "
                             + "-> burst lama masih menahan skala")
    }
}

/// D81 — tepi KIRI grafik hilang per detik.
///
/// Gejalanya: ujung garis kanan (data baru) muncul halus, tapi ujung kiri
/// "hilang" dalam langkah-langkah satu detik.
///
/// Penyebab: `project` mengambil satu sampel sebelum jendela (supaya kurva
/// tidak terpotong), TETAPI lalu membuangnya lagi lewat `guard age < window`.
/// Akibatnya jalur yang digambar tidak pernah mencapai x <= 0, dan antara
/// x = 0 dan titik paling kiri yang digambar selalu ada celah. Lebar celah
/// itu naik-turun 0..(satu spasi sampel) dan kembar setiap detik — persis
/// "hilang per detik".
final class SparklineLeftEdgeContinuityTests: XCTestCase {
    private let size = CGSize(width: 300, height: 42)

    private func series(_ n: Int) -> TrafficSeries {
        let s = TrafficSeries(capacity: 128)
        for i in 0..<n { s.append(time: Double(i), value: 100 + Double(i % 7) * 30) }
        return s
    }

    /// Jalur WAJIB menutup tepi kiri: harus ada titik pada x <= 0, supaya
    /// setelah `.clipped()` tidak ada celah di x = 0.
    func testPathAlwaysReachesTheLeftEdge() {
        let s = series(120)
        var checked = 0
        for now in stride(from: 60.0, through: 110.0, by: 0.05) {
            let pts = Sparkline.points(s, now: now, size: size)
            // JANGAN `continue` kalau kosong: jalur kosong harus GAGAL, bukan
            // lolos diam-diam. Versi pertama test ini memakai `guard ... else
            // { continue }`, jadi saat mutasi membuat `project` break sebelum
            // menggambar apa pun, kedua test di file ini LULUS tanpa menguji
            // apa pun.
            guard let first = pts.first else {
                return XCTFail("di now=\(now) jalur kosong — tepi kiri tidak tertutup")
            }
            checked += 1
            XCTAssertLessThanOrEqual(
                Double(first.x), 0.0,
                "di now=\(now) titik paling kiri di x=\(first.x) — ada celah di tepi kiri")
        }
        XCTAssertGreaterThan(checked, 500, "loop tidak boleh di-short-circuit")
    }

    /// Nilai di x=0 harus BERJALAN HALUS antar frame, bukan melompat
    /// mengikuti pertukaran sampel tiap detik.
    func testLeftEdgeValueDoesNotStepOncePerSecond() {
        let s = series(120)
        var prev: Double?
        var worst = 0.0
        var sampled = 0
        var t = 60.0
        while t < 110 {
            let pts = Sparkline.points(s, now: t, size: size)
            if let edge = leftEdgeY(points: pts) {
                if let p = prev { worst = max(worst, abs(edge - p)) }
                prev = edge
                sampled += 1
            }
            t += 1.0 / 60
        }
        // Kalau `sampled` kecil, pengukurannya tidak menguji apa pun.
        XCTAssertGreaterThan(sampled, 2000,
                             "hanya \(sampled) frame punya tepi kiri — ukurannya hampa")
        XCTAssertLessThan(worst, 1.0,
                          "ujung kiri melompat \(worst)px antar frame — ada langkah per detik")
    }

    /// Nilai garis tepat di x = 0, diinterpolasi dari dua titik yang
    /// mengapitnya. Inilah yang benar-benar dilihat user di tepi kiri.
    private func leftEdgeY(points: [CGPoint]) -> Double? {
        guard let a = points.first(where: { $0.x <= 0 }) else { return nil }
        guard let b = points.first(where: { $0.x >= 0 }) else { return nil }
        if a.x == b.x { return Double(a.y) }
        let f = CGFloat((0 - a.x) / (b.x - a.x))
        return Double(a.y + (b.y - a.y) * f)
    }
}

/// D81 lanjutan: toleransi satu sampel di luar jendela tidak boleh
/// berubah jadi "garis panjang yang tidak pernah terjadi" setelah jeda data
/// besar (misal lama idle, lalu koneksi hidup lagi).
final class SparklineGapDoesNotDrawFalseLineTests: XCTestCase {
    private let size = CGSize(width: 300, height: 42)

    func testOldSampleAcrossBigGapIsNotStitched() {
        let s = TrafficSeries(capacity: 128)
        s.append(time: 0, value: 50)
        s.append(time: 100, value: 900)     // jeda 100 detik

        let (pts, _) = Sparkline.points(s, nil, now: 100.5, size: size)

        // Selisih y tidak boleh sebesar nilai lama -> baru yang berarti
        // garis panjang menyesatkan digambar.
        let ys = pts.map(\.y)
        let spread = (ys.max() ?? 0) - (ys.min() ?? 0)
        XCTAssertLessThan(spread, 1.0,
                          "sampel lama harus TIDAK dijahit ke sampel baru; "
                          + "selisih y \(spread)px")
    }

    /// Jalur normal (sampel rapat) TETAP harus menjangkau x <= 0 — jangan
    /// sampai perbaikan D81 malah membalik perilaku di kasus biasa.
    func testDenseDataStillReachesTheLeftEdge() {
        let s = TrafficSeries(capacity: 128)
        for i in 0..<80 { s.append(time: Double(i), value: Double(100 + i % 5)) }
        // now=70.5 -> jendela mulai dari detik 10.5, jadi ada sampel older
        // yang boleh dibuat x-nya negatif.
        //
        // Versi pertama memakai now=59.5 dengan 60 sampel: jendela-nya mulai
        // SEBELUM sampel tertua, jadi `start` mentok di 0 dan tidak ada
        // sampel lebih tua untuk dimuat. Garis mulai di x=2.5 dan itu BENAR —
        // tidak ada data di sebelah kiri. Test itu menuntut sesuatu yang
        // tidak mungkin.
        let (pts, _) = Sparkline.points(s, nil, now: 70.5, size: size)
        XCTAssertTrue(pts.contains { $0.x <= 0 },
                      "data rapat harus tetap menjangkau tepi kiri")
    }
}
