import CoreGraphics
import LevelMap
import Testing
@testable import LevelMapEditor

@Suite("Editor handles")
struct HandleTests {
    let context = RouteContext(width: 400, spacing: 100)
    let route = RouteJSON(start: 0.5, segments: [
        .straight(levels: 2, toX: 0.25),
        .spline(levels: 4, points: [.init(x: 0.2, y: 0.5), .init(x: 0.8, y: 1)]),
        .detour(side: .trailing, levels: 3, inset: 0.1),
    ], repeating: [.polyline(levels: 2, points: [.init(x: 0.3, y: 1), .init(x: 0.7, y: 2)], smooth: true)])

    @Test func handlesSitWhereTheRoadGoes() throws {
        let layout = RouteHandles(route: route, context: context)
        #expect(layout.markers.map(\.kind) == [.straight, .spline, .detour, .polyline])
        #expect(layout.handles.first?.position == CGPoint(x: 200, y: 0))

        let straightEnd = try #require(layout.handles.first { $0.target == .straightEnd(SegmentRef(section: .main, index: 0)) })
        #expect(straightEnd.position.x == 100)

        // The spline starts where the straight ends and its points are fractions of its length.
        let splineRef = SegmentRef(section: .main, index: 1)
        let first = try #require(layout.handles.first { $0.target == .point(splineRef, 0) })
        #expect(first.segmentStart == straightEnd.position)
        #expect(first.position.x == 80)
        let length = context.length(forLevels: 4)
        #expect(abs(first.position.y - (straightEnd.position.y + length * 0.5)) < 0.001)

        let edge = try #require(layout.handles.first { $0.target == .detourEdge(SegmentRef(section: .main, index: 2)) })
        #expect(abs(edge.position.x - 360) < 0.001)

        // The repeating polyline gets handles too, on its first pass.
        #expect(layout.handles.contains { $0.target == .point(SegmentRef(section: .repeating, index: 0), 1) })
    }

    @Test func draggingUpdatesTheRoute() throws {
        var route = route
        let layout = RouteHandles(route: route, context: context)
        func handle(_ target: RouteHandle.Target) throws -> RouteHandle {
            try #require(layout.handles.first { $0.target == target })
        }

        route.drag(try handle(.start), to: CGPoint(x: 123, y: 999), context: context)
        #expect(route.start == 0.31)

        let straight = SegmentRef(section: .main, index: 0)
        route.drag(try handle(.straightEnd(straight)), to: CGPoint(x: -50, y: 0), context: context)
        #expect(route[straight] == .straight(levels: 2, toX: 0))

        let detour = SegmentRef(section: .main, index: 2)
        route.drag(try handle(.detourEdge(detour)), to: CGPoint(x: 340, y: 0), context: context)
        #expect(route[detour] == .detour(side: .trailing, levels: 3, inset: 0.15))
        route.drag(try handle(.detourEdge(detour)), to: CGPoint(x: 0, y: 0), context: context)
        #expect(route[detour] == .detour(side: .trailing, levels: 3, inset: 0.5))

        // A spline point can't pass the next one, and the last point stays at the end.
        let spline = SegmentRef(section: .main, index: 1)
        let point = try handle(.point(spline, 0))
        route.drag(point, to: CGPoint(x: 300, y: point.segmentStart.y + 10_000), context: context)
        #expect(route[spline]?.points == [.init(x: 0.75, y: 1), .init(x: 0.8, y: 1)])
        let last = try handle(.point(spline, 1))
        route.drag(last, to: CGPoint(x: 400, y: 0), context: context)
        #expect(route[spline]?.points.last == .init(x: 1, y: 1))

        // Polyline points are measured in map widths.
        let poly = SegmentRef(section: .repeating, index: 0)
        let polyPoint = try handle(.point(poly, 1))
        route.drag(polyPoint, to: CGPoint(x: 200, y: polyPoint.segmentStart.y + 1000), context: context)
        #expect(route[poly]?.points.last == .init(x: 0.5, y: 2.5))
        #expect(throws: Never.self) { try route.route() }
    }
}
