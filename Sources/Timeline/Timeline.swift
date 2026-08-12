import CoreGraphics
import Foundation

/// The editing lanes shown in the timeline, top to bottom.
public enum TrackKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case map
    case countries
    case frontlines
    case armies
    case text
    case flags
    case audio
    case effects

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .map: return "MAP"
        case .countries: return "COUNTRIES"
        case .frontlines: return "FRONTLINES"
        case .armies: return "ARMIES"
        case .text: return "TEXT"
        case .flags: return "FLAGS"
        case .audio: return "AUDIO"
        case .effects: return "EFFECTS"
        }
    }

    public var tintHex: String {
        switch self {
        case .map: return "4A6E8A"
        case .countries: return "C9A227"
        case .frontlines: return "B3423A"
        case .armies: return "9C6B3F"
        case .text: return "A8A296"
        case .flags: return "4E8A5C"
        case .audio: return "7A6094"
        case .effects: return "C98A2B"
        }
    }

    public var symbolName: String {
        switch self {
        case .map: return "map"
        case .countries: return "flag.square"
        case .frontlines: return "chart.line.uptrend.xyaxis"
        case .armies: return "shield.lefthalf.filled"
        case .text: return "textformat"
        case .flags: return "flag"
        case .audio: return "waveform"
        case .effects: return "sparkles"
        }
    }
}

/// What a timeline item does when it plays.
public enum TimelineAction: Codable, Hashable, Sendable {
    /// Sweep territory from its current owner to `attacker` over the item's
    /// duration. `bearing` is the compass direction of the advance in degrees
    /// clockwise from north; it drives the half-plane sweep.
    case captureTerritory(units: [String], attacker: String, bearing: Double)
    /// Change ownership with no sweep — for treaty transfers and instant edits.
    case transferTerritory(units: [String], to: String)
    case captureCity(cityID: String, by: String)
    case spawnArmy(Army)
    case moveArmy(armyID: UUID, to: GeoCoordinate)
    case removeArmy(armyID: UUID)
    case showBattle(BattleMarker)
    case showFrontline(Frontline)
    case moveFrontline(frontlineID: UUID, to: [GeoCoordinate])
    case hideFrontline(frontlineID: UUID)
    case cameraMove(to: MapCamera)
    case showText(TextElement)
    /// The pre-war matchup card: both coalitions' flags, names and strength bars.
    case showVersusCard(VersusCard)
    /// Records something on the timeline without changing the map directly.
    case markEvent(WarEvent)

    /// The lane this action belongs in.
    public var track: TrackKind {
        switch self {
        case .captureTerritory, .transferTerritory, .captureCity: return .countries
        case .spawnArmy, .moveArmy, .removeArmy: return .armies
        case .showBattle: return .effects
        case .showFrontline, .moveFrontline, .hideFrontline: return .frontlines
        case .cameraMove: return .map
        case .showText, .showVersusCard: return .text
        case .markEvent: return .effects
        }
    }
}

/// One clip on the timeline.
public struct TimelineItem: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    /// Seconds from the start of the video.
    public var start: TimeInterval
    /// Seconds. Zero means instantaneous.
    public var duration: TimeInterval
    public var easing: EasingCurve
    public var action: TimelineAction
    public var isEnabled: Bool

    public init(id: UUID = UUID(),
                title: String,
                start: TimeInterval,
                duration: TimeInterval,
                easing: EasingCurve = .smoothStep,
                action: TimelineAction,
                isEnabled: Bool = true) {
        self.id = id
        self.title = title
        self.start = start
        self.duration = max(0, duration)
        self.easing = easing
        self.action = action
        self.isEnabled = isEnabled
    }

    public var end: TimeInterval { start + duration }
    public var track: TrackKind { action.track }

    /// Eased progress at a point in project time: 0 before it starts, 1 after it
    /// finishes.
    public func progress(at time: TimeInterval) -> Double {
        guard duration > 0 else { return time >= start ? 1 : 0 }
        return easing.apply(min(max((time - start) / duration, 0), 1))
    }

    public func isActive(at time: TimeInterval) -> Bool {
        time >= start && time <= end
    }
}

/// A territory mid-capture, drawn as a partial fill sweeping across the unit.
public struct ContestedTerritory: Hashable, Sendable {
    public var attackerID: String
    public var defenderID: String?
    /// 0…1 of the territory taken.
    public var progress: Double
    /// Direction of advance, degrees clockwise from north.
    public var bearing: Double

    public init(attackerID: String, defenderID: String?, progress: Double, bearing: Double) {
        self.attackerID = attackerID
        self.defenderID = defenderID
        self.progress = progress
        self.bearing = bearing
    }
}

/// Everything needed to draw one frame. Immutable, and the only thing the renderer
/// consumes — so the live preview and the exported video are drawing from an
/// identical description.
public struct WorldSnapshot: Sendable {
    public var time: TimeInterval
    public var date: HistoricalDate
    public var ownership: [String: String]
    public var contested: [String: ContestedTerritory]
    public var cityOwners: [String: String]
    public var armies: [Army]
    public var frontlines: [Frontline]
    public var battles: [BattleMarker]
    public var texts: [ResolvedText]
    /// The matchup card, if one is on screen at this instant.
    public var versusCard: ResolvedVersusCard?
    public var camera: MapCamera
    /// Events at or before this instant, most recent first — drives the event list.
    public var recentEvents: [WarEvent]

    public init(time: TimeInterval,
                date: HistoricalDate,
                ownership: [String: String] = [:],
                contested: [String: ContestedTerritory] = [:],
                cityOwners: [String: String] = [:],
                armies: [Army] = [],
                frontlines: [Frontline] = [],
                battles: [BattleMarker] = [],
                texts: [ResolvedText] = [],
                versusCard: ResolvedVersusCard? = nil,
                camera: MapCamera = .world,
                recentEvents: [WarEvent] = []) {
        self.time = time
        self.date = date
        self.ownership = ownership
        self.contested = contested
        self.cityOwners = cityOwners
        self.armies = armies
        self.frontlines = frontlines
        self.battles = battles
        self.texts = texts
        self.versusCard = versusCard
        self.camera = camera
        self.recentEvents = recentEvents
    }

    /// The country holding a unit, counting a capture as complete only once the
    /// sweep has finished.
    public func owner(of unitID: String) -> String? {
        ownership[unitID]
    }

    /// Territory count per country, for the statistics panel.
    public func territoryCounts() -> [String: Int] {
        var counts: [String: Int] = [:]
        for (_, owner) in ownership {
            counts[owner, default: 0] += 1
        }
        return counts
    }
}

/// A `VersusCard` resolved for one instant, with its fade applied.
public struct ResolvedVersusCard: Hashable, Sendable {
    public var card: VersusCard
    /// 0…1, so the card can fade in and out rather than snapping on.
    public var opacity: Double

    public init(card: VersusCard, opacity: Double) {
        self.card = card
        self.opacity = opacity
    }
}

/// The animated document: a span of history, a video duration, and the clips that
/// carry one into the other.
public struct Timeline: Codable, Hashable, Sendable {
    /// Length of the finished video in seconds.
    public var duration: TimeInterval
    /// The historical span the video covers.
    public var historicalRange: HistoricalInterval
    public var items: [TimelineItem]

    /// World state before any clip has played.
    public var initialOwnership: [String: String]
    public var initialCityOwners: [String: String]
    public var initialArmies: [Army]
    public var initialCamera: MapCamera

    public init(duration: TimeInterval = 30,
                historicalRange: HistoricalInterval,
                items: [TimelineItem] = [],
                initialOwnership: [String: String] = [:],
                initialCityOwners: [String: String] = [:],
                initialArmies: [Army] = [],
                initialCamera: MapCamera = .world) {
        self.duration = max(0.1, duration)
        self.historicalRange = historicalRange
        self.items = items
        self.initialOwnership = initialOwnership
        self.initialCityOwners = initialCityOwners
        self.initialArmies = initialArmies
        self.initialCamera = initialCamera
    }

    // MARK: - Time mapping

    /// The historical date shown at a point in the video.
    ///
    /// The mapping is linear: the video's duration is stretched evenly across the
    /// historical span. Pacing is expressed by *where clips sit*, not by warping the
    /// clock, which keeps the date counter honest and monotonic.
    public func date(at time: TimeInterval) -> HistoricalDate {
        historicalRange.date(atProgress: duration > 0 ? time / duration : 0)
    }

    /// Where a historical date falls in the video.
    public func time(for date: HistoricalDate) -> TimeInterval {
        historicalRange.progress(at: date) * duration
    }

    public func items(on track: TrackKind) -> [TimelineItem] {
        items.filter { $0.track == track }.sorted { $0.start < $1.start }
    }

    /// The last moment anything happens — used to suggest a duration.
    public var contentEnd: TimeInterval {
        items.map(\.end).max() ?? 0
    }

    public mutating func add(_ item: TimelineItem) {
        items.append(item)
    }

    public mutating func remove(id: UUID) {
        items.removeAll { $0.id == id }
    }

    public mutating func update(_ item: TimelineItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index] = item
    }
}
