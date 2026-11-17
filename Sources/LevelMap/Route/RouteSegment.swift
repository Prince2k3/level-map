import CoreGraphics

/// Values a segment needs to turn its description into points.
public struct RouteContext: Sendable, Equatable {
    /// The map width in points.
    public var width: CGFloat
    /// How far the road advances along the scroll axis per level, in points.
    public var spacing: CGFloat
    /// The least room the map keeps between a level and its edges. Segments needn't respect it:
    /// the resolved route is scaled in across the map to keep clear of the sides.
    public var edgeInset: CGFloat

    /// - Parameter edgeInset: Defaults to half the spacing.
    public init(width: CGFloat, spacing: CGFloat, edgeInset: CGFloat? = nil) {
        self.width = width
        self.spacing = spacing
        self.edgeInset = min(max(edgeInset ?? spacing / 2, 0), width / 2)
    }

    /// The scroll-axis length a segment with `levels` levels occupies.
    public func length(forLevels levels: Int) -> CGFloat {
        CGFloat(levels) * spacing
    }
}

/// A point the road passes through.
public struct RouteWaypoint: Sendable, Equatable {
    public var point: CGPoint
    /// When `true`, the road turns sharply here instead of curving smoothly.
    public var isCorner: Bool

    public init(_ point: CGPoint, isCorner: Bool = false) {
        self.point = point
        self.isCorner = isCorner
    }
}

/// One stretch of road that owns a number of levels.
///
/// A segment only lists the points the road passes through. The route joins all
/// waypoints into one smooth curve (Catmull-Rom style), so neighbouring segments
/// meet without kinks unless a waypoint is marked as a corner. The segment's
/// levels are then spread evenly, by arc length, along its stretch of road.
///
/// Conform to this protocol to make your own segment shapes.
public protocol RouteSegment: Sendable {
    /// How many levels sit on this segment.
    var levelCount: Int { get }

    /// The waypoints after `start` (which is where the previous segment ended),
    /// in points. The last waypoint is where this segment ends. `y` values should
    /// keep increasing so that the road keeps moving along the scroll axis.
    func waypoints(from start: CGPoint, in context: RouteContext) -> [RouteWaypoint]
}

// MARK: - Built-in segments

/// A straight run, optionally drifting to a new horizontal position.
public struct Straight: RouteSegment {
    public var levelCount: Int
    /// Where the segment ends across the map (a fraction of the width), or `nil` to keep the current position.
    public var endX: CGFloat?

    public init(levels: Int, toX endX: CGFloat? = nil) {
        precondition(levels > 0, "Straight needs at least one level")
        self.levelCount = levels
        self.endX = endX
    }

    public func waypoints(from start: CGPoint, in context: RouteContext) -> [RouteWaypoint] {
        let x = endX.map { $0 * context.width } ?? start.x
        return [RouteWaypoint(CGPoint(x: x, y: start.y + context.length(forLevels: levelCount)))]
    }
}

/// A smooth wave that swings from side to side around the middle of the map.
///
/// With an even number of half-waves the segment ends back in the middle,
/// heading the same way it started, so it repeats seamlessly.
public struct Serpentine: RouteSegment {
    public var levelCount: Int
    /// How far each swing reaches from the middle, as a fraction of the width (0...0.5).
    public var amplitude: CGFloat
    /// Number of swings (one swing = middle → side → middle).
    public var halfWaves: Int

    /// - Parameters:
    ///   - levels: How many levels sit on the wave.
    ///   - amplitude: How far each swing reaches from the middle, as a fraction of the width (0...0.5).
    ///   - halfWaves: The number of swings. Defaults to one swing per three levels.
    public init(levels: Int, amplitude: CGFloat = 0.3, halfWaves: Int? = nil) {
        precondition(levels > 0, "Serpentine needs at least one level")
        self.levelCount = levels
        self.amplitude = min(max(amplitude, 0), 0.5)
        self.halfWaves = max(1, halfWaves ?? Int((CGFloat(levels) / 3).rounded()))
    }

    public func waypoints(from start: CGPoint, in context: RouteContext) -> [RouteWaypoint] {
        WaveShape.waypoints(from: start, context: context, levels: levelCount,
                            amplitude: amplitude, halfWaves: halfWaves, cornersAtPeaks: false)
    }
}

/// Like ``Serpentine``, but with sharp turns at each side.
public struct Zigzag: RouteSegment {
    public var levelCount: Int
    public var amplitude: CGFloat
    public var halfWaves: Int

    public init(levels: Int, amplitude: CGFloat = 0.3, halfWaves: Int? = nil) {
        precondition(levels > 0, "Zigzag needs at least one level")
        self.levelCount = levels
        self.amplitude = min(max(amplitude, 0), 0.5)
        self.halfWaves = max(1, halfWaves ?? Int((CGFloat(levels) / 3).rounded()))
    }

    public func waypoints(from start: CGPoint, in context: RouteContext) -> [RouteWaypoint] {
        WaveShape.waypoints(from: start, context: context, levels: levelCount,
                            amplitude: amplitude, halfWaves: halfWaves, cornersAtPeaks: true)
    }
}

/// A free-form smooth curve through the given points.
public struct Spline: RouteSegment {
    public var levelCount: Int
    /// `x` is a fraction of the map width; `y` is a fraction of this segment's length.
    /// The last point is where the segment ends, so it usually has `y == 1`.
    public var points: [RoutePoint]

    public init(levels: Int, through points: [RoutePoint]) {
        precondition(levels > 0, "Spline needs at least one level")
        precondition(!points.isEmpty, "Spline needs at least one point")
        self.levelCount = levels
        self.points = points
    }

    public func waypoints(from start: CGPoint, in context: RouteContext) -> [RouteWaypoint] {
        let length = context.length(forLevels: levelCount)
        return points.map {
            RouteWaypoint(CGPoint(x: $0.x * context.width, y: start.y + $0.y * length))
        }
    }
}

/// A bulge out towards one edge of the map and back, for example around a landmark.
public struct Detour: RouteSegment {
    public var levelCount: Int
    public var side: RouteSide
    /// How close to the edge the road gets, as a fraction of the width from the edge.
    public var inset: CGFloat

    public init(around side: RouteSide, levels: Int, inset: CGFloat = 0.12) {
        precondition(levels > 0, "Detour needs at least one level")
        self.levelCount = levels
        self.side = side
        self.inset = min(max(inset, 0), 0.5)
    }

    public func waypoints(from start: CGPoint, in context: RouteContext) -> [RouteWaypoint] {
        let length = context.length(forLevels: levelCount)
        let edgeX = side == .leading ? inset * context.width : (1 - inset) * context.width
        return [
            RouteWaypoint(CGPoint(x: edgeX, y: start.y + length * 0.3)),
            RouteWaypoint(CGPoint(x: edgeX, y: start.y + length * 0.7)),
            RouteWaypoint(CGPoint(x: start.x, y: start.y + length)),
        ]
    }
}

enum WaveShape {
    /// Waypoints for a wave that swings from the middle line to alternating sides.
    ///
    /// A zigzag gets a corner at each peak and a waypoint at each crossing of the middle line.
    /// A serpentine is sampled from a sine at quarter steps of each swing: with only peaks and
    /// crossings, a spline crosses the middle at the chord's angle (a sine crosses π/2 times
    /// steeper), so the road would wobble between waypoints.
    static func waypoints(
        from start: CGPoint, context: RouteContext, levels: Int,
        amplitude: CGFloat, halfWaves: Int, cornersAtPeaks: Bool
    ) -> [RouteWaypoint] {
        let length = context.length(forLevels: levels)
        let center = context.width / 2
        let reach = amplitude * context.width
        // Swing away from whichever side we start on; from the middle, go trailing first.
        var direction: CGFloat = start.x > center + 0.5 ? -1 : 1
        let swing = length / CGFloat(halfWaves)

        if cornersAtPeaks {
            var result: [RouteWaypoint] = []
            result.reserveCapacity(halfWaves * 2)
            for wave in 0..<halfWaves {
                let y = start.y + CGFloat(wave) * swing
                result.append(RouteWaypoint(CGPoint(x: center + direction * reach, y: y + swing / 2), isCorner: true))
                result.append(RouteWaypoint(CGPoint(x: center, y: y + swing)))
                direction = -direction
            }
            return result
        }

        let steps = 4
        var result: [RouteWaypoint] = []
        result.reserveCapacity(halfWaves * steps)
        for wave in 0..<halfWaves {
            let y = start.y + CGFloat(wave) * swing
            for step in 1...steps {
                let t = CGFloat(step) / CGFloat(steps)
                // The first swing starts wherever the road is, and eases into the sine.
                let from = wave == 0 ? start.x : center
                let base = from + (center - from) * t
                let x = base + direction * reach * sin(.pi * t)
                result.append(RouteWaypoint(CGPoint(x: x, y: y + t * swing)))
            }
            direction = -direction
        }
        return result
    }
}
