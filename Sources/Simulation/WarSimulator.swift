import CoreGraphics
import Foundation

/// The national characteristics that decide how a country fights.
///
/// All values are relative rather than absolute — 1.0 is "an average major power of
/// the period". They are exposed directly in the Auto Simulator sheet.
public struct CountryStrength: Codable, Hashable, Sendable {
    public var military: Double
    public var economy: Double
    public var population: Double
    public var technology: Double
    public var supply: Double
    public var morale: Double

    public init(military: Double = 1,
                economy: Double = 1,
                population: Double = 1,
                technology: Double = 1,
                supply: Double = 1,
                morale: Double = 1) {
        self.military = military
        self.economy = economy
        self.population = population
        self.technology = technology
        self.supply = supply
        self.morale = morale
    }

    /// A single offensive figure. Military weight dominates; economy and population
    /// matter but with diminishing returns, which is why they are square-rooted.
    public var offensivePower: Double {
        military * technology * supply * (0.5 + 0.5 * morale)
            * (economy.squareRoot() * 0.6 + population.squareRoot() * 0.4)
    }

    /// Defence leans harder on manpower and morale than on technology.
    public var defensivePower: Double {
        military * (0.7 + 0.3 * technology) * supply * (0.4 + 0.6 * morale)
            * (population.squareRoot() * 0.6 + economy.squareRoot() * 0.4)
    }

    public static let major = CountryStrength(military: 1.4, economy: 1.4, population: 1.3,
                                              technology: 1.3, supply: 1.2, morale: 1.1)
    public static let minor = CountryStrength(military: 0.5, economy: 0.5, population: 0.5,
                                              technology: 0.8, supply: 0.8, morale: 1.0)
}

/// Knobs for the automatic war simulator.
public struct SimulationConfig: Codable, Hashable, Sendable {
    /// Seed for every random decision. Same seed, same war.
    public var seed: UInt64
    /// Days advanced per simulation step. Larger is faster and coarser.
    public var tickDays: Int
    /// Fraction of a territory an even fight takes per tick. Sets the overall pace.
    public var baseAdvancePerTick: Double
    /// How much luck can swing a single tick, 0…1. Zero makes the war a pure
    /// function of the strengths, which the determinism tests rely on.
    public var randomness: Double
    /// Multiplier applied to a defender fighting on its own soil.
    public var homeDefenceBonus: Double
    /// Penalty per extra front a country is attacking on — the cost of spreading thin.
    public var multiFrontPenalty: Double
    /// Morale lost by a country per territory it loses.
    public var moraleLossPerTerritory: Double
    /// A country capitulates once it holds this fraction or less of what it started
    /// with, or loses its capital.
    public var capitulationThreshold: Double

    public init(seed: UInt64 = 20_260_811,
                tickDays: Int = 7,
                baseAdvancePerTick: Double = 0.12,
                randomness: Double = 0.35,
                homeDefenceBonus: Double = 1.35,
                multiFrontPenalty: Double = 0.12,
                moraleLossPerTerritory: Double = 0.04,
                capitulationThreshold: Double = 0.25) {
        self.seed = seed
        self.tickDays = max(1, tickDays)
        self.baseAdvancePerTick = baseAdvancePerTick
        self.randomness = min(max(randomness, 0), 1)
        self.homeDefenceBonus = homeDefenceBonus
        self.multiFrontPenalty = multiFrontPenalty
        self.moraleLossPerTerritory = moraleLossPerTerritory
        self.capitulationThreshold = capitulationThreshold
    }

    public static let deterministic = SimulationConfig(randomness: 0)
}

/// What the simulator produced.
public struct SimulationResult: Sendable {
    /// Animation clips, ready to drop into a timeline.
    public var items: [TimelineItem]
    public var events: [WarEvent]
    public var finalOwnership: [String: String]
    /// Countries that capitulated, in the order they did.
    public var capitulated: [String]
    /// Human-readable trace, shown in the simulator sheet.
    public var log: [String]
}

/// Resolves a war between factions over territory.
///
/// The model is a front-based attrition one: every tick, each territory bordering an
/// enemy is pushed on by the strongest adjacent attacker, at a rate set by the odds
/// between them. It is not a claim about how these wars actually went — Historical
/// Mode exists precisely so that a scenario can replay recorded events instead. What
/// it does guarantee is that results are *believable and reproducible*: the same
/// seed and the same inputs always produce the same war.
public struct WarSimulator: Sendable {

    public let config: SimulationConfig
    private let neighbours: [String: [String]]
    private let anchors: [String: GeoCoordinate]
    private let capitalUnits: [String: String]

    /// - Parameters:
    ///   - neighbours: adjacency between territory units, from the map library.
    ///   - anchors: label anchor per unit, used to work out advance bearings.
    ///   - capitalUnits: the unit holding each country's capital, if known.
    public init(config: SimulationConfig = SimulationConfig(),
                neighbours: [String: [String]],
                anchors: [String: GeoCoordinate] = [:],
                capitalUnits: [String: String] = [:]) {
        self.config = config
        self.neighbours = neighbours
        self.anchors = anchors
        self.capitalUnits = capitalUnits
    }

    /// Convenience initialiser that pulls topology straight from the bundled map.
    public init(config: SimulationConfig = SimulationConfig(),
                library: MapLibrary,
                capitalUnits: [String: String] = [:]) throws {
        let units = try library.units()
        self.init(config: config,
                  neighbours: Dictionary(units.map { ($0.id, $0.neighbours) },
                                         uniquingKeysWith: { first, _ in first }),
                  anchors: Dictionary(units.map { ($0.id, $0.anchor) },
                                      uniquingKeysWith: { first, _ in first }),
                  capitalUnits: capitalUnits)
    }

    // MARK: - Simulation

    public func simulate(war: War,
                         initialOwnership: [String: String],
                         strengths: [String: CountryStrength],
                         timeline: Timeline) -> SimulationResult {

        var random = DeterministicRandom(seed: config.seed)
        var ownership = initialOwnership
        var morale = Dictionary(uniqueKeysWithValues: war.allParticipantIDs.map { ($0, 1.0) })
        var partialAdvance: [String: Double] = [:]
        var attackers: [String: String] = [:]

        var items: [TimelineItem] = []
        var events: [WarEvent] = []
        var capitulated: [String] = []
        var log: [String] = []

        let startingCount = countTerritories(ownership)
        var date = war.interval.start
        let end = war.interval.end

        while date < end {
            let next = date.adding(days: config.tickDays)

            // Every territory that currently borders an enemy is a potential front.
            for (unit, defender) in ownership.sorted(by: { $0.key < $1.key }) {
                guard !capitulated.contains(defender) else { continue }
                guard let attacker = strongestAttacker(on: unit,
                                                       defender: defender,
                                                       ownership: ownership,
                                                       war: war,
                                                       strengths: strengths,
                                                       morale: morale,
                                                       capitulated: capitulated)
                else {
                    // No enemy adjacent any more: the front has moved on and any
                    // partial progress here is given up.
                    partialAdvance.removeValue(forKey: unit)
                    attackers.removeValue(forKey: unit)
                    continue
                }

                let odds = combatOdds(attacker: attacker,
                                      defender: defender,
                                      strengths: strengths,
                                      morale: morale,
                                      ownership: ownership,
                                      war: war)
                let advance = config.baseAdvancePerTick * odds
                    * random.jitter(spread: config.randomness)

                let previous = partialAdvance[unit] ?? 0
                let accumulated = previous + max(0, advance)
                attackers[unit] = attacker

                guard accumulated >= 1 else {
                    partialAdvance[unit] = accumulated
                    continue
                }

                // Territory falls. The clip spans the ticks it actually took, so the
                // animation's pace reflects how hard the fight was.
                let ticksTaken = max(1.0, 1.0 / max(advance, 0.0001))
                let daysTaken = min(Double(config.tickDays) * ticksTaken,
                                    Double(next.days(since: war.interval.start)))
                let captureStart = next.adding(days: -Int(daysTaken))

                items.append(TimelineItem(
                    title: "\(attacker) takes \(unit)",
                    start: timeline.time(for: max(captureStart, war.interval.start)),
                    duration: max(0.2, timeline.time(for: next)
                                  - timeline.time(for: max(captureStart, war.interval.start))),
                    easing: .smoothStep,
                    action: .captureTerritory(units: [unit],
                                              attacker: attacker,
                                              bearing: bearing(from: attacker,
                                                               to: unit,
                                                               ownership: ownership))
                ))

                events.append(WarEvent(kind: .invasion,
                                       date: next,
                                       title: "\(unit) captured",
                                       detail: "\(attacker) takes \(unit) from \(defender)",
                                       actorIDs: [attacker, defender],
                                       territoryIDs: [unit],
                                       coordinate: anchors[unit]))

                ownership[unit] = attacker
                partialAdvance.removeValue(forKey: unit)
                morale[defender] = max(0, (morale[defender] ?? 1) - config.moraleLossPerTerritory)
                morale[attacker] = min(1.4, (morale[attacker] ?? 1) + config.moraleLossPerTerritory / 2)
                log.append("\(next.formatted(.dayMonthNameYear)): \(attacker) captured \(unit)")
            }

            // Check whether anyone has been knocked out.
            for country in war.allParticipantIDs where !capitulated.contains(country) {
                guard let starting = startingCount[country], starting > 0 else { continue }
                let remaining = countTerritories(ownership)[country] ?? 0
                let lostCapital = capitalUnits[country].map { ownership[$0] != country } ?? false
                let collapsed = Double(remaining) / Double(starting) <= config.capitulationThreshold

                if lostCapital || collapsed || remaining == 0 {
                    capitulated.append(country)
                    events.append(WarEvent(
                        kind: .capitulation,
                        date: next,
                        title: "\(country) capitulates",
                        detail: lostCapital ? "Capital captured" : "Territory collapsed",
                        actorIDs: [country]
                    ))
                    log.append("\(next.formatted(.dayMonthNameYear)): \(country) capitulated")
                }
            }

            if isDecided(war: war, capitulated: capitulated) { break }
            date = next
        }

        return SimulationResult(items: items.sorted { $0.start < $1.start },
                                events: events,
                                finalOwnership: ownership,
                                capitulated: capitulated,
                                log: log)
    }

    // MARK: - Combat model

    /// The strongest enemy country adjacent to a territory, or nil if none is.
    private func strongestAttacker(on unit: String,
                                   defender: String,
                                   ownership: [String: String],
                                   war: War,
                                   strengths: [String: CountryStrength],
                                   morale: [String: Double],
                                   capitulated: [String]) -> String? {
        var best: String?
        var bestPower = 0.0
        // Sorted for determinism: a dictionary's order must never decide a war.
        for neighbour in (neighbours[unit] ?? []).sorted() {
            guard let owner = ownership[neighbour],
                  owner != defender,
                  !capitulated.contains(owner),
                  war.areEnemies(owner, defender) else { continue }
            let power = (strengths[owner] ?? .minor).offensivePower * (morale[owner] ?? 1)
            if power > bestPower {
                bestPower = power
                best = owner
            }
        }
        return best
    }

    /// How decisively the attacker outmatches the defender, as a multiplier on the
    /// base advance rate. 1.0 means an even fight.
    private func combatOdds(attacker: String,
                            defender: String,
                            strengths: [String: CountryStrength],
                            morale: [String: Double],
                            ownership: [String: String],
                            war: War) -> Double {
        let attack = (strengths[attacker] ?? .minor).offensivePower
            * (morale[attacker] ?? 1)
            * frontPenalty(for: attacker, ownership: ownership, war: war)
        let defence = (strengths[defender] ?? .minor).defensivePower
            * (morale[defender] ?? 1)
            * config.homeDefenceBonus

        guard defence > 0 else { return 3 }
        // Bounded so a hopeless mismatch still takes time and a near-even fight still
        // moves — a front that never budges makes for a dull video.
        return min(max(attack / defence, 0.15), 3.0)
    }

    /// Attacking in many places at once costs momentum everywhere.
    private func frontPenalty(for country: String,
                              ownership: [String: String],
                              war: War) -> Double {
        var fronts = 0
        for (unit, owner) in ownership where owner == country {
            for neighbour in neighbours[unit] ?? [] {
                if let other = ownership[neighbour], war.areEnemies(country, other) {
                    fronts += 1
                    break
                }
            }
        }
        return 1 / (1 + config.multiFrontPenalty * Double(max(0, fronts - 1)))
    }

    /// Compass bearing of the advance, so the renderer sweeps the fill in from the
    /// side the attacker is actually on.
    private func bearing(from attacker: String,
                         to unit: String,
                         ownership: [String: String]) -> Double {
        guard let target = anchors[unit] else { return 90 }
        // Average the attacker's adjacent holdings to find where the push comes from.
        var sumLon = 0.0
        var sumLat = 0.0
        var count = 0.0
        for neighbour in neighbours[unit] ?? [] where ownership[neighbour] == attacker {
            guard let anchor = anchors[neighbour] else { continue }
            sumLon += anchor.longitude
            sumLat += anchor.latitude
            count += 1
        }
        guard count > 0 else { return 90 }
        let origin = GeoCoordinate(longitude: sumLon / count, latitude: sumLat / count)

        var deltaLon = target.longitude - origin.longitude
        if deltaLon > 180 { deltaLon -= 360 }
        if deltaLon < -180 { deltaLon += 360 }
        let deltaLat = target.latitude - origin.latitude
        // atan2(east, north) gives a compass bearing clockwise from north.
        let degrees = atan2(deltaLon, deltaLat) * 180 / .pi
        return degrees < 0 ? degrees + 360 : degrees
    }

    private func countTerritories(_ ownership: [String: String]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for (_, owner) in ownership { counts[owner, default: 0] += 1 }
        return counts
    }

    /// The war ends when one whole faction has capitulated.
    private func isDecided(war: War, capitulated: [String]) -> Bool {
        guard war.factions.count >= 2 else { return false }
        return war.factions.contains { faction in
            !faction.memberCountryIDs.isEmpty
                && faction.memberCountryIDs.allSatisfy { capitulated.contains($0) }
        }
    }
}
