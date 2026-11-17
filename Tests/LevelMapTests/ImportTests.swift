import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import LevelMap

@Suite("Route imports")
struct ImportTests {
    // A small road that runs in rows: right, up, left, up, right.
    let rows = LevelRoute.points([CGPoint(x: 50, y: 50), CGPoint(x: 350, y: 50), CGPoint(x: 350, y: 150),
                                  CGPoint(x: 50, y: 150), CGPoint(x: 50, y: 250), CGPoint(x: 350, y: 250),
                                  CGPoint(x: 350, y: 350)], width: 400, smooth: false)

    @Test func pointsRouteKeepsItsProportionsAndPlacesLevels() throws {
        // Half the drawing's width, with no inset so the drawing's edges are kept.
        let road = rows.resolved(width: 200, spacing: 110, edgeInset: 0)
        #expect(road.levelCount == 7)
        let first = try #require(road.level(0)?.position)
        let last = try #require(road.level(6)?.position)
        #expect(abs(first.x - 25) < 0.01)
        #expect(abs(last.x - 175) < 0.01)
        // 300 drawing units along the scroll axis at half scale, regardless of spacing.
        #expect(abs((last.y - first.y) - 150) < 0.01)
        // Corners are kept: the road is 1,200 drawing units long, so levels are 200 apart. Level 1
        // is two-thirds along the first row and level 2 sits on the second turn.
        let second = try #require(road.level(1)?.position)
        let third = try #require(road.level(2)?.position)
        #expect(abs(second.x - 125) < 0.5 && abs(second.y - first.y) < 0.5)
        #expect(abs(third.x - 175) < 0.5 && abs(third.y - first.y - 50) < 0.5)
    }

    @Test func roadsThatDoubleBackStillTileIntoChunks() throws {
        // Rows that dip backwards along the scroll axis before moving on.
        let route = LevelRoute.points([CGPoint(x: 50, y: 0), CGPoint(x: 350, y: 40), CGPoint(x: 350, y: 120),
                                       CGPoint(x: 50, y: 90), CGPoint(x: 50, y: 200), CGPoint(x: 350, y: 170),
                                       CGPoint(x: 350, y: 300)], width: 400, levels: 21)
        let layout = ChunkLayout(road: route.resolved(width: 400, spacing: 110), dataCount: nil, chunkSize: 4)
        // The first level sits on the road's start, so the map adds half a spacing before it.
        var previousEnd: CGFloat = -55
        for index in 0..<layout.chunkCount! {
            let chunk = layout.chunk(index)
            #expect(chunk.extent >= 0)
            #expect(abs(chunk.origin - previousEnd) < 0.001)
            previousEnd = chunk.origin + chunk.extent
        }
        // And half a spacing after the last level, which ends the road.
        let last = try #require(layout.road.level(20)?.position.y)
        #expect(abs(previousEnd - last - 55) < 0.5)
    }

    @Test func builtInRoutesKeepHalfASpacingAtTheEnds() throws {
        let layout = ChunkLayout(road: LevelRoute { Serpentine(levels: 12, amplitude: 0.3, halfWaves: 4) }
                                    .resolved(width: 390, spacing: 110),
                                 dataCount: nil, chunkSize: 10)
        // Built-in segments already leave nearly half a slot; the map tops it up to the inset.
        #expect(layout.leadingMargin < 10)
        let first = try #require(layout.road.level(0)?.position.y)
        #expect(abs(first - layout.chunk(0).origin - 55) < 0.01)
        let last = try #require(layout.road.level(11)?.position.y)
        let lastChunk = layout.chunk(layout.chunkCount! - 1)
        #expect(abs(lastChunk.origin + lastChunk.extent - last - 55) < 0.01)
    }

    @Test func routesThatTouchTheEdgesAreScaledIn() throws {
        // Levels on both edges of a 200-point map.
        let road = rows.resolved(width: 200, spacing: 110, edgeInset: 40)
        let xs = (0..<7).compactMap { road.level($0)?.position.x }
        #expect(abs(xs.min()! - 40) < 0.5)
        #expect(abs(xs.max()! - 160) < 0.5)
        // Routes that already keep clear are left alone.
        let wave = LevelRoute { Serpentine(levels: 12, amplitude: 0.3, halfWaves: 4) }
        #expect(wave.resolved(width: 390, spacing: 110).level(3)?.position
                == wave.resolved(width: 390, spacing: 110, edgeInset: 0).level(3)?.position)
    }

    @Test func mapLeavesTheEdgeInsetBeforeTheFirstLevel() {
        let road = LevelRoute { Serpentine(levels: 12, amplitude: 0.3, halfWaves: 4) }
            .resolved(width: 390, spacing: 110, edgeInset: 90)
        let layout = ChunkLayout(road: road, dataCount: nil, chunkSize: 10)
        let first = road.level(0)!.position.y
        #expect(abs(first - layout.chunk(0).origin - 90) < 0.5)
    }

    @Test func reachNeverFallsBackAndMatchesMonotonicRoads() {
        let wave = LevelRoute.serpentine(amplitude: 0.35).resolved(width: 390, spacing: 110)
        for distance in stride(from: CGFloat(0), to: 5_000, by: 37) {
            #expect(abs(wave.reach(atDistance: distance) - wave.sample(atDistance: distance).position.y) < 0.5)
        }
        let rows = LevelRoute.points([CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 2), CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 3)],
                                     width: 1, smooth: false).resolved(width: 100, spacing: 110)
        var last: CGFloat = -.infinity
        for distance in stride(from: CGFloat(0), to: rows.length!, by: 5) {
            let reach = rows.reach(atDistance: distance)
            #expect(reach >= last - 0.001)
            #expect(reach >= rows.sample(atDistance: distance).position.y - 0.001)
            last = reach
        }
    }

    @Test func routeJSONRoundTrips() throws {
        let world = LevelRoute {
            Start(x: 0.4)
            Straight(levels: 2, toX: 0.6)
            Serpentine(levels: 10, amplitude: 0.32)
            Detour(around: .leading, levels: 3)
            Zigzag(levels: 6, amplitude: 0.25, halfWaves: 2)
            Spline(levels: 4, through: [.init(x: 0.5, y: 0), .init(x: 0.2, y: 0.5)])
            Polyline(levels: 3, points: [.init(x: 0.1, y: 0), .init(x: 0.9, y: 0.4)], smooth: false)
            Repeat { Serpentine(levels: 6, halfWaves: 2) }
        }
        let json = try RouteJSON(world)
        let data = try JSONEncoder().encode(json)
        let decoded = try JSONDecoder().decode(RouteJSON.self, from: data)
        #expect(decoded == json)
        #expect(decoded.segments.count == 6)

        let original = world.resolved(width: 390, spacing: 110)
        let rebuilt = try decoded.route().resolved(width: 390, spacing: 110)
        for level in [0, 5, 17, 25, 40, 300] {
            #expect(original.level(level)?.position == rebuilt.level(level)?.position)
        }
    }

    @Test func routeJSONRejectsBadInput() throws {
        struct Custom: RouteSegment {
            var levelCount: Int { 1 }
            func waypoints(from start: CGPoint, in context: RouteContext) -> [RouteWaypoint] { [] }
        }
        #expect(throws: RouteJSON.Error.customSegment("Custom")) { try RouteJSON(LevelRoute { Custom() }) }
        #expect(throws: RouteJSON.Error.emptySegment) {
            try RouteJSON(segments: [.straight(levels: 0, toX: nil)]).route()
        }
        #expect(throws: RouteJSON.Error.emptyRepeat) {
            try RouteJSON(segments: [], repeating: [.spline(levels: 0, points: [])]).route()
        }
        var future = RouteJSON(segments: [.straight(levels: 1, toX: nil)])
        future.version = 2
        #expect(throws: RouteJSON.Error.unsupportedVersion(2)) { try future.route() }
    }

    @Test func avatarWalksShortHopsOnly() {
        typealias Map = LevelMap<Range<Int>, EmptyView>
        #expect(Map.avatarAnimation(from: 4, to: 5, reduceMotion: false) != nil)
        #expect(Map.avatarAnimation(from: 4, to: 7, reduceMotion: false) != nil)
        #expect(Map.avatarAnimation(from: 4, to: 8, reduceMotion: false) == nil)
        #expect(Map.avatarAnimation(from: 4, to: 5, reduceMotion: true) == nil)
        #expect(Map.avatarAnimation(from: 4, to: 4, reduceMotion: false) == nil)
    }
}

