import SwiftUI

// A hook for the LevelMapEditor target in this package: it draws views in route coordinates over
// the map's scroll content. Not part of the public API.

/// What an overlay needs to place views on the road and to turn touches back into route points.
package struct LevelMapOverlayContext {
    /// The name of the coordinate space the overlay is drawn in. Read drag locations in it.
    package static let coordinateSpace = "LevelMapOverlay"

    package let axis: Axis
    /// The map's size across the scroll axis: the width routes are resolved for.
    package let crossSize: CGFloat
    /// Converts a route point's position along the scroll axis to the scroll content's coordinates.
    package let alongOffset: CGFloat
    /// Whether the map runs bottom-up (or right-to-left), which flips the content.
    package let mirrored: Bool

    /// Where a route point (`x` across, `y` along the road) sits in the overlay's coordinates.
    package func location(of point: CGPoint) -> CGPoint {
        axis == .vertical ? CGPoint(x: point.x, y: point.y + alongOffset)
                          : CGPoint(x: point.y + alongOffset, y: point.x)
    }

    /// The route point under a location in ``coordinateSpace``.
    package func routePoint(at location: CGPoint) -> CGPoint {
        axis == .vertical ? CGPoint(x: location.x, y: location.y - alongOffset)
                          : CGPoint(x: location.y, y: location.x - alongOffset)
    }

    /// Apply with `scaleEffect` to keep text and symbols the right way round on a mirrored map.
    package var glyphScale: CGSize {
        guard mirrored else { return CGSize(width: 1, height: 1) }
        return axis == .vertical ? CGSize(width: 1, height: -1) : CGSize(width: -1, height: 1)
    }
}

/// `AnyView` is not `Sendable`, but environment values are only read on the main actor.
struct LevelMapOverlay: @unchecked Sendable {
    let make: @MainActor (LevelMapOverlayContext) -> AnyView
}

extension View {
    /// Draws `content` over the map's road, in route coordinates. For the map editor.
    package func levelMapOverlay(@ViewBuilder _ content: @escaping @MainActor (LevelMapOverlayContext) -> some View) -> some View {
        environment(\.levelMapOverlay, LevelMapOverlay { AnyView(content($0)) })
    }
}
