import CoreGraphics

/// The chunk scenes worked out for one update of the map.
///
/// The ground and road behind the chunks are redrawn whenever a chunk scrolls in or out, and each
/// redraw used to sample the road again for every chunk on screen. A cache made with the layout
/// and theme plan of one update is only shared by the views built from that same update, so it
/// never hands out a scene from an older layout, and needs no way to compare layouts.
@MainActor
final class ChunkSceneCache {
    private struct Key: Hashable {
        let index: Int
        let scenery: Bool
    }

    private let layout: ChunkLayout
    private let plan: ThemePlan
    private let crossSize: CGFloat
    private var scenes: [Key: ChunkScene] = [:]

    init(layout: ChunkLayout, plan: ThemePlan, crossSize: CGFloat) {
        self.layout = layout
        self.plan = plan
        self.crossSize = crossSize
    }

    /// The scene for the chunk at `index`, with or without its scattered decorations.
    func scene(forChunk index: Int, scenery: Bool) -> ChunkScene {
        let key = Key(index: index, scenery: scenery)
        if let scene = scenes[key] { return scene }
        let scene = ChunkScene(layout: layout, chunk: layout.chunk(index), plan: plan, crossSize: crossSize,
                               scenery: scenery)
        scenes[key] = scene
        return scene
    }
}
