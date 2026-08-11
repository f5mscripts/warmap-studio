import CoreGraphics
import Foundation

/// A flag described as geometry rather than shipped as an image.
///
/// Historical flags are a licensing minefield and an asset-management chore, and a
/// country needs a *different* flag depending on the year — so WarMap Studio draws
/// them instead. A `FlagSpec` is a background field plus a stack of overlays, which
/// covers the overwhelming majority of national flags: tricolours, bicolours, Nordic
/// crosses, saltires, cantons, crescents, sun discs and simple charges.
///
/// Flags this vocabulary genuinely cannot express (intricate coats of arms, for
/// instance) fall back to their plain field colours, and any flag can be overridden
/// with an imported image per country per date range. See `HistoricalFlag`.
public struct FlagSpec: Hashable, Codable, Sendable {
    public var field: FlagField
    public var overlays: [FlagOverlay]
    /// Width divided by height. Most national flags are 3:2 or 5:3.
    public var aspectRatio: Double

    public init(field: FlagField, overlays: [FlagOverlay] = [], aspectRatio: Double = 1.5) {
        self.field = field
        self.overlays = overlays
        self.aspectRatio = aspectRatio
    }

    /// The colour that best represents the flag when it is too small to draw —
    /// used for territory fills and timeline chips.
    public var representativeColorHex: String {
        switch field {
        case .solid(let hex): return hex
        case .horizontal(let colors), .vertical(let colors), .diagonal(let colors):
            // The middle band reads as "the" colour of most tricolours.
            return colors.isEmpty ? "808080" : colors[colors.count / 2]
        }
    }
}

/// The background of a flag.
public enum FlagField: Hashable, Codable, Sendable {
    case solid(String)
    /// Bands from top to bottom.
    case horizontal([String])
    /// Bands from hoist (left) to fly (right).
    case vertical([String])
    /// Bands running corner to corner, hoist-top to fly-bottom.
    case diagonal([String])
}

/// Something drawn on top of the field.
public enum FlagOverlay: Hashable, Codable, Sendable {
    /// A centred cross. `offsetFromHoist` shifts it towards the hoist, as on
    /// Nordic flags — 0.5 is centred, 0.36 is the usual Nordic position.
    case cross(color: String, thickness: Double, offsetFromHoist: Double)
    /// An X across the whole flag.
    case saltire(color: String, thickness: Double)
    /// A rectangle in the upper hoist corner, sized as a fraction of the flag.
    case canton(color: String, widthFraction: Double, heightFraction: Double)
    /// A filled circle. `center` is in flag-relative coordinates (0…1).
    case disc(color: String, radius: Double, center: CGPoint)
    /// A crescent, drawn as a disc with a second disc subtracted.
    case crescent(color: String, radius: Double, center: CGPoint)
    /// A regular star.
    case star(color: String, points: Int, radius: Double, center: CGPoint)
    /// A horizontal stripe at a given vertical position.
    case stripe(color: String, thickness: Double, position: Double)
    /// A triangle based on the hoist, pointing towards the fly.
    case hoistTriangle(color: String, widthFraction: Double)
    /// A thin outline around the whole flag — used where a white field would
    /// otherwise vanish against the parchment.
    case border(color: String, thickness: Double)
}

/// A flag together with the period it was flown.
///
/// This is the shape that makes the era system work: a country holds several of
/// these, and asking for "the flag on 1 September 1939" picks the right one instead
/// of anachronistically showing a modern flag on a 1939 map.
public struct HistoricalFlag: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID
    /// `nil` start or end means open-ended in that direction.
    public var startDate: HistoricalDate?
    public var endDate: HistoricalDate?
    public var spec: FlagSpec
    /// Relative path of a user-imported image inside the project package. When set,
    /// it wins over `spec`.
    public var importedAssetPath: String?
    /// Shown in the inspector, e.g. "Weimar Republic (1919–1933)".
    public var label: String

    public init(id: UUID = UUID(),
                label: String,
                startDate: HistoricalDate? = nil,
                endDate: HistoricalDate? = nil,
                spec: FlagSpec,
                importedAssetPath: String? = nil) {
        self.id = id
        self.label = label
        self.startDate = startDate
        self.endDate = endDate
        self.spec = spec
        self.importedAssetPath = importedAssetPath
    }

    public func covers(_ date: HistoricalDate) -> Bool {
        if let start = startDate, date < start { return false }
        if let end = endDate, date >= end { return false }
        return true
    }
}

// MARK: - Common flag vocabulary

extension FlagSpec {

    public static func tricolourVertical(_ a: String, _ b: String, _ c: String) -> FlagSpec {
        FlagSpec(field: .vertical([a, b, c]))
    }

    public static func tricolourHorizontal(_ a: String, _ b: String, _ c: String) -> FlagSpec {
        FlagSpec(field: .horizontal([a, b, c]))
    }

    public static func bicolourHorizontal(_ a: String, _ b: String) -> FlagSpec {
        FlagSpec(field: .horizontal([a, b]))
    }

    public static func nordicCross(field: String, cross: String) -> FlagSpec {
        FlagSpec(field: .solid(field),
                 overlays: [.cross(color: cross, thickness: 0.18, offsetFromHoist: 0.36)],
                 aspectRatio: 1.6)
    }

    public static func solid(_ hex: String) -> FlagSpec {
        FlagSpec(field: .solid(hex))
    }
}
