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
    private let position: Binding<LevelMapCameraPosition>?
    private let node: (Data.Level, Int, LevelState, LevelPlacement) -> Node

    @Environment(\.layoutDirection) private var layoutDirection
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
    @Environment(\.levelMapLayers) private var layers
    @Environment(\.levelMapFollow) private var legacyFollow
    @Environment(\.levelMapAvatarVisibility) private var avatarVisibility
    @Environment(\.levelMapRecenterTrigger) private var recenterTrigger
    @Environment(\.levelMapFocusOffset) private var focusOffset
    @Environment(\.levelMapContentMargins) private var contentMargins
    @Environment(\.levelMapRecenterButton) private var recenterButton
    @Environment(\.levelMapMarks) private var marks
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
    /// How the map is magnified while it follows the avatar.
    @State private var camera = FollowCamera()
    @State private var animationContext = MapAnimationContext()
    /// When progress last changed, so the follow camera can glide over the time between updates.
    @State private var progressClock = ProgressClock()
    /// Whether the avatar was last seen on screen, so a walk only carries the map along while the
    /// player is watching it rather than after they have scrolled away.
    @State private var sighting = AvatarSighting()
    /// The same as `sighting`, but kept as state for the recenter button, so only a map that
    /// shows one is redrawn when the avatar comes and goes.
    @State private var avatarInView = true
    /// Chunks added at a time when an endless map nears its end.
    private let pageSize = 6

    /// - Parameters:
    ///   - data: The levels to show. Arrays and `Range<Int>` work directly; ``EndlessLevels`` never ends.
    ///   - route: The road the levels sit on. A finite route caps how many levels are shown.
    ///   - axis: The scroll direction.
    ///   - startsAtEnd: Puts level 0 at the bottom (or trailing edge) so the player climbs the map.
    ///   - current: The player's current level. The map opens on it and scrolls to it when it changes.
    ///   - position: Optional two-way camera state. When supplied, overrides the legacy follow modifier.
    ///   - node: The view for each level.
    public init(
        _ data: Data,
        route: LevelRoute,
        axis: Axis = .vertical,
        startsAtEnd: Bool = false,
        current: Int = 0,
        position: Binding<LevelMapCameraPosition>? = nil,
        @ViewBuilder node: @escaping (_ level: Data.Level, _ index: Int, _ state: LevelState) -> Node
    ) {
        self.data = data
        self.route = route
        self.axis = axis
        self.startsAtEnd = startsAtEnd
        self.current = current
        self.position = position
        self.node = { level, index, state, _ in node(level, index, state) }
    }

    /// Creates a map whose nodes are also told where they sit, so they can put labels on the
    /// roomier side of the road or turn with it.
    ///
    /// ```swift
    /// LevelMap(stops, route: .serpentine(), current: arrived) { stop, index, state, placement in
    ///     StopPin(stop: stop, state: state)
    ///         .overlay(alignment: placement.side == .trailing ? .leading : .trailing) {
    ///             Text(stop.name).fixedSize().offset(x: placement.side == .trailing ? -60 : 60)
    ///         }
    /// }
    /// ```
    /// - Parameters:
    ///   - data: The levels to show. Arrays and `Range<Int>` work directly; ``EndlessLevels`` never ends.
    ///   - route: The road the levels sit on. A finite route caps how many levels are shown.
    ///   - axis: The scroll direction.
    ///   - startsAtEnd: Puts level 0 at the bottom (or trailing edge) so the player climbs the map.
    ///   - current: The player's current level. The map opens on it and scrolls to it when it changes.
    ///   - position: Optional two-way camera state. Manual scrolling writes back `positionedByUser`.
    ///   - placedNode: The view for each level, given where the level sits across the map.
    public init(
        _ data: Data,
        route: LevelRoute,
        axis: Axis = .vertical,
        startsAtEnd: Bool = false,
        current: Int = 0,
        position: Binding<LevelMapCameraPosition>? = nil,
        @ViewBuilder placedNode: @escaping (_ level: Data.Level, _ index: Int, _ state: LevelState,
                                            _ placement: LevelPlacement) -> Node
    ) {
        self.data = data
        self.route = route
        self.axis = axis
        self.startsAtEnd = startsAtEnd
        self.current = current
        self.position = position
        self.node = placedNode
    }

    private var follow: LevelMapFollow? {
        if let position { return position.wrappedValue.followConfiguration }
        return legacyFollow
    }

    private var tracksPlayer: Bool { position?.wrappedValue.tracksPlayer ?? true }

    public var body: some View {
        GeometryReader { proxy in
            let crossSize = axis == .vertical ? proxy.size.width : proxy.size.height
            let viewport = axis == .vertical ? proxy.size.height : proxy.size.width
            if crossSize > 0 {
                let layout = ChunkLayout(road: route.resolved(width: crossSize, spacing: spacing, edgeInset: edgeInset),
                                         dataCount: data.levelCount, chunkSize: chunkSize)
                scrollView(layout: layout, crossSize: crossSize, viewport: viewport, size: proxy.size,
                           safeArea: proxy.safeAreaInsets)
            }
        }
    }

    private func scrollView(layout: ChunkLayout, crossSize: CGFloat, viewport: CGFloat, size: CGSize,
                            safeArea: EdgeInsets) -> some View {
        let target = clampedCurrent(in: layout)
        let chunkCount = layout.chunkCount
            ?? max(loadedChunks, layout.chunkIndex(containing: max(target, cameraLevel(in: layout))) + pageSize)

        let plan = ThemePlan(base: theme, chapters: chapters, transition: transition)
        let scenes = ChunkSceneCache(layout: layout, plan: plan, crossSize: crossSize)

        return ScrollViewReader { reader in
            ScrollView(axis == .vertical ? .vertical : .horizontal) {
                stack {
                    // Chunks are identified by the id `scrollTo` is given. With an `.id` on each chunk
                    // instead, a scroll builds every chunk before the target to find it, which
                    // stalls for seconds deep in an endless map.
                    ForEach(0..<chunkCount, id: \.chunkID) { index in
                        let chunk = layout.chunk(index)
                        ChunkView(layout: layout, chunk: chunk,
                                  scene: scenes.scene(forChunk: index, scenery: true),
                                  plan: plan, data: data, frame: frame(chunk, crossSize: crossSize),
                                  mirrored: startsAtEnd, current: current,
                                  unlockAnimation: reduceMotion ? nil : unlockAnimation,
                                  rotorNamespace: rotorNamespace, node: node, markerScale: markerScale)
                            // VoiceOver reads chunks, and the levels inside them, in road order,
                            // whichever way the map runs on screen.
                            .accessibilityElement(children: .contain)
                            .accessibilitySortPriority(-Double(index))
                            .anchorPreference(key: ChunkBoundsKey.self, value: .bounds) { [index: $0] }
                            .onAppear {
                                // Page in more of an endless map before the player reaches the end.
                                if layout.chunkCount == nil, index >= chunkCount - 2 {
                                    loadedChunks = chunkCount + pageSize
                                }
                            }
                    }
                }
                // A finite map is exactly as long as its road. Left to itself the lazy stack guesses
                // the length of chunks it hasn't built, so a fast fling ran past the last level
                // into empty ground before springing back.
                .frame(width: axis == .horizontal ? layout.contentExtent : nil,
                       height: axis == .vertical ? layout.contentExtent : nil,
                       alignment: .topLeading)
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
                                PlacedChunk(index: index, rect: proxy[anchor],
                                            scene: scenes.scene(forChunk: index, scenery: false),
                                            frame: frame(layout.chunk(index), crossSize: crossSize))
                            }
                        }
                        let completed = completedDistance(in: layout)
                        ForEach(placed, id: \.index) { item in
                            ChunkGround(scene: item.scene, plan: plan, frame: item.frame, part: .ground)
                                .offset(x: item.rect.minX, y: item.rect.minY)
                        }
                        layerViews(.belowRoad, placed: placed.map { ($0.index, $0.rect) }, layout: layout)
                        ForEach(placed, id: \.index) { item in
                            ChunkGround(scene: item.scene, plan: plan, frame: item.frame, part: .outline)
                                .offset(x: item.rect.minX, y: item.rect.minY)
                        }
                        ForEach(placed, id: \.index) { item in
                            ChunkRoad(scene: item.scene, plan: plan, frame: item.frame, completed: completed)
                                .modifier(MapDefaultAnimation(animation: reduceMotion ? nil : unlockAnimation, value: current))
                                .offset(x: item.rect.minX, y: item.rect.minY)
                        }
                        layerViews(.aboveRoad, placed: placed.map { ($0.index, $0.rect) }, layout: layout)
                    }
                    .accessibilityHidden(true)
                }
                // Kept apart from the layers below: it reads where the content is in the viewport,
                // which changes on every scroll frame, and that would rebuild every layer with it.
                .overlayPreferenceValue(ChunkBoundsKey.self) { bounds in
                    GeometryReader { proxy in
                        VisibilityReporter(isVisible: avatarIsVisible(bounds: bounds, proxy: proxy, layout: layout,
                                                                      target: target, viewport: viewport)) { visible in
                            sighting.isVisible = visible
                            avatarVisibility?.action(visible)
                            if recenterButton != nil {
                                withAnimation(.snappy) { avatarInView = visible }
                            }
                        }
                    }
                }
                .overlayPreferenceValue(ChunkBoundsKey.self) { bounds in
                    if avatar != nil || overlay != nil || !marks.isEmpty
                        || layers.contains(where: { $0.placement == .aboveNodes }) {
                        GeometryReader { proxy in
                            let placed = bounds.keys.sorted().compactMap { index in
                                bounds[index].map { (index: index, rect: proxy[$0]) }
                            }
                            layerViews(.aboveNodes, placed: placed, layout: layout)
                            marksLayer(placed: placed, layout: layout)
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
                .environment(\.levelMapZoom, camera.zoom)
                // Room past the ends for the content margins, so the map can scroll a level near
                // either end clear of whatever covers that edge, as `contentMargins` lets a list do.
                .padding(axis == .vertical ? .top : .leading, scrollPadding.start)
                .padding(axis == .vertical ? .bottom : .trailing, scrollPadding.end)
            }
            .scrollDisabled(follow != nil)
            .modifier(CameraUserInteraction {
                guard let position, follow == nil, !position.wrappedValue.positionedByUser else { return }
                position.wrappedValue = .userPositioned
            })
            // The scroll view's own coordinates, unmirrored, for finding the avatar on screen.
            .coordinateSpace(.named(Self.viewportSpace))
            // Bottom-up maps mirror the whole scroll view, so content grows away from level 0
            // without shifting what is on screen. Nodes are mirrored back in `ChunkView`.
            .scaleEffect(x: startsAtEnd && axis == .horizontal ? -1 : 1,
                         y: startsAtEnd && axis == .vertical ? -1 : 1)
            // Following the avatar magnifies the map around it. This sits outside the scroll
            // view so it never changes what the scroll view lays out or where it scrolls.
            .scaleEffect(camera.zoom, anchor: UnitPoint(x: camera.focus.x / max(size.width, 1),
                                                        y: camera.focus.y / max(size.height, 1)))
            .offset(x: camera.anchor.x - camera.focus.x, y: camera.anchor.y - camera.focus.y)
            // While magnified, the map is clipped to its frame, plus the safe area the scroll
            // view draws under (behind the home indicator), so no gap opens there.
            .clipShape(ZoomClip(isZoomed: camera.zoom > 1.001, axis: axis, safeArea: safeArea))
            // Clipping doesn't limit touches: magnified, the map would take taps meant for the
            // views around it. Keep its touches to the same area it draws in.
            .contentShape(ZoomClip(isZoomed: true, axis: axis, safeArea: safeArea))
            .overlay(alignment: recenterButton?.alignment ?? .bottomTrailing) {
                if let recenterButton, !avatarInView, follow == nil {
                    recenterButton.make {
                        if let position { position.wrappedValue = .automatic }
                        else { scrollToAvatar(reader, layout: layout, viewport: viewport, target: target, animated: !reduceMotion) }
                    }
                    .padding(16)
                    .padding(contentMargins)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            // Shows when the map is pulled past its ends.
            .background { plan.theme(forChapter: 0).background.view(axis: axis)
                .ignoresSafeArea(edges: axis == .vertical ? .vertical : .horizontal) }
            .accessibilityRotor("Current level") {
                AccessibilityRotorEntry("Current level", id: MapItemID.level(target), in: rotorNamespace) {
                    // The node only exists once its chunk is on screen.
                    if let position { position.wrappedValue = .automatic }
                    else { scroll(reader, to: target, layout: layout, viewport: viewport, animated: false) }
                }
            }
            .onAppear {
                avatarLevel = target
                heldProgress = progress
                if position != nil {
                    applyPosition(reader, layout: layout, size: size, animation: nil)
                } else if follow != nil {
                    followAvatar(reader, layout: layout, size: size, animation: nil)
                } else {
                    scroll(reader, to: target, layout: layout, viewport: viewport, animated: false)
                }
            }
            .onChange(of: current) {
                let level = clampedCurrent(in: layout)
                let pace = reduceMotion ? nil : progressClock.pace()
                // Mid-walk, the avatar steps onto the new level at the walk's own even pace;
                // otherwise it walks or jumps there as for any change of level.
                let animation = if let pace, abs(level - (avatarLevel ?? level)) == 1 {
                    Animation.linear(duration: pace)
                } else {
                    Self.avatarAnimation(from: avatarLevel ?? level, to: level, reduceMotion: reduceMotion)
                }
                if !tracksPlayer {
                    // Viewing future stops does not change or follow player progress.
                } else if follow != nil {
                    // The camera moves with the walk, so the avatar stays where it is held.
                    followAvatar(reader, layout: layout, size: size, animation: animation)
                } else if sighting.isVisible, let pace,
                          let distance = layout.travelledDistance(fromLevel: level, progress: progress) {
                    // Mid-walk, arriving carries on the glide the walk was making, instead of
                    // starting a new scroll of its own.
                    scroll(reader, toDistance: distance, nearLevel: level, layout: layout, viewport: viewport,
                           animation: .linear(duration: pace))
                } else {
                    scroll(reader, to: level, layout: layout, viewport: viewport, animated: !reduceMotion)
                }
                withTransaction(animationContext.resolved(fallback: animation, reduceMotion: reduceMotion)) {
                    avatarLevel = level
                    heldProgress = progress
                }
            }
            .onChange(of: progress) {
                if avatarLevel == target { heldProgress = progress }
                let interval = progressClock.tick()
                if follow != nil {
                    // A scroll can't share the walk's own animation, so the camera glides at an even
                    // pace over the time since the last update, arriving as the next one comes in.
                    followAvatar(reader, layout: layout, size: size,
                                 animation: reduceMotion ? nil : .linear(duration: interval))
                } else if tracksPlayer, !reduceMotion, sighting.isVisible {
                    // Without following, the map still glides along with the walk, so the avatar
                    // stays where the current level rests rather than the map waiting and catching
                    // up on arrival.
                    // This aims at where the walk is, not where the avatar is drawn: on arriving, this
                    // can run before the avatar moves to the new level, and aiming at the avatar
                    // would hold the map still for a moment.
                    let level = clampedCurrent(in: layout)
                    if let distance = layout.travelledDistance(fromLevel: level, progress: progress) {
                        scroll(reader, toDistance: distance, nearLevel: level, layout: layout, viewport: viewport,
                               animation: .linear(duration: interval))
                    }
                }
            }
            .onChange(of: position?.wrappedValue) {
                applyPosition(reader, layout: layout, size: size, animation: reduceMotion ? nil : .smooth(duration: 0.6))
            }
            .onChange(of: follow) {
                guard position == nil else { return }
                if follow != nil {
                    followAvatar(reader, layout: layout, size: size, animation: reduceMotion ? nil : .smooth(duration: 0.6))
                } else {
                    // The zoom and the scroll together decide where the avatar is drawn, so they share
                    // one animation. On different curves the avatar overshoots its resting place.
                    let animation: Animation? = reduceMotion ? nil : .smooth(duration: 0.6)
                    withTransaction(animationContext.resolved(fallback: animation, reduceMotion: reduceMotion)) {
                        camera = FollowCamera(anchor: camera.anchor)
                    }
                    scrollToAvatar(reader, layout: layout, viewport: viewport, target: target, animation: animation)
                }
            }
            .onChange(of: size) {
                if position != nil {
                    applyPosition(reader, layout: layout, size: size, animation: nil)
                } else if follow != nil {
                    followAvatar(reader, layout: layout, size: size, animation: nil)
                }
            }
            .onChange(of: layout.levelCount) {
                if position != nil { applyPosition(reader, layout: layout, size: size, animation: nil) }
            }
            .onChange(of: recenterTrigger) {
                guard follow == nil else { return }
                if let position { position.wrappedValue = .automatic }
                else { scrollToAvatar(reader, layout: layout, viewport: viewport, target: target, animated: !reduceMotion) }
            }
        }
        .transaction { transaction in
            animationContext.transaction = transaction
        }
    }

    /// The camera target is also included in endless paging before scrolling to it.
    private func cameraLevel(in layout: ChunkLayout) -> Int {
        position?.wrappedValue.resolvedLevel(in: layout)?.index ?? 0
    }

    private func applyPosition(_ reader: ScrollViewProxy, layout: ChunkLayout, size: CGSize,
                               animation: Animation?) {
        guard let requested = position?.wrappedValue else { return }
        let viewport = axis == .vertical ? size.height : size.width
        switch requested.framing {
        case .user:
            return
        case .avatar:
            followAvatar(reader, layout: layout, size: size, animation: animation)
        case .automatic:
            resetZoom(animation: animation)
            let level = clampedCurrent(in: layout)
            if let distance = layout.travelledDistance(fromLevel: level, progress: progress) {
                scroll(reader, toDistance: distance, nearLevel: level, layout: layout, viewport: viewport,
                       animation: animation)
            }
        case let .level(_, anchor):
            resetZoom(animation: animation)
            if let target = requested.resolvedLevel(in: layout) {
                scroll(reader, toDistance: target.distance, nearLevel: target.index, layout: layout, viewport: viewport,
                       animation: animation, screenAnchor: axis == .vertical ? anchor.y : anchor.x)
            }
        }
    }

    private func resetZoom(animation: Animation?) {
        withTransaction(animationContext.resolved(fallback: animation, reduceMotion: reduceMotion)) {
            camera = FollowCamera(anchor: camera.anchor)
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
                .scaleEffect(markerScale)
                .modifier(AvatarPlacement(distance: distance, road: layout.road, axis: axis, alongOffset: offset,
                                          mirrorX: startsAtEnd && axis == .horizontal ? -1 : 1,
                                          mirrorY: startsAtEnd && axis == .vertical ? -1 : 1))
                .accessibilityHidden(true)
                .allowsHitTesting(false)
        }
    }

    /// The ``levelMapLayer(_:content:)`` layers with `placement`, drawn across the laid-out chunks.
    @ViewBuilder
    private func layerViews(_ placement: LevelMapLayerPlacement, placed: [(index: Int, rect: CGRect)],
                            layout: ChunkLayout) -> some View {
        let matching = layers.filter { $0.placement == placement }
        if !matching.isEmpty, let (geometry, origin) = layerGeometry(placed: placed, layout: layout) {
            ForEach(matching.indices, id: \.self) { index in
                upright(matching[index].make(geometry), geometry: geometry, origin: origin)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// The ``levelMapMarks(_:at:placement:content:)`` marks near the laid-out chunks.
    @ViewBuilder
    private func marksLayer(placed: [(index: Int, rect: CGRect)], layout: ChunkLayout) -> some View {
        if !marks.isEmpty, let (geometry, origin) = layerGeometry(placed: placed, layout: layout) {
            // A level either side, so a mark beside the first or last level doesn't pop in late.
            let range = Double(geometry.levels.lowerBound) - 1...Double(geometry.levels.upperBound)
            let scale = markerScale
            upright(MarkLayout(axis: axis, scale: scale) {
                ForEach(marks.indices, id: \.self) { group in
                    let placement = marks[group].placement
                    ForEach(marks[group].marks.filter { range.contains($0.position) }, id: \.id) { mark in
                        if let point = geometry.point(atLevel: mark.position),
                           let side = geometry.placement(ofLevel: mark.position) {
                            mark.view
                                .scaleEffect(scale)
                                .layoutValue(key: MarkSpotKey.self,
                                             value: MarkSpot(point: point, direction: placement.direction(at: side),
                                                             spacing: placement.spacing))
                        }
                    }
                }
            }, geometry: geometry, origin: origin)
        }
    }

    /// The geometry handed to layers drawn across `placed`, and where their top-leading corner is.
    private func layerGeometry(placed: [(index: Int, rect: CGRect)],
                               layout: ChunkLayout) -> (LevelMapGeometry, CGPoint)? {
        guard let first = placed.first else { return nil }
        let union = placed.dropFirst().reduce(first.rect) { $0.union($1.rect) }
        let along = { (rect: CGRect) in self.axis == .vertical ? rect.minY : rect.minX }
        let alongOffset = along(first.rect) - layout.chunk(first.index).origin
        let low = placed.map(\.index).min() ?? first.index
        let high = placed.map(\.index).max() ?? first.index
        // The measured rects wobble in their last digits as the map glides. Rounded, the size
        // holds still, so a layer that compares it isn't redrawn every frame.
        let size = CGSize(width: (union.width * 1000).rounded() / 1000,
                          height: (union.height * 1000).rounded() / 1000)
        let geometry = LevelMapGeometry(size: size, axis: axis, layout: layout,
                                        levels: layout.chunk(low).levels.lowerBound..<layout.chunk(high).levels.upperBound,
                                        originAlong: along(union) - alongOffset, mirrored: startsAtEnd,
                                        zoom: layerZoom, layoutDirection: layoutDirection)
        return (geometry, union.origin)
    }

    /// Sizes `content` to a layer and stands it the right way up over the chunks it covers.
    private func upright(_ content: some View, geometry: LevelMapGeometry, origin: CGPoint) -> some View {
        content
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            // Bottom-up maps are mirrored as a whole; the layer is mirrored back so its content
            // stands the right way up. LevelMapGeometry flips its points to match.
            .scaleEffect(x: startsAtEnd && axis == .horizontal ? -1 : 1,
                         y: startsAtEnd && axis == .vertical ? -1 : 1)
            .offset(x: origin.x, y: origin.y)
    }

    /// The zoom handed to layers.
    private var layerZoom: CGFloat { camera.zoom }

    /// How much nodes and the avatar are shrunk to keep their size while the map is zoomed in.
    private var markerScale: CGFloat {
        guard follow?.scalesMarkers ?? true else { return 1 }
        return 1 / max(camera.zoom, 1)
    }

    static var viewportSpace: String { "LevelMapViewport" }

    /// The content margins at the top and bottom of the map (or its leading and trailing edges).
    private var marginsAlong: (start: CGFloat, end: CGFloat) {
        axis == .vertical ? (contentMargins.top, contentMargins.bottom)
                          : (contentMargins.leading, contentMargins.trailing)
    }

    /// The content margins along the scroll axis in the scroll view's own coordinates, which a
    /// mirrored map runs from the far end of the screen.
    private var scrollPadding: (start: CGFloat, end: CGFloat) {
        let (start, end) = marginsAlong
        return startsAtEnd ? (end, start) : (start, end)
    }

    /// Whether the avatar, at rest, is on screen and at least 40 points from the ends of the part of
    /// the map the content margins leave uncovered.
    private func avatarIsVisible(bounds: [Int: Anchor<CGRect>], proxy: GeometryProxy, layout: ChunkLayout,
                                 target: Int, viewport: CGFloat) -> Bool {
        let level = avatarLevel ?? target
        let home = layout.chunkIndex(containing: level)
        // Measured from a chunk that is laid out, as the avatar is placed. The stack's own frame
        // can't be used: deep in a long map it only estimates the chunks it hasn't built.
        guard let index = bounds.keys.min(by: { abs($0 - home) < abs($1 - home) }), let anchor = bounds[index],
              let distance = layout.travelledDistance(fromLevel: level, progress: level == target ? progress : heldProgress)
        else { return false }
        let rect = proxy[anchor]
        let offset = (axis == .vertical ? rect.minY : rect.minX) - layout.chunk(index).origin
        let frame = proxy.frame(in: .named(Self.viewportSpace))
        let along = layout.road.sample(atDistance: distance).position.y + offset
            + (axis == .vertical ? frame.minY : frame.minX)
        // The scroll view's own coordinates are unmirrored; the margins are on screen.
        let onScreen = startsAtEnd ? viewport - along : along
        let (start, end) = marginsAlong
        let margin = min(40, max(viewport - start - end, 0) / 4)
        return onScreen >= start + margin && onScreen <= viewport - end - margin
    }

    /// Scrolls and zooms so the avatar sits at the follow anchor, as near as the map's edges allow.
    private func followAvatar(_ reader: ScrollViewProxy, layout: ChunkLayout, size: CGSize, animation: Animation?) {
        let level = clampedCurrent(in: layout)
        guard let follow, size.width > 0, size.height > 0,
              let distance = layout.travelledDistance(fromLevel: level, progress: progress) else { return }
        let zoom = reduceMotion ? 1 : follow.zoom
        let viewport = axis == .vertical ? size.height : size.width
        let anchor = CGPoint(x: follow.anchor.x * size.width, y: follow.anchor.y * size.height)
        let screenTarget = axis == .vertical ? anchor.y : anchor.x
        let contentTarget = startsAtEnd ? viewport - screenTarget : screenTarget

        // Where the avatar will be once scrolled: the scroll view stops at its ends.
        let point = layout.road.sample(atDistance: distance).position
        let padding = scrollPadding
        let position = layout.contentPosition(ofRouteY: point.y) + padding.start
        var offset = max(position - contentTarget, 0)
        if let extent = layout.contentExtent.map({ $0 + padding.start + padding.end }) {
            offset = min(offset, max(extent - viewport, 0))
        }
        var along = position - offset
        if startsAtEnd { along = viewport - along }
        let avatar = axis == .vertical ? CGPoint(x: point.x, y: along) : CGPoint(x: along, y: point.x)

        // Keep the magnified view inside the map, so its edges never show.
        func clamp(_ value: CGFloat, anchor: CGFloat, length: CGFloat) -> CGFloat {
            let low = anchor / zoom, high = length - (length - anchor) / zoom
            return low <= high ? min(max(value, low), high) : value
        }
        let focus = CGPoint(x: clamp(avatar.x, anchor: anchor.x, length: size.width),
                            y: clamp(avatar.y, anchor: anchor.y, length: size.height))

        let (chunk, unit) = layout.scrollAnchor(forDistance: distance, nearLevel: level,
                                                target: contentTarget, viewport: viewport)
        let move = {
            reader.scrollTo(MapItemID.chunk(chunk), anchor: axis == .vertical ? UnitPoint(x: 0.5, y: unit)
                                                                               : UnitPoint(x: unit, y: 0.5))
            camera = FollowCamera(zoom: zoom, focus: focus, anchor: anchor)
        }
        withTransaction(animationContext.resolved(fallback: animation, reduceMotion: reduceMotion), move)
    }

    /// Scrolls so the avatar, where it stands between levels, rests where the current level would.
    private func scrollToAvatar(_ reader: ScrollViewProxy, layout: ChunkLayout, viewport: CGFloat, target: Int,
                                animated: Bool) {
        scrollToAvatar(reader, layout: layout, viewport: viewport, target: target, animation: animated ? .smooth : nil)
    }

    private func scrollToAvatar(_ reader: ScrollViewProxy, layout: ChunkLayout, viewport: CGFloat, target: Int,
                                animation: Animation?) {
        let level = avatarLevel ?? target
        guard let distance = layout.travelledDistance(fromLevel: level, progress: level == target ? progress : heldProgress)
        else { return }
        scroll(reader, toDistance: distance, nearLevel: level, layout: layout, viewport: viewport, animation: animation)
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

    /// Brings a level to rest in one step: the middle of the uncovered map, moved by the focus offset.
    private func scroll(_ reader: ScrollViewProxy, to level: Int, layout: ChunkLayout,
                        viewport: CGFloat, animated: Bool) {
        guard layout.levelCount != 0, let distance = layout.road.distance(ofLevel: level) else { return }
        scroll(reader, toDistance: distance, nearLevel: level, layout: layout, viewport: viewport,
               animation: animated ? .smooth : nil)
    }

    /// Scrolls to the chunk holding `distance` with an anchor worked out by
    /// ``ChunkLayout/scrollAnchor(forDistance:nearLevel:target:viewport:)``. Chunk ids are always
    /// known to the lazy stack, unlike the ids of nodes inside chunks that have not been created yet.
    private func scroll(_ reader: ScrollViewProxy, toDistance distance: CGFloat, nearLevel level: Int,
                        layout: ChunkLayout, viewport: CGFloat, animation: Animation?, screenAnchor: CGFloat? = nil) {
        guard layout.levelCount != 0 else { return }
        // A positive offset moves the resting point up the screen (or towards the leading edge).
        // The scroll view's own coordinates run the other way on mirrored maps.
        let (start, end) = marginsAlong
        let screenTarget = screenAnchor.map { viewport * $0 }
            ?? (start + max(viewport - start - end, 0) / 2 - focusOffset)
        let target = startsAtEnd ? viewport - screenTarget : screenTarget
        let (chunk, anchor) = layout.scrollAnchor(forDistance: distance, nearLevel: level,
                                                  target: target, viewport: viewport)
        let point = axis == .vertical ? UnitPoint(x: 0.5, y: anchor) : UnitPoint(x: anchor, y: 0.5)
        withTransaction(animationContext.resolved(fallback: animation, reduceMotion: reduceMotion)) {
            reader.scrollTo(MapItemID.chunk(chunk), anchor: point)
        }
    }
}

/// Clips the magnified map to its frame, grown by the safe area at the ends of the scroll axis
/// (where the scroll view draws too); leaves it unclipped otherwise.
private struct ZoomClip: Shape {
    let isZoomed: Bool
    let axis: Axis
    let safeArea: EdgeInsets

    func path(in rect: CGRect) -> Path {
        guard isZoomed else { return Path(rect.insetBy(dx: -10_000, dy: -10_000)) }
        if axis == .vertical {
            return Path(CGRect(x: rect.minX, y: rect.minY - safeArea.top,
                               width: rect.width, height: rect.height + safeArea.top + safeArea.bottom))
        }
        return Path(CGRect(x: rect.minX - safeArea.leading, y: rect.minY,
                           width: rect.width + safeArea.leading + safeArea.trailing, height: rect.height))
    }
}

/// Times progress updates. A class, so ticking it doesn't redraw the map.
final class ProgressClock {
    private var last: Date?
    private var lastInterval: Double = 0.35

    /// The pace of updates while they keep coming, or `nil` once they have stopped.
    func pace(now: Date = .now) -> Double? {
        guard let last, now.timeIntervalSince(last) <= 1.5 else { return nil }
        return lastInterval
    }

    /// Seconds since the previous update, kept to a pace that reads as a glide: a first update,
    /// or one after a long pause, takes a moment rather than snapping or crawling.
    func tick(now: Date = .now) -> Double {
        defer { last = now }
        guard let last else { lastInterval = 0.35; return lastInterval }
        let interval = now.timeIntervalSince(last)
        lastInterval = interval > 1.5 ? 0.35 : min(max(interval, 0.05), 1.5)
        return lastInterval
    }
}

/// How the map is magnified while following the avatar: `focus` (in the map's own coordinates)
/// is magnified by `zoom` and shown at `anchor`. With `focus == anchor` and a zoom of 1, nothing moves.
private struct FollowCamera: Equatable {
    var zoom: CGFloat = 1
    var focus: CGPoint = .zero
    var anchor: CGPoint = .zero

    /// No magnification, keeping `anchor` so turning following off animates in place.
    init(anchor: CGPoint) {
        self.init(zoom: 1, focus: anchor, anchor: anchor)
    }

    init(zoom: CGFloat = 1, focus: CGPoint = .zero, anchor: CGPoint = .zero) {
        self.zoom = zoom
        self.focus = focus
        self.anchor = anchor
    }
}

/// Reports changes in whether the avatar is on screen, and its first value.
/// Whether the avatar was on screen when last laid out. A class, so updating it doesn't redraw the map.
final class AvatarSighting {
    var isVisible = true
}

private struct VisibilityReporter: View {
    let isVisible: Bool
    let action: @MainActor (Bool) -> Void

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onChange(of: isVisible, initial: true) { action(isVisible) }
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

private extension Int {
    /// The id of the chunk at this index, which `scrollTo` targets.
    var chunkID: MapItemID { .chunk(self) }
}


extension LevelMap {
    /// Creates a map from a random-access collection with explicit stable element identities.
    /// `current` remains a zero-based road offset, independent of collection indices or IDs.
    public init<Elements: RandomAccessCollection, ID: Hashable>(
        _ elements: Elements, id: KeyPath<Elements.Element, ID>, route: LevelRoute,
        axis: Axis = .vertical, startsAtEnd: Bool = false, current: Int = 0, position: Binding<LevelMapCameraPosition>? = nil,
        @ViewBuilder node: @escaping (Elements.Element, Int, LevelState) -> Node
    ) where Data == LevelMapCollection<Elements, ID> {
        self.init(LevelMapCollection(elements, id: id), route: route, axis: axis,
                  startsAtEnd: startsAtEnd, current: current, position: position, node: node)
    }

    /// Creates a map whose collection elements supply their own stable identities.
    public init<Elements: RandomAccessCollection>(
        _ elements: Elements, route: LevelRoute, axis: Axis = .vertical,
        startsAtEnd: Bool = false, current: Int = 0, position: Binding<LevelMapCameraPosition>? = nil,
        @ViewBuilder node: @escaping (Elements.Element, Int, LevelState) -> Node
    ) where Elements.Element: Identifiable, Data == LevelMapCollection<Elements, Elements.Element.ID> {
        self.init(elements, id: \.id, route: route, axis: axis,
                  startsAtEnd: startsAtEnd, current: current, position: position, node: node)
    }

    /// Creates placed nodes from a collection with explicit stable identities.
    public init<Elements: RandomAccessCollection, ID: Hashable>(
        _ elements: Elements, id: KeyPath<Elements.Element, ID>, route: LevelRoute,
        axis: Axis = .vertical, startsAtEnd: Bool = false, current: Int = 0, position: Binding<LevelMapCameraPosition>? = nil,
        @ViewBuilder placedNode: @escaping (Elements.Element, Int, LevelState, LevelPlacement) -> Node
    ) where Data == LevelMapCollection<Elements, ID> {
        self.init(LevelMapCollection(elements, id: id), route: route, axis: axis,
                  startsAtEnd: startsAtEnd, current: current, position: position, placedNode: placedNode)
    }

    /// Creates placed nodes from identifiable collection elements.
    public init<Elements: RandomAccessCollection>(
        _ elements: Elements, route: LevelRoute, axis: Axis = .vertical,
        startsAtEnd: Bool = false, current: Int = 0, position: Binding<LevelMapCameraPosition>? = nil,
        @ViewBuilder placedNode: @escaping (Elements.Element, Int, LevelState, LevelPlacement) -> Node
    ) where Elements.Element: Identifiable, Data == LevelMapCollection<Elements, Elements.Element.ID> {
        self.init(elements, id: \.id, route: route, axis: axis,
                  startsAtEnd: startsAtEnd, current: current, position: position, placedNode: placedNode)
    }
}
