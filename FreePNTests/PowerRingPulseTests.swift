import XCTest
@testable import FreePNApp

/// D72 — denyut tombol daya adalah OPACITY terang-redup, bukan rotasi.
///
/// Sejarah perubahan ini penting, karena setiap langkahnya memperbaiki satu
/// keluhan dan menimbulkan yang lain:
///  - D67: `rotationEffect(working ? 360 : 0)` → cincin terpuntir BALIK tiap
///    status berubah.
///  - D67 (kedua): `phase` naik tanpa henti → kilatan hilang, tapi cincin
///    berputar terus-menerus termasuk saat terputus.
///  - D71: spinner hanya saat bekerja → benar, tapi rotasi tetap tidak memberi
///    informasi.
///  - D72 (sekarang): rotasi dihapus total; denyut opacity naik-turun.
final class PowerRingPulseTests: XCTestCase {
    /// Hanya dua dari lima status yang berdenyut.
    nonisolated static func shouldPulse(for status: ConnectionStatus) -> Bool {
        status == .connecting || status == .disconnecting
    }

    func testDisconnectedIsStill() {
        XCTAssertFalse(Self.shouldPulse(for: .disconnected))
    }

    func testErrorIsStill() {
        XCTAssertFalse(Self.shouldPulse(for: .error))
    }

    func testConnectedIsStill() {
        XCTAssertFalse(Self.shouldPulse(for: .connected))
    }

    func testWorkingStatesPulse() {
        XCTAssertTrue(Self.shouldPulse(for: .connecting))
        XCTAssertTrue(Self.shouldPulse(for: .disconnecting))
    }

    func testExactlyTwoOfFiveStatusesPulse() {
        let all: [ConnectionStatus] = [.disconnected, .connecting, .connected, .disconnecting, .error]
        XCTAssertEqual(all.filter { Self.shouldPulse(for: $0) }.count, 2)
    }

    // MARK: - Nilai opacity

    /// Saat diam, opacity PENUH — bukan redup. Tombol terputus harus tetap
    /// terbaca jelas sebagai "tekan untuk sambung"; kalau ikut redup, tombol
    /// utama aplikasi kehilangan daya tariknya saat justru
    /// paling dibutuhkan.
    func testIdleIsFullyOpaque() {
        for pulse in [true, false] {
            XCTAssertEqual(PowerRing.ringOpacity(working: false, pulse: pulse), 1.0,
                           "saat diam cincin harus selalu penuh")
        }
    }

    /// Saat bekerja, denyut antara dua ujung — nilai yang berbeda itu ESSENSIAL
    /// untuk disebut denyut. Kalau keduanya sama, tidak ada yang bergerak.
    func testWorkingPulseHasTwoDistinctExtremes() {
        let dim = PowerRing.ringOpacity(working: true, pulse: false)
        let bright = PowerRing.ringOpacity(working: true, pulse: true)
        XCTAssertNotEqual(dim, bright, "denyut harus punya dua nilai berbeda")
        XCTAssertEqual(bright, 1.0, "puncak denyut = penuh")
        XCTAssertLessThan(dim, 1.0, "lembah denyut harus redup")
        // Terlalu redup = cincin hilang saat sedang connect; terjauh masih
        // harus terbaca sebagai "ada proses jalan".
        XCTAssertGreaterThan(dim, 0.2, "lembah jangan terlalu redup — cincin harus tetap terlihat")
    }

    /// Denyut tidak boleh menyentuh nilai saat diam, apa pun posisinya.
    func testIdleIgnoresPulsePosition() {
        XCTAssertEqual(PowerRing.ringOpacity(working: false, pulse: false),
                       PowerRing.ringOpacity(working: false, pulse: true))
    }

    /// Flip Bool bolak-balik menghasilkan denyut yang bolak-balik — dipakai untuk
    /// memastikan `repeatForever(autoreverses:)` menghasilkan gerakan, bukan
    /// nilai yang diam di satu tempat.
    func testFlippingPulseProducesMovement() {
        var pulse = false
        var seen: [Double] = []
        for _ in 0..<4 {
            seen.append(PowerRing.ringOpacity(working: true, pulse: pulse))
            pulse.toggle()
        }
        XCTAssertEqual(seen, [0.35, 1.0, 0.35, 1.0])
        XCTAssertGreaterThan(Set(seen).count, 1, "harus ada gerakan")
    }

    /// Tidak boleh ada rotasi tersisa di view. Jika `rotationEffect` /
    /// `phase` / `spinning` muncul lagi, kilatan-balik D67 ikut kembali —
    /// dan itu sulit dilihat tanpa menjalankan app.
    func testNoRotationCodeRemainsInSource() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // FreePNTests/
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("FreePN/DesignSystem/Badge.swift")
        let src = try String(contentsOf: url, encoding: .utf8)

        guard let start = src.range(of: "public struct PowerRing"),
              let end = src.range(of: "private var ringTint")
        else { return XCTFail("tidak menemukan blok PowerRing") }
        let block = String(src[start.lowerBound..<end.lowerBound])
        // Komentari boleh menyebutnya (sejarah D67); kode tidak boleh.
        let code = block.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.hasPrefix("//") }
            .joined(separator: "\n")

        for forbidden in ["rotationEffect", "repeatForever(autoreverses: false)", "@State private var phase"] {
            XCTAssertFalse(code.contains(forbidden),
                           "kode \(forbidden) tidak boleh ada lagi — rotasi dihapus di D72")
        }
        XCTAssertTrue(code.contains("repeatForever(autoreverses: true)"),
                      "denyut harus pakai repeatForever(autoreverses: true)")
    }
}
