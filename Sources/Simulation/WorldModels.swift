import CoreGraphics
import Foundation

// MARK: - Armies

/// The symbol drawn for an army on the map.
public enum ArmyIcon: String, Codable, CaseIterable, Sendable, Identifiable {
    case infantry, armour, cavalry, airborne, marine, artillery, fleet, airForce, partisan

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .infantry: return "Infantry"
        case .armour: return "Armoured"
        case .cavalry: return "Cavalry"
        case .airborne: return "Airborne"
        case .marine: return "Marine"
        case .artillery: return "Artillery"
        case .fleet: return "Fleet"
        case .airForce: return "Air Force"
        case .partisan: return "Partisan"
        }
    }

    /// Kilometres per day on open ground before terrain and supply modifiers.
    public var baseSpeed: Double {
        switch self {
        case .infantry: return 20
        case .armour: return 45
        case .cavalry: return 35
        case .airborne: return 120
        case .marine: return 22
        case .artillery: return 12
        case .fleet: return 300
        case .airForce: return 600
        case .partisan: return 15
        }
    }

    /// SF Symbols name used for the marker glyph.
    public var symbolName: String {
        switch self {
        case .infantry: return "figure.walk"
        case .armour: return "shield.lefthalf.filled"
        case .cavalry: return "hare.fill"
        case .airborne: return "parachute.fill"
        case .marine: return "water.waves"
        case .artillery: return "scope"
        case .fleet: return "ferry.fill"
        case .airForce: return "airplane"
        case .partisan: return "person.3.fill"
        }
    }
}

/// A military formation that can be positioned, moved and fought with.
public struct Army: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var countryID: String
    /// Nominal manpower. Displayed on the marker and used as the combat base.
    public var size: Int
    public var position: GeoCoordinate
    public var icon: ArmyIcon
    /// Kilometres per day. Defaults from the icon but can be overridden.
    public var speedKmPerDay: Double
    /// Fighting effectiveness, 0…1. Falls with casualties.
    public var strength: Double
    /// Willingness to keep fighting, 0…1. A broken army retreats regardless of size.
    public var morale: Double
    /// Offensive multiplier, typically 0.5…2.
    public var attack: Double
    /// Defensive multiplier, typically 0.5…2.
    public var defense: Double
    /// Supply level, 0…1. Multiplies both attack and movement.
    public var supply: Double

    public init(id: UUID = UUID(),
                name: String,
                countryID: String,
                size: Int,
                position: GeoCoordinate,
                icon: ArmyIcon = .infantry,
                speedKmPerDay: Double? = nil,
                strength: Double = 1.0,
                morale: Double = 1.0,
                attack: Double = 1.0,
                defense: Double = 1.0,
                supply: Double = 1.0) {
        self.id = id
        self.name = name
        self.countryID = countryID
        self.size = size
        self.position = position
        self.icon = icon
        self.speedKmPerDay = speedKmPerDay ?? icon.baseSpeed
        self.strength = strength
        self.morale = morale
        self.attack = attack
        self.defense = defense
        self.supply = supply
    }

    /// The number that actually matters in combat: paper strength discounted by
    /// condition. An army at half strength and broken morale is worth far less than
    /// its headcount suggests.
    public var combatPower: Double {
        Double(size) * strength * (0.4 + 0.6 * morale) * (0.5 + 0.5 * supply)
    }

    /// Armies below this morale disengage rather than fight on.
    public static let routThreshold: Double = 0.25

    public var isBroken: Bool { morale < Self.routThreshold || strength <= 0.05 }

    /// Splits off a fraction into a new formation, leaving the remainder behind.
    public func split(fraction: Double, name: String) -> (remaining: Army, detached: Army) {
        let clamped = min(max(fraction, 0.05), 0.95)
        var remaining = self
        var detached = self
        detached.id = UUID()
        detached.name = name
        detached.size = Int(Double(size) * clamped)
        remaining.size = size - detached.size
        return (remaining, detached)
    }

    /// Merges another formation in, pooling manpower and averaging condition by size.
    public func merged(with other: Army) -> Army {
        var result = self
        let total = Double(size + other.size)
        guard total > 0 else { return result }
        let w1 = Double(size) / total
        let w2 = Double(other.size) / total
        result.size = size + other.size
        result.strength = strength * w1 + other.strength * w2
        result.morale = morale * w1 + other.morale * w2
        result.supply = supply * w1 + other.supply * w2
        result.attack = attack * w1 + other.attack * w2
        result.defense = defense * w1 + other.defense * w2
        return result
    }
}

// MARK: - Frontlines

public enum FrontlineStyle: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Solid line with the attacker's colour.
    case solid
    /// Dashed — for fluid or unconfirmed fronts.
    case dashed
    /// Toothed line, the classic front symbol.
    case toothed
    /// Soft gradient band rather than a hard line.
    case gradient

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .solid: return "Solid"
        case .dashed: return "Dashed"
        case .toothed: return "Toothed"
        case .gradient: return "Gradient"
        }
    }
}

/// A hand-drawn or generated front between two powers.
public struct Frontline: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var points: [GeoCoordinate]
    /// The power pushing forward — supplies the line's colour and arrow direction.
    public var attackerID: String
    public var defenderID: String
    public var style: FrontlineStyle
    public var thickness: Double
    public var showsArrows: Bool
    /// Fractions along the line where advance arrows are drawn.
    public var arrowPositions: [Double]

    public init(id: UUID = UUID(),
                name: String = "Front",
                points: [GeoCoordinate],
                attackerID: String,
                defenderID: String,
                style: FrontlineStyle = .toothed,
                thickness: Double = 3,
                showsArrows: Bool = true,
                arrowPositions: [Double] = [0.25, 0.5, 0.75]) {
        self.id = id
        self.name = name
        self.points = points
        self.attackerID = attackerID
        self.defenderID = defenderID
        self.style = style
        self.thickness = thickness
        self.showsArrows = showsArrows
        self.arrowPositions = arrowPositions
    }
}

// MARK: - Battles

public enum BattleKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case battle
    case majorBattle
    case cityCapture
    case offensive
    case defensive
    case siege
    case naval
    case airBattle

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .battle: return "Battle"
        case .majorBattle: return "Major Battle"
        case .cityCapture: return "City Capture"
        case .offensive: return "Offensive"
        case .defensive: return "Defensive"
        case .siege: return "Siege"
        case .naval: return "Naval Battle"
        case .airBattle: return "Air Battle"
        }
    }

    /// The glyph drawn on the map.
    public var glyph: String {
        switch self {
        case .battle: return "⚔"
        case .majorBattle: return "💥"
        case .cityCapture: return "🏙"
        case .offensive: return "🔥"
        case .defensive: return "🛡"
        case .siege: return "🏰"
        case .naval: return "⚓"
        case .airBattle: return "✈"
        }
    }

    /// Major engagements draw larger and stay on screen longer.
    public var importance: Int {
        switch self {
        case .majorBattle: return 1
        case .battle, .cityCapture, .offensive: return 2
        default: return 3
        }
    }
}

/// A labelled engagement pinned to a place and a date.
public struct BattleMarker: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    /// Free text, typically the outcome: "Major Soviet victory".
    public var detail: String
    public var date: HistoricalDate
    /// Optional end date; set for sieges and long battles.
    public var endDate: HistoricalDate?
    public var coordinate: GeoCoordinate
    public var kind: BattleKind
    /// Country ids involved, for colouring the marker.
    public var participantIDs: [String]

    public init(id: UUID = UUID(),
                title: String,
                detail: String = "",
                date: HistoricalDate,
                endDate: HistoricalDate? = nil,
                coordinate: GeoCoordinate,
                kind: BattleKind = .battle,
                participantIDs: [String] = []) {
        self.id = id
        self.title = title
        self.detail = detail
        self.date = date
        self.endDate = endDate
        self.coordinate = coordinate
        self.kind = kind
        self.participantIDs = participantIDs
    }

    /// Battles show for a while after they happen so the viewer can read them.
    public func isVisible(on date: HistoricalDate, lingerDays: Int = 45) -> Bool {
        let start = self.date
        let end = (endDate ?? self.date).adding(days: lingerDays)
        return date >= start && date <= end
    }
}

// MARK: - Events

/// The kinds of thing that can happen in a war, each with its own timeline glyph.
public enum WarEventKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case warDeclared
    case invasion
    case battle
    case cityCaptured
    case capitulation
    case allianceFormed
    case allianceBroken
    case peaceTreaty
    case annexation
    case independence
    case revolution
    case coup
    case civilWar
    case countrySplit
    case countryReunified

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .warDeclared: return "War Declared"
        case .invasion: return "Invasion"
        case .battle: return "Battle"
        case .cityCaptured: return "City Captured"
        case .capitulation: return "Capitulation"
        case .allianceFormed: return "Alliance Formed"
        case .allianceBroken: return "Alliance Broken"
        case .peaceTreaty: return "Peace Treaty"
        case .annexation: return "Annexation"
        case .independence: return "Independence"
        case .revolution: return "Revolution"
        case .coup: return "Coup"
        case .civilWar: return "Civil War"
        case .countrySplit: return "Country Split"
        case .countryReunified: return "Country Reunified"
        }
    }

    /// SF Symbol shown on the timeline.
    public var symbolName: String {
        switch self {
        case .warDeclared: return "exclamationmark.triangle.fill"
        case .invasion: return "arrow.right.to.line"
        case .battle: return "burst.fill"
        case .cityCaptured: return "building.2.fill"
        case .capitulation: return "flag.slash.fill"
        case .allianceFormed: return "link"
        case .allianceBroken: return "link.badge.plus"
        case .peaceTreaty: return "dove.fill"
        case .annexation: return "square.on.square.dashed"
        case .independence: return "flag.fill"
        case .revolution: return "flame.fill"
        case .coup: return "bolt.fill"
        case .civilWar: return "arrow.triangle.branch"
        case .countrySplit: return "arrow.triangle.pull"
        case .countryReunified: return "arrow.triangle.merge"
        }
    }

    public var tintHex: String {
        switch self {
        case .warDeclared, .invasion, .civilWar: return "B3423A"
        case .battle, .cityCaptured: return "C98A2B"
        case .capitulation, .peaceTreaty: return "4E8A5C"
        case .allianceFormed, .allianceBroken: return "4A6E8A"
        case .annexation, .countrySplit, .countryReunified: return "C9A227"
        case .independence, .revolution, .coup: return "9C6B3F"
        }
    }
}

/// Something that happened, pinned to a date and shown on the timeline.
public struct WarEvent: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var kind: WarEventKind
    public var date: HistoricalDate
    public var title: String
    public var detail: String
    /// Country ids involved.
    public var actorIDs: [String]
    /// Territory units this event transfers or affects.
    public var territoryIDs: [String]
    /// Where to point the camera or place a marker, if anywhere.
    public var coordinate: GeoCoordinate?

    public init(id: UUID = UUID(),
                kind: WarEventKind,
                date: HistoricalDate,
                title: String,
                detail: String = "",
                actorIDs: [String] = [],
                territoryIDs: [String] = [],
                coordinate: GeoCoordinate? = nil) {
        self.id = id
        self.kind = kind
        self.date = date
        self.title = title
        self.detail = detail
        self.actorIDs = actorIDs
        self.territoryIDs = territoryIDs
        self.coordinate = coordinate
    }
}

// MARK: - Factions and wars

/// A side in a war: Axis, Allies, Central Powers, the Delian League.
public struct Faction: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var colorHex: String
    public var memberCountryIDs: [String]
    /// The dominant member, used when the faction needs a single flag.
    public var leaderCountryID: String?

    public init(id: UUID = UUID(),
                name: String,
                colorHex: String,
                memberCountryIDs: [String] = [],
                leaderCountryID: String? = nil) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.memberCountryIDs = memberCountryIDs
        self.leaderCountryID = leaderCountryID
    }
}

/// How a simulated war is judged to have ended.
public enum VictoryCondition: Codable, Hashable, Sendable {
    /// One side holds every capital of the other.
    case capitalsCaptured
    /// One side controls at least this fraction of the contested territory.
    case territoryShare(Double)
    /// The war simply runs to its end date — the historical case.
    case scriptedEnd
    /// A named country capitulates.
    case capitulationOf(String)
}

/// A war: participants, timespan, and everything that happens inside it.
public struct War: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var interval: HistoricalInterval
    public var factions: [Faction]
    public var events: [WarEvent]
    public var battles: [BattleMarker]
    public var frontlines: [Frontline]
    public var armies: [Army]
    public var victoryCondition: VictoryCondition

    public init(id: UUID = UUID(),
                name: String,
                interval: HistoricalInterval,
                factions: [Faction] = [],
                events: [WarEvent] = [],
                battles: [BattleMarker] = [],
                frontlines: [Frontline] = [],
                armies: [Army] = [],
                victoryCondition: VictoryCondition = .scriptedEnd) {
        self.id = id
        self.name = name
        self.interval = interval
        self.factions = factions
        self.events = events
        self.battles = battles
        self.frontlines = frontlines
        self.armies = armies
        self.victoryCondition = victoryCondition
    }

    /// The faction a country belongs to, if any.
    public func faction(of countryID: String) -> Faction? {
        factions.first { $0.memberCountryIDs.contains(countryID) }
    }

    /// Whether two countries are on opposite sides.
    public func areEnemies(_ a: String, _ b: String) -> Bool {
        guard let factionA = faction(of: a), let factionB = faction(of: b) else { return false }
        return factionA.id != factionB.id
    }

    public var allParticipantIDs: [String] {
        factions.flatMap(\.memberCountryIDs)
    }
}
