import XCTest
@testable import WarMapStudio

/// The unit catalogue: what exists, when it existed, how fast it moves, and where it
/// is allowed to stand.
final class ArmyIconTests: XCTestCase {

    // MARK: - Compatibility

    func testTheOriginalTypesKeepTheirStoredNames() {
        // These raw values are what every saved project already contains. Renaming
        // `infantry` to `rifleman` would read better and would silently break every
        // `.warmap` file on the device.
        for name in ["infantry", "armour", "cavalry", "airborne", "marine",
                     "artillery", "fleet", "airForce", "partisan"] {
            XCTAssertNotNil(ArmyIcon(rawValue: name), "\(name) no longer decodes")
        }
    }

    func testEveryTypeIsCatalogued() {
        // Well beyond the original nine, and every one reachable from the picker.
        XCTAssertGreaterThan(ArmyIcon.allCases.count, 25)
        for icon in ArmyIcon.allCases {
            XCTAssertFalse(icon.displayName.isEmpty)
            XCTAssertFalse(icon.symbolName.isEmpty)
            XCTAssertFalse(icon.abbreviation.isEmpty)
            XCTAssertGreaterThan(icon.baseSpeed, 0)
        }
        // Each category is actually populated.
        for category in ArmyCategory.allCases {
            XCTAssertFalse(ArmyIcon.allCases.filter { $0.category == category }.isEmpty,
                           "\(category) has no unit types")
        }
    }

    // MARK: - Era

    func testAJetDoesNotAppearInAWorldWarOneProject() {
        let nineteenFourteen = HistoricalDate(year: 1914, month: 8, day: 1)
        XCTAssertFalse(ArmyIcon.jetFighter.isAvailable(on: nineteenFourteen))
        XCTAssertFalse(ArmyIcon.helicopter.isAvailable(on: nineteenFourteen))
        XCTAssertFalse(ArmyIcon.airborne.isAvailable(on: nineteenFourteen))
        // Infantry, cavalry and guns have always been there.
        XCTAssertTrue(ArmyIcon.infantry.isAvailable(on: nineteenFourteen))
        XCTAssertTrue(ArmyIcon.cavalry.isAvailable(on: nineteenFourteen))
        XCTAssertTrue(ArmyIcon.artillery.isAvailable(on: nineteenFourteen))
    }

    func testTypesRetireAsWellAsArrive() {
        let modern = HistoricalDate(year: 2020)
        XCTAssertFalse(ArmyIcon.battleship.isAvailable(on: modern),
                       "no navy has commissioned one since the 1960s")
        XCTAssertFalse(ArmyIcon.diveBomber.isAvailable(on: modern))
        XCTAssertTrue(ArmyIcon.jetFighter.isAvailable(on: modern))
        XCTAssertTrue(ArmyIcon.helicopter.isAvailable(on: modern))
    }

    func testEveryPeriodHasSomethingToOffer() {
        for year in [-500, 1200, 1800, 1914, 1943, 1975, 2020] {
            let available = ArmyIcon.available(on: HistoricalDate(year: year))
            XCTAssertFalse(available.isEmpty, "nothing available in \(year)")
            XCTAssertTrue(available.allSatisfy { $0.isAvailable(on: HistoricalDate(year: year)) })
        }
        // A 1943 project should be able to field most of the catalogue.
        let wartime = ArmyIcon.available(on: HistoricalDate(year: 1943))
        XCTAssertGreaterThan(wartime.count, 20)
        XCTAssertTrue(wartime.contains(.heavyTank))
        XCTAssertTrue(wartime.contains(.carrier))
    }

    // MARK: - Movement

    /// Speeds are kilometres covered per *day*, not top speed, so the ordering only
    /// holds within a domain: a destroyer steams around the clock and covers more
    /// ground in a day than a helicopter flying sorties from a base.
    func testSpeedsAreOrderedTheWayTheRealThingsAre() {
        XCTAssertGreaterThan(ArmyIcon.jetFighter.baseSpeed, ArmyIcon.fighter.baseSpeed)
        XCTAssertGreaterThan(ArmyIcon.fighter.baseSpeed, ArmyIcon.helicopter.baseSpeed)
        XCTAssertGreaterThan(ArmyIcon.destroyer.baseSpeed, ArmyIcon.submarine.baseSpeed)
        XCTAssertGreaterThan(ArmyIcon.lightTank.baseSpeed, ArmyIcon.heavyTank.baseSpeed)
        XCTAssertGreaterThan(ArmyIcon.cavalry.baseSpeed, ArmyIcon.infantry.baseSpeed)
        XCTAssertGreaterThan(ArmyIcon.infantry.baseSpeed, ArmyIcon.howitzer.baseSpeed)
        // Every aircraft outruns every ground unit.
        let slowestPlane = ArmyIcon.allCases.filter { $0.category == .aircraft }
            .map(\.baseSpeed).min() ?? 0
        let fastestGround = ArmyIcon.allCases.filter { $0.domain == .land }
            .map(\.baseSpeed).max() ?? 0
        XCTAssertGreaterThan(slowestPlane, fastestGround)
    }

    func testAnArmyTakesItsSpeedFromItsType() {
        let jet = Army(name: "1st Fighter Wing", countryID: "germany", size: 200,
                       position: GeoCoordinate(longitude: 13, latitude: 52),
                       icon: .jetFighter)
        XCTAssertEqual(jet.speedKmPerDay, ArmyIcon.jetFighter.baseSpeed)
    }

    // MARK: - Where they can stand

    func testOnlyAircraftAndShipsCanBePlacedAtSea() {
        for icon in ArmyIcon.allCases {
            switch icon.category {
            case .aircraft:
                XCTAssertEqual(icon.domain, .air)
                XCTAssertTrue(icon.canBePlacedAtSea)
            case .naval:
                XCTAssertEqual(icon.domain, .sea)
                XCTAssertTrue(icon.canBePlacedAtSea)
            case .infantry, .armour, .artillery:
                XCTAssertEqual(icon.domain, .land)
                XCTAssertFalse(icon.canBePlacedAtSea, "\(icon) should need land under it")
            }
        }
    }

    // MARK: - Art

    func testEveryTypeHasItsOwnSprite() {
        var seen: [String: ArmyIcon] = [:]
        for icon in ArmyIcon.allCases {
            let sprite = PixelSprite.army(icon)
            XCTAssertEqual(sprite.width, 12, "\(icon) is not on the 12-pixel grid")
            XCTAssertEqual(sprite.height, 12, "\(icon) is not on the 12-pixel grid")
            XCTAssertTrue(sprite.runs.contains { $0.tone == .body },
                          "\(icon) carries none of its owner's colour")

            // Two unit types sharing one drawing would make them indistinguishable on
            // the map, which is the whole point of having thirty-one of them.
            let key = sprite.rows.joined()
            if let clash = seen[key] {
                XCTFail("\(icon) is drawn exactly like \(clash)")
            }
            seen[key] = icon
        }
    }
}
