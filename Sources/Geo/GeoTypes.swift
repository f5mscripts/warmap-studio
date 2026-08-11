import CoreGraphics
import Foundation

/// A longitude/latitude pair in degrees (WGS84).
public struct GeoCoordinate: Hashable, Codable, Sendable {
    public var longitude: Double
    public var latitude: Double

    public init(longitude: Double, latitude: Double) {
        self.longitude = longitude
        self.latitude = latitude
    }

    /// Decodes the GeoJSON `[lon, lat]` array form used by the bundled map data.
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        longitude = try container.decode(Double.self)
        latitude = try container.decode(Double.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(longitude)
        try container.encode(latitude)
    }
}

/// An axis-aligned longitude/latitude rectangle.
public struct GeoBounds: Hashable, Codable, Sendable {
    public var minLongitude: Double
    public var minLatitude: Double
    public var maxLongitude: Double
    public var maxLatitude: Double

    public init(minLongitude: Double, minLatitude: Double, maxLongitude: Double, maxLatitude: Double) {
        self.minLongitude = minLongitude
        self.minLatitude = minLatitude
        self.maxLongitude = maxLongitude
        self.maxLatitude = maxLatitude
    }

    /// The `[minLon, minLat, maxLon, maxLat]` array form used by `territories.json`.
    public init(array: [Double]) {
        self.init(minLongitude: array[0], minLatitude: array[1],
                  maxLongitude: array[2], maxLatitude: array[3])
    }

    public var center: GeoCoordinate {
        GeoCoordinate(longitude: (minLongitude + maxLongitude) / 2,
                      latitude: (minLatitude + maxLatitude) / 2)
    }

    public var longitudeSpan: Double { maxLongitude - minLongitude }
    public var latitudeSpan: Double { maxLatitude - minLatitude }

    public func intersects(_ other: GeoBounds) -> Bool {
        !(other.maxLongitude < minLongitude || other.minLongitude > maxLongitude
          || other.maxLatitude < minLatitude || other.minLatitude > maxLatitude)
    }

    public func contains(_ c: GeoCoordinate) -> Bool {
        c.longitude >= minLongitude && c.longitude <= maxLongitude
            && c.latitude >= minLatitude && c.latitude <= maxLatitude
    }

    /// Grows the box to include a coordinate, or starts one if empty.
    public mutating func expand(toInclude c: GeoCoordinate) {
        minLongitude = Swift.min(minLongitude, c.longitude)
        maxLongitude = Swift.max(maxLongitude, c.longitude)
        minLatitude = Swift.min(minLatitude, c.latitude)
        maxLatitude = Swift.max(maxLatitude, c.latitude)
    }

    public mutating func expand(toInclude other: GeoBounds) {
        minLongitude = Swift.min(minLongitude, other.minLongitude)
        maxLongitude = Swift.max(maxLongitude, other.maxLongitude)
        minLatitude = Swift.min(minLatitude, other.minLatitude)
        maxLatitude = Swift.max(maxLatitude, other.maxLatitude)
    }

    /// Expands by a fraction of the current size on every side.
    public func padded(by fraction: Double) -> GeoBounds {
        let dx = longitudeSpan * fraction
        let dy = latitudeSpan * fraction
        return GeoBounds(minLongitude: minLongitude - dx, minLatitude: minLatitude - dy,
                         maxLongitude: maxLongitude + dx, maxLatitude: maxLatitude + dy)
    }

    /// A box that swallows anything unioned into it.
    public static let empty = GeoBounds(minLongitude: .infinity, minLatitude: .infinity,
                                        maxLongitude: -.infinity, maxLatitude: -.infinity)

    public static let world = GeoBounds(minLongitude: -180, minLatitude: -85,
                                        maxLongitude: 180, maxLatitude: 85)

    public var isEmpty: Bool { minLongitude > maxLongitude || minLatitude > maxLatitude }
}

/// A closed ring of coordinates. The first and last points are expected to coincide,
/// as they do in GeoJSON.
public typealias GeoRing = [GeoCoordinate]

/// A polygon: one exterior ring plus zero or more holes.
public struct GeoPolygon: Hashable, Sendable {
    public var exterior: GeoRing
    public var holes: [GeoRing]

    public init(exterior: GeoRing, holes: [GeoRing] = []) {
        self.exterior = exterior
        self.holes = holes
    }

    public var bounds: GeoBounds {
        var b = GeoBounds.empty
        for c in exterior { b.expand(toInclude: c) }
        return b
    }
}

/// A territory's shape. Multi-part because countries have islands and exclaves.
public struct GeoMultiPolygon: Hashable, Sendable {
    public var polygons: [GeoPolygon]

    public init(polygons: [GeoPolygon]) {
        self.polygons = polygons
    }

    public var bounds: GeoBounds {
        var b = GeoBounds.empty
        for p in polygons { b.expand(toInclude: p.bounds) }
        return b
    }

    public var isEmpty: Bool { polygons.isEmpty }

    /// Decodes the `[polygon][ring][point]` nesting emitted by
    /// `Tools/prepare_map_data.py`.
    public init(nestedRings: [[[[Double]]]]) {
        polygons = nestedRings.compactMap { rings in
            guard let first = rings.first else { return nil }
            func ring(_ raw: [[Double]]) -> GeoRing {
                raw.compactMap { pair in
                    pair.count >= 2
                        ? GeoCoordinate(longitude: pair[0], latitude: pair[1])
                        : nil
                }
            }
            let exterior = ring(first)
            guard exterior.count >= 3 else { return nil }
            return GeoPolygon(exterior: exterior, holes: rings.dropFirst().map(ring))
        }
    }
}
