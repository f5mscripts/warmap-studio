import CoreGraphics
import Foundation

/// The fixed colour vocabulary of the pixel-art map style.
///
/// Low resolution is unforgiving. At 200 pixels across, two countries whose colours
/// differ by a few percent become the same country, and a subtle fill sinks into the
/// sea behind it. So the pixel style does not draw the project's colours directly —
/// it quantises every one of them onto this 24-entry palette.
///
/// Six entries are reserved for the map itself (ink, two seas, shore, neutral land,
/// paper) and are never handed to a country, which is what stops a side being
/// coloured the same as the ocean it is fighting across.
public enum PixelPalette {

    // MARK: - Reserved terrain entries

    /// Outlines, borders and every dark edge in the style.
    public static let ink = "0B0F1A"
    public static let deepSea = "12294A"
    public static let sea = "1D4E89"
    public static let shallowSea = "3A7FC1"
    public static let neutralLand = "6E7686"
    /// The near-white used for labels, strength bars and sprite highlights.
    public static let paper = "E8ECF5"

    public static let terrain: [String] = [ink, deepSea, sea, shallowSea, neutralLand, paper]

    /// The eighteen colours a country's fill can be quantised to. Saturated and well
    /// separated in hue, because hue is the only channel that survives being drawn
    /// four pixels wide.
    public static let faction: [String] = [
        "C22E2E",  // red
        "8C1F1F",  // maroon
        "F2643C",  // orange
        "F0A02B",  // amber
        "F5D96B",  // sand
        "7A4A22",  // brown
        "C98C4B",  // tan
        "1FA850",  // green
        "0E6B45",  // deep green
        "8FD44A",  // lime
        "1EB9A0",  // teal
        "2E6FE0",  // blue
        "6FC8F0",  // sky
        "4B3AA8",  // indigo
        "8B45C8",  // purple
        "E05FC0",  // magenta
        "9AA3B5",  // steel
        "3C4356",  // slate
    ]

    /// Capital dots and other gold furniture reuse the amber faction entry.
    public static let amber = "F0A02B"
    /// Explosions, attack arrows and battle markers.
    public static let danger = "C22E2E"

    public static var all: [String] { terrain + faction }

    // MARK: - Quantisation

    /// The palette entry closest to `hex`, by perceptual distance.
    public static func nearest(to hex: String, in candidates: [String] = all) -> String {
        guard let target = components(hex), let first = candidates.first else { return hex }
        var best = first
        var bestDistance = Double.greatestFiniteMagnitude
        for candidate in candidates {
            guard let rgb = components(candidate) else { continue }
            let d = distance(target, rgb)
            if d < bestDistance {
                bestDistance = d
                best = candidate
            }
        }
        return best
    }

    /// Quantises a whole cast of countries at once, spreading them across the palette
    /// so that two similar reds do not collapse into the same side.
    ///
    /// Each country takes its nearest *unused* entry; only once all eighteen are gone
    /// do countries start sharing. That is deliberately more aggressive than
    /// quantising each colour on its own — a near-neighbour pushed one entry along is
    /// still recognisably itself, whereas two powers painted the same red at 200
    /// pixels across are simply one power.
    ///
    /// Countries are processed in id order, never dictionary order, so a project
    /// always produces the same colours: frame after frame, and preview to export.
    public static func factionColors(for colorsByCountryID: [String: String]) -> [String: String] {
        var taken: Set<String> = []
        var result: [String: String] = [:]

        for id in colorsByCountryID.keys.sorted() {
            // An unparseable colour is left out entirely: `nearest` would hand back
            // the malformed string, which is not a palette entry.
            guard let hex = colorsByCountryID[id], components(hex) != nil else { continue }

            let free = faction.filter { !taken.contains($0) }
            let chosen = nearest(to: hex, in: free.isEmpty ? faction : free)
            taken.insert(chosen)
            result[id] = chosen
        }
        return result
    }

    // MARK: - Colour maths

    /// Parses `"RRGGBB"` or `"#RRGGBB"` into 0–255 components.
    static func components(_ hex: String) -> (r: Double, g: Double, b: Double)? {
        var text = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        if text.count == 3 { text = text.map { "\($0)\($0)" }.joined() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        return (Double((value >> 16) & 0xFF), Double((value >> 8) & 0xFF), Double(value & 0xFF))
    }

    /// Squared "redmean" distance — a cheap approximation of perceptual difference
    /// that, unlike plain RGB distance, does not think navy and forest green are
    /// neighbours.
    static func distance(_ first: (r: Double, g: Double, b: Double),
                         _ second: (r: Double, g: Double, b: Double)) -> Double {
        let rMean = (first.r + second.r) / 2
        let dr = first.r - second.r
        let dg = first.g - second.g
        let db = first.b - second.b
        return (2 + rMean / 256) * dr * dr + 4 * dg * dg + (2 + (255 - rMean) / 256) * db * db
    }

    /// The palette entry closest to `hex`, as a drawable colour.
    public static func cgColor(_ hex: String) -> CGColor {
        FlagRenderer.cgColor(nearest(to: hex))
    }
}
