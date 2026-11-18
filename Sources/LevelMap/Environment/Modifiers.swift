import SwiftUI

extension EnvironmentValues {
    @Entry var levelSpacing: CGFloat = 110
    @Entry var levelMapEdgeInset: CGFloat? = nil
    @Entry var levelMapChunkSize: Int = 10
    @Entry var levelMapTheme: LevelMapTheme = .plain
    @Entry var levelMapChapters: LevelMapChapters? = nil
    @Entry var levelMapChapterTransition: ChapterTransition = .fade(length: 240)
    @Entry var levelMapUnlockAnimation: Animation? = .smooth(duration: 0.6)
    @Entry var levelMapAvatar: LevelMapAvatar? = nil
    @Entry var levelMapProgress: Double = 0
    @Entry var levelMapOverlay: LevelMapOverlay? = nil
    @Entry var levelMapLayers: [LevelMapLayer] = []
    @Entry var levelMapFollow: LevelMapFollow? = nil
    @Entry var levelMapAvatarVisibility: LevelMapAvatarVisibility? = nil
    @Entry var levelMapRecenterTrigger: LevelMapRecenterTrigger? = nil
    @Entry var levelMapFocusOffset: CGFloat = 0
}

private struct LevelMapZoomKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    /// How far ``SwiftUICore/View/levelMapFollowsAvatar(_:zoom:anchor:scalesMarkers:)`` has
    /// magnified the map: 1 when it isn't following. Read it in level nodes and avatars that
    /// scale themselves rather than letting the map do it.
    public internal(set) var levelMapZoom: CGFloat {
        get { self[LevelMapZoomKey.self] }
        set { self[LevelMapZoomKey.self] = newValue }
    }
}

/// Set with ``SwiftUICore/View/levelMapFollowsAvatar(_:zoom:anchor:scalesMarkers:)``.
struct LevelMapFollow: Sendable, Equatable {
    let zoom: CGFloat
    let anchor: UnitPoint
    let scalesMarkers: Bool
}

/// `@MainActor` closures are not `Sendable`, but environment values are only read on the main actor.
struct LevelMapAvatarVisibility: @unchecked Sendable {
    let action: @MainActor (Bool) -> Void
}

/// `AnyHashable` is not `Sendable`, but environment values are only read on the main actor.
struct LevelMapRecenterTrigger: @unchecked Sendable, Equatable {
    let value: AnyHashable
}

extension View {
    /// How far the road advances along the scroll axis per level, in points. Defaults to 110.
    public func levelSpacing(_ spacing: CGFloat) -> some View {
        environment(\.levelSpacing, spacing)
    }

    /// The least room left between a level and the map's edges, in points, so nodes (and an
    /// avatar standing on them) are not cut off. Defaults to half the level spacing.
    ///
    /// Routes that already keep clear of the sides are left as they are; routes that run closer,
    /// like imported paths that touch the edge, are scaled in across the map to fit. The map also
    /// leaves this much room before the first level and after the last.
    public func levelMapEdgeInset(_ inset: CGFloat) -> some View {
        environment(\.levelMapEdgeInset, max(inset, 0))
    }

    /// How many levels each lazily created chunk holds. Defaults to 10.
    public func levelMapChunkSize(_ size: Int) -> some View {
        environment(\.levelMapChunkSize, max(size, 1))
    }

    /// The look of the map: ground, road and scenery. Defaults to ``LevelMapTheme/plain``.
    public func levelMapTheme(_ theme: LevelMapTheme) -> some View {
        environment(\.levelMapTheme, theme)
    }

    /// Splits the map into chapters of `length` levels, each drawn with its own theme.
    /// Overrides ``levelMapTheme(_:)``.
    ///
    /// ```swift
    /// .levelMapChapters(every: 50) { chapter in
    ///     [LevelMapTheme.meadow, .desert, .snow][chapter % 3]
    /// }
    /// ```
    /// The closure may be called often while scrolling, so keep it cheap.
    public func levelMapChapters(every length: Int,
                                 _ theme: @escaping @Sendable (_ chapter: Int) -> LevelMapTheme) -> some View {
        environment(\.levelMapChapters, LevelMapChapters(every: length, theme: theme))
    }

    /// How the ground changes between chapters. Defaults to a 240-point fade.
    public func levelMapChapterTransition(_ transition: ChapterTransition) -> some View {
        environment(\.levelMapChapterTransition, transition)
    }

    /// The animation used when the current level changes: the completed road grows and the
    /// nodes change state. Pass `nil` to switch it off.
    public func levelMapUnlockAnimation(_ animation: Animation?) -> some View {
        environment(\.levelMapUnlockAnimation, animation)
    }

    /// A marker for the player, drawn over the current level. When the current level moves on
    /// by a few levels, the avatar walks there along the road; bigger jumps, and any change while
    /// Reduce Motion is on, move it at once.
    ///
    /// The avatar is centred on the level's position, so offset it to stand beside the node:
    ///
    /// ```swift
    /// .levelMapAvatar {
    ///     Image(systemName: "figure.walk.circle.fill")
    ///         .font(.largeTitle)
    ///         .offset(y: -44)
    /// }
    /// ```
    /// VoiceOver skips the avatar; the current level's node already says where the player is.
    public func levelMapAvatar(@ViewBuilder _ avatar: () -> some View) -> some View {
        environment(\.levelMapAvatar, LevelMapAvatar(view: AnyView(avatar())))
    }

    /// How far the player has got from the current level towards the next: 0 at the current
    /// level, 1 at the next. The avatar stands that far along the road, and the completed road
    /// reaches it.
    ///
    /// Use it when reaching a level takes more than a tap, such as walking to a real place:
    ///
    /// ```swift
    /// LevelMap(stops, route: .serpentine(), current: arrived) { ... }
    ///     .levelMapAvatar { Walker() }
    ///     .levelMapProgress(toNext: 1 - metresLeft / legLength)
    /// ```
    /// Changes inside `withAnimation` glide the avatar along the road. When the player arrives,
    /// add 1 to `current` and set the progress back to 0 in the same update; the avatar stays
    /// where it is. Values are clamped to 0...1, and progress past the last level is ignored.
    /// The map doesn't scroll as progress changes; it scrolls when `current` does.
    public func levelMapProgress(toNext progress: Double) -> some View {
        environment(\.levelMapProgress, progress)
    }

    /// Zooms in on the avatar and keeps it at `anchor` while `isOn` is true, for showing a walk
    /// as it happens. Scrolling is switched off meanwhile; when following stops, the map zooms
    /// back out and scrolls to rest on the avatar.
    ///
    /// ```swift
    /// LevelMap(stops, route: .serpentine(), current: arrived) { ... }
    ///     .levelMapAvatar { Walker() }
    ///     .levelMapProgress(toNext: walked)
    ///     .levelMapFollowsAvatar(session.isLive)
    /// ```
    /// - Parameters:
    ///   - isOn: Whether to follow the avatar.
    ///   - zoom: How far to magnify the map while following.
    ///   - anchor: Where the avatar is held, as a fraction of the map's size.
    ///   - scalesMarkers: Shrinks level nodes and the avatar by the zoom, so they keep their size
    ///     while the ground around them grows. Turn it off to scale them yourself with
    ///     ``SwiftUICore/EnvironmentValues/levelMapZoom``.
    ///
    /// Following is off while Reduce Motion is on: the map still keeps the avatar in view, but
    /// without the zoom.
    public func levelMapFollowsAvatar(_ isOn: Bool = true, zoom: CGFloat = 2.2,
                                      anchor: UnitPoint = UnitPoint(x: 0.5, y: 0.45),
                                      scalesMarkers: Bool = true) -> some View {
        environment(\.levelMapFollow, isOn ? LevelMapFollow(zoom: max(zoom, 1), anchor: anchor,
                                                            scalesMarkers: scalesMarkers) : nil)
    }

    /// Calls `action` when the avatar scrolls out of view (`false`) or back into it (`true`), and
    /// once when the map appears. Use it to offer a way back to the player:
    ///
    /// ```swift
    /// @State private var avatarVisible = true
    /// @State private var recenter = 0
    ///
    /// LevelMap(...) { ... }
    ///     .levelMapAvatar { Walker() }
    ///     .onLevelMapAvatarVisibilityChange { avatarVisible = $0 }
    ///     .levelMapRecenter(on: recenter)
    ///     .overlay(alignment: .bottomTrailing) {
    ///         if !avatarVisible {
    ///             Button("Back to you", systemImage: "location.fill") { recenter += 1 }
    ///         }
    ///     }
    /// ```
    /// The avatar counts as out of view when it is within 40 points of the map's ends.
    public func onLevelMapAvatarVisibilityChange(_ action: @escaping @MainActor (_ isVisible: Bool) -> Void) -> some View {
        environment(\.levelMapAvatarVisibility, LevelMapAvatarVisibility(action: action))
    }

    /// Scrolls the map back to the avatar, where it stands between levels, whenever `trigger`
    /// changes.
    public func levelMapRecenter(on trigger: some Hashable) -> some View {
        environment(\.levelMapRecenterTrigger, LevelMapRecenterTrigger(value: AnyHashable(trigger)))
    }

    /// Moves where the current level rests when the map scrolls to it, in points towards the top
    /// (or leading edge) of the map. Use it to keep the player clear of cards floating over the
    /// bottom of the map. Defaults to 0, the middle.
    public func levelMapFocusOffset(_ offset: CGFloat) -> some View {
        environment(\.levelMapFocusOffset, offset)
    }
}
