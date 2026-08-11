import Foundation

/// What kind of polity this is. Affects the default label styling and gives the
/// scenario tools something to reason about — a puppet state collapses when its
/// patron does, a colony transfers with its metropole.
public enum PolityKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case empire
    case kingdom
    case republic
    case federation
    case unionOfRepublics
    case cityState
    case duchy
    case caliphate
    case colony
    case dominion
    case puppetState
    case occupiedTerritory
    case provisionalGovernment
    case tribalConfederation
    case neutral

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .empire: return "Empire"
        case .kingdom: return "Kingdom"
        case .republic: return "Republic"
        case .federation: return "Federation"
        case .unionOfRepublics: return "Union of Republics"
        case .cityState: return "City-State"
        case .duchy: return "Duchy"
        case .caliphate: return "Caliphate"
        case .colony: return "Colony"
        case .dominion: return "Dominion"
        case .puppetState: return "Puppet State"
        case .occupiedTerritory: return "Occupied Territory"
        case .provisionalGovernment: return "Provisional Government"
        case .tribalConfederation: return "Tribal Confederation"
        case .neutral: return "Neutral State"
        }
    }

    /// Puppets and occupied zones are drawn with a hatched overlay so they read as
    /// controlled-but-not-annexed at a glance.
    public var isSubordinate: Bool {
        switch self {
        case .puppetState, .occupiedTerritory, .colony, .dominion: return true
        default: return false
        }
    }
}

public enum Continent: String, Codable, CaseIterable, Sendable, Identifiable {
    case europe, asia, africa, northAmerica, southAmerica, oceania, middleEast

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .europe: return "Europe"
        case .asia: return "Asia"
        case .africa: return "Africa"
        case .northAmerica: return "North America"
        case .southAmerica: return "South America"
        case .oceania: return "Oceania"
        case .middleEast: return "Middle East"
        }
    }
}

/// A political entity that can own territory, field armies and fight wars.
///
/// Deliberately not tied to a modern nation-state: the Roman Empire, Nazi Germany,
/// Vichy France and a user-invented breakaway republic are all the same type, and
/// the whole catalogue is data rather than code baked into the UI, so adding a
/// country never means touching a view.
public struct Country: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    /// Plain name: "Germany".
    public var name: String
    /// Formal name for the period: "German Reich".
    public var displayName: String
    /// Two to four letters for cramped map labels: "GER".
    public var shortName: String
    /// Territory fill colour, `RRGGBB`.
    public var colorHex: String
    public var kind: PolityKind
    public var continent: Continent
    /// City id of the capital, from the bundled city database.
    public var capitalCityID: String?
    /// When the polity existed. `nil` for countries with no meaningful end.
    public var existence: HistoricalInterval?
    /// The era this entity most belongs to, used to filter the country picker.
    public var era: HistoricalEra?
    /// Flags in force over time; resolved by date.
    public var flags: [HistoricalFlag]
    /// The territory units this country holds by default when a scenario starts.
    public var homeTerritoryIDs: [String]
    /// Ids of other countries it is allied with at scenario start.
    public var allianceIDs: [String]
    /// True for countries the user created, so the UI can offer to delete them.
    public var isCustom: Bool

    public init(id: String,
                name: String,
                displayName: String? = nil,
                shortName: String,
                colorHex: String,
                kind: PolityKind,
                continent: Continent,
                capitalCityID: String? = nil,
                existence: HistoricalInterval? = nil,
                era: HistoricalEra? = nil,
                flags: [HistoricalFlag] = [],
                homeTerritoryIDs: [String] = [],
                allianceIDs: [String] = [],
                isCustom: Bool = false) {
        self.id = id
        self.name = name
        self.displayName = displayName ?? name
        self.shortName = shortName
        self.colorHex = colorHex
        self.kind = kind
        self.continent = continent
        self.capitalCityID = capitalCityID
        self.existence = existence
        self.era = era
        self.flags = flags
        self.homeTerritoryIDs = homeTerritoryIDs
        self.allianceIDs = allianceIDs
        self.isCustom = isCustom
    }

    /// The flag flown on a given date.
    ///
    /// Falls back to the last flag defined, so a country with a single flag behaves
    /// sensibly and one whose date ranges do not cover the scenario still draws
    /// something rather than nothing.
    public func flag(on date: HistoricalDate) -> HistoricalFlag? {
        flags.first { $0.covers(date) } ?? flags.last
    }

    /// Whether the country exists on a date — used to keep extinct polities out of
    /// the picker and to trigger collapse animations.
    public func exists(on date: HistoricalDate) -> Bool {
        guard let existence else { return true }
        return existence.contains(date)
    }

    /// A label like "German Reich · Empire".
    public var subtitle: String {
        kind == .neutral ? displayName : "\(displayName) · \(kind.displayName)"
    }
}
