import CoreGraphics

/// A road through traced points, for example from a drawing or an older level map.
///
/// Unlike the other segments, a polyline keeps the proportions it was drawn with: its length
/// along the scroll axis grows with the map's width, and ``SwiftUICore/View/levelMapSpacing(_:)``
/// does not apply to it. Levels are still spread evenly along it by arc length.
///
/// The road may double back on itself (run sideways, or briefly backwards along the scroll axis).
///
/// The first level sits on the first point and the last level on the last point, so with one
/// level per point and evenly spaced points, every level lands on a point.
public struct Polyline: RouteSegment, EndPlacedLevels {
    public var levelCount: Int
    /// `x` is a fraction of the map width. `y` is the distance along the scroll axis from where
    /// the segment starts, in map widths (so `y == 2` is twice as far as the map is wide).
    public var points: [RoutePoint]
    /// When `true` the road curves smoothly through the points; when `false` it runs straight
    /// between them with sharp turns.
    public var smooth: Bool

    public init(levels: Int, points: [RoutePoint], smooth: Bool = true) {
        precondition(levels > 0, "Polyline needs at least one level")
        precondition(!points.isEmpty, "Polyline needs at least one point")
        self.levelCount = levels
        self.points = points
        self.smooth = smooth
    }

    /// A polyline through points traced on a drawing.
    ///
    /// - Parameters:
    ///   - levels: How many levels to place along the road. Defaults to one per point.
    ///   - points: Points in the drawing's coordinates: `x` across the map, `y` in the direction of travel.
    ///   - width: The drawing's size across the map, which becomes the map's width.
    ///   - smooth: Whether the road curves through the points or turns sharply at them.
    public init(levels: Int? = nil, tracing points: [CGPoint], width: CGFloat, smooth: Bool = true) {
        precondition(width > 0, "Width must be positive")
        precondition(!points.isEmpty, "Polyline needs at least one point")
        let first = points[0]
        self.init(levels: levels ?? points.count,
                  points: points.map { RoutePoint(x: $0.x / width, y: ($0.y - first.y) / width) },
                  smooth: smooth)
    }

    public func waypoints(from start: CGPoint, in context: RouteContext) -> [RouteWaypoint] {
        points.map {
            RouteWaypoint(CGPoint(x: $0.x * context.width, y: start.y + $0.y * context.width), isCorner: !smooth)
        }
    }
}

extension LevelRoute {
    /// A route through raw points, for example level positions copied from another tool.
    ///
    /// ```swift
    /// // Positions from a 1080-point-wide design, travelling down the page.
    /// let route = LevelRoute.points([CGPoint(x: 540, y: 80), CGPoint(x: 900, y: 300), ...], width: 1080)
    /// ```
    ///
    /// - Parameters:
    ///   - points: `x` across the map and `y` in the direction of travel, in any units.
    ///   - width: The size across the map in the same units; it becomes the map's width.
    ///   - levels: How many levels to place along the road. Defaults to one per point.
    ///   - smooth: Whether the road curves through the points or turns sharply at them.
    public static func points(_ points: [CGPoint], width: CGFloat, levels: Int? = nil, smooth: Bool = true) -> LevelRoute {
        precondition(!points.isEmpty, "A points route needs at least one point")
        return LevelRoute(components: [
            RouteComponent(kind: .start(Start(x: points[0].x / width))),
            RouteComponent(kind: .segment(Polyline(levels: levels, tracing: points, width: width, smooth: smooth))),
        ])
    }
}

/// A segment whose first and last levels sit on its ends instead of half a slot in.
protocol EndPlacedLevels {}
