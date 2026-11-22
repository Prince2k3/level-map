import SwiftUI
import Testing
@testable import LevelMap

@Suite("API audit regressions")
struct APIRegressionTests {
    @Test @MainActor func disablingImplicitAnimationPreservesExplicitCallerAnimation() {
        let context = MapAnimationContext()
        var transaction = Transaction(animation: .linear(duration: 2))
        transaction.disablesAnimations = true
        transaction.isContinuous = true
        context.transaction = transaction
        let result = context.resolved(fallback: .spring(), reduceMotion: false)
        #expect(result.animation == transaction.animation)
        #expect(result.disablesAnimations)
        #expect(result.isContinuous)
    }

    @Test @MainActor func disabledTransactionWithoutExplicitAnimationStaysUnanimated() {
        let context = MapAnimationContext()
        context.transaction.disablesAnimations = true
        #expect(context.resolved(fallback: .spring(), reduceMotion: false).animation == nil)
    }

    @Test @MainActor func reduceMotionStillSuppressesExplicitAndFallbackAnimations() {
        let context = MapAnimationContext()
        context.transaction.animation = .linear(duration: 2)
        #expect(context.resolved(fallback: .spring(), reduceMotion: true).animation == nil)
        context.transaction.animation = nil
        #expect(context.resolved(fallback: .spring(), reduceMotion: true).animation == nil)
    }

    @Test @MainActor func callerAndCompatibilityDefaultsKeepTheirPrecedence() {
        let context = MapAnimationContext()
        #expect(context.resolved(fallback: .spring(), reduceMotion: false).animation == .spring())
        context.transaction.animation = .linear(duration: 2)
        #expect(context.resolved(fallback: .spring(), reduceMotion: false).animation == .linear(duration: 2))
    }

    @Test @MainActor func repeatedUserEventsReleaseBoundCameraOnlyOnce() {
        let state = CameraState()
        let binding = Binding(get: { state.position }, set: { state.position = $0; state.writes += 1 })
        // Drag, wheel and accessibility event sources all use this ownership path.
        for _ in 0..<3 { LevelMapCameraPosition.userDidScroll(binding, isFollowing: false) }
        #expect(state.position.positionedByUser)
        #expect(!state.position.tracksPlayer)
        #expect(state.writes == 1)
        state.position = .automatic
        LevelMapCameraPosition.userDidScroll(binding, isFollowing: false)
        #expect(state.writes == 2)
        LevelMapCameraPosition.userDidScroll(nil, isFollowing: false)
    }

    @Test @MainActor func followingStillLocksManualCameraChanges() {
        let state = CameraState()
        state.position = .avatar()
        let binding = Binding(get: { state.position }, set: { state.position = $0; state.writes += 1 })
        LevelMapCameraPosition.userDidScroll(binding, isFollowing: true)
        #expect(state.position.followsAvatar)
        #expect(state.writes == 0)
    }

    @Test @MainActor func nativeScrollPhasesDoNotMistakeProgrammaticAnimationForUserInput() {
        if #available(macOS 15, visionOS 2, *) {
            #expect(CameraUserInteraction.isUserScroll(.interacting))
            #expect(CameraUserInteraction.isUserScroll(.decelerating))
            #expect(!CameraUserInteraction.isUserScroll(.animating))
            #expect(!CameraUserInteraction.isUserScroll(.idle))
            #expect(!CameraUserInteraction.isUserScroll(.tracking))
        }
    }

    #if os(macOS)
    @Test @MainActor func legacyWheelRoutingAcceptsBothAxesOnlyInsideTheMap() {
        let bounds = CGRect(x: 0, y: 0, width: 300, height: 500)
        #expect(LegacyWheelObserver.WheelView.acceptsScroll(at: CGPoint(x: 100, y: 100), in: bounds,
                                                           delta: CGSize(width: 0, height: 5)))
        #expect(LegacyWheelObserver.WheelView.acceptsScroll(at: CGPoint(x: 100, y: 100), in: bounds,
                                                           delta: CGSize(width: -5, height: 0)))
        #expect(!LegacyWheelObserver.WheelView.acceptsScroll(at: CGPoint(x: 100, y: -10), in: bounds,
                                                            delta: CGSize(width: 0, height: 5)))
        #expect(!LegacyWheelObserver.WheelView.acceptsScroll(at: CGPoint(x: 100, y: 100), in: bounds, delta: .zero))
    }
    #endif

    @Test func accessibilityPagingMovesTheExistingViewportInEitherDirection() throws {
        let snapshot = CameraScrollSnapshot(index: 4, origin: -100, extent: 1100)
        for direction: CGFloat in [-1, 1] {
            let anchor = try #require(snapshot.pageAnchor(direction: direction, viewport: 600))
            let after = anchor * (600 - snapshot.extent)
            #expect(abs(after - (snapshot.origin - direction * 600 * 0.8)) < 0.001)
        }
        #expect(CameraScrollSnapshot(index: 4, origin: 0, extent: 600)
            .pageAnchor(direction: 1, viewport: 600) == nil)
    }

    @Test @MainActor func overlappingMarginsUseTheModifierClosestToTheView() throws {
        for direction in [LayoutDirection.leftToRight, .rightToLeft] {
            let recorder = MarginRecorder()
            let view = MarginReader(recorder: recorder)
                .levelMapContentMargins(.top, 10)
                .levelMapContentMargins(.top, 20)
                .levelMapContentMargins(.bottom, 30)
                .environment(\.layoutDirection, direction)
            _ = try #require(ImageRenderer(content: view).cgImage)
            #expect(recorder.value.top == 10)
            #expect(recorder.value.bottom == 30)
        }
        let recorder = MarginRecorder()
        _ = try #require(ImageRenderer(content: MarginReader(recorder: recorder)
            .levelMapContentMargins(.top, 20).levelMapContentMargins(.top, 10)).cgImage)
        #expect(recorder.value.top == 20)
    }
}

@MainActor private final class CameraState {
    var position = LevelMapCameraPosition.level(12)
    var writes = 0
}
@MainActor private final class MarginRecorder { var value = EdgeInsets() }
private struct MarginReader: View {
    @Environment(\.levelMapContentMargins) private var margins
    let recorder: MarginRecorder
    var body: some View {
        let _ = recorder.value = margins
        Color.red.frame(width: 10, height: 10)
    }
}
