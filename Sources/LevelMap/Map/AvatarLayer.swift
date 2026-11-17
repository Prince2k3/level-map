import SwiftUI

/// The player's marker, set with ``SwiftUICore/View/levelMapAvatar(_:)``.
///
/// `AnyView` is not `Sendable`, but environment values are only read on the main actor.
struct LevelMapAvatar: @unchecked Sendable {
    let view: AnyView
}

/// Draws the avatar over the map at a distance along the road. The distance is animatable, so
/// a change of level walks the avatar along the road instead of sliding it in a straight line.
struct AvatarPlacement: ViewModifier, Animatable {
    var distance: CGFloat
    let road: ResolvedRoute
    let axis: Axis
    /// Converts a route point's position along the scroll axis to the scroll content's coordinates.
    let alongOffset: CGFloat
    let mirrorX: CGFloat
    let mirrorY: CGFloat

    nonisolated var animatableData: CGFloat {
        get { distance }
        set { distance = newValue }
    }

    func body(content: Content) -> some View {
        let point = road.sample(atDistance: distance).position
        let along = point.y + alongOffset
        content
            .scaleEffect(x: mirrorX, y: mirrorY)
            .position(axis == .vertical ? CGPoint(x: point.x, y: along) : CGPoint(x: along, y: point.x))
    }
}

extension LevelMap {
    /// How the avatar gets from one level to the next: a walk along the road for short hops,
    /// a jump for long ones or when Reduce Motion is on.
    static func avatarAnimation(from old: Int, to new: Int, reduceMotion: Bool) -> Animation? {
        let hops = abs(new - old)
        guard !reduceMotion, hops > 0, hops <= 3 else { return nil }
        return .easeInOut(duration: 0.35 + 0.3 * Double(hops))
    }
}
