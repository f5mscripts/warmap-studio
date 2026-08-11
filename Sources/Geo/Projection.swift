import CoreGraphics
import Foundation

/// A point on the projected plane, in "projection units".
///
/// Both supported projections are scaled so that one unit of x equals one degree of
/// longitude at the equator, which keeps camera spans readable ("show 60° of Europe")
/// and makes the two projections interchangeable without rescaling the camera.
public struct ProjectedPoint: Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// How the globe is flattened.
///
/// This is a closed enum rather than a protocol on purpose: projecting runs per
/// vertex per frame, and an enum keeps that path free of existential dispatch. New
/// projections are added as cases here — the renderer needs no changes.
public enum MapProjectionKind: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Web Mercator. Angle-preserving, so country shapes look the way people expect.
    /// The default, and what almost every historical map video uses.
    case mercator
    /// Plate carrée. Longitude and latitude map straight to x and y. Useful for
    /// whole-world framing where Mercator's polar stretch is distracting.
    case equirectangular

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .mercator: return "Mercator"
        case .equirectangular: return "Equirectangular"
        }
    }

    /// Mercator diverges at the poles, so latitude is clamped before projecting.
    /// 85.051129° is the standard Web Mercator cut-off, where the projected map
    /// becomes exactly square.
    public var latitudeLimit: Double {
        switch self {
        case .mercator: return 85.051129
        case .equirectangular: return 90
        }
    }

    public func project(_ coordinate: GeoCoordinate) -> ProjectedPoint {
        let lat = min(max(coordinate.latitude, -latitudeLimit), latitudeLimit)
        switch self {
        case .equirectangular:
            return ProjectedPoint(x: coordinate.longitude, y: lat)
        case .mercator:
            let phi = lat * .pi / 180
            let y = log(tan(.pi / 4 + phi / 2)) * 180 / .pi
            return ProjectedPoint(x: coordinate.longitude, y: y)
        }
    }

    public func unproject(_ point: ProjectedPoint) -> GeoCoordinate {
        switch self {
        case .equirectangular:
            return GeoCoordinate(longitude: point.x,
                                 latitude: min(max(point.y, -90), 90))
        case .mercator:
            let phi = 2 * atan(exp(point.y * .pi / 180)) - .pi / 2
            return GeoCoordinate(longitude: point.x, latitude: phi * 180 / .pi)
        }
    }

    /// Projects a whole bounding box. Because both projections are monotonic in each
    /// axis independently, projecting the two corners is exact.
    public func project(_ bounds: GeoBounds) -> (min: ProjectedPoint, max: ProjectedPoint) {
        let lo = project(GeoCoordinate(longitude: bounds.minLongitude, latitude: bounds.minLatitude))
        let hi = project(GeoCoordinate(longitude: bounds.maxLongitude, latitude: bounds.maxLatitude))
        return (lo, hi)
    }
}

/// Where the camera is looking.
///
/// `span` is the width of the viewport measured in projection units, so a smaller
/// span means a closer camera. Storing span rather than a zoom level keeps
/// keyframe interpolation linear in something the user can reason about.
public struct MapCamera: Equatable, Codable, Sendable {
    public var center: GeoCoordinate
    public var span: Double
    /// Clockwise rotation in radians, applied about the viewport centre.
    public var rotation: Double

    public static let minimumSpan: Double = 0.05
    public static let maximumSpan: Double = 720

    public init(center: GeoCoordinate, span: Double, rotation: Double = 0) {
        self.center = center
        self.span = min(max(span, Self.minimumSpan), Self.maximumSpan)
        self.rotation = rotation
    }

    public static let world = MapCamera(
        center: GeoCoordinate(longitude: 0, latitude: 20), span: 360
    )

    /// Frames a bounding box inside a viewport, leaving `padding` as a fraction of
    /// the larger dimension.
    public static func fitting(_ bounds: GeoBounds,
                               in viewport: CGSize,
                               projection: MapProjectionKind = .mercator,
                               padding: Double = 0.08) -> MapCamera {
        guard viewport.width > 0, viewport.height > 0, !bounds.isEmpty else {
            return .world
        }
        let (lo, hi) = projection.project(bounds)
        let width = max(hi.x - lo.x, 1e-6)
        let height = max(hi.y - lo.y, 1e-6)
        let aspect = Double(viewport.width / viewport.height)
        // The span must cover the box horizontally *and* cover its height once the
        // viewport aspect is taken into account; the larger requirement wins.
        let span = max(width, height * aspect) * (1 + padding * 2)
        let centre = projection.unproject(
            ProjectedPoint(x: (lo.x + hi.x) / 2, y: (lo.y + hi.y) / 2)
        )
        return MapCamera(center: centre, span: span, rotation: 0)
    }

    /// Linear interpolation for camera keyframes.
    ///
    /// Span is interpolated geometrically rather than linearly: zooming from 360° to
    /// 4° linearly spends almost the whole animation crawling across the last few
    /// degrees, whereas a logarithmic ramp reads as a smooth, constant-rate zoom.
    public static func interpolate(_ a: MapCamera, _ b: MapCamera, _ t: Double) -> MapCamera {
        let clamped = min(max(t, 0), 1)
        let span = a.span * pow(b.span / a.span, clamped)
        // Take the shorter way around the antimeridian.
        var deltaLon = b.center.longitude - a.center.longitude
        if deltaLon > 180 { deltaLon -= 360 }
        if deltaLon < -180 { deltaLon += 360 }
        return MapCamera(
            center: GeoCoordinate(
                longitude: a.center.longitude + deltaLon * clamped,
                latitude: a.center.latitude + (b.center.latitude - a.center.latitude) * clamped
            ),
            span: span,
            rotation: a.rotation + (b.rotation - a.rotation) * clamped
        )
    }
}

/// An immutable camera + viewport pair that converts coordinates to screen points.
///
/// One transform is built per rendered frame and shared by every layer, which is
/// what keeps the on-screen preview and the exported video pixel-identical: the
/// export renders the same frames through the same transform at a different size.
public struct MapTransform: Equatable, Sendable {
    public let projection: MapProjectionKind
    public let camera: MapCamera
    public let viewport: CGSize

    /// Screen points per projection unit.
    public let scale: Double
    private let originX: Double
    private let originY: Double
    private let cosR: Double
    private let sinR: Double

    public init(projection: MapProjectionKind, camera: MapCamera, viewport: CGSize) {
        self.projection = projection
        self.camera = camera
        self.viewport = viewport
        self.scale = viewport.width > 0 ? Double(viewport.width) / camera.span : 1
        let c = projection.project(camera.center)
        self.originX = c.x
        self.originY = c.y
        self.cosR = cos(camera.rotation)
        self.sinR = sin(camera.rotation)
    }

    public func point(for coordinate: GeoCoordinate) -> CGPoint {
        point(forProjected: projection.project(coordinate))
    }

    /// Faster path for callers that already hold projected geometry.
    public func point(forProjected p: ProjectedPoint) -> CGPoint {
        let dx = (p.x - originX) * scale
        // Screen y grows downwards while projected y grows north, hence the flip.
        let dy = -(p.y - originY) * scale
        let rx = dx * cosR - dy * sinR
        let ry = dx * sinR + dy * cosR
        return CGPoint(x: rx + Double(viewport.width) / 2,
                       y: ry + Double(viewport.height) / 2)
    }

    public func coordinate(for point: CGPoint) -> GeoCoordinate {
        let dx = Double(point.x) - Double(viewport.width) / 2
        let dy = Double(point.y) - Double(viewport.height) / 2
        // Undo the rotation, then the scale and the y flip.
        let ux = dx * cosR + dy * sinR
        let uy = -dx * sinR + dy * cosR
        return projection.unproject(
            ProjectedPoint(x: ux / scale + originX, y: -uy / scale + originY)
        )
    }

    /// The geographic box the viewport currently shows.
    ///
    /// Under rotation the visible region is a rotated rectangle, so this returns the
    /// axis-aligned box that contains it — deliberately generous, because it is used
    /// to decide what to *skip* drawing and a too-small box would cull visible land.
    public var visibleBounds: GeoBounds {
        let corners = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: viewport.width, y: 0),
            CGPoint(x: 0, y: viewport.height),
            CGPoint(x: viewport.width, y: viewport.height),
        ]
        var bounds = GeoBounds.empty
        for corner in corners {
            bounds.expand(toInclude: coordinate(for: corner))
        }
        return bounds
    }

    /// How many projection units one screen point covers — the yardstick for
    /// choosing a level of detail.
    public var unitsPerPoint: Double { scale > 0 ? 1 / scale : .infinity }

    /// The projected-space → screen-space mapping as a single affine transform.
    ///
    /// Projection itself is non-linear, but everything the camera does afterwards —
    /// translate, scale, flip, rotate — is affine. That is what lets the renderer
    /// build each territory's `CGPath` once in projected units and then just hand
    /// Core Graphics a transform: panning and zooming never rebuild a path, and an
    /// export reuses the same paths for every frame.
    public var projectedToScreen: CGAffineTransform {
        var t = CGAffineTransform(translationX: CGFloat(-originX), y: CGFloat(-originY))
        t = t.concatenating(CGAffineTransform(scaleX: CGFloat(scale), y: CGFloat(-scale)))
        if camera.rotation != 0 {
            t = t.concatenating(CGAffineTransform(rotationAngle: CGFloat(camera.rotation)))
        }
        return t.concatenating(CGAffineTransform(translationX: viewport.width / 2,
                                                 y: viewport.height / 2))
    }

    /// The projected-space rectangle the viewport covers, for culling paths whose
    /// own projected bounds fall outside it.
    public var visibleProjectedRect: CGRect {
        let corners = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: viewport.width, y: 0),
            CGPoint(x: 0, y: viewport.height),
            CGPoint(x: viewport.width, y: viewport.height),
        ].map { screenPoint -> CGPoint in
            let dx = Double(screenPoint.x) - Double(viewport.width) / 2
            let dy = Double(screenPoint.y) - Double(viewport.height) / 2
            let ux = dx * cosR + dy * sinR
            let uy = -dx * sinR + dy * cosR
            return CGPoint(x: ux / scale + originX, y: -uy / scale + originY)
        }
        var minX = CGFloat.infinity, minY = CGFloat.infinity
        var maxX = -CGFloat.infinity, maxY = -CGFloat.infinity
        for c in corners {
            minX = Swift.min(minX, c.x); maxX = Swift.max(maxX, c.x)
            minY = Swift.min(minY, c.y); maxY = Swift.max(maxY, c.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
