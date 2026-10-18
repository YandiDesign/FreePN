import XCTest
@testable import FreePNApp

/// D74 — satuan laju trafik harus menyesuaikan besarannya.
///
/// Sebelumnya hardcoded `"\(Int(bytesPerSecond / 1024)) KB/s"`: label selalu KB
/// apa pun besarnya, jadi unduh 8 MB/s tampil "8192 KB/s" dan user harus
/// menghitung sendiri di kepalanya. Bug itu tidak terlihat sebelum D73, karena
/// sampai saat itu angkanya sendiri salah.
final class TrafficRateUnitTests: XCTestCase {
    private let KiB = 1024.0
    private let MiB = 1024.0 * 1024
    private let GiB = 1024.0 * 1024 * 1024

    // MARK: - Beralih satuan

    func testKilobytesStayInKiB() {
        XCTAssertEqual(TrafficCard.rate(1 * KiB), "1 KiB/s")
        XCTAssertEqual(TrafficCard.rate(64 * KiB), "64 KiB/s")
        XCTAssertEqual(TrafficCard.rate(999 * KiB), "999 KiB/s")
    }

    func testMegabytesSwitchToMiB() {
        XCTAssertEqual(TrafficCard.rate(1 * MiB), "1 MiB/s")
        XCTAssertEqual(TrafficCard.rate(8 * MiB), "8 MiB/s")
        XCTAssertEqual(TrafficCard.rate(512 * MiB), "512 MiB/s")
    }

    func testGigabytesSwitchToGiB() {
        XCTAssertEqual(TrafficCard.rate(1 * GiB), "1 GiB/s")
        XCTAssertEqual(TrafficCard.rate(3 * GiB), "3 GiB/s")
    }

    /// Batas tepat di bawah 1 MiB: 1023.9 KiB adalah 1023.9 KiB, dan UI harus
    /// memilih KiB — bukan MiB yang akan tampil "0 MiB/s" (nol terasa bohong).
    func testJustBelowMegabyteStaysInKiB() {
        XCTAssertEqual(TrafficCard.rate(1023.9 * KiB), "1 MiB/s",
                       ">= 1000 KiB sudah pindah ke MiB")
        XCTAssertEqual(TrafficCard.rate(999 * KiB), "999 KiB/s")
    }

    /// Label tidak boleh pernah jadi nol untuk trafik nyata: unduh 300 byte
    /// per detik itu trafik, bukan "tidak ada".
    func testSubKibibyteTrafficDoesNotDisplayZero() {
        XCTAssertEqual(TrafficCard.rate(300), "1 KiB/s")
        XCTAssertEqual(TrafficCard.rate(1), "1 KiB/s")
    }

    func testIdleIsZero() {
        XCTAssertEqual(TrafficCard.rate(0), "0 KiB/s")
    }

    // MARK: - Kasus yang bisa merusak UI

    /// Data rusak dari core tidak boleh membuat layout rusak: `NaN`/`.infinity`
    /// akan membuat `Int(...)` trap dan merusak seluruh kartu.
    func testNonFiniteValuesAreSafe() {
        XCTAssertEqual(TrafficCard.rate(Double.nan), "0 KiB/s")
        XCTAssertEqual(TrafficCard.rate(Double.infinity), "0 KiB/s")
        XCTAssertEqual(TrafficCard.rate(-Double.infinity), "0 KiB/s")
    }

    func testNegativeRateIsSafe() {
        XCTAssertEqual(TrafficCard.rate(-5), "0 KiB/s")
    }

    /// Lebar label harus stabil: maksimum 3 digit + satuan, supaya kolom
    /// tidak bergoyang tiap 2 detik saat angka berubah.
    func testLabelWidthIsBounded() {
        for bps in [1.0, KiB, MiB, GiB, 999 * GiB, 1024 * GiB] {
            let text = TrafficCard.rate(bps)
            let digits = text.prefix(while: { $0.isNumber })
            XCTAssertLessThanOrEqual(digits.count, 4,
                                     "label \(text) terlalu lebar — kolom akan bergoyang")
        }
    }

    /// Satuan harus biner (1024), konsisten dengan `ByteCountFormatter` binary
    /// yang dipakai untuk total tepat di bawahnya. Kalau rate pakai 1000 dan
    /// total pakai 1024, dua angka di kartu yang sama saling bertentangan.
    func testUnitsAreBinaryConsistentWithTotal() {
        // 1 MiB = 1.048.576 byte. Dengan basis 1024 hasilnya tepat "1 MiB/s".
        XCTAssertEqual(TrafficCard.rate(1_048_576), "1 MiB/s")
        // Basis 1000 akan memberi "1 MB/s" dan angka desimal berbeda.
        XCTAssertFalse(TrafficCard.rate(1_048_576).hasPrefix("1 MB"),
                       "satuan harus biner agar cocok dengan total di bawahnya")
    }

    /// Tidak boleh ada satuan yang tak dikenal di keluaran mana pun — termasuk
    /// untuk angka ekstrem di kedua arah.
    ///
    /// Eksponen negatif dan positif besar diuji karena dua-duanya pernah
    /// menyingkap bug nyata:
    ///  - negatif: `rate` meng-clamp ke "1 KiB/s" untuk nilai di bawah 1 KiB;
    ///    versi pertama test ini salah mengira itu satuan tak dikenal.
    ///  - positif besar: mencapai batas daftar satuan, dan tanpa clamp nilai
    ///    `Int(value)` TRAP — proses mati, bukan hanya salah tampil.
    func testAlwaysUsesAKnownUnit() {
        let known = ["KiB/s", "MiB/s", "GiB/s", "TiB/s", "PiB/s", "EiB/s"]
        for exp in stride(from: -2.0, through: 40.0, by: 1.0) {
            let bps = pow(1024.0, exp)
            guard bps.isFinite, bps > 0 else { continue }
            let text = TrafficCard.rate(bps)
            let unit = text.split(separator: " ").last.map(String.init) ?? ""
            XCTAssertTrue(known.contains(unit),
                          "unknown unit \"\(unit)\" (label \(text)) at 1024^\(exp)")
            XCTAssertFalse(text.contains("nan") || text.contains("inf"),
                           "label \(text) tidak boleh memuat NaN/inf")
        }
    }

    /// Nilai astronomis tidak boleh membuat `Int(...)` TRAP. Bug ini nyata:
    /// tanpa clamp, `rate(pow(1024, 20))` membunuh proses — dan di app, itu
    /// berarti jendela hilang saat data core yang menganeh sampai ke UI.
    func testAstronomicalValueDoesNotCrash() {
        for exp in [10.0, 15.0, 20.0, 30.0, 300.0, 1e6] {
            let text = TrafficCard.rate(pow(1024.0, exp))
            XCTAssertFalse(text.isEmpty, "exp \(exp) menghasilkan label kosong")
        }
        // Nilai maksimum harus tertahan di satuan terakhir, bukan jadi angka
        // selebar beribu-ribu digit.
        let extreme = TrafficCard.rate(Double.greatestFiniteMagnitude)
        XCTAssertTrue(extreme.hasSuffix("EiB/s"), "unexpected: \(extreme)")
        XCTAssertLessThanOrEqual(extreme.split(separator: " ").first?.count ?? 99, 3,
                                 "label ekstrem terlalu lebar: \(extreme)")
    }

    /// Melompat satu satuan harus menaikkan ANGKA, tidak menurunkannya:
    /// 512 KiB boleh -> "1 MiB/s", tapi "1 MiB/s" -> "512 KiB/s" akan sangat
    /// membingungkan karena angka turun saat laju naik.
    func testUnitStepUpNeverShrinksTheNumber() {
        XCTAssertEqual(TrafficCard.rate(512 * KiB), "512 KiB/s")
        XCTAssertEqual(TrafficCard.rate(1024 * KiB), "1 MiB/s")
        XCTAssertEqual(TrafficCard.rate(1024 * MiB), "1 GiB/s")
    }

    /// Menyalakan laju tidak boleh membuat label lebih pendek secara tekstual
    /// (mis. "10 MiB/s" -> "1 KiB/s" karena ada batas satuan di tengah).
    func testLargerRateNeverYieldsShorterLabel() {
        var previous = ""
        for exp in 0...20 {
            let text = TrafficCard.rate(pow(1024.0, Double(exp)))
            XCTAssertGreaterThanOrEqual(text.count, previous.count,
                                       "label memendek saat laju naik: \(previous) -> \(text)")
            previous = text
        }
    }
}
