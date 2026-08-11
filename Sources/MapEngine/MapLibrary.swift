import Foundation

/// Loads and caches the map data that ships inside the app bundle.
///
/// Territory metadata, cities and regions are small and always needed, so they load
/// together up front. Geometry and borders exist at three levels of detail and are
/// loaded on first use per level: a world-view project never pays to parse the
/// full-detail coastlines, and a zoomed-in one never parses the coarse ones.
///
/// Instances are immutable once a level is loaded, and access is serialised, so the
/// export renderer can pull geometry from a background thread while the editor draws.
public final class MapLibrary: @unchecked Sendable {

    public static let shared = MapLibrary()

    private let lock = NSLock()
    private var core: Core?
    private var geometryCache: [Int: [String: GeoMultiPolygon]] = [:]
    private var borderCache: [Int: [BorderSegment]] = [:]
    private let bundle: Bundle

    private struct Core {
        let units: [TerritoryUnit]
        let unitsByID: [String: TerritoryUnit]
        let cities: [City]
        let citiesByUnit: [String: [City]]
        let regions: [MapRegion]
    }

    public init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    // MARK: - Core data

    /// Parses territories, cities and regions. Safe to call repeatedly; the work
    /// happens once.
    @discardableResult
    private func loadCore() throws -> Core {
        lock.lock()
        defer { lock.unlock() }
        if let core { return core }

        let units: [TerritoryUnit] = try decode([TerritoryUnit].self, from: "territories")
        let cities: [City] = try decode([City].self, from: "cities")
        let regions: [MapRegion] = try decode([MapRegion].self, from: "regions")

        guard !units.isEmpty else {
            throw WarMapError.mapDataCorrupt(resource: "territories.json",
                                             detail: "the file contains no territories")
        }

        let loaded = Core(
            units: units,
            unitsByID: Dictionary(units.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }),
            cities: cities,
            citiesByUnit: Dictionary(grouping: cities, by: \.unitID),
            regions: regions
        )
        core = loaded
        return loaded
    }

    public func units() throws -> [TerritoryUnit] { try loadCore().units }

    public func unit(_ id: String) throws -> TerritoryUnit? { try loadCore().unitsByID[id] }

    public func cities() throws -> [City] { try loadCore().cities }

    public func cities(in unitID: String) throws -> [City] {
        try loadCore().citiesByUnit[unitID] ?? []
    }

    public func regions() throws -> [MapRegion] { try loadCore().regions }

    public func region(_ id: String) throws -> MapRegion? {
        try loadCore().regions.first { $0.id == id }
    }

    // MARK: - Geometry

    /// Territory outlines at a level of detail, keyed by unit id.
    public func geometry(lod: LevelOfDetail) throws -> [String: GeoMultiPolygon] {
        lock.lock()
        if let cached = geometryCache[lod.rawValue] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        // Decode outside the lock: parsing takes long enough that holding it would
        // stall the renderer on another thread for no reason.
        let raw = try decode([String: [[[[Double]]]]].self, from: "geometry-lod\(lod.rawValue)")
        let parsed = raw.mapValues { GeoMultiPolygon(nestedRings: $0) }

        lock.lock()
        geometryCache[lod.rawValue] = parsed
        lock.unlock()
        return parsed
    }

    /// Boundary polylines at a level of detail.
    public func borders(lod: LevelOfDetail) throws -> [BorderSegment] {
        lock.lock()
        if let cached = borderCache[lod.rawValue] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let parsed = try decode([BorderSegment].self, from: "borders-lod\(lod.rawValue)")

        lock.lock()
        borderCache[lod.rawValue] = parsed
        lock.unlock()
        return parsed
    }

    /// Drops cached geometry under memory pressure. Core data stays — it is small and
    /// the UI needs it constantly.
    public func purgeGeometryCaches() {
        lock.lock()
        geometryCache.removeAll()
        borderCache.removeAll()
        lock.unlock()
    }

    /// Combined bounds of a set of units — used to frame the camera on a country or
    /// on everyone involved in a war.
    public func bounds(of unitIDs: some Sequence<String>) throws -> GeoBounds {
        let byID = try loadCore().unitsByID
        var box = GeoBounds.empty
        for id in unitIDs {
            if let unit = byID[id] { box.expand(toInclude: unit.bounds) }
        }
        return box.isEmpty ? .world : box
    }

    // MARK: - Loading

    private func decode<T: Decodable>(_ type: T.Type, from resource: String) throws -> T {
        // Depending on whether the resource folder is copied as a group or as a
        // folder reference, the file lands either at the bundle root or under
        // MapData/. Try both rather than depending on how the project was generated.
        let url = bundle.url(forResource: resource, withExtension: "json")
            ?? bundle.url(forResource: resource, withExtension: "json", subdirectory: "MapData")
        guard let url else {
            throw WarMapError.mapDataMissing(resource: "\(resource).json")
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw WarMapError.mapDataCorrupt(resource: "\(resource).json",
                                             detail: error.localizedDescription)
        }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw WarMapError.mapDataCorrupt(resource: "\(resource).json",
                                             detail: String(describing: error))
        }
    }
}
