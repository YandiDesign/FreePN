// Vendored dari https://github.com/spilneo/DotMap (MIT).
// Salinan, bukan modul: `Package.swift` upstream memakai swift-tools 5.9,
// sedangkan proyek ini dibangun dengan Xcode 14.3.1 (Swift 5.8) yang
// tidak bisa mengurai manifest itu. Yang diubah hanya `Bundle.module`
// -> `Bundle.main` (sumber dayageo ada di bundle app, bukan SPM).
// `IPLocationService` sengaja TIDAK ikut: ia memanggil ipwho.is /
// ipinfo.io, jadi menyertakan IP user ke pihak ketiga.
import CoreGraphics
import Foundation

// MARK: - Mercator

struct MercatorProjection: GeoProjection {
    let long0: Double
    var k0 = 1.0

    func forward(lat: Double, lng: Double) -> CGPoint? {
        if abs(abs(lat) - 90) <= Geo.epsln { return nil }
        let phi = lat * Geo.d2r
        let x = Geo.a * k0 * Geo.adjustLon(lng * Geo.d2r - long0)
        let ts = Geo.tsfnz(Geo.e, phi, sin(phi))
        let y = -Geo.a * k0 * log(ts)
        return CGPoint(x: x, y: y)
    }

    func inverse(x: Double, y: Double) -> Coordinate? {
        let ts = exp(-y / (Geo.a * k0))
        guard let lat = Geo.phi2z(Geo.e, ts) else { return nil }
        let lon = Geo.adjustLon(long0 + x / (Geo.a * k0))
        return Coordinate(lat: lat * Geo.r2d, lng: lon * Geo.r2d)
    }
}

// MARK: - Equirectangular (Plate Carrée)

struct EquirectangularProjection: GeoProjection {
    let long0: Double
    var lat0 = 0.0
    var rc = 1.0  // cos(lat_ts), lat_ts = 0

    func forward(lat: Double, lng: Double) -> CGPoint? {
        let dlon = Geo.adjustLon(lng * Geo.d2r - long0)
        let dlat = Geo.adjustLat(lat * Geo.d2r - lat0)
        return CGPoint(x: Geo.a * dlon * rc, y: Geo.a * dlat)
    }

    func inverse(x: Double, y: Double) -> Coordinate? {
        let lng = Geo.adjustLon(long0 + x / (Geo.a * rc))
        let lat = Geo.adjustLat(lat0 + y / Geo.a)
        return Coordinate(lat: lat * Geo.r2d, lng: lng * Geo.r2d)
    }
}

// MARK: - Miller

struct MillerProjection: GeoProjection {
    let long0: Double

    func forward(lat: Double, lng: Double) -> CGPoint? {
        let dlon = Geo.adjustLon(lng * Geo.d2r - long0)
        let x = Geo.a * dlon
        let y = Geo.a * log(tan(Geo.quarterPi + lat * Geo.d2r / 2.5)) * 1.25
        return CGPoint(x: x, y: y)
    }

    func inverse(x: Double, y: Double) -> Coordinate? {
        let lon = Geo.adjustLon(long0 + x / Geo.a)
        let lat = 2.5 * (atan(exp(0.8 * y / Geo.a)) - Geo.quarterPi)
        return Coordinate(lat: lat * Geo.r2d, lng: lon * Geo.r2d)
    }
}

// MARK: - Gall–Peters (cylindrical equal area, lat_ts = 45°)

struct GallPetersProjection: GeoProjection {
    let long0: Double
    private let k0: Double

    init(long0: Double) {
        self.long0 = long0
        let latTs = 45.0 * Geo.d2r
        self.k0 = Geo.msfnz(Geo.e, sin(latTs), cos(latTs))
    }

    func forward(lat: Double, lng: Double) -> CGPoint? {
        let dlon = Geo.adjustLon(lng * Geo.d2r - long0)
        let qs = Geo.qsfnz(Geo.e, sin(lat * Geo.d2r))
        let x = Geo.a * k0 * dlon
        let y = Geo.a * qs * 0.5 / k0
        return CGPoint(x: x, y: y)
    }

    func inverse(x: Double, y: Double) -> Coordinate? {
        guard let lat = Geo.iqsfnz(Geo.e, 2 * y * k0 / Geo.a) else { return nil }
        let lon = Geo.adjustLon(long0 + x / (Geo.a * k0))
        return Coordinate(lat: lat * Geo.r2d, lng: lon * Geo.r2d)
    }
}
