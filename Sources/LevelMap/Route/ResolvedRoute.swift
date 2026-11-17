import CoreGraphics

/// The concrete geometry of a ``LevelRoute`` for one map width.
///
/// All lookups are O(log n) in the number of segments and use constant memory,
/// however many times an endless route has repeated. Coordinates follow
/// ``RouteSample``: `x` across the map, `y` along the scroll axis from the start of the road.
public struct ResolvedRoute: Sendable {
    /// One segment's stretch of road.
    struct Piece: Sendable {
        let curves: [CubicBezier]
        let table: ArcLengthTable
        let firstLevel: Int
        let levelCount: Int
        let startDistance: CGFloat
        /// The furthest the road has reached along the scroll axis by the end of each curve.
        let curveReach: [CGFloat]
        /// The furthest the road reached along the scroll axis before this piece.
        let reachBefore: CGFloat
        /// Whether the first and last levels sit on the piece's ends (see ``EndPlacedLevels``).
        let levelsAtEnds: Bool

        var length: CGFloat { table.totalLength }

        /// The furthest the road has reached along the scroll axis by `distance` into this piece.
        /// Only curve ends are counted, which is exact for roads that keep moving forward.
        func reach(atLocalDistance distance: CGFloat) -> CGFloat {
            guard !curves.isEmpty else { return reachBefore }
            let (curve, t) = table.location(atDistance: distance)
            let before = curve > 0 ? curveReach[curve - 1] : max(reachBefore, curves[0].p0.y)
            return max(before, curves[curve].point(at: t).y)
        }

        /// The furthest the road reaches by the end of this piece.
        var reachAfter: CGFloat { curveReach.last ?? reachBefore }

        func sample(atLocalDistance distance: CGFloat) -> (CGPoint, CGVector) {
            guard !curves.isEmpty else { return (.zero, CGVector(dx: 0, dy: 1)) }
            let (curve, t) = table.location(atDistance: distance)
            return (curves[curve].point(at: t), curves[curve].tangent(at: t))
        }

        /// Arc-length offset of a level inside this piece. Levels sit in the middle of equal slices,
        /// or are spread from one end to the other when ``levelsAtEnds`` is set.
        func localDistance(ofLevel index: Int) -> CGFloat {
            if levelsAtEnds, levelCount > 1 {
                return CGFloat(index - firstLevel) * length / CGFloat(levelCount - 1)
            }
            return (CGFloat(index - firstLevel) + 0.5) * length / CGFloat(levelCount)
        }
    }

    /// The repeating tail of an endless route.
    struct Cycle: Sendable {
        let pieces: [Piece]
        let levelCount: Int
        let length: CGFloat
        /// How far one repetition moves along the scroll axis.
        let advance: CGFloat
        /// The furthest one repetition reaches along the scroll axis, from its start.
        var reach: CGFloat { pieces.last?.reachAfter ?? 0 }
    }

    public let context: RouteContext
    let startPoint: CGPoint
    let prefix: [Piece]
    let prefixLevelCount: Int
    let prefixLength: CGFloat
    /// Where the finite part ends along the scroll axis (and the cycle begins).
    let prefixEndY: CGFloat
    let cycle: Cycle?

    // MARK: Public API

    /// The number of levels, or `nil` for an endless route.
    public var levelCount: Int? { cycle == nil ? prefixLevelCount : nil }

    /// The total road length, or `nil` for an endless route.
    public var length: CGFloat? { cycle == nil ? prefixLength : nil }

    /// Whether the route goes on forever.
    public var isEndless: Bool { cycle != nil }

    /// The position of level `index` (0-based), or `nil` if the route has no such level.
    public func level(_ index: Int) -> RouteSample? {
        guard index >= 0 else { return nil }
        if index < prefixLevelCount {
            let piece = prefix[Self.lastIndex(in: prefix, notAfter: index, key: \.firstLevel)]
            return sample(piece: piece, localDistance: piece.localDistance(ofLevel: index),
                          distanceOffset: 0, yOffset: 0)
        }
        guard let cycle else { return nil }
        let (repetition, local) = (index - prefixLevelCount).quotientAndRemainder(dividingBy: cycle.levelCount)
        let piece = cycle.pieces[Self.lastIndex(in: cycle.pieces, notAfter: local, key: \.firstLevel)]
        return sample(piece: piece, localDistance: piece.localDistance(ofLevel: local),
                      distanceOffset: prefixLength + CGFloat(repetition) * cycle.length,
                      yOffset: prefixEndY + CGFloat(repetition) * cycle.advance)
    }

    /// How far along the road level `index` sits, or `nil` if the route has no such level.
    public func distance(ofLevel index: Int) -> CGFloat? {
        level(index)?.distance
    }

    /// How far along the road a player stands who has left level `index` and covered `progress`
    /// of the way to the next one (0 at the level, 1 at the next).
    ///
    /// Progress is clamped to 0...1, and past the last level of a finite route the player stays
    /// on it. Returns `nil` if the route has no level `index`.
    public func distance(ofLevel index: Int, progress: Double) -> CGFloat? {
        guard let start = distance(ofLevel: index) else { return nil }
        let fraction = progress.isFinite ? min(max(progress, 0), 1) : 0
        guard fraction > 0, let end = distance(ofLevel: index + 1) else { return start }
        return start + (end - start) * CGFloat(fraction)
    }

    /// The point `distance` along the road. Distances past the end of a finite route are clamped.
    public func sample(atDistance distance: CGFloat) -> RouteSample {
        let distance = max(distance, 0)
        if let cycle, distance >= prefixLength, cycle.length > 0 {
            let local = distance - prefixLength
            let repetition = (local / cycle.length).rounded(.down)
            let remainder = local - repetition * cycle.length
            let piece = cycle.pieces[Self.lastIndex(in: cycle.pieces, notAfter: remainder, key: \.startDistance)]
            return sample(piece: piece, localDistance: remainder - piece.startDistance,
                          distanceOffset: prefixLength + repetition * cycle.length,
                          yOffset: prefixEndY + repetition * cycle.advance)
        }
        guard !prefix.isEmpty else {
            return RouteSample(position: startPoint, tangent: CGVector(dx: 0, dy: 1), distance: 0)
        }
        let clamped = min(distance, prefixLength)
        let piece = prefix[Self.lastIndex(in: prefix, notAfter: clamped, key: \.startDistance)]
        return sample(piece: piece, localDistance: clamped - piece.startDistance, distanceOffset: 0, yOffset: 0)
    }

    /// The furthest the road has reached along the scroll axis by `distance`.
    ///
    /// For a road that keeps moving forward this is just the `y` of ``sample(atDistance:)``.
    /// A road that doubles back (imported drawings often do) can dip below this, and the map
    /// uses it to split the road into chunks that never go backwards.
    public func reach(atDistance distance: CGFloat) -> CGFloat {
        let distance = max(distance, 0)
        let prefixReach = prefix.last?.reachAfter ?? startPoint.y
        if let cycle, distance >= prefixLength, cycle.length > 0 {
            let local = distance - prefixLength
            let repetition = (local / cycle.length).rounded(.down)
            let remainder = local - repetition * cycle.length
            let piece = cycle.pieces[Self.lastIndex(in: cycle.pieces, notAfter: remainder, key: \.startDistance)]
            var result = max(prefixReach, prefixEndY + repetition * cycle.advance
                             + piece.reach(atLocalDistance: remainder - piece.startDistance))
            if repetition >= 1 {
                result = max(result, prefixEndY + (repetition - 1) * cycle.advance + cycle.reach)
            }
            return result
        }
        guard !prefix.isEmpty else { return startPoint.y }
        let clamped = min(distance, prefixLength)
        let piece = prefix[Self.lastIndex(in: prefix, notAfter: clamped, key: \.startDistance)]
        return piece.reach(atLocalDistance: clamped - piece.startDistance)
    }

    // MARK: Building

    /// The waypoints one segment produced and how its levels are placed.
    struct LevelRange {
        var range: Range<Int>
        let levels: Int
        let atEnds: Bool
    }

    init(route: LevelRoute, context: RouteContext) {
        self.context = context
        let startPoint = CGPoint(x: route.start.x * context.width, y: 0)

        // 1. Waypoints for the finite part.
        var waypoints = [RouteWaypoint(startPoint)]
        var ranges: [LevelRange] = []
        for segment in route.segments {
            let from = waypoints.count - 1
            waypoints += segment.waypoints(from: waypoints[from].point, in: context)
            ranges.append(LevelRange(range: from..<(waypoints.count - 1), levels: segment.levelCount,
                                     atEnds: segment is EndPlacedLevels))
        }
        let prefixEnd = waypoints[waypoints.count - 1].point
        self.prefixEndY = prefixEnd.y

        // 2. Waypoints for one repetition, in local coordinates starting at y = 0.
        var cycleWaypoints: [RouteWaypoint] = []
        var cycleRanges: [LevelRange] = []
        var joinDirection: CGVector?
        var advance: CGFloat = 0
        if let body = route.repeatingSegments {
            let origin = CGPoint(x: prefixEnd.x, y: 0)
            cycleWaypoints = [RouteWaypoint(origin)]
            for segment in body {
                let from = cycleWaypoints.count - 1
                cycleWaypoints += segment.waypoints(from: cycleWaypoints[from].point, in: context)
                cycleRanges.append(LevelRange(range: from..<(cycleWaypoints.count - 1), levels: segment.levelCount,
                                              atEnds: segment is EndPlacedLevels))
            }
            // Close the loop so every repetition starts where the last one ended.
            let end = cycleWaypoints[cycleWaypoints.count - 1].point
            let drift = abs(end.x - origin.x)
            if drift > 0.5 {
                cycleWaypoints.append(RouteWaypoint(CGPoint(x: origin.x, y: end.y + max(context.spacing, drift * 0.8))))
                let last = cycleRanges.count - 1
                cycleRanges[last].range = cycleRanges[last].range.lowerBound..<(cycleWaypoints.count - 1)
            } else {
                cycleWaypoints[cycleWaypoints.count - 1].point.x = origin.x
            }
            cycleWaypoints[0].isCorner = cycleWaypoints[cycleWaypoints.count - 1].isCorner
            advance = cycleWaypoints[cycleWaypoints.count - 1].point.y
            precondition(advance > 0, "Repeat must move forward along the scroll axis")

            // Tangent where repetitions join, using the neighbours on both sides of the seam.
            let count = cycleWaypoints.count
            let previous = cycleWaypoints[count - 2].point.offsetBy(dy: -advance)
            joinDirection = (cycleWaypoints[1].point - previous).normalized ?? CGVector(dx: 0, dy: 1)
        }

        // Keep clear of the sides: scale the road in across the map if any waypoint strays
        // closer to an edge than the inset. Routes that already keep clear are untouched.
        let squeeze = Self.edgeSqueeze(for: waypoints + cycleWaypoints, context: context)
        for index in waypoints.indices { waypoints[index].point.x = squeeze(waypoints[index].point.x) }
        for index in cycleWaypoints.indices { cycleWaypoints[index].point.x = squeeze(cycleWaypoints[index].point.x) }
        self.startPoint = CGPoint(x: squeeze(startPoint.x), y: startPoint.y)

        // 3. Smooth curves through the waypoints.
        var prefixDirections = Self.directions(for: waypoints)
        var prefixArms = Self.armLengths(for: waypoints)
        if let joinDirection {
            prefixDirections[prefixDirections.count - 1] = joinDirection
            prefixArms[prefixArms.count - 1] = nil
        }
        let (prefix, prefixLevels, prefixLength) = Self.pieces(
            waypoints: waypoints, directions: prefixDirections, arms: prefixArms, ranges: ranges)
        self.prefix = prefix
        self.prefixLevelCount = prefixLevels
        self.prefixLength = prefixLength

        if let joinDirection {
            var directions = Self.directions(for: cycleWaypoints)
            directions[0] = joinDirection
            directions[directions.count - 1] = joinDirection
            var arms = Self.armLengths(for: cycleWaypoints)
            arms[0] = nil
            arms[arms.count - 1] = nil
            let (pieces, levels, length) = Self.pieces(
                waypoints: cycleWaypoints, directions: directions, arms: arms, ranges: cycleRanges)
            self.cycle = Cycle(pieces: pieces, levelCount: levels, length: length, advance: advance)
        } else {
            self.cycle = nil
        }
    }

    /// Maps the waypoints' cross-axis span into `inset...width - inset`, stretching only as far as
    /// needed: a span already inside those bounds maps to itself.
    private static func edgeSqueeze(for waypoints: [RouteWaypoint], context: RouteContext) -> (CGFloat) -> CGFloat {
        let xs = waypoints.map(\.point.x)
        guard let minX = xs.min(), let maxX = xs.max() else { return { $0 } }
        let low = context.edgeInset, high = context.width - context.edgeInset
        let from = min(minX, low), to = max(maxX, high)
        guard from < low || to > high, to > from else { return { $0 } }
        let scale = (high - low) / (to - from)
        return { low + ($0 - from) * scale }
    }

    /// Catmull-Rom style direction at each waypoint: along the line joining its neighbours.
    private static func directions(for waypoints: [RouteWaypoint]) -> [CGVector] {
        let points = waypoints.map(\.point)
        return points.indices.map { index in
            let previous = index > 0 ? points[index - 1] : nil
            let next = index < points.count - 1 ? points[index + 1] : nil
            let current = points[index]
            switch (previous, next) {
            case let (previous?, next?):
                return (next - previous).normalized
                    ?? (next - current).normalized
                    ?? CGVector(dx: 0, dy: 1)
            case let (nil, next?):
                return (next - current).normalized ?? CGVector(dx: 0, dy: 1)
            case let (previous?, nil):
                return (current - previous).normalized ?? CGVector(dx: 0, dy: 1)
            case (nil, nil):
                return CGVector(dx: 0, dy: 1)
            }
        }
    }

    /// Catmull-Rom control-arm length at each interior waypoint: a sixth of the distance between
    /// its neighbours. `nil` at the ends, where the arm falls back to a third of the chord.
    private static func armLengths(for waypoints: [RouteWaypoint]) -> [CGFloat?] {
        waypoints.indices.map { index in
            guard index > 0, index < waypoints.count - 1 else { return nil }
            return (waypoints[index + 1].point - waypoints[index - 1].point).length / 6
        }
    }

    private static func pieces(
        waypoints: [RouteWaypoint], directions: [CGVector], arms: [CGFloat?],
        ranges: [LevelRange]
    ) -> ([Piece], levels: Int, length: CGFloat) {
        var pieces: [Piece] = []
        var levels = 0
        var distance: CGFloat = 0
        var reach = waypoints.first?.point.y ?? 0
        for (range, levelCount, atEnds) in ranges.map({ ($0.range, $0.levels, $0.atEnds) }) {
            let curves: [CubicBezier] = range.compactMap { index in
                let a = waypoints[index]
                let b = waypoints[index + 1]
                let chord = b.point - a.point
                let length = chord.length
                guard length > 1e-6 else { return nil }
                // Catmull-Rom arms (a sixth of the neighbour span) keep the curvature even, so the
                // road does not bulge and wobble between waypoints. Capping them at half the chord
                // keeps each span close to its chord (no loops); the shared direction at each
                // waypoint keeps joins smooth.
                let armA = min(arms[index] ?? length / 3, length / 2)
                let armB = min(arms[index + 1] ?? length / 3, length / 2)
                let c1 = a.isCorner ? a.point + chord / 3 : a.point + directions[index] * armA
                let c2 = b.isCorner ? b.point - chord / 3 : b.point - directions[index + 1] * armB
                return CubicBezier(p0: a.point, c1: c1, c2: c2, p3: b.point)
            }
            let reachBefore = reach
            let curveReach = curves.map { curve in
                reach = max(reach, curve.p0.y, curve.p3.y)
                return reach
            }
            let piece = Piece(curves: curves, table: ArcLengthTable(curves: curves),
                              firstLevel: levels, levelCount: levelCount, startDistance: distance,
                              curveReach: curveReach, reachBefore: reachBefore, levelsAtEnds: atEnds)
            pieces.append(piece)
            levels += levelCount
            distance += piece.length
        }
        return (pieces, levels, distance)
    }

    // MARK: Helpers

    private func sample(piece: Piece, localDistance: CGFloat, distanceOffset: CGFloat, yOffset: CGFloat) -> RouteSample {
        let (point, tangent) = piece.sample(atLocalDistance: localDistance)
        return RouteSample(position: point.offsetBy(dy: yOffset), tangent: tangent,
                           distance: distanceOffset + piece.startDistance + localDistance)
    }

    /// Index of the last element whose `key` is `<= value`. `elements` must be sorted by `key`.
    private static func lastIndex<Element, Key: Comparable>(
        in elements: [Element], notAfter value: Key, key: KeyPath<Element, Key>
    ) -> Int {
        var low = 0
        var high = elements.count
        while low < high {
            let mid = (low + high) / 2
            if elements[mid][keyPath: key] <= value { low = mid + 1 } else { high = mid }
        }
        return max(low - 1, 0)
    }
}
