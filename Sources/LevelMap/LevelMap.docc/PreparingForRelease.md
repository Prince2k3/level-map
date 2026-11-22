# Moving to the release API

The library is still preparing for its first full release. Superseded APIs have been removed
rather than retained as deprecated overloads. The supported platform minimums are iOS 18,
macOS 14 and visionOS 1.

| Removed API | Replacement |
| --- | --- |
| Three-argument `node:` builder | Single-argument `content:` builder receiving `LevelMapNodeContext` |
| Four-argument `placedNode:` builder | `context.placement` in the same content builder |
| `.levelSpacing(_:)` | `.levelMapSpacing(_:)` |
| `.levelMapFollowsAvatar(...)` | Assign `.avatar(zoom:anchor:scalesMarkers:)` or `.automatic` to the camera binding |
| `.levelMapRecenter(on:)` | Assign `.automatic` to the binding, or use `.levelMapRecenterButton()` |
| `.levelMapFocusOffset(_:)` | Use explicit camera `.level(_:anchor:)` framing, or content margins for floating panels |

```swift
@State private var camera: LevelMapCameraPosition = .automatic

var body: some View {
    LevelMap(stops, id: \.id, route: .serpentine(), current: reached,
             position: $camera) { context in
        StopPin(stop: context.level, state: context.state)
    }
    .levelMapSpacing(130)
    .levelMapRecenterButton()
}
```

For live following, set `camera = .avatar()` when a session starts and `.automatic` when it ends.
Player progress is independent of camera framing. Without a binding the map uses an internal
`.automatic` camera; manual scrolling releases tracking until the recenter button is used.
The original data-source protocol, collection identities, route builders, themes, layers, marks,
and progress modifiers remain available. See <doc:LayersAndCamera> for the complete contract.
