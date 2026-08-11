import CoreGraphics
import Foundation

/// The built-in catalogue of countries, empires and other polities.
///
/// This is data, not UI. Adding a country means adding an entry here (or creating
/// one in the app, which produces the same type with `isCustom` set) — no view code
/// changes. Flags are declared per period so a country drawn on a 1914 map does not
/// fly its 1990 flag.
///
/// Coverage is deliberately deepest around the shipped scenarios — the World Wars,
/// the Napoleonic period, Rome and the Cold War — rather than spread thin across all
/// of history.
public enum CountryLibrary {

    public static let all: [Country] = europe + eurasia + asia + americas + ancient

    private static let byID: [String: Country] =
        Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

    public static func country(_ id: String) -> Country? { byID[id] }

    /// Countries that existed on a date, for the country picker and era filtering.
    public static func existing(on date: HistoricalDate) -> [Country] {
        all.filter { $0.exists(on: date) }
    }

    public static func inEra(_ era: HistoricalEra) -> [Country] {
        all.filter { $0.era == nil || $0.era == era || $0.exists(on: HistoricalDate(year: era.startYear)) }
    }

    // MARK: - Helpers

    private static func interval(_ from: Int, _ to: Int) -> HistoricalInterval {
        HistoricalInterval(start: HistoricalDate(year: from), end: HistoricalDate(year: to))
    }

    private static func flag(_ label: String,
                             _ spec: FlagSpec,
                             from: Int? = nil,
                             to: Int? = nil) -> HistoricalFlag {
        HistoricalFlag(label: label,
                       startDate: from.map { HistoricalDate(year: $0) },
                       endDate: to.map { HistoricalDate(year: $0) },
                       spec: spec)
    }

    // MARK: - Europe

    private static let europe: [Country] = [
        Country(
            id: "germany",
            name: "Germany",
            displayName: "German Reich",
            shortName: "GER",
            colorHex: "5E6860",
            kind: .empire,
            continent: .europe,
            capitalCityID: "city.berlin",
            existence: interval(1871, 1990),
            era: .worldWarTwo,
            flags: [
                flag("German Empire", FlagSpec.tricolourHorizontal("000000", "FFFFFF", "D00000"),
                     from: 1871, to: 1919),
                flag("Weimar Republic", FlagSpec.tricolourHorizontal("000000", "DD0000", "FFCE00"),
                     from: 1919, to: 1933),
                // 1935–1945: field colours only. WarMap Studio does not ship the
                // charge that sat on this flag; import an image per flag if you
                // need an exact reproduction.
                flag("Germany (1935–1945)",
                     FlagSpec(field: .solid("C8102E"),
                              overlays: [.disc(color: "FFFFFF", radius: 0.32,
                                               center: CGPoint(x: 0.5, y: 0.5))]),
                     from: 1933, to: 1945),
                flag("Federal Republic", FlagSpec.tricolourHorizontal("000000", "DD0000", "FFCE00"),
                     from: 1949),
            ],
            homeTerritoryIDs: ["DEU"]
        ),
        Country(
            id: "prussia",
            name: "Prussia",
            displayName: "Kingdom of Prussia",
            shortName: "PRU",
            colorHex: "3F4A54",
            kind: .kingdom,
            continent: .europe,
            capitalCityID: "city.berlin",
            existence: interval(1701, 1918),
            era: .nineteenthCentury,
            flags: [flag("Prussia", FlagSpec.bicolourHorizontal("FFFFFF", "111111"))],
            homeTerritoryIDs: ["DEU", "POL", "RUS-KGD"]
        ),
        Country(
            id: "austria_hungary",
            name: "Austria-Hungary",
            displayName: "Austro-Hungarian Empire",
            shortName: "A-H",
            colorHex: "9A8C6E",
            kind: .empire,
            continent: .europe,
            capitalCityID: "city.vienna",
            existence: interval(1867, 1918),
            era: .worldWarOne,
            flags: [flag("Austria-Hungary",
                         FlagSpec(field: .horizontal(["D00000", "FFFFFF", "D00000"]),
                                  overlays: [.stripe(color: "FFCE00", thickness: 0.06, position: 0.5)]))],
            homeTerritoryIDs: ["AUT", "HUN", "CZE", "SVK", "HRV", "SVN", "BIH"]
        ),
        Country(
            id: "austria",
            name: "Austria",
            shortName: "AUT",
            colorHex: "A8574F",
            kind: .republic,
            continent: .europe,
            capitalCityID: "city.vienna",
            era: .interwar,
            flags: [flag("Austria", FlagSpec.tricolourHorizontal("ED2939", "FFFFFF", "ED2939"))],
            homeTerritoryIDs: ["AUT"]
        ),
        Country(
            id: "poland",
            name: "Poland",
            displayName: "Republic of Poland",
            shortName: "POL",
            colorHex: "B04A44",
            kind: .republic,
            continent: .europe,
            capitalCityID: "city.warsaw",
            era: .interwar,
            flags: [flag("Poland",
                         FlagSpec(field: .horizontal(["FFFFFF", "DC143C"]),
                                  overlays: [.border(color: "8A8A8A", thickness: 0.01)]))],
            homeTerritoryIDs: ["POL", "UKR-W", "BLR-W"]
        ),
        Country(
            id: "france",
            name: "France",
            displayName: "French Republic",
            shortName: "FRA",
            colorHex: "56749E",
            kind: .republic,
            continent: .europe,
            capitalCityID: "city.paris",
            flags: [
                flag("Kingdom of France", FlagSpec.solid("FFFFFF"), to: 1792),
                flag("France", FlagSpec.tricolourVertical("002395", "FFFFFF", "ED2939"), from: 1792),
            ],
            homeTerritoryIDs: ["FRA-OCC", "FRA-VICHY"]
        ),
        Country(
            id: "vichy_france",
            name: "Vichy France",
            displayName: "French State",
            shortName: "VF",
            colorHex: "8B93A8",
            kind: .puppetState,
            continent: .europe,
            existence: interval(1940, 1944),
            era: .worldWarTwo,
            flags: [flag("French State", FlagSpec.tricolourVertical("002395", "FFFFFF", "ED2939"),
                         from: 1940, to: 1944)],
            homeTerritoryIDs: ["FRA-VICHY"]
        ),
        Country(
            id: "french_empire",
            name: "France",
            displayName: "First French Empire",
            shortName: "FRA",
            colorHex: "4B6FA5",
            kind: .empire,
            continent: .europe,
            capitalCityID: "city.paris",
            existence: interval(1804, 1815),
            era: .napoleonic,
            flags: [flag("First French Empire",
                         FlagSpec.tricolourVertical("002395", "FFFFFF", "ED2939"),
                         from: 1804, to: 1815)],
            homeTerritoryIDs: ["FRA-OCC", "FRA-VICHY", "BEL", "NLD"]
        ),
        Country(
            id: "united_kingdom",
            name: "United Kingdom",
            displayName: "United Kingdom",
            shortName: "UK",
            colorHex: "7A6094",
            kind: .kingdom,
            continent: .europe,
            capitalCityID: "city.london",
            flags: [flag("United Kingdom",
                         FlagSpec(field: .solid("012169"),
                                  overlays: [
                                    .saltire(color: "FFFFFF", thickness: 0.20),
                                    .saltire(color: "C8102E", thickness: 0.10),
                                    .cross(color: "FFFFFF", thickness: 0.30, offsetFromHoist: 0.5),
                                    .cross(color: "C8102E", thickness: 0.18, offsetFromHoist: 0.5),
                                  ]))],
            homeTerritoryIDs: ["GBR"]
        ),
        Country(
            id: "british_empire",
            name: "British Empire",
            displayName: "British Empire",
            shortName: "GBR",
            colorHex: "6A5488",
            kind: .empire,
            continent: .europe,
            capitalCityID: "city.london",
            existence: interval(1707, 1949),
            era: .nineteenthCentury,
            flags: [flag("British Empire",
                         FlagSpec(field: .solid("012169"),
                                  overlays: [
                                    .saltire(color: "FFFFFF", thickness: 0.20),
                                    .saltire(color: "C8102E", thickness: 0.10),
                                    .cross(color: "FFFFFF", thickness: 0.30, offsetFromHoist: 0.5),
                                    .cross(color: "C8102E", thickness: 0.18, offsetFromHoist: 0.5),
                                  ]))],
            homeTerritoryIDs: ["GBR", "IND", "AUS", "CAN", "NZL", "ZAF"]
        ),
        Country(
            id: "italy",
            name: "Italy",
            displayName: "Kingdom of Italy",
            shortName: "ITA",
            colorHex: "808A54",
            kind: .kingdom,
            continent: .europe,
            capitalCityID: "city.rome",
            existence: interval(1861, 1946),
            era: .worldWarTwo,
            flags: [
                flag("Kingdom of Italy", FlagSpec.tricolourVertical("008C45", "FFFFFF", "CD212A"),
                     to: 1946),
                flag("Italian Republic", FlagSpec.tricolourVertical("008C45", "FFFFFF", "CD212A"),
                     from: 1946),
            ],
            homeTerritoryIDs: ["ITA"]
        ),
        Country(
            id: "spain",
            name: "Spain",
            shortName: "ESP",
            colorHex: "A28A54",
            kind: .kingdom,
            continent: .europe,
            capitalCityID: "city.madrid",
            flags: [flag("Spain", FlagSpec(field: .horizontal(["AA151B", "F1BF00", "AA151B"])))],
            homeTerritoryIDs: ["ESP"]
        ),
        Country(
            id: "portugal",
            name: "Portugal",
            shortName: "POR",
            colorHex: "6E8464",
            kind: .republic,
            continent: .europe,
            capitalCityID: "city.lisbon",
            flags: [flag("Portugal", FlagSpec(field: .vertical(["006600", "FF0000"])))],
            homeTerritoryIDs: ["PRT"]
        ),
        Country(
            id: "netherlands",
            name: "Netherlands",
            shortName: "NLD",
            colorHex: "B08252",
            kind: .kingdom,
            continent: .europe,
            capitalCityID: "city.amsterdam",
            flags: [flag("Netherlands", FlagSpec.tricolourHorizontal("AE1C28", "FFFFFF", "21468B"))],
            homeTerritoryIDs: ["NLD"]
        ),
        Country(
            id: "belgium",
            name: "Belgium",
            shortName: "BEL",
            colorHex: "988C60",
            kind: .kingdom,
            continent: .europe,
            capitalCityID: "city.brussels",
            flags: [flag("Belgium", FlagSpec.tricolourVertical("000000", "FDDA24", "EF3340"))],
            homeTerritoryIDs: ["BEL"]
        ),
        Country(
            id: "switzerland",
            name: "Switzerland",
            shortName: "SUI",
            colorHex: "806060",
            kind: .federation,
            continent: .europe,
            flags: [flag("Switzerland",
                         FlagSpec(field: .solid("FF0000"),
                                  overlays: [.cross(color: "FFFFFF", thickness: 0.20,
                                                    offsetFromHoist: 0.5)],
                                  aspectRatio: 1.0))],
            homeTerritoryIDs: ["CHE"]
        ),
        Country(
            id: "denmark",
            name: "Denmark",
            shortName: "DEN",
            colorHex: "9E7670",
            kind: .kingdom,
            continent: .europe,
            capitalCityID: "city.copenhagen",
            flags: [flag("Denmark", FlagSpec.nordicCross(field: "C8102E", cross: "FFFFFF"))],
            homeTerritoryIDs: ["DNK"]
        ),
        Country(
            id: "norway",
            name: "Norway",
            shortName: "NOR",
            colorHex: "6E8094",
            kind: .kingdom,
            continent: .europe,
            capitalCityID: "city.oslo",
            flags: [flag("Norway",
                         FlagSpec(field: .solid("BA0C2F"),
                                  overlays: [
                                    .cross(color: "FFFFFF", thickness: 0.25, offsetFromHoist: 0.36),
                                    .cross(color: "00205B", thickness: 0.125, offsetFromHoist: 0.36),
                                  ],
                                  aspectRatio: 1.375))],
            homeTerritoryIDs: ["NOR"]
        ),
        Country(
            id: "sweden",
            name: "Sweden",
            shortName: "SWE",
            colorHex: "60768C",
            kind: .kingdom,
            continent: .europe,
            capitalCityID: "city.stockholm",
            flags: [flag("Sweden", FlagSpec.nordicCross(field: "006AA7", cross: "FECC00"))],
            homeTerritoryIDs: ["SWE"]
        ),
        Country(
            id: "finland",
            name: "Finland",
            shortName: "FIN",
            colorHex: "8C98A0",
            kind: .republic,
            continent: .europe,
            capitalCityID: "city.helsinki",
            flags: [flag("Finland", FlagSpec.nordicCross(field: "FFFFFF", cross: "002F6C"))],
            homeTerritoryIDs: ["FIN", "FIN-KARELIA"]
        ),
        Country(
            id: "czechoslovakia",
            name: "Czechoslovakia",
            shortName: "CZS",
            colorHex: "7E8A6E",
            kind: .republic,
            continent: .europe,
            capitalCityID: "city.prague",
            existence: interval(1918, 1993),
            era: .interwar,
            flags: [flag("Czechoslovakia",
                         FlagSpec(field: .horizontal(["FFFFFF", "D7141A"]),
                                  overlays: [.hoistTriangle(color: "11457E", widthFraction: 0.5)]))],
            homeTerritoryIDs: ["CZE", "SVK"]
        ),
        Country(
            id: "slovakia",
            name: "Slovakia",
            displayName: "Slovak Republic",
            shortName: "SVK",
            colorHex: "848A70",
            kind: .puppetState,
            continent: .europe,
            existence: interval(1939, 1945),
            era: .worldWarTwo,
            flags: [flag("Slovak Republic",
                         FlagSpec.tricolourHorizontal("FFFFFF", "0B4EA2", "EE1C25"),
                         from: 1939, to: 1945)],
            homeTerritoryIDs: ["SVK"]
        ),
        Country(
            id: "yugoslavia",
            name: "Yugoslavia",
            displayName: "Kingdom of Yugoslavia",
            shortName: "YUG",
            colorHex: "6C8474",
            kind: .kingdom,
            continent: .europe,
            capitalCityID: "city.belgrade",
            existence: interval(1918, 1992),
            era: .interwar,
            flags: [flag("Yugoslavia", FlagSpec.tricolourHorizontal("003893", "FFFFFF", "C6363C"))],
            homeTerritoryIDs: ["SRB", "HRV", "BIH", "SVN", "MNE", "MKD"]
        ),
        Country(
            id: "romania",
            name: "Romania",
            shortName: "ROU",
            colorHex: "A88448",
            kind: .kingdom,
            continent: .europe,
            capitalCityID: "city.bucharest",
            flags: [flag("Romania", FlagSpec.tricolourVertical("002B7F", "FCD116", "CE1126"))],
            homeTerritoryIDs: ["ROU", "ROU-TRANS-N", "MDA"]
        ),
        Country(
            id: "hungary",
            name: "Hungary",
            shortName: "HUN",
            colorHex: "8C7658",
            kind: .kingdom,
            continent: .europe,
            capitalCityID: "city.budapest",
            flags: [flag("Hungary", FlagSpec.tricolourHorizontal("CE2939", "FFFFFF", "477050"))],
            homeTerritoryIDs: ["HUN"]
        ),
        Country(
            id: "bulgaria",
            name: "Bulgaria",
            shortName: "BUL",
            colorHex: "786C4C",
            kind: .kingdom,
            continent: .europe,
            capitalCityID: "city.sofia",
            flags: [flag("Bulgaria", FlagSpec.tricolourHorizontal("FFFFFF", "00966E", "D62612"))],
            homeTerritoryIDs: ["BGR"]
        ),
        Country(
            id: "greece",
            name: "Greece",
            shortName: "GRE",
            colorHex: "5C7E98",
            kind: .kingdom,
            continent: .europe,
            capitalCityID: "city.athens",
            flags: [flag("Greece",
                         FlagSpec(field: .horizontal(["0D5EAF", "FFFFFF", "0D5EAF", "FFFFFF",
                                                      "0D5EAF", "FFFFFF", "0D5EAF", "FFFFFF",
                                                      "0D5EAF"]),
                                  overlays: [.canton(color: "0D5EAF", widthFraction: 0.44,
                                                     heightFraction: 0.55),
                                             .cross(color: "FFFFFF", thickness: 0.06,
                                                    offsetFromHoist: 0.22)]))],
            homeTerritoryIDs: ["GRC"]
        ),
        Country(
            id: "ireland",
            name: "Ireland",
            shortName: "IRL",
            colorHex: "64866C",
            kind: .republic,
            continent: .europe,
            capitalCityID: "city.dublin",
            flags: [flag("Ireland", FlagSpec.tricolourVertical("169B62", "FFFFFF", "FF883E"))],
            homeTerritoryIDs: ["IRL"]
        ),
        Country(
            id: "estonia",
            name: "Estonia",
            shortName: "EST",
            colorHex: "808C94",
            kind: .republic,
            continent: .europe,
            capitalCityID: "city.tallinn",
            flags: [flag("Estonia", FlagSpec.tricolourHorizontal("0072CE", "000000", "FFFFFF"))],
            homeTerritoryIDs: ["EST"]
        ),
        Country(
            id: "latvia",
            name: "Latvia",
            shortName: "LVA",
            colorHex: "887470",
            kind: .republic,
            continent: .europe,
            capitalCityID: "city.riga",
            flags: [flag("Latvia",
                         FlagSpec(field: .horizontal(["9E3039", "FFFFFF", "9E3039"])))],
            homeTerritoryIDs: ["LVA"]
        ),
        Country(
            id: "lithuania",
            name: "Lithuania",
            shortName: "LTU",
            colorHex: "908064",
            kind: .republic,
            continent: .europe,
            capitalCityID: "city.vilnius",
            flags: [flag("Lithuania", FlagSpec.tricolourHorizontal("FDB913", "006A44", "C1272D"))],
            homeTerritoryIDs: ["LTU"]
        ),
    ]

    // MARK: - Eurasia

    private static let eurasia: [Country] = [
        Country(
            id: "ussr",
            name: "Soviet Union",
            displayName: "Union of Soviet Socialist Republics",
            shortName: "USSR",
            colorHex: "962C2C",
            kind: .unionOfRepublics,
            continent: .europe,
            capitalCityID: "city.moscow",
            existence: interval(1922, 1991),
            era: .worldWarTwo,
            flags: [flag("Soviet Union",
                         FlagSpec(field: .solid("CC0000"),
                                  overlays: [.star(color: "FFD700", points: 5, radius: 0.10,
                                                   center: CGPoint(x: 0.18, y: 0.26))]),
                         from: 1922, to: 1991)],
            homeTerritoryIDs: ["RUS", "UKR-E", "UKR-CRIMEA", "BLR-E", "KAZ", "UZB",
                               "TKM", "KGZ", "TJK", "GEO", "ARM", "AZE"]
        ),
        Country(
            id: "russian_empire",
            name: "Russia",
            displayName: "Russian Empire",
            shortName: "RUS",
            colorHex: "7C5A4A",
            kind: .empire,
            continent: .europe,
            capitalCityID: "city.st_petersburg",
            existence: interval(1721, 1917),
            era: .worldWarOne,
            flags: [flag("Russian Empire",
                         FlagSpec.tricolourHorizontal("FFFFFF", "0033A0", "DA291C"),
                         to: 1917)],
            homeTerritoryIDs: ["RUS", "UKR-E", "UKR-W", "BLR-E", "BLR-W", "POL",
                               "EST", "LVA", "LTU", "FIN", "FIN-KARELIA"]
        ),
        Country(
            id: "russia",
            name: "Russia",
            displayName: "Russian Federation",
            shortName: "RUS",
            colorHex: "8C4A44",
            kind: .federation,
            continent: .europe,
            capitalCityID: "city.moscow",
            era: .modern,
            flags: [flag("Russia", FlagSpec.tricolourHorizontal("FFFFFF", "0033A0", "DA291C"),
                         from: 1991)],
            homeTerritoryIDs: ["RUS", "RUS-KGD"]
        ),
        Country(
            id: "ottoman_empire",
            name: "Ottoman Empire",
            displayName: "Ottoman Empire",
            shortName: "OTT",
            colorHex: "96684C",
            kind: .empire,
            continent: .middleEast,
            capitalCityID: "city.istanbul",
            existence: interval(1299, 1922),
            era: .worldWarOne,
            flags: [flag("Ottoman Empire",
                         FlagSpec(field: .solid("E30A17"),
                                  overlays: [
                                    .crescent(color: "FFFFFF", radius: 0.24,
                                              center: CGPoint(x: 0.40, y: 0.5)),
                                    .star(color: "FFFFFF", points: 5, radius: 0.09,
                                          center: CGPoint(x: 0.60, y: 0.5)),
                                  ]),
                         to: 1922)],
            homeTerritoryIDs: ["TUR", "SYR", "IRQ", "ISR", "JOR", "LBN", "SAU", "EGY", "LBY"]
        ),
        Country(
            id: "turkey",
            name: "Turkey",
            displayName: "Republic of Türkiye",
            shortName: "TUR",
            colorHex: "966C50",
            kind: .republic,
            continent: .middleEast,
            capitalCityID: "city.ankara",
            era: .modern,
            flags: [flag("Türkiye",
                         FlagSpec(field: .solid("E30A17"),
                                  overlays: [
                                    .crescent(color: "FFFFFF", radius: 0.24,
                                              center: CGPoint(x: 0.40, y: 0.5)),
                                    .star(color: "FFFFFF", points: 5, radius: 0.09,
                                          center: CGPoint(x: 0.60, y: 0.5)),
                                  ]),
                         from: 1923)],
            homeTerritoryIDs: ["TUR"]
        ),
        Country(
            id: "ukraine",
            name: "Ukraine",
            shortName: "UKR",
            colorHex: "5A7CA8",
            kind: .republic,
            continent: .europe,
            capitalCityID: "city.kyiv",
            era: .modern,
            flags: [flag("Ukraine", FlagSpec.bicolourHorizontal("0057B7", "FFD700"))],
            homeTerritoryIDs: ["UKR-W", "UKR-E", "UKR-CRIMEA"]
        ),
    ]

    // MARK: - Asia

    private static let asia: [Country] = [
        Country(
            id: "japan",
            name: "Japan",
            displayName: "Empire of Japan",
            shortName: "JPN",
            colorHex: "A85858",
            kind: .empire,
            continent: .asia,
            capitalCityID: "city.tokyo",
            era: .worldWarTwo,
            flags: [flag("Japan",
                         FlagSpec(field: .solid("FFFFFF"),
                                  overlays: [
                                    .disc(color: "BC002D", radius: 0.30,
                                          center: CGPoint(x: 0.5, y: 0.5)),
                                    .border(color: "8A8A8A", thickness: 0.01),
                                  ]))],
            homeTerritoryIDs: ["JPN"]
        ),
        Country(
            id: "china",
            name: "China",
            displayName: "Republic of China",
            shortName: "CHN",
            colorHex: "B08A44",
            kind: .republic,
            continent: .asia,
            capitalCityID: "city.beijing",
            era: .worldWarTwo,
            flags: [flag("Republic of China",
                         FlagSpec(field: .solid("EE1C25"),
                                  overlays: [.canton(color: "0033A0", widthFraction: 0.5,
                                                     heightFraction: 0.5),
                                             .star(color: "FFFFFF", points: 12, radius: 0.12,
                                                   center: CGPoint(x: 0.25, y: 0.25))]),
                         to: 1949),
                    flag("People's Republic of China",
                         FlagSpec(field: .solid("EE1C25"),
                                  overlays: [.star(color: "FFDE00", points: 5, radius: 0.14,
                                                   center: CGPoint(x: 0.17, y: 0.28))]),
                         from: 1949)],
            homeTerritoryIDs: ["CHN"]
        ),
        Country(
            id: "india",
            name: "India",
            shortName: "IND",
            colorHex: "C08040",
            kind: .republic,
            continent: .asia,
            era: .modern,
            flags: [flag("India",
                         FlagSpec(field: .horizontal(["FF9933", "FFFFFF", "138808"]),
                                  overlays: [.disc(color: "000080", radius: 0.08,
                                                   center: CGPoint(x: 0.5, y: 0.5))]))],
            homeTerritoryIDs: ["IND"]
        ),
    ]

    // MARK: - Americas

    private static let americas: [Country] = [
        Country(
            id: "united_states",
            name: "United States",
            displayName: "United States of America",
            shortName: "USA",
            colorHex: "4A6E8A",
            kind: .federation,
            continent: .northAmerica,
            capitalCityID: "city.washington_dc",
            flags: [flag("United States",
                         FlagSpec(field: .horizontal(["B22234", "FFFFFF", "B22234", "FFFFFF",
                                                      "B22234", "FFFFFF", "B22234", "FFFFFF",
                                                      "B22234", "FFFFFF", "B22234", "FFFFFF",
                                                      "B22234"]),
                                  overlays: [.canton(color: "3C3B6E", widthFraction: 0.4,
                                                     heightFraction: 0.54)],
                                  aspectRatio: 1.9))],
            homeTerritoryIDs: ["USA"]
        ),
        Country(
            id: "canada",
            name: "Canada",
            shortName: "CAN",
            colorHex: "8A5A5A",
            kind: .dominion,
            continent: .northAmerica,
            flags: [flag("Canada",
                         FlagSpec(field: .vertical(["D80621", "FFFFFF", "D80621"]),
                                  overlays: [.disc(color: "D80621", radius: 0.16,
                                                   center: CGPoint(x: 0.5, y: 0.5))],
                                  aspectRatio: 2.0))],
            homeTerritoryIDs: ["CAN"]
        ),
        Country(
            id: "brazil",
            name: "Brazil",
            shortName: "BRA",
            colorHex: "5A8A5A",
            kind: .republic,
            continent: .southAmerica,
            flags: [flag("Brazil",
                         FlagSpec(field: .solid("009739"),
                                  overlays: [.disc(color: "002776", radius: 0.24,
                                                   center: CGPoint(x: 0.5, y: 0.5))]))],
            homeTerritoryIDs: ["BRA"]
        ),
    ]

    // MARK: - Ancient and classical

    private static let ancient: [Country] = [
        Country(
            id: "roman_republic",
            name: "Rome",
            displayName: "Roman Republic",
            shortName: "ROM",
            colorHex: "8E3B3B",
            kind: .republic,
            continent: .europe,
            capitalCityID: "city.rome",
            existence: interval(-509, -27),
            era: .classical,
            flags: [flag("Roman Republic",
                         FlagSpec(field: .solid("8E1600"),
                                  overlays: [.star(color: "D4AF37", points: 4, radius: 0.28,
                                                   center: CGPoint(x: 0.5, y: 0.5))]),
                         to: -27)],
            homeTerritoryIDs: ["ITA"]
        ),
        Country(
            id: "roman_empire",
            name: "Rome",
            displayName: "Roman Empire",
            shortName: "ROM",
            colorHex: "9E3535",
            kind: .empire,
            continent: .europe,
            capitalCityID: "city.rome",
            existence: interval(-27, 476),
            era: .classical,
            flags: [flag("Roman Empire",
                         FlagSpec(field: .solid("7E1310"),
                                  overlays: [.star(color: "D4AF37", points: 4, radius: 0.28,
                                                   center: CGPoint(x: 0.5, y: 0.5))]),
                         from: -27, to: 476)],
            homeTerritoryIDs: ["ITA", "FRA-OCC", "FRA-VICHY", "ESP", "PRT", "GRC",
                               "TUR", "EGY", "TUN", "DZA", "MAR", "SYR", "ISR", "GBR"]
        ),
        Country(
            id: "byzantine_empire",
            name: "Byzantium",
            displayName: "Byzantine Empire",
            shortName: "BYZ",
            colorHex: "7B3F8E",
            kind: .empire,
            continent: .europe,
            capitalCityID: "city.istanbul",
            existence: interval(395, 1453),
            era: .medieval,
            flags: [flag("Byzantine Empire",
                         FlagSpec(field: .solid("6E0A14"),
                                  overlays: [.cross(color: "D4AF37", thickness: 0.16,
                                                    offsetFromHoist: 0.5)]),
                         from: 395, to: 1453)],
            homeTerritoryIDs: ["TUR", "GRC", "BGR", "MKD", "ALB"]
        ),
        Country(
            id: "carthage",
            name: "Carthage",
            displayName: "Carthaginian Republic",
            shortName: "CAR",
            colorHex: "3F6E8E",
            kind: .republic,
            continent: .africa,
            capitalCityID: "city.carthage",
            existence: interval(-814, -146),
            era: .classical,
            flags: [flag("Carthage",
                         FlagSpec(field: .solid("1E4E6E"),
                                  overlays: [.crescent(color: "E8DCC0", radius: 0.26,
                                                       center: CGPoint(x: 0.45, y: 0.5))]),
                         to: -146)],
            homeTerritoryIDs: ["TUN", "DZA", "MAR", "ESP"]
        ),
        Country(
            id: "macedon",
            name: "Macedon",
            displayName: "Kingdom of Macedon",
            shortName: "MAC",
            colorHex: "4E6E8E",
            kind: .kingdom,
            continent: .europe,
            existence: interval(-808, -168),
            era: .classical,
            flags: [flag("Macedon",
                         FlagSpec(field: .solid("D4A017"),
                                  overlays: [.star(color: "8E1600", points: 8, radius: 0.30,
                                                   center: CGPoint(x: 0.5, y: 0.5))]),
                         to: -168)],
            homeTerritoryIDs: ["MKD", "GRC"]
        ),
    ]
}
