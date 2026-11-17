/// A small, fast random number generator (SplitMix64) that always produces the same
/// sequence for the same seed, so generated scenery looks the same on every launch.
///
/// Use ``unit()`` and ``value(in:)`` rather than the standard library's
/// `random(in:using:)`: how the standard library turns raw bits into a range is not
/// guaranteed to stay the same between Swift versions.
public struct SeededRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A value in `0..<1`.
    public mutating func unit() -> Double {
        Double(next() >> 11) * 0x1p-53
    }

    /// A value in `range` (the upper bound is never returned unless the range is empty).
    public mutating func value(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + unit() * (range.upperBound - range.lowerBound)
    }

    /// Mixes several values into one well-spread seed.
    static func seed(_ values: Int...) -> UInt64 {
        var generator = SeededRandom(seed: 0x5EED_1E7E_15CE_4E2A)
        var result: UInt64 = 0
        for value in values {
            generator.state ^= UInt64(bitPattern: Int64(value))
            result = generator.next()
        }
        return result
    }
}
