import SwiftUI

/// Scroll identifiers for chunks and levels inside a ``LevelMap``.
enum MapItemID: Hashable {
    case chunk(Int)
    case level(Int)
}

/// Converts route coordinates (`y` along the scroll axis) to a chunk's screen coordinates.
struct ChunkFrame {
    let axis: Axis
    let crossSize: CGFloat
    let extent: CGFloat

    func point(_ point: CGPoint) -> CGPoint {
        axis == .vertical ? point : CGPoint(x: point.y, y: point.x)
    }

    var width: CGFloat { axis == .vertical ? crossSize : extent }
    var height: CGFloat { axis == .vertical ? extent : crossSize }

    /// A point `y` along the chunk, as a unit point (may fall outside 0...1).
    func unit(alongScroll y: CGFloat) -> UnitPoint {
        let fraction = extent > 0 ? y / extent : 0
        return axis == .vertical ? UnitPoint(x: 0.5, y: fraction) : UnitPoint(x: fraction, y: 0.5)
    }
}

/// One lazily created slice of the map: its scenery and level nodes.
///
/// The ground and road are drawn by ``ChunkGround`` and ``ChunkRoad`` in layers behind every
/// chunk. Each chunk draws over the one before it, so a road drawn here would cover the nodes of
/// the previous chunk wherever the road crosses the seam.
struct ChunkView<Data: LevelMapDataSource, Node: View>: View {
    @Environment(\.layoutDirection) private var layoutDirection
    let layout: ChunkLayout
    let chunk: ChunkLayout.Chunk
    let scene: ChunkScene
    let plan: ThemePlan
    let data: Data
    let frame: ChunkFrame
    /// Whether the scroll view is mirrored, so nodes and scenery must be mirrored back.
    let mirrored: Bool
    let current: Int
    /// Animates the node states when a level unlocks.
    let unlockAnimation: Animation?
    let rotorNamespace: Namespace.ID
    let node: (Data.Level, Int, LevelState, LevelPlacement) -> Node
    /// Shrinks nodes while the map is zoomed in on the avatar, so they keep their size.
    var markerScale: CGFloat = 1

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(scene.decorations, id: \.chapter) { group in
                let theme = plan.theme(forChapter: group.chapter)
                ForEach(group.decorations.indices, id: \.self) { index in
                    let placed = group.decorations[index]
                    DecorationView(decoration: theme.decorations[placed.kind], size: placed.size)
                        .scaleEffect(x: mirrorX, y: mirrorY)
                        .position(frame.point(placed.position))
                }
            }

            ForEach(chunk.levels.map { LevelEntry(index: $0, id: data.levelID(at: $0)) }) { entry in
                let index = entry.index
                if let sample = layout.localSample(ofLevel: index, in: chunk) {
                    let state = LevelState(level: index, current: current)
                    node(data.level(at: index), index, state,
                         LevelPlacement(sample: sample, crossSize: frame.crossSize, axis: frame.axis, mirrored: mirrored,
                                        layoutDirection: layoutDirection))
                        .modifier(MapDefaultAnimation(animation: unlockAnimation, value: state))
                        .accessibilityElement(children: .combine)
                        .accessibilityValue(state.accessibilityDescription)
                        .accessibilitySortPriority(-Double(index))
                        .modifier(RotorEntry(isCurrent: state == .current, id: MapItemID.level(index),
                                             namespace: rotorNamespace))
                        .scaleEffect(x: mirrorX * markerScale, y: mirrorY * markerScale)
                        .id(entry.id)
                        .position(frame.point(sample.position))
                }
            }
        }
        .frame(width: frame.width, height: frame.height, alignment: .topLeading)
    }

    private var mirrorX: CGFloat { mirrored && frame.axis == .horizontal ? -1 : 1 }
    private var mirrorY: CGFloat { mirrored && frame.axis == .vertical ? -1 : 1 }
}

/// The ground under one chunk, with chapter fades, or the outline of its road.
///
/// The map draws every chunk's ground, then every chunk's outline, so an outline never covers
/// the road its neighbour spills across the seam.
struct ChunkGround: View {
    enum Part { case ground, outline }

    let scene: ChunkScene
    let plan: ThemePlan
    let frame: ChunkFrame
    let part: Part

    var body: some View {
        ZStack(alignment: .topLeading) {
            if part == .ground {
                ground
            } else {
                outline
            }
        }
        .frame(width: frame.width, height: frame.height, alignment: .topLeading)
    }

    @ViewBuilder
    private var ground: some View {
            ForEach(scene.ground, id: \.chapter) { layer in
                let ground = plan.theme(forChapter: layer.chapter).background.view(axis: frame.axis)
                if let fade = layer.fade {
                    ground.mask {
                        LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 1)],
                                       startPoint: frame.unit(alongScroll: fade.lowerBound),
                                       endPoint: frame.unit(alongScroll: fade.upperBound))
                    }
                } else {
                    ground
                }
            }
    }

    private var outline: some View {
            ForEach(scene.road.indices, id: \.self) { index in
                let piece = scene.road[index]
                let style = plan.theme(forChapter: piece.chapter).road
                if let outline = style.outline, style.outlineWidth > 0 {
                    Path { $0.addLines(piece.points.map(frame.point)) }
                        .stroke(outline, style: StrokeStyle(lineWidth: style.width + 2 * style.outlineWidth,
                                                            lineCap: style.lineCap, lineJoin: .round,
                                                            dash: style.dash.isEmpty ? [] : style.dash.map { $0 + 2 * style.outlineWidth },
                                                            dashPhase: piece.distances.lowerBound))
                }
            }
    }
}

/// The road through one chunk: its fill, the completed stretch and the centre line.
///
/// Drawn in a layer behind every chunk's nodes, so the road never covers a level.
// Paths (not a Canvas) so strokes may spill past the chunk's edges without clipping.
struct ChunkRoad: View {
    let scene: ChunkScene
    let plan: ThemePlan
    let frame: ChunkFrame
    /// Where the completed road ends, as a distance along the whole road.
    let completed: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(scene.road.indices, id: \.self) { index in
                let piece = scene.road[index]
                let style = plan.theme(forChapter: piece.chapter).road
                let path = Path { $0.addLines(piece.points.map(frame.point)) }
                let stroke = StrokeStyle(lineWidth: style.width, lineCap: style.lineCap, lineJoin: .round,
                                         dash: style.dash, dashPhase: piece.distances.lowerBound)
                // The whole remaining road is drawn under the completed part, so dashes don't
                // crawl as the completed part grows over them.
                Group {
                    if let shader = style.shader {
                        path.stroke(shader, style: stroke)
                    } else {
                        path.stroke(style.color, style: stroke)
                    }
                }
                path.trim(from: 0, to: piece.completedFraction(upTo: completed))
                    .stroke(style.completedColor,
                            style: StrokeStyle(lineWidth: style.completedWidth ?? style.width,
                                               lineCap: style.lineCap, lineJoin: .round))
                    .shadow(color: style.completedGlow?.color ?? .clear, radius: style.completedGlow?.radius ?? 0)
                if let line = style.centerLine {
                    path.stroke(line.color, style: StrokeStyle(
                        lineWidth: line.width, lineCap: .butt, lineJoin: .round,
                        dash: line.dash, dashPhase: piece.distances.lowerBound))
                }
            }
        }
        .frame(width: frame.width, height: frame.height, alignment: .topLeading)
    }
}

struct DecorationView: View {
    let decoration: Decoration
    let size: CGFloat

    var body: some View {
        image
            .resizable()
            .scaledToFit()
            .foregroundStyle(decoration.color)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    private var image: Image {
        switch decoration.content {
        case let .symbol(name): Image(systemName: name)
        case let .image(image): image
        }
    }
}

extension MapBackground {
    @ViewBuilder
    func view(axis: Axis) -> some View {
        switch self {
        case let .color(color):
            Rectangle().fill(color)
        case let .gradient(colors):
            LinearGradient(colors: colors,
                           startPoint: axis == .vertical ? .leading : .top,
                           endPoint: axis == .vertical ? .trailing : .bottom)
        }
    }
}

/// Marks the current level's node as the target of the "Current level" rotor.
private struct RotorEntry: ViewModifier {
    let isCurrent: Bool
    let id: MapItemID
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        if isCurrent {
            content.accessibilityRotorEntry(id: id, in: namespace)
        } else {
            content
        }
    }
}

extension LevelState {
    /// Read by VoiceOver after the node's own label.
    var accessibilityDescription: Text {
        switch self {
        case .completed: Text("Completed")
        case .current: Text("Current level")
        case .locked: Text("Locked")
        }
    }
}

private struct LevelEntry: Identifiable {
    let index: Int
    let id: AnyHashable
}
