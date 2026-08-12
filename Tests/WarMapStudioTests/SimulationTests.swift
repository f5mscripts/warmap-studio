import XCTest
@testable import WarMapStudio

final class SimulationTests: XCTestCase {

    // MARK: - Random source

    func testSeededRandomIsReproducible() {
        var a = DeterministicRandom(seed: 42)
        var b = DeterministicRandom(seed: 42)
        for _ in 0..<200 {
            XCTAssertEqual(a.next(), b.next())
        }
    }

    func testDifferentSeedsDiverge() {
        var a = DeterministicRandom(seed: 1)
        var b = DeterministicRandom(seed: 2)
        let left = (0..<20).map { _ in a.next() }
        let right = (0..<20).map { _ in b.next() }
        XCTAssertNotEqual(left, right)
    }

    func testUnitValuesStayInRangeAndSpreadOut() {
        var random = DeterministicRandom(seed: 7)
        var sum = 0.0
        let count = 5_000
        for _ in 0..<count {
            let value = random.unit()
            XCTAssertGreaterThanOrEqual(value, 0)
            XCTAssertLessThan(value, 1)
            sum += value
        }
        // A uniform generator should average near 0.5; this catches a badly broken
        // one without being flaky.
        XCTAssertEqual(sum / Double(count), 0.5, accuracy: 0.03)
    }

    func testJitterWithZeroSpreadIsExactlyOne() {
        var random = DeterministicRandom(seed: 99)
        for _ in 0..<50 {
            XCTAssertEqual(random.jitter(spread: 0), 1.0)
        }
    }

    func testDerivedStreamsAreIndependentAndStable() {
        let base = DeterministicRandom(seed: 5)
        var first = base.stream("combat")
        var second = base.stream("weather")
        var firstAgain = base.stream("combat")
        XCTAssertNotEqual(first.next(), second.next())
        // Same label from the same base must give the same stream every time.
        var firstOnceMore = base.stream("combat")
        XCTAssertEqual(firstOnceMore.next(), firstAgain.next())
    }

    // MARK: - Combat model

    func testStrongerCountriesHaveHigherPower() {
        XCTAssertGreaterThan(CountryStrength.major.offensivePower,
                             CountryStrength.minor.offensivePower)
        XCTAssertGreaterThan(CountryStrength.major.defensivePower,
                             CountryStrength.minor.defensivePower)
    }

    func testMoraleAndSupplyReduceCombatPower() {
        let healthy = CountryStrength(military: 1, supply: 1, morale: 1)
        let starving = CountryStrength(military: 1, supply: 0.3, morale: 0.3)
        XCTAssertGreaterThan(healthy.offensivePower, starving.offensivePower * 1.5)
    }

    func testArmyCombatPowerFallsWithCasualtiesAndBrokenMorale() {
        let fresh = Army(name: "6th Army", countryID: "germany", size: 250_000,
                         position: GeoCoordinate(longitude: 44, latitude: 48))
        var spent = fresh
        spent.strength = 0.3
        spent.morale = 0.2
        XCTAssertLessThan(spent.combatPower, fresh.combatPower * 0.5)
        XCTAssertTrue(spent.isBroken)
        XCTAssertFalse(fresh.isBroken)
    }

    func testArmySplitConservesManpower() {
        let army = Army(name: "Army Group Centre", countryID: "germany", size: 400_000,
                        position: GeoCoordinate(longitude: 30, latitude: 53))
        let (remaining, detached) = army.split(fraction: 0.25, name: "Detachment")
        XCTAssertEqual(remaining.size + detached.size, 400_000)
        XCTAssertNotEqual(remaining.id, detached.id)
        XCTAssertEqual(detached.name, "Detachment")
    }

    func testArmyMergeAveragesConditionBySize() {
        var big = Army(name: "Big", countryID: "ussr", size: 300_000,
                       position: GeoCoordinate(longitude: 37, latitude: 55))
        big.morale = 1.0
        var small = Army(name: "Small", countryID: "ussr", size: 100_000,
                         position: GeoCoordinate(longitude: 37, latitude: 55))
        small.morale = 0.2

        let merged = big.merged(with: small)
        XCTAssertEqual(merged.size, 400_000)
        // Weighted 3:1 towards the larger formation.
        XCTAssertEqual(merged.morale, 0.8, accuracy: 0.001)
    }

    // MARK: - The simulator

    /// A tiny three-territory world: A and B are allies facing C.
    private func makeFixture() -> (War, [String: String], [String: CountryStrength], Timeline, WarSimulator) {
        let neighbours = [
            "T1": ["T2"],
            "T2": ["T1", "T3"],
            "T3": ["T2"],
        ]
        let anchors = [
            "T1": GeoCoordinate(longitude: 10, latitude: 50),
            "T2": GeoCoordinate(longitude: 20, latitude: 50),
            "T3": GeoCoordinate(longitude: 30, latitude: 50),
        ]
        let war = War(
            name: "Test War",
            interval: HistoricalInterval(start: HistoricalDate(year: 1939, month: 9, day: 1),
                                         end: HistoricalDate(year: 1941, month: 9, day: 1)),
            factions: [
                Faction(name: "Attackers", colorHex: "5E6860", memberCountryIDs: ["attacker"]),
                Faction(name: "Defenders", colorHex: "B04A44", memberCountryIDs: ["defender"]),
            ]
        )
        let ownership = ["T1": "attacker", "T2": "defender", "T3": "defender"]
        let strengths = ["attacker": CountryStrength.major, "defender": CountryStrength.minor]
        let timeline = Timeline(duration: 20, historicalRange: war.interval,
                                initialOwnership: ownership)
        let simulator = WarSimulator(config: .deterministic,
                                     neighbours: neighbours,
                                     anchors: anchors,
                                     capitalUnits: ["defender": "T3"])
        return (war, ownership, strengths, timeline, simulator)
    }

    func testTheStrongerSideTakesGround() {
        let (war, ownership, strengths, timeline, simulator) = makeFixture()
        let result = simulator.simulate(war: war, initialOwnership: ownership,
                                        strengths: strengths, timeline: timeline)
        XCTAssertEqual(result.finalOwnership["T2"], "attacker",
                       "a major power should overrun a minor one's border province")
        XCTAssertFalse(result.items.isEmpty, "the simulation should produce animation clips")
        XCTAssertFalse(result.events.isEmpty)
    }

    func testSimulationIsReproducibleForAGivenSeed() {
        let (war, ownership, strengths, timeline, _) = makeFixture()
        let config = SimulationConfig(seed: 12_345, randomness: 0.5)
        let neighbours = ["T1": ["T2"], "T2": ["T1", "T3"], "T3": ["T2"]]

        func run() -> SimulationResult {
            WarSimulator(config: config, neighbours: neighbours)
                .simulate(war: war, initialOwnership: ownership,
                          strengths: strengths, timeline: timeline)
        }

        let first = run()
        let second = run()
        XCTAssertEqual(first.finalOwnership, second.finalOwnership)
        XCTAssertEqual(first.log, second.log)
        XCTAssertEqual(first.items.map(\.start), second.items.map(\.start))
    }

    func testDifferentSeedsCanProduceDifferentWars() {
        let (war, ownership, strengths, timeline, _) = makeFixture()
        let neighbours = ["T1": ["T2"], "T2": ["T1", "T3"], "T3": ["T2"]]

        func run(seed: UInt64) -> [String] {
            WarSimulator(config: SimulationConfig(seed: seed, randomness: 0.9),
                         neighbours: neighbours)
                .simulate(war: war, initialOwnership: ownership,
                          strengths: strengths, timeline: timeline).log
        }

        // With high randomness the timing of captures should vary between seeds.
        let a = run(seed: 1)
        let b = run(seed: 999_999)
        XCTAssertNotEqual(a, b, "randomness should actually affect the outcome")
    }

    func testCapitulationIsRecordedWhenTheCapitalFalls() {
        let (war, ownership, strengths, timeline, simulator) = makeFixture()
        let result = simulator.simulate(war: war, initialOwnership: ownership,
                                        strengths: strengths, timeline: timeline)
        XCTAssertTrue(result.capitulated.contains("defender"))
        XCTAssertTrue(result.events.contains { $0.kind == .capitulation })
    }

    func testAWeakAttackerDoesNotSweepTheBoard() {
        let (war, ownership, _, timeline, simulator) = makeFixture()
        // Invert the strengths: now the defender is the major power.
        let strengths = ["attacker": CountryStrength.minor, "defender": CountryStrength.major]
        let result = simulator.simulate(war: war, initialOwnership: ownership,
                                        strengths: strengths, timeline: timeline)
        XCTAssertEqual(result.finalOwnership["T3"], "defender",
                       "a minor power should not reach the far side in two years")
    }

    func testGeneratedClipsFallInsideTheVideoAndAnimateOwnership() {
        let (war, ownership, strengths, timeline, simulator) = makeFixture()
        let result = simulator.simulate(war: war, initialOwnership: ownership,
                                        strengths: strengths, timeline: timeline)

        for item in result.items {
            XCTAssertGreaterThanOrEqual(item.start, 0)
            XCTAssertLessThanOrEqual(item.start, timeline.duration + 0.001)
            XCTAssertGreaterThan(item.duration, 0, "a capture needs time to animate")
        }

        // Feeding the clips back through the evaluator must reproduce the same
        // final ownership the simulator reported.
        var animated = timeline
        animated.items = result.items
        let snapshot = TimelineEvaluator(timeline: animated).snapshot(at: timeline.duration)
        for (unit, owner) in result.finalOwnership {
            XCTAssertEqual(snapshot.ownership[unit], owner,
                           "\(unit) ended up differently in the animation than in the simulation")
        }
    }

    func testSimulatorBuildsFromTheBundledMapTopology() throws {
        let simulator = try WarSimulator(config: .deterministic, library: MapLibrary(bundle: .main))
        let war = War(name: "Border War",
                      interval: HistoricalInterval(start: HistoricalDate(year: 1939, month: 9, day: 1),
                                                   end: HistoricalDate(year: 1939, month: 10, day: 6)),
                      factions: [
                        Faction(name: "Germany", colorHex: "5E6860", memberCountryIDs: ["germany"]),
                        Faction(name: "Poland", colorHex: "B04A44", memberCountryIDs: ["poland"]),
                      ])
        let ownership = ["DEU": "germany", "POL": "poland",
                         "UKR-W": "poland", "BLR-W": "poland"]
        let timeline = Timeline(duration: 12, historicalRange: war.interval,
                                initialOwnership: ownership)
        let result = simulator.simulate(
            war: war,
            initialOwnership: ownership,
            strengths: ["germany": .major, "poland": .minor],
            timeline: timeline
        )
        XCTAssertFalse(result.items.isEmpty,
                       "Germany bordering Poland should generate at least one capture")
        XCTAssertTrue(result.items.allSatisfy { item in
            if case .captureTerritory(_, let attacker, _) = item.action {
                return attacker == "germany"
            }
            return true
        })
    }

    // MARK: - Coalitions

    /// Two countries a side, in a line: alpha and beta face gamma and delta.
    ///
    /// `weakScale` shrinks the second coalition's countries, so the matchup can be
    /// set anywhere from even to hopeless.
    private func coalitionFixture(weakScale: Double)
    -> (War, [String: String], [String: CountryStrength], Timeline, [String: [String]], [String: String]) {
        let neighbours = [
            "T1": ["T2"], "T2": ["T1", "T3"], "T3": ["T2", "T4"],
            "T4": ["T3", "T5"], "T5": ["T4", "T6"], "T6": ["T5"],
        ]
        let war = War(
            name: "Coalition War",
            interval: HistoricalInterval(start: HistoricalDate(year: 1939, month: 9, day: 1),
                                         end: HistoricalDate(year: 1941, month: 9, day: 1)),
            factions: [
                Faction(name: "Alliance", colorHex: "5E6860",
                        memberCountryIDs: ["alpha", "beta"]),
                Faction(name: "Coalition", colorHex: "B04A44",
                        memberCountryIDs: ["gamma", "delta"]),
            ]
        )
        let ownership = ["T1": "alpha", "T2": "alpha", "T3": "beta",
                         "T4": "gamma", "T5": "delta", "T6": "delta"]
        let strengths: [String: CountryStrength] = [
            "alpha": .major,
            "beta": CountryStrength(military: 0.9, economy: 0.9, population: 0.9),
            "gamma": CountryStrength(military: 1.4 * weakScale, economy: 1.4 * weakScale,
                                     population: 1.3 * weakScale, technology: 1.3,
                                     supply: 1.2, morale: 1.1),
            "delta": CountryStrength(military: 0.9 * weakScale, economy: 0.9 * weakScale,
                                     population: 0.9 * weakScale),
        ]
        let timeline = Timeline(duration: 20, historicalRange: war.interval,
                                initialOwnership: ownership)
        let capitals = ["alpha": "T1", "beta": "T3", "gamma": "T4", "delta": "T6"]
        return (war, ownership, strengths, timeline, neighbours, capitals)
    }

    /// Territories held by each side at the end.
    private func territoryTally(_ ownership: [String: String], war: War) -> [Int] {
        war.factions.map { faction in
            ownership.values.filter { faction.memberCountryIDs.contains($0) }.count
        }
    }

    func testCoalitionPoolingHasDiminishingReturns() throws {
        let simulator = WarSimulator(config: SimulationConfig(), neighbours: [:])
        let interval = HistoricalInterval(start: HistoricalDate(year: 1939),
                                          end: HistoricalDate(year: 1941))
        let war = War(name: "Big", interval: interval, factions: [
            Faction(name: "Five", colorHex: "000000",
                    memberCountryIDs: ["a", "b", "c", "d", "e"]),
            Faction(name: "One", colorHex: "FFFFFF", memberCountryIDs: ["z"]),
        ])
        let even = Dictionary(uniqueKeysWithValues:
            ["a", "b", "c", "d", "e", "z"].map { ($0, CountryStrength.major) })
        let state = simulator.coalitionState(war: war, strengths: even,
                                             morale: [:], capitulated: [], fortune: [:])

        let five = try XCTUnwrap(state.offence[war.factions[0].id])
        let one = try XCTUnwrap(state.offence[war.factions[1].id])
        // Five average powers are worth about 3.9 of one, not five.
        XCTAssertEqual(five / one, pow(5, 0.85), accuracy: 0.001)
        XCTAssertGreaterThan(five, one * 3, "numbers should still count for a lot")
        XCTAssertLessThan(five, one * 5, "but not simply add up")

        // A member that has capitulated stops contributing.
        let reduced = simulator.coalitionState(war: war, strengths: even, morale: [:],
                                               capitulated: ["a", "b"], fortune: [:])
        XCTAssertLessThan(try XCTUnwrap(reduced.offence[war.factions[0].id]), five)
    }

    func testFortuneIsDrawnOncePerWarAndVariesWithTheSeed() {
        let (war, _, _, _, neighbours, _) = coalitionFixture(weakScale: 0.8)

        func fortunes(seed: UInt64, randomness: Double = 0.35) -> [Double] {
            let simulator = WarSimulator(config: SimulationConfig(seed: seed,
                                                                  randomness: randomness),
                                         neighbours: neighbours)
            return war.factions.map { simulator.fortunes(for: war)[$0.id] ?? 1 }
        }

        XCTAssertEqual(fortunes(seed: 7), fortunes(seed: 7), "a seed must fix the luck")
        XCTAssertNotEqual(fortunes(seed: 7), fortunes(seed: 8))
        // Within ±35% at the default randomness, and switched off entirely at zero.
        for value in fortunes(seed: 7) {
            XCTAssertGreaterThanOrEqual(value, 0.65)
            XCTAssertLessThanOrEqual(value, 1.35)
        }
        XCTAssertEqual(fortunes(seed: 7, randomness: 0), [1, 1],
                       "no luck means no fortune roll either")
    }

    /// The point of the fortune roll: a moderately weaker coalition has to win
    /// sometimes, or "luck" is a slider that changes nothing.
    ///
    /// Two hundred seeds of the same matchup. Per-tick jitter alone cannot do this —
    /// over a hundred ticks it averages out to almost exactly 1, which is what the
    /// companion test below records.
    func testAWeakerCoalitionWinsARespectableShareOfWars() {
        let (war, ownership, strengths, timeline, neighbours, capitals) =
            coalitionFixture(weakScale: 0.8)

        var upsets = 0
        let seeds = 200
        for seed in 1...UInt64(seeds) {
            let simulator = WarSimulator(config: SimulationConfig(seed: seed),
                                         neighbours: neighbours,
                                         capitalUnits: capitals)
            let result = simulator.simulate(war: war, initialOwnership: ownership,
                                            strengths: strengths, timeline: timeline)
            let tally = territoryTally(result.finalOwnership, war: war)
            if tally[1] > tally[0] { upsets += 1 }
        }

        let rate = Double(upsets) / Double(seeds)
        XCTAssertGreaterThanOrEqual(rate, 0.15,
                                    "the underdog never winning makes the seed meaningless")
        XCTAssertLessThanOrEqual(rate, 0.35,
                                 "the underdog winning this often makes strength meaningless")
    }

    func testWithoutTheFortuneRollTheUnderdogNeverWins() {
        let (war, ownership, strengths, timeline, neighbours, capitals) =
            coalitionFixture(weakScale: 0.8)

        var upsets = 0
        for seed in 1...UInt64(40) {
            // Per-tick jitter at full strength, but no per-war luck.
            let config = SimulationConfig(seed: seed, randomness: 0.35, warFortune: 0)
            let result = WarSimulator(config: config, neighbours: neighbours,
                                      capitalUnits: capitals)
                .simulate(war: war, initialOwnership: ownership,
                          strengths: strengths, timeline: timeline)
            let tally = territoryTally(result.finalOwnership, war: war)
            if tally[1] > tally[0] { upsets += 1 }
        }
        XCTAssertEqual(upsets, 0,
                       "tick-level randomness averages out; this is why fortune exists")
    }

    func testAnAllyOnTheFrontFightsHarderWithABigPartnerBehindIt() throws {
        let neighbours = ["T1": ["T2"], "T2": ["T1"]]
        let interval = HistoricalInterval(start: HistoricalDate(year: 1939, month: 9, day: 1),
                                          end: HistoricalDate(year: 1941, month: 9, day: 1))
        let ownership = ["T1": "small", "T2": "target"]
        let timeline = Timeline(duration: 20, historicalRange: interval,
                                initialOwnership: ownership)
        let strengths: [String: CountryStrength] = [
            "small": .minor, "giant": .major, "target": .minor,
        ]

        func captureDate(alliedWithGiant: Bool) throws -> HistoricalDate {
            let members = alliedWithGiant ? ["small", "giant"] : ["small"]
            let war = War(name: "W", interval: interval, factions: [
                Faction(name: "A", colorHex: "000000", memberCountryIDs: members),
                Faction(name: "B", colorHex: "FFFFFF", memberCountryIDs: ["target"]),
            ])
            let result = WarSimulator(config: .deterministic, neighbours: neighbours)
                .simulate(war: war, initialOwnership: ownership,
                          strengths: strengths, timeline: timeline)
            return try XCTUnwrap(result.events.first { $0.kind == .invasion }?.date,
                                 "the border province should fall either way")
        }

        // The giant holds no territory here — it is purely the weight behind the
        // small ally standing on the border, so the only thing that can make the
        // attack land sooner is coalition support reaching the front.
        XCTAssertLessThan(try captureDate(alliedWithGiant: true),
                          try captureDate(alliedWithGiant: false),
                          "coalition support should reach the country actually fighting")
    }

    func testBearingPointsFromTheAttackerTowardsTheTarget() {
        // T1 is west of T2, so an advance from T1 into T2 should read as due east.
        let simulator = WarSimulator(
            config: .deterministic,
            neighbours: ["T1": ["T2"], "T2": ["T1"]],
            anchors: ["T1": GeoCoordinate(longitude: 10, latitude: 50),
                      "T2": GeoCoordinate(longitude: 20, latitude: 50)]
        )
        let war = War(name: "W",
                      interval: HistoricalInterval(start: HistoricalDate(year: 1940),
                                                   end: HistoricalDate(year: 1941)),
                      factions: [
                        Faction(name: "A", colorHex: "000000", memberCountryIDs: ["a"]),
                        Faction(name: "B", colorHex: "FFFFFF", memberCountryIDs: ["b"]),
                      ])
        let ownership = ["T1": "a", "T2": "b"]
        let timeline = Timeline(duration: 10,
                                historicalRange: war.interval,
                                initialOwnership: ownership)
        let result = simulator.simulate(war: war, initialOwnership: ownership,
                                        strengths: ["a": .major, "b": .minor],
                                        timeline: timeline)

        let bearings = result.items.compactMap { item -> Double? in
            if case .captureTerritory(_, _, let bearing) = item.action { return bearing }
            return nil
        }
        XCTAssertFalse(bearings.isEmpty)
        for bearing in bearings {
            XCTAssertEqual(bearing, 90, accuracy: 1, "an advance eastwards should bear 090")
        }
    }
}
