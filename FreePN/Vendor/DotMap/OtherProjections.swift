// Vendored dari https://github.com/spilneo/DotMap (MIT).
// Salinan, bukan modul: `Package.swift` upstream memakai swift-tools 5.9,
// sedangkan proyek ini dibangun dengan Xcode 14.3.1 (Swift 5.8) yang
// tidak bisa mengurai manifest itu. Yang diubah hanya `Bundle.module`
// -> `Bundle.main` (sumber dayageo ada di bundle app, bukan SPM).
// `IPLocationService` sengaja TIDAK ikut: ia memanggil ipwho.is /
// ipinfo.io, jadi menyertakan IP user ke pihak ketiga.
import CoreGraphics
import Foundation

// MARK: - Orthographic

struct OrthographicProjection: GeoProjection {
    let lat0: Double
    let long0: Double
    private let sinP14: Double
    private let cosP14: Double

    init(lat0: Double, long0: Double) {
        self.lat0 = lat0
        self.long0 = long0
        self.sinP14 = sin(lat0)
        self.cosP14 = cos(lat0)
    }

    func forward(lat: Double, lng: Double) -> CGPoint? {
        let dlon = Geo.adjustLon(lng * Geo.d2r - long0)
        let phi = lat * Geo.d2r
        let sinphi = sin(phi)
        let cosphi = cos(phi)
        let coslon = cos(dlon)
        let g = sinP14 * sinphi + cosP14 * cosphi * coslon
        guard g > 0 || abs(g) <= Geo.epsln else { return nil }
        let x = Geo.a * cosphi * sin(dlon)
        let y = Geo.a * (cosP14 * sinphi - sinP14 * cosphi * coslon)
        return CGPoint(x: x, y: y)
    }

    func inverse(x: Double, y: Double) -> Coordinate? {
        let rh = (x * x + y * y).squareRoot()
        let z = Geo.asinz(rh / Geo.a)
        let sinz = sin(z)
        let cosz = cos(z)
        var lon = long0
        if abs(rh) <= Geo.epsln {
            return Coordinate(lat: lat0 * Geo.r2d, lng: long0 * Geo.r2d)
        }
        let lat = Geo.asinz(cosz * sinP14 + (y * sinz * cosP14) / rh)
        let con = abs(lat0) - Geo.halfPi
        if abs(con) <= Geo.epsln {
            if lat0 >= 0 {
                lon = Geo.adjustLon(long0 + atan2(x, -y))
            } else {
                lon = Geo.adjustLon(long0 - atan2(-x, y))
            }
            return Coordinate(lat: lat * Geo.r2d, lng: lon * Geo.r2d)
        }
        lon = Geo.adjustLon(long0 + atan2(x * sinz, rh * cosP14 * cosz - y * sinP14 * sinz))
        return Coordinate(lat: lat * Geo.r2d, lng: lon * Geo.r2d)
    }
}

// MARK: - Van der Grinten

struct VanDerGrintenProjection: GeoProjection {
    let long0: Double
    private let r: Double

    init(long0: Double) {
        self.long0 = long0
        self.r = Geo.a
    }

    func forward(lat: Double, lng: Double) -> CGPoint? {
        let dlon = Geo.adjustLon(lng * Geo.d2r - long0)
        let phi = lat * Geo.d2r
        if abs(phi) <= Geo.epsln {
            return CGPoint(x: r * dlon, y: 0)
        }
        let theta = Geo.asinz(2 * abs(phi / Double.pi))
        if abs(dlon) <= Geo.epsln || abs(abs(phi) - Geo.halfPi) <= Geo.epsln {
            let y = Double.pi * r * tan(0.5 * theta) * (phi >= 0 ? 1 : -1)
            return CGPoint(x: 0, y: y)
        }
        let al = 0.5 * abs((Double.pi / dlon) - (dlon / Double.pi))
        let asq = al * al
        let sinth = sin(theta)
        let costh = cos(theta)

        let g = costh / (sinth + costh - 1)
        let gsq = g * g
        let m = g * (2 / sinth - 1)
        let msq = m * m
        var con =
            Double.pi * r * (al * (g - msq) + (asq * (g - msq) * (g - msq) - (msq + asq) * (gsq - msq)).squareRoot())
            / (msq + asq)
        if dlon < 0 { con = -con }
        let x = con
        let q = asq + g
        con = Double.pi * r * (m * q - al * ((msq + asq) * (asq + 1) - q * q).squareRoot()) / (msq + asq)
        let y = phi >= 0 ? con : -con
        return CGPoint(x: x, y: y)
    }

    func inverse(x: Double, y: Double) -> Coordinate? {
        let con = Double.pi * r
        let xx = x / con
        let yy = y / con
        let xys = xx * xx + yy * yy
        let c1 = -abs(yy) * (1 + xys)
        let c2 = c1 - 2 * yy * yy + xx * xx
        let c3 = -2 * c1 + 1 + 2 * yy * yy + xys * xys
        let d = yy * yy / c3 + (2 * c2 * c2 * c2 / c3 / c3 / c3 - 9 * c1 * c2 / c3 / c3) / 27
        let a1 = (c1 - c2 * c2 / 3 / c3) / c3
        let m1 = 2 * (-a1 / 3).squareRoot()
        var c = ((3 * d) / a1) / m1
        if abs(c) > 1 { c = c >= 0 ? 1 : -1 }
        let th1 = acos(c) / 3
        let lat =
            y >= 0
            ? (-m1 * cos(th1 + Double.pi / 3) - c2 / 3 / c3) * Double.pi
            : -(-m1 * cos(th1 + Double.pi / 3) - c2 / 3 / c3) * Double.pi

        let lon: Double
        if abs(xx) < Geo.epsln {
            lon = long0
        } else {
            lon = Geo.adjustLon(
                long0 + Double.pi * (xys - 1 + (1 + 2 * (xx * xx - yy * yy) + xys * xys).squareRoot()) / 2 / xx)
        }
        guard lat.isFinite, lon.isFinite else { return nil }
        return Coordinate(lat: lat * Geo.r2d, lng: lon * Geo.r2d)
    }
}
