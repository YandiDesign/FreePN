// Vendored dari https://github.com/spilneo/DotMap (MIT).
// Salinan, bukan modul: `Package.swift` upstream memakai swift-tools 5.9,
// sedangkan proyek ini dibangun dengan Xcode 14.3.1 (Swift 5.8) yang
// tidak bisa mengurai manifest itu. Yang diubah hanya `Bundle.module`
// -> `Bundle.main` (sumber dayageo ada di bundle app, bukan SPM).
// `IPLocationService` sengaja TIDAK ikut: ia memanggil ipwho.is /
// ipinfo.io, jadi menyertakan IP user ke pihak ketiga.
import Foundation

// MARK: - Errors

public enum DotMapError: Error, LocalizedError, Equatable {
    case heightOrWidthRequired
    case unknownCountries([String])
    case noValidProjectedPoints
    case countriesDataMissing

    public var errorDescription: String? {
        switch self {
        case .heightOrWidthRequired:
            return "Either height or width must be greater than zero."
        case .unknownCountries(let ids):
            return "Unknown country code(s): \(ids.joined(separator: ", "))."
        case .noValidProjectedPoints:
            return "No valid projected points found for the given region and projection."
        case .countriesDataMissing:
            return "The bundled countries.geo.json resource could not be loaded."
        }
    }
}

// MARK: - Resolved grid

/// The precomputed grid, equivalent to the `MapData` object of `dotted-map`.
struct MapGrid: Sendable {
    var points: [MapPoint]
    var xMin: Double
    var yMin: Double
    var xMax: Double
    var yMax: Double
    var xRange: Double
    var yRange: Double
    var region: Region
    var grid: Grid
    var width: Double
    var height: Double
    var ystep: Double
    var projection: Projection
}

enum MapGridBuilder {
    /// The projected bounding box of the map region.
    private struct Bounds {
        let xMin: Double
        let yMin: Double
        let xMax: Double
        let yMax: Double

        var xRange: Double { xMax - xMin }
        var yRange: Double { yMax - yMin }
    }

    /// Resolved map geometry used to place the grid dots.
    private struct Layout {
        let width: Double
        let height: Double
        let bounds: Bounds
        let ystep: Double
    }

    static func build(_ settings: MapSettings) throws -> MapGrid {
        guard settings.height > 0 || settings.width > 0 else {
            throw DotMapError.heightOrWidthRequired
        }
        guard !WorldGeoJSON.all.isEmpty else {
            throw DotMapError.countriesDataMissing
        }

        // Resolve countries and region, exactly like the original library.
        let impl = ProjectionFactory.make(settings.projection)
        let polygons = try WorldGeoJSON.features(for: settings.countries).flatMap(\.polygons)
        let region = try resolveRegion(settings: settings, polygons: polygons)
        let bounds = try projectedBounds(region: region, impl: impl)
        let size = try resolveSize(settings: settings, bounds: bounds)
        let ystep = settings.grid == .diagonal ? (3.0).squareRoot() / 2 : 1
        let layout = Layout(width: size.width, height: size.height, bounds: bounds, ystep: ystep)
        let points = gridPoints(settings: settings, layout: layout, impl: impl, polygons: polygons)

        return MapGrid(
            points: points,
            xMin: bounds.xMin,
            yMin: bounds.yMin,
            xMax: bounds.xMax,
            yMax: bounds.yMax,
            xRange: bounds.xRange,
            yRange: bounds.yRange,
            region: region,
            grid: settings.grid,
            width: size.width,
            height: size.height,
            ystep: ystep,
            projection: settings.projection
        )
    }

    private static func resolveRegion(settings: MapSettings, polygons: [GeoPolygon]) throws -> Region {
        if let explicit = settings.region {
            return explicit
        }
        if !settings.countries.isEmpty {
            guard let fitted = polygons.boundingRegion else {
                throw DotMapError.unknownCountries(settings.countries)
            }
            return fitted
        }
        return .world
    }

    /// Computes the projected bounding box by sampling the region boundary
    /// and its diagonal. Some projections (e.g. orthographic) cannot project
    /// all corners, so non-finite samples are skipped.
    private static func projectedBounds(region: Region, impl: GeoProjection) throws -> Bounds {
        let samples = 100
        var xMin = Double.infinity
        var yMin = Double.infinity
        var xMax = -Double.infinity
        var yMax = -Double.infinity

        for index in 0...samples {
            let fraction = Double(index) / Double(samples)
            let sampleLat = region.lat.min + fraction * (region.lat.max - region.lat.min)
            let sampleLng = region.lng.min + fraction * (region.lng.max - region.lng.min)
            let candidates: [(lat: Double, lng: Double)] = [
                (region.lat.min, sampleLng),
                (region.lat.max, sampleLng),
                (sampleLat, region.lng.min),
                (sampleLat, region.lng.max),
                (sampleLat, sampleLng)
            ]
            for candidate in candidates {
                guard let projected = impl.forward(lat: candidate.lat, lng: candidate.lng) else { continue }
                xMin = min(xMin, projected.x)
                yMin = min(yMin, projected.y)
                xMax = max(xMax, projected.x)
                yMax = max(yMax, projected.y)
            }
        }

        guard xMin.isFinite, yMin.isFinite, xMax.isFinite, yMax.isFinite else {
            throw DotMapError.noValidProjectedPoints
        }
        return Bounds(xMin: xMin, yMin: yMin, xMax: xMax, yMax: yMax)
    }

    private static func resolveSize(settings: MapSettings, bounds: Bounds) throws -> (width: Double, height: Double) {
        var width = settings.width
        var height = settings.height
        if width <= 0 {
            width = (height * bounds.xRange / bounds.yRange).rounded()
        } else if height <= 0 {
            height = (width * bounds.yRange / bounds.xRange).rounded()
        }
        guard width > 0, height > 0 else { throw DotMapError.heightOrWidthRequired }
        return (width, height)
    }

    private static func gridPoints(
        settings: MapSettings,
        layout: Layout,
        impl: GeoProjection,
        polygons: [GeoPolygon]
    ) -> [MapPoint] {
        let grid = settings.grid
        var points: [MapPoint] = []
        var y = 0.0
        while y * layout.ystep < layout.height {
            var x = 0.0
            while x < layout.width {
                let localx = (Int(y) % 2 == 0 && grid == .diagonal) ? x + 0.5 : x
                let localy = y * layout.ystep
                let projectedX = (localx / layout.width) * layout.bounds.xRange + layout.bounds.xMin
                let projectedY = layout.bounds.yMax - (localy / layout.height) * layout.bounds.yRange
                if let wgs84 = impl.inverse(x: projectedX, y: projectedY),
                    polygons.containsCoordinate(lat: wgs84.lat, lng: wgs84.lng)
                {
                    points.append(MapPoint(x: localx, y: localy))
                }
                x += 1
            }
            y += 1
        }
        return points
    }
}

// MARK: - Cache

/// Grids are expensive to compute, exactly like in `dotted-map`, so they are
/// cached by settings. Pins are not part of the cache.
enum MapGridCache {
    struct Key: Hashable {
        let height: Double
        let width: Double
        let countries: [String]
        let region: Region?
        let grid: Grid
        let projection: Projection

        init(_ settings: MapSettings) {
            self.height = settings.height
            self.width = settings.width
            self.countries = settings.countries
            self.region = settings.region
            self.grid = settings.grid
            self.projection = settings.projection
        }
    }

    private static var storage: [Key: MapGrid] = [:]
    private static var order: [Key] = []
    private static let lock = NSLock()

    static func grid(for settings: MapSettings) throws -> MapGrid {
        let key = Key(settings)
        lock.lock()
        defer { lock.unlock() }
        if let cached = storage[key] { return cached }
        let grid = try MapGridBuilder.build(settings)
        storage[key] = grid
        order.append(key)
        while order.count > 16 {
            let oldest = order.removeFirst()
            storage[oldest] = nil
        }
        return grid
    }

    static func clear() {
        lock.lock()
        defer { lock.unlock() }
        storage.removeAll()
        order.removeAll()
    }
}

// MARK: - DottedMap

/// A native Swift port of the `dotted-map` library.
///
/// ```swift
/// let map = try DottedMap(settings: MapSettings(height: 60, grid: .diagonal))
/// _ = map.addPin(PinInput(lat: 48.8534, lng: 2.3488))
/// ```
public final class DottedMap: @unchecked Sendable {
    private let map: MapGrid
    private let projectionImpl: GeoProjection
    private let polygons: [GeoPolygon]
    private let avoidOuterPins: Bool
    private let lock = NSLock()
    private var pins: [MapPoint] = []

    /// Metadata about the generated map, mirroring `map.image`.
    public let image: DotMapImage

    public init(settings: MapSettings) throws {
        let grid = try MapGridCache.grid(for: settings)
        self.map = grid
        self.projectionImpl = ProjectionFactory.make(grid.projection)
        self.avoidOuterPins = settings.avoidOuterPins

        // Only resolve the polygons when they are actually needed, to keep
        // map creation cheap when no country data is involved.
        if settings.avoidOuterPins {
            let features = (try? WorldGeoJSON.features(for: settings.countries)) ?? []
            self.polygons = features.flatMap(\.polygons)
        } else {
            self.polygons = []
        }

        self.image = DotMapImage(region: grid.region, width: grid.width, height: grid.height)
    }

    // MARK: Geometry

    public var width: Double { map.width }
    public var height: Double { map.height }
    public var region: Region { map.region }
    public var grid: Grid { map.grid }
    public var projection: Projection { map.projection }
    public var ystep: Double { map.ystep }

    /// The raw grid points (without pins), in map units.
    public var points: [MapPoint] { map.points }

    // MARK: Pins

    /// Snaps a geographic coordinate to the nearest dot of the grid,
    /// mirroring `getPin`. Returns `nil` when the projection cannot represent
    /// the coordinate.
    public func getPin(lat: Double, lng: Double) -> MapPoint? {
        guard let projected = projectionImpl.forward(lat: lat, lng: lng) else { return nil }
        if avoidOuterPins && !polygons.containsCoordinate(lat: lat, lng: lng) { return nil }

        var rawX = width * (projected.x - map.xMin) / map.xRange
        let rawY = height * (map.yMax - projected.y) / map.yRange
        guard rawX.isFinite, rawY.isFinite else { return nil }

        let yIndex = safeIndex((rawY / ystep).rounded())
        if yIndex % 2 == 0 && grid == .diagonal { rawX -= 0.5 }
        let xIndex = safeIndex(rawX.rounded())

        var localx = Double(xIndex)
        let localy = Double(yIndex) * ystep
        if yIndex % 2 == 0 && grid == .diagonal { localx += 0.5 }

        let projectedX = localx * map.xRange / width + map.xMin
        let projectedY = map.yMax - localy * map.yRange / height
        guard let wgs84 = projectionImpl.inverse(x: projectedX, y: projectedY),
            wgs84.lat.isFinite, wgs84.lng.isFinite
        else { return nil }

        return MapPoint(x: localx, y: localy, lat: wgs84.lat, lng: wgs84.lng)
    }

    /// Snaps and registers a pin, mirroring `addPin`. Returns `nil` when the
    /// coordinate cannot be represented (or is dropped by `avoidOuterPins`).
    @discardableResult
    public func addPin(_ input: PinInput) -> MapPoint? {
        guard let snapped = getPin(lat: input.lat, lng: input.lng) else { return nil }
        let pin = MapPoint(
            x: snapped.x,
            y: snapped.y,
            lat: snapped.lat,
            lng: snapped.lng,
            data: input.data,
            svgOptions: input.svgOptions
        )
        lock.lock()
        pins.append(pin)
        lock.unlock()
        return pin
    }

    /// All grid points followed by all pins, mirroring `getPoints`.
    public func getPoints() -> [MapPoint] {
        lock.lock()
        defer { lock.unlock() }
        return map.points + pins
    }

    /// The registered pins.
    public var registeredPins: [MapPoint] {
        lock.lock()
        defer { lock.unlock() }
        return pins
    }

    public func removeAllPins() {
        lock.lock()
        pins.removeAll()
        lock.unlock()
    }

    // MARK: SVG

    /// Renders the map as an SVG string, mirroring `getSVG`.
    public func getSVG(_ settings: SvgSettings = SvgSettings()) -> String {
        lock.lock()
        let pins = self.pins
        lock.unlock()

        func pointSVG(_ point: MapPoint) -> String {
            let pointRadius = point.svgOptions?.radius ?? settings.radius
            let color = point.svgOptions?.color ?? settings.color
            switch settings.shape {
            case .circle:
                return
                    "<circle cx=\"\(num(point.x))\" cy=\"\(num(point.y))\" r=\"\(num(pointRadius))\" fill=\"\(color)\" />"
            case .hexagon:
                let sqrt3radius = (3.0).squareRoot() * pointRadius
                let polyPoints: [(Double, Double)] = [
                    (point.x + sqrt3radius, point.y - pointRadius),
                    (point.x + sqrt3radius, point.y + pointRadius),
                    (point.x, point.y + 2 * pointRadius),
                    (point.x - sqrt3radius, point.y + pointRadius),
                    (point.x - sqrt3radius, point.y - pointRadius),
                    (point.x, point.y - 2 * pointRadius)
                ]
                let attribute = polyPoints.map { "\(num($0.0)),\(num($0.1))" }.joined(separator: " ")
                return "<polyline points=\"\(attribute)\" fill=\"\(color)\" />"
            }
        }

        let dots = map.points.map(pointSVG).joined(separator: "\n")
        let pinDots = pins.map(pointSVG).joined(separator: "\n")
        return
            "<svg viewBox=\"0 0 \(num(width)) \(num(height))\" xmlns=\"http://www.w3.org/2000/svg\" style=\"background-color: \(settings.backgroundColor)\">\n        \(dots)\n        \(pinDots)\n      </svg>"
    }

    private func safeIndex(_ value: Double) -> Int {
        Int(max(-1_000_000, min(1_000_000, value)))
    }

    private func num(_ value: Double) -> String {
        String(value)
    }
}
