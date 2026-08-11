import CoreGraphics
import Foundation

/// The preset scenarios the app ships with, including the demo seeded on first
/// launch.
///
/// Each is a fully-formed project rather than a template — open one, press Play, and
/// it runs. They are meant to be edited: nothing here is locked, and duplicating a
/// preset is the intended way to start something new.
public enum ScenarioLibrary {

    public struct Preset: Identifiable, Sendable {
        public let id: String
        public let name: String
        public let subtitle: String
        public let era: HistoricalEra
        public let periodLabel: String
        public let build: @Sendable () -> WarMapProject
    }

    public static var all: [Preset] {
        [
            Preset(id: "ww2-europe", name: "WW2 Europe — Demo",
                   subtitle: "European Front", era: .worldWarTwo,
                   periodLabel: "1939–1945", build: ww2Europe),
            Preset(id: "ww1", name: "World War I",
                   subtitle: "The Great War", era: .worldWarOne,
                   periodLabel: "1914–1918", build: worldWarOne),
            Preset(id: "napoleonic", name: "Napoleonic Wars",
                   subtitle: "Revolution and Empire", era: .napoleonic,
                   periodLabel: "1803–1815", build: napoleonic),
            Preset(id: "roman", name: "Roman Expansion",
                   subtitle: "Republic to Empire", era: .classical,
                   periodLabel: "264 BC–117 AD", build: romanExpansion),
            Preset(id: "cold-war", name: "Cold War",
                   subtitle: "Two blocs", era: .coldWar,
                   periodLabel: "1947–1991", build: coldWar),
        ]
    }

    public static func preset(_ id: String) -> Preset? {
        all.first { $0.id == id }
    }

    // MARK: - Shared helpers

    private static func countries(_ ids: [String]) -> [Country] {
        ids.compactMap { CountryLibrary.country($0) }
    }

    /// Expands a country → territory mapping into the ownership dictionary the
    /// timeline needs.
    private static func ownership(_ mapping: [String: [String]]) -> [String: String] {
        var result: [String: String] = [:]
        for (country, units) in mapping {
            for unit in units { result[unit] = country }
        }
        return result
    }

    private static func date(_ year: Int, _ month: Int = 1, _ day: Int = 1) -> HistoricalDate {
        HistoricalDate(year: year, month: month, day: day)
    }

    private static func camera(_ lon: Double, _ lat: Double, _ span: Double) -> MapCamera {
        MapCamera(center: GeoCoordinate(longitude: lon, latitude: lat), span: span)
    }

    // MARK: - WW2 Europe (the demo)

    /// The project seeded on first launch.
    ///
    /// Deliberately dense: within forty seconds it shows a title, a date counter,
    /// camera moves, four territorial sweeps with the right bearings, city captures,
    /// battle markers, a front, and an army — so pressing Play demonstrates most of
    /// what the app does without the user building anything first.
    public static func ww2Europe() -> WarMapProject {
        let start = date(1939, 9, 1)
        let end = date(1945, 5, 8)
        let range = HistoricalInterval(start: start, end: end)

        let ids = ["germany", "poland", "ussr", "france", "united_kingdom", "italy",
                   "slovakia", "romania", "hungary", "bulgaria", "yugoslavia",
                   "greece", "finland", "sweden", "norway", "denmark", "netherlands",
                   "belgium", "switzerland", "spain", "portugal", "ireland",
                   "estonia", "latvia", "lithuania", "turkey", "austria"]

        var initialOwnership = ownership([
            "germany": ["DEU", "AUT", "CZE", "RUS-KGD"],
            "slovakia": ["SVK"],
            "poland": ["POL", "UKR-W", "BLR-W"],
            "ussr": ["RUS", "UKR-E", "UKR-CRIMEA", "BLR-E", "KAZ", "GEO", "ARM", "AZE",
                     "UZB", "TKM", "KGZ", "TJK"],
            "france": ["FRA-OCC", "FRA-VICHY"],
            "united_kingdom": ["GBR"],
            "italy": ["ITA", "ALB"],
            "romania": ["ROU", "ROU-TRANS-N", "MDA"],
            "hungary": ["HUN"],
            "bulgaria": ["BGR"],
            "yugoslavia": ["SRB", "HRV", "BIH", "SVN", "MNE", "MKD"],
            "greece": ["GRC"],
            "finland": ["FIN", "FIN-KARELIA"],
            "sweden": ["SWE"],
            "norway": ["NOR"],
            "denmark": ["DNK"],
            "netherlands": ["NLD"],
            "belgium": ["BEL"],
            "switzerland": ["CHE"],
            "spain": ["ESP"],
            "portugal": ["PRT"],
            "ireland": ["IRL"],
            "estonia": ["EST"],
            "latvia": ["LVA"],
            "lithuania": ["LTU"],
            "turkey": ["TUR"],
        ])
        initialOwnership["LUX"] = "belgium"

        let duration: TimeInterval = 42
        var timeline = Timeline(duration: duration,
                                historicalRange: range,
                                initialOwnership: initialOwnership,
                                initialCamera: camera(14, 52, 46))

        func at(_ year: Int, _ month: Int, _ day: Int) -> TimeInterval {
            timeline.time(for: date(year, month, day))
        }

        var items: [TimelineItem] = []

        // Titles and the running date.
        items.append(TimelineItem(title: "Title", start: 0, duration: 4.5, easing: .easeOut,
                                  action: .showText(TextElement(
                                    content: "SEPTEMBER 1, 1939",
                                    style: .title,
                                    animation: .historicalTitle,
                                    position: CGPoint(x: 0.5, y: 0.17)))))
        items.append(TimelineItem(title: "Subtitle", start: 0.8, duration: 4, easing: .easeOut,
                                  action: .showText(TextElement(
                                    content: "Germany invades Poland",
                                    style: .subtitle,
                                    animation: .slideUp,
                                    position: CGPoint(x: 0.5, y: 0.245)))))
        items.append(TimelineItem(title: "Date counter", start: 3.5, duration: duration - 3.5,
                                  easing: .linear,
                                  action: .showText(.dateCounter(format: .dayMonthNameYear,
                                                                 position: CGPoint(x: 0.5, y: 0.06)))))

        // Camera: Europe, into Poland, west to France, then east to Moscow.
        items.append(TimelineItem(title: "Push in on Poland", start: 2.2, duration: 3.4,
                                  easing: .easeInOut, action: .cameraMove(to: camera(19.5, 52.2, 20))))
        items.append(TimelineItem(title: "Swing west", start: at(1940, 4, 1), duration: 3,
                                  easing: .easeInOut, action: .cameraMove(to: camera(6, 49.5, 26))))
        items.append(TimelineItem(title: "Turn east", start: at(1941, 5, 20), duration: 3.5,
                                  easing: .easeInOut, action: .cameraMove(to: camera(30, 53, 42))))
        items.append(TimelineItem(title: "Back to Europe", start: at(1944, 6, 1), duration: 3,
                                  easing: .easeInOut, action: .cameraMove(to: camera(16, 51, 48))))

        // 1939: the partition of Poland.
        items.append(TimelineItem(title: "Invasion of Poland", start: at(1939, 9, 1),
                                  duration: 2.4, easing: .smoothStep,
                                  action: .captureTerritory(units: ["POL"], attacker: "germany",
                                                            bearing: 100)))
        items.append(TimelineItem(title: "Soviet entry", start: at(1939, 9, 17),
                                  duration: 1.6, easing: .smoothStep,
                                  action: .captureTerritory(units: ["UKR-W", "BLR-W"],
                                                            attacker: "ussr", bearing: 270)))
        items.append(TimelineItem(title: "Warsaw falls", start: at(1939, 9, 27), duration: 0,
                                  action: .captureCity(cityID: "city.warsaw", by: "germany")))
        items.append(TimelineItem(title: "Siege of Warsaw", start: at(1939, 9, 8), duration: 2.2,
                                  action: .showBattle(BattleMarker(
                                    title: "Siege of Warsaw",
                                    detail: "Poland capitulates after 27 days",
                                    date: date(1939, 9, 8),
                                    coordinate: GeoCoordinate(longitude: 21.0, latitude: 52.23),
                                    kind: .siege,
                                    participantIDs: ["germany", "poland"]))))

        // 1940: Denmark, Norway, the Low Countries, France.
        items.append(TimelineItem(title: "Winter War", start: at(1940, 3, 13), duration: 1.2,
                                  easing: .smoothStep,
                                  action: .captureTerritory(units: ["FIN-KARELIA"],
                                                            attacker: "ussr", bearing: 300)))
        items.append(TimelineItem(title: "Denmark and Norway", start: at(1940, 4, 9),
                                  duration: 1.8, easing: .smoothStep,
                                  action: .captureTerritory(units: ["DNK", "NOR"],
                                                            attacker: "germany", bearing: 10)))
        items.append(TimelineItem(title: "The Low Countries", start: at(1940, 5, 10),
                                  duration: 1.2, easing: .smoothStep,
                                  action: .captureTerritory(units: ["NLD", "BEL", "LUX"],
                                                            attacker: "germany", bearing: 260)))
        items.append(TimelineItem(title: "Fall of France", start: at(1940, 5, 20),
                                  duration: 2.0, easing: .smoothStep,
                                  action: .captureTerritory(units: ["FRA-OCC"],
                                                            attacker: "germany", bearing: 235)))
        items.append(TimelineItem(title: "Vichy France", start: at(1940, 6, 22), duration: 0.6,
                                  easing: .easeOut,
                                  action: .transferTerritory(units: ["FRA-VICHY"],
                                                             to: "vichy_france")))
        items.append(TimelineItem(title: "Dunkirk", start: at(1940, 5, 26), duration: 1.6,
                                  action: .showBattle(BattleMarker(
                                    title: "Dunkirk",
                                    detail: "338,000 evacuated",
                                    date: date(1940, 5, 26),
                                    coordinate: GeoCoordinate(longitude: 2.38, latitude: 51.04),
                                    kind: .defensive,
                                    participantIDs: ["united_kingdom", "germany"]))))
        items.append(TimelineItem(title: "Paris falls", start: at(1940, 6, 14), duration: 0,
                                  action: .captureCity(cityID: "city.paris", by: "germany")))
        items.append(TimelineItem(title: "Baltic annexation", start: at(1940, 6, 15),
                                  duration: 1.0, easing: .smoothStep,
                                  action: .captureTerritory(units: ["EST", "LVA", "LTU"],
                                                            attacker: "ussr", bearing: 280)))

        // 1941: the Balkans and Barbarossa.
        items.append(TimelineItem(title: "Balkan campaign", start: at(1941, 4, 6),
                                  duration: 1.6, easing: .smoothStep,
                                  action: .captureTerritory(
                                    units: ["SRB", "HRV", "BIH", "SVN", "MNE", "MKD", "GRC"],
                                    attacker: "germany", bearing: 160)))
        items.append(TimelineItem(title: "Operation Barbarossa", start: at(1941, 6, 22),
                                  duration: 3.6, easing: .smoothStep,
                                  action: .captureTerritory(units: ["BLR-W", "BLR-E", "UKR-W"],
                                                            attacker: "germany", bearing: 75)))
        items.append(TimelineItem(title: "Into Ukraine", start: at(1941, 8, 1),
                                  duration: 2.6, easing: .smoothStep,
                                  action: .captureTerritory(units: ["UKR-E"],
                                                            attacker: "germany", bearing: 95)))
        items.append(TimelineItem(title: "Eastern Front", start: at(1941, 7, 1), duration: 0,
                                  action: .showFrontline(Frontline(
                                    name: "Eastern Front",
                                    points: [
                                        GeoCoordinate(longitude: 30.0, latitude: 59.5),
                                        GeoCoordinate(longitude: 32.5, latitude: 55.5),
                                        GeoCoordinate(longitude: 34.0, latitude: 51.0),
                                        GeoCoordinate(longitude: 35.5, latitude: 47.5),
                                    ],
                                    attackerID: "germany",
                                    defenderID: "ussr"))))
        // Held in a variable so the removal below can name the same formation --
        // a fresh UUID there would silently never match anything.
        let sixthArmy = Army(name: "German 6th Army",
                             countryID: "germany",
                             size: 250_000,
                             position: GeoCoordinate(longitude: 30.5, latitude: 50.4),
                             icon: .armour)
        items.append(TimelineItem(title: "6th Army", start: at(1941, 7, 1), duration: 0,
                                  action: .spawnArmy(sixthArmy)))
        items.append(TimelineItem(title: "6th Army advances", start: at(1942, 7, 17),
                                  duration: 2.4, easing: .easeInOut,
                                  action: .moveArmy(armyID: sixthArmy.id,
                                                    to: GeoCoordinate(longitude: 44.3,
                                                                      latitude: 48.7))))
        items.append(TimelineItem(title: "Battle of Moscow", start: at(1941, 10, 2), duration: 2.2,
                                  action: .showBattle(BattleMarker(
                                    title: "Battle of Moscow",
                                    detail: "German advance halted",
                                    date: date(1941, 10, 2),
                                    coordinate: GeoCoordinate(longitude: 37.6, latitude: 55.75),
                                    kind: .majorBattle,
                                    participantIDs: ["germany", "ussr"]))))

        // 1942–43: Stalingrad and the turn of the tide.
        items.append(TimelineItem(title: "Battle of Stalingrad", start: at(1942, 7, 17),
                                  duration: 3.0,
                                  action: .showBattle(BattleMarker(
                                    title: "Battle of Stalingrad",
                                    detail: "Major Soviet victory",
                                    date: date(1942, 7, 17),
                                    endDate: date(1943, 2, 2),
                                    coordinate: GeoCoordinate(longitude: 44.52, latitude: 48.72),
                                    kind: .majorBattle,
                                    participantIDs: ["germany", "ussr"]))))
        items.append(TimelineItem(title: "Stalingrad", start: at(1942, 7, 17), duration: 0,
                                  action: .markEvent(WarEvent(
                                    kind: .battle,
                                    date: date(1942, 7, 17),
                                    title: "Battle of Stalingrad",
                                    detail: "17 July 1942 — Major Soviet victory",
                                    actorIDs: ["germany", "ussr"]))))
        items.append(TimelineItem(title: "6th Army destroyed", start: at(1943, 2, 2), duration: 0,
                                  action: .removeArmy(armyID: sixthArmy.id)))
        items.append(TimelineItem(title: "Soviet counter-offensive", start: at(1943, 2, 2),
                                  duration: 3.4, easing: .smoothStep,
                                  action: .captureTerritory(units: ["UKR-E", "BLR-E"],
                                                            attacker: "ussr", bearing: 275)))
        items.append(TimelineItem(title: "Kursk", start: at(1943, 7, 5), duration: 1.6,
                                  action: .showBattle(BattleMarker(
                                    title: "Battle of Kursk",
                                    detail: "Largest tank battle in history",
                                    date: date(1943, 7, 5),
                                    coordinate: GeoCoordinate(longitude: 36.19, latitude: 51.73),
                                    kind: .majorBattle,
                                    participantIDs: ["germany", "ussr"]))))

        // 1944–45: liberation and collapse.
        items.append(TimelineItem(title: "D-Day", start: at(1944, 6, 6), duration: 1.4,
                                  action: .showBattle(BattleMarker(
                                    title: "Normandy Landings",
                                    detail: "Allied invasion of France",
                                    date: date(1944, 6, 6),
                                    coordinate: GeoCoordinate(longitude: -0.70, latitude: 49.35),
                                    kind: .offensive,
                                    participantIDs: ["united_kingdom", "germany"]))))
        items.append(TimelineItem(title: "Liberation of France", start: at(1944, 6, 6),
                                  duration: 2.4, easing: .smoothStep,
                                  action: .captureTerritory(units: ["FRA-OCC", "FRA-VICHY"],
                                                            attacker: "france", bearing: 80)))
        items.append(TimelineItem(title: "Liberation of the Low Countries",
                                  start: at(1944, 9, 3), duration: 1.4, easing: .smoothStep,
                                  action: .captureTerritory(units: ["BEL", "LUX", "NLD"],
                                                            attacker: "united_kingdom",
                                                            bearing: 60)))
        items.append(TimelineItem(title: "Soviet advance west", start: at(1944, 7, 1),
                                  duration: 3.2, easing: .smoothStep,
                                  action: .captureTerritory(units: ["POL", "UKR-W", "BLR-W",
                                                                    "ROU", "ROU-TRANS-N", "BGR"],
                                                            attacker: "ussr", bearing: 265)))
        items.append(TimelineItem(title: "Fall of Berlin", start: at(1945, 4, 16), duration: 1.8,
                                  easing: .smoothStep,
                                  action: .captureTerritory(units: ["DEU", "AUT", "CZE",
                                                                    "SVK", "RUS-KGD"],
                                                            attacker: "ussr", bearing: 265)))
        items.append(TimelineItem(title: "Battle of Berlin", start: at(1945, 4, 16), duration: 1.6,
                                  action: .showBattle(BattleMarker(
                                    title: "Battle of Berlin",
                                    detail: "8 May 1945 — Germany surrenders",
                                    date: date(1945, 4, 16),
                                    coordinate: GeoCoordinate(longitude: 13.4, latitude: 52.52),
                                    kind: .majorBattle,
                                    participantIDs: ["ussr", "germany"]))))
        items.append(TimelineItem(title: "Berlin falls", start: at(1945, 5, 2), duration: 0,
                                  action: .captureCity(cityID: "city.berlin", by: "ussr")))
        items.append(TimelineItem(title: "Closing title", start: duration - 4.5, duration: 4.4,
                                  easing: .easeOut,
                                  action: .showText(TextElement(
                                    content: "VICTORY IN EUROPE",
                                    style: .title,
                                    animation: .historicalTitle,
                                    position: CGPoint(x: 0.5, y: 0.45)))))

        timeline.items = items

        let axis = Faction(name: "Axis", colorHex: "5E6860",
                           memberCountryIDs: ["germany", "italy", "slovakia", "hungary",
                                              "romania", "bulgaria", "finland"],
                           leaderCountryID: "germany")
        let allies = Faction(name: "Allies", colorHex: "56749E",
                             memberCountryIDs: ["united_kingdom", "france", "ussr", "poland",
                                                "yugoslavia", "greece"],
                             leaderCountryID: "united_kingdom")

        let war = War(name: "Second World War",
                      interval: range,
                      factions: [axis, allies],
                      victoryCondition: .scriptedEnd)

        var catalogue = countries(ids)
        if let vichy = CountryLibrary.country("vichy_france") { catalogue.append(vichy) }

        return WarMapProject(
            name: "WW2 Europe — Demo",
            subtitle: "European Front",
            era: .worldWarTwo,
            mapRegionID: "europe",
            mapStyle: .military,
            exportPreset: .tiktok,
            timeline: timeline,
            countries: catalogue,
            wars: [war]
        )
    }

    // MARK: - Other presets

    public static func worldWarOne() -> WarMapProject {
        let range = HistoricalInterval(start: date(1914, 7, 28), end: date(1918, 11, 11))
        var timeline = Timeline(duration: 30,
                                historicalRange: range,
                                initialOwnership: ownership([
                                    "germany": ["DEU"],
                                    "austria_hungary": ["AUT", "HUN", "CZE", "SVK", "HRV",
                                                        "SVN", "BIH"],
                                    "ottoman_empire": ["TUR", "SYR", "IRQ", "ISR", "JOR", "LBN"],
                                    "france": ["FRA-OCC", "FRA-VICHY"],
                                    "united_kingdom": ["GBR"],
                                    "russian_empire": ["RUS", "UKR-W", "UKR-E", "UKR-CRIMEA",
                                                       "BLR-W", "BLR-E", "POL", "EST", "LVA",
                                                       "LTU", "FIN", "FIN-KARELIA"],
                                    "italy": ["ITA"],
                                    "romania": ["ROU", "ROU-TRANS-N", "MDA"],
                                    "bulgaria": ["BGR"],
                                    "greece": ["GRC"],
                                    "spain": ["ESP"],
                                    "netherlands": ["NLD"],
                                    "belgium": ["BEL"],
                                    "switzerland": ["CHE"],
                                ]),
                                initialCamera: camera(14, 50, 44))
        timeline.items = [
            TimelineItem(title: "Title", start: 0, duration: 4,
                         action: .showText(TextElement(content: "28 JULY 1914",
                                                       style: .title,
                                                       animation: .historicalTitle))),
            TimelineItem(title: "Date counter", start: 3, duration: 27, easing: .linear,
                         action: .showText(.dateCounter(format: .monthNameYear))),
            TimelineItem(title: "Invasion of Belgium",
                         start: timeline.time(for: date(1914, 8, 4)), duration: 1.5,
                         action: .captureTerritory(units: ["BEL"], attacker: "germany",
                                                   bearing: 250)),
            TimelineItem(title: "Western Front",
                         start: timeline.time(for: date(1914, 9, 12)), duration: 0,
                         action: .showFrontline(Frontline(
                            name: "Western Front",
                            points: [GeoCoordinate(longitude: 2.9, latitude: 51.0),
                                     GeoCoordinate(longitude: 3.2, latitude: 49.9),
                                     GeoCoordinate(longitude: 5.4, latitude: 49.2),
                                     GeoCoordinate(longitude: 7.5, latitude: 47.6)],
                            attackerID: "germany", defenderID: "france"))),
            TimelineItem(title: "Verdun",
                         start: timeline.time(for: date(1916, 2, 21)), duration: 2,
                         action: .showBattle(BattleMarker(
                            title: "Battle of Verdun",
                            detail: "Ten months of attrition",
                            date: date(1916, 2, 21),
                            coordinate: GeoCoordinate(longitude: 5.38, latitude: 49.16),
                            kind: .majorBattle))),
        ]
        return WarMapProject(name: "World War I", subtitle: "The Great War",
                             era: .worldWarOne, mapRegionID: "europe",
                             mapStyle: .antique, timeline: timeline,
                             countries: countries(["germany", "austria_hungary", "ottoman_empire",
                                                   "france", "united_kingdom", "russian_empire",
                                                   "italy", "romania", "bulgaria", "greece",
                                                   "belgium", "netherlands", "switzerland",
                                                   "spain"]))
    }

    public static func napoleonic() -> WarMapProject {
        let range = HistoricalInterval(start: date(1803, 5, 18), end: date(1815, 6, 18))
        var timeline = Timeline(duration: 30,
                                historicalRange: range,
                                initialOwnership: ownership([
                                    "french_empire": ["FRA-OCC", "FRA-VICHY", "BEL", "NLD"],
                                    "united_kingdom": ["GBR"],
                                    "prussia": ["DEU", "POL"],
                                    "austria_hungary": ["AUT", "HUN", "CZE", "SVK", "SVN", "HRV"],
                                    "russian_empire": ["RUS", "UKR-W", "UKR-E", "BLR-W", "BLR-E",
                                                       "LTU", "LVA", "EST", "FIN", "FIN-KARELIA"],
                                    "spain": ["ESP"],
                                    "portugal": ["PRT"],
                                    "ottoman_empire": ["TUR", "BGR", "GRC", "SRB", "MKD"],
                                    "denmark": ["DNK", "NOR"],
                                    "sweden": ["SWE"],
                                ]),
                                initialCamera: camera(14, 50, 50))
        timeline.items = [
            TimelineItem(title: "Title", start: 0, duration: 4,
                         action: .showText(TextElement(content: "NAPOLEONIC WARS",
                                                       style: .title,
                                                       animation: .historicalTitle))),
            TimelineItem(title: "Date counter", start: 3, duration: 27, easing: .linear,
                         action: .showText(.dateCounter(format: .yearOnly))),
            TimelineItem(title: "Austerlitz",
                         start: timeline.time(for: date(1805, 12, 2)), duration: 2,
                         action: .showBattle(BattleMarker(
                            title: "Austerlitz",
                            detail: "The Battle of the Three Emperors",
                            date: date(1805, 12, 2),
                            coordinate: GeoCoordinate(longitude: 16.76, latitude: 49.13),
                            kind: .majorBattle))),
            TimelineItem(title: "Invasion of Russia",
                         start: timeline.time(for: date(1812, 6, 24)), duration: 2.5,
                         action: .captureTerritory(units: ["BLR-W", "BLR-E"],
                                                   attacker: "french_empire", bearing: 70)),
            TimelineItem(title: "Waterloo",
                         start: timeline.time(for: date(1815, 6, 18)) - 1.5, duration: 1.5,
                         action: .showBattle(BATTLE_WATERLOO)),
        ]
        return WarMapProject(name: "Napoleonic Wars", subtitle: "Revolution and Empire",
                             era: .napoleonic, mapRegionID: "europe",
                             mapStyle: .parchment, timeline: timeline,
                             countries: countries(["french_empire", "united_kingdom", "prussia",
                                                   "austria_hungary", "russian_empire", "spain",
                                                   "portugal", "ottoman_empire", "denmark",
                                                   "sweden"]))
    }

    private static let BATTLE_WATERLOO = BattleMarker(
        title: "Waterloo",
        detail: "18 June 1815 — the end of the Hundred Days",
        date: HistoricalDate(year: 1815, month: 6, day: 18),
        coordinate: GeoCoordinate(longitude: 4.40, latitude: 50.68),
        kind: .majorBattle
    )

    public static func romanExpansion() -> WarMapProject {
        let range = HistoricalInterval(start: date(-263, 1, 1), end: date(117, 1, 1))
        var timeline = Timeline(duration: 34,
                                historicalRange: range,
                                initialOwnership: ownership([
                                    "roman_republic": ["ITA"],
                                    "carthage": ["TUN", "DZA", "MAR", "ESP"],
                                    "macedon": ["MKD", "GRC"],
                                ]),
                                initialCamera: camera(16, 38, 54))
        timeline.items = [
            TimelineItem(title: "Title", start: 0, duration: 4.5,
                         action: .showText(TextElement(content: "ROMAN EXPANSION",
                                                       style: .title,
                                                       animation: .historicalTitle))),
            TimelineItem(title: "Date counter", start: 3.5, duration: 30, easing: .linear,
                         action: .showText(.dateCounter(format: .yearOnly))),
            TimelineItem(title: "First Punic War",
                         start: timeline.time(for: date(-263, 1, 1)), duration: 3,
                         action: .captureTerritory(units: ["TUN"], attacker: "roman_republic",
                                                   bearing: 190)),
            TimelineItem(title: "Conquest of Greece",
                         start: timeline.time(for: date(-146, 1, 1)), duration: 2.5,
                         action: .captureTerritory(units: ["GRC", "MKD"],
                                                   attacker: "roman_republic", bearing: 110)),
            TimelineItem(title: "Gaul",
                         start: timeline.time(for: date(-58, 1, 1)), duration: 3,
                         action: .captureTerritory(units: ["FRA-OCC", "FRA-VICHY"],
                                                   attacker: "roman_republic", bearing: 320)),
            TimelineItem(title: "Egypt",
                         start: timeline.time(for: date(-30, 1, 1)), duration: 2,
                         action: .captureTerritory(units: ["EGY"], attacker: "roman_empire",
                                                   bearing: 150)),
            TimelineItem(title: "Britannia",
                         start: timeline.time(for: date(43, 1, 1)), duration: 2.5,
                         action: .captureTerritory(units: ["GBR"], attacker: "roman_empire",
                                                   bearing: 330)),
        ]
        return WarMapProject(name: "Roman Expansion", subtitle: "Republic to Empire",
                             era: .classical, mapRegionID: "mediterranean",
                             mapStyle: .parchment, timeline: timeline,
                             countries: countries(["roman_republic", "roman_empire", "carthage",
                                                   "macedon", "byzantine_empire"]))
    }

    public static func coldWar() -> WarMapProject {
        let range = HistoricalInterval(start: date(1947, 3, 12), end: date(1991, 12, 26))
        var timeline = Timeline(duration: 30,
                                historicalRange: range,
                                initialOwnership: ownership([
                                    "ussr": ["RUS", "UKR-W", "UKR-E", "UKR-CRIMEA", "BLR-W",
                                             "BLR-E", "EST", "LVA", "LTU", "KAZ", "UZB", "TKM",
                                             "KGZ", "TJK", "GEO", "ARM", "AZE", "MDA", "RUS-KGD",
                                             "POL", "CZE", "SVK", "HUN", "ROU", "ROU-TRANS-N",
                                             "BGR"],
                                    "united_states": ["USA"],
                                    "united_kingdom": ["GBR"],
                                    "france": ["FRA-OCC", "FRA-VICHY"],
                                    "germany": ["DEU"],
                                    "italy": ["ITA"],
                                    "turkey": ["TUR"],
                                ]),
                                initialCamera: camera(20, 50, 70))
        timeline.items = [
            TimelineItem(title: "Title", start: 0, duration: 4,
                         action: .showText(TextElement(content: "THE COLD WAR",
                                                       style: .title,
                                                       animation: .historicalTitle))),
            TimelineItem(title: "Date counter", start: 3, duration: 27, easing: .linear,
                         action: .showText(.dateCounter(format: .yearOnly))),
            TimelineItem(title: "Dissolution of the USSR",
                         start: timeline.time(for: date(1991, 12, 26)) - 3, duration: 3,
                         easing: .smoothStep,
                         action: .transferTerritory(units: ["UKR-W", "UKR-E", "UKR-CRIMEA"],
                                                    to: "ukraine")),
        ]
        return WarMapProject(name: "Cold War", subtitle: "Two blocs",
                             era: .coldWar, mapRegionID: "europe",
                             mapStyle: .atlas, timeline: timeline,
                             countries: countries(["ussr", "united_states", "united_kingdom",
                                                   "france", "germany", "italy", "turkey",
                                                   "ukraine", "russia"]))
    }
}
