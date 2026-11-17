import CoreGraphics

/// Everything a chunk draws apart from its level nodes, worked out from the layout and theme plan.
/// Coordinates are route coordinates relative to the chunk's origin.
struct ChunkScene: Sendable {
    /// A stretch of road drawn in one chapter's style.
    struct RoadPiece: Sendable {
        let chapter: Int
        let distances: ClosedRange<CGFloat>
        let points: [CGPoint]

        /// How much of this piece (0...1, by length) is completed when the completed road ends at `distance`.
        func completedFraction(upTo distance: CGFloat) -> CGFloat {
            let length = distances.upperBound - distances.lowerBound
            guard length > 0 else { return distance >= distances.upperBound ? 1 : 0 }
            return min(max((distance - distances.lowerBound) / length, 0), 1)
        }
    }

    /// One chapter's ground. Every layer after the first fades in over the one before.
    struct GroundLayer: Sendable, Equatable {
        let chapter: Int
        /// Where the fade begins and ends along the scroll axis; `nil` for the bottom layer.
        let fade: ClosedRange<CGFloat>?
    }

    /// One chapter's decorations.
    struct DecorationGroup: Sendable {
        let chapter: Int
        let decorations: [PlacedDecoration]
    }

    let road: [RoadPiece]
    let ground: [GroundLayer]
    let decorations: [DecorationGroup]

    /// - Parameters:
    ///   - overlap: How far each chunk's road reaches into its neighbours, so no seam shows.
    ///   - scenery: Whether to scatter decorations (the ground layer has no use for them).
    init(layout: ChunkLayout, chunk: ChunkLayout.Chunk, plan: ThemePlan, crossSize: CGFloat,
         overlap: CGFloat = 1, scenery: Bool = true) {
        let first = chunk.levels.lowerBound

        // Road, split where chapters change.
        let start = max(chunk.distances.lowerBound - overlap, 0)
        let end = chunk.distances.upperBound + overlap
        let roadSpans = plan.spans(coveringDistances: start...end, near: first, in: layout)
        road = roadSpans.indices.map { index in
            let from = index == 0 ? start : roadSpans[index].startDistance
            let to = index + 1 < roadSpans.count ? roadSpans[index + 1].startDistance + 0.5 : end
            return RoadPiece(chapter: roadSpans[index].chapter, distances: from...max(from, to),
                             points: layout.roadPoints(from: from, to: to, origin: chunk.origin))
        }

        // Ground: the chapter in force just before the chunk, then each chapter fading in.
        let half = max(plan.transition.length, 0.5) / 2
        let groundSpans = plan.spans(coveringY: (chunk.origin - half)...(chunk.origin + chunk.extent + half),
                                     near: first, in: layout)
        ground = groundSpans.enumerated().map { index, span in
            let center = span.startY - chunk.origin
            return GroundLayer(chapter: span.chapter, fade: index == 0 ? nil : (center - half)...(center + half))
        }

        guard scenery else {
            decorations = []
            return
        }

        // Decorations: scattered per chapter inside the chunk, clear of the road in this chunk and
        // its neighbours (the road can run close to a chunk edge).
        let size = layout.chunkSize
        let reachStart = layout.boundaryDistance(beforeLevel: max(first - size, 0))
        let lastLevel = chunk.levels.upperBound + size
        let reachEnd = layout.boundaryDistance(beforeLevel: layout.levelCount.map { min(lastLevel, $0) } ?? lastLevel)
        let keepOutRoad = layout.roadPoints(from: reachStart, to: reachEnd, step: 6, origin: chunk.origin)
        let zoneSpans = plan.spans(coveringY: chunk.origin...(chunk.origin + chunk.extent), near: first, in: layout)
        decorations = zoneSpans.indices.compactMap { index in
            let span = zoneSpans[index]
            let theme = plan.theme(forChapter: span.chapter)
            guard !theme.decorations.isEmpty else { return nil }
            let top = max(span.startY - chunk.origin, 0)
            let bottom = index + 1 < zoneSpans.count ? zoneSpans[index + 1].startY - chunk.origin : chunk.extent
            let area = CGRect(x: 0, y: top, width: crossSize, height: max(min(bottom, chunk.extent) - top, 0))
            let placed = Scenery.scatter(theme.decorations, density: theme.decorationDensity, in: area,
                                         avoiding: keepOutRoad, keepOut: theme.road.width / 2 + theme.roadClearance,
                                         seed: SeededRandom.seed(theme.seed, chunk.index, span.chapter))
            return DecorationGroup(chapter: span.chapter, decorations: placed)
        }
    }
}
