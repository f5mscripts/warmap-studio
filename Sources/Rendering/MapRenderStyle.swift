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

    public var showsCities: Bool
    /// Cities with `importance` above this are hidden. 1 shows only world cities.
    public var maximumCityImportance: Int
    public var showsCapitalsOnly: Bool
    public var showsCountryLabels: Bool
    public var showsFlags: Bool
    public var showsGraticule: Bool
    public var graticuleHex: String

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
                contestedHighlight: Double = 0.16,
                showsCities: Bool = true,
                maximumCityImportance: Int = 2,
                showsCapitalsOnly: Bool = false,
                showsCountryLabels: Bool = true,
                showsFlags: Bool = false,
                showsGraticule: Bool = false,
                graticuleHex: String = "1E2A36") {
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
        self.showsCities = showsCities
        self.maximumCityImportance = maximumCityImportance
        self.showsCapitalsOnly = showsCapitalsOnly
        self.showsCountryLabels = showsCountryLabels
        self.showsFlags = showsFlags
        self.showsGraticule = showsGraticule
        self.graticuleHex = graticuleHex
    }

    /// The look that goes with each era's map style.
    public static func preset(_ style: MapStyle) -> MapRenderStyle {
        switch style {
        case .military:
            return MapRenderStyle()

        case .atlas:
            return MapRenderStyle(oceanHex: "1B2B3A",
                                  oceanDeepHex: "16232F",
                                  neutralLandHex: "7C838C",
                                  coastlineHex: "51606E",
                                  borderHex: "10151A",
                                  borderWidth: 1.6,
                                  showsGraticule: true,
                                  graticuleHex: "24384A")

        case .parchment:
            return MapRenderStyle(oceanHex: "C3B48C",
                                  oceanDeepHex: "B4A47C",
                                  neutralLandHex: "D9CBA6",
                                  coastlineHex: "6E5C3A",
                                  borderHex: "4A3B22",
                                  coastlineWidth: 1.2,
                                  borderWidth: 2.2,
                                  cityDotHex: "3A2E1A",
                                  cityLabelHex: "3A2E1A",
                                  capitalDotHex: "7A5A1E",
                                  labelHex: "3A2E1A",
                                  labelOutlineHex: "E8DCC0",
                                  territoryOpacity: 0.82,
                                  showsGraticule: true,
                                  graticuleHex: "AD9C74")

        case .antique:
            return MapRenderStyle(oceanHex: "9FA98E",
                                  oceanDeepHex: "8E9A7E",
                                  neutralLandHex: "CDC3A5",
                                  coastlineHex: "5A5340",
                                  borderHex: "3E3728",
                                  cityDotHex: "34301F",
                                  territoryOpacity: 0.86,
                                  showsGraticule: true,
                                  graticuleHex: "8A9378")
        }
    }
}
