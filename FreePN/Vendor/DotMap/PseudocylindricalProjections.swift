// Vendored dari https://github.com/spilneo/DotMap (MIT).
// Salinan, bukan modul: `Package.swift` upstream memakai swift-tools 5.9,
// sedangkan proyek ini dibangun dengan Xcode 14.3.1 (Swift 5.8) yang
// tidak bisa mengurai manifest itu. Yang diubah hanya `Bundle.module`
// -> `Bundle.main` (sumber dayageo ada di bundle app, bukan SPM).
// `IPLocationService` sengaja TIDAK ikut: ia memanggil ipwho.is /
// ipinfo.io, jadi menyertakan IP user ke pihak ketiga.
import CoreGraphics
import Foundation

// MARK: - Robinson

struct RobinsonProjection: GeoProjection {
    let long0: Double

    private static let coefsX: [[Double]] = [
        [1.0000, 2.2199e-17, -7.15515e-05, 3.1103e-06],
        [0.9986, -0.000482243, -2.4897e-05, -1.3309e-06],
        [0.9954, -0.00083103, -4.48605e-05, -9.86701e-07],
        [0.9900, -0.00135364, -5.9661e-05, 3.6777e-06],
        [0.9822, -0.00167442, -4.49547e-06, -5.72411e-06],
        [0.9730, -0.00214868, -9.03571e-05, 1.8736e-08],
        [0.9600, -0.00305085, -9.00761e-05, 1.64917e-06],
        [0.9427, -0.00382792, -6.53386e-05, -2.6154e-06],
        [0.9216, -0.00467746, -0.00010457, 4.81243e-06],
        [0.8962, -0.00536223, -3.23831e-05, -5.43432e-06],
        [0.8679, -0.00609363, -0.000113898, 3.32484e-06],
        [0.8350, -0.00698325, -6.40253e-05, 9.34959e-07],
        [0.7986, -0.00755338, -5.00009e-05, 9.35324e-07],
        [0.7597, -0.00798324, -3.5971e-05, -2.27626e-06],
        [0.7186, -0.00851367, -7.01149e-05, -8.6303e-06],
        [0.6732, -0.00986209, -0.000199569, 1.91974e-05],
        [0.6213, -0.010418, 8.83923e-05, 6.24051e-06],
        [0.5722, -0.00906601, 0.000182, 6.24051e-06],
        [0.5322, -0.00677797, 0.000275608, 6.24051e-06]
    ]

    private static let coefsY: [[Double]] = [
        [-5.20417e-18, 0.0124, 1.21431e-18, -8.45284e-11],
        [0.0620, 0.0124, -1.26793e-09, 4.22642e-10],
        [0.1240, 0.0124, 5.07171e-09, -1.60604e-09],
        [0.1860, 0.0123999, -1.90189e-08, 6.00152e-09],
        [0.2480, 0.0124002, 7.10039e-08, -2.24e-08],
        [0.3100, 0.0123992, -2.64997e-07, 8.35986e-08],
        [0.3720, 0.0124029, 9.88983e-07, -3.11994e-07],
        [0.4340, 0.0123893, -3.69093e-06, -4.35621e-07],
        [0.4958, 0.0123198, -1.02252e-05, -3.45523e-07],
        [0.5571, 0.0121916, -1.54081e-05, -5.82288e-07],
        [0.6176, 0.0119938, -2.41424e-05, -5.25327e-07],
        [0.6769, 0.011713, -3.20223e-05, -5.16405e-07],
        [0.7346, 0.0113541, -3.97684e-05, -6.09052e-07],
        [0.7903, 0.0109107, -4.89042e-05, -1.04739e-06],
        [0.8435, 0.0103431, -6.4615e-05, -1.40374e-09],
        [0.8936, 0.00969686, -6.4636e-05, -8.547e-06],
        [0.9394, 0.00840947, -0.000192841, -4.2106e-06],
        [0.9761, 0.00616527, -0.000256, -4.2106e-06],
        [1.0000, 0.00328947, -0.000319159, -4.2106e-06]
    ]

    private static let fxc = 0.8487
    private static let fyc = 1.3523
    private static let c1 = Geo.r2d / 5
    private static let rc1 = 1 / c1
    private static let nodes = 18

    private static func poly3(_ coefs: [Double], _ x: Double) -> Double {
        coefs[0] + x * (coefs[1] + x * (coefs[2] + x * coefs[3]))
    }

    private static func poly3Derivative(_ coefs: [Double], _ x: Double) -> Double {
        coefs[1] + x * (2 * coefs[2] + x * 3 * coefs[3])
    }

    func forward(lat: Double, lng: Double) -> CGPoint? {
        let lon = Geo.adjustLon(lng * Geo.d2r - long0)
        var dphi = abs(lat * Geo.d2r)
        var i = Int(floor(dphi * Self.c1))
        if i < 0 { i = 0 } else if i >= Self.nodes { i = Self.nodes - 1 }
        dphi = Geo.r2d * (dphi - Self.rc1 * Double(i))
        var x = Self.poly3(Self.coefsX[i], dphi) * lon
        var y = Self.poly3(Self.coefsY[i], dphi)
        if lat < 0 { y = -y }
        x *= Geo.a * Self.fxc
        y *= Geo.a * Self.fyc
        return CGPoint(x: x, y: y)
    }

    func inverse(x: Double, y: Double) -> Coordinate? {
        var lon = x / (Geo.a * Self.fxc)
        let latAbs = abs(y) / (Geo.a * Self.fyc)
        var lat: Double
        if latAbs >= 1 {
            lon /= Self.coefsX[Self.nodes][0]
            lat = y < 0 ? -Geo.halfPi : Geo.halfPi
        } else {
            var i = Int(floor(latAbs * Double(Self.nodes)))
            if i < 0 { i = 0 } else if i >= Self.nodes { i = Self.nodes - 1 }
            while i > 0 && Self.coefsY[i][0] > latAbs { i -= 1 }
            while i < Self.nodes - 1 && Self.coefsY[i + 1][0] <= latAbs { i += 1 }
            let coefs = Self.coefsY[i]
            var t = 5 * (latAbs - coefs[0]) / (Self.coefsY[i + 1][0] - coefs[0])
            for _ in 0..<100 {
                let upd = (Self.poly3(coefs, t) - latAbs) / Self.poly3Derivative(coefs, t)
                t -= upd
                if abs(upd) < Geo.epsln { break }
            }
            lon /= Self.poly3(Self.coefsX[i], t)
            lat = (5 * Double(i) + t) * Geo.d2r
            if y < 0 { lat = -lat }
        }
        return Coordinate(lat: lat * Geo.r2d, lng: Geo.adjustLon(lon + long0) * Geo.r2d)
    }
}

// MARK: - Equal Earth

struct EqualEarthProjection: GeoProjection {
    let long0: Double

    private static let a1 = 1.340264
    private static let a2 = -0.081106
    private static let a3 = 0.000893
    private static let a4 = 0.003796
    private static let m = (3.0).squareRoot() / 2

    private let apa: [Double]
    private let qp: Double
    private let rqda: Double

    init(long0: Double) {
        self.long0 = long0
        let qp = Geo.qsfnz(Geo.e, 1)
        self.apa = Geo.authset(Geo.es)
        self.qp = qp
        self.rqda = (0.5 * qp).squareRoot()
    }

    func forward(lat: Double, lng: Double) -> CGPoint? {
        let lam = Geo.adjustLon(lng * Geo.d2r - long0)
        let phi = lat * Geo.d2r
        let sinphi = Geo.qsfnz(Geo.e, sin(phi)) / qp
        let p = asin(Self.m * sinphi)
        let p2 = p * p
        let p6 = p2 * p2 * p2
        var x = lam * cos(p) / (Self.m * (Self.a1 + 3 * Self.a2 * p2 + p6 * (7 * Self.a3 + 9 * Self.a4 * p2)))
        var y = p * (Self.a1 + Self.a2 * p2 + p6 * (Self.a3 + Self.a4 * p2))
        x *= rqda
        y *= rqda
        return CGPoint(x: Geo.a * x, y: Geo.a * y)
    }

    func inverse(x: Double, y: Double) -> Coordinate? {
        var xx = x / Geo.a / rqda
        var yy = y / Geo.a / rqda

        var p = yy
        for _ in 0..<12 {
            let p2 = p * p
            let p6 = p2 * p2 * p2
            let fy = p * (Self.a1 + Self.a2 * p2 + p6 * (Self.a3 + Self.a4 * p2)) - yy
            let fpy = Self.a1 + 3 * Self.a2 * p2 + p6 * (7 * Self.a3 + 9 * Self.a4 * p2)
            let dlat = fy / fpy
            p -= dlat
            if abs(dlat) < 1e-9 { break }
        }
        let p2 = p * p
        let p6 = p2 * p2 * p2
        xx = Self.m * xx * (Self.a1 + 3 * Self.a2 * p2 + p6 * (7 * Self.a3 + 9 * Self.a4 * p2)) / cos(p)
        yy = asin(sin(p) / Self.m)
        yy = Geo.authlat(yy, apa)
        let lng = Geo.adjustLon(xx + long0)
        return Coordinate(lat: yy * Geo.r2d, lng: lng * Geo.r2d)
    }
}

// MARK: - Mollweide

struct MollweideProjection: GeoProjection {
    let long0: Double

    func forward(lat: Double, lng: Double) -> CGPoint? {
        var deltaLon = Geo.adjustLon(lng * Geo.d2r - long0)
        let phi = lat * Geo.d2r
        var theta = phi
        let con = Double.pi * sin(phi)
        for _ in 0..<100 {
            let deltaTheta = -(theta + sin(theta) - con) / (1 + cos(theta))
            theta += deltaTheta
            if abs(deltaTheta) < Geo.epsln { break }
        }
        theta /= 2
        if Double.pi / 2 - abs(phi) < Geo.epsln { deltaLon = 0 }
        let x = 0.900316316158 * Geo.a * deltaLon * cos(theta)
        let y = 1.4142135623731 * Geo.a * sin(theta)
        return CGPoint(x: x, y: y)
    }

    func inverse(x: Double, y: Double) -> Coordinate? {
        var arg = y / (1.4142135623731 * Geo.a)
        if abs(arg) > 0.999999999999 { arg = arg < 0 ? -0.999999999999 : 0.999999999999 }
        let theta = asin(arg)
        var lon = Geo.adjustLon(long0 + (x / (0.900316316158 * Geo.a * cos(theta))))
        if lon < -Double.pi { lon = -Double.pi }
        if lon > Double.pi { lon = Double.pi }
        arg = (2 * theta + sin(2 * theta)) / Double.pi
        if abs(arg) > 1 { arg = 1 }
        let lat = asin(arg)
        return Coordinate(lat: lat * Geo.r2d, lng: lon * Geo.r2d)
    }
}

// MARK: - Sinusoidal

struct SinusoidalProjection: GeoProjection {
    let long0: Double
    private let en: [Double]

    init(long0: Double) {
        self.long0 = long0
        self.en = Geo.enfn(Geo.es)
    }

    func forward(lat: Double, lng: Double) -> CGPoint? {
        let lon = Geo.adjustLon(lng * Geo.d2r - long0)
        let phi = lat * Geo.d2r
        let s = sin(phi)
        let c = cos(phi)
        let y = Geo.a * Geo.mlfn(phi, s, c, en)
        let x = Geo.a * lon * c / (1 - Geo.es * s * s).squareRoot()
        return CGPoint(x: x, y: y)
    }

    func inverse(x: Double, y: Double) -> Coordinate? {
        let lat = Geo.invMlfn(y / Geo.a, Geo.es, en)
        var lon = long0
        if abs(lat) < Geo.halfPi {
            let s = sin(lat)
            lon = long0 + x * (1 - Geo.es * s * s).squareRoot() / (Geo.a * cos(lat))
        }
        return Coordinate(lat: lat * Geo.r2d, lng: Geo.adjustLon(lon) * Geo.r2d)
    }
}
