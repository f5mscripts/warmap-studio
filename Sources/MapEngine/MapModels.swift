import Foundation

/// The atom of territorial ownership.
///
/// One unit is usually one country, but countries that need to be split on screen —
/// partitioned Poland, occupied and Vichy France, Kaliningrad — are cut into several
/// units by `Tools/prepare_map_data.py`. Because ownership is stored per unit, every
/// territorial event in the app (annexation, partition, collapse, independence) is
/// the same operation: reassign units.
public struct TerritoryUnit: Identifiable, Hashable, Sendable, Decodable {
    public let id: String
    /// Geographic name of the unit itself, not of whoever holds it.
    public let name: String
    /// ISO code of the present-day country the unit was derived from.
    public let iso: String
    /// A point guaranteed to lie inside the unit — the label and marker anchor.
    public let anchor: GeoCoordinate
    public let bounds: GeoBounds
    /// Area in square degrees. Only ever compared against other units, so the
    /// distortion of unprojected degrees does not matter.
    public let area: Double
    /// Units sharing a land border. Drives frontline placement and army movement.
    public let neighbours: [String]

    private enum CodingKeys: String, CodingKey {
        case id, name, iso, anchor, bbox, area, neighbours
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        iso = try container.decode(String.self, forKey: .iso)
        anchor = try container.decode(GeoCoordinate.self, forKey: .anchor)
        area = try container.decode(Double.self, forKey: .area)
        neighbours = try container.decode([String].self, forKey: .neighbours)

        let box = try container.decode([Double].self, forKey: .bbox)
        guard box.count == 4 else {
            throw DecodingError.dataCorruptedError(
                forKey: .bbox, in: container,
                debugDescription: "expected 4 numbers, found \(box.count)"
            )
        }
        bounds = GeoBounds(array: box)
    }

    public init(id: String, name: String, iso: String, anchor: GeoCoordinate,
                bounds: GeoBounds, area: Double, neighbours: [String]) {
        self.id = id
        self.name = name
        self.iso = iso
        self.anchor = anchor
        self.bounds = bounds
        self.area = area
        self.neighbours = neighbours
    }
}

/// A stretch of boundary shared by at most two territory units.
///
/// Borders are stored separately from territory outlines so the renderer can decide
/// per frame whether a given stretch is a border at all: when both sides belong to
/// the same power it is an internal seam and must not be drawn. That is what lets a
/// partitioned country look seamless again once it is reunified.
public struct BorderSegment: Hashable, Sendable, Decodable {
    public let a: String
    /// `nil` when the far side is sea — a coastline rather than a border.
    public let b: String?
    public let points: [GeoCoordinate]

    public var isCoastline: Bool { b == nil }

    /// Cheap reject box, computed once at load rather than per frame.
    public let bounds: GeoBounds

    private enum CodingKeys: String, CodingKey { case a, b, points }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        a = try container.decode(String.self, forKey: .a)
        b = try container.decodeIfPresent(String.self, forKey: .b)
        points = try container.decode([GeoCoordinate].self, forKey: .points)

        var box = GeoBounds.empty
        for p in points { box.expand(toInclude: p) }
        bounds = box
    }
}

/// A name a place went by during a particular stretch of history.
public struct HistoricalPlaceName: Hashable, Sendable, Decodable {
    public let name: String
    /// `nil` means "for as long as the map goes back".
    public let startYear: Int?
    /// `nil` means "still current".
    public let endYear: Int?

    public func covers(year: Int) -> Bool {
        if let start = startYear, year < start { return false }
        if let end = endYear, year >= end { return false }
        return true
    }
}

/// A settlement that can be labelled, captured, or fought over.
public struct City: Identifiable, Hashable, Sendable, Decodable {
    public let id: String
    /// Present-day name. Use `name(inYear:)` for anything era-specific.
    public let name: String
    public let coordinate: GeoCoordinate
    /// The territory unit this city sits in, so capture follows ownership.
    public let unitID: String
    /// 1 is a world city, 5 is a minor place. Drives label filtering and marker size.
    public let importance: Int
    public let isCapital: Bool
    public let historicalNames: [HistoricalPlaceName]

    private enum CodingKeys: String, CodingKey {
        case id, name, lon, lat, unit, importance, capital, historicalNames
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        coordinate = GeoCoordinate(
            longitude: try container.decode(Double.self, forKey: .lon),
            latitude: try container.decode(Double.self, forKey: .lat)
        )
        unitID = try container.decodeIfPresent(String.self, forKey: .unit) ?? ""
        importance = try container.decodeIfPresent(Int.self, forKey: .importance) ?? 3
        isCapital = try container.decodeIfPresent(Bool.self, forKey: .capital) ?? false
        historicalNames = try container.decodeIfPresent([HistoricalPlaceName].self,
                                                        forKey: .historicalNames) ?? []
    }

    /// The name this place went by in a given year — Constantinople before 1930,
    /// Istanbul after; Stalingrad only between 1925 and 1961.
    public func name(inYear year: Int) -> String {
        historicalNames.first { $0.covers(year: year) }?.name ?? name
    }
}

/// A framing preset offered by the New Project wizard.
public struct MapRegion: Identifiable, Hashable, Sendable, Decodable {
    public let id: String
    public let name: String
    public let bounds: GeoBounds

    private enum CodingKeys: String, CodingKey { case id, name, box }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        let box = try container.decode([Double].self, forKey: .box)
        guard box.count == 4 else {
            throw DecodingError.dataCorruptedError(
                forKey: .box, in: container,
                debugDescription: "expected 4 numbers, found \(box.count)"
            )
        }
        bounds = GeoBounds(array: box)
    }
}

/// How much geometric detail to draw.
///
/// The renderer picks a level from the camera span, so a world view does not pay for
/// coastline vertices that land inside a single pixel.
public enum LevelOfDetail: Int, CaseIterable, Sendable {
    case full = 0
    case medium = 1
    case coarse = 2

    /// Chooses a level from how many degrees of longitude one screen point covers.
    ///
    /// The thresholds are the tolerances the data was simplified at
    /// (0.08° and 0.35°), so a level is only used where its own error is at most
    /// about one point on screen.
    public static func forUnitsPerPoint(_ unitsPerPoint: Double) -> LevelOfDetail {
        if unitsPerPoint > 0.35 { return .coarse }
        if unitsPerPoint > 0.08 { return .medium }
        return .full
    }
}
