import CoreGraphics
import Foundation

/// Draws `FlagSpec` values with Core Graphics.
///
/// Used everywhere a flag appears — country labels on the map, the dashboard, the
/// timeline, the inspector, and the exported video — so that one description of a
/// flag renders identically at 16 points and at 200.
public enum FlagRenderer {

    /// Draws the flag to fill `rect` exactly. The caller decides the aspect; use
    /// `fittedRect(for:in:)` first if the flag's own ratio should be respected.
    public static func draw(_ spec: FlagSpec, in rect: CGRect, context: CGContext) {
        guard rect.width > 0, rect.height > 0 else { return }

        context.saveGState()
        context.clip(to: rect)

        drawField(spec.field, in: rect, context: context)
        for overlay in spec.overlays {
            draw(overlay, in: rect, context: context)
        }

        context.restoreGState()
    }

    /// The largest rect with the flag's aspect ratio that fits inside `bounds`,
    /// centred.
    public static func fittedRect(for spec: FlagSpec, in bounds: CGRect) -> CGRect {
        let ratio = max(spec.aspectRatio, 0.1)
        var size = CGSize(width: bounds.width, height: bounds.width / ratio)
        if size.height > bounds.height {
            size = CGSize(width: bounds.height * ratio, height: bounds.height)
        }
        return CGRect(x: bounds.midX - size.width / 2,
                      y: bounds.midY - size.height / 2,
                      width: size.width,
                      height: size.height)
    }

    // MARK: - Field

    private static func drawField(_ field: FlagField, in rect: CGRect, context: CGContext) {
        switch field {
        case .solid(let hex):
            context.setFillColor(cgColor(hex))
            context.fill(rect)

        case .horizontal(let colors):
            guard !colors.isEmpty else { return }
            let bandHeight = rect.height / CGFloat(colors.count)
            for (index, hex) in colors.enumerated() {
                context.setFillColor(cgColor(hex))
                // Overdraw by a hair so anti-aliasing never leaves a seam between bands.
                context.fill(CGRect(x: rect.minX,
                                    y: rect.minY + CGFloat(index) * bandHeight,
                                    width: rect.width,
                                    height: bandHeight + 0.5))
            }

        case .vertical(let colors):
            guard !colors.isEmpty else { return }
            let bandWidth = rect.width / CGFloat(colors.count)
            for (index, hex) in colors.enumerated() {
                context.setFillColor(cgColor(hex))
                context.fill(CGRect(x: rect.minX + CGFloat(index) * bandWidth,
                                    y: rect.minY,
                                    width: bandWidth + 0.5,
                                    height: rect.height))
            }

        case .diagonal(let colors):
            guard !colors.isEmpty else { return }
            // Fill the whole flag with the first colour, then lay the remaining
            // colours as corner-to-corner wedges.
            context.setFillColor(cgColor(colors[0]))
            context.fill(rect)
            guard colors.count > 1 else { return }
            let step = 1.0 / Double(colors.count)
            for (index, hex) in colors.enumerated().dropFirst() {
                let offset = CGFloat(Double(index) * step)
                context.setFillColor(cgColor(hex))
                context.beginPath()
                context.move(to: CGPoint(x: rect.minX + rect.width * offset, y: rect.maxY))
                context.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * offset))
                context.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                context.closePath()
                context.fillPath()
            }
        }
    }

    // MARK: - Overlays

    private static func draw(_ overlay: FlagOverlay, in rect: CGRect, context: CGContext) {
        switch overlay {
        case .cross(let hex, let thickness, let offsetFromHoist):
            context.setFillColor(cgColor(hex))
            let bar = rect.height * CGFloat(thickness)
            let x = rect.minX + rect.width * CGFloat(offsetFromHoist)
            context.fill(CGRect(x: rect.minX, y: rect.midY - bar / 2,
                                width: rect.width, height: bar))
            context.fill(CGRect(x: x - bar / 2, y: rect.minY,
                                width: bar, height: rect.height))

        case .saltire(let hex, let thickness):
            context.setStrokeColor(cgColor(hex))
            context.setLineWidth(rect.height * CGFloat(thickness))
            context.beginPath()
            context.move(to: CGPoint(x: rect.minX, y: rect.minY))
            context.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            context.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            context.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            context.strokePath()

        case .canton(let hex, let widthFraction, let heightFraction):
            context.setFillColor(cgColor(hex))
            context.fill(CGRect(x: rect.minX, y: rect.minY,
                                width: rect.width * CGFloat(widthFraction),
                                height: rect.height * CGFloat(heightFraction)))

        case .disc(let hex, let radius, let center):
            context.setFillColor(cgColor(hex))
            let r = rect.height * CGFloat(radius)
            let c = point(center, in: rect)
            context.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))

        case .crescent(let hex, let radius, let center):
            drawCrescent(hex: hex, radius: radius, center: center, in: rect, context: context)

        case .star(let hex, let points, let radius, let center):
            context.setFillColor(cgColor(hex))
            context.addPath(starPath(points: points,
                                     radius: rect.height * CGFloat(radius),
                                     center: point(center, in: rect)))
            context.fillPath()

        case .stripe(let hex, let thickness, let position):
            context.setFillColor(cgColor(hex))
            let bar = rect.height * CGFloat(thickness)
            context.fill(CGRect(x: rect.minX,
                                y: rect.minY + rect.height * CGFloat(position) - bar / 2,
                                width: rect.width, height: bar))

        case .hoistTriangle(let hex, let widthFraction):
            context.setFillColor(cgColor(hex))
            context.beginPath()
            context.move(to: CGPoint(x: rect.minX, y: rect.minY))
            context.addLine(to: CGPoint(x: rect.minX + rect.width * CGFloat(widthFraction),
                                        y: rect.midY))
            context.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            context.closePath()
            context.fillPath()

        case .border(let hex, let thickness):
            context.setStrokeColor(cgColor(hex))
            let width = rect.height * CGFloat(thickness)
            context.setLineWidth(width)
            context.stroke(rect.insetBy(dx: width / 2, dy: width / 2))
        }
    }

    /// A crescent as the difference of two discs: fill the outer one, then punch a
    /// smaller offset disc back out using the colours already underneath.
    private static func drawCrescent(hex: String, radius: Double, center: CGPoint,
                                     in rect: CGRect, context: CGContext) {
        let r = rect.height * CGFloat(radius)
        let c = point(center, in: rect)

        context.saveGState()
        // Clip to the outer disc minus the inner disc using the even-odd rule, so
        // whatever is behind the flag shows through the bite.
        let outer = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
        let innerRadius = r * 0.82
        let innerCentre = CGPoint(x: c.x + r * 0.28, y: c.y)
        let inner = CGRect(x: innerCentre.x - innerRadius, y: innerCentre.y - innerRadius,
                           width: innerRadius * 2, height: innerRadius * 2)

        let path = CGMutablePath()
        path.addEllipse(in: outer)
        path.addEllipse(in: inner)
        context.addPath(path)
        context.clip(using: .evenOdd)
        context.setFillColor(cgColor(hex))
        context.fill(rect)
        context.restoreGState()
    }

    private static func starPath(points: Int, radius: CGFloat, center: CGPoint) -> CGPath {
        let path = CGMutablePath()
        let count = max(3, points)
        let inner = radius * 0.4
        for i in 0..<(count * 2) {
            let r = i.isMultiple(of: 2) ? radius : inner
            // Start at the top and go clockwise.
            let angle = -CGFloat.pi / 2 + CGFloat(i) * .pi / CGFloat(count)
            let p = CGPoint(x: center.x + r * cos(angle), y: center.y + r * sin(angle))
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }

    /// Flag-relative (0…1, origin at the top hoist corner) to context coordinates.
    private static func point(_ relative: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + rect.width * relative.x,
                y: rect.minY + rect.height * relative.y)
    }

    // MARK: - Colour

    /// Parses `"RRGGBB"` or `"#RRGGBB"`. Unparseable input becomes mid-grey rather
    /// than crashing or drawing nothing, so a typo in a project file is visible but
    /// harmless.
    public static func cgColor(_ hex: String) -> CGColor {
        var text = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        if text.count == 3 {
            // Expand shorthand like "F00".
            text = text.map { "\($0)\($0)" }.joined()
        }
        guard text.count == 6, let value = UInt32(text, radix: 16) else {
            return CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        }
        return CGColor(red: CGFloat((value >> 16) & 0xFF) / 255,
                       green: CGFloat((value >> 8) & 0xFF) / 255,
                       blue: CGFloat(value & 0xFF) / 255,
                       alpha: 1)
    }
}
