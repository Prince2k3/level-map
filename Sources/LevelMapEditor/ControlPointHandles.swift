import LevelMap
import SwiftUI

/// A draggable point on the route.
struct RouteHandle: Identifiable, Equatable {
    enum Target: Hashable {
        /// Where the road begins across the map.
        case start
        /// A spline or polyline control point.
        case point(SegmentRef, Int)
        /// Where a straight segment ends across the map.
        case straightEnd(SegmentRef)
        /// How close a detour gets to the edge.
        case detourEdge(SegmentRef)
    }

    let target: Target
    /// In route coordinates: `x` across the map, `y` along the road, in points.
    let position: CGPoint
    /// Where the handle's segment starts, in route coordinates.
    let segmentStart: CGPoint
    var id: Target { target }

    var segment: SegmentRef? {
        switch target {
        case .start: nil
        case let .point(ref, _), let .straightEnd(ref), let .detourEdge(ref): ref
        }
    }
}

/// Where a segment begins on the road, for the labels drawn on the map.
struct SegmentMarker: Identifiable, Equatable {
    let ref: SegmentRef
    let kind: SegmentKind
    let start: CGPoint
    var id: SegmentRef { ref }
}

/// Handles and segment markers for one route, laid out the way the map draws it.
struct RouteHandles {
    var handles: [RouteHandle] = []
    var markers: [SegmentMarker] = []

    /// Replays each segment's waypoints from where the previous one ended, as
    /// ``ResolvedRoute`` does. Handles for the repeating part sit on its first pass.
    init(route: RouteJSON, context: RouteContext) {
        var cursor = CGPoint(x: route.start * context.width, y: 0)
        handles.append(RouteHandle(target: .start, position: cursor, segmentStart: cursor))
        for section in [RouteSection.main, .repeating] {
            for (index, segment) in route.segments(in: section).enumerated() {
                let ref = SegmentRef(section: section, index: index)
                markers.append(SegmentMarker(ref: ref, kind: segment.kind, start: cursor))
                guard let waypoints = try? segment.segment().waypoints(from: cursor, in: context).map(\.point),
                      let end = waypoints.last else { continue }
                switch segment {
                case .spline, .polyline:
                    for (point, position) in waypoints.enumerated() {
                        handles.append(RouteHandle(target: .point(ref, point), position: position, segmentStart: cursor))
                    }
                case .straight:
                    handles.append(RouteHandle(target: .straightEnd(ref), position: end, segmentStart: cursor))
                case .detour:
                    handles.append(RouteHandle(target: .detourEdge(ref), position: waypoints[0], segmentStart: cursor))
                case .serpentine, .zigzag:
                    break
                }
                cursor = end
            }
        }
    }
}

extension RouteJSON {
    /// Moves a handle to `location` (route coordinates). Values are rounded to hundredths.
    mutating func drag(_ handle: RouteHandle, to location: CGPoint, context: RouteContext) {
        let x = rounded(min(max(location.x / context.width, 0), 1))
        switch handle.target {
        case .start:
            start = x
        case let .straightEnd(ref):
            guard case let .straight(levels, _) = self[ref] else { return }
            self[ref] = .straight(levels: levels, toX: x)
        case let .detourEdge(ref):
            guard case let .detour(side, levels, _) = self[ref] else { return }
            let inset = side == .leading ? x : 1 - x
            self[ref] = .detour(side: side, levels: levels, inset: rounded(min(max(inset, 0), 0.5)))
        case let .point(ref, index):
            guard var segment = self[ref], segment.points.indices.contains(index) else { return }
            var points = segment.points
            // Spline points are fractions of the segment's length; polyline points are in map widths.
            let unit = segment.kind == .spline ? context.length(forLevels: segment.levelCount) : context.width
            let along = (location.y - handle.segmentStart.y) / max(unit, 1)
            // Points keep their order along the road. The last spline point stays at the end, so
            // the segment keeps the length its levels give it.
            let lower = index > 0 ? points[index - 1].y : 0
            let upper = index < points.count - 1 ? points[index + 1].y : (segment.kind == .spline ? 1 : .infinity)
            var y = rounded(min(max(along, lower), upper))
            if segment.kind == .spline, index == points.count - 1 { y = points[index].y }
            points[index] = RoutePoint(x: x, y: y)
            segment.points = points
            self[ref] = segment
        }
    }
}

// MARK: - Views

/// Draws the handles and segment markers over the map and drags them.
struct ControlPointOverlay: View {
    @Binding var route: RouteJSON
    @Binding var selection: SegmentRef?
    let overlay: LevelMapOverlayContext
    let spacing: CGFloat

    var body: some View {
        let context = RouteContext(width: overlay.crossSize, spacing: spacing)
        let layout = RouteHandles(route: route, context: context)
        ZStack(alignment: .topLeading) {
            ForEach(layout.markers) { marker in
                // On the side away from the road, and a little along it so the first one isn't
                // cut off at the map's edge.
                let x = marker.start.x > overlay.crossSize / 2 ? 54 : overlay.crossSize - 54
                markerTag(marker)
                    .position(overlay.location(of: CGPoint(x: x, y: marker.start.y + 14)))
            }
            ForEach(layout.handles) { handle in
                HandleDot(handle: handle, selected: handle.segment == nil || handle.segment == selection)
                    .scaleEffect(x: overlay.glyphScale.width, y: overlay.glyphScale.height)
                    .position(overlay.location(of: handle.position))
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named(LevelMapOverlayContext.coordinateSpace))
                            .onChanged { value in
                                if let segment = handle.segment { selection = segment }
                                route.drag(handle, to: overlay.routePoint(at: value.location), context: context)
                            }
                    )
            }
        }
    }

    private func markerTag(_ marker: SegmentMarker) -> some View {
        let selected = marker.ref == selection
        return Button {
            selection = marker.ref
        } label: {
            Label("\(marker.ref.section == .repeating ? "↻" : "")\(marker.ref.index + 1) \(marker.kind.rawValue)",
                  systemImage: marker.kind.symbol)
                .labelStyle(.titleOnly)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(selected ? Color.accentColor : Color.black.opacity(0.55), in: Capsule())
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .scaleEffect(x: overlay.glyphScale.width, y: overlay.glyphScale.height)
        .accessibilityLabel("Select segment \(marker.ref.index + 1), \(marker.kind.rawValue)")
    }
}

private struct HandleDot: View {
    let handle: RouteHandle
    let selected: Bool

    var body: some View {
        ZStack {
            Circle().fill(.white)
            Circle().strokeBorder(selected ? Color.accentColor : .gray, lineWidth: 4)
            if case .start = handle.target {
                Image(systemName: "flag.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(Color.accentColor)
            }
        }
        .frame(width: selected ? 26 : 18, height: selected ? 26 : 18)
        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
        // A bigger target than the dot, for fingers.
        .frame(width: 44, height: 44)
        .contentShape(Circle())
        .opacity(selected ? 1 : 0.75)
        .accessibilityLabel(label)
    }

    private var label: String {
        switch handle.target {
        case .start: "Road start"
        case let .point(_, index): "Control point \(index + 1)"
        case .straightEnd: "Straight end"
        case .detourEdge: "Detour edge"
        }
    }
}
