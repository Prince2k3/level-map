import CoreGraphics
import Foundation

/// A route as plain data, for saving in a file or sending from a server. The map editor exports
/// this format too.
///
/// ```swift
/// let json = try JSONEncoder().encode(RouteJSON(route))
/// let route = try JSONDecoder().decode(RouteJSON.self, from: json).route()
/// ```
public struct RouteJSON: Codable, Sendable, Equatable {
    /// The format version. Only `1` exists so far.
    public var version: Int
    /// Where the road begins across the map, as a fraction of the width.
    public var start: CGFloat
    public var segments: [Segment]
    /// Segments repeated forever after `segments`, or `nil` for a route with an end.
    public var repeating: [Segment]?

    /// One segment. Each case matches the segment type of the same name.
    public enum Segment: Codable, Sendable, Equatable {
        case straight(levels: Int, toX: CGFloat?)
        case serpentine(levels: Int, amplitude: CGFloat, halfWaves: Int)
        case zigzag(levels: Int, amplitude: CGFloat, halfWaves: Int)
        case spline(levels: Int, points: [RoutePoint])
        case detour(side: RouteSide, levels: Int, inset: CGFloat)
        case polyline(levels: Int, points: [RoutePoint], smooth: Bool)
    }

    public enum Error: Swift.Error, Equatable {
        /// The route uses a segment type of your own, which has no JSON form.
        case customSegment(String)
        case unsupportedVersion(Int)
        /// A segment has no levels, or a spline or polyline has no points.
        case emptySegment
        /// The repeating part has no levels, so the route could never end or advance.
        case emptyRepeat
    }

    public init(start: CGFloat = 0.5, segments: [Segment], repeating: [Segment]? = nil) {
        self.version = 1
        self.start = start
        self.segments = segments
        self.repeating = repeating
    }

    /// The JSON form of `route`. Throws ``Error/customSegment(_:)`` if the route uses a segment
    /// type this format does not know.
    public init(_ route: LevelRoute) throws {
        self.init(start: route.start.x,
                  segments: try route.segments.map(Segment.init),
                  repeating: try route.repeatingSegments?.map(Segment.init))
    }

    /// Builds the route, checking that every segment is valid.
    public func route() throws -> LevelRoute {
        guard version == 1 else { throw Error.unsupportedVersion(version) }
        var components = [RouteComponent(kind: .start(Start(x: start)))]
        components += try segments.map { RouteComponent(kind: .segment(try $0.segment())) }
        if let repeating {
            guard repeating.contains(where: { $0.levels > 0 }) else { throw Error.emptyRepeat }
            let body = try repeating.map { RouteComponent(kind: .segment(try $0.segment())) }
            components.append(RouteComponent(kind: .repeating(Repeat(body: body))))
        }
        return LevelRoute(components: components)
    }
}

extension RouteJSON.Segment {
    package var levels: Int {
        switch self {
        case let .straight(levels, _), let .serpentine(levels, _, _), let .zigzag(levels, _, _),
             let .spline(levels, _), let .detour(_, levels, _), let .polyline(levels, _, _):
            levels
        }
    }

    init(_ segment: any RouteSegment) throws {
        switch segment {
        case let s as Straight: self = .straight(levels: s.levelCount, toX: s.endX)
        case let s as Serpentine: self = .serpentine(levels: s.levelCount, amplitude: s.amplitude, halfWaves: s.halfWaves)
        case let s as Zigzag: self = .zigzag(levels: s.levelCount, amplitude: s.amplitude, halfWaves: s.halfWaves)
        case let s as Spline: self = .spline(levels: s.levelCount, points: s.points)
        case let s as Detour: self = .detour(side: s.side, levels: s.levelCount, inset: s.inset)
        case let s as Polyline: self = .polyline(levels: s.levelCount, points: s.points, smooth: s.smooth)
        default: throw RouteJSON.Error.customSegment(String(describing: type(of: segment)))
        }
    }

    package func segment() throws -> any RouteSegment {
        guard levels > 0 else { throw RouteJSON.Error.emptySegment }
        switch self {
        case let .straight(levels, toX):
            return Straight(levels: levels, toX: toX)
        case let .serpentine(levels, amplitude, halfWaves):
            return Serpentine(levels: levels, amplitude: amplitude, halfWaves: max(halfWaves, 1))
        case let .zigzag(levels, amplitude, halfWaves):
            return Zigzag(levels: levels, amplitude: amplitude, halfWaves: max(halfWaves, 1))
        case let .spline(levels, points):
            guard !points.isEmpty else { throw RouteJSON.Error.emptySegment }
            return Spline(levels: levels, through: points)
        case let .detour(side, levels, inset):
            return Detour(around: side, levels: levels, inset: inset)
        case let .polyline(levels, points, smooth):
            guard !points.isEmpty else { throw RouteJSON.Error.emptySegment }
            return Polyline(levels: levels, points: points, smooth: smooth)
        }
    }
}
