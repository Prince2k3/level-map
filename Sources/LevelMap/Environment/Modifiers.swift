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
}
