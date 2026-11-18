import SwiftUI
import Testing
@testable import LevelMap

@Suite("Mark placement")
struct MarkPlacementTests {
    let leading = LevelPlacement(crossFraction: 0.2, heading: .zero)
    let trailing = LevelPlacement(crossFraction: 0.8, heading: .zero)

    @Test func onRoadStaysOnTheRoad() {
        #expect(LevelMapMarkPlacement.onRoad.direction(at: leading) == 0)
        #expect(LevelMapMarkPlacement.onRoad.direction(at: trailing) == 0)
        #expect(LevelMapMarkPlacement.onRoad.spacing == 0)
    }

    @Test func outsideMovesTowardsTheNearerEdge() {
        #expect(LevelMapMarkPlacement.outside().direction(at: leading) == -1)
        #expect(LevelMapMarkPlacement.outside().direction(at: trailing) == 1)
    }

    @Test func insideMovesTowardsTheMiddle() {
        #expect(LevelMapMarkPlacement.inside().direction(at: leading) == 1)
        #expect(LevelMapMarkPlacement.inside().direction(at: trailing) == -1)
    }

    @Test(arguments: [LevelMapMarkPlacement.outside(spacing: 7), .inside(spacing: 7)])
    func besideTheRoadKeepsItsSpacing(placement: LevelMapMarkPlacement) {
        #expect(placement.spacing == 7)
    }
}
