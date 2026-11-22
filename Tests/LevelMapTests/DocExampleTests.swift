import CoreGraphics
import Foundation
import LevelMap
import SwiftUI
import Testing

/// The code in the DocC guides, kept compiling and working.
@Suite("Documentation examples")
struct DocExampleTests {
    /// From "Designing routes".
    struct Staircase: RouteSegment {
        var levelCount: Int

        func waypoints(from start: CGPoint, in context: RouteContext) -> [RouteWaypoint] {
            let step = context.length(forLevels: levelCount) / 4
            return (1...4).map { i in
                let x = i.isMultiple(of: 2) ? context.width * 0.25 : context.width * 0.75
                return RouteWaypoint(CGPoint(x: x, y: start.y + step * CGFloat(i)), isCorner: true)
            }
        }
    }

    static let forest = LevelRoute {
        Start(x: 0.5)
        Straight(levels: 2)
        Serpentine(levels: 10, amplitude: 0.32)
        Detour(around: .leading, levels: 3)
        Zigzag(levels: 6, amplitude: 0.25, halfWaves: 2)
        Repeat { Serpentine(levels: 6, halfWaves: 2) }
    }

    @Test func generatedRoute() {
        let hasBonusLevels = true
        let route = LevelRoute {
            for world in 0..<5 {
                Serpentine(levels: 10, amplitude: world.isMultiple(of: 2) ? 0.3 : 0.4)
                Detour(around: world.isMultiple(of: 2) ? .leading : .trailing, levels: 3)
            }
            if hasBonusLevels {
                Zigzag(levels: 6)
            }
            Staircase(levelCount: 4)
        }
        let road = route.resolved(width: 390, spacing: 110)
        #expect(road.levelCount == 5 * 13 + 6 + 4)
        #expect(!road.isEndless)
    }

    @Test func forestRouteRoundTripsAndMeasures() throws {
        let data = try JSONEncoder().encode(RouteJSON(Self.forest))
        let route = try JSONDecoder().decode(RouteJSON.self, from: data).route()
        let road = route.resolved(width: 390, spacing: 110)
        #expect(road.isEndless && road.levelCount == nil)
        #expect(road.level(5_000)?.position == Self.forest.resolved(width: 390, spacing: 110).level(5_000)?.position)

        // Custom segments have no JSON form.
        #expect(throws: RouteJSON.Error.customSegment("Staircase")) {
            try RouteJSON(LevelRoute { Staircase(levelCount: 4) })
        }
    }
}

/// The README's quick start, kept compiling.
private struct ReadmeWorldScreen: View {
    @State private var current = 0

    var body: some View {
        LevelMap(EndlessLevels(), route: DocExampleTests.forest, startsAtEnd: true, current: current) { context in
            Text("\(context.index + 1)")
                .frame(width: 52, height: 52)
                .background(Circle().fill(context.state == .locked ? .gray : .orange))
        }
        .levelMapTheme(.plain)
        .levelMapAvatar { Image(systemName: "figure.walk.circle.fill").font(.largeTitle) }
    }
}

/// The quick start's "Show progress towards the next level" example, kept compiling.
private struct QuickStartWalkScreen: View {
    let current: Int
    let metresLeft: Double
    let legLength: Double

    var body: some View {
        LevelMap(0..<20, route: .serpentine(), startsAtEnd: true, current: current) { context in
            Text("\(context.index + 1)")
        }
        .levelMapProgress(toNext: 1 - metresLeft / legLength)
        .levelMapAvatar { Image(systemName: "figure.walk.circle.fill").font(.largeTitle) }
    }
}
