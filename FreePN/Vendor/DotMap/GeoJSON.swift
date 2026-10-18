// Vendored dari https://github.com/spilneo/DotMap (MIT).
// Salinan, bukan modul: `Package.swift` upstream memakai swift-tools 5.9,
// sedangkan proyek ini dibangun dengan Xcode 14.3.1 (Swift 5.8) yang
// tidak bisa mengurai manifest itu. Yang diubah hanya `Bundle.module`
// -> `Bundle.main` (sumber dayageo ada di bundle app, bukan SPM).
// `IPLocationService` sengaja TIDAK ikut: ia memanggil ipwho.is /
// ipinfo.io, jadi menyertakan IP user ke pihak ketiga.
import Foundation

// MARK: - Geometry

/// A closed ring of WGS84 coordinates with a cached bounding box.
struct GeoRing: Sendable {
    let coordinates: [Coordinate]
    let minLat: Double
    let maxLat: Double
    let minLng: Double
    let maxLng: Double

    init(coordinates: [Coordinate]) {
        var closed = coordinates
        if let first = closed.first, let last = closed.last, first != last {
            closed.append(first)
        }
        self.coordinates = closed
        self.minLat = closed.map(\.lat).min() ?? 0
        self.maxLat = closed.map(\.lat).max() ?? 0
        self.minLng = closed.map(\.lng).min() ?? 0
        self.maxLng = closed.map(\.lng).max() ?? 0
    }
}

/// A GeoJSON polygon: the first ring is the exterior, the rest are holes.
struct GeoPolygon: Sendable {
    let rings: [GeoRing]
    let minLat: Double
    let maxLat: Double
    let minLng: Double
    let maxLng: Double

    init(rings: [GeoRing]) {
        self.rings = rings
        if let outer = rings.first {
            self.minLat = rings.dropFirst().reduce(outer.minLat) { min($0, $1.minLat) }
            self.maxLat = rings.dropFirst().reduce(outer.maxLat) { max($0, $1.maxLat) }
            self.minLng = rings.dropFirst().reduce(outer.minLng) { min($0, $1.minLng) }
            self.maxLng = rings.dropFirst().reduce(outer.maxLng) { max($0, $1.maxLng) }
        } else {
            self.minLat = 0
            self.maxLat = 0
            self.minLng = 0
            self.maxLng = 0
        }
    }

    /// Point-in-polygon test with hole support, matching the semantics of
    /// `@turf/boolean-point-in-polygon` (points on the boundary are inside).
    ///
    /// The crossing-parity test is a port of `point-in-polygon-hao`, which turf
    /// uses under the hood.
    func contains(lat: Double, lng: Double) -> Bool {
        guard lng >= minLng, lng <= maxLng, lat >= minLat, lat <= maxLat else { return false }
        var crossings = 0
        for ring in rings {
            let points = ring.coordinates
            guard points.count > 2 else { continue }
            var u1 = points[0].lng - lng
            var v1 = points[0].lat - lat
            for index in 0..<(points.count - 1) {
                let u2 = points[index + 1].lng - lng
                let v2 = points[index + 1].lat - lat
                if v1 == 0 && v2 == 0 {
                    if (u2 <= 0 && u1 >= 0) || (u1 <= 0 && u2 >= 0) { return true }
                } else if (v2 >= 0 && v1 <= 0) || (v2 <= 0 && v1 >= 0) {
                    let f = u2 * v1 - u1 * v2
                    if f == 0 { return true }
                    if (f > 0 && v2 > 0 && v1 <= 0) || (f < 0 && v2 <= 0 && v1 > 0) {
                        crossings += 1
                    }
                }
                u1 = u2
                v1 = v2
            }
        }
        return crossings % 2 != 0
    }
}

extension Array where Element == GeoPolygon {
    func containsCoordinate(lat: Double, lng: Double) -> Bool {
        for polygon in self where polygon.contains(lat: lat, lng: lng) {
            return true
        }
        return false
    }

    var boundingRegion: Region? {
        guard let first = self.first else { return nil }
        var minLat = first.minLat
        var maxLat = first.maxLat
        var minLng = first.minLng
        var maxLng = first.maxLng
        for polygon in dropFirst() {
            minLat = Swift.min(minLat, polygon.minLat)
            maxLat = Swift.max(maxLat, polygon.maxLat)
            minLng = Swift.min(minLng, polygon.minLng)
            maxLng = Swift.max(maxLng, polygon.maxLng)
        }
        return Region(latMin: minLat, latMax: maxLat, lngMin: minLng, lngMax: maxLng)
    }
}

// MARK: - Decoding

private struct FeatureCollection: Decodable {
    let features: [FeatureJSON]
}

private struct FeatureJSON: Decodable {
    let id: String
    let properties: Properties
    let geometry: Geometry

    struct Properties: Decodable {
        let name: String
    }

    struct Geometry: Decodable {
        let polygons: [[[[Double]]]]

        private enum CodingKeys: String, CodingKey {
            case type
            case coordinates
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)
            switch type {
            case "Polygon":
                let coordinates = try container.decode([[[Double]]].self, forKey: .coordinates)
                self.polygons = [coordinates]
            case "MultiPolygon":
                self.polygons = try container.decode([[[[Double]]]].self, forKey: .coordinates)
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: .type,
                    in: container,
                    debugDescription: "Unsupported GeoJSON geometry type: \(type)"
                )
            }
        }
    }
}

// MARK: - World countries

/// The bundled `countries.geo.json` dataset (180 features, keyed by ISO
/// 3166-1 alpha-3 code), lazy-loaded from the package resources.
enum WorldGeoJSON {
    struct Feature: Sendable {
        let id: String
        let name: String
        let polygons: [GeoPolygon]
    }

    static let all: [Feature] = load()
    /// Note: the dataset contains two features with the id `-99`
    /// (Northern Cyprus and Somaliland); like the original library, the last
    /// one wins.
    static let byID: [String: Feature] = {
        var dictionary: [String: Feature] = [:]
        for feature in all {
            dictionary[feature.id] = feature
        }
        return dictionary
    }()

    static func features(for countryIDs: [String]) throws -> [Feature] {
        guard !countryIDs.isEmpty else { return all }
        var features: [Feature] = []
        var missing: [String] = []
        for id in countryIDs {
            if let feature = byID[id] {
                features.append(feature)
            } else {
                missing.append(id)
            }
        }
        if !missing.isEmpty {
            throw DotMapError.unknownCountries(missing)
        }
        return features
    }

    private static func load() -> [Feature] {
        guard let url = Bundle.main.url(forResource: "countries.geo.json", withExtension: nil) else {
            return []
        }
        do {
            let data = try Data(contentsOf: url)
            let collection = try JSONDecoder().decode(FeatureCollection.self, from: data)
            return collection.features.map { feature in
                let polygons = feature.geometry.polygons.map { rings in
                    GeoPolygon(
                        rings: rings.map { ring in
                            GeoRing(coordinates: ring.map { Coordinate(lat: $0[1], lng: $0[0]) })
                        })
                }
                return Feature(id: feature.id, name: feature.properties.name, polygons: polygons)
            }
        } catch {
            return []
        }
    }
}
