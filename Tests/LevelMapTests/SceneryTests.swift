import CoreGraphics
import SwiftUI
import Testing
@testable import LevelMap

@Suite("Seeded random")
struct SeededRandomTests {
    @Test func matchesTheSplitMix64ReferenceSequence() {
        var random = SeededRandom(seed: 0)
        #expect(random.next() == 0xE220_A839_7B1D_CDAF)
        #expect(random.next() == 0x6E78_9E6A_A1B9_65F4)
        #expect(random.next() == 0x06C4_5D18_8009_454F)
    }

    @Test func unitValuesStayInRange() {
        var random = SeededRandom(seed: 42)
        for _ in 0..<10_000 {
            let value = random.unit()
            #expect(value >= 0 && value < 1)
        }
    }

    @Test func seedsMixEveryValue() {
        #expect(SeededRandom.seed(0, 1, 2) == SeededRandom.seed(0, 1, 2))
        #expect(SeededRandom.seed(0, 1, 2) != SeededRandom.seed(0, 2, 1))
        #expect(SeededRandom.seed(0, 1) != SeededRandom.seed(1, 1))
        #expect(SeededRandom.seed(0, 0) != SeededRandom.seed(0, 1))
    }
}

@Suite("Scenery")
struct SceneryTests {
    let decorations: [Decoration] = [
        .symbol("tree.fill", color: .green, size: 24...40, weight: 3),
        .symbol("leaf.fill", color: .green, size: 14...20),
    ]
    let area = CGRect(x: 0, y: 0, width: 390, height: 1_100)
    /// A road straight down the middle.
    var road: [CGPoint] { stride(from: -50.0, through: 1_150, by: 5).map { CGPoint(x: 195, y: $0) } }

    func scatter(seed: UInt64) -> [PlacedDecoration] {
        Scenery.scatter(decorations, density: 0.8, in: area, avoiding: road, keepOut: 43, seed: seed)
    }

    @Test func sameSeedGivesTheSameScenery() {
        let first = scatter(seed: 7)
        #expect(!first.isEmpty)
        #expect(first == scatter(seed: 7))
        #expect(first != scatter(seed: 8))
    }

    @Test func decorationsStayInsideClearOfTheRoadAndApart() {
        let placed = scatter(seed: 3)
        // Roughly the requested density, less what the road and crowding reject.
        #expect(placed.count > 10)
        #expect(placed.count <= Int((390 * 1_100 / 10_000 * 0.8).rounded()))
        for (index, item) in placed.enumerated() {
            let radius = item.size / 2
            #expect(area.insetBy(dx: radius - 0.001, dy: radius - 0.001).contains(item.position))
            #expect(abs(item.position.x - 195) >= 43 + radius - 0.001)
            #expect(decorations[item.kind].size.contains(item.size))
            for other in placed[(index + 1)...] {
                #expect(item.position.distance(to: other.position) >= (radius + other.size / 2) * 0.9 - 0.001)
            }
        }
    }

    @Test func emptyInputsPlaceNothing() {
        #expect(Scenery.scatter([], density: 1, in: area, avoiding: road, keepOut: 10, seed: 1).isEmpty)
        #expect(Scenery.scatter(decorations, density: 0, in: area, avoiding: road, keepOut: 10, seed: 1).isEmpty)
        #expect(Scenery.scatter(decorations, density: 1, in: .zero, avoiding: road, keepOut: 10, seed: 1).isEmpty)
    }

    @Test func distanceToPolylineMeasuresToSegments() {
        let line = [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 100)]
        #expect(Scenery.distanceSquared(from: CGPoint(x: 30, y: 50), to: line) == 900)
        #expect(Scenery.distanceSquared(from: CGPoint(x: 0, y: 130), to: line) == 900)
        #expect(Scenery.distanceSquared(from: .zero, to: []) == .infinity)
    }
}

@Suite("Chunk scene")
struct ChunkSceneTests {
    let route = LevelRoute.serpentine(amplitude: 0.3)

    func layout(data: Int? = nil, chunkSize: Int = 10) -> ChunkLayout {
        ChunkLayout(road: route.resolved(width: 390, spacing: 110), dataCount: data, chunkSize: chunkSize)
    }

    static func theme(_ chapter: Int) -> LevelMapTheme {
        LevelMapTheme(background: .color(.green), road: RoadStyle(width: 20 + CGFloat(chapter)),
                      decorations: [.symbol("tree.fill", color: .green)], seed: 0)
    }

    func chapters(every length: Int, fade: CGFloat = 200) -> ThemePlan {
        ThemePlan(base: .plain, chapters: LevelMapChapters(every: length, theme: Self.theme),
                  transition: .fade(length: fade))
    }

    @Test func sceneryIsTheSameEveryTime() {
        let layout = layout()
        let plan = chapters(every: 25)
        for index in [0, 3, 499] {
            let chunk = layout.chunk(index)
            let a = ChunkScene(layout: layout, chunk: chunk, plan: plan, crossSize: 390)
            let b = ChunkScene(layout: layout, chunk: chunk, plan: plan, crossSize: 390)
            #expect(a.decorations.map(\.decorations) == b.decorations.map(\.decorations))
            #expect(a.decorations.allSatisfy { !$0.decorations.isEmpty })
        }
    }

    @Test func oneThemeMeansOnePieceAndOneGround() {
        let layout = layout()
        let scene = ChunkScene(layout: layout, chunk: layout.chunk(4), plan: ThemePlan(base: Self.theme(0)), crossSize: 390)
        #expect(scene.road.count == 1)
        #expect(scene.ground == [.init(chapter: 0, fade: nil)])
        #expect(scene.decorations.map(\.chapter) == [0])
    }

    @Test func chapterBoundarySplitsRoadGroundAndScenery() {
        let layout = layout()
        // Chapters of 25 levels: chunk 2 (levels 20..<30) holds the start of chapter 1 at level 25.
        let chunk = layout.chunk(2)
        let scene = ChunkScene(layout: layout, chunk: chunk, plan: chapters(every: 25), crossSize: 390)
        #expect(scene.road.map(\.chapter) == [0, 1])
        #expect(scene.decorations.map(\.chapter) == [0, 1])
        #expect(scene.ground.map(\.chapter) == [0, 1])

        let boundary = layout.boundaryDistance(beforeLevel: 25)
        #expect(abs(scene.road[1].distances.lowerBound - boundary) < 0.001)
        let boundaryY = layout.road.sample(atDistance: boundary).position.y - chunk.origin
        let fade = try! #require(scene.ground[1].fade)
        #expect(abs(fade.lowerBound - (boundaryY - 100)) < 0.001)
        #expect(abs(fade.upperBound - (boundaryY + 100)) < 0.001)
    }

    @Test func fadeReachesIntoTheNeighbouringChunks() {
        let layout = layout()
        // Chapter 1 starts at level 20, the first level of chunk 2. Chunk 1 sees the fade begin; chunk 2
        // starts with chapter 0's ground underneath and fades to chapter 1.
        let plan = chapters(every: 20, fade: 400)
        let before = ChunkScene(layout: layout, chunk: layout.chunk(1), plan: plan, crossSize: 390)
        let after = ChunkScene(layout: layout, chunk: layout.chunk(2), plan: plan, crossSize: 390)
        #expect(before.ground.map(\.chapter) == [0, 1])
        #expect(after.ground.map(\.chapter) == [0, 1])
        #expect(before.road.map(\.chapter) == [0, 1]) // the 1-point overlap crosses the boundary
        #expect(after.decorations.map(\.chapter) == [1])
    }

    @Test func completedFractionFollowsTheCurrentLevel() {
        let layout = layout()
        let chunk = layout.chunk(1)
        let piece = ChunkScene(layout: layout, chunk: chunk, plan: ThemePlan(base: .plain), crossSize: 390).road[0]
        #expect(piece.completedFraction(upTo: 0) == 0)
        #expect(piece.completedFraction(upTo: .infinity) == 1)
        let middle = layout.road.distance(ofLevel: 15)!
        let fraction = piece.completedFraction(upTo: middle)
        #expect(fraction > 0.4 && fraction < 0.6)
    }

    @Test func decorationsAvoidTheRoadNearChunkEdges() {
        let layout = layout()
        let theme = LevelMapTheme(background: .color(.green), decorations: [.symbol("tree.fill", color: .green)],
                                  decorationDensity: 3, roadClearance: 30)
        for index in 0..<6 {
            let chunk = layout.chunk(index)
            let scene = ChunkScene(layout: layout, chunk: chunk, plan: ThemePlan(base: theme), crossSize: 390)
            let road = layout.roadPoints(from: 0, to: layout.chunk(index + 2).distances.upperBound, step: 2,
                                         origin: chunk.origin)
            for placed in scene.decorations.flatMap(\.decorations) {
                let gap = Scenery.distanceSquared(from: placed.position, to: road).squareRoot()
                #expect(gap >= theme.road.width / 2 + theme.roadClearance + placed.size / 2 - 1)
                #expect(placed.position.y - placed.size / 2 >= -0.001)
                #expect(placed.position.y + placed.size / 2 <= chunk.extent + 0.001)
            }
        }
    }
}
