import CoreGraphics
@testable import LevelMap
import Testing

@Suite("Progress towards the next level")
struct ProgressTests {
    let road = LevelRoute.serpentine().resolved(width: 390, spacing: 110)

    @Test func interpolatesAlongTheRoad() throws {
        let start = try #require(road.distance(ofLevel: 4))
        let end = try #require(road.distance(ofLevel: 5))
        #expect(road.distance(ofLevel: 4, progress: 0) == start)
        #expect(road.distance(ofLevel: 4, progress: 1) == end)
        let half = try #require(road.distance(ofLevel: 4, progress: 0.5))
        #expect(abs(half - (start + end) / 2) < 0.001)
    }

    @Test func clampsOutOfRangeProgress() {
        #expect(road.distance(ofLevel: 4, progress: -2) == road.distance(ofLevel: 4))
        #expect(road.distance(ofLevel: 4, progress: 7) == road.distance(ofLevel: 5))
        #expect(road.distance(ofLevel: 4, progress: .nan) == road.distance(ofLevel: 4))
    }

    @Test func staysOnTheLastLevel() {
        let finite = LevelRoute { Straight(levels: 3) }.resolved(width: 390, spacing: 110)
        #expect(finite.distance(ofLevel: 2, progress: 0.5) == finite.distance(ofLevel: 2))
        #expect(finite.distance(ofLevel: 3, progress: 0.5) == nil)

        // Fewer data levels than route levels: the last shown level has no next.
        let layout = ChunkLayout(road: road, dataCount: 5, chunkSize: 10)
        #expect(layout.travelledDistance(fromLevel: 4, progress: 0.5) == road.distance(ofLevel: 4))
        #expect(layout.travelledDistance(fromLevel: 3, progress: 0.5) == road.distance(ofLevel: 3, progress: 0.5))
    }
}
