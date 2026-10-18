// Vendored dari https://github.com/spilneo/DotMap (MIT).
// Salinan, bukan modul: `Package.swift` upstream memakai swift-tools 5.9,
// sedangkan proyek ini dibangun dengan Xcode 14.3.1 (Swift 5.8) yang
// tidak bisa mengurai manifest itu. Yang diubah hanya `Bundle.module`
// -> `Bundle.main` (sumber dayageo ada di bundle app, bukan SPM).
// `IPLocationService` sengaja TIDAK ikut: ia memanggil ipwho.is /
// ipinfo.io, jadi menyertakan IP user ke pihak ketiga.
import CoreGraphics
import Foundation

// MARK: - Coordinates & regions

/// A WGS84 geographic coordinate, in degrees.
public struct Coordinate: Codable, Hashable, Sendable {
    public var lat: Double
    public var lng: Double

    public init(lat: Double, lng: Double) {
        self.lat = lat
        self.lng = lng
    }

    public init(latitude: Double, longitude: Double) {
        self.init(lat: latitude, lng: longitude)
    }

    public var latitude: Double { lat }
    public var longitude: Double { lng }
}

/// A lat/lng bounding box, mirroring the `region` option of `dotted-map`.
public struct Region: Codable, Hashable, Sendable {
    public struct Span: Codable, Hashable, Sendable {
        public var min: Double
        public var max: Double

        public init(min: Double, max: Double) {
            self.min = min
            self.max = max
        }
    }

    public var lat: Span
    public var lng: Span

    public init(lat: Span, lng: Span) {
        self.lat = lat
        self.lng = lng
    }

    public init(latMin: Double, latMax: Double, lngMin: Double, lngMax: Double) {
        self.lat = Span(min: latMin, max: latMax)
        self.lng = Span(min: lngMin, max: lngMax)
    }

    public static let world = Region(latMin: -56, latMax: 71, lngMin: -168, lngMax: 168)
}

// MARK: - Projections

/// The projections supported by `dotted-map`.
public enum ProjectionName: String, Codable, CaseIterable, Sendable {
    case mercator
    case equirectangular
    case robinson
    case equalEarth
    case mollweide
    case miller
    case sinusoidal
    case orthographic
    case gallPeters
    case vanDerGrinten

    public var displayName: String {
        switch self {
        case .mercator: return "Mercator"
        case .equirectangular: return "Equirectangular"
        case .robinson: return "Robinson"
        case .equalEarth: return "Equal Earth"
        case .mollweide: return "Mollweide"
        case .miller: return "Miller"
        case .sinusoidal: return "Sinusoidal"
        case .orthographic: return "Orthographic"
        case .gallPeters: return "Gall–Peters"
        case .vanDerGrinten: return "Van der Grinten"
        }
    }
}

public struct Projection: Codable, Hashable, Sendable {
    public var name: ProjectionName
    /// Optional projection center. Only `orthographic` uses `lat`; every
    /// projection uses `lng` (the `lon_0` parameter of proj4).
    public var center: Coordinate?

    public init(name: ProjectionName = .mercator, center: Coordinate? = nil) {
        self.name = name
        self.center = center
    }
}

// MARK: - Map settings

public enum Grid: String, Codable, CaseIterable, Sendable {
    case vertical
    case diagonal

    public var displayName: String {
        switch self {
        case .vertical: return "Vertical"
        case .diagonal: return "Diagonal"
        }
    }
}

public struct MapSettings: Hashable, Sendable {
    /// Map height in dots. If `width` is `0` the aspect ratio is derived from
    /// the projected region.
    public var height: Double
    /// Map width in dots. If `height` is `0` the aspect ratio is derived from
    /// the projected region.
    public var width: Double
    /// ISO 3166-1 alpha-3 country codes (e.g. `["FRA", "ITA"]`). Empty means
    /// the whole world.
    public var countries: [String]
    /// Optional explicit region. When `nil`, the region fits the countries (or
    /// the whole world).
    public var region: Region?
    public var grid: Grid
    public var projection: Projection
    /// Drop pins that fall outside the region/countries.
    public var avoidOuterPins: Bool

    public init(
        height: Double = 0,
        width: Double = 0,
        countries: [String] = [],
        region: Region? = nil,
        grid: Grid = .vertical,
        projection: Projection = Projection(),
        avoidOuterPins: Bool = false
    ) {
        self.height = height
        self.width = width
        self.countries = countries
        self.region = region
        self.grid = grid
        self.projection = projection
        self.avoidOuterPins = avoidOuterPins
    }
}

// MARK: - Points & pins

public enum DotShape: String, Codable, CaseIterable, Sendable {
    case circle
    case hexagon
}

/// Per-point SVG options, mirroring `svgOptions` in `dotted-map`.
public struct PinOptions: Codable, Hashable, Sendable {
    public var color: String?
    public var radius: Double?

    public init(color: String? = nil, radius: Double? = nil) {
        self.color = color
        self.radius = radius
    }
}

/// A raw point of the map, in map units (x grows right, y grows down).
public struct MapPoint: Hashable, Sendable {
    public var x: Double
    public var y: Double
    /// Snapped geographic position (pins only; grid points have no lat/lng).
    public var lat: Double?
    public var lng: Double?
    /// Optional string payload supplied with `addPin` (e.g. a place name).
    public var data: String?
    public var svgOptions: PinOptions?

    public init(
        x: Double,
        y: Double,
        lat: Double? = nil,
        lng: Double? = nil,
        data: String? = nil,
        svgOptions: PinOptions? = nil
    ) {
        self.x = x
        self.y = y
        self.lat = lat
        self.lng = lng
        self.data = data
        self.svgOptions = svgOptions
    }

    public var coordinate: Coordinate? {
        guard let lat, let lng else { return nil }
        return Coordinate(lat: lat, lng: lng)
    }
}

/// Input accepted by `DottedMap.addPin`.
public struct PinInput: Sendable {
    public var lat: Double
    public var lng: Double
    public var data: String?
    public var svgOptions: PinOptions?

    public init(lat: Double, lng: Double, data: String? = nil, svgOptions: PinOptions? = nil) {
        self.lat = lat
        self.lng = lng
        self.data = data
        self.svgOptions = svgOptions
    }

    public init(coordinate: Coordinate, data: String? = nil, svgOptions: PinOptions? = nil) {
        self.init(lat: coordinate.lat, lng: coordinate.lng, data: data, svgOptions: svgOptions)
    }
}

/// Options for `DottedMap.getSVG`.
public struct SvgSettings: Sendable {
    public var shape: DotShape
    public var color: String
    public var backgroundColor: String
    public var radius: Double

    public init(
        shape: DotShape = .circle,
        color: String = "current",
        backgroundColor: String = "transparent",
        radius: Double = 0.5
    ) {
        self.shape = shape
        self.color = color
        self.backgroundColor = backgroundColor
        self.radius = radius
    }
}

/// Metadata about the generated map, mirroring `map.image` in `dotted-map`.
public struct DotMapImage: Hashable, Sendable {
    public let region: Region
    public let width: Double
    public let height: Double

    public init(region: Region, width: Double, height: Double) {
        self.region = region
        self.width = width
        self.height = height
    }
}
