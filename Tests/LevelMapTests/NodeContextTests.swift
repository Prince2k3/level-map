import SwiftUI
import Testing
@testable import LevelMap

@Suite("Node context and modifier compatibility")
struct NodeContextTests {
    struct Stop: Identifiable { let id: String }

    @Test @MainActor func allDataFormsAcceptContextContentWithoutBreakingLegacyBuilders() {
        let camera = Binding.constant(LevelMapCameraPosition.automatic)
        let stops = [Stop(id: "a"), Stop(id: "b")]
        _ = LevelMap(stops, route: .straight) { context in Text(context.level.id) }
        _ = LevelMap(stops[...], route: .straight, position: camera) { context in Text(context.level.id) }
        _ = LevelMap(stops[...], id: \.id, route: .straight, position: camera, content: { context in
            if context.state == .current { Text(context.level.id) } else { EmptyView() }
        })
        _ = LevelMap(0..<10, route: .straight) { context in Text("\(context.index)") }
        _ = LevelMap(EndlessLevels(), route: .straight, current: 4, position: camera) { context in
            Text("\(context.level)")
        }
        _ = LevelMap(stops, route: .straight, node: { stop, _, _ in Text(stop.id) })
        _ = LevelMap(stops, route: .straight, placedNode: { stop, _, _, _ in Text(stop.id) })
    }

    @Test @MainActor func renderedContextContainsModelRoadOffsetStateAndRTLPlacement() throws {
        let recorded = ContextRecorder()
        let view = LevelMap(["before", "one", "two", "three"][1...], id: \.self,
                            route: LevelRoute { Straight(levels: 3) }, current: 1) { context in
            let _ = recorded.nodes.updateValue(context, forKey: context.index)
            Color.red.frame(width: 10, height: 10)
        }.frame(width: 300, height: 600).environment(\.layoutDirection, .rightToLeft)
        _ = try #require(ImageRenderer(content: view).cgImage)
        for (index, model) in ["one", "two", "three"].enumerated() {
            let context = try #require(recorded.nodes[index])
            #expect(context.level == model)
            #expect(context.index == index)
            #expect(context.state == LevelState(level: index, current: 1))
            #expect(context.placement.layoutDirection == .rightToLeft)
        }
    }

    @Test @MainActor func legacyBuildersReceiveTheSameValuesAsContextContent() throws {
        let modern = ContextRecorder(), legacy = ContextRecorder(), placed = ContextRecorder()
        let route = LevelRoute { Straight(levels: 3) }
        let models = ["one", "two", "three"]
        let modernMap = LevelMap(models, route: route, current: 1, content: { context in
            let _ = modern.nodes.updateValue(context, forKey: context.index)
            Color.red.frame(width: 10, height: 10)
        })
        let legacyMap = LevelMap(models, route: route, current: 1, node: { level, index, state in
            let _ = legacy.nodes.updateValue(LevelMapNodeContext(level: level, index: index, state: state,
                                                                 placement: LevelPlacement(crossFraction: 0.5, heading: .zero)),
                                             forKey: index)
            Color.red.frame(width: 10, height: 10)
        })
        let placedMap = LevelMap(models, route: route, current: 1, placedNode: { level, index, state, placement in
            let _ = placed.nodes.updateValue(LevelMapNodeContext(level: level, index: index, state: state,
                                                                 placement: placement), forKey: index)
            Color.red.frame(width: 10, height: 10)
        })
        _ = try #require(ImageRenderer(content: modernMap.frame(width: 300, height: 600)).cgImage)
        _ = try #require(ImageRenderer(content: legacyMap.frame(width: 300, height: 600)).cgImage)
        _ = try #require(ImageRenderer(content: placedMap.frame(width: 300, height: 600)).cgImage)
        for index in models.indices {
            let context = try #require(modern.nodes[index])
            let old = try #require(legacy.nodes[index])
            #expect(old.level == context.level)
            #expect(old.index == context.index)
            #expect(old.state == context.state)
            #expect(placed.nodes[index] == context)
        }
    }

    @Test @MainActor func spacingAliasAndCanonicalNameUseTheSameEnvironment() throws {
        let old = SpacingRecorder(), new = SpacingRecorder(), defaultValue = SpacingRecorder()
        _ = try #require(ImageRenderer(content: SpacingReader(recorder: old).levelSpacing(145)).cgImage)
        _ = try #require(ImageRenderer(content: SpacingReader(recorder: new).levelMapSpacing(145)).cgImage)
        _ = try #require(ImageRenderer(content: SpacingReader(recorder: defaultValue)).cgImage)
        #expect(old.value == 145)
        #expect(new.value == old.value)
        #expect(defaultValue.value == 110)
    }

    @Test func contextsCanBeCreatedForPreviews() {
        let placement = LevelPlacement(crossFraction: 0.2, heading: .zero)
        let context = LevelMapNodeContext(level: "first", index: 0, state: .current, placement: placement)
        #expect(context == LevelMapNodeContext(level: "first", index: 0, state: .current, placement: placement))
        #expect(Set([context]).contains(context))
    }
}

@MainActor private final class ContextRecorder {
    var nodes: [Int: LevelMapNodeContext<String>] = [:]
}
@MainActor private final class SpacingRecorder { var value: CGFloat? }
private struct SpacingReader: View {
    @Environment(\.levelSpacing) private var spacing
    let recorder: SpacingRecorder
    var body: some View {
        let _ = recorder.value = spacing
        Color.red.frame(width: 10, height: 10)
    }
}
