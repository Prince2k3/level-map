import SwiftUI
import Testing
@testable import LevelMap

@Suite("Bound camera positions")
struct CameraPositionTests {
    private func layout(count: Int? = nil) -> ChunkLayout {
        ChunkLayout(road: LevelRoute.serpentine().resolved(width: 390, spacing: 110),
                    dataCount: count, chunkSize: 10)
    }

    @Test func explicitLevelIsIndependentOfPlayerAndUsesFractionalArcLength() throws {
        let map = layout()
        let target = try #require(LevelMapCameraPosition.level(5030.5).resolvedLevel(in: map))
        #expect(target.index == 5030)
        #expect(target.distance == map.travelledDistance(fromLevel: 5030, progress: 0.5))
        #expect(!LevelMapCameraPosition.level(5030.5).tracksPlayer)
        #expect(LevelMapCameraPosition.automatic.tracksPlayer)
        #expect(LevelMapCameraPosition.avatar().tracksPlayer)
        #expect(LevelMapCameraPosition.avatar().followsAvatar)
    }

    @Test func finiteAndEmptyMapsResolveSafely() throws {
        let finite = layout(count: 3)
        let target = try #require(LevelMapCameraPosition.level(5000).resolvedLevel(in: finite))
        #expect(target.index == 2)
        #expect(target.distance == finite.road.distance(ofLevel: 2))
        #expect(LevelMapCameraPosition.level(2).resolvedLevel(in: layout(count: 0)) == nil)
        #expect(LevelMapCameraPosition.level(-10).level == 0)
        #expect(LevelMapCameraPosition.level(.nan).level == 0)
        #expect(LevelMapCameraPosition.level(.infinity).level == 0)
    }

    @Test func userInteractionReleasesCameraOwnership() {
        let user = LevelMapCameraPosition.userPositioned
        #expect(user.positionedByUser)
        #expect(!user.tracksPlayer)
        #expect(user.level == nil)
        #expect(!user.followsAvatar)
        #expect(!LevelMapCameraPosition.automatic.positionedByUser)
        #expect(!LevelMapCameraPosition.avatar().positionedByUser)
    }

    @Test func followConfigurationAndAnchorsAreNormalized() throws {
        let follow = try #require(LevelMapCameraPosition.avatar(zoom: 0, anchor: UnitPoint(x: -1, y: 2),
                                                                scalesMarkers: false).followConfiguration)
        #expect(follow.zoom == 1)
        #expect(follow.anchor == UnitPoint(x: 0, y: 1))
        #expect(!follow.scalesMarkers)
        #expect(LevelMapCameraPosition.avatar(zoom: .nan).followConfiguration?.zoom == 1)
    }

    @Test func boundTargetWorksWithMirroredAndHorizontalScrollCoordinates() throws {
        let map = layout(count: 50)
        let target = try #require(LevelMapCameraPosition.level(25.5).resolvedLevel(in: map))
        for screenTarget: CGFloat in [200, 400] {
            let (chunk, anchor) = map.scrollAnchor(forDistance: target.distance, nearLevel: target.index,
                                                  target: screenTarget, viewport: 600)
            let slice = map.chunk(chunk)
            let local = map.road.sample(atDistance: target.distance).position.y - slice.origin
            #expect(abs(local + anchor * (600 - slice.extent) - screenTarget) < 0.001)
        }
    }

    @Test @MainActor func boundAndAutomaticCameraInitializersCompile() {
        let binding = Binding.constant(LevelMapCameraPosition.automatic)
        _ = LevelMap(0..<100, route: .straight, current: 4, position: binding) { _ in EmptyView() }
        _ = LevelMap(0..<100, route: .straight, position: binding) { _ in EmptyView() }
        _ = LevelMap(["a", "b"][...], id: \.self, route: .straight, position: binding) { _ in EmptyView() }
        _ = LevelMap(["a", "b"][...], id: \.self, route: .straight, position: binding) { _ in EmptyView() }
        _ = LevelMap(EndlessLevels(), route: .straight) { _ in EmptyView() }
            .levelMapRecenterButton()
    }
}
