import CoreGraphics
import Foundation

/// How a text element enters and leaves.
public enum TextAnimationPreset: String, Codable, CaseIterable, Sendable, Identifiable {
    case fade
    case slideUp
    case slideLeft
    case typewriter
    case scale
    case pop
    /// Letter-spacing opens out under a drawn rule — the documentary title look.
    case historicalTitle
    /// Digits roll like an odometer. Meant for the date counter.
    case dateCounter
    /// Wipes in behind a moving highlight, for revealing a country name.
    case countryReveal

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .fade: return "Fade"
        case .slideUp: return "Slide Up"
        case .slideLeft: return "Slide In"
        case .typewriter: return "Typewriter"
        case .scale: return "Scale"
        case .pop: return "Pop"
        case .historicalTitle: return "Historical Title"
        case .dateCounter: return "Date Counter"
        case .countryReveal: return "Country Reveal"
        }
    }

    /// The curve that suits each preset by default.
    public var defaultEasing: EasingCurve {
        switch self {
        case .fade, .typewriter, .dateCounter: return .linear
        case .slideUp, .slideLeft, .countryReveal: return .easeOut
        case .scale, .historicalTitle: return .easeInOut
        case .pop: return .backOut
        }
    }
}

/// Visual treatment of a text element.
public struct TextStyle: Codable, Hashable, Sendable {
    public var fontSize: Double
    public var weight: Int
    /// Serif reads as historical; the UI face reads as modern.
    public var usesSerif: Bool
    public var colorHex: String
    public var opacity: Double
    public var letterSpacing: Double
    public var outlineColorHex: String?
    public var outlineWidth: Double
    public var shadowRadius: Double
    public var shadowOpacity: Double
    public var alignment: TextAlignmentOption
    public var isUppercase: Bool

    public init(fontSize: Double = 48,
                weight: Int = 700,
                usesSerif: Bool = true,
                colorHex: String = "F2EDE1",
                opacity: Double = 1,
                letterSpacing: Double = 0,
                outlineColorHex: String? = nil,
                outlineWidth: Double = 0,
                shadowRadius: Double = 8,
                shadowOpacity: Double = 0.6,
                alignment: TextAlignmentOption = .center,
                isUppercase: Bool = false) {
        self.fontSize = fontSize
        self.weight = weight
        self.usesSerif = usesSerif
        self.colorHex = colorHex
        self.opacity = opacity
        self.letterSpacing = letterSpacing
        self.outlineColorHex = outlineColorHex
        self.outlineWidth = outlineWidth
        self.shadowRadius = shadowRadius
        self.shadowOpacity = shadowOpacity
        self.alignment = alignment
        self.isUppercase = isUppercase
    }

    public static let title = TextStyle(fontSize: 64, weight: 800, usesSerif: true,
                                        letterSpacing: 3, shadowRadius: 12,
                                        isUppercase: true)
    public static let subtitle = TextStyle(fontSize: 34, weight: 600, usesSerif: true,
                                           colorHex: "C9A227")
    public static let caption = TextStyle(fontSize: 24, weight: 500, usesSerif: false,
                                          colorHex: "A8A296")
    public static let dateCounter = TextStyle(fontSize: 44, weight: 700, usesSerif: false,
                                              colorHex: "F2EDE1", letterSpacing: 1)
}

public enum TextAlignmentOption: String, Codable, CaseIterable, Sendable {
    case leading, center, trailing
}

/// A piece of text placed over the map.
///
/// `position` is in normalised viewport coordinates (0…1) rather than points, so a
/// project composed for TikTok's 9:16 still lays out correctly when exported at
/// 16:9 or previewed on an iPad.
public struct TextElement: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var content: String
    public var style: TextStyle
    public var animation: TextAnimationPreset
    public var position: CGPoint
    /// Fraction of viewport width the text may occupy before wrapping.
    public var maxWidthFraction: Double
    /// When set, the content is replaced by the timeline's current date in this
    /// format — this is what makes the animated date counter work.
    public var dateFormat: HistoricalDate.Format?

    public init(id: UUID = UUID(),
                content: String,
                style: TextStyle = .title,
                animation: TextAnimationPreset = .fade,
                position: CGPoint = CGPoint(x: 0.5, y: 0.18),
                maxWidthFraction: Double = 0.86,
                dateFormat: HistoricalDate.Format? = nil) {
        self.id = id
        self.content = content
        self.style = style
        self.animation = animation
        self.position = position
        self.maxWidthFraction = maxWidthFraction
        self.dateFormat = dateFormat
    }

    /// A date counter that rewrites itself from the timeline clock.
    public static func dateCounter(format: HistoricalDate.Format = .dayMonthNameYear,
                                   position: CGPoint = CGPoint(x: 0.5, y: 0.08)) -> TextElement {
        TextElement(content: "",
                    style: .dateCounter,
                    animation: .dateCounter,
                    position: position,
                    dateFormat: format)
    }
}

/// A text element resolved for one instant: content substituted, entry animation
/// applied, ready to draw.
///
/// The renderer never sees `TextElement` directly — it draws these, which is what
/// keeps the preview and the export identical.
public struct ResolvedText: Identifiable, Hashable, Sendable {
    public var id: UUID
    /// Already substituted and case-folded; for the typewriter this is truncated.
    public var content: String
    public var style: TextStyle
    public var position: CGPoint
    public var maxWidthFraction: Double
    /// Multiplied into `style.opacity`.
    public var opacity: Double
    public var scale: Double
    /// Offset in normalised viewport units, for the sliding presets.
    public var offset: CGPoint
    /// Extra tracking added by `historicalTitle`, on top of the style's own.
    public var extraLetterSpacing: Double
    /// 0…1 — how much of the reveal highlight has passed. Only `countryReveal`
    /// uses it.
    public var revealProgress: Double

    public init(id: UUID, content: String, style: TextStyle, position: CGPoint,
                maxWidthFraction: Double, opacity: Double, scale: Double,
                offset: CGPoint, extraLetterSpacing: Double, revealProgress: Double) {
        self.id = id
        self.content = content
        self.style = style
        self.position = position
        self.maxWidthFraction = maxWidthFraction
        self.opacity = opacity
        self.scale = scale
        self.offset = offset
        self.extraLetterSpacing = extraLetterSpacing
        self.revealProgress = revealProgress
    }
}

public enum TextAnimator {

    /// Resolves an element at a point in its life.
    ///
    /// `progress` runs 0…1 across the element's own timeline item. The entry
    /// animation occupies the first `entryFraction`, the exit the last, and the
    /// middle is held steady — so lengthening a title on the timeline makes it stay
    /// longer rather than animate slower.
    public static func resolve(_ element: TextElement,
                               progress: Double,
                               date: HistoricalDate,
                               easing: EasingCurve,
                               entryFraction: Double = 0.25,
                               exitFraction: Double = 0.15) -> ResolvedText {
        let p = min(max(progress, 0), 1)

        let entry = entryFraction > 0 ? min(p / entryFraction, 1) : 1
        let exitStart = 1 - exitFraction
        let exit = exitFraction > 0 && p > exitStart
            ? min((p - exitStart) / exitFraction, 1)
            : 0

        let easedEntry = easing.apply(entry)
        let fadeOut = 1 - exit

        var content = element.dateFormat.map { date.formatted($0) } ?? element.content
        if element.style.isUppercase { content = content.uppercased() }

        var opacity = easedEntry * fadeOut
        var scale = 1.0
        var offset = CGPoint.zero
        var extraSpacing = 0.0
        var reveal = 1.0

        switch element.animation {
        case .fade:
            break
        case .slideUp:
            offset = CGPoint(x: 0, y: (1 - easedEntry) * 0.06)
        case .slideLeft:
            offset = CGPoint(x: (1 - easedEntry) * -0.12, y: 0)
        case .typewriter:
            // Reveal by character rather than by opacity.
            opacity = fadeOut
            let visible = Int((Double(content.count) * entry).rounded())
            content = String(content.prefix(max(0, visible)))
        case .scale:
            scale = 0.8 + 0.2 * easedEntry
        case .pop:
            scale = easing.apply(entry)
        case .historicalTitle:
            extraSpacing = (1 - easedEntry) * 14
            scale = 0.98 + 0.02 * easedEntry
        case .dateCounter:
            // The counter should not blink on every date change; it holds steady
            // once it has appeared and only fades at the very end.
            opacity = min(entry * 3, 1) * fadeOut
        case .countryReveal:
            reveal = easedEntry
            opacity = fadeOut
        }

        return ResolvedText(id: element.id,
                            content: content,
                            style: element.style,
                            position: element.position,
                            maxWidthFraction: element.maxWidthFraction,
                            opacity: max(0, min(opacity, 1)),
                            scale: scale,
                            offset: offset,
                            extraLetterSpacing: extraSpacing,
                            revealProgress: reveal)
    }
}
