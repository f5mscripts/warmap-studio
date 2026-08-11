import XCTest
@testable import WarMapStudio

/// Dates drive the timeline, the simulation clock and the animated date counter, and
/// the app deliberately does not use Foundation's calendar — so the arithmetic is
/// pinned down here, especially across the BC/AD boundary where off-by-one errors
/// love to hide.
final class HistoricalDateTests: XCTestCase {

    // MARK: - Round-tripping

    func testEpochIsTheUnixEpoch() {
        XCTAssertEqual(HistoricalDate(year: 1970, month: 1, day: 1).dayNumber, 0)
    }

    func testKnownDatesConvertBothWays() {
        let cases: [(Int, Int, Int)] = [
            (1939, 9, 1),    // invasion of Poland
            (1945, 5, 8),
            (1815, 6, 18),   // Waterloo
            (1453, 5, 29),   // fall of Constantinople
            (1, 1, 1),
            (0, 1, 1),       // 1 BC
            (-264, 3, 15),   // First Punic War
            (-753, 4, 21),   // traditional founding of Rome
            (2000, 2, 29),   // leap year on a century divisible by 400
        ]
        for (year, month, day) in cases {
            let date = HistoricalDate(year: year, month: month, day: day)
            let c = date.components
            XCTAssertEqual(c.year, year, "year round-trip failed for \(year)-\(month)-\(day)")
            XCTAssertEqual(c.month, month, "month round-trip failed for \(year)-\(month)-\(day)")
            XCTAssertEqual(c.day, day, "day round-trip failed for \(year)-\(month)-\(day)")
        }
    }

    func testDayNumbersIncreaseWithTime() {
        let ordered = [
            HistoricalDate(year: -753, month: 4, day: 21),
            HistoricalDate(year: -264, month: 1, day: 1),
            HistoricalDate(year: 0, month: 6, day: 1),
            HistoricalDate(year: 1, month: 1, day: 1),
            HistoricalDate(year: 1453, month: 5, day: 29),
            HistoricalDate(year: 1939, month: 9, day: 1),
            HistoricalDate(year: 2026, month: 1, day: 1),
        ]
        for i in 1..<ordered.count {
            XCTAssertLessThan(ordered[i - 1], ordered[i])
        }
    }

    // MARK: - Leap years

    func testLeapYearRules() {
        XCTAssertTrue(HistoricalDate.isLeapYear(2024))
        XCTAssertTrue(HistoricalDate.isLeapYear(2000))
        XCTAssertFalse(HistoricalDate.isLeapYear(1900))
        XCTAssertFalse(HistoricalDate.isLeapYear(2023))
        XCTAssertTrue(HistoricalDate.isLeapYear(-4), "proleptic leap years continue before AD")
    }

    func testFebruaryLengthFollowsLeapYears() {
        XCTAssertEqual(HistoricalDate.daysIn(month: 2, year: 2024), 29)
        XCTAssertEqual(HistoricalDate.daysIn(month: 2, year: 1900), 28)
        XCTAssertEqual(HistoricalDate.daysIn(month: 2, year: 2000), 29)
    }

    func testInvalidDayIsClampedToMonthLength() {
        let date = HistoricalDate(year: 2023, month: 2, day: 31)
        XCTAssertEqual(date.month, 2)
        XCTAssertEqual(date.day, 28)
    }

    // MARK: - Differences

    func testKnownDayDifference() {
        // 1 September 1939 to 8 May 1945.
        let start = HistoricalDate(year: 1939, month: 9, day: 1)
        let end = HistoricalDate(year: 1945, month: 5, day: 8)
        XCTAssertEqual(end.days(since: start), 2076)
    }

    func testOneYearApartIsThreeSixtyFiveOrSix() {
        XCTAssertEqual(HistoricalDate(year: 2023, month: 1, day: 1)
            .days(since: HistoricalDate(year: 2022, month: 1, day: 1)), 365)
        XCTAssertEqual(HistoricalDate(year: 2025, month: 1, day: 1)
            .days(since: HistoricalDate(year: 2024, month: 1, day: 1)), 366)
    }

    func testDifferenceSpanningTheEraBoundary() {
        // 1 BC is year 0, so 1 January 1 BC to 1 January 1 AD is one (leap) year.
        let bc = HistoricalDate(year: 0, month: 1, day: 1)
        let ad = HistoricalDate(year: 1, month: 1, day: 1)
        XCTAssertEqual(ad.days(since: bc), 366)
    }

    // MARK: - Arithmetic

    func testAddingDaysCrossesMonthAndYearBoundaries() {
        let date = HistoricalDate(year: 1939, month: 12, day: 30).adding(days: 5)
        XCTAssertEqual(date.components.year, 1940)
        XCTAssertEqual(date.components.month, 1)
        XCTAssertEqual(date.components.day, 4)
    }

    func testAddingMonthsClampsRatherThanOverflowing() {
        let date = HistoricalDate(year: 2023, month: 1, day: 31).adding(months: 1)
        XCTAssertEqual(date.components.month, 2)
        XCTAssertEqual(date.components.day, 28, "31 Jan + 1 month should land on 28 Feb")
    }

    func testAddingMonthsGoesBackwardsAcrossAYear() {
        let date = HistoricalDate(year: 1940, month: 2, day: 15).adding(months: -4)
        XCTAssertEqual(date.components.year, 1939)
        XCTAssertEqual(date.components.month, 10)
    }

    func testAddingYearsHandlesLeapDay() {
        let date = HistoricalDate(year: 2024, month: 2, day: 29).adding(years: 1)
        XCTAssertEqual(date.components.year, 2025)
        XCTAssertEqual(date.components.month, 2)
        XCTAssertEqual(date.components.day, 28)
    }

    func testClampingToARange() {
        let range = HistoricalDate(year: 1939)...HistoricalDate(year: 1945)
        XCTAssertEqual(HistoricalDate(year: 1930).clamped(to: range), HistoricalDate(year: 1939))
        XCTAssertEqual(HistoricalDate(year: 1950).clamped(to: range), HistoricalDate(year: 1945))
        XCTAssertEqual(HistoricalDate(year: 1942).clamped(to: range), HistoricalDate(year: 1942))
    }

    // MARK: - BC handling

    func testBCDetectionAndDisplayYear() {
        let oneBC = HistoricalDate(year: 0, month: 1, day: 1)
        XCTAssertTrue(oneBC.isBC)
        XCTAssertEqual(oneBC.displayYear, 1)

        let punic = HistoricalDate(year: -263, month: 1, day: 1)
        XCTAssertTrue(punic.isBC)
        XCTAssertEqual(punic.displayYear, 264)

        let modern = HistoricalDate(year: 1939, month: 9, day: 1)
        XCTAssertFalse(modern.isBC)
        XCTAssertEqual(modern.displayYear, 1939)
    }

    // MARK: - Formatting

    func testEveryFormatRendersTheSameDate() {
        let date = HistoricalDate(year: 1939, month: 9, day: 1)
        XCTAssertEqual(date.formatted(.dayMonthYear), "01/09/1939")
        XCTAssertEqual(date.formatted(.monthDayYear), "09/01/1939")
        XCTAssertEqual(date.formatted(.monthNameDayYear), "September 1, 1939")
        XCTAssertEqual(date.formatted(.dayMonthNameYear), "1 September 1939")
        XCTAssertEqual(date.formatted(.monthNameYear), "September 1939")
        XCTAssertEqual(date.formatted(.yearOnly), "1939")
    }

    func testBCDatesGetAnEraSuffix() {
        let date = HistoricalDate(year: -263, month: 3, day: 15)
        XCTAssertEqual(date.formatted(.yearOnly), "264 BC")
        XCTAssertTrue(date.formatted(.dayMonthNameYear).hasSuffix("264 BC"))
        XCTAssertEqual(date.formatted(.yearOnly, includeEra: false), "264")
    }

    // MARK: - Codable

    func testCodableRoundTrip() throws {
        let original = HistoricalDate(year: -264, month: 7, day: 4)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HistoricalDate.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testEncodesAsReadableComponents() throws {
        let data = try JSONEncoder().encode(HistoricalDate(year: 1939, month: 9, day: 1))
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains("\"year\":1939"), "project files should stay readable: \(json)")
        XCTAssertTrue(json.contains("\"month\":9"))
    }

    // MARK: - Intervals

    func testIntervalProgressAndSampling() {
        let interval = HistoricalInterval(start: HistoricalDate(year: 1939, month: 9, day: 1),
                                          end: HistoricalDate(year: 1945, month: 5, day: 8))
        XCTAssertEqual(interval.progress(at: interval.start), 0, accuracy: 1e-9)
        XCTAssertEqual(interval.progress(at: interval.end), 1, accuracy: 1e-9)
        XCTAssertEqual(interval.progress(at: HistoricalDate(year: 1930)), 0,
                       "dates before the start clamp to 0")

        let midpoint = interval.date(atProgress: 0.5)
        XCTAssertEqual(midpoint.days(since: interval.start), interval.dayCount / 2)
    }

    func testIntervalRejectsInvertedRanges() {
        let interval = HistoricalInterval(start: HistoricalDate(year: 1945),
                                          end: HistoricalDate(year: 1939))
        XCTAssertGreaterThanOrEqual(interval.end, interval.start)
    }

    // MARK: - Eras

    func testEraLookupForKnownDates() {
        XCTAssertEqual(HistoricalEra.era(for: HistoricalDate(year: 1942)), .worldWarTwo)
        XCTAssertEqual(HistoricalEra.era(for: HistoricalDate(year: 1916)), .worldWarOne)
        XCTAssertEqual(HistoricalEra.era(for: HistoricalDate(year: 1805)), .napoleonic)
        XCTAssertEqual(HistoricalEra.era(for: HistoricalDate(year: -300)), .classical)
    }

    func testEraRangeLabels() {
        XCTAssertEqual(HistoricalEra.worldWarTwo.yearRangeLabel, "1939–1945")
        XCTAssertTrue(HistoricalEra.classical.yearRangeLabel.contains("BC"))
    }
}
