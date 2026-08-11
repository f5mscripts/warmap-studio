import CoreGraphics
import Foundation

/// Polygon and polyline operations used by the renderer and the frontline tools.
///
/// Everything here works in screen space on `CGPoint`, is pure, and has no
/// dependency on the map data — which is what makes the border animations testable
/// and identical between the live preview and the exported video.
public enum Geometry {

    // MARK: - Half-plane clipping

    /// Clips a polygon to one side of a line: Sutherland–Hodgman against a single
    /// half-plane.
    ///
    /// Keeps the region where `dot(p - origin, normal) >= 0`. This is the primitive
    /// behind every advancing border in the app — hold the normal fixed, slide the
    /// origin along it, and the attacker's fill grows across the territory. It is
    /// exact, allocation-light, and needs no polygon boolean library.
    ///
    /// The input is treated as a closed ring; a convex result is not required, but
    /// as with any Sutherland–Hodgman clip a concave polygon may come back with
    /// coincident edges joining separated pieces. At border-sweep scale that is
    /// invisible, and it never produces a wrong-side fill.
    public static func clip(_ points: [CGPoint], origin: CGPoint, normal: CGVector) -> [CGPoint] {
        guard points.count >= 3 else { return [] }

        @inline(__always)
        func signedDistance(_ p: CGPoint) -> CGFloat {
            (p.x - origin.x) * normal.dx + (p.y - origin.y) * normal.dy
        }

        var output: [CGPoint] = []
        output.reserveCapacity(points.count + 4)

        for i in 0..<points.count {
            let current = points[i]
            let next = points[(i + 1) % points.count]
            let dCurrent = signedDistance(current)
            let dNext = signedDistance(next)

            if dCurrent >= 0 {
                output.append(current)
            }
            if (dCurrent >= 0) != (dNext >= 0) {
                let denominator = dCurrent - dNext
                guard abs(denominator) > .ulpOfOne else { continue }
                let t = dCurrent / denominator
                output.append(CGPoint(x: current.x + (next.x - current.x) * t,
                                      y: current.y + (next.y - current.y) * t))
            }
        }
        return output
    }

    /// Builds the half-plane for a sweep across `bounds` in `direction`.
    ///
    /// `progress` 0 puts the cut at the trailing edge (nothing captured) and 1 puts
    /// it past the leading edge (everything captured). The normal points backwards
    /// along the direction so the *captured* side is what `clip` keeps.
    public static func sweepHalfPlane(bounds: CGRect,
                                      direction: CGVector,
                                      progress: Double) -> (origin: CGPoint, normal: CGVector) {
        let length = max(sqrt(direction.dx * direction.dx + direction.dy * direction.dy), .ulpOfOne)
        let unit = CGVector(dx: direction.dx / length, dy: direction.dy / length)

        // Project the rectangle's corners onto the sweep axis to find how far the
        // cut must travel to cross the whole shape.
        let corners = [
            CGPoint(x: bounds.minX, y: bounds.minY),
            CGPoint(x: bounds.maxX, y: bounds.minY),
            CGPoint(x: bounds.minX, y: bounds.maxY),
            CGPoint(x: bounds.maxX, y: bounds.maxY),
        ]
        var lo = CGFloat.infinity
        var hi = -CGFloat.infinity
        for c in corners {
            let t = c.x * unit.dx + c.y * unit.dy
            lo = min(lo, t)
            hi = max(hi, t)
        }

        let clamped = CGFloat(min(max(progress, 0), 1))
        // Nudge outwards at both ends so 0% and 100% are exactly empty and exactly
        // full rather than leaving a hairline of the other colour.
        let travel = lo + (hi - lo) * clamped
        let epsilon: CGFloat = 0.5
        let position = travel + (clamped >= 1 ? epsilon : (clamped <= 0 ? -epsilon : 0))
        let origin = CGPoint(x: unit.dx * position, y: unit.dy * position)
        return (origin, CGVector(dx: -unit.dx, dy: -unit.dy))
    }

    // MARK: - Hit testing

    /// Even-odd point-in-polygon (ray casting), used to find the tapped territory.
    public static func contains(_ ring: [CGPoint], point: CGPoint) -> Bool {
        guard ring.count >= 3 else { return false }
        var inside = false
        var j = ring.count - 1
        for i in 0..<ring.count {
            let a = ring[i]
            let b = ring[j]
            if (a.y > point.y) != (b.y > point.y) {
                let denominator = b.y - a.y
                if abs(denominator) > .ulpOfOne {
                    let x = a.x + (point.y - a.y) / denominator * (b.x - a.x)
                    if point.x < x { inside.toggle() }
                }
            }
            j = i
        }
        return inside
    }

    // MARK: - Polyline operations

    /// Douglas–Peucker simplification of an open polyline.
    public static func simplify(_ points: [CGPoint], tolerance: CGFloat) -> [CGPoint] {
        guard tolerance > 0, points.count > 2 else { return points }

        func recurse(_ slice: ArraySlice<CGPoint>) -> [CGPoint] {
            guard slice.count > 2,
                  let first = slice.first,
                  let last = slice.last else { return Array(slice) }

            let dx = last.x - first.x
            let dy = last.y - first.y
            let length = sqrt(dx * dx + dy * dy)

            var worstIndex = slice.startIndex
            var worstDistance: CGFloat = -1
            for i in (slice.startIndex + 1)..<(slice.endIndex - 1) {
                let p = slice[i]
                let distance: CGFloat
                if length < .ulpOfOne {
                    distance = hypot(p.x - first.x, p.y - first.y)
                } else {
                    distance = abs(dy * p.x - dx * p.y + last.x * first.y - last.y * first.x) / length
                }
                if distance > worstDistance {
                    worstDistance = distance
                    worstIndex = i
                }
            }

            guard worstDistance > tolerance else { return [first, last] }
            let left = recurse(slice[slice.startIndex...worstIndex])
            let right = recurse(slice[worstIndex..<slice.endIndex])
            return Array(left.dropLast()) + right
        }

        return recurse(points[...])
    }

    /// Chaikin corner cutting — the "smooth" tool for hand-drawn frontlines.
    ///
    /// Each pass replaces every segment with two points at 1/4 and 3/4, which
    /// converges on a quadratic B-spline. Two passes is usually enough to turn a
    /// shaky finger-drawn line into something that looks deliberate.
    public static func smooth(_ points: [CGPoint], iterations: Int = 2, closed: Bool = false) -> [CGPoint] {
        guard points.count >= 3, iterations > 0 else { return points }
        var current = points
        for _ in 0..<iterations {
            var next: [CGPoint] = []
            next.reserveCapacity(current.count * 2)
            if !closed, let first = current.first { next.append(first) }
            let limit = closed ? current.count : current.count - 1
            for i in 0..<limit {
                let a = current[i]
                let b = current[(i + 1) % current.count]
                next.append(CGPoint(x: a.x * 0.75 + b.x * 0.25, y: a.y * 0.75 + b.y * 0.25))
                next.append(CGPoint(x: a.x * 0.25 + b.x * 0.75, y: a.y * 0.25 + b.y * 0.75))
            }
            if !closed, let last = current.last { next.append(last) }
            current = next
        }
        return current
    }

    /// Total length of a polyline.
    public static func length(_ points: [CGPoint]) -> CGFloat {
        guard points.count > 1 else { return 0 }
        var total: CGFloat = 0
        for i in 1..<points.count {
            total += hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y)
        }
        return total
    }

    /// The point a given fraction along a polyline, plus the direction there.
    /// Used to place arrowheads and battle markers on a frontline.
    public static func pointAlong(_ points: [CGPoint], fraction: Double) -> (point: CGPoint, direction: CGVector)? {
        guard points.count > 1 else { return points.first.map { ($0, CGVector(dx: 1, dy: 0)) } }
        let total = length(points)
        guard total > 0 else { return (points[0], CGVector(dx: 1, dy: 0)) }

        let target = total * CGFloat(min(max(fraction, 0), 1))
        var travelled: CGFloat = 0
        for i in 1..<points.count {
            let a = points[i - 1]
            let b = points[i]
            let segment = hypot(b.x - a.x, b.y - a.y)
            if travelled + segment >= target, segment > .ulpOfOne {
                let t = (target - travelled) / segment
                return (
                    CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t),
                    CGVector(dx: (b.x - a.x) / segment, dy: (b.y - a.y) / segment)
                )
            }
            travelled += segment
        }
        let a = points[points.count - 2]
        let b = points[points.count - 1]
        let segment = max(hypot(b.x - a.x, b.y - a.y), .ulpOfOne)
        return (b, CGVector(dx: (b.x - a.x) / segment, dy: (b.y - a.y) / segment))
    }

    /// Signed area of a ring. Positive means counter-clockwise in a y-up space;
    /// with screen coordinates (y down) the sign flips, so callers that care about
    /// winding should compare against their own convention.
    public static func signedArea(_ ring: [CGPoint]) -> CGFloat {
        guard ring.count >= 3 else { return 0 }
        var sum: CGFloat = 0
        var j = ring.count - 1
        for i in 0..<ring.count {
            sum += (ring[j].x * ring[i].y) - (ring[i].x * ring[j].y)
            j = i
        }
        return sum / 2
    }

    /// Area-weighted centroid of a ring, falling back to the average vertex for
    /// degenerate input.
    public static func centroid(_ ring: [CGPoint]) -> CGPoint {
        guard ring.count >= 3 else {
            guard !ring.isEmpty else { return .zero }
            let sum = ring.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
            return CGPoint(x: sum.x / CGFloat(ring.count), y: sum.y / CGFloat(ring.count))
        }
        var area: CGFloat = 0
        var cx: CGFloat = 0
        var cy: CGFloat = 0
        var j = ring.count - 1
        for i in 0..<ring.count {
            let cross = ring[j].x * ring[i].y - ring[i].x * ring[j].y
            area += cross
            cx += (ring[j].x + ring[i].x) * cross
            cy += (ring[j].y + ring[i].y) * cross
            j = i
        }
        guard abs(area) > .ulpOfOne else {
            let sum = ring.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
            return CGPoint(x: sum.x / CGFloat(ring.count), y: sum.y / CGFloat(ring.count))
        }
        return CGPoint(x: cx / (3 * area), y: cy / (3 * area))
    }
}
