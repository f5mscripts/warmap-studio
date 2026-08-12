import CoreGraphics
import Foundation

/// The geometry side of the pixel-art style: how big the low-resolution buffer is,
/// and how drawing is pushed onto its grid.
///
/// Rendering small and upscaling is what makes the pixels; snapping is what makes
/// them *look* deliberate. Without it a coastline lands on fractional pixel
/// coordinates and Core Graphics resolves the fraction as coverage, so an
/// upscaled edge comes out as a soft staircase instead of a tiled one — even with
/// anti-aliasing off, since a polygon edge crossing a pixel centre still flips that
/// whole pixel on or off at an arbitrary point along the run.
public enum PixelGrid {

    /// A low-resolution buffer and the whole-number factor it is blown up by.
    public struct Buffer: Equatable, Sendable {
        /// Buffer size in low-resolution pixels.
        public let size: CGSize
        /// Upscale factor. Always an integer, so every source pixel becomes an
        /// identical square block rather than some blocks being a row taller.
        public let scale: CGFloat

        /// The size the upscaled image occupies. Never smaller than the viewport it
        /// was derived from, so no edge of the frame is left unpainted.
        public var outputSize: CGSize {
            CGSize(width: size.width * scale, height: size.height * scale)
        }
    }

    /// Chooses a buffer for `viewport` whose short edge is near `shortEdge` pixels.
    ///
    /// The scale is rounded to a whole number first and the buffer sized from it,
    /// rather than the other way round: an exact 200-pixel short edge with a 5.4×
    /// upscale would give a frame of mixed 5- and 6-pixel blocks, which reads as a
    /// rendering fault rather than as pixel art.
    public static func buffer(for viewport: CGSize, shortEdge: Int) -> Buffer? {
        guard viewport.width >= 1, viewport.height >= 1, shortEdge >= 1 else { return nil }
        let short = min(viewport.width, viewport.height)
        let scale = max(1, (short / CGFloat(shortEdge)).rounded())
        let size = CGSize(width: (viewport.width / scale).rounded(.up),
                          height: (viewport.height / scale).rounded(.up))
        return Buffer(size: size, scale: scale)
    }

    // MARK: - Snapping

    /// Snaps to whole pixels. `offset` shifts the result off the grid line — pass
    /// `lineOffset(forWidth:)` when stroking, so an odd-width line covers whole
    /// pixels instead of straddling two half-lit ones.
    public static func snap(_ value: CGFloat, offset: CGFloat = 0) -> CGFloat {
        // Coordinates this large only occur for geometry far outside the viewport,
        // where snapping buys nothing and rounding risks losing precision entirely.
        guard value.isFinite, abs(value) < 1e7 else { return value }
        return value.rounded() + offset
    }

    public static func snap(_ point: CGPoint, offset: CGFloat = 0) -> CGPoint {
        CGPoint(x: snap(point.x, offset: offset), y: snap(point.y, offset: offset))
    }

    /// Snaps a rectangle outwards, so a one-pixel-tall bar never rounds away to
    /// nothing.
    public static func snap(_ rect: CGRect) -> CGRect {
        guard !rect.isNull, !rect.isInfinite else { return rect }
        let minX = snap(rect.minX)
        let minY = snap(rect.minY)
        return CGRect(x: minX,
                      y: minY,
                      width: max(1, snap(rect.maxX) - minX),
                      height: max(1, snap(rect.maxY) - minY))
    }

    /// Rebuilds a path with every point on the pixel grid.
    ///
    /// Curves keep their control points snapped too. In practice the map's territory
    /// and border paths are polylines, so this is a straight vertex rewrite.
    public static func snap(_ path: CGPath, offset: CGFloat = 0) -> CGPath {
        let snapped = CGMutablePath()
        path.applyWithBlock { pointer in
            let element = pointer.pointee
            let points = element.points
            switch element.type {
            case .moveToPoint:
                snapped.move(to: snap(points[0], offset: offset))
            case .addLineToPoint:
                snapped.addLine(to: snap(points[0], offset: offset))
            case .addQuadCurveToPoint:
                snapped.addQuadCurve(to: snap(points[1], offset: offset),
                                     control: snap(points[0], offset: offset))
            case .addCurveToPoint:
                snapped.addCurve(to: snap(points[2], offset: offset),
                                 control1: snap(points[0], offset: offset),
                                 control2: snap(points[1], offset: offset))
            case .closeSubpath:
                snapped.closeSubpath()
            @unknown default:
                break
            }
        }
        return snapped
    }

    /// Half a pixel for odd stroke widths, zero for even ones — the classic fix for
    /// blurry hairlines, which matters more here than usual because a stroke is only
    /// one or two pixels wide to begin with.
    public static func lineOffset(forWidth width: CGFloat) -> CGFloat {
        Int(width.rounded()) % 2 == 0 ? 0 : 0.5
    }
}
