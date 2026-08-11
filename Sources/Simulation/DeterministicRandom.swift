import Foundation

/// A seeded pseudo-random generator with reproducible output.
///
/// The simulation must never use `arc4random`, `Double.random(in:)` or anything else
/// seeded from the system: a scenario has to replay identically every time it is
/// scrubbed, re-opened or exported, or the preview and the finished video would
/// diverge. Every random decision in the war simulator draws from one of these,
/// seeded from the project.
///
/// SplitMix64 is used rather than Swift's `SystemRandomNumberGenerator` because its
/// algorithm is fixed and documented — a future Swift release cannot silently change
/// the sequence and invalidate saved projects.
public struct DeterministicRandom: RandomNumberGenerator, Sendable {

    private var state: UInt64

    public init(seed: UInt64) {
        // A zero seed would make the first outputs unusually structured; offset it.
        self.state = seed &+ 0x9E37_79B9_7F4A_7C15
    }

    public mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A uniform value in 0..<1.
    public mutating func unit() -> Double {
        // Take the top 53 bits, the most a Double can represent exactly.
        Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }

    public mutating func double(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + unit() * (range.upperBound - range.lowerBound)
    }

    /// A multiplier centred on 1 that varies by at most `spread`.
    ///
    /// This is how the simulator adds uncertainty without letting it dominate:
    /// `spread` 0 makes outcomes purely a function of the strengths involved, which
    /// is what the deterministic tests rely on.
    public mutating func jitter(spread: Double) -> Double {
        guard spread > 0 else { return 1 }
        return 1 + double(in: -spread...spread)
    }

    public mutating func bool(probability: Double) -> Bool {
        unit() < probability
    }

    /// Derives an independent stream from this one, so adding a new random decision
    /// in one part of the simulation cannot shift the sequence another part sees.
    public func stream(_ label: String) -> DeterministicRandom {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in label.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
        }
        return DeterministicRandom(seed: state ^ hash)
    }
}
