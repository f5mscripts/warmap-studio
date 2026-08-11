import Foundation

/// A calendar date that works across the whole range the app covers, including BC.
///
/// Foundation's `Date`/`Calendar` are the wrong tool here: they are built around an
/// absolute time scale with time zones and locale-sensitive eras, and they get
/// awkward and slow around 264 BC. The timeline only ever needs whole days, ordering
/// and differences, so this stores a single day number in the proleptic Gregorian
/// calendar and does exact integer arithmetic on it.
///
/// Years use astronomical numbering internally — year 0 is 1 BC, year −1 is 2 BC —
/// which is what makes "how many days between these two dates" work across the
/// BC/AD boundary without a special case. Display converts back to BC/AD.
public struct HistoricalDate: Hashable, Comparable, Codable, Sendable {

    /// Days since 1 January 1970, proleptic Gregorian. Negative before that.
    public let dayNumber: Int

    public init(dayNumber: Int) {
        self.dayNumber = dayNumber
    }

    public init(year: Int, month: Int, day: Int) {
        let m = min(max(month, 1), 12)
        let d = min(max(day, 1), Self.daysIn(month: m, year: year))
        self.dayNumber = Self.daysFromCivil(year: year, month: m, day: d)
    }

    /// Convenience for whole years, e.g. `HistoricalDate(year: -264)` for 264 BC.
    public init(year: Int) {
        self.init(year: year, month: 1, day: 1)
    }

    // MARK: - Components

    public var year: Int { Self.civilFromDays(dayNumber).year }
    public var month: Int { Self.civilFromDays(dayNumber).month }
    public var day: Int { Self.civilFromDays(dayNumber).day }

    public var components: (year: Int, month: Int, day: Int) { Self.civilFromDays(dayNumber) }

    /// True for dates before 1 AD.
    public var isBC: Bool { year <= 0 }

    /// The year as people write it: 1 BC is year 0 astronomically, 2 BC is −1.
    public var displayYear: Int { isBC ? 1 - year : year }

    // MARK: - Arithmetic

    public func adding(days: Int) -> HistoricalDate {
        HistoricalDate(dayNumber: dayNumber + days)
    }

    /// Adds months, clamping the day to the target month's length so that
    /// 31 January plus one month is 28 (or 29) February rather than overflowing.
    public func adding(months: Int) -> HistoricalDate {
        let c = components
        let total = c.year * 12 + (c.month - 1) + months
        let newYear = Int((Double(total) / 12).rounded(.down))
        let newMonth = total - newYear * 12 + 1
        return HistoricalDate(year: newYear, month: newMonth,
                              day: min(c.day, Self.daysIn(month: newMonth, year: newYear)))
    }

    public func adding(years: Int) -> HistoricalDate {
        let c = components
        return HistoricalDate(year: c.year + years, month: c.month,
                              day: min(c.day, Self.daysIn(month: c.month, year: c.year + years)))
    }

    /// Whole days from `other` to `self`.
    public func days(since other: HistoricalDate) -> Int {
        dayNumber - other.dayNumber
    }

    /// Fractional years between two dates, for pacing a timeline ruler.
    public func years(since other: HistoricalDate) -> Double {
        Double(dayNumber - other.dayNumber) / 365.2425
    }

    public static func < (lhs: HistoricalDate, rhs: HistoricalDate) -> Bool {
        lhs.dayNumber < rhs.dayNumber
    }

    /// Clamps into a closed range — used constantly when scrubbing the timeline.
    public func clamped(to range: ClosedRange<HistoricalDate>) -> HistoricalDate {
        min(max(self, range.lowerBound), range.upperBound)
    }

    // MARK: - Calendar maths

    public static func isLeapYear(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }

    public static func daysIn(month: Int, year: Int) -> Int {
        switch month {
        case 1, 3, 5, 7, 8, 10, 12: return 31
        case 4, 6, 9, 11: return 30
        case 2: return isLeapYear(year) ? 29 : 28
        default: return 30
        }
    }

    /// Days-from-civil, after Howard Hinnant's `chrono` algorithms.
    ///
    /// Shifting the year to start in March puts the leap day at the end of the
    /// cycle, which removes every special case from the conversion and keeps it
    /// exact for negative years.
    static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        var y = year
        y -= month <= 2 ? 1 : 0
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400                                     // [0, 399]
        let doy = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1  // [0, 365]
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy             // [0, 146096]
        return era * 146097 + doe - 719468
    }

    static func civilFromDays(_ dayNumber: Int) -> (year: Int, month: Int, day: Int) {
        var z = dayNumber
        z += 719468
        let era = (z >= 0 ? z : z - 146096) / 146097
        let doe = z - era * 146097                                  // [0, 146096]
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365  // [0, 399]
        let y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)           // [0, 365]
        let mp = (5 * doy + 2) / 153                                // [0, 11]
        let d = doy - (153 * mp + 2) / 5 + 1                        // [1, 31]
        let m = mp + (mp < 10 ? 3 : -9)                             // [1, 12]
        return (y + (m <= 2 ? 1 : 0), m, d)
    }
}

// MARK: - Formatting

extension HistoricalDate {

    /// How dates read on screen and in the animated date counter.
    public enum Format: String, Codable, CaseIterable, Sendable, Identifiable {
        case dayMonthYear       // 01/09/1939
        case monthDayYear       // 09/01/1939
        case monthNameDayYear   // September 1, 1939
        case dayMonthNameYear   // 1 September 1939
        case monthNameYear      // September 1939
        case yearOnly           // 1939

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .dayMonthYear: return "DD/MM/YYYY"
            case .monthDayYear: return "MM/DD/YYYY"
            case .monthNameDayYear: return "Month DD, YYYY"
            case .dayMonthNameYear: return "DD Month YYYY"
            case .monthNameYear: return "Month YYYY"
            case .yearOnly: return "YYYY"
            }
        }
    }

    public static let monthNames = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December",
    ]

    public static let shortMonthNames = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun",
        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    ]

    public var monthName: String { Self.monthNames[max(0, min(11, month - 1))] }
    public var shortMonthName: String { Self.shortMonthNames[max(0, min(11, month - 1))] }

    /// Renders the date, appending "BC" only where it is actually needed.
    public func formatted(_ format: Format = .dayMonthNameYear, includeEra: Bool = true) -> String {
        let c = components
        let yearText = String(displayYear)
        let suffix = (includeEra && isBC) ? " BC" : ""

        func pad(_ value: Int) -> String { value < 10 ? "0\(value)" : String(value) }

        switch format {
        case .dayMonthYear:
            return "\(pad(c.day))/\(pad(c.month))/\(yearText)\(suffix)"
        case .monthDayYear:
            return "\(pad(c.month))/\(pad(c.day))/\(yearText)\(suffix)"
        case .monthNameDayYear:
            return "\(monthName) \(c.day), \(yearText)\(suffix)"
        case .dayMonthNameYear:
            return "\(c.day) \(monthName) \(yearText)\(suffix)"
        case .monthNameYear:
            return "\(monthName) \(yearText)\(suffix)"
        case .yearOnly:
            return "\(yearText)\(suffix)"
        }
    }

    /// A compact label for timeline rulers, where space is tight.
    public var tickLabel: String {
        isBC ? "\(displayYear) BC" : String(displayYear)
    }
}

// MARK: - Codable

extension HistoricalDate {
    private enum CodingKeys: String, CodingKey { case year, month, day }

    /// Encoded as year/month/day rather than a raw day number so that a `.warmap`
    /// project file stays readable and hand-editable.
    public init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self),
           let year = try? container.decode(Int.self, forKey: .year) {
            let month = (try? container.decode(Int.self, forKey: .month)) ?? 1
            let day = (try? container.decode(Int.self, forKey: .day)) ?? 1
            self.init(year: year, month: month, day: day)
            return
        }
        // Tolerate a bare integer day number too, so older or generated files load.
        let single = try decoder.singleValueContainer()
        self.init(dayNumber: try single.decode(Int.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let c = components
        try container.encode(c.year, forKey: .year)
        try container.encode(c.month, forKey: .month)
        try container.encode(c.day, forKey: .day)
    }
}

// MARK: - Ranges

/// A named stretch of time with a start and an end.
public struct HistoricalInterval: Hashable, Codable, Sendable {
    public var start: HistoricalDate
    public var end: HistoricalDate

    public init(start: HistoricalDate, end: HistoricalDate) {
        self.start = start
        self.end = max(start, end)
    }

    public var dayCount: Int { end.days(since: start) }

    public func contains(_ date: HistoricalDate) -> Bool {
        date >= start && date <= end
    }

    /// Where `date` falls within the interval, 0 at the start and 1 at the end.
    public func progress(at date: HistoricalDate) -> Double {
        guard dayCount > 0 else { return date >= end ? 1 : 0 }
        return min(max(Double(date.days(since: start)) / Double(dayCount), 0), 1)
    }

    /// The date a given fraction of the way through.
    public func date(atProgress progress: Double) -> HistoricalDate {
        start.adding(days: Int((Double(dayCount) * min(max(progress, 0), 1)).rounded()))
    }
}
