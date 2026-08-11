import Foundation

/// An alternate-history branch.
///
/// A branch carries its own complete timeline copied from the point of divergence,
/// so exploring "what if France survives?" can never disturb the original. Branches
/// nest: a branch can itself be branched.
public struct ScenarioBranch: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    /// `nil` means it forked from the project's original timeline.
    public var parentID: UUID?
    public var divergenceDate: HistoricalDate
    public var note: String
    public var timeline: Timeline
    public var createdAt: Date

    public init(id: UUID = UUID(),
                name: String,
                parentID: UUID? = nil,
                divergenceDate: HistoricalDate,
                note: String = "",
                timeline: Timeline,
                createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.parentID = parentID
        self.divergenceDate = divergenceDate
        self.note = note
        self.timeline = timeline
        self.createdAt = createdAt
    }
}

/// A complete WarMap Studio project — everything a `.warmap` file holds apart from
/// imported media.
public struct WarMapProject: Identifiable, Codable, Hashable, Sendable {

    /// Bumped whenever the on-disk shape changes incompatibly. A file claiming a
    /// higher version is refused with a clear message rather than half-read.
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    public var id: UUID
    public var name: String
    public var subtitle: String
    public var createdAt: Date
    public var modifiedAt: Date

    public var era: HistoricalEra
    public var mapRegionID: String
    public var projection: MapProjectionKind
    public var mapStyle: MapStyle
    public var renderStyle: MapRenderStyle
    public var exportPreset: ExportPreset
    public var dateFormat: HistoricalDate.Format

    /// The original, historical timeline. Branches never modify it.
    public var timeline: Timeline
    public var countries: [Country]
    public var wars: [War]
    public var audioClips: [AudioClip]
    public var branches: [ScenarioBranch]
    /// Which branch is being edited. `nil` means the original timeline.
    public var activeBranchID: UUID?

    public init(id: UUID = UUID(),
                name: String,
                subtitle: String = "",
                era: HistoricalEra = .worldWarTwo,
                mapRegionID: String = "europe",
                projection: MapProjectionKind = .mercator,
                mapStyle: MapStyle = .military,
                renderStyle: MapRenderStyle? = nil,
                exportPreset: ExportPreset = .tiktok,
                dateFormat: HistoricalDate.Format = .dayMonthNameYear,
                timeline: Timeline,
                countries: [Country] = [],
                wars: [War] = [],
                audioClips: [AudioClip] = [],
                branches: [ScenarioBranch] = [],
                activeBranchID: UUID? = nil,
                createdAt: Date = Date(),
                modifiedAt: Date = Date()) {
        self.formatVersion = Self.currentFormatVersion
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.era = era
        self.mapRegionID = mapRegionID
        self.projection = projection
        self.mapStyle = mapStyle
        self.renderStyle = renderStyle ?? .preset(mapStyle)
        self.exportPreset = exportPreset
        self.dateFormat = dateFormat
        self.timeline = timeline
        self.countries = countries
        self.wars = wars
        self.audioClips = audioClips
        self.branches = branches
        self.activeBranchID = activeBranchID
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    /// Decodes tolerantly: a field added in a later minor revision falls back to a
    /// default rather than failing the whole load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try c.decodeIfPresent(Int.self, forKey: .formatVersion) ?? 1
        guard formatVersion <= Self.currentFormatVersion else {
            throw WarMapError.projectVersionUnsupported(found: formatVersion,
                                                        supported: Self.currentFormatVersion)
        }
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle) ?? ""
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? Date()
        era = try c.decodeIfPresent(HistoricalEra.self, forKey: .era) ?? .worldWarTwo
        mapRegionID = try c.decodeIfPresent(String.self, forKey: .mapRegionID) ?? "europe"
        projection = try c.decodeIfPresent(MapProjectionKind.self, forKey: .projection) ?? .mercator
        mapStyle = try c.decodeIfPresent(MapStyle.self, forKey: .mapStyle) ?? .military
        renderStyle = try c.decodeIfPresent(MapRenderStyle.self, forKey: .renderStyle)
            ?? .preset(mapStyle)
        exportPreset = try c.decodeIfPresent(ExportPreset.self, forKey: .exportPreset) ?? .tiktok
        dateFormat = try c.decodeIfPresent(HistoricalDate.Format.self, forKey: .dateFormat)
            ?? .dayMonthNameYear
        timeline = try c.decode(Timeline.self, forKey: .timeline)
        countries = try c.decodeIfPresent([Country].self, forKey: .countries) ?? []
        wars = try c.decodeIfPresent([War].self, forKey: .wars) ?? []
        audioClips = try c.decodeIfPresent([AudioClip].self, forKey: .audioClips) ?? []
        branches = try c.decodeIfPresent([ScenarioBranch].self, forKey: .branches) ?? []
        activeBranchID = try c.decodeIfPresent(UUID.self, forKey: .activeBranchID)
    }

    // MARK: - Derived

    /// Countries keyed by id, which is what the renderer wants.
    public var countryIndex: [String: Country] {
        Dictionary(countries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// The timeline currently being edited: the active branch's, or the original.
    public var activeTimeline: Timeline {
        get {
            guard let activeBranchID,
                  let branch = branches.first(where: { $0.id == activeBranchID }) else {
                return timeline
            }
            return branch.timeline
        }
        set {
            guard let activeBranchID,
                  let index = branches.firstIndex(where: { $0.id == activeBranchID }) else {
                timeline = newValue
                return
            }
            branches[index].timeline = newValue
        }
    }

    public var activeBranchName: String {
        guard let activeBranchID,
              let branch = branches.first(where: { $0.id == activeBranchID }) else {
            return "Original Timeline"
        }
        return branch.name
    }

    /// A label like "1939–1945" for the dashboard card.
    public var periodLabel: String {
        let start = timeline.historicalRange.start
        let end = timeline.historicalRange.end
        return start.displayYear == end.displayYear
            ? start.tickLabel
            : "\(start.tickLabel)–\(end.tickLabel)"
    }

    /// Forks the current timeline at a date into a new branch, leaving the original
    /// untouched. Clips that start after the divergence are dropped from the copy —
    /// that is the point of the fork.
    public mutating func branch(named name: String,
                                at date: HistoricalDate,
                                note: String = "") -> ScenarioBranch {
        var copy = activeTimeline
        let divergence = copy.time(for: date)
        copy.items = copy.items.filter { $0.start < divergence }

        let branch = ScenarioBranch(name: name,
                                    parentID: activeBranchID,
                                    divergenceDate: date,
                                    note: note,
                                    timeline: copy)
        branches.append(branch)
        return branch
    }

    /// Branches that fork directly from a given parent, for drawing the tree.
    public func children(of parentID: UUID?) -> [ScenarioBranch] {
        branches.filter { $0.parentID == parentID }
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion, id, name, subtitle, createdAt, modifiedAt, era, mapRegionID,
             projection, mapStyle, renderStyle, exportPreset, dateFormat, timeline,
             countries, wars, audioClips, branches, activeBranchID
    }
}

/// The cheap header the dashboard lists, read without loading a whole project.
public struct ProjectSummary: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var subtitle: String
    public var periodLabel: String
    public var era: HistoricalEra
    public var modifiedAt: Date
    public var url: URL
    public var thumbnailURL: URL?

    public init(id: UUID, name: String, subtitle: String, periodLabel: String,
                era: HistoricalEra, modifiedAt: Date, url: URL, thumbnailURL: URL?) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.periodLabel = periodLabel
        self.era = era
        self.modifiedAt = modifiedAt
        self.url = url
        self.thumbnailURL = thumbnailURL
    }
}
