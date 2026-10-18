// Vendored dari https://github.com/spilneo/DotMap (MIT).
// Salinan, bukan modul: `Package.swift` upstream memakai swift-tools 5.9,
// sedangkan proyek ini dibangun dengan Xcode 14.3.1 (Swift 5.8) yang
// tidak bisa mengurai manifest itu. Yang diubah hanya `Bundle.module`
// -> `Bundle.main` (sumber dayageo ada di bundle app, bukan SPM).
// `IPLocationService` sengaja TIDAK ikut: ia memanggil ipwho.is /
// ipinfo.io, jadi menyertakan IP user ke pihak ketiga.
import CoreGraphics
import Foundation

// MARK: - Projection protocol

/// A map projection. Inputs and outputs are degrees; projected outputs are in
/// meters with the y axis pointing north.
public protocol GeoProjection: Sendable {
    func forward(lat: Double, lng: Double) -> CGPoint?
    func inverse(x: Double, y: Double) -> Coordinate?
}

enum ProjectionFactory {
    static func make(_ projection: Projection) -> GeoProjection {
        let lat0 = (projection.center?.lat ?? 0) * Geo.d2r
        let lng0 = (projection.center?.lng ?? 0) * Geo.d2r
        switch projection.name {
        case .mercator: return MercatorProjection(long0: lng0)
        case .equirectangular: return EquirectangularProjection(long0: lng0)
        case .robinson: return RobinsonProjection(long0: lng0)
        case .equalEarth: return EqualEarthProjection(long0: lng0)
        case .mollweide: return MollweideProjection(long0: lng0)
        case .miller: return MillerProjection(long0: lng0)
        case .sinusoidal: return SinusoidalProjection(long0: lng0)
        case .orthographic: return OrthographicProjection(lat0: lat0, long0: lng0)
        case .gallPeters: return GallPetersProjection(long0: lng0)
        case .vanDerGrinten: return VanDerGrintenProjection(long0: lng0)
        }
    }
}
