import CoreGraphics
import Foundation

/// Turns map geometry into `CGPath`s and keeps them around.
///
/// Paths are built in **projected** coordinates, not screen coordinates. Everything
/// the camera does after projection is affine, so a path built once stays valid
/// through any amount of panning, zooming and rotating — the renderer just supplies
/// `MapTransform.projectedToScreen` at draw time. Only a change of projection or
/// level of detail invalidates anything.
///
/// That is what makes 60 fps editing achievable: dragging the map re-strokes cached
/// paths instead of re-projecting ~50,000 vertices every frame.
public final class TerritoryPathCache: @unchecked Sendable {

    /// A path plus the projected-space box it occupies, so culling needs no
    /// `CGPath` bounding-box call per frame.
    public struct CachedPath {
        public let path: CGPath
        public let bounds: CGRect
    }

    private struct Key: Hashable {
        let id: String
        let lod: Int
        let projection: MapProjectionKind
    }

    private let lock = NSLock()
    private var territoryPaths: [Key: CachedPath] = [:]
    private var borderPaths: [Key: CachedPath] = [:]
    private let library: MapLibrary

    public init(library: MapLibrary = .shared) {
        self.library = library
    }

    // MARK: - Territories

    /// The outline of one territory unit in projected coordinates.
    public func territoryPath(unitID: String,
                              lod: LevelOfDetail,
                              projection: MapProjectionKind) throws -> CachedPath? {
        let key = Key(id: unitID, lod: lod.rawValue, projection: projection)

        lock.lock()
        if let hit = territoryPaths[key] {
            lock.unlock()
            return hit
        }
        lock.unlock()

        guard let multi = try library.geometry(lod: lod)[unitID] else { return nil }
        let built = Self.buildPath(from: multi, projection: projection)

        lock.lock()
        territoryPaths[key] = built
        lock.unlock()
        return built
    }

    /// Builds every territory path for a level of detail in one pass.
    ///
    /// Called when a project opens so the first frame is not a stutter of lazy
    /// misses. Returns the ids it managed to build.
    @discardableResult
    public func warm(lod: LevelOfDetail, projection: MapProjectionKind) throws -> [String] {
        let geometry = try library.geometry(lod: lod)
        var built: [Key: CachedPath] = [:]
        built.reserveCapacity(geometry.count)
        for (id, multi) in geometry {
            built[Key(id: id, lod: lod.rawValue, projection: projection)] =
                Self.buildPath(from: multi, projection: projection)
        }

        lock.lock()
        territoryPaths.merge(built) { _, new in new }
        lock.unlock()
        return geometry.keys.sorted()
    }

    // MARK: - Borders

    /// One border polyline as a path, keyed by its index in the borders array.
    public func borderPath(index: Int,
                           segment: BorderSegment,
                           lod: LevelOfDetail,
                           projection: MapProjectionKind) -> CachedPath {
        let key = Key(id: "border.\(index)", lod: lod.rawValue, projection: projection)

        lock.lock()
        if let hit = borderPaths[key] {
            lock.unlock()
            return hit
        }
        lock.unlock()

        let built = Self.buildPath(fromPolyline: segment.points, projection: projection)

        lock.lock()
        borderPaths[key] = built
        lock.unlock()
        return built
    }

    // MARK: - Cache control

    public func purge() {
        lock.lock()
        territoryPaths.removeAll()
        borderPaths.removeAll()
        lock.unlock()
    }

    /// Drops everything except the level of detail currently on screen — the response
    /// to a memory warning that does not cost a visible stutter.
    public func purge(keeping lod: LevelOfDetail) {
        lock.lock()
        territoryPaths = territoryPaths.filter { $0.key.lod == lod.rawValue }
        borderPaths = borderPaths.filter { $0.key.lod == lod.rawValue }
        lock.unlock()
    }

    public var cachedPathCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return territoryPaths.count + borderPaths.count
    }

    // MARK: - Building

    static func buildPath(from multi: GeoMultiPolygon,
                          projection: MapProjectionKind) -> CachedPath {
        let path = CGMutablePath()
        for polygon in multi.polygons {
            appendRing(polygon.exterior, to: path, projection: projection)
            // Holes are appended as ordinary subpaths; drawing with the even-odd
            // rule punches them out, which is how lakes and enclaves stay unfilled.
            for hole in polygon.holes {
                appendRing(hole, to: path, projection: projection)
            }
        }
        return CachedPath(path: path, bounds: path.isEmpty ? .null : path.boundingBoxOfPath)
    }

    static func buildPath(fromPolyline points: [GeoCoordinate],
                          projection: MapProjectionKind) -> CachedPath {
        let path = CGMutablePath()
        var started = false
        for coordinate in points {
            let p = projection.project(coordinate)
            let point = CGPoint(x: p.x, y: p.y)
            if started {
                path.addLine(to: point)
            } else {
                path.move(to: point)
                started = true
            }
        }
        return CachedPath(path: path, bounds: path.isEmpty ? .null : path.boundingBoxOfPath)
    }

    private static func appendRing(_ ring: GeoRing,
                                   to path: CGMutablePath,
                                   projection: MapProjectionKind) {
        guard ring.count >= 3 else { return }
        var started = false
        for coordinate in ring {
            let p = projection.project(coordinate)
            let point = CGPoint(x: p.x, y: p.y)
            if started {
                path.addLine(to: point)
            } else {
                path.move(to: point)
                started = true
            }
        }
        path.closeSubpath()
    }
}
