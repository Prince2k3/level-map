import SwiftUI

/// Where a ``SwiftUICore/View/levelMapLayer(_:content:)`` is drawn among the map's own layers.
public enum LevelMapLayerPlacement: Sendable, Hashable {
    /// Over the ground, under the road. For terrain, or a wide band under part of the road.
    case belowRoad
    /// Over the road, under the level nodes.
    case aboveRoad
    /// Over the level nodes, under the avatar. Drawn above the scenery the theme scatters.
    case aboveNodes
}

/// The map's shape, handed to a ``SwiftUICore/View/levelMapLayer(_:content:)`` so it can draw in
/// step with the road.
///
/// A layer covers the stretch of map that is laid out at the moment: ``levels`` are the levels in
/// it, and ``size`` is its size. Points are in the layer's own coordinates, with the origin at its
/// top-leading corner, with positive x towards trailing, the right way up, even on maps that run bottom-up.
///
/// Positions are given in levels, and may fall between them: `3.5` is halfway along the road from
/// level 3 to level 4, and `-0.5` is before the first level.
public struct LevelMapGeometry: Sendable {
    /// The size of the layer.
    public let size: CGSize
    public let axis: Axis
    /// The layout direction used by the map and its logical drawing coordinates.
    public let layoutDirection: LayoutDirection
    /// How many levels the map shows, or `nil` for an endless map.
    public let levelCount: Int?
    /// The levels inside the layer. Draw what belongs to these; the layer is rebuilt as the map scrolls.
    public let levels: Range<Int>
    /// How far ``SwiftUICore/View/levelMapFollowsAvatar(_:zoom:anchor:scalesMarkers:)`` has magnified
    /// the map, 1 when it isn't following. Shrink labels and markers by this much to keep their size.
    public let zoom: CGFloat

    let layout: ChunkLayout
    /// The route `y` (along the road's axis) at the layer's leading edge, before mirroring.
    let originAlong: CGFloat
    let mirrored: Bool
    let road: RoadDistanceIndex

    init(size: CGSize, axis: Axis, layout: ChunkLayout, levels: Range<Int>, originAlong: CGFloat,
         mirrored: Bool, zoom: CGFloat, layoutDirection: LayoutDirection = .leftToRight) {
        self.size = size
        self.axis = axis
        self.layoutDirection = layoutDirection
        self.layout = layout
        levelCount = layout.levelCount
        self.levels = levels
        self.originAlong = originAlong
        self.mirrored = mirrored
        self.zoom = zoom
        // The road through the layer and a little beyond, for distanceToRoad(from:).
        let start = layout.boundaryDistance(beforeLevel: max(levels.lowerBound - 1, 0))
        let end = layout.boundaryDistance(beforeLevel: levels.upperBound + 1)
        road = RoadDistanceIndex {
            layout.roadPoints(from: start, to: end, step: 6, origin: 0)
                .map { Self.location(of: $0, axis: axis, size: size, originAlong: originAlong, mirrored: mirrored) }
        }
    }

    /// Where the road is at `level`, or `nil` for a position past the end of an empty map.
    public func point(atLevel level: Double) -> CGPoint? {
        sample(atLevel: level).map { location(of: $0.position) }
    }

    /// The direction towards higher levels in the layer's logical drawing coordinates.
    /// SwiftUI mirrors the drawing horizontally in right-to-left layouts.
    public func heading(atLevel level: Double) -> Angle? {
        sample(atLevel: level).map { LevelPlacement.screenAngle(of: $0.tangent, axis: axis, mirrored: mirrored) }
    }

    /// The road from one position to another, to stroke over or under the map's own road.
    ///
    /// ```swift
    /// map.roadPath(from: 4, to: 4.6)
    ///     .stroke(.green.opacity(0.3), style: StrokeStyle(lineWidth: 18, lineCap: .round))
    /// ```
    public func roadPath(from start: Double, to end: Double) -> Path {
        guard let from = distance(atLevel: min(start, end)), let to = distance(atLevel: max(start, end)) else {
            return Path()
        }
        let points = layout.roadPoints(from: from, to: to, step: 3, origin: 0).map(location(of:))
        return Path { $0.addLines(points) }
    }

    /// How far `point` is from the nearest part of the road inside the layer. Use it to keep
    /// scenery clear of the road.
    public func distanceToRoad(from point: CGPoint) -> CGFloat {
        road.distance(from: point)
    }

    /// Where `level` sits across the map, as it is passed to a ``LevelMap`` node.
    public func placement(ofLevel level: Double) -> LevelPlacement? {
        sample(atLevel: level).map(placement(of:))
    }

    // MARK: Conversion

    func placement(of sample: RouteSample) -> LevelPlacement {
        LevelPlacement(sample: sample, crossSize: layout.road.context.width, axis: axis, mirrored: mirrored,
                       layoutDirection: layoutDirection)
    }

    private func sample(atLevel level: Double) -> RouteSample? {
        distance(atLevel: level).map(layout.road.sample(atDistance:))
    }

    /// The distance along the road of a position given in levels.
    private func distance(atLevel level: Double) -> CGFloat? {
        guard level.isFinite, layout.levelCount != 0, let first = layout.road.distance(ofLevel: 0) else { return nil }
        let whole = level.rounded(.down)
        let index = Int(min(whole, Double(Int.max / 2)))
        let fraction = CGFloat(level - whole)
        if index < 0 {
            let next = layout.road.distance(ofLevel: 1) ?? first + 1
            return max(first + (next - first) * CGFloat(level), 0)
        }
        // Past the last level, the road runs on to its end.
        if let count = layout.levelCount, index >= count - 1 {
            let last = layout.road.distance(ofLevel: count - 1) ?? first
            let end = layout.boundaryDistance(beforeLevel: count)
            return min(last + (end - last) * CGFloat(level - Double(count - 1)) * 2, end)
        }
        guard let start = layout.road.distance(ofLevel: index),
              let end = layout.road.distance(ofLevel: index + 1) else { return nil }
        return start + (end - start) * fraction
    }

    private func location(of point: CGPoint) -> CGPoint {
        Self.location(of: point, axis: axis, size: size, originAlong: originAlong, mirrored: mirrored)
    }

    private static func location(of point: CGPoint, axis: Axis, size: CGSize, originAlong: CGFloat,
                                 mirrored: Bool) -> CGPoint {
        let extent = axis == .vertical ? size.height : size.width
        var along = point.y - originAlong
        if mirrored { along = extent - along }
        return axis == .vertical ? CGPoint(x: point.x, y: along) : CGPoint(x: along, y: point.x)
    }
}

/// Where a level sits on the map, passed to the node closure of
/// ``LevelMap/init(_:route:axis:startsAtEnd:current:placedNode:)``.
public struct LevelPlacement: Sendable, Hashable {
    /// Which half of the map a level is in.
    public enum Side: Sendable, Hashable {
        /// The leading half: left in left-to-right layouts, right in right-to-left layouts.
        /// For horizontal maps, the top half of the cross axis (unchanged by language direction).
        case leading
        /// The trailing half: right in left-to-right layouts, left in right-to-left layouts.
        /// For horizontal maps, the bottom half of the cross axis (unchanged by language direction).
        case trailing
    }

    /// How far across the map the level is in logical drawing coordinates: 0 at the leading
    /// (or top) edge, 1 at the trailing (or bottom) edge. SwiftUI mirrors x when drawing RTL.
    /// Use `physicalCrossFraction` when working with physical screen coordinates.
    public let crossFraction: CGFloat
    /// The direction towards the next level in SwiftUI's logical drawing coordinates.
    /// Use with `rotationEffect`; SwiftUI mirrors that drawing horizontally in RTL.
    public let heading: Angle

    /// The scroll axis. On a horizontal map the cross axis runs from top to bottom.
    public let axis: Axis
    /// The direction of the map's logical horizontal coordinates.
    public let layoutDirection: LayoutDirection

    /// Creates placement in logical map coordinates. Existing calls default to a vertical LTR map.
    public init(crossFraction: CGFloat, heading: Angle, axis: Axis = .vertical,
                layoutDirection: LayoutDirection = .leftToRight) {
        self.crossFraction = crossFraction
        self.heading = heading
        self.axis = axis
        self.layoutDirection = layoutDirection
    }

    /// Creates placement from physical screen coordinates: left-to-right for a vertical map,
    /// top-to-bottom for a horizontal map. The heading is still in logical drawing coordinates.
    public init(physicalCrossFraction: CGFloat, heading: Angle, axis: Axis = .vertical,
                layoutDirection: LayoutDirection = .leftToRight) {
        let logical = axis == .vertical && layoutDirection == .rightToLeft
            ? 1 - physicalCrossFraction : physicalCrossFraction
        self.init(crossFraction: logical, heading: heading, axis: axis, layoutDirection: layoutDirection)
    }

    /// The physical fraction across the map: 0 at left (or top), 1 at right (or bottom).
    public var physicalCrossFraction: CGFloat {
        axis == .vertical && layoutDirection == .rightToLeft ? 1 - crossFraction : crossFraction
    }

    /// A physical screen edge, independent of the language's reading direction.
    public enum PhysicalSide: Sendable, Hashable {
        case left, right, top, bottom
    }

    /// The physical half containing this placement. The centre belongs to the logical leading half.
    public var physicalSide: PhysicalSide {
        if axis == .horizontal { return side == .leading ? .top : .bottom }
        let leadingIsLeft = layoutDirection == .leftToRight
        return (side == .leading) == leadingIsLeft ? .left : .right
    }

    /// The half of the map the level is in. A label put on the other side, towards the middle,
    /// has the most room and stays clear of the edge.
    public var side: Side { crossFraction > 0.5 ? .trailing : .leading }

    init(sample: RouteSample, crossSize: CGFloat, axis: Axis, mirrored: Bool,
         layoutDirection: LayoutDirection = .leftToRight) {
        self.init(crossFraction: crossSize > 0 ? sample.position.x / crossSize : 0.5,
                  heading: Self.screenAngle(of: sample.tangent, axis: axis, mirrored: mirrored),
                  axis: axis, layoutDirection: layoutDirection)
    }

    /// A route tangent (`dy` along the scroll axis) as an angle on screen.
    static func screenAngle(of tangent: CGVector, axis: Axis, mirrored: Bool) -> Angle {
        let along = mirrored ? -tangent.dy : tangent.dy
        let vector = axis == .vertical ? CGVector(dx: tangent.dx, dy: along) : CGVector(dx: along, dy: tangent.dx)
        return Angle(radians: atan2(Double(vector.dy), Double(vector.dx)))
    }
}

/// A view drawn in step with the map, set with ``SwiftUICore/View/levelMapLayer(_:content:)``.
///
/// `AnyView` is not `Sendable`, but environment values are only read on the main actor.
struct LevelMapLayer: @unchecked Sendable {
    let placement: LevelMapLayerPlacement
    let make: @MainActor (LevelMapGeometry) -> AnyView
}

extension View {
    /// Draws your own view in step with the map: terrain, a highlight along part of the road, or
    /// markers placed between levels. Call it more than once to add more layers; layers with the
    /// same placement are drawn in the order they were added.
    ///
    /// ```swift
    /// LevelMap(stops, route: .serpentine()) { ... }
    ///     .levelMapLayer(.belowRoad) { map in
    ///         map.roadPath(from: leg.start, to: leg.end)
    ///             .stroke(.green.opacity(0.25), style: StrokeStyle(lineWidth: 18, lineCap: .round))
    ///     }
    ///     .levelMapLayer(.aboveNodes) { map in
    ///         if let point = map.point(atLevel: leg.end) {
    ///             GoalPennant().position(point)
    ///         }
    ///     }
    /// ```
    /// The layer covers only the part of the map that is laid out, so it stays cheap on long and
    /// endless maps; ``LevelMapGeometry/levels`` says which levels that is. Layers don't take
    /// touches, and VoiceOver skips them.
    public func levelMapLayer(_ placement: LevelMapLayerPlacement = .belowRoad,
                              @ViewBuilder content: @escaping @MainActor (_ map: LevelMapGeometry) -> some View) -> some View {
        transformEnvironment(\.levelMapLayers) { layers in
            // Outer modifiers run first, so inserting at the front keeps the order they were written in.
            layers.insert(LevelMapLayer(placement: placement) { AnyView(content($0)) }, at: 0)
        }
    }
}
