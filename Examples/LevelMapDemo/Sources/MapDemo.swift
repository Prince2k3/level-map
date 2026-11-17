import LevelMap
import SwiftUI

struct MapDemo: View {
    enum Sample: String, CaseIterable, Identifiable {
        case world = "World", serpentine = "Wave", zigzag = "Zigzag", spline = "Spline"
        /// Made in the editor tab and pasted in as `ExportedWorld.swift`.
        case exported = "Exported"
        var id: Self { self }

        var route: LevelRoute {
            switch self {
            case .world:
                LevelRoute {
                    Start(x: 0.5)
                    Straight(levels: 2)
                    Serpentine(levels: 10, amplitude: 0.32)
                    Detour(around: .leading, levels: 3)
                    Zigzag(levels: 6, amplitude: 0.25, halfWaves: 2)
                    Repeat { Serpentine(levels: 6, halfWaves: 2) }
                }
            case .serpentine: .serpentine(amplitude: 0.35)
            case .zigzag: .zigzag()
            case .spline:
                .spline([.init(x: 0.5, y: 0), .init(x: 0.15, y: 0.35), .init(x: 0.85, y: 0.7), .init(x: 0.5, y: 1)],
                        levelsPerRepeat: 7)
            case .exported: .tidewater
            }
        }

        var nodeSize: CGFloat { 52 }
    }

    enum Look: String, CaseIterable, Identifiable {
        case meadow = "Meadow", desert = "Desert", snow = "Snow", chapters = "Chapters"
        var id: Self { self }
    }

    /// Launch with `-sample Exported` (any segment title) to open on that sample.
    @State private var sample = Sample(rawValue: UserDefaults.standard.string(forKey: "sample") ?? "") ?? .world
    /// Launch with `-look Meadow` (any theme title) to open with that look.
    @State private var look = Look(rawValue: UserDefaults.standard.string(forKey: "look") ?? "") ?? .chapters
    /// `-current 0` on launch opens on that level.
    @State private var current = UserDefaults.standard.string(forKey: "current").flatMap(Int.init) ?? 4_999
    /// `-topDown` on launch puts level 1 at the top.
    @State private var startsAtEnd = !ProcessInfo.processInfo.arguments.contains("-topDown")
    // `-horizontal` on launch starts the demo in horizontal mode (handy for UI checks).
    @State private var horizontal = ProcessInfo.processInfo.arguments.contains("-horizontal")
    // A simulated walk to the next level, as if each level were a place to reach on foot.
    // `-walk` on launch starts walking.
    @State private var walking = ProcessInfo.processInfo.arguments.contains("-walk")
    @State private var metresLeft = Self.legLength
    private static let legLength = 120.0
    /// Metres walked per simulated location update. `-walkStep 5` on launch changes it.
    private static let walkStep: Double = {
        let step = UserDefaults.standard.double(forKey: "walkStep")
        return step > 0 ? step : 10
    }()
    /// `-uitest` on launch shows where the avatar is, for the UI tests. The library hides the
    /// avatar from accessibility, since VoiceOver already announces the current level.
    private static let probing = ProcessInfo.processInfo.arguments.contains("-uitest")
    @State private var probe = AvatarProbe()

    var body: some View {
        VStack(spacing: 0) {
            controls
            Group {
                if sample == .exported {
                    // Exactly what the editor's usage comment says to write.
                    map.tidewaterLook()
                } else {
                    themed(map.levelSpacing(horizontal ? 90 : 110))
                }
            }
            // Room for the avatar, which stands above its level's node, at every edge of the map.
            .levelMapEdgeInset(sample.nodeSize / 2 + 46)
            // Rebuild the map when its shape changes, so it reopens on the current level.
            .id("\(sample)-\(startsAtEnd)-\(horizontal)")
        }
        .task {
            // `-autoplay` completes a few levels on its own, for recording the README GIFs.
            guard ProcessInfo.processInfo.arguments.contains("-autoplay") else { return }
            for _ in 0..<4 {
                try? await Task.sleep(for: .seconds(1.6))
                current += 1
            }
        }
        .onChange(of: current, initial: true) { probe.current = current }
        .task(id: walking) {
            // Pretend location updates: `walkStep` metres every half second.
            while walking, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(0.5))
                guard walking else { break }
                withAnimation(.linear(duration: 0.5)) {
                    metresLeft -= Self.walkStep
                    if metresLeft <= 0 {
                        // Arrived: the next level becomes current and the next leg begins.
                        current += 1
                        metresLeft = Self.legLength
                    }
                }
            }
        }
    }

    private var map: some View {
        LevelMap(EndlessLevels(), route: sample.route,
                 axis: horizontal ? .horizontal : .vertical,
                 startsAtEnd: startsAtEnd, current: current) { [probe] _, index, state in
            LevelNode(number: index + 1, state: state, size: sample.nodeSize)
                .background {
                    if Self.probing {
                        Color.clear.onGeometryChange(for: CGPoint.self) { proxy in
                            let frame = proxy.frame(in: .global)
                            return CGPoint(x: frame.midX, y: frame.midY)
                        } action: { probe.nodes[index] = $0 }
                    }
                }
        }
        .levelMapAvatar { [probe] in
            ZStack {
                if Self.probing {
                    // Sits on the road where the avatar stands, before the image is lifted.
                    Color.clear.frame(width: 1, height: 1)
                        .onGeometryChange(for: CGPoint.self) { proxy in
                            let frame = proxy.frame(in: .global)
                            return CGPoint(x: frame.midX.rounded(), y: frame.midY.rounded())
                        } action: { probe.position = $0 }
                }
                Image(systemName: "figure.walk.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white, .indigo)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 2)
                    .offset(y: -(sample.nodeSize / 2 + 22))
            }
        }
        .levelMapProgress(toNext: 1 - metresLeft / Self.legLength)
    }

    @ViewBuilder
    private func themed(_ map: some View) -> some View {
        switch look {
        case .meadow: map.levelMapTheme(.meadow)
        case .desert: map.levelMapTheme(.desert)
        case .snow: map.levelMapTheme(.snow)
        case .chapters:
            // A new look every 20 levels; level 5,001 starts chapter 250.
            map.levelMapChapters(every: 20) { chapter in
                [LevelMapTheme.meadow, .desert, .snow][chapter % 3]
            }
            .levelMapChapterTransition(.fade(length: 260))
        }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            Picker("Route", selection: $sample) {
                ForEach(Sample.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            Picker("Theme", selection: $look) {
                ForEach(Look.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            HStack {
                Toggle("Bottom-up", isOn: $startsAtEnd)
                Toggle("Horizontal", isOn: $horizontal)
            }
            HStack {
                Button("Complete level") { current += 1; metresLeft = Self.legLength }
                Spacer()
                VStack {
                    Text("Level \(current + 1)")
                        .accessibilityIdentifier("levelLabel")
                    if walking || metresLeft < Self.legLength {
                        Text("\(Int(metresLeft)) m to go").foregroundStyle(.secondary)
                            .accessibilityIdentifier("metresLabel")
                    }
                    if Self.probing {
                        AvatarProbeLabel(probe: probe)
                    }
                }
                .monospacedDigit()
                Spacer()
                Button(walking ? "Stop" : "Walk") { walking.toggle() }
                Button("Go to 1") { current = 0; metresLeft = Self.legLength }
            }
        }
        .font(.footnote)
        .padding()
    }
}

/// Where the avatar is on screen. Only `AvatarProbeLabel` reads it, so the map isn't rebuilt
/// on every frame of the avatar's walk.
@MainActor @Observable
final class AvatarProbe {
    var position: CGPoint?
    /// The centres of the loaded nodes, by index, measured in the same frames as `position`, so
    /// the gap between the avatar and a node holds while the map scrolls.
    var nodes: [Int: CGPoint] = [:]
    /// The current level, set by the demo.
    var current = 0

    /// How far the avatar is from the current level's node.
    var gap: CGFloat? {
        guard let position, let node = nodes[current] else { return nil }
        return hypot(position.x - node.x, position.y - node.y)
    }
}

struct AvatarProbeLabel: View {
    let probe: AvatarProbe

    var body: some View {
        Text(probe.position.map { "\(Int($0.x)),\(Int($0.y))" } ?? "none")
            .font(.system(size: 8))
            .accessibilityIdentifier("avatarProbe")
        // As "level:points", tagged with the level it was measured against.
        Text(verbatim: probe.gap.map { "\(probe.current + 1):\(Int($0.rounded()))" } ?? "none")
            .font(.system(size: 8))
            .accessibilityIdentifier("avatarGap")
    }
}

struct LevelNode: View {
    let number: Int
    let state: LevelState
    var size: CGFloat = 52

    var body: some View {
        Text("\(number)")
            .font(.system(size: (number > 999 ? 13 : 16) * size / 52, weight: .bold).monospacedDigit())
            .foregroundStyle(state == .locked ? Color(white: 0.45) : .white)
            .frame(width: size, height: size)
            .background {
                Circle()
                    .fill(fill)
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 2)
            }
            .overlay {
                if state == .current {
                    Circle().stroke(.white, lineWidth: 4 * size / 52).padding(-6 * size / 52)
                }
            }
    }

    private var fill: Color {
        switch state {
        case .completed: .orange
        case .current: .pink
        case .locked: Color(white: 0.9)
        }
    }
}

// MARK: - Themes (SF Symbols and gradients only)

extension LevelMapTheme {
    static let meadow = LevelMapTheme(
        background: .gradient([Color(red: 0.47, green: 0.74, blue: 0.38),
                               Color(red: 0.58, green: 0.82, blue: 0.45),
                               Color(red: 0.47, green: 0.74, blue: 0.38)]),
        road: RoadStyle(width: 28,
                        color: Color(red: 0.94, green: 0.87, blue: 0.66),
                        completedColor: Color(red: 0.99, green: 0.74, blue: 0.32),
                        outline: Color(red: 0.62, green: 0.48, blue: 0.30), outlineWidth: 3),
        decorations: [
            .symbol("tree.fill", color: Color(red: 0.18, green: 0.48, blue: 0.24), size: 30...46, weight: 3),
            .symbol("leaf.fill", color: Color(red: 0.30, green: 0.60, blue: 0.28), size: 14...20, weight: 2),
            .symbol("camera.macro", color: Color(red: 0.96, green: 0.45, blue: 0.62), size: 14...20, weight: 2),
        ],
        decorationDensity: 0.7, seed: 1)

    static let desert = LevelMapTheme(
        background: .gradient([Color(red: 0.93, green: 0.78, blue: 0.52),
                               Color(red: 0.97, green: 0.86, blue: 0.62),
                               Color(red: 0.93, green: 0.78, blue: 0.52)]),
        road: RoadStyle(width: 26,
                        color: Color(red: 0.72, green: 0.52, blue: 0.34),
                        completedColor: Color(red: 0.88, green: 0.38, blue: 0.20),
                        centerLine: .init(color: Color(red: 0.98, green: 0.92, blue: 0.78), width: 3, dash: [10, 12])),
        decorations: [
            .symbol("mountain.2.fill", color: Color(red: 0.76, green: 0.56, blue: 0.36), size: 34...52, weight: 2),
            .symbol("triangle.fill", color: Color(red: 0.85, green: 0.66, blue: 0.40), size: 20...32, weight: 2),
            .symbol("circle.fill", color: Color(red: 0.70, green: 0.60, blue: 0.50), size: 6...10, weight: 3),
            .symbol("sun.max.fill", color: Color(red: 0.98, green: 0.70, blue: 0.20), size: 22...28, weight: 0.3),
        ],
        decorationDensity: 0.55, seed: 2)

    static let snow = LevelMapTheme(
        background: .gradient([Color(red: 0.82, green: 0.89, blue: 0.96),
                               Color(red: 0.95, green: 0.97, blue: 1.00),
                               Color(red: 0.82, green: 0.89, blue: 0.96)]),
        road: RoadStyle(width: 26,
                        color: Color(red: 0.70, green: 0.80, blue: 0.90),
                        completedColor: Color(red: 0.30, green: 0.62, blue: 0.95),
                        outline: Color(red: 0.45, green: 0.56, blue: 0.70), outlineWidth: 2),
        decorations: [
            .symbol("tree.fill", color: Color(red: 0.16, green: 0.40, blue: 0.42), size: 28...42, weight: 3),
            .symbol("snowflake", color: Color(red: 0.55, green: 0.72, blue: 0.92), size: 12...20, weight: 2),
            .symbol("mountain.2.fill", color: Color(red: 0.62, green: 0.70, blue: 0.80), size: 34...50, weight: 1),
        ],
        decorationDensity: 0.6, seed: 3)
}
