import SwiftUI
import Testing
@testable import LevelMap

@Suite("Public collection API")
struct APICompatibilityTests {
    struct Stop: Identifiable { let id: String }

    @Test func slicesUseOffsetsRatherThanTheirIndices() {
        let slice = ["a", "b", "c", "d"][1...2]
        let data = LevelMapCollection(slice, id: \.self)
        #expect(data.levelCount == 2)
        #expect(data.level(at: 0) == "b")
        #expect(data.level(at: 1) == "c")
    }

    @Test func typeErasedArraysDoNotMixModelIDsWithSlotIDs() {
        struct Numbered: Identifiable { let id: Int }
        let mixed: [Any] = [Numbered(id: 1), "plain"]
        #expect(mixed.levelID(at: 0) == AnyHashable(0))
        #expect(mixed.levelID(at: 1) == AnyHashable(1))
        let identified = [Numbered(id: 10), Numbered(id: 20)]
        #expect(identified.levelID(at: 0) == AnyHashable(10))
        #expect(identified.levelID(at: 1) == AnyHashable(20))
    }

    @Test func identityFollowsElementsAcrossInsertionAndReordering() {
        let old = LevelMapCollection(["a", "b", "c"], id: \.self)
        let new = LevelMapCollection(["c", "x", "a", "b"], id: \.self)
        #expect(old.levelID(at: 0) == new.levelID(at: 2))
        #expect(old.levelID(at: 1) == new.levelID(at: 3))
        #expect(old.levelID(at: 2) == new.levelID(at: 0))
    }

    @Test @MainActor func canonicalInitializersSupportAllDataForms() {
        let stops = [Stop(id: "a"), Stop(id: "b")]
        _ = LevelMap(stops, route: .straight) { context in Text(context.level.id) }
        #expect(stops.levelID(at: 0) == AnyHashable("a"))
        _ = LevelMap(stops[...], route: .straight) { context in Text(context.level.id) }
        _ = LevelMap(stops[...], id: \.id, route: .straight) { context in Text(context.level.id) }
        _ = LevelMap(0..<10, route: .straight) { context in Text("\(context.index)") }
        _ = LevelMap(["a", "b"], route: .straight) { context in Text(context.level) }
        _ = LevelMap(EndlessLevels(), route: .straight) { context in Text("\(context.index)") }
    }

    @Test @MainActor func animationRespectsCallerAndDisabling() {
        let context = MapAnimationContext()
        context.transaction = Transaction(animation: .linear(duration: 2))
        #expect(context.resolved(fallback: .spring(), reduceMotion: false).animation == .linear(duration: 2))
        context.transaction.disablesAnimations = true
        let disabled = context.resolved(fallback: .spring(), reduceMotion: false)
        #expect(disabled.animation == .linear(duration: 2))
        #expect(disabled.disablesAnimations)
        context.transaction = Transaction()
        #expect(context.resolved(fallback: .linear(duration: 1), reduceMotion: false).animation == .linear(duration: 1))
        #expect(context.resolved(fallback: .spring(), reduceMotion: true).animation == nil)
    }
}
