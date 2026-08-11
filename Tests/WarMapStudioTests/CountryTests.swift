import CoreGraphics
import XCTest
@testable import WarMapStudio

final class CountryTests: XCTestCase {

    // MARK: - Catalogue integrity

    func testCountryIdentifiersAreUnique() {
        let ids = CountryLibrary.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "country ids must be unique")
    }

    func testEveryCountryHasAtLeastOneFlagAndAColour() {
        for country in CountryLibrary.all {
            XCTAssertFalse(country.flags.isEmpty, "\(country.id) has no flag")
            XCTAssertEqual(country.colorHex.count, 6, "\(country.id) has a malformed colour")
            XCTAssertNotNil(UInt32(country.colorHex, radix: 16), "\(country.id) colour is not hex")
        }
    }

    func testHomeTerritoriesReferenceRealMapUnits() throws {
        let known = Set(try MapLibrary(bundle: .main).units().map(\.id))
        for country in CountryLibrary.all {
            for territory in country.homeTerritoryIDs {
                XCTAssertTrue(known.contains(territory),
                              "\(country.id) claims unknown territory \(territory)")
            }
        }
    }

    func testTheScenarioPowersAreAllPresent() {
        for id in ["germany", "poland", "ussr", "france", "united_kingdom", "italy",
                   "japan", "united_states", "roman_empire", "ottoman_empire",
                   "austria_hungary", "byzantine_empire", "british_empire", "prussia"] {
            XCTAssertNotNil(CountryLibrary.country(id), "missing country \(id)")
        }
    }

    // MARK: - Existence over time

    func testExtinctPolitiesAreAbsentOutsideTheirLifetime() throws {
        let ussr = try XCTUnwrap(CountryLibrary.country("ussr"))
        XCTAssertFalse(ussr.exists(on: HistoricalDate(year: 1900)))
        XCTAssertTrue(ussr.exists(on: HistoricalDate(year: 1941)))
        XCTAssertFalse(ussr.exists(on: HistoricalDate(year: 2000)))

        let rome = try XCTUnwrap(CountryLibrary.country("roman_empire"))
        XCTAssertTrue(rome.exists(on: HistoricalDate(year: 117)))
        XCTAssertFalse(rome.exists(on: HistoricalDate(year: 800)))
    }

    func testCountriesWithoutAnEndDateAlwaysExist() throws {
        let uk = try XCTUnwrap(CountryLibrary.country("united_kingdom"))
        XCTAssertTrue(uk.exists(on: HistoricalDate(year: 1750)))
        XCTAssertTrue(uk.exists(on: HistoricalDate(year: 2026)))
    }

    func testExistingOnDateFiltersTheCatalogue() {
        let inWar = CountryLibrary.existing(on: HistoricalDate(year: 1941)).map(\.id)
        XCTAssertTrue(inWar.contains("ussr"))
        XCTAssertTrue(inWar.contains("germany"))
        XCTAssertFalse(inWar.contains("roman_empire"))
        XCTAssertFalse(inWar.contains("byzantine_empire"))
    }

    // MARK: - Flags resolve by date

    func testGermanyFliesADifferentFlagInEachPeriod() throws {
        let germany = try XCTUnwrap(CountryLibrary.country("germany"))
        let imperial = try XCTUnwrap(germany.flag(on: HistoricalDate(year: 1914)))
        let weimar = try XCTUnwrap(germany.flag(on: HistoricalDate(year: 1925)))
        let wartime = try XCTUnwrap(germany.flag(on: HistoricalDate(year: 1940)))

        XCTAssertNotEqual(imperial.spec, weimar.spec,
                          "the 1914 and 1925 flags should differ")
        XCTAssertNotEqual(weimar.spec, wartime.spec,
                          "the 1925 and 1940 flags should differ")
    }

    func testFranceUsesTheRoyalFlagBeforeTheRevolution() throws {
        let france = try XCTUnwrap(CountryLibrary.country("france"))
        let royal = try XCTUnwrap(france.flag(on: HistoricalDate(year: 1700)))
        let tricolour = try XCTUnwrap(france.flag(on: HistoricalDate(year: 1800)))
        XCTAssertEqual(royal.spec.field, .solid("FFFFFF"))
        XCTAssertNotEqual(royal.spec, tricolour.spec)
    }

    func testFlagLookupFallsBackRatherThanReturningNil() throws {
        // A date far outside every declared range must still produce something to
        // draw — a missing flag should never blank out a country label.
        let poland = try XCTUnwrap(CountryLibrary.country("poland"))
        XCTAssertNotNil(poland.flag(on: HistoricalDate(year: -500)))
        XCTAssertNotNil(poland.flag(on: HistoricalDate(year: 3000)))
    }

    func testHistoricalFlagCoverageBoundariesAreHalfOpen() {
        let f = HistoricalFlag(label: "test",
                               startDate: HistoricalDate(year: 1919),
                               endDate: HistoricalDate(year: 1933),
                               spec: .solid("FF0000"))
        XCTAssertFalse(f.covers(HistoricalDate(year: 1918)))
        XCTAssertTrue(f.covers(HistoricalDate(year: 1919)))
        XCTAssertTrue(f.covers(HistoricalDate(year: 1932)))
        XCTAssertFalse(f.covers(HistoricalDate(year: 1933)),
                       "the end date belongs to the next flag")
    }

    // MARK: - Flag rendering

    func testFlagRendererParsesColours() {
        let red = FlagRenderer.cgColor("FF0000")
        XCTAssertEqual(red.components?[0] ?? 0, 1.0, accuracy: 0.001)
        XCTAssertEqual(red.components?[1] ?? 1, 0.0, accuracy: 0.001)

        XCTAssertNotNil(FlagRenderer.cgColor("#00FF00"))
        XCTAssertNotNil(FlagRenderer.cgColor("F00"), "shorthand hex should expand")
        XCTAssertNotNil(FlagRenderer.cgColor("nonsense"), "bad input must not crash")
    }

    func testFlagRendererDrawsEveryCatalogueFlagWithoutCrashing() throws {
        // Exercises every overlay type the catalogue actually uses.
        let size = CGSize(width: 60, height: 40)
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let rect = CGRect(origin: .zero, size: size)
        for country in CountryLibrary.all {
            for flag in country.flags {
                FlagRenderer.draw(flag.spec, in: rect, context: context)
            }
        }
        XCTAssertNotNil(context.makeImage())
    }

    func testFittedRectRespectsAspectRatio() {
        let spec = FlagSpec(field: .solid("FF0000"), aspectRatio: 2.0)
        let fitted = FlagRenderer.fittedRect(for: spec, in: CGRect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertEqual(fitted.width / fitted.height, 2.0, accuracy: 0.001)
        XCTAssertLessThanOrEqual(fitted.width, 100.001)
        XCTAssertLessThanOrEqual(fitted.height, 100.001)
    }

    func testRepresentativeColourFallsOutOfTheField() {
        XCTAssertEqual(FlagSpec.solid("C9A227").representativeColorHex, "C9A227")
        XCTAssertEqual(FlagSpec.tricolourVertical("002395", "FFFFFF", "ED2939")
            .representativeColorHex, "FFFFFF")
    }

    // MARK: - Codable

    func testCountryCodableRoundTrip() throws {
        let original = try XCTUnwrap(CountryLibrary.country("germany"))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Country.self, from: data)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.flags.count, original.flags.count)
        XCTAssertEqual(decoded.flags.first?.spec, original.flags.first?.spec)
    }

    func testFlagSpecCodableRoundTripCoversEveryOverlay() throws {
        let spec = FlagSpec(
            field: .horizontal(["FF0000", "FFFFFF"]),
            overlays: [
                .cross(color: "0000FF", thickness: 0.2, offsetFromHoist: 0.36),
                .saltire(color: "FFFFFF", thickness: 0.1),
                .canton(color: "000080", widthFraction: 0.4, heightFraction: 0.5),
                .disc(color: "FFD700", radius: 0.2, center: CGPoint(x: 0.5, y: 0.5)),
                .crescent(color: "FFFFFF", radius: 0.2, center: CGPoint(x: 0.4, y: 0.5)),
                .star(color: "FFFFFF", points: 5, radius: 0.1, center: CGPoint(x: 0.6, y: 0.5)),
                .stripe(color: "000000", thickness: 0.05, position: 0.5),
                .hoistTriangle(color: "008000", widthFraction: 0.4),
                .border(color: "888888", thickness: 0.01),
            ]
        )
        let data = try JSONEncoder().encode(spec)
        XCTAssertEqual(try JSONDecoder().decode(FlagSpec.self, from: data), spec)
    }
}
