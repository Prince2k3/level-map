import CoreGraphics

/// Splits a resolved road into chunks of levels whose size along the scroll axis is known
/// before they are drawn, so a lazy stack can lay out any part of an endless map.
///
/// Coordinates are route coordinates: `x` across the map, `y` along the scroll axis.
struct ChunkLayout: Sendable {
    struct Chunk: Sendable, Equatable {
        let index: Int
        let levels: Range<Int>
        /// The stretch of road this chunk draws, as arc length.
        let distances: ClosedRange<CGFloat>
        /// Where the chunk starts along the scroll axis.
        let origin: CGFloat
        /// The chunk's size along the scroll axis.
        let extent: CGFloat
    }

    let road: ResolvedRoute
    /// The number of levels shown: the smaller of the data's and the route's counts. `nil` when both are endless.
    let levelCount: Int?
    let chunkSize: Int

    init(road: ResolvedRoute, dataCount: Int?, chunkSize: Int) {
        precondition(chunkSize > 0, "Chunk size must be positive")
        self.road = road
        self.chunkSize = chunkSize
        switch (dataCount, road.levelCount) {
        case let (data?, route?): levelCount = min(data, route)
        case let (data?, nil): levelCount = data
        case let (nil, route?): levelCount = route
        case (nil, nil): levelCount = nil
        }
    }

    /// The number of chunks, or `nil` when the map is endless.
    var chunkCount: Int? {
        levelCount.map { ($0 + chunkSize - 1) / chunkSize }
    }

    func chunkIndex(containing level: Int) -> Int {
        max(level, 0) / chunkSize
    }

    func levels(inChunk index: Int) -> Range<Int> {
        let lower = index * chunkSize
        let upper = lower + chunkSize
        return lower..<(levelCount.map { min(upper, $0) } ?? upper)
    }

    /// Arc length where the road belonging to `level` begins: halfway from the previous level.
    /// Passing the level count gives the end of the shown road.
    func boundaryDistance(beforeLevel level: Int) -> CGFloat {
        guard level > 0, let previous = road.distance(ofLevel: level - 1) else { return 0 }
        if let next = road.distance(ofLevel: level) { return (previous + next) / 2 }
        return road.length ?? previous
    }

    /// Where a player stands who is `progress` of the way from `level` to the next. The last
    /// shown level has no next, so progress there is ignored.
    func travelledDistance(fromLevel level: Int, progress: Double) -> CGFloat? {
        let isLast = levelCount.map { level >= $0 - 1 } ?? false
        return road.distance(ofLevel: level, progress: isLast ? 0 : progress)
    }

    func chunk(_ index: Int) -> Chunk {
        let levels = levels(inChunk: index)
        let start = boundaryDistance(beforeLevel: levels.lowerBound)
        let end = boundaryDistance(beforeLevel: levels.upperBound)
        // Chunks split the scroll axis at how far the road has reached, so they never overlap even
        // when the road doubles back. Road that dips behind a chunk's start spills over its edge.
        let origin = index == 0 ? -leadingMargin : road.reach(atDistance: start)
        let isLast = chunkCount.map { index == $0 - 1 } ?? false
        let endY = road.reach(atDistance: end) + (isLast ? trailingMargin : 0)
        return Chunk(index: index, levels: levels, distances: start...max(start, end),
                     origin: origin, extent: max(endY - origin, 0))
    }

    /// Room added before the first level so its node (and an avatar on it) never hangs off the
    /// map: at least the route's edge inset.
    var leadingMargin: CGFloat {
        guard let first = road.level(0) else { return 0 }
        return max(0, road.context.edgeInset - first.position.y)
    }

    /// Room added after the last level of a finite map, like ``leadingMargin``.
    var trailingMargin: CGFloat {
        guard let count = levelCount, count > 0, let last = road.level(count - 1) else { return 0 }
        let end = road.reach(atDistance: boundaryDistance(beforeLevel: count))
        return max(0, road.context.edgeInset - (end - last.position.y))
    }

    /// A level's position relative to the start of its chunk.
    func localSample(ofLevel level: Int, in chunk: Chunk) -> RouteSample? {
        guard var sample = road.level(level) else { return nil }
        sample.position.y -= chunk.origin
        return sample
    }

    /// Where to scroll so `level` lands in the middle of a viewport `viewport` points long.
    ///
    /// `ScrollViewProxy.scrollTo(_:anchor:)` lines up the anchor point of the target with the same
    /// point of the viewport. Solving for the anchor that puts the level at the viewport's centre
    /// lets one scroll to the chunk (which the lazy stack can always find) do the whole job.
    /// The anchor may fall outside `0...1`; when the chunk is as long as the viewport any anchor
    /// gives the same offset, so the chunk's centre is used.
    func scrollAnchor(forLevel level: Int, viewport: CGFloat) -> (chunk: Int, anchor: CGFloat) {
        let chunk = chunk(chunkIndex(containing: level))
        guard let sample = localSample(ofLevel: level, in: chunk) else { return (chunk.index, 0.5) }
        let difference = viewport - chunk.extent
        guard abs(difference) > 0.5 else { return (chunk.index, 0.5) }
        return (chunk.index, (viewport / 2 - sample.position.y) / difference)
    }

    /// Where to scroll so the road at `distance` lands `target` points from the start of a viewport
    /// `viewport` points long, in the scroll view's own (unmirrored) coordinates. Scrolls to the
    /// chunk the point is in, as ``scrollAnchor(forLevel:viewport:)`` does; `level` is a hint for
    /// finding it.
    func scrollAnchor(forDistance distance: CGFloat, nearLevel level: Int, target: CGFloat,
                      viewport: CGFloat) -> (chunk: Int, anchor: CGFloat) {
        let y = road.sample(atDistance: distance).position.y
        var chunk = chunk(chunkIndex(containing: level))
        while y < chunk.origin, chunk.index > 0 {
            chunk = self.chunk(chunk.index - 1)
        }
        while y > chunk.origin + chunk.extent, chunkCount.map({ chunk.index < $0 - 1 }) ?? true {
            chunk = self.chunk(chunk.index + 1)
        }
        let difference = viewport - chunk.extent
        guard abs(difference) > 0.5 else { return (chunk.index, 0.5) }
        return (chunk.index, (target - (y - chunk.origin)) / difference)
    }

    /// How far from the start of the scroll content a route `y` is. Chunks tile the content
    /// end to end, starting at the first chunk's origin.
    func contentPosition(ofRouteY y: CGFloat) -> CGFloat {
        y + leadingMargin
    }

    /// The length of the scroll content, or `nil` for an endless map.
    var contentExtent: CGFloat? {
        guard let count = chunkCount else { return nil }
        guard count > 0 else { return 0 }
        let last = chunk(count - 1)
        return last.origin + last.extent + leadingMargin
    }

    /// The chunk's stretch of road as a polyline relative to the start of the chunk.
    /// Slices overlap their neighbours slightly so no seam shows between chunks.
    func roadPoints(in chunk: Chunk, step: CGFloat = 3, overlap: CGFloat = 1) -> [CGPoint] {
        roadPoints(from: chunk.distances.lowerBound - overlap, to: chunk.distances.upperBound + overlap,
                   step: step, origin: chunk.origin)
    }

    /// The road between two arc lengths as a polyline, with `y` measured from `origin`.
    /// Points are `step` apart along the road, so a fraction of the polyline's length is
    /// (very nearly) the same fraction of the arc length.
    func roadPoints(from start: CGFloat, to end: CGFloat, step: CGFloat = 3, origin: CGFloat) -> [CGPoint] {
        let start = max(start, 0)
        let end = max(end, start)
        var points: [CGPoint] = []
        points.reserveCapacity(Int((end - start) / step) + 2)
        var distance = start
        while distance < end {
            points.append(road.sample(atDistance: distance).position)
            distance += step
        }
        points.append(road.sample(atDistance: end).position)
        return points.map { CGPoint(x: $0.x, y: $0.y - origin) }
    }
}
