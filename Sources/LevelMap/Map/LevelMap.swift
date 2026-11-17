import SwiftUI

/// A scrolling map of levels laid along a road.
///
/// The map is built from chunks of levels that are created lazily as they scroll into view,
/// so it handles any number of levels, including an endless supply.
///
/// ```swift
/// LevelMap(0..<500, route: .serpentine(amplitude: 0.35), startsAtEnd: true, current: progress) { level, index, state in
///     LevelNode(number: index + 1, state: state)
/// }
/// .levelSpacing(110)
/// ```
public struct LevelMap<Data: LevelMapDataSource, Node: View>: View {
    private let data: Data
    private let route: LevelRoute
    private let axis: Axis
    private let startsAtEnd: Bool
    private let current: Int
    private let node: (Data.Level, Int, LevelState) -> Node

    @Environment(\.levelSpacing) private var spacing
    @Environment(\.levelMapEdgeInset) private var edgeInset
    @Environment(\.levelMapChunkSize) private var chunkSize
    @Environment(\.levelMapTheme) private var theme
    @Environment(\.levelMapChapters) private var chapters
    @Environment(\.levelMapChapterTransition) private var transition
    @Environment(\.levelMapUnlockAnimation) private var unlockAnimation
    @Environment(\.levelMapAvatar) private var avatar
    @Environment(\.levelMapProgress) private var progress
    @Environment(\.levelMapOverlay) private var overlay
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var rotorNamespace
    /// Where the avatar stands. Lags `current` while the avatar walks; `nil` until the map appears.
    @State private var avatarLevel: Int?
    /// The progress the avatar last showed on `avatarLevel`. When `current` and the progress
    /// change in one update, the avatar holds this until it starts walking, rather than first
    /// sliding back to `avatarLevel`'s node.
    @State private var heldProgress: Double = 0
    /// For endless maps: how many chunks the stack currently holds. Grows as the end comes into view.
    @State private var loadedChunks = 0
    /// Chunks added at a time when an endless map nears its end.
    private let pageSize = 6

    /// - Parameters:
    ///   - data: The levels to show. Arrays and `Range<Int>` work directly; ``EndlessLevels`` never ends.
    ///   - route: The road the levels sit on. A finite route caps how many levels are shown.
    ///   - axis: The scroll direction.
    ///   - startsAtEnd: Puts level 0 at the bottom (or trailing edge) so the player climbs the map.
    ///   - current: The player's current level. The map opens on it and scrolls to it when it changes.
    ///   - node: The view for each level.
    public init(
        _ data: Data,
        route: LevelRoute,
        axis: Axis = .vertical,
        startsAtEnd: Bool = false,
        current: Int = 0,
        @ViewBuilder node: @escaping (_ level: Data.Level, _ index: Int, _ state: LevelState) -> Node
    ) {
        self.data = data
        self.route = route
        self.axis = axis
        self.startsAtEnd = startsAtEnd
        self.current = current
        self.node = node
    }

    public var body: some View {
        GeometryReader { proxy in
            let crossSize = axis == .vertical ? proxy.size.width : proxy.size.height
            let viewport = axis == .vertical ? proxy.size.height : proxy.size.width
            if crossSize > 0 {
                let layout = ChunkLayout(road: route.resolved(width: crossSize, spacing: spacing, edgeInset: edgeInset),
                                         dataCount: data.levelCount, chunkSize: chunkSize)
                scrollView(layout: layout, crossSize: crossSize, viewport: viewport)
            }
        }
    }

    private func scrollView(layout: ChunkLayout, crossSize: CGFloat, viewport: CGFloat) -> some View {
        let target = clampedCurrent(in: layout)
        let chunkCount = layout.chunkCount
            ?? max(loadedChunks, layout.chunkIndex(containing: target) + pageSize)

        let plan = ThemePlan(base: theme, chapters: chapters, transition: transition)

        return ScrollViewReader { reader in
            ScrollView(axis == .vertical ? .vertical : .horizontal) {
                stack {
                    ForEach(0..<chunkCount, id: \.self) { index in
                        let chunk = layout.chunk(index)
                        ChunkView(layout: layout, chunk: chunk,
                                  scene: ChunkScene(layout: layout, chunk: chunk, plan: plan, crossSize: crossSize),
                                  plan: plan, data: data, frame: frame(chunk, crossSize: crossSize),
                                  mirrored: startsAtEnd, current: current,
                                  unlockAnimation: unlockAnimation,
                                  rotorNamespace: rotorNamespace, node: node)
                            // VoiceOver reads chunks, and the levels inside them, in road order,
                            // whichever way the map runs on screen.
                            .accessibilityElement(children: .contain)
                            .accessibilitySortPriority(-Double(index))
                            .anchorPreference(key: ChunkBoundsKey.self, value: .bounds) { [index: $0] }
                            .id(MapItemID.chunk(index))
                            .onAppear {
                                // Page in more of an endless map before the player reaches the end.
                                if layout.chunkCount == nil, index >= chunkCount - 2 {
                                    loadedChunks = chunkCount + pageSize
                                }
                            }
                    }
                }
                // Ground, road outlines and road go behind every chunk's nodes, each layer across
                // all chunks before the next: a chunk's road would otherwise cover the previous
                // chunk's nodes, and its outline the road its neighbour spills across the seam.
                // They are placed at the frames the chunks report: the lazy stack only estimates
                // where chunks it has not laid out yet sit, so a second stack would drift out of
                // line with this one.
                .backgroundPreferenceValue(ChunkBoundsKey.self) { bounds in
                    GeometryReader { proxy in
                        let placed = bounds.keys.sorted().compactMap { index in
                            bounds[index].map { anchor in
                                let chunk = layout.chunk(index)
                                return PlacedChunk(index: index, rect: proxy[anchor],
                                                   scene: ChunkScene(layout: layout, chunk: chunk, plan: plan,
                                                                     crossSize: crossSize, scenery: false),
                                                   frame: frame(chunk, crossSize: crossSize))
                            }
                        }
                        let completed = completedDistance(in: layout)
                        ForEach(placed, id: \.index) { item in
                            ChunkGround(scene: item.scene, plan: plan, frame: item.frame, part: .ground)
                                .offset(x: item.rect.minX, y: item.rect.minY)
                        }
                        ForEach(placed, id: \.index) { item in
                            ChunkGround(scene: item.scene, plan: plan, frame: item.frame, part: .outline)
                                .offset(x: item.rect.minX, y: item.rect.minY)
                        }
                        ForEach(placed, id: \.index) { item in
                            ChunkRoad(scene: item.scene, plan: plan, frame: item.frame, completed: completed)
                                .animation(reduceMotion ? nil : unlockAnimation, value: current)
                                .offset(x: item.rect.minX, y: item.rect.minY)
                        }
                    }
                    .accessibilityHidden(true)
                }
                .overlayPreferenceValue(ChunkBoundsKey.self) { bounds in
                    if avatar != nil || overlay != nil {
                        GeometryReader { proxy in
                            if let avatar {
                                avatarLayer(avatar, bounds: bounds, proxy: proxy, layout: layout, target: target)
                            }
                            if let overlay, let index = bounds.keys.min(), let anchor = bounds[index] {
                                let rect = proxy[anchor]
                                overlay.make(LevelMapOverlayContext(
                                    axis: axis, crossSize: crossSize,
                                    alongOffset: (axis == .vertical ? rect.minY : rect.minX) - layout.chunk(index).origin,
                                    mirrored: startsAtEnd))
                            }
                        }
                        .coordinateSpace(.named(LevelMapOverlayContext.coordinateSpace))
                    }
                }
            }
            // Shows when the map is pulled past its ends.
            .background { plan.theme(forChapter: 0).background.view(axis: axis)
                .ignoresSafeArea(edges: axis == .vertical ? .vertical : .horizontal) }
            // Bottom-up maps mirror the whole scroll view, so content grows away from level 0
            // without shifting what is on screen. Nodes are mirrored back in `ChunkView`.
            .scaleEffect(x: startsAtEnd && axis == .horizontal ? -1 : 1,
                         y: startsAtEnd && axis == .vertical ? -1 : 1)
            .accessibilityRotor("Current level") {
                AccessibilityRotorEntry("Current level", id: MapItemID.level(target), in: rotorNamespace) {
                    // The node only exists once its chunk is on screen.
                    scroll(reader, to: target, layout: layout, viewport: viewport, animated: false)
                }
            }
            .onAppear {
                avatarLevel = target
                heldProgress = progress
                scroll(reader, to: target, layout: layout, viewport: viewport, animated: false)
            }
            .onChange(of: current) {
                let level = clampedCurrent(in: layout)
                scroll(reader, to: level, layout: layout, viewport: viewport, animated: !reduceMotion)
                let animation = Self.avatarAnimation(from: avatarLevel ?? level, to: level, reduceMotion: reduceMotion)
                withAnimation(animation) {
                    avatarLevel = level
                    heldProgress = progress
                }
            }
            .onChange(of: progress) {
                if avatarLevel == target { heldProgress = progress }
            }
        }
    }

    /// The avatar, placed using the frame of a chunk the stack has laid out (preferably the one
    /// it stands in), since the lazy stack only estimates where other chunks sit.
    @ViewBuilder
    private func avatarLayer(_ avatar: LevelMapAvatar, bounds: [Int: Anchor<CGRect>], proxy: GeometryProxy,
                             layout: ChunkLayout, target: Int) -> some View {
        let level = avatarLevel ?? target
        let home = layout.chunkIndex(containing: level)
        // Progress belongs to the current level, so it waits until the avatar has walked there.
        // Until then the avatar keeps the progress it last showed, so it doesn't jump back.
        if let index = bounds.keys.min(by: { abs($0 - home) < abs($1 - home) }), let anchor = bounds[index],
           let distance = layout.travelledDistance(fromLevel: level, progress: level == target ? progress : heldProgress) {
            let rect = proxy[anchor]
            let offset = (axis == .vertical ? rect.minY : rect.minX) - layout.chunk(index).origin
            avatar.view
                .modifier(AvatarPlacement(distance: distance, road: layout.road, axis: axis, alongOffset: offset,
                                          mirrorX: startsAtEnd && axis == .horizontal ? -1 : 1,
                                          mirrorY: startsAtEnd && axis == .vertical ? -1 : 1))
                .accessibilityHidden(true)
                .allowsHitTesting(false)
        }
    }

    /// Where the completed road ends: at the current level, or past the end once every level is done.
    private func completedDistance(in layout: ChunkLayout) -> CGFloat {
        if let count = layout.levelCount, current >= count { return .infinity }
        return layout.travelledDistance(fromLevel: max(current, 0), progress: progress) ?? 0
    }

    private func frame(_ chunk: ChunkLayout.Chunk, crossSize: CGFloat) -> ChunkFrame {
        ChunkFrame(axis: axis, crossSize: crossSize, extent: chunk.extent)
    }

    @ViewBuilder
    private func stack(@ViewBuilder content: () -> some View) -> some View {
        if axis == .vertical {
            LazyVStack(spacing: 0, content: content)
        } else {
            LazyHStack(spacing: 0, content: content)
        }
    }

    private func clampedCurrent(in layout: ChunkLayout) -> Int {
        guard let count = layout.levelCount else { return max(current, 0) }
        return min(max(current, 0), max(count - 1, 0))
    }

    /// Centres a level in one step: scrolls to its chunk with an anchor worked out by
    /// ``ChunkLayout/scrollAnchor(forLevel:viewport:)``. Chunk ids are always known to the lazy
    /// stack, unlike the ids of nodes inside chunks that have not been created yet.
    private func scroll(_ reader: ScrollViewProxy, to level: Int, layout: ChunkLayout,
                        viewport: CGFloat, animated: Bool) {
        guard layout.levelCount != 0 else { return }
        let (chunk, anchor) = layout.scrollAnchor(forLevel: level, viewport: viewport)
        let point = axis == .vertical ? UnitPoint(x: 0.5, y: anchor) : UnitPoint(x: anchor, y: 0.5)
        withAnimation(animated ? .smooth : nil) {
            reader.scrollTo(MapItemID.chunk(chunk), anchor: point)
        }
    }
}

/// A chunk the stack has laid out, with what its background layers draw.
private struct PlacedChunk {
    let index: Int
    let rect: CGRect
    let scene: ChunkScene
    let frame: ChunkFrame
}

/// Where each laid-out chunk sits, so the ground can be drawn behind it.
private struct ChunkBoundsKey: PreferenceKey {
    static var defaultValue: [Int: Anchor<CGRect>] { [:] }
    static func reduce(value: inout [Int: Anchor<CGRect>], nextValue: () -> [Int: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}
