import CoreGraphics
import Foundation

/// Everything about how a map looks, separated from what it shows.
///
/// The renderer takes a `WorldSnapshot` (what) and a `MapRenderStyle` (how). Keeping
/// them apart is what lets the same project export as a dark military map or an aged
/// parchment one without touching the timeline.
public struct MapRenderStyle: Hashable, Codable, Sendable {

    public var oceanHex: String
    public var oceanDeepHex: String
    /// Territory with no owner in the snapshot.
    public var neutralLandHex: String
    public var coastlineHex: String
    public var borderHex: String
    public var coastlineWidth: Double
    public var borderWidth: Double

    public var cityDotHex: String
    public var cityLabelHex: String
    public var capitalDotHex: String

    public var labelHex: String
    public var labelOutlineHex: String

    /// Territory fills are drawn at this opacity over the ocean, so coastlines and
    /// graticules stay faintly visible underneath on the parchment styles.
    public var territoryOpacity: Double
    /// Extra brightness applied to the attacking colour during a capture, so an
    /// advance reads clearly even between two similar faction colours.
    public var contestedHighlight: Double
    /// How wide that leading edge is drawn, in points. A two-point line disappears
    /// on a phone; this is the glow that sells the advance.
    public var contestedEdgeWidth: Double
    /// How far country fills are pushed towards their saturated form, 0…1.
    ///
    /// The historical palette is full of khaki and slate, which reads as mud at
    /// phone size. This leaves the country's own colour untouched and only changes
    /// what gets painted.
    public var fillSaturationBoost: Double

    public var showsCities: Bool
    /// Cities with `importance` above this are hidden. 1 shows only world cities.
    public var maximumCityImportance: Int
    public var showsCapitalsOnly: Bool
    public var showsCountryLabels: Bool
    public var showsFlags: Bool
    public var showsGraticule: Bool
    public var graticuleHex: String

    /// Draw the frame into a small offscreen buffer and blow it up without
    /// interpolation, on a restricted palette — the pixel-art style.
    ///
    /// This is a different render path rather than a set of colours, which is why it
    /// lives here as a flag: everything downstream of it (label sizes, sprite
    /// markers, grid snapping) keys off this one value.
    public var isPixelated: Bool
    /// Short edge of that buffer, in pixels. Around 200 is the sweet spot: coarse
    /// enough that the pixels are the point, fine enough that Denmark survives.
    public var pixelShortEdge: Int

    public init(oceanHex: String = "121C26",
                oceanDeepHex: String = "0C141C",
                neutralLandHex: String = "686C74",
                coastlineHex: String = "3C4652",
                borderHex: String = "0E1014",
                coastlineWidth: Double = 1,
                borderWidth: Double = 2,
                cityDotHex: String = "F2EDE1",
                cityLabelHex: String = "F2EDE1",
                capitalDotHex: String = "C9A227",
                labelHex: String = "F2EDE1",
                labelOutlineHex: String = "0B0D10",
                territoryOpacity: Double = 1.0,
                contestedHighlight: Double = 0.45,
                contestedEdgeWidth: Double = 5,
                fillSaturationBoost: Double = 0.35,
                showsCities: Bool = true,
                maximumCityImportance: Int = 2,
                showsCapitalsOnly: Bool = false,
                showsCountryLabels: Bool = true,
                showsFlags: Bool = false,
                showsGraticule: Bool = false,
                graticuleHex: String = "1E2A36",
                isPixelated: Bool = false,
                pixelShortEdge: Int = 200) {
        self.oceanHex = oceanHex
        self.oceanDeepHex = oceanDeepHex
        self.neutralLandHex = neutralLandHex
        self.coastlineHex = coastlineHex
        self.borderHex = borderHex
        self.coastlineWidth = coastlineWidth
        self.borderWidth = borderWidth
        self.cityDotHex = cityDotHex
        self.cityLabelHex = cityLabelHex
        self.capitalDotHex = capitalDotHex
        self.labelHex = labelHex
        self.labelOutlineHex = labelOutlineHex
        self.territoryOpacity = territoryOpacity
        self.contestedHighlight = contestedHighlight
        self.contestedEdgeWidth = contestedEdgeWidth
        self.fillSaturationBoost = min(max(fillSaturationBoost, 0), 1)
        self.showsCities = showsCities
        self.maximumCityImportance = maximumCityImportance
        self.showsCapitalsOnly = showsCapitalsOnly
        self.showsCountryLabels = showsCountryLabels
        self.showsFlags = showsFlags
        self.showsGraticule = showsGraticule
        self.graticuleHex = graticuleHex
        self.isPixelated = isPixelated
        self.pixelShortEdge = pixelShortEdge
    }

    /// Decodes field by field so a style saved before a field existed still loads.
    ///
    /// Synthesised decoding would refuse the whole style — and with it the whole
    /// project — the moment a new key was added, which is exactly what happened when
    /// the pixel fields arrived.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = MapRenderStyle()
        func string(_ key: CodingKeys, _ fallbackHex: String) throws -> String {
            try c.decodeIfPresent(String.self, forKey: key) ?? fallbackHex
        }
        oceanHex = try string(.oceanHex, fallback.oceanHex)
        oceanDeepHex = try string(.oceanDeepHex, fallback.oceanDeepHex)
        neutralLandHex = try string(.neutralLandHex, fallback.neutralLandHex)
        coastlineHex = try string(.coastlineHex, fallback.coastlineHex)
        borderHex = try string(.borderHex, fallback.borderHex)
        coastlineWidth = try c.decodeIfPresent(Double.self, forKey: .coastlineWidth)
            ?? fallback.coastlineWidth
        borderWidth = try c.decodeIfPresent(Double.self, forKey: .borderWidth) ?? fallback.borderWidth
        cityDotHex = try string(.cityDotHex, fallback.cityDotHex)
        cityLabelHex = try string(.cityLabelHex, fallback.cityLabelHex)
        capitalDotHex = try string(.capitalDotHex, fallback.capitalDotHex)
        labelHex = try string(.labelHex, fallback.labelHex)
        labelOutlineHex = try string(.labelOutlineHex, fallback.labelOutlineHex)
        territoryOpacity = try c.decodeIfPresent(Double.self, forKey: .territoryOpacity)
            ?? fallback.territoryOpacity
        contestedHighlight = try c.decodeIfPresent(Double.self, forKey: .contestedHighlight)
            ?? fallback.contestedHighlight
        contestedEdgeWidth = try c.decodeIfPresent(Double.self, forKey: .contestedEdgeWidth)
            ?? fallback.contestedEdgeWidth
        fillSaturationBoost = try c.decodeIfPresent(Double.self, forKey: .fillSaturationBoost)
            ?? fallback.fillSaturationBoost
        showsCities = try c.decodeIfPresent(Bool.self, forKey: .showsCities) ?? fallback.showsCities
        maximumCityImportance = try c.decodeIfPresent(Int.self, forKey: .maximumCityImportance)
            ?? fallback.maximumCityImportance
        showsCapitalsOnly = try c.decodeIfPresent(Bool.self, forKey: .showsCapitalsOnly)
            ?? fallback.showsCapitalsOnly
        showsCountryLabels = try c.decodeIfPresent(Bool.self, forKey: .showsCountryLabels)
            ?? fallback.showsCountryLabels
        showsFlags = try c.decodeIfPresent(Bool.self, forKey: .showsFlags) ?? fallback.showsFlags
        showsGraticule = try c.decodeIfPresent(Bool.self, forKey: .showsGraticule)
            ?? fallback.showsGraticule
        graticuleHex = try string(.graticuleHex, fallback.graticuleHex)
        isPixelated = try c.decodeIfPresent(Bool.self, forKey: .isPixelated) ?? fallback.isPixelated
        pixelShortEdge = try c.decodeIfPresent(Int.self, forKey: .pixelShortEdge)
            ?? fallback.pixelShortEdge
    }

    /// The look that goes with each era's map style.
    public static func preset(_ style: MapStyle) -> MapRenderStyle {
        switch style {
        case .military:
            return MapRenderStyle(borderWidth: 2.8, showsFlags: true)

        case .atlas:
            return MapRenderStyle(oceanHex: "1B2B3A",
                                  oceanDeepHex: "16232F",
                                  neutralLandHex: "7C838C",
                                  coastlineHex: "51606E",
                                  borderHex: "10151A",
                                  borderWidth: 2.4,
                                  showsFlags: true,
                                  showsGraticule: true,
                                  graticuleHex: "24384A")

        case .parchment:
            return MapRenderStyle(oceanHex: "C3B48C",
                                  oceanDeepHex: "B4A47C",
                                  neutralLandHex: "D9CBA6",
                                  coastlineHex: "6E5C3A",
                                  borderHex: "4A3B22",
                                  coastlineWidth: 1.2,
                                  borderWidth: 3,
                                  cityDotHex: "3A2E1A",
                                  cityLabelHex: "3A2E1A",
                                  capitalDotHex: "7A5A1E",
                                  labelHex: "3A2E1A",
                                  labelOutlineHex: "E8DCC0",
                                  territoryOpacity: 0.82,
                                  // Parchment is meant to look aged, so it keeps
                                  // more of the muted palette than the others.
                                  fillSaturationBoost: 0.2,
                                  showsFlags: true,
                                  showsGraticule: true,
                                  graticuleHex: "AD9C74")

        case .antique:
            return MapRenderStyle(oceanHex: "9FA98E",
                                  oceanDeepHex: "8E9A7E",
                                  neutralLandHex: "CDC3A5",
                                  coastlineHex: "5A5340",
                                  borderHex: "3E3728",
                                  borderWidth: 2.6,
                                  cityDotHex: "34301F",
                                  territoryOpacity: 0.86,
                                  fillSaturationBoost: 0.2,
                                  showsFlags: true,
                                  showsGraticule: true,
                                  graticuleHex: "8A9378")

        case .pixel:
            // Every colour here is a palette entry, and every width is measured in
            // low-resolution pixels rather than points: a border of 2 is two of the
            // big square pixels, not two hairlines that vanish on upscale.
            return MapRenderStyle(oceanHex: PixelPalette.sea,
                                  oceanDeepHex: PixelPalette.deepSea,
                                  neutralLandHex: PixelPalette.neutralLand,
                                  coastlineHex: PixelPalette.ink,
                                  borderHex: PixelPalette.ink,
                                  coastlineWidth: 1,
                                  borderWidth: 2,
                                  cityDotHex: PixelPalette.paper,
                                  cityLabelHex: PixelPalette.paper,
                                  capitalDotHex: PixelPalette.amber,
                                  labelHex: PixelPalette.paper,
                                  labelOutlineHex: PixelPalette.ink,
                                  // Partial opacity would blend two palette entries
                                  // into a colour that is in neither.
                                  territoryOpacity: 1.0,
                                  contestedHighlight: 0.55,
                                  contestedEdgeWidth: 2,
                                  // The palette is already as saturated as it gets.
                                  fillSaturationBoost: 0,
                                  showsCities: true,
                                  maximumCityImportance: 1,
                                  showsCountryLabels: true,
                                  showsFlags: true,
                                  showsGraticule: false,
                                  graticuleHex: PixelPalette.shallowSea,
                                  isPixelated: true,
                                  pixelShortEdge: 200)
        }
    }
}
