import SwiftUI

/// Path GitHub yang diturunkan dari SVG Font Awesome Free 7.3.1
/// (`viewBox="0 0 640 640"`, satu `<path>`).
///
/// Kenapa bukan `Image(nsImage:)` atau aset PNG:
/// - `NSImage` tidak bisa merender SVG di app sandbox (WebKit tidak
///   tersedia tanpa biaya tambahan), jadi SVG harus dikonversi.
/// - PNG buram di Retina dan menambah satu aset biner ke bundle untuk glyph
///   yang bentuknya statis.
///
/// SVG memakai sumbu Y ke bawah, sama seperti SwiftUI, jadi koordinat hanya
/// perlu dibagi 640 — tanpa pembalikan.
///
/// Outlinenya ditulis SEKALI di `outline` (dalam koordinat viewBox 640), lalu
/// `path(in:)` memetakannya ke SwiftUI dan `sourceBounds` menghitung kotak
/// batangnya. Dua-duanya diturunkan dari tabel yang sama, jadi tidak mungkin
/// One goes out of sync — dan geometrinya bisa diuji tanpa merender apa pun.
///
/// Bentuk, urutan, dan nilai koordinat sudah diverifikasi identik dengan
/// atribut `d` di SVG asli (162 angka, urutan sama).
///
/// Lisensi ikon: Font Awesome Free — CC BY 4.0.
/// https://fontawesome.com/license/free
public struct GitHubMark: Shape {
    /// Ukuran viewBox SVG asal.
    private static let box: CGFloat = 640

    /// Satu perintah path. `control1`/`control2` hanya dipakai oleh `.curve`.
    private enum Segment {
        case move(CGPoint)
        case line(CGPoint)
        case curve(to: CGPoint, c1: CGPoint, c2: CGPoint)
        case close
    }

    /// Peta koordinat viewBox → titik.
    private static func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: x, y: y)
    }

    /// Outlinenya, dalam koordinat viewBox 640×640 — urutan dan nilai diambil
    /// persis dari atribut `d` SVG.
    private static let outline: [Segment] = {
        var s: [Segment] = []

        // Kepala & badan katak (paruh atas).
        s.append(.move(p(280.5, 426.5)))
        s.append(.curve(to: p(168, 309.5), c1: p(214.5, 418.5), c2: p(168, 371)))
        s.append(.curve(to: p(192, 239.5), c1: p(168, 284.5), c2: p(177, 257.5)))
        s.append(.curve(to: p(194, 173.5), c1: p(185.5, 223), c2: p(186.5, 188)))
        s.append(.curve(to: p(257, 196), c1: p(214, 171), c2: p(241, 181.5)))
        s.append(.curve(to: p(320.5, 187), c1: p(276, 190), c2: p(296, 187)))
        s.append(.curve(to: p(383, 195.5), c1: p(345, 187), c2: p(365, 190)))
        s.append(.curve(to: p(446, 173.5), c1: p(398.5, 181.5), c2: p(426, 171)))
        s.append(.curve(to: p(447.5, 239), c1: p(453, 187), c2: p(454, 222)))
        s.append(.curve(to: p(472, 309.5), c1: p(463.5, 258), c2: p(472, 283.5)))
        s.append(.curve(to: p(358.5, 426), c1: p(472, 371), c2: p(425.5, 417.5)))

        // Ekor kanan (paruh bawah).
        s.append(.curve(to: p(387, 488.5), c1: p(375.5, 437), c2: p(387, 461)))
        s.append(.line(p(387, 540.5)))
        s.append(.curve(to: p(414.5, 558), c1: p(387, 555.5), c2: p(399.5, 564)))
        s.append(.curve(to: p(576, 321), c1: p(505, 523.5), c2: p(576, 433)))
        s.append(.curve(to: p(319.5, 64), c1: p(576, 179.5), c2: p(461, 64)))
        s.append(.curve(to: p(64, 321), c1: p(178, 64), c2: p(64, 179.5)))
        s.append(.curve(to: p(229.5, 558.5), c1: p(64, 432), c2: p(134.5, 524)))
        s.append(.curve(to: p(256, 541), c1: p(243, 563.5), c2: p(256, 554.5)))
        s.append(.line(p(256, 501)))

        // Ekor kiri.
        s.append(.curve(to: p(232, 506), c1: p(249, 504), c2: p(240, 506)))
        s.append(.curve(to: p(165.5, 454.5), c1: p(199, 506), c2: p(179.5, 488)))
        s.append(.curve(to: p(142.5, 431.5), c1: p(160, 441), c2: p(154, 433)))
        s.append(.curve(to: p(134.5, 425.5), c1: p(136.5, 431), c2: p(134.5, 428.5)))
        s.append(.curve(to: p(154.5, 415), c1: p(134.5, 419.5), c2: p(144.5, 415)))
        s.append(.curve(to: p(194.5, 442.5), c1: p(169, 415), c2: p(181.5, 424)))
        s.append(.curve(to: p(227.5, 463.5), c1: p(204.5, 457), c2: p(215, 463.5)))
        s.append(.curve(to: p(259.5, 447.5), c1: p(240, 463.5), c2: p(248, 459)))
        s.append(.curve(to: p(280.5, 426.5), c1: p(268, 439), c2: p(274.5, 431.5)))
        s.append(.close)
        return s
    }()

    public init() {}

    public func path(in rect: CGRect) -> Path {
        let unit = rect.width / Self.box
        func map(_ pt: CGPoint) -> CGPoint {
            CGPoint(x: rect.minX + pt.x * unit, y: rect.minY + pt.y * unit)
        }
        var path = Path()
        for segment in Self.outline {
            switch segment {
            case .move(let pt): path.move(to: map(pt))
            case .line(let pt): path.addLine(to: map(pt))
            case .curve(let to, let c1, let c2):
                path.addCurve(to: map(to), control1: map(c1), control2: map(c2))
            case .close: path.closeSubpath()
            }
        }
        return path
    }

    /// Kotak pembatas glyph dalam koordinat viewBox.
    ///
    /// Menginclusive titik tujuan dan titik kontrol kurva. Titik kontrol
    /// kurva kubik selalu berada di dalam kurvanya, jadi menyertakan keduanya
    /// tidak membuat kotak melebar — dan justru menutupi kesalahan yang
    /// membuat satu kurva meleset jauh.
    public static var sourceBounds: CGRect {
        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude
        func note(_ pt: CGPoint) {
            minX = min(minX, pt.x); maxX = max(maxX, pt.x)
            minY = min(minY, pt.y); maxY = max(maxY, pt.y)
        }
        for segment in outline {
            switch segment {
            case .move(let pt), .line(let pt): note(pt)
            case .curve(let to, let c1, let c2): note(to); note(c1); note(c2)
            case .close: break
            }
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}