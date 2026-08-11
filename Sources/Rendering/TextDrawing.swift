import CoreGraphics
import CoreText
import Foundation
import UIKit

/// Core Text drawing used by the map renderer.
///
/// SwiftUI cannot help here: the exporter draws into a bitmap context on a
/// background thread with no view hierarchy, and the preview must produce identical
/// output. Core Text is the only layer both can share.
///
/// Coordinates are top-left origin, y growing downwards — matching every other
/// coordinate in the renderer — which Core Text is coaxed into by flipping the
/// context's text matrix rather than the context itself.
public enum TextDrawing {

    /// Builds a font for a numeric weight, optionally in a serif design.
    public static func font(size: CGFloat, weight: Int, usesSerif: Bool) -> UIFont {
        let uiWeight: UIFont.Weight
        switch weight {
        case ..<300: uiWeight = .light
        case ..<400: uiWeight = .regular
        case ..<500: uiWeight = .medium
        case ..<600: uiWeight = .semibold
        case ..<700: uiWeight = .bold
        case ..<800: uiWeight = .heavy
        default: uiWeight = .black
        }
        let base = UIFont.systemFont(ofSize: max(size, 1), weight: uiWeight)
        guard usesSerif,
              let descriptor = base.fontDescriptor.withDesign(.serif) else { return base }
        return UIFont(descriptor: descriptor, size: max(size, 1))
    }

    private static func line(_ text: String,
                             fontSize: CGFloat,
                             weight: Int,
                             usesSerif: Bool,
                             color: CGColor?,
                             outline: CGColor?,
                             outlineWidth: CGFloat,
                             letterSpacing: Double) -> CTLine {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font(size: fontSize, weight: weight, usesSerif: usesSerif)
        ]
        if let color {
            attributes[.foregroundColor] = color
        }
        if letterSpacing != 0 {
            attributes[.kern] = letterSpacing
        }
        if let outline, outlineWidth > 0 {
            attributes[.strokeColor] = outline
            // Core Text reads stroke width as a percentage of the font size, and a
            // negative value means "stroke *and* fill" rather than outline only —
            // which is what gives labels a readable halo over busy terrain.
            attributes[.strokeWidth] = -(outlineWidth / max(fontSize, 1)) * 100
        }
        let string = NSAttributedString(string: text, attributes: attributes)
        return CTLineCreateWithAttributedString(string as CFAttributedString)
    }

    /// Bounding size of a string, used for layout and collision avoidance.
    public static func measure(_ text: String,
                               fontSize: CGFloat,
                               weight: Int,
                               usesSerif: Bool,
                               letterSpacing: Double = 0) -> CGSize {
        guard !text.isEmpty else { return .zero }
        let ctLine = line(text, fontSize: fontSize, weight: weight, usesSerif: usesSerif,
                          color: nil, outline: nil, outlineWidth: 0,
                          letterSpacing: letterSpacing)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(ctLine, &ascent, &descent, &leading))
        return CGSize(width: width, height: ascent + descent)
    }

    /// Draws a single line with `origin` at its top-left corner.
    public static func draw(_ text: String,
                            at origin: CGPoint,
                            fontSize: CGFloat,
                            weight: Int,
                            usesSerif: Bool,
                            color: CGColor,
                            outline: CGColor?,
                            outlineWidth: CGFloat,
                            letterSpacing: Double = 0,
                            context: CGContext) {
        guard !text.isEmpty else { return }
        let ctLine = line(text, fontSize: fontSize, weight: weight, usesSerif: usesSerif,
                          color: color, outline: outline, outlineWidth: outlineWidth,
                          letterSpacing: letterSpacing)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        _ = CTLineGetTypographicBounds(ctLine, &ascent, &descent, &leading)

        context.saveGState()
        // Flip the text matrix instead of the context: glyphs come out the right way
        // up while every coordinate the caller passes stays in y-down space.
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = CGPoint(x: origin.x, y: origin.y + ascent)
        CTLineDraw(ctLine, context)
        context.restoreGState()
    }

    /// Draws text wrapped to a maximum width, returning the height it used.
    @discardableResult
    public static func drawWrapped(_ text: String,
                                   in rect: CGRect,
                                   fontSize: CGFloat,
                                   weight: Int,
                                   usesSerif: Bool,
                                   color: CGColor,
                                   alignment: TextAlignmentOption,
                                   letterSpacing: Double = 0,
                                   context: CGContext) -> CGFloat {
        guard !text.isEmpty, rect.width > 0 else { return 0 }

        let paragraph = NSMutableParagraphStyle()
        switch alignment {
        case .leading: paragraph.alignment = .left
        case .center: paragraph.alignment = .center
        case .trailing: paragraph.alignment = .right
        }
        paragraph.lineBreakMode = .byWordWrapping

        var attributes: [NSAttributedString.Key: Any] = [
            .font: font(size: fontSize, weight: weight, usesSerif: usesSerif),
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ]
        if letterSpacing != 0 { attributes[.kern] = letterSpacing }

        let string = NSAttributedString(string: text, attributes: attributes)
        let framesetter = CTFramesetterCreateWithAttributedString(string as CFAttributedString)
        let path = CGPath(rect: rect, transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), path, nil)

        context.saveGState()
        context.textMatrix = .identity
        // CTFrameDraw lays out top-down in a y-up space, so the context itself is
        // flipped here rather than just the text matrix.
        context.translateBy(x: 0, y: rect.maxY + rect.minY)
        context.scaleBy(x: 1, y: -1)
        CTFrameDraw(frame, context)
        context.restoreGState()

        let size = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter, CFRangeMake(0, 0), nil,
            CGSize(width: rect.width, height: .greatestFiniteMagnitude), nil
        )
        return size.height
    }
}
