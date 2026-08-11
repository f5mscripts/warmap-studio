import XCTest
@testable import WarMapStudio

/// Exercises the map data that actually ships in the bundle. These tests fail if the
/// resources go missing from the build, if the generator's output drifts from what
/// the decoders expect, or if a subdivision the demo scenarios rely on disappears.
final class MapDataTests: XCTestCase {

    private var library: MapLibrary!

    override func setUpWithError() throws {
        try super.setUpWithError()
        library = MapLibrary(bundle: .main)
    }

    // MARK: - Presence and shape

    func testTerritoriesLoadFromTheBundle() throws {
        let units = try library.units()
        XCTAssertGreaterThan(units.count, 150, "expected the full Natural Earth set")
        XCTAssertTrue(units.allSatisfy { !$0.id.isEmpty })
        XCTAssertTrue(units.allSatisfy { !$0.bounds.isEmpty })
    }

    func testTerritoryIdentifiersAreUnique() throws {
        let ids = try library.units().map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "territory ids must be unique")
    }

    func testAnchorLiesInsideItsOwnBoundingBox() throws {
        for unit in try library.units() {
            XCTAssertTrue(unit.bounds.contains(unit.anchor),
                          "\(unit.id): label anchor fell outside its bounds")
        }
    }

    func testRegionsCoverTheWizardPresets() throws {
        let ids = Set(try library.regions().map(\.id))
        for expected in ["world", "europe", "asia", "middle_east", "africa",
                         "north_america", "south_america", "mediterranean"] {
            XCTAssertTrue(ids.contains(expected), "missing region preset \(expected)")
        }
    }

    // MARK: - Subdivisions the scenarios depend on

    func testPartitionableUnitsExist() throws {
        let ids = Set(try library.units().map(\.id))
        // These are the cuts that let the app animate the 1939 partition, the Vichy
        // demarcation, and the post-war transfers. Losing one silently breaks a
        // preset scenario, so name them explicitly.
        for expected in ["POL", "DEU", "UKR-W", "UKR-E", "BLR-W", "BLR-E",
                         "RUS-KGD", "FRA-OCC", "FRA-VICHY", "ROU-TRANS-N",
                         "FIN-KARELIA", "UKR-CRIMEA"] {
            XCTAssertTrue(ids.contains(expected), "missing territory unit \(expected)")
        }
    }

    func testInterwarPolandNeighboursItsPartitionUnits() throws {
        let poland = try XCTUnwrap(try library.unit("POL"))
        XCTAssertTrue(poland.neighbours.contains("DEU"))
        XCTAssertTrue(poland.neighbours.contains("UKR-W"))
        XCTAssertTrue(poland.neighbours.contains("BLR-W"))
        XCTAssertTrue(poland.neighbours.contains("RUS-KGD"),
                      "East Prussia must border Poland for the 1939 scenario")
    }

    func testAdjacencyIsSymmetric() throws {
        let units = try library.units()
        let byID = Dictionary(uniqueKeysWithValues: units.map { ($0.id, $0) })
        for unit in units {
            for neighbour in unit.neighbours {
                let other = try XCTUnwrap(byID[neighbour],
                                          "\(unit.id) lists unknown neighbour \(neighbour)")
                XCTAssertTrue(other.neighbours.contains(unit.id),
                              "\(unit.id) ↔ \(neighbour) adjacency is one-way")
            }
        }
    }

    // MARK: - Geometry

    func testGeometryLoadsAtEveryLevelOfDetail() throws {
        for lod in LevelOfDetail.allCases {
            let geometry = try library.geometry(lod: lod)
            XCTAssertGreaterThan(geometry.count, 150, "lod \(lod.rawValue) is missing territories")
            let poland = try XCTUnwrap(geometry["POL"], "lod \(lod.rawValue) has no Poland")
            XCTAssertFalse(poland.isEmpty)
        }
    }

    func testEveryTerritoryHasGeometryAtEveryLevel() throws {
        let ids = Set(try library.units().map(\.id))
        for lod in LevelOfDetail.allCases {
            let geometry = try library.geometry(lod: lod)
            let missing = ids.subtracting(geometry.keys)
            XCTAssertTrue(missing.isEmpty,
                          "lod \(lod.rawValue) is missing geometry for \(missing.sorted())")
        }
    }

    func testCoarserLevelsHaveFewerVertices() throws {
        func vertexCount(_ lod: LevelOfDetail) throws -> Int {
            try library.geometry(lod: lod).values.reduce(0) { total, multi in
                total + multi.polygons.reduce(0) { $0 + $1.exterior.count }
            }
        }
        let full = try vertexCount(.full)
        let coarse = try vertexCount(.coarse)
        XCTAssertLessThan(coarse, full, "the coarse level should actually be simpler")
    }

    func testGeometryAgreesWithDeclaredBounds() throws {
        let geometry = try library.geometry(lod: .full)
        for unit in try library.units() {
            guard let multi = geometry[unit.id] else { continue }
            let actual = multi.bounds
            // A degree of slack absorbs the coordinate rounding in the generator.
            XCTAssertEqual(actual.minLongitude, unit.bounds.minLongitude, accuracy: 1.0,
                           "\(unit.id) bounds disagree with its geometry")
            XCTAssertEqual(actual.maxLatitude, unit.bounds.maxLatitude, accuracy: 1.0,
                           "\(unit.id) bounds disagree with its geometry")
        }
    }

    // MARK: - Borders

    func testBordersLoadAndReferenceRealTerritories() throws {
        let ids = Set(try library.units().map(\.id))
        let borders = try library.borders(lod: .medium)
        XCTAssertGreaterThan(borders.count, 100)
        for segment in borders {
            XCTAssertTrue(ids.contains(segment.a), "border references unknown unit \(segment.a)")
            if let b = segment.b {
                XCTAssertTrue(ids.contains(b), "border references unknown unit \(b)")
            }
            XCTAssertGreaterThanOrEqual(segment.points.count, 2)
        }
    }

    /// The whole point of the shared-edge table: a seam between two units of the same
    /// country must be available to hide. If these pairs stopped being shared
    /// borders, partitioned countries would show their internal cuts again.
    func testInternalCutsAreSharedBordersNotCoastline() throws {
        let borders = try library.borders(lod: .full)
        func hasSharedBorder(_ x: String, _ y: String) -> Bool {
            borders.contains { ($0.a == x && $0.b == y) || ($0.a == y && $0.b == x) }
        }
        XCTAssertTrue(hasSharedBorder("FRA-OCC", "FRA-VICHY"))
        XCTAssertTrue(hasSharedBorder("ROU", "ROU-TRANS-N"))
        XCTAssertTrue(hasSharedBorder("UKR-W", "UKR-E"))
        XCTAssertTrue(hasSharedBorder("BLR-W", "BLR-E"))
        XCTAssertTrue(hasSharedBorder("FIN", "FIN-KARELIA"))
    }

    // MARK: - Cities

    func testCitiesLoadWithUsableAnchors() throws {
        let cities = try library.cities()
        XCTAssertGreaterThan(cities.count, 200)
        XCTAssertTrue(cities.contains { $0.name == "Berlin" })
        XCTAssertTrue(cities.contains { $0.name == "Moscow" })
        XCTAssertTrue(cities.contains { $0.name == "Warsaw" })
        for city in cities {
            XCTAssertTrue((-180...180).contains(city.coordinate.longitude))
            XCTAssertTrue((-90...90).contains(city.coordinate.latitude))
        }
    }

    func testHistoricalCityNamesResolveByYear() throws {
        let byName = Dictionary(try library.cities().map { ($0.name, $0) },
                                uniquingKeysWith: { first, _ in first })

        func assertName(_ city: String, inYear year: Int, is expected: String,
                        line: UInt = #line) throws {
            let match = try XCTUnwrap(byName[city], "city \(city) is missing", line: line)
            XCTAssertEqual(match.name(inYear: year), expected, line: line)
        }

        try assertName("Istanbul", inYear: 1500, is: "Constantinople")
        try assertName("Istanbul", inYear: 2000, is: "Istanbul")
        try assertName("Volgograd", inYear: 1900, is: "Tsaritsyn")
        try assertName("Volgograd", inYear: 1942, is: "Stalingrad")
        try assertName("Volgograd", inYear: 2020, is: "Volgograd")
        try assertName("St. Petersburg", inYear: 1942, is: "Leningrad")
        try assertName("Kaliningrad", inYear: 1940, is: "Königsberg")
        try assertName("Gdansk", inYear: 1939, is: "Danzig")
        try assertName("Lviv", inYear: 1930, is: "Lwów")
    }

    /// A renamed city must stay one city. Shipping "Stalingrad" alongside
    /// "Volgograd" would put two dots on the same bend of the Volga.
    func testRenamedCitiesAreNotDuplicatedAsSeparatePlaces() throws {
        let names = Set(try library.cities().map(\.name))
        for historicalName in ["Stalingrad", "Leningrad", "Constantinople",
                               "Danzig", "Königsberg", "Breslau"] {
            XCTAssertFalse(names.contains(historicalName),
                           "\(historicalName) should be a historical name, not its own city")
        }
    }

    func testCitiesAreAttachedToTerritories() throws {
        let ids = Set(try library.units().map(\.id))
        let unattached = try library.cities().filter { !$0.unitID.isEmpty && !ids.contains($0.unitID) }
        XCTAssertTrue(unattached.isEmpty,
                      "cities point at unknown territories: \(unattached.map(\.name))")
    }

    // MARK: - Path building

    func testPathCacheBuildsGeometryAndCachesIt() throws {
        let cache = TerritoryPathCache(library: library)
        let first = try XCTUnwrap(try cache.territoryPath(unitID: "POL", lod: .coarse,
                                                          projection: .mercator))
        XCTAssertFalse(first.path.isEmpty)
        XCTAssertFalse(first.bounds.isNull)

        let countAfterFirst = cache.cachedPathCount
        _ = try cache.territoryPath(unitID: "POL", lod: .coarse, projection: .mercator)
        XCTAssertEqual(cache.cachedPathCount, countAfterFirst, "second lookup should hit the cache")
    }

    func testPathCachePurgeKeepsTheRequestedLevel() throws {
        let cache = TerritoryPathCache(library: library)
        _ = try cache.territoryPath(unitID: "POL", lod: .coarse, projection: .mercator)
        _ = try cache.territoryPath(unitID: "POL", lod: .full, projection: .mercator)
        cache.purge(keeping: .coarse)
        XCTAssertEqual(cache.cachedPathCount, 1)
    }
}
