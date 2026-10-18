// Vendored dari https://github.com/spilneo/DotMap (MIT).
// Salinan, bukan modul: `Package.swift` upstream memakai swift-tools 5.9,
// sedangkan proyek ini dibangun dengan Xcode 14.3.1 (Swift 5.8) yang
// tidak bisa mengurai manifest itu. Yang diubah hanya `Bundle.module`
// -> `Bundle.main` (sumber dayageo ada di bundle app, bukan SPM).
// `IPLocationService` sengaja TIDAK ikut: ia memanggil ipwho.is /
// ipinfo.io, jadi menyertakan IP user ke pihak ketiga.
#if canImport(SwiftUI)
import CoreGraphics
import SwiftUI

// MARK: - Layout

/// Converts map units (0…width, 0…height) to view points for a given size.
public struct MapLayout: Sendable {
    public let scale: Double
    public let offsetX: Double
    public let offsetY: Double
    public let mapWidth: Double
    public let mapHeight: Double

    public init(scale: Double, offsetX: Double, offsetY: Double, mapWidth: Double, mapHeight: Double) {
        self.scale = scale
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.mapWidth = mapWidth
        self.mapHeight = mapHeight
    }

    public var transform: CGAffineTransform {
        CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: offsetX, ty: offsetY)
    }

    public func point(x: Double, y: Double) -> CGPoint {
        CGPoint(x: offsetX + x * scale, y: offsetY + y * scale)
    }
}

public extension DottedMap {
    /// Aspect-fit layout for the map inside `size`.
    ///
    /// `zoom` multiplies the fitted scale (1 = exactly fit, 2 = twice as big),
    /// and `pan` shifts the result in points.
    func layout(in size: CGSize, zoom: Double = 1, pan: CGSize = .zero) -> MapLayout {
        guard width > 0, height > 0, size.width > 0, size.height > 0 else {
            return MapLayout(scale: 0, offsetX: 0, offsetY: 0, mapWidth: width, mapHeight: height)
        }
        let fit = min(size.width / width, size.height / height)
        let scale = fit * max(0.01, zoom)
        let drawnWidth = width * scale
        let drawnHeight = height * scale
        return MapLayout(
            scale: scale,
            offsetX: (size.width - drawnWidth) / 2 + pan.width,
            offsetY: (size.height - drawnHeight) / 2 + pan.height,
            mapWidth: width,
            mapHeight: height
        )
    }
}

// MARK: - Pins

/// A pin to draw on top of the dot grid.
///
/// LOCAL PATCH (D61): `id` is a `String`, not a random `UUID`.
///
/// `ForEach` identifies rows by `id`, so a fresh UUID per render makes SwiftUI
/// tear down and rebuild the pin view every time. That resets its `@State
/// pulsing`, so the `repeatForever` halo animation restarts from zero on every
/// parent redraw — a permanent flicker plus a Core Animation re-allocation.
/// Callers pass a stable key (e.g. the node id).
public struct MapPin: Identifiable, Sendable {
    public let id: String
    public var lat: Double
    public var lng: Double
    public var color: Color
    /// Pin radius in map units (a grid dot uses `dotRadius`, default 0.22).
    public var radius: Double
    public var label: String?
    /// Active pins get a pulsing halo, like a live location indicator.
    public var isActive: Bool

    public init(
        id: String,
        lat: Double,
        lng: Double,
        color: Color,
        radius: Double = 0.4,
        label: String? = nil,
        isActive: Bool = false
    ) {
        self.id = id
        self.lat = lat
        self.lng = lng
        self.color = color
        self.radius = radius
        self.label = label
        self.isActive = isActive
    }

    public init(
        coordinate: Coordinate,
        id: String,
        color: Color,
        radius: Double = 0.4,
        label: String? = nil,
        isActive: Bool = false
    ) {
        self.init(
            id: id, lat: coordinate.lat, lng: coordinate.lng, color: color,
            radius: radius, label: label, isActive: isActive)
    }
}

// MARK: - DotMapView

/// A SwiftUI view that renders a `DottedMap` with `Canvas`.
///
/// ```swift
/// DotMapView(map: map, pins: [
///     MapPin(lat: 48.85, lng: 2.35, color: .green, isActive: true)
/// ])
/// ```
public struct DotMapView: View {
    public var map: DottedMap
    public var dotShape: DotShape
    /// Radius of a regular dot, in map units.
    public var dotRadius: Double
    public var dotColor: Color
    public var backgroundColor: Color
    public var pins: [MapPin]
    public var showsLabels: Bool
    /// On-screen size multiplier (1 = fit the available space).
    public var zoom: Double
    /// Pan offset in points, applied on top of the centered layout.
    public var pan: CGSize

    public init(
        map: DottedMap,
        dotShape: DotShape = .circle,
        dotRadius: Double = 0.24,
        dotColor: Color = Color(red: 0.26, green: 0.23, blue: 0.21),
        backgroundColor: Color = Color(red: 0.01, green: 0.012, blue: 0.004),
        pins: [MapPin] = [],
        showsLabels: Bool = true,
        zoom: Double = 1,
        pan: CGSize = .zero
    ) {
        self.map = map
        self.dotShape = dotShape
        self.dotRadius = dotRadius
        self.dotColor = dotColor
        self.backgroundColor = backgroundColor
        self.pins = pins
        self.showsLabels = showsLabels
        self.zoom = zoom
        self.pan = pan
    }

    public var body: some View {
        GeometryReader { proxy in
            let layout = map.layout(in: proxy.size, zoom: zoom, pan: pan)
            ZStack {
                backgroundColor
                Canvas { context, _ in
                    let path = DotPathCache.shared.path(for: map, radius: dotRadius, shape: dotShape)
                    context.transform = layout.transform
                    context.fill(path, with: .color(dotColor))
                }
                ForEach(pins) { pin in
                    if let snapped = map.getPin(lat: pin.lat, lng: pin.lng) {
                        MapPinView(
                            pin: pin,
                            anchor: layout.point(x: snapped.x, y: snapped.y),
                            scale: layout.scale,
                            showsLabel: showsLabels
                        )
                    }
                }
            }
        }
        .clipped()
    }
}

// MARK: - Pin rendering

private struct MapPinView: View {
    let pin: MapPin
    let anchor: CGPoint
    let scale: Double
    let showsLabel: Bool

    @State private var pulsing = false

    var body: some View {
        let diameter = max(5, pin.radius * 2 * scale)
        ZStack {
            if pin.isActive {
                Circle()
                    .stroke(pin.color.opacity(0.7), lineWidth: max(1, diameter * 0.08))
                    .frame(width: diameter, height: diameter)
                    .scaleEffect(pulsing ? 3.2 : 1)
                    .opacity(pulsing ? 0 : 0.9)
            }
            Circle()
                .fill(pin.color)
                .frame(width: diameter, height: diameter)
                .shadow(color: pin.color.opacity(0.8), radius: diameter * 0.7)
        }
        .overlay(alignment: .leading) {
            if showsLabel, let label = pin.label {
                Text(label)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(pin.color)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.black.opacity(0.55)))
                    .overlay(Capsule().stroke(pin.color.opacity(0.35), lineWidth: 0.5))
                    .offset(x: diameter + 14)
            }
        }
        .position(anchor)
        .onAppear {
            guard pin.isActive else { return }
            withAnimation(.easeOut(duration: 2.0).repeatForever(autoreverses: false)) {
                pulsing = true
            }
        }
    }
}

// MARK: - Path cache

/// Builds and caches the dot path in map coordinates so that resizing or
/// re-rendering the view never rebuilds thousands of ellipses.
final class DotPathCache {
    static let shared = DotPathCache()

    private struct Key: Hashable {
        let mapID: ObjectIdentifier
        let radius: Double
        let shape: DotShape
    }

    private var storage: [Key: Path] = [:]
    private var order: [Key] = []
    private let lock = NSLock()

    func path(for map: DottedMap, radius: Double, shape: DotShape) -> Path {
        let key = Key(mapID: ObjectIdentifier(map), radius: radius, shape: shape)
        lock.lock()
        defer { lock.unlock() }
        if let cached = storage[key] { return cached }

        let r = max(radius, 0.001)
        var path = Path()
        for point in map.points {
            switch shape {
            case .circle:
                path.addEllipse(in: CGRect(x: point.x - r, y: point.y - r, width: 2 * r, height: 2 * r))
            case .hexagon:
                let sqrt3radius = (3.0).squareRoot() * r
                let vertices: [CGPoint] = [
                    CGPoint(x: point.x + sqrt3radius, y: point.y - r),
                    CGPoint(x: point.x + sqrt3radius, y: point.y + r),
                    CGPoint(x: point.x, y: point.y + 2 * r),
                    CGPoint(x: point.x - sqrt3radius, y: point.y + r),
                    CGPoint(x: point.x - sqrt3radius, y: point.y - r),
                    CGPoint(x: point.x, y: point.y - 2 * r)
                ]
                path.move(to: vertices[0])
                for vertex in vertices.dropFirst() {
                    path.addLine(to: vertex)
                }
                path.closeSubpath()
            }
        }

        storage[key] = path
        order.append(key)
        while order.count > 8 {
            let oldest = order.removeFirst()
            storage[oldest] = nil
        }
        return path
    }
}
#endif
