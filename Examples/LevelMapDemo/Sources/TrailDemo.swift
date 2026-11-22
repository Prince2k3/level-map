import LevelMap
import SwiftUI

/// A hiking-trail map built from the library's hooks: a dotted road that lights up with a glow,
/// terrain drawn in a layer, today's leg as a band along the road, a goal pennant, labels placed
/// by which side of the map a stop is on, and a camera that follows the walker.
struct TrailMap: View {
    let current: Int
    /// How far the walker is towards the next stop, 0–1.
    let progress: Double
    /// While walking, the map zooms in and follows the walker.
    let walking: Bool
    /// The trailhead sits at the bottom and the walk climbs up the screen.
    var startsAtEnd = true
    /// Today's goal is this many stops past where the day started.
    var legLength = 2

    @State private var dayStart: Int?
    @State private var position: LevelMapCameraPosition = .automatic

    /// The trail goes on as far as the walker does.
    private static let stops = EndlessLevels()
    private var legStart: Int { dayStart ?? current }
    private var legEnd: Int { legStart + legLength }

    var body: some View {
        LevelMap(Self.stops, route: .serpentine(amplitude: 0.34), startsAtEnd: startsAtEnd,
                 current: current, position: $position) { context in
            TrailPin(level: context.index, state: context.state,
                     labelOnLeading: context.placement.side == .trailing,
                     isGoal: context.index == legEnd)
        }
        .levelMapTheme(.trail)
        .levelMapSpacing(130)
        .levelMapEdgeInset(60)
        .levelMapLayer(.belowRoad) { map in
            TrailTerrain(map: map).equatable()
        }
        .levelMapLayer(.belowRoad) { map in
            // Today's leg, as a soft band under the road.
            map.roadPath(from: Double(legStart), to: Double(legEnd))
                .stroke(Color.trailGoal.opacity(current >= legEnd ? 0.35 : 0.22),
                        style: StrokeStyle(lineWidth: 18, lineCap: .round))
        }
        .levelMapLayer(.aboveNodes) { map in
            if map.levels.contains(legEnd), let point = map.point(atLevel: Double(legEnd)),
               let placement = map.placement(ofLevel: Double(legEnd)) {
                // On the side away from the stop's label.
                let side: CGFloat = placement.side == .trailing ? 1 : -1
                TrailPennant(isComplete: current >= legEnd)
                    .scaleEffect(1 / map.zoom)
                    .position(x: point.x + side * 46 / map.zoom, y: point.y - 22 / map.zoom)
            }
        }
        .levelMapAvatar { TrailWalker(isLive: walking) }
        .levelMapProgress(toNext: progress)
        .onChange(of: walking, initial: true) {
            position = walking ? .avatar() : .automatic
        }
        .levelMapRecenterButton { recenter in
            Button("Back to you", systemImage: "location.fill", action: recenter)
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .tint(.trailAccent)
                .accessibilityIdentifier("backToYou")
        }
        .onAppear { dayStart = current }
        // Going back (the demo's "Go to 1") starts a new day.
        .onChange(of: current) { old, new in
            if new < old {
                dayStart = new
                position = walking ? .avatar() : .automatic
            }
        }
    }
}

// MARK: - Terrain

/// Stippled ground that leaves a clear verge beside the road, and contour rings at the far edge
/// beside every other stop. Equatable on what it draws, so the walk's ticks don't redraw it.
///
/// Drawn as paths rather than a `Canvas`: a canvas is a bitmap, and one as tall as several
/// chunks, inside a map mirrored to run bottom-up, is cut off at the edge of what was on screen.
struct TrailTerrain: View, Equatable {
    let map: LevelMapGeometry

    nonisolated static func == (a: Self, b: Self) -> Bool {
        a.map.levels == b.map.levels && a.map.size == b.map.size
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<4, id: \.self) { ring in
                rings(ring).stroke(Color.trailGoal.opacity(0.12 - Double(ring) * 0.02), lineWidth: 1)
            }
            stipple.fill(.white.opacity(0.14))
        }
        .frame(width: map.size.width, height: map.size.height, alignment: .topLeading)
    }

    /// One ring of the contours beside every other stop.
    private func rings(_ ring: Int) -> Path {
        Path { path in
            let radius = 26 + CGFloat(ring) * 17
            for level in map.levels where level.isMultiple(of: 2) {
                guard let point = map.point(atLevel: Double(level)),
                      let placement = map.placement(ofLevel: Double(level)) else { continue }
                let x = placement.side == .trailing ? map.size.width * 0.07 : map.size.width * 0.93
                path.addEllipse(in: CGRect(x: x - radius, y: point.y - radius * 0.8,
                                           width: radius * 2, height: radius * 1.6))
            }
        }
    }

    private var stipple: Path {
        Path { path in
            var noise = TrailNoise(seed: 31 &+ map.levels.lowerBound)
            let spacing: CGFloat = 24
            var y: CGFloat = 8
            while y < map.size.height {
                var x = CGFloat(noise.next(0, Double(spacing)))
                while x < map.size.width {
                    let point = CGPoint(x: x + CGFloat(noise.next(-5, 5)), y: y + CGFloat(noise.next(-5, 5)))
                    if map.distanceToRoad(from: point) > 30 {
                        path.addEllipse(in: CGRect(x: point.x - 1, y: point.y - 1, width: 2, height: 2))
                    }
                    x += spacing
                }
                y += spacing
            }
        }
    }
}

private struct TrailNoise {
    var state: UInt64
    init(seed: Int) { state = UInt64(truncatingIfNeeded: seed) &* 0x9E37_79B9_7F4A_7C15 | 1 }
    mutating func next(_ lower: Double, _ upper: Double) -> Double {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return lower + Double(state % 10_000) / 10_000 * (upper - lower)
    }
}

// MARK: - Stops, walker, pennant

struct TrailPin: View {
    let level: Int
    let state: LevelState
    let labelOnLeading: Bool
    var isGoal = false

    private var isMajor: Bool { level.isMultiple(of: 5) }
    private var size: CGFloat { isMajor ? 34 : 18 }
    private var lit: Bool { state != .locked }

    var body: some View {
        ZStack {
            Circle().fill(lit ? Color.trailAccent : Color(white: 0.25))
            Circle().strokeBorder(state == .current ? .white : (lit ? .trailAccent : .gray), lineWidth: isMajor ? 2 : 1.5)
            if isMajor {
                Image(systemName: level == 0 ? "figure.hiking" : "flag.fill")
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(lit ? .white : .gray)
            } else if lit {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.48, weight: .heavy))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: lit ? Color.trailAccent.opacity(0.5) : .clear, radius: 6)
        .overlay(alignment: labelOnLeading ? .trailing : .leading) {
            VStack(alignment: labelOnLeading ? .trailing : .leading, spacing: 1) {
                Text(level == 0 ? "Trailhead" : "Stop \(level)")
                    .font(.subheadline.weight(isMajor ? .bold : .semibold))
                    .foregroundStyle(lit ? .white : Color(white: 0.7))
                Text(caption)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(state == .current ? Color.trailAccent : (isGoal ? .trailGoal : .gray))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.black.opacity(0.45), in: .rect(cornerRadius: 8))
            .fixedSize()
            .offset(x: labelOnLeading ? -(size + 10) : size + 10)
        }
    }

    private var caption: String {
        switch state {
        case .completed: "Passed"
        case .current: "You are here"
        case .locked: isGoal ? "Today's goal" : "Ahead"
        }
    }
}

struct TrailWalker: View {
    var isLive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: isLive ? "figure.walk.motion" : "figure.walk")
            .font(.system(size: 19, weight: .bold))
            .foregroundStyle(.white)
            .symbolEffect(.pulse, isActive: isLive && !reduceMotion)
            .frame(width: 42, height: 42)
            .background(Color.trailAccent, in: .circle)
            .overlay { Circle().strokeBorder(.white, lineWidth: 3) }
            .shadow(color: Color.trailAccent.opacity(0.7), radius: 10, y: 2)
    }
}

struct TrailPennant: View {
    var isComplete: Bool

    var body: some View {
        Label(isComplete ? "Goal met" : "Goal", systemImage: isComplete ? "checkmark.seal.fill" : "flag.checkered")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.black)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.trailGoal, in: .capsule)
            .shadow(color: Color.trailGoal.opacity(0.5), radius: 6)
    }
}

extension Color {
    static let trailAccent = Color(red: 0.25, green: 0.78, blue: 0.55)
    static let trailGoal = Color(red: 0.98, green: 0.80, blue: 0.35)
}

extension LevelMapTheme {
    static let trail = LevelMapTheme(
        background: .color(Color(red: 0.09, green: 0.13, blue: 0.12)),
        road: .dotted(.white.opacity(0.35), completed: .trailAccent, dotSize: 5, gap: 10))
}
