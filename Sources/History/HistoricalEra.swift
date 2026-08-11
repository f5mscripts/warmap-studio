import Foundation

/// The broad periods the app organises its content by.
///
/// An era is a filter, not a hard boundary: choosing one preselects the countries,
/// city names, flags and map styling that suit it, and nothing stops a project from
/// spanning several. The ranges below are the conventional Western-historiography
/// ones — deliberately round, and not claims about when history "really" changed.
public enum HistoricalEra: String, Codable, CaseIterable, Sendable, Identifiable {
    case ancient
    case classical
    case medieval
    case earlyModern
    case napoleonic
    case nineteenthCentury
    case worldWarOne
    case interwar
    case worldWarTwo
    case coldWar
    case modern

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .ancient: return "Ancient"
        case .classical: return "Classical"
        case .medieval: return "Medieval"
        case .earlyModern: return "Early Modern"
        case .napoleonic: return "Napoleonic"
        case .nineteenthCentury: return "19th Century"
        case .worldWarOne: return "World War I"
        case .interwar: return "Interwar"
        case .worldWarTwo: return "World War II"
        case .coldWar: return "Cold War"
        case .modern: return "Modern"
        }
    }

    /// A one-line hint shown under the era in the wizard.
    public var summary: String {
        switch self {
        case .ancient: return "Bronze Age to the first empires"
        case .classical: return "Greece, Rome, Persia"
        case .medieval: return "Kingdoms, caliphates and crusades"
        case .earlyModern: return "Gunpowder empires and colonisation"
        case .napoleonic: return "Revolution and the Grande Armée"
        case .nineteenthCentury: return "Nation-states and empire"
        case .worldWarOne: return "The Great War"
        case .interwar: return "Between the wars"
        case .worldWarTwo: return "The Second World War"
        case .coldWar: return "Two blocs, one divided world"
        case .modern: return "Present-day borders"
        }
    }

    public var startYear: Int {
        switch self {
        case .ancient: return -3000
        case .classical: return -800
        case .medieval: return 476
        case .earlyModern: return 1500
        case .napoleonic: return 1789
        case .nineteenthCentury: return 1815
        case .worldWarOne: return 1914
        case .interwar: return 1919
        case .worldWarTwo: return 1939
        case .coldWar: return 1947
        case .modern: return 1991
        }
    }

    public var endYear: Int {
        switch self {
        case .ancient: return -800
        case .classical: return 476
        case .medieval: return 1500
        case .earlyModern: return 1789
        case .napoleonic: return 1815
        case .nineteenthCentury: return 1914
        case .worldWarOne: return 1918
        case .interwar: return 1939
        case .worldWarTwo: return 1945
        case .coldWar: return 1991
        case .modern: return 2100
        }
    }

    public var interval: HistoricalInterval {
        HistoricalInterval(start: HistoricalDate(year: startYear),
                           end: HistoricalDate(year: endYear))
    }

    public func contains(_ date: HistoricalDate) -> Bool {
        interval.contains(date)
    }

    /// The era a date falls in, for labelling a project from its start date.
    public static func era(for date: HistoricalDate) -> HistoricalEra {
        allCases.first { $0.contains(date) } ?? .modern
    }

    /// A short label like "1939–1945" for project cards.
    public var yearRangeLabel: String {
        func label(_ year: Int) -> String {
            year < 0 ? "\(-year) BC" : String(year)
        }
        return "\(label(startYear))–\(label(endYear))"
    }

    /// Map styling changes with the era: older periods lean further into the
    /// parchment-and-ink look, modern ones stay closer to a clean atlas.
    public var suggestedMapStyle: MapStyle {
        switch self {
        case .ancient, .classical, .medieval:
            return .parchment
        case .earlyModern, .napoleonic, .nineteenthCentury:
            return .antique
        case .worldWarOne, .interwar, .worldWarTwo, .coldWar:
            return .military
        case .modern:
            return .atlas
        }
    }
}

/// The visual treatment applied to the map as a whole.
public enum MapStyle: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Aged paper, ink coastlines, warm territory fills.
    case parchment
    /// Muted engraved look with hatched seas.
    case antique
    /// Dark charcoal with saturated faction colours — the war-room look.
    case military
    /// Clean, high-contrast, modern reference atlas.
    case atlas

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .parchment: return "Parchment"
        case .antique: return "Antique"
        case .military: return "Military"
        case .atlas: return "Atlas"
        }
    }
}
