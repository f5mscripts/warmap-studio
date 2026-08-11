import CoreGraphics
import Foundation

/// Timing curves for every animated property in the app.
///
/// Deliberately hand-rolled rather than delegating to Core Animation: the export
/// renderer evaluates animation at arbitrary times on a background thread with no
/// `CALayer` involved, and the preview must produce byte-identical results. A pure
/// function of `t` is the only way both can agree.
public enum EasingCurve: String, Codable, CaseIterable, Sendable, Identifiable {
    case linear
    case easeIn
    case easeOut
    case easeInOut
    /// Slow start, fast middle, slow end — stronger than `easeInOut`. The default
    /// for territory sweeps, where a linear advance looks mechanical.
    case smoothStep
    /// Overshoots slightly then settles. For markers appearing.
    case backOut
    /// Decaying bounce. For emphatic reveals.
    case elasticOut
    /// Snaps at the end. For city captures.
    case anticipate

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .linear: return "Linear"
        case .easeIn: return "Ease In"
        case .easeOut: return "Ease Out"
        case .easeInOut: return "Ease In-Out"
        case .smoothStep: return "Smooth"
        case .backOut: return "Overshoot"
        case .elasticOut: return "Elastic"
        case .anticipate: return "Anticipate"
        }
    }

    /// Maps normalised progress to eased progress. Input is clamped to 0…1; output
    /// may briefly leave that range for the overshooting curves, which is the point.
    public func apply(_ t: Double) -> Double {
        let x = min(max(t, 0), 1)
        switch self {
        case .linear:
            return x
        case .easeIn:
            return x * x
        case .easeOut:
            return 1 - (1 - x) * (1 - x)
        case .easeInOut:
            return x < 0.5 ? 2 * x * x : 1 - pow(-2 * x + 2, 2) / 2
        case .smoothStep:
            return x * x * x * (x * (x * 6 - 15) + 10)
        case .backOut:
            let c1 = 1.70158
            let c3 = c1 + 1
            return 1 + c3 * pow(x - 1, 3) + c1 * pow(x - 1, 2)
        case .elasticOut:
            guard x > 0, x < 1 else { return x }
            let c4 = (2 * Double.pi) / 3
            return pow(2, -10 * x) * sin((x * 10 - 0.75) * c4) + 1
        case .anticipate:
            let c1 = 1.70158
            return x * x * ((c1 + 1) * x - c1)
        }
    }
}

/// Interpolation helpers shared by the animation and rendering layers.
public enum Interpolate {

    public static func double(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }

    public static func point(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * CGFloat(t), y: a.y + (b.y - a.y) * CGFloat(t))
    }

    public static func coordinate(_ a: GeoCoordinate, _ b: GeoCoordinate, _ t: Double) -> GeoCoordinate {
        // Take the short way around the antimeridian, so an army crossing the Pacific
        // does not swing back across the whole map.
        var deltaLon = b.longitude - a.longitude
        if deltaLon > 180 { deltaLon -= 360 }
        if deltaLon < -180 { deltaLon += 360 }
        return GeoCoordinate(longitude: a.longitude + deltaLon * t,
                             latitude: a.latitude + (b.latitude - a.latitude) * t)
    }

    /// Interpolates two polylines by resampling both to a common vertex count, which
    /// is what lets a hand-drawn frontline morph smoothly into another shape even
    /// when the two have completely different numbers of points.
    public static func polyline(_ a: [GeoCoordinate],
                                _ b: [GeoCoordinate],
                                _ t: Double,
                                samples: Int = 64) -> [GeoCoordinate] {
        guard !a.isEmpty else { return b }
        guard !b.isEmpty else { return a }
        let from = resample(a, count: samples)
        let to = resample(b, count: samples)
        return zip(from, to).map { coordinate($0, $1, t) }
    }

    /// Resamples a polyline to exactly `count` points, evenly spaced by arc length.
    public static func resample(_ points: [GeoCoordinate], count: Int) -> [GeoCoordinate] {
        guard points.count > 1, count > 1 else {
            return Array(repeating: points.first ?? GeoCoordinate(longitude: 0, latitude: 0),
                         count: max(count, 1))
        }

        var cumulative: [Double] = [0]
        cumulative.reserveCapacity(points.count)
        var total = 0.0
        for i in 1..<points.count {
            let dx = points[i].longitude - points[i - 1].longitude
            let dy = points[i].latitude - points[i - 1].latitude
            total += (dx * dx + dy * dy).squareRoot()
            cumulative.append(total)
        }
        guard total > 0 else { return Array(repeating: points[0], count: count) }

        var result: [GeoCoordinate] = []
        result.reserveCapacity(count)
        var segment = 1
        for i in 0..<count {
            let target = total * Double(i) / Double(count - 1)
            while segment < cumulative.count - 1 && cumulative[segment] < target {
                segment += 1
            }
            let spanStart = cumulative[segment - 1]
            let spanLength = cumulative[segment] - spanStart
            let local = spanLength > 0 ? (target - spanStart) / spanLength : 0
            result.append(coordinate(points[segment - 1], points[segment], local))
        }
        return result
    }

    /// Blends two `RRGGBB` colours, returning the same form.
    public static func colorHex(_ a: String, _ b: String, _ t: Double) -> String {
        func channels(_ hex: String) -> (Double, Double, Double)? {
            let text = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
            guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
            return (Double((value >> 16) & 0xFF), Double((value >> 8) & 0xFF), Double(value & 0xFF))
        }
        guard let from = channels(a), let to = channels(b) else { return t < 0.5 ? a : b }
        let r = UInt32((from.0 + (to.0 - from.0) * t).rounded())
        let g = UInt32((from.1 + (to.1 - from.1) * t).rounded())
        let bl = UInt32((from.2 + (to.2 - from.2) * t).rounded())
        return String(format: "%02X%02X%02X", r, g, bl)
    }
}
