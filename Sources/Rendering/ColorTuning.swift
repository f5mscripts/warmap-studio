import CoreGraphics
import Foundation

/// Small colour adjustments the map styles apply to country fills.
///
/// Country colours are chosen to be plausible rather than punchy — a lot of the
/// historical palette is muted khaki and slate. That reads as authentic on a large
/// screen and as mud in a phone-sized video, so the bolder styles push the fills
/// towards their saturated form before drawing. The country's own colour is never
/// changed; only what the renderer paints with is.
public enum ColorTuning {

    /// Pushes a colour away from grey, keeping its brightness roughly intact.
    ///
    /// `amount` is a fraction: 0 leaves the colour alone, 0.5 moves it half of the
    /// way from its current saturation to fully saturated. Greys stay grey, because
    /// a colour with no hue has nothing to push away from.
    public static func saturated(_ hex: String, by amount: Double) -> String {
        guard amount > 0, let rgb = PixelPalette.components(hex) else { return hex }
        let boost = min(max(amount, 0), 1)

        // Rec. 601 luma: the eye reads green as much brighter than blue, and using a
        // flat average here visibly darkens greens and lightens blues.
        let luma = 0.299 * rgb.r + 0.587 * rgb.g + 0.114 * rgb.b

        func push(_ channel: Double) -> Int {
            let stretched = luma + (channel - luma) * (1 + boost)
            return Int(min(max(stretched.rounded(), 0), 255))
        }
        return String(format: "%02X%02X%02X", push(rgb.r), push(rgb.g), push(rgb.b))
    }

    /// The same adjustment, as a drawable colour.
    public static func cgColor(_ hex: String, saturationBoost: Double) -> CGColor {
        FlagRenderer.cgColor(saturated(hex, by: saturationBoost))
    }
}
