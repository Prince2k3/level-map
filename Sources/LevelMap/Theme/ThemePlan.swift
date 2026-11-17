import CoreGraphics

/// The theme (or chapter themes) a map is drawn with, and where each chapter starts.
struct ThemePlan: Sendable {
    let base: LevelMapTheme
    let chapters: LevelMapChapters?
    let transition: ChapterTransition

    init(base: LevelMapTheme, chapters: LevelMapChapters? = nil, transition: ChapterTransition = .fade(length: 240)) {
        self.base = base
        self.chapters = chapters
        self.transition = transition
    }

    func theme(forChapter chapter: Int) -> LevelMapTheme {
        chapters?.theme(chapter) ?? base
    }

    /// Where a chapter's road begins.
    struct Span: Sendable, Equatable {
        let chapter: Int
        /// Arc length where the chapter begins: halfway between its first level and the one before.
        let startDistance: CGFloat
        /// Where the chapter begins along the scroll axis.
        let startY: CGFloat
    }

    /// The chapters with ground in `range` (along the scroll axis), in order. The first is the
    /// chapter in force at the start of the range. `level` is any level near the range, used as
    /// the starting point of the search.
    func spans(coveringY range: ClosedRange<CGFloat>, near level: Int, in layout: ChunkLayout) -> [Span] {
        spans(near: level, in: layout, from: range.lowerBound, to: range.upperBound, key: \.startY)
    }

    /// The chapters the road passes through between two arc lengths, in order.
    func spans(coveringDistances range: ClosedRange<CGFloat>, near level: Int, in layout: ChunkLayout) -> [Span] {
        spans(near: level, in: layout, from: range.lowerBound, to: range.upperBound, key: \.startDistance)
    }

    private func spans(near level: Int, in layout: ChunkLayout, from lower: CGFloat, to upper: CGFloat,
                       key: KeyPath<Span, CGFloat>) -> [Span] {
        guard let length = chapters?.length else {
            return [Span(chapter: 0, startDistance: 0, startY: 0)]
        }
        func span(_ chapter: Int) -> Span {
            guard chapter > 0 else { return Span(chapter: 0, startDistance: 0, startY: 0) }
            let distance = layout.boundaryDistance(beforeLevel: chapter * length)
            return Span(chapter: chapter, startDistance: distance,
                        startY: layout.road.reach(atDistance: distance))
        }
        var chapter = max(level, 0) / length
        var first = span(chapter)
        while chapter > 0, first[keyPath: key] > lower {
            chapter -= 1
            first = span(chapter)
        }
        var result = [first]
        // A chapter is at least one level long, so a range never crosses many of them;
        // the cap only guards against a road that stops moving forward.
        for _ in 0..<64 {
            let next = chapter + 1
            if let count = layout.levelCount, next * length >= count { break }
            let candidate = span(next)
            guard candidate[keyPath: key] < upper else { break }
            result.append(candidate)
            chapter = next
        }
        return result
    }
}
