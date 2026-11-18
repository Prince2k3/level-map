import CoreGraphics
import SwiftUI
import Testing
@testable import LevelMap

@Suite("Map geometry")
struct MapGeometryTests {
    let layout = ChunkLayout(road: LevelRoute { Serpentine(levels: 30, amplitude: 0.35) }
                                .resolved(width: 390, spacing: 110),
                             dataCount: nil, chunkSize: 10)

    /// A layer over chunks 0 and 1, laid out from the top of the content.
    func geometry(mirrored: Bool = false, axis: Axis = .vertical) -> LevelMapGeometry {
        let first = layout.chunk(0), second = layout.chunk(1)
        let extent = first.extent + second.extent
        let size = axis == .vertical ? CGSize(width: 390, height: extent) : CGSize(width: extent, height: 390)
        return LevelMapGeometry(size: size, axis: axis, layout: layout, levels: 0..<20,
                                originAlong: first.origin, mirrored: mirrored, zoom: 1)
    }

    @Test func pointsLandOnTheLevels() throws {
        let map = geometry()
        for level in [0, 5, 13] {
            let sample = try #require(layout.road.level(level))
            let point = try #require(map.point(atLevel: Double(level)))
            #expect(abs(point.x - sample.position.x) < 0.01)
            #expect(abs(point.y - (sample.position.y - layout.chunk(0).origin)) < 0.01)
        }
    }

    @Test func fractionalLevelsFallBetweenLevels() throws {
        let map = geometry()
        let start = try #require(layout.road.distance(ofLevel: 4))
        let end = try #require(layout.road.distance(ofLevel: 5))
        let expected = layout.road.sample(atDistance: (start + end) / 2).position
        let point = try #require(map.point(atLevel: 4.5))
        #expect(abs(point.x - expected.x) < 0.01)
        #expect(abs(point.y - (expected.y - layout.chunk(0).origin)) < 0.01)
    }

    @Test func mirroredMapsFlipAlongTheAxis() throws {
        let plain = geometry(), mirrored = geometry(mirrored: true)
        let a = try #require(plain.point(atLevel: 3)), b = try #require(mirrored.point(atLevel: 3))
        #expect(abs(a.x - b.x) < 0.01)
        #expect(abs(b.y - (plain.size.height - a.y)) < 0.01)
    }

    @Test func horizontalMapsSwapAxes() throws {
        let vertical = geometry(), horizontal = geometry(axis: .horizontal)
        let a = try #require(vertical.point(atLevel: 7)), b = try #require(horizontal.point(atLevel: 7))
        #expect(abs(a.x - b.y) < 0.01)
        #expect(abs(a.y - b.x) < 0.01)
    }

    @Test func roadPathRunsBetweenPositions() throws {
        let map = geometry()
        let path = map.roadPath(from: 2, to: 3)
        let start = try #require(map.point(atLevel: 2)), end = try #require(map.point(atLevel: 3))
        #expect(!path.isEmpty)
        #expect(path.boundingRect.insetBy(dx: -1, dy: -1).contains(start))
        #expect(path.boundingRect.insetBy(dx: -1, dy: -1).contains(end))
        // Reversed arguments give the same stretch.
        #expect(map.roadPath(from: 3, to: 2).boundingRect == path.boundingRect)
    }

    @Test func distanceToRoadIsZeroOnTheRoad() throws {
        let map = geometry()
        let onRoad = try #require(map.point(atLevel: 6.3))
        #expect(map.distanceToRoad(from: onRoad) < 4)
        #expect(map.distanceToRoad(from: CGPoint(x: onRoad.x + 300, y: onRoad.y)) > 50)
    }

    @Test func placementMatchesTheSideOfTheMap() throws {
        let map = geometry()
        for level in 0..<20 {
            let sample = try #require(layout.road.level(level))
            let placement = try #require(map.placement(ofLevel: Double(level)))
            #expect(abs(placement.crossFraction - sample.position.x / 390) < 0.001)
            #expect(placement.side == (sample.position.x > 195 ? .trailing : .leading))
        }
    }

    @Test func headingPointsTowardsTheNextLevel() throws {
        let map = geometry()
        let heading = try #require(map.heading(atLevel: 4))
        let here = try #require(map.point(atLevel: 4)), ahead = try #require(map.point(atLevel: 4.05))
        let direction = atan2(ahead.y - here.y, ahead.x - here.x)
        #expect(abs(heading.radians - Double(direction)) < 0.1)
        // Mirroring flips which way the road runs up the screen.
        let flipped = try #require(geometry(mirrored: true).heading(atLevel: 4))
        #expect(abs(sin(flipped.radians) + sin(heading.radians)) < 0.01)
    }

    @Test func positionsBeforeTheStartAndPastTheEnd() throws {
        let finite = ChunkLayout(road: LevelRoute { Serpentine(levels: 5) }.resolved(width: 390, spacing: 110),
                                 dataCount: nil, chunkSize: 10)
        let map = LevelMapGeometry(size: CGSize(width: 390, height: finite.chunk(0).extent), axis: .vertical,
                                   layout: finite, levels: 0..<5, originAlong: finite.chunk(0).origin,
                                   mirrored: false, zoom: 1)
        let first = try #require(map.point(atLevel: 0)), before = try #require(map.point(atLevel: -0.5))
        #expect(before.y < first.y)
        let last = try #require(map.point(atLevel: 4)), past = try #require(map.point(atLevel: 4.5))
        #expect(past.y > last.y)
        #expect(map.point(atLevel: .nan) == nil)
    }
}

@Suite("Follow scrolling")
struct FollowScrollTests {
    let layout = ChunkLayout(road: LevelRoute { Serpentine(levels: 40, amplitude: 0.35) }
                                .resolved(width: 390, spacing: 110),
                             dataCount: nil, chunkSize: 10)

    @Test func contentExtentAddsUpTheChunks() throws {
        let extent = try #require(layout.contentExtent)
        let sum = (0..<4).map { layout.chunk($0).extent }.reduce(0, +)
        #expect(abs(extent - sum) < 0.01)
        let endless = ChunkLayout(road: LevelRoute { Repeat { Serpentine(levels: 4) } }.resolved(width: 390, spacing: 110),
                                  dataCount: nil, chunkSize: 10)
        #expect(endless.contentExtent == nil)
    }

    @Test func contentPositionStartsAtTheFirstChunk() {
        #expect(layout.contentPosition(ofRouteY: layout.chunk(0).origin) == 0)
        #expect(abs(layout.contentPosition(ofRouteY: layout.chunk(2).origin)
                    - layout.chunk(0).extent - layout.chunk(1).extent) < 0.01)
    }

    /// `scrollTo(anchor:)` lines up the anchor of the chunk with the same point of the viewport.
    func screenPosition(ofDistance distance: CGFloat, chunk: Int, anchor: CGFloat, viewport: CGFloat) -> CGFloat {
        let chunk = layout.chunk(chunk)
        let y = layout.road.sample(atDistance: distance).position.y - chunk.origin
        return anchor * viewport - anchor * chunk.extent + y
    }

    @Test func scrollAnchorPutsADistanceAtTheTarget() throws {
        let viewport: CGFloat = 700
        for (level, target) in [(5, 350.0), (12, 200.0), (25, 520.0)] {
            let start = try #require(layout.road.distance(ofLevel: level))
            let distance = start + 40
            let (chunk, anchor) = layout.scrollAnchor(forDistance: distance, nearLevel: level,
                                                      target: target, viewport: viewport)
            #expect(abs(screenPosition(ofDistance: distance, chunk: chunk, anchor: anchor, viewport: viewport) - target) < 0.01)
        }
    }

    @Test func scrollAnchorFindsTheChunkFromAWrongHint() throws {
        let distance = try #require(layout.road.distance(ofLevel: 25))
        let (chunk, _) = layout.scrollAnchor(forDistance: distance, nearLevel: 3, target: 300, viewport: 700)
        #expect(chunk == 2)
    }

    @Test func distanceAnchorMatchesTheLevelAnchorAtTheCentre() throws {
        let distance = try #require(layout.road.distance(ofLevel: 14))
        let byLevel = layout.scrollAnchor(forLevel: 14, viewport: 700)
        let byDistance = layout.scrollAnchor(forDistance: distance, nearLevel: 14, target: 350, viewport: 700)
        #expect(byLevel.chunk == byDistance.chunk)
        #expect(abs(byLevel.anchor - byDistance.anchor) < 0.001)
    }
}

@Suite("Road style")
struct RoadStyleTests {
    @Test func dottedRoadIsRoundAndDashed() {
        let style = RoadStyle.dotted(.white, completed: .green, dotSize: 6, gap: 14)
        #expect(style.lineCap == .round)
        #expect(style.dash == [0, 14])
        #expect(style.width == 6)
        #expect(style.completedWidth == 6)
        #expect(style.completedGlow != nil)
        #expect(RoadStyle.dotted(.white, completed: .green, glow: 0).completedGlow == nil)
    }

    @Test func defaultsKeepTheSolidRoad() {
        let style = RoadStyle()
        #expect(style.lineCap == .butt)
        #expect(style.dash.isEmpty)
        #expect(style.completedWidth == nil)
        #expect(style.completedGlow == nil)
    }
}
