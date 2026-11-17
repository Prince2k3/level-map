import CoreGraphics

/// A point on a resolved road.
///
/// Coordinates are in points. `x` runs across the map (`0...width`), and `y` runs
/// along the scroll axis, starting at `0` where the road begins and growing in the
/// direction of travel. Views flip or rotate this space when they draw it.
public struct RouteSample: Sendable, Equatable {
    /// The position on the road.
    public var position: CGPoint
    /// The direction of travel, with length 1.
    public var tangent: CGVector
    /// The arc-length distance from the start of the road.
    public var distance: CGFloat

    public init(position: CGPoint, tangent: CGVector, distance: CGFloat) {
        self.position = position
        self.tangent = tangent
        self.distance = distance
    }

    /// The direction of travel as an angle in radians, measured from the +x axis.
    public var angle: Double {
        atan2(Double(tangent.dy), Double(tangent.dx))
    }
}

/// A point given as fractions: `x` across the map width, `y` along a segment's length.
public struct RoutePoint: Sendable, Hashable, Codable {
    public var x: CGFloat
    public var y: CGFloat

    public init(x: CGFloat, y: CGFloat) {
        self.x = x
        self.y = y
    }
}

/// Which side of the map a segment bends towards.
public enum RouteSide: Sendable, Hashable, Codable {
    case leading
    case trailing
}
