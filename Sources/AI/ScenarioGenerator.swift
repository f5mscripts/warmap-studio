import Foundation

/// Turns a sentence into a scenario.
///
/// Deliberately a protocol with a working offline default: WarMap Studio must never
/// require an API key, a network, or an account to do anything. The offline
/// generator handles the shapes people actually type ("Germany attacks the USSR in
/// 1940") by matching countries and dates against the bundled catalogue; a remote
/// generator can be slotted in behind the same protocol if the user supplies a key.
public protocol ScenarioGenerator: Sendable {
    var name: String { get }
    var requiresNetwork: Bool { get }
    func generate(from prompt: String, into project: WarMapProject) async throws -> WarMapProject
}

/// The default generator. No key, no network, entirely local.
///
/// It is a parser, not a model: it finds the countries named in the prompt, the
/// years mentioned, and a verb suggesting who is attacking whom, then builds a
/// plausible timeline from the map's own adjacency. That covers the common case
/// honestly, and never invents a claim about history it cannot support.
public struct OfflineScenarioGenerator: ScenarioGenerator {

    public let name = "Built-in"
    public let requiresNetwork = false

    private let library: MapLibrary

    public init(library: MapLibrary = .shared) {
        self.library = library
    }

    public func generate(from prompt: String, into project: WarMapProject) async throws -> WarMapProject {
        let lowered = prompt.lowercased()

        let mentioned = matchCountries(in: lowered, from: project)
        guard mentioned.count >= 2 else {
            throw WarMapError.scenarioGenerationFailed(
                detail: "name at least two countries, for example “Germany attacks the USSR in 1940”"
            )
        }

        let years = matchYears(in: prompt)
        let start = years.first.map { HistoricalDate(year: $0) }
            ?? project.timeline.historicalRange.start
        let end = years.count > 1
            ? HistoricalDate(year: years[1])
            : start.adding(years: 4)

        let attacker = mentioned[0]
        let defender = mentioned[1]

        var updated = project
        var timeline = updated.activeTimeline
        timeline.historicalRange = HistoricalInterval(start: start, end: end)

        // Everything the defender holds that touches the attacker becomes the
        // opening front, which is what makes the generated invasion look sensible
        // instead of teleporting across the map.
        let units = try library.units()
        let neighbours = Dictionary(units.map { ($0.id, $0.neighbours) },
                                    uniquingKeysWith: { first, _ in first })
        let attackerUnits = timeline.initialOwnership
            .filter { $0.value == attacker.id }.map(\.key)
        let frontUnits = timeline.initialOwnership
            .filter { pair in
                pair.value == defender.id
                    && (neighbours[pair.key] ?? []).contains { attackerUnits.contains($0) }
            }
            .map(\.key)
            .sorted()

        var items: [TimelineItem] = []
        items.append(TimelineItem(
            title: "Opening title", start: 0, duration: 4, easing: .easeOut,
            action: .showText(TextElement(
                content: "\(attacker.name.uppercased()) ATTACKS \(defender.name.uppercased())",
                style: .title, animation: .historicalTitle))
        ))
        items.append(TimelineItem(
            title: "Date counter", start: 3, duration: timeline.duration - 3, easing: .linear,
            action: .showText(.dateCounter(format: .dayMonthNameYear))
        ))
        items.append(TimelineItem(
            title: "War declared", start: 2, duration: 0,
            action: .markEvent(WarEvent(kind: .warDeclared, date: start,
                                        title: "\(attacker.name) declares war",
                                        detail: prompt,
                                        actorIDs: [attacker.id, defender.id]))
        ))

        if frontUnits.isEmpty {
            // Not adjacent: say so on screen rather than silently producing nothing.
            items.append(TimelineItem(
                title: "No shared border", start: 4.5, duration: 4,
                action: .showText(TextElement(
                    content: "\(attacker.name) and \(defender.name) share no border",
                    style: .subtitle, animation: .fade))
            ))
        } else {
            var offset: TimeInterval = 5
            for unit in frontUnits.prefix(8) {
                items.append(TimelineItem(
                    title: "Advance into \(unit)", start: offset, duration: 2.4,
                    easing: .smoothStep,
                    action: .captureTerritory(units: [unit], attacker: attacker.id,
                                              bearing: 90)
                ))
                offset += 1.6
            }
        }

        timeline.items.append(contentsOf: items)
        updated.activeTimeline = timeline

        let war = War(
            name: "\(attacker.name)–\(defender.name) War",
            interval: HistoricalInterval(start: start, end: end),
            factions: [
                Faction(name: attacker.name, colorHex: attacker.colorHex,
                        memberCountryIDs: [attacker.id], leaderCountryID: attacker.id),
                Faction(name: defender.name, colorHex: defender.colorHex,
                        memberCountryIDs: [defender.id], leaderCountryID: defender.id),
            ]
        )
        updated.wars.append(war)
        return updated
    }

    /// Countries named in the prompt, in the order they appear — which is usually
    /// attacker first in English.
    private func matchCountries(in prompt: String, from project: WarMapProject) -> [Country] {
        var found: [(position: Int, country: Country)] = []
        let pool = project.countries.isEmpty ? CountryLibrary.all : project.countries

        for country in pool {
            let aliases = [country.name, country.displayName, country.shortName]
                .map { $0.lowercased() }
            for alias in aliases where alias.count > 2 {
                if let range = prompt.range(of: alias) {
                    let position = prompt.distance(from: prompt.startIndex,
                                                   to: range.lowerBound)
                    if !found.contains(where: { $0.country.id == country.id }) {
                        found.append((position, country))
                    }
                    break
                }
            }
        }
        return found.sorted { $0.position < $1.position }.map(\.country)
    }

    /// Four-digit years, in the order written.
    private func matchYears(in prompt: String) -> [Int] {
        var years: [Int] = []
        var digits = ""
        for character in prompt {
            if character.isNumber {
                digits.append(character)
            } else {
                if digits.count == 4, let year = Int(digits), (1000...2100).contains(year) {
                    years.append(year)
                }
                digits = ""
            }
        }
        if digits.count == 4, let year = Int(digits), (1000...2100).contains(year) {
            years.append(year)
        }
        return years
    }
}

/// Where an optional remote generator's key lives.
///
/// The Keychain, never source and never `UserDefaults`. Nothing in the app reads it
/// unless the user has explicitly pasted a key in, and removing the key returns the
/// app to fully offline operation.
public enum ScenarioAPIKeyStore {

    private static let service = "studio.warmap.scenario-generator"
    private static let account = "api-key"

    public static func save(_ key: String) throws {
        let data = Data(key.utf8)
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw WarMapError.scenarioGenerationFailed(
                detail: "the key could not be stored (Keychain status \(status))")
        }
    }

    public static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    public static var hasKey: Bool { load() != nil }
}
