import SwiftUI

/// A requested framing of a level map, independent of the player's current level.
///
/// Bind this to a map's `position` parameter. Manual scrolling writes back a value whose
/// `positionedByUser` is true. Assign a new framing to resume programmatic camera control.
public struct LevelMapCameraPosition: Equatable, Sendable {
    enum Framing: Equatable, Sendable {
        case automatic
        case level(Double, UnitPoint)
        case avatar(LevelMapFollow)
        case user
    }
    let framing: Framing

    /// Whether manual scrolling has taken ownership of the camera.
    public var positionedByUser: Bool { framing == .user }

    /// The requested fractional level, or nil for automatic, avatar and user-controlled framing.
    /// This is a request, not a measurement of the viewport after scrolling or clamping.
    public var level: Double? {
        if case let .level(level, _) = framing { return level }
        return nil
    }

    /// Opens on the player and tracks visible progress until the person scrolls manually.
    public static var automatic: Self { Self(framing: .automatic) }

    /// Frames a fractional level at a screen anchor without changing player progress.
    /// Finite maps clamp to their last level. Nonfinite values are treated as zero.
    public static func level(_ level: Double, anchor: UnitPoint = .center) -> Self {
        Self(framing: .level(level.isFinite ? max(level, 0) : 0, normalized(anchor)))
    }

    /// Continuously follows the avatar. Manual scrolling is disabled in this mode.
    /// A zoom of one follows without magnifying; Reduce Motion suppresses magnification.
    public static func avatar(zoom: CGFloat = 2.2,
                              anchor: UnitPoint = UnitPoint(x: 0.5, y: 0.45),
                              scalesMarkers: Bool = true) -> Self {
        Self(framing: .avatar(LevelMapFollow(zoom: zoom.isFinite ? max(zoom, 1) : 1,
                                             anchor: normalized(anchor), scalesMarkers: scalesMarkers)))
    }

    static var userPositioned: Self { Self(framing: .user) }

    /// Whether the camera continuously tracks the player's avatar.
    public var followsAvatar: Bool { followConfiguration != nil }

    var followConfiguration: LevelMapFollow? {
        if case let .avatar(follow) = framing { return follow }
        return nil
    }

    var tracksPlayer: Bool {
        switch framing {
        case .automatic, .avatar: true
        case .level, .user: false
        }
    }

    /// Resolves a request without confusing collection IDs with road offsets.
    func resolvedLevel(in layout: ChunkLayout) -> (index: Int, distance: CGFloat)? {
        guard let level, layout.levelCount != 0 else { return nil }
        let upper = layout.levelCount.map { max($0 - 1, 0) } ?? (Int.max / 1024)
        let clamped = min(level, Double(upper))
        let index = Int(clamped)
        guard let distance = layout.travelledDistance(fromLevel: index, progress: clamped - Double(index))
        else { return nil }
        return (index, distance)
    }

    private static func normalized(_ point: UnitPoint) -> UnitPoint {
        func clamp(_ value: CGFloat) -> CGFloat { value.isFinite ? min(max(value, 0), 1) : 0.5 }
        return UnitPoint(x: clamp(point.x), y: clamp(point.y))
    }
}

/// Observe native scrolling when available, keeping an iOS 17-compatible drag fallback.
struct CameraUserInteraction: ViewModifier {
    let action: @MainActor () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18, macOS 15, visionOS 2, *) {
            content.onScrollPhaseChange { _, phase in
                if phase == .interacting || phase == .decelerating { action() }
            }
        } else {
            content.simultaneousGesture(DragGesture(minimumDistance: 10).onChanged { _ in action() })
        }
    }
}
