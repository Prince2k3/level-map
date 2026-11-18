import CoreGraphics
import Testing
@testable import LevelMap

@Suite("Road distance index")
struct RoadDistanceIndexTests {
    private static let road: [CGPoint] = (0...120).map { step in
        let y = CGFloat(step) * 6
        return CGPoint(x: 180 + 120 * sin(y / 70), y: y)
    }

    @Test(arguments: [
        CGPoint(x: 0, y: 0), CGPoint(x: 180, y: 300), CGPoint(x: 400, y: 50),
        CGPoint(x: -300, y: 900), CGPoint(x: 260, y: 721), CGPoint(x: 90, y: 444),
    ])
    func matchesAScanOfTheWholeRoad(point: CGPoint) {
        let index = RoadDistanceIndex { Self.road }
        let expected = Scenery.distanceSquared(from: point, to: Self.road).squareRoot()
        #expect(abs(index.distance(from: point) - expected) < 0.001)
    }

    @Test func emptyRoadIsInfinitelyFar() {
        #expect(RoadDistanceIndex { [] }.distance(from: .zero) == .infinity)
    }

    @Test func singlePointRoadIsThatPoint() {
        #expect(RoadDistanceIndex { [CGPoint(x: 3, y: 4)] }.distance(from: .zero) == 5)
    }
}
