import CoreGraphics
import Testing
@testable import LevelMap

@Suite("Chunk layout")
struct ChunkLayoutTests {
    let world = LevelRoute {
        Straight(levels: 3)
        Serpentine(levels: 14, amplitude: 0.35)
        Detour(around: .trailing, levels: 4)
        Repeat { Zigzag(levels: 6, halfWaves: 2) }
    }

    func layout(_ route: LevelRoute, data: Int?, chunkSize: Int = 10) -> ChunkLayout {
        ChunkLayout(road: route.resolved(width: 390, spacing: 110), dataCount: data, chunkSize: chunkSize)
    }

    @Test func countsTakeTheSmallerOfDataAndRoute() {
        let finiteRoute = LevelRoute { Serpentine(levels: 25) }
        #expect(layout(finiteRoute, data: 100).levelCount == 25)
        #expect(layout(finiteRoute, data: 7).levelCount == 7)
        #expect(layout(finiteRoute, data: nil).levelCount == 25)
        #expect(layout(world, data: 42).levelCount == 42)
        #expect(layout(world, data: nil).levelCount == nil)
        #expect(layout(world, data: nil).chunkCount == nil)
        #expect(layout(finiteRoute, data: nil).chunkCount == 3)
        #expect(layout(finiteRoute, data: 0).chunkCount == 0)
    }

    @Test func chunksCoverEveryLevelOnce() {
        let layout = layout(world, data: 95, chunkSize: 10)
        let all = (0..<layout.chunkCount!).flatMap { layout.levels(inChunk: $0) }
        #expect(all == Array(0..<95))
        #expect(layout.levels(inChunk: 9) == 90..<95)
        for level in [0, 9, 10, 57, 94] {
            #expect(layout.levels(inChunk: layout.chunkIndex(containing: level)).contains(level))
        }
    }

    @Test func chunksTileTheScrollAxisWithoutGaps() {
        let layout = layout(world, data: nil, chunkSize: 7)
        var previous = layout.chunk(0)
        #expect(previous.origin == 0)
        for index in 1..<40 {
            let chunk = layout.chunk(index)
            #expect(abs(chunk.origin - (previous.origin + previous.extent)) < 0.001)
            #expect(chunk.distances.lowerBound == previous.distances.upperBound)
            #expect(chunk.extent > 0)
            previous = chunk
        }
    }

    @Test func levelsSitInsideTheirChunk() {
        let layout = layout(world, data: nil, chunkSize: 5)
        for index in 0..<30 {
            let chunk = layout.chunk(index)
            for level in chunk.levels {
                let y = layout.localSample(ofLevel: level, in: chunk)!.position.y
                #expect(y > 0 && y < chunk.extent, "level \(level) at \(y) of \(chunk.extent)")
            }
        }
    }

    @Test func scrollAnchorCentresTheLevel() {
        let layout = layout(world, data: nil, chunkSize: 10)
        for viewport in [300.0, 640.0, 2_000.0] as [CGFloat] {
            for level in [0, 3, 4_999, 5_004] {
                let (index, anchor) = layout.scrollAnchor(forLevel: level, viewport: viewport)
                let chunk = layout.chunk(index)
                // scrollTo lines up chunk point `anchor * extent` with viewport point `anchor * viewport`.
                let chunkTopOnScreen = anchor * viewport - anchor * chunk.extent
                let levelOnScreen = chunkTopOnScreen + layout.localSample(ofLevel: level, in: chunk)!.position.y
                #expect(chunk.levels.contains(level))
                #expect(abs(levelOnScreen - viewport / 2) < 0.001)
            }
        }
    }

    @Test func lastChunkEndsWithTheRoad() throws {
        let route = LevelRoute { Serpentine(levels: 12) }
        let layout = layout(route, data: nil, chunkSize: 5)
        let road = route.resolved(width: 390, spacing: 110)
        let last = layout.chunk(2)
        #expect(last.levels == 10..<12)
        #expect(abs(last.distances.upperBound - (try #require(road.length))) < 0.001)
    }

    @Test func roadSlicesMeetAtChunkSeams() throws {
        let layout = layout(world, data: nil)
        for index in 0..<10 {
            let a = layout.chunk(index), b = layout.chunk(index + 1)
            let aEnd = try #require(layout.roadPoints(in: a, overlap: 0).last)
            let bStart = try #require(layout.roadPoints(in: b, overlap: 0).first)
            #expect(abs(aEnd.x - bStart.x) < 0.001)
            #expect(abs((aEnd.y + a.origin) - (bStart.y + b.origin)) < 0.001)
        }
    }

    @Test func farChunksAreCheap() {
        let layout = layout(world, data: nil)
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            let chunk = layout.chunk(layout.chunkIndex(containing: 1_000_000))
            #expect(chunk.levels.contains(1_000_000))
            _ = layout.roadPoints(in: chunk)
        }
        #expect(elapsed < .milliseconds(20))
    }

    @Test func levelState() {
        #expect(LevelState(level: 2, current: 5) == .completed)
        #expect(LevelState(level: 5, current: 5) == .current)
        #expect(LevelState(level: 6, current: 5) == .locked)
    }

    @Test func dataSources() {
        #expect((10..<20).levelCount == 10)
        #expect((10..<20).level(at: 3) == 13)
        #expect(["a", "b"].levelCount == 2)
        #expect(EndlessLevels().levelCount == nil)
        #expect(EndlessLevels().level(at: 42) == 42)
    }
}
