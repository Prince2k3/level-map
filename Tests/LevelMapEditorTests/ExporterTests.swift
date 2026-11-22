import CoreGraphics
import Foundation
import LevelMap
import Testing
@testable import LevelMapEditor

@Suite("Editor exports")
struct ExporterTests {
    let design = LevelMapDesign(
        name: "Forest world",
        route: RouteJSON(start: 0.4, segments: [
            .straight(levels: 2, toX: 0.6),
            .serpentine(levels: 10, amplitude: 0.32, halfWaves: 3),
            .detour(side: .trailing, levels: 3, inset: 0.12),
            .spline(levels: 7, points: [.init(x: 0.5, y: 0), .init(x: 0.15, y: 0.35),
                                        .init(x: 0.85, y: 0.7), .init(x: 0.5, y: 1)]),
            .polyline(levels: 3, points: [.init(x: 0.1, y: 0.25), .init(x: 0.9, y: 0.5)], smooth: false),
        ], repeating: [.zigzag(levels: 6, amplitude: 0.25, halfWaves: 2), .straight(levels: 1, toX: nil)]),
        spacing: 120, startsAtEnd: true, chapterLength: 20, themes: ["meadow", "desert", "snow"])

    @Test func writesSwiftSource() {
        let expected = """
        // Made with LevelMapEditor.
        import LevelMap
        import SwiftUI

        extension LevelRoute {
            static let forestWorld = LevelRoute {
                Start(x: 0.4)
                Straight(levels: 2, toX: 0.6)
                Serpentine(levels: 10, amplitude: 0.32, halfWaves: 3)
                Detour(around: .trailing, levels: 3)
                Spline(levels: 7, through: [
                    .init(x: 0.5, y: 0),
                    .init(x: 0.15, y: 0.35),
                    .init(x: 0.85, y: 0.7),
                    .init(x: 0.5, y: 1),
                ])
                Polyline(levels: 3, points: [.init(x: 0.1, y: 0.25), .init(x: 0.9, y: 0.5)], smooth: false)
                Repeat {
                    Zigzag(levels: 6, amplitude: 0.25, halfWaves: 2)
                    Straight(levels: 1)
                }
            }
        }

        extension View {
            /// Spacing and themes for `LevelRoute.forestWorld`.
            func forestWorldLook() -> some View {
                levelMapSpacing(120)
                    .levelMapChapters(every: 20) { chapter in
                        [LevelMapTheme.meadow, .desert, .snow][chapter % 3]
                    }
            }
        }

        // Usage:
        // LevelMap(levels, route: .forestWorld, startsAtEnd: true) { context in
        //     ...
        // }
        // .forestWorldLook()

        """
        #expect(LevelMapExporter.swift(design) == expected)
    }

    @Test func singleThemeAndNoRepeat() {
        var design = design
        design.route = RouteJSON(segments: [.straight(levels: 4, toX: nil)])
        design.chapterLength = nil
        design.startsAtEnd = false
        let swift = LevelMapExporter.swift(design)
        #expect(!swift.contains("Repeat"))
        #expect(swift.contains("            .levelMapTheme(.meadow)\n"))
        #expect(swift.contains("// LevelMap(levels, route: .forestWorld) {"))
        // Chapters need at least two themes.
        design.chapterLength = 10
        design.themes = ["snow"]
        #expect(LevelMapExporter.swift(design).contains(".levelMapTheme(.snow)"))
    }

    @Test func formatsNumbersAndNames() {
        #expect(LevelMapExporter.number(0.5) == "0.5")
        #expect(LevelMapExporter.number(1.0 / 3) == "0.333")
        #expect(LevelMapExporter.number(2) == "2")
        #expect(LevelMapExporter.number(-0.0001) == "0")
        #expect(LevelMapExporter.identifier("Forest world") == "forestWorld")
        #expect(LevelMapExporter.identifier("  ") == "myWorld")
        #expect(LevelMapExporter.identifier("3 peaks") == "_3Peaks")
        #expect(LevelMapExporter.identifier("snowyPass") == "snowyPass")
    }

    @Test func jsonRoundTripsAndBuildsTheSameRoute() throws {
        let text = LevelMapExporter.json(design)
        #expect(text.contains("\"version\" : 1"))
        let decoded = try JSONDecoder().decode(RouteJSON.self, from: Data(text.utf8))
        #expect(decoded == design.route)

        let original = try design.buildRoute().resolved(width: 390, spacing: 120)
        let rebuilt = try decoded.route().resolved(width: 390, spacing: 120)
        for level in [0, 9, 30, 200] {
            #expect(original.level(level)?.position == rebuilt.level(level)?.position)
        }
    }

    @Test func designsSaveAsJSON() throws {
        let data = try JSONEncoder().encode(design)
        #expect(try JSONDecoder().decode(LevelMapDesign.self, from: data) == design)
    }

    @Test func editsKeepTheRouteValid() throws {
        var route = design.route
        let added = route.append(SegmentKind.spline.template, to: .main)
        #expect(added == SegmentRef(section: .main, index: 5))
        route[added]?.addPoint()
        #expect(route[added]?.points.count == 4)
        #expect(route[added]?.points[2] == RoutePoint(x: 0.63, y: 0.83))
        route[added]?.levelCount = 0  // clamped to one level
        #expect(route[added]?.levelCount == 1)

        let moved = route.move(added, by: -1)
        #expect(moved.index == 4 && route[moved]?.kind == .spline)

        // Emptying the repeat makes the route finite rather than invalid.
        route.remove(SegmentRef(section: .repeating, index: 1))
        route.remove(SegmentRef(section: .repeating, index: 0))
        #expect(route.repeating == nil)
        #expect(throws: Never.self) { try route.route() }

        let back = route.switchSection(SegmentRef(section: .main, index: 0))
        #expect(back == SegmentRef(section: .repeating, index: 0))
        #expect(route.repeating?.first?.kind == .straight)
    }

    @Test func previewShowsThreePassesOfTheRepeat() {
        // 2 + 10 + 3 + 7 + 3 levels, then 3 × 7 repeating levels.
        #expect(design.previewLevelCount == 25 + 21)
    }
}
