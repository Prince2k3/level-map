import CoreGraphics

extension CGPoint {
    static func + (lhs: CGPoint, rhs: CGVector) -> CGPoint { CGPoint(x: lhs.x + rhs.dx, y: lhs.y + rhs.dy) }
    static func - (lhs: CGPoint, rhs: CGVector) -> CGPoint { CGPoint(x: lhs.x - rhs.dx, y: lhs.y - rhs.dy) }
    static func - (lhs: CGPoint, rhs: CGPoint) -> CGVector { CGVector(dx: lhs.x - rhs.x, dy: lhs.y - rhs.y) }

    func distance(to other: CGPoint) -> CGFloat { (other - self).length }
    func offsetBy(dy: CGFloat) -> CGPoint { CGPoint(x: x, y: y + dy) }
}

extension CGVector {
    static func * (lhs: CGVector, rhs: CGFloat) -> CGVector { CGVector(dx: lhs.dx * rhs, dy: lhs.dy * rhs) }
    static func / (lhs: CGVector, rhs: CGFloat) -> CGVector { CGVector(dx: lhs.dx / rhs, dy: lhs.dy / rhs) }

    var length: CGFloat { lengthSquared.squareRoot() }
    var lengthSquared: CGFloat { dx * dx + dy * dy }

    /// This vector scaled to length 1, or `nil` when it is (almost) zero.
    var normalized: CGVector? {
        let length = self.length
        guard length > 1e-9 else { return nil }
        return self / length
    }
}

/// A cubic Bézier curve.
struct CubicBezier: Sendable, Equatable {
    var p0: CGPoint
    var c1: CGPoint
    var c2: CGPoint
    var p3: CGPoint

    func point(at t: CGFloat) -> CGPoint {
        let mt = 1 - t
        let a = mt * mt * mt
        let b = 3 * mt * mt * t
        let c = 3 * mt * t * t
        let d = t * t * t
        return CGPoint(
            x: a * p0.x + b * c1.x + c * c2.x + d * p3.x,
            y: a * p0.y + b * c1.y + c * c2.y + d * p3.y
        )
    }

    func derivative(at t: CGFloat) -> CGVector {
        let mt = 1 - t
        let a = 3 * mt * mt
        let b = 6 * mt * t
        let c = 3 * t * t
        return CGVector(
            dx: a * (c1.x - p0.x) + b * (c2.x - c1.x) + c * (p3.x - c2.x),
            dy: a * (c1.y - p0.y) + b * (c2.y - c1.y) + c * (p3.y - c2.y)
        )
    }

    /// Unit direction of travel at `t`. Falls back to the chord direction where the
    /// derivative vanishes (for example when a control point sits on an end point).
    func tangent(at t: CGFloat) -> CGVector {
        if let direction = derivative(at: t).normalized { return direction }
        let nudged = t < 0.5 ? min(t + 1e-3, 1) : max(t - 1e-3, 0)
        if let direction = derivative(at: nudged).normalized { return direction }
        return (p3 - p0).normalized ?? CGVector(dx: 0, dy: 1)
    }
}

/// Maps arc-length distance to a location on a chain of cubic curves.
///
/// Each curve is sampled at a fixed number of points. A lookup is a binary search
/// over the cumulative chord lengths followed by linear interpolation, so it runs
/// in O(log n) time.
struct ArcLengthTable: Sendable {
    static let defaultSamplesPerCurve = 48

    let samplesPerCurve: Int
    let curveCount: Int
    /// Cumulative lengths. Entry `i` is the length up to sample `i`; there are
    /// `curveCount * samplesPerCurve + 1` entries.
    private let lengths: [CGFloat]

    init(curves: [CubicBezier], samplesPerCurve: Int = ArcLengthTable.defaultSamplesPerCurve) {
        self.samplesPerCurve = samplesPerCurve
        self.curveCount = curves.count
        var lengths: [CGFloat] = [0]
        lengths.reserveCapacity(curves.count * samplesPerCurve + 1)
        var total: CGFloat = 0
        for curve in curves {
            var previous = curve.p0
            for step in 1...samplesPerCurve {
                let point = curve.point(at: CGFloat(step) / CGFloat(samplesPerCurve))
                total += previous.distance(to: point)
                lengths.append(total)
                previous = point
            }
        }
        self.lengths = lengths
    }

    var totalLength: CGFloat { lengths.last ?? 0 }

    /// The curve index and curve parameter `t` at arc-length `distance`, clamped to the chain.
    func location(atDistance distance: CGFloat) -> (curve: Int, t: CGFloat) {
        guard curveCount > 0 else { return (0, 0) }
        let d = min(max(distance, 0), totalLength)

        // Find the last index whose cumulative length is <= d.
        var low = 0
        var high = lengths.count - 1
        while low < high - 1 {
            let mid = (low + high) / 2
            if lengths[mid] <= d { low = mid } else { high = mid }
        }
        let span = lengths[high] - lengths[low]
        let fraction = span > 0 ? (d - lengths[low]) / span : 0
        let sample = CGFloat(low) + fraction
        let curve = min(low / samplesPerCurve, curveCount - 1)
        let t = (sample - CGFloat(curve * samplesPerCurve)) / CGFloat(samplesPerCurve)
        return (curve, min(max(t, 0), 1))
    }
}
