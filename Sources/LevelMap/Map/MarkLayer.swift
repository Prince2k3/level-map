import SwiftUI

/// Where a ``SwiftUICore/View/levelMapMarks(_:at:placement:content:)`` mark sits relative to the road.
public enum LevelMapMarkPlacement: Sendable, Hashable {
    /// Centred on the road.
    case onRoad
    /// Beside the road, on the side nearer the map's edge, `spacing` points clear of it. The mark
    /// is kept inside the map.
    case outside(spacing: CGFloat = 18)
    /// Beside the road, on the side towards the middle of the map, `spacing` points clear of it.
    case inside(spacing: CGFloat = 18)
}

/// Views placed along the road, set with ``SwiftUICore/View/levelMapMarks(_:at:placement:content:)``.
///
/// `AnyView` is not `Sendable`, but environment values are only read on the main actor.
struct LevelMapMarkGroup: @unchecked Sendable {
    struct Mark {
        let id: AnyHashable
        let position: Double
        let view: AnyView
    }

    let placement: LevelMapMarkPlacement
    let marks: [Mark]
}

extension View {
    /// Places a view for each item along the road, such as a collectible, a reward or a sign,
    /// that the player can tap.
    ///
    /// ```swift
    /// LevelMap(stops, route: .serpentine(), current: arrived) { ... }
    ///     .levelMapMarks(gems, at: \.level, placement: .outside()) { gem in
    ///         Button { collect(gem) } label: { GemBubble(gem: gem) }
    ///     }
    /// ```
    /// Positions are given in levels, as in ``LevelMapGeometry``: `3.5` is halfway along the road
    /// from level 3 to level 4. Marks keep their size while
    /// the camera’s `.avatar(zoom:anchor:scalesMarkers:)` framing magnifies the map,
    /// and are drawn over the level nodes, under the avatar.
    ///
    /// Unlike a ``SwiftUICore/View/levelMapLayer(_:content:)``, marks take touches and VoiceOver
    /// reads them. Call it more than once to add more groups of marks.
    /// - Parameters:
    ///   - items: The items to mark.
    ///   - position: Where along the road each item sits, in levels.
    ///   - placement: Where each mark sits relative to the road.
    ///   - content: The view for each item.
    public func levelMapMarks<Items: Collection>(
        _ items: Items,
        at position: (Items.Element) -> Double,
        placement: LevelMapMarkPlacement = .onRoad,
        @ViewBuilder content: (Items.Element) -> some View
    ) -> some View where Items.Element: Identifiable {
        let group = LevelMapMarkGroup(placement: placement, marks: items.map { item in
            LevelMapMarkGroup.Mark(id: AnyHashable(item.id), position: position(item), view: AnyView(content(item)))
        })
        return transformEnvironment(\.levelMapMarks) { groups in
            // Outer modifiers run first, so inserting at the front keeps the order they were written in.
            groups.insert(group, at: 0)
        }
    }
}

/// Lays marks out beside the road. A layout rather than `position`, so each mark is moved off the
/// road by its own measured size.
struct MarkLayout: Layout {
    let axis: Axis
    /// How much marks are shrunk to keep their size while the map is magnified.
    let scale: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let crossSize = axis == .vertical ? bounds.width : bounds.height
        for subview in subviews {
            let spot = subview[MarkSpotKey.self]
            let size = subview.sizeThatFits(.unspecified)
            let half = (axis == .vertical ? size.width : size.height) * scale / 2
            var cross = axis == .vertical ? spot.point.x : spot.point.y
            if spot.direction != 0 {
                cross += spot.direction * (half + spot.spacing * scale)
                let inset = half + 4 * scale
                if inset * 2 <= crossSize { cross = min(max(cross, inset), crossSize - inset) }
            }
            let center = axis == .vertical ? CGPoint(x: bounds.minX + cross, y: bounds.minY + spot.point.y)
                                           : CGPoint(x: bounds.minX + spot.point.x, y: bounds.minY + cross)
            subview.place(at: center, anchor: .center, proposal: .unspecified)
        }
    }
}

/// Where a mark's road point is, and which way across the map it is moved off it.
struct MarkSpot: Sendable {
    var point: CGPoint = .zero
    /// A logical direction: -1 towards leading (or top), 1 towards trailing (or bottom).
    /// SwiftUI mirrors horizontal placement in RTL; don't negate this direction again.
    var direction: CGFloat = 0
    var spacing: CGFloat = 0
}

struct MarkSpotKey: LayoutValueKey {
    static let defaultValue = MarkSpot()
}

extension LevelMapMarkPlacement {
    /// Which way across the map a mark at `placement` moves off the road.
    func direction(at placement: LevelPlacement) -> CGFloat {
        let outward: CGFloat = placement.side == .trailing ? 1 : -1
        switch self {
        case .onRoad: return 0
        case .outside: return outward
        case .inside: return -outward
        }
    }

    var spacing: CGFloat {
        switch self {
        case .onRoad: 0
        case .outside(let spacing), .inside(let spacing): spacing
        }
    }
}
