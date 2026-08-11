import SwiftUI

/// Visual identity for WarMap Studio: a dark charcoal atlas with aged parchment and
/// bronze/gold leaf. Every colour, radius and font in the app resolves through here so
/// the look stays coherent and a theme swap is a one-file change.
public enum Theme {

    // MARK: - Palette

    public enum Palette {
        /// Deepest layer — the "table" the atlas rests on.
        public static let abyss = Color(hex: 0x0B0D10)
        /// Primary window/background charcoal.
        public static let charcoal = Color(hex: 0x14171C)
        /// Raised surfaces: cards, panels, sheets.
        public static let slate = Color(hex: 0x1C2027)
        /// Higher elevation: popovers, selected rows.
        public static let graphite = Color(hex: 0x252A33)
        /// Hairlines and dividers.
        public static let rule = Color(hex: 0x333A45)

        /// Aged paper for map bodies and legend plates.
        public static let parchment = Color(hex: 0xE8DCC0)
        public static let parchmentDeep = Color(hex: 0xD3C29B)
        public static let parchmentShadow = Color(hex: 0xB09B70)

        /// Primary accent — gold leaf.
        public static let gold = Color(hex: 0xC9A227)
        public static let goldBright = Color(hex: 0xE8C547)
        public static let goldDim = Color(hex: 0x8A6F1C)
        /// Secondary accent — oxidised bronze.
        public static let bronze = Color(hex: 0x9C6B3F)

        /// The sea. Deliberately desaturated so territory colours stay dominant.
        public static let ocean = Color(hex: 0x121C26)
        public static let oceanDeep = Color(hex: 0x0C141C)

        // Semantic
        public static let danger = Color(hex: 0xB3423A)
        public static let warning = Color(hex: 0xC98A2B)
        public static let success = Color(hex: 0x4E8A5C)
        public static let info = Color(hex: 0x4A6E8A)

        // Text
        public static let textPrimary = Color(hex: 0xF2EDE1)
        public static let textSecondary = Color(hex: 0xA8A296)
        public static let textTertiary = Color(hex: 0x6E6A62)
        /// Text drawn on top of parchment or a gold fill.
        public static let textOnLight = Color(hex: 0x1A1712)
    }

    // MARK: - Typography

    public enum Font {
        /// Display face for titles and dates. Serif reads as "historical atlas".
        public static func display(_ size: CGFloat, weight: SwiftUI.Font.Weight = .bold) -> SwiftUI.Font {
            .system(size: size, weight: weight, design: .serif)
        }

        /// Body/UI face.
        public static func ui(_ size: CGFloat, weight: SwiftUI.Font.Weight = .regular) -> SwiftUI.Font {
            .system(size: size, weight: weight, design: .default)
        }

        /// Tabular figures for timecodes, counters and numeric readouts.
        public static func mono(_ size: CGFloat, weight: SwiftUI.Font.Weight = .medium) -> SwiftUI.Font {
            .system(size: size, weight: weight, design: .monospaced)
        }

        public static let screenTitle = display(28)
        public static let sectionTitle = display(20, weight: .semibold)
        public static let cardTitle = ui(16, weight: .semibold)
        public static let body = ui(15)
        public static let caption = ui(12)
        public static let label = ui(11, weight: .semibold)
    }

    // MARK: - Metrics

    public enum Metric {
        public static let cornerSmall: CGFloat = 6
        public static let corner: CGFloat = 12
        public static let cornerLarge: CGFloat = 18

        public static let gutter: CGFloat = 16
        public static let gutterTight: CGFloat = 8
        public static let gutterLoose: CGFloat = 24

        public static let hairline: CGFloat = 1
        public static let toolbarHeight: CGFloat = 52
        public static let timelineHeight: CGFloat = 190
        public static let toolRailWidth: CGFloat = 64
        public static let inspectorWidth: CGFloat = 300
    }

    // MARK: - Motion

    public enum Motion {
        public static let quick: Animation = .easeOut(duration: 0.16)
        public static let standard: Animation = .easeInOut(duration: 0.26)
        public static let deliberate: Animation = .easeInOut(duration: 0.42)
        public static let springy: Animation = .spring(response: 0.36, dampingFraction: 0.78)
    }

    // MARK: - Gradients

    /// Vignette used behind the dashboard and onboarding.
    public static var atlasBackground: LinearGradient {
        LinearGradient(
            colors: [Palette.abyss, Palette.charcoal, Palette.abyss],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Gold leaf sweep for primary buttons and selected states.
    public static var goldLeaf: LinearGradient {
        LinearGradient(
            colors: [Palette.goldBright, Palette.gold, Palette.goldDim],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    public static var parchmentSheet: LinearGradient {
        LinearGradient(
            colors: [Palette.parchment, Palette.parchmentDeep],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Colour helpers

extension Color {
    /// Builds a colour from a `0xRRGGBB` literal.
    public init(hex: UInt32, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: opacity
        )
    }

    /// Round-trips through a hex string, used by the project file format.
    public init?(hexString: String) {
        var s = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let value = UInt32(s, radix: 16) else { return nil }
        if s.count == 6 {
            self.init(hex: value)
        } else {
            self.init(hex: value >> 8, opacity: Double(value & 0xFF) / 255.0)
        }
    }
}
