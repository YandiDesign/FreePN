// Vendored dari https://github.com/spilneo/DotMap (MIT).
// Salinan, bukan modul: `Package.swift` upstream memakai swift-tools 5.9,
// sedangkan proyek ini dibangun dengan Xcode 14.3.1 (Swift 5.8) yang
// tidak bisa mengurai manifest itu. Yang diubah hanya `Bundle.module`
// -> `Bundle.main` (sumber dayageo ada di bundle app, bukan SPM).
// `IPLocationService` sengaja TIDAK ikut: ia memanggil ipwho.is /
// ipinfo.io, jadi menyertakan IP user ke pihak ketiga.
import Foundation

// MARK: - Geodesy helpers (faithful ports of proj4js' common helpers)

enum Geo {
    /// WGS84 semi-major axis (proj4 `+datum=WGS84`).
    static let a = 6_378_137.0
    /// WGS84 first eccentricity squared.
    static let es = 0.0066943799901413165
    static let e = es.squareRoot()

    static let halfPi = Double.pi / 2
    static let quarterPi = Double.pi / 4
    static let twoPi = Double.pi * 2
    /// Slightly greater than π, from proj4js.
    static let spi = 3.14159265359
    static let epsln = 1e-10
    static let d2r = Double.pi / 180
    static let r2d = 180 / Double.pi

    static func sign(_ x: Double) -> Double { x < 0 ? -1 : 1 }

    static func adjustLon(_ x: Double) -> Double {
        abs(x) <= spi ? x : x - sign(x) * twoPi
    }

    static func adjustLat(_ x: Double) -> Double {
        abs(x) < halfPi ? x : x - sign(x) * Double.pi
    }

    static func asinz(_ x: Double) -> Double {
        asin(min(1, max(-1, x)))
    }

    /// Authalic latitude helper (proj4 `qsfnz`).
    static func qsfnz(_ eccent: Double, _ sinphi: Double) -> Double {
        if eccent > 1e-7 {
            let con = eccent * sinphi
            return (1 - eccent * eccent) * (sinphi / (1 - con * con) - (0.5 / eccent) * log((1 - con) / (1 + con)))
        }
        return 2 * sinphi
    }

    /// Inverse authalic latitude helper (proj4 `iqsfnz`).
    static func iqsfnz(_ eccent: Double, _ q: Double) -> Double? {
        let temp = 1 - (1 - eccent * eccent) / (2 * eccent) * log((1 - eccent) / (1 + eccent))
        if abs(abs(q) - temp) < 1e-6 {
            return q < 0 ? -halfPi : halfPi
        }
        var phi = asin(0.5 * q)
        for _ in 0..<30 {
            let sinPhi = sin(phi)
            let cosPhi = cos(phi)
            let con = eccent * sinPhi
            let dphi =
                pow(1 - con * con, 2) / (2 * cosPhi)
                * (q / (1 - eccent * eccent) - sinPhi / (1 - con * con) + 0.5 / eccent * log((1 - con) / (1 + con)))
            phi += dphi
            if abs(dphi) <= 1e-10 { return phi }
        }
        return nil
    }

    /// Small-circle scale factor (proj4 `msfnz`).
    static func msfnz(_ eccent: Double, _ sinphi: Double, _ cosphi: Double) -> Double {
        let con = eccent * sinphi
        return cosphi / (1 - con * con).squareRoot()
    }

    /// `tsfnz` used by the ellipsoidal Mercator.
    static func tsfnz(_ eccent: Double, _ phi: Double, _ sinphi: Double) -> Double {
        let con = eccent * sinphi
        let com = 0.5 * eccent
        let ratio = pow((1 - con) / (1 + con), com)
        return tan(0.5 * (halfPi - phi)) / ratio
    }

    /// `phi2z` used by the ellipsoidal Mercator inverse.
    static func phi2z(_ eccent: Double, _ ts: Double) -> Double? {
        let eccnth = 0.5 * eccent
        var phi = halfPi - 2 * atan(ts)
        for _ in 0...15 {
            let con = eccent * sin(phi)
            let dphi = halfPi - 2 * atan(ts * pow((1 - con) / (1 + con), eccnth)) - phi
            phi += dphi
            if abs(dphi) <= 1e-10 { return phi }
        }
        return nil
    }

    // MARK: Meridional distance (proj4 `pj_enfn` / `pj_mlfn` / `pj_inv_mlfn`)

    static func enfn(_ es: Double) -> [Double] {
        let c00 = 1.0, c02 = 0.25, c04 = 0.046875, c06 = 0.01953125, c08 = 0.01068115234375
        let c22 = 0.75
        let c44 = 0.46875, c46 = 0.01302083333333333333, c48 = 0.00712076822916666666
        let c66 = 0.36458333333333333333, c68 = 0.00569661458333333333
        let c88 = 0.3076171875

        var en = [Double](repeating: 0, count: 5)
        en[0] = c00 - es * (c02 + es * (c04 + es * (c06 + es * c08)))
        en[1] = es * (c22 - es * (c04 + es * (c06 + es * c08)))
        let t = es * es
        en[2] = t * (c44 - es * (c46 + es * c48))
        let t2 = t * es
        en[3] = t2 * (c66 - es * c68)
        en[4] = t2 * es * c88
        return en
    }

    static func mlfn(_ phi: Double, _ sphi: Double, _ cphi: Double, _ en: [Double]) -> Double {
        let c = cphi * sphi
        let s = sphi * sphi
        return en[0] * phi - c * (en[1] + s * (en[2] + s * (en[3] + s * en[4])))
    }

    static func invMlfn(_ arg: Double, _ es: Double, _ en: [Double]) -> Double {
        let k = 1 / (1 - es)
        var phi = arg
        for _ in 0..<20 {
            let s = sin(phi)
            let t = 1 - es * s * s
            let delta = (mlfn(phi, s, cos(phi), en) - arg) * (t * t.squareRoot()) * k
            phi -= delta
            if abs(delta) < epsln { return phi }
        }
        return phi
    }

    // MARK: Authalic latitude (proj4 `authset` / `authlat`)

    static func authset(_ es: Double) -> [Double] {
        let p00 = 0.33333333333333333333
        let p01 = 0.17222222222222222222
        let p02 = 0.10257936507936507936
        let p10 = 0.06388888888888888888
        let p11 = 0.06640211640211640211
        let p20 = 0.01641501294219154443

        var apa = [Double](repeating: 0, count: 3)
        apa[0] = es * p00
        var t = es * es
        apa[0] += t * p01
        apa[1] = t * p10
        t *= es
        apa[0] += t * p02
        apa[1] += t * p11
        apa[2] = t * p20
        return apa
    }

    static func authlat(_ beta: Double, _ apa: [Double]) -> Double {
        let t = beta + beta
        return beta + apa[0] * sin(t) + apa[1] * sin(t + t) + apa[2] * sin(t + t + t)
    }
}
