# Layers, placement and the camera

Draw custom content in map coordinates, build nodes from a context, and control the camera
independently of player progress.

## Node content

Every node builder receives a ``LevelMapNodeContext`` containing the model (`level`), its
zero-based road offset (`index`), its `state`, and its `placement`:

```swift
LevelMap(stops, id: \.id, route: .serpentine(), current: reached) { context in
    StopPin(stop: context.level, state: context.state)
        .overlay(alignment: context.placement.side == .leading ? .leading : .trailing) {
            Text(context.level.name)
                .fixedSize()
                .offset(x: context.placement.side == .leading ? 40 : -40)
        }
}
.levelMapSpacing(130)
```

Use `content:` when supplying the builder explicitly. Arrays, integer ranges and custom
``LevelMapDataSource`` values work directly. Random-access collections, including slices with
nonzero indices, accept `id:` or use their elements' `Identifiable` conformance. IDs must be
unique and stable; indices and `current` are always zero-based road offsets, not model IDs.
Custom data sources can implement `levelID(at:)`; its default uses the road offset.

Nodes live in lazy chunks. Moving a model between chunks can recreate its local view state.
Keep durable state in the model, keyed by its ID.

## Layout direction

``LevelPlacement`` uses SwiftUI's logical drawing coordinates. On vertical maps, `.leading`
means left in LTR and right in RTL. `crossFraction` runs from zero at leading to one at trailing.
SwiftUI mirrors positioned nodes and path layers together; don't negate their coordinates or
horizontal offsets a second time.

On horizontal maps the cross axis runs vertically: `.leading` identifies the top half and
`.trailing` the bottom half. Language direction does not swap them. `startsAtEnd` reverses
travel along the road, not these cross-axis sides.

Nodes and ``LevelMapGeometry`` inherit `layoutDirection`, including explicit overrides:

```swift
map.environment(\.layoutDirection, .rightToLeft)
```

For physical screen integrations, use `physicalSide` (`.left`, `.right`, `.top`, `.bottom`),
`physicalCrossFraction`, or `LevelPlacement(physicalCrossFraction:heading:axis:layoutDirection:)`.
The logical initializer defaults to a vertical, left-to-right context when used independently.

## Custom layers

``SwiftUICore/View/levelMapLayer(_:content:)`` supplies ``LevelMapGeometry`` for the chunks near
the viewport. Points use the layer's logical top-leading coordinate space, upright even when
the map runs bottom-up. A fractional position such as `3.5` is halfway along the road from
level 3 to level 4. Use `levels` to limit work to the laid-out range.

```swift
map
    .levelMapLayer(.belowRoad) { geometry in
        geometry.roadPath(from: 4, to: 6)
            .stroke(.green.opacity(0.25), style: StrokeStyle(lineWidth: 18, lineCap: .round))
    }
    .levelMapLayer(.aboveNodes) { geometry in
        if geometry.levels.contains(6), let point = geometry.point(atLevel: 6) {
            GoalPennant()
                .scaleEffect(1 / geometry.zoom)
                .position(point)
        }
    }
```

Layers can sit `.belowRoad`, `.aboveRoad`, or `.aboveNodes`. Layers at the same placement draw
in modifier order. They don't receive touches or VoiceOver focus. Use shapes or paths for
large terrain layers: a very tall Canvas can be clipped when the map is mirrored. Expensive
static layers can be Equatable on their geometry inputs, including layout direction when relevant.

Use ``SwiftUICore/View/levelMapMarks(_:at:placement:content:)`` for interactive content instead:

```swift
map.levelMapMarks(rewards, at: \.level, placement: .outside(spacing: 18)) { reward in
    Button { collect(reward) } label: { RewardBubble(reward: reward) }
}
```

Marks have stable identities, take touches and participate in accessibility. They appear over
nodes and under the avatar. `.outside` places a mark towards the nearer edge; `.inside` moves
it towards the centre. Both work in RTL. Marks retain their size while the camera zooms.

## Road style

Use ``RoadStyle/dotted(_:completed:dotSize:gap:completedWidth:glow:)`` for a dotted path with a
solid completed path and glow. Custom styles offer `lineCap`, `dash`, `completedWidth`, and
`completedGlow` in addition to the road, outline and centre-line colours.

```swift
let road = RoadStyle.dotted(.gray, completed: .green,
                            dotSize: 5, gap: 10, completedWidth: 6, glow: 8)
```

## Camera ownership

``LevelMapCameraPosition`` is the single programmatic camera API. Bind it to `position:`;
player progress remains in `current` and `levelMapProgress(toNext:)`:

```swift
@State private var position: LevelMapCameraPosition = .automatic

var body: some View {
    LevelMap(stops, id: \.id, route: .serpentine(), current: reached,
             position: $position) { context in
        StopPin(stop: context.level, state: context.state)
    }
    .levelMapAvatar { Walker() }
    .levelMapProgress(toNext: walked)
    .levelMapRecenterButton()
}
```

- `.automatic` opens on the player and tracks visible progress until manual scrolling takes ownership.
- `.level(12.5, anchor: .center)` frames a fractional level without changing player progress.
- `.avatar(zoom: 2.2, anchor: UnitPoint(x: 0.5, y: 0.45))` continuously follows the avatar and disables
  manual scrolling. Use zoom one for following without magnification.

Assign a framing with `withAnimation` to animate a camera change. Manual scrolling writes back
`positionedByUser == true` and releases automatic tracking. The binding reports ownership,
not a measured viewport: `level` is populated only for an explicit level request. A finite map
clamps a requested level to its last node without rewriting the request; an endless map loads
enough chunks to reach the target.

Omitting `position` uses an internal camera with the same `.automatic` ownership behavior.
The built-in recenter button works with bound and internal cameras. For another recenter control,
assign `.automatic` to the binding. Resting automatic framing centres the player within content
margins. Explicit level and avatar anchors are fractions of the whole visible map.

Nodes and avatars retain their size while zoomed. To scale them yourself, use
`scalesMarkers: false` and read ``SwiftUICore/EnvironmentValues/levelMapZoom``.
Reduce Motion suppresses camera magnification and map-generated movement.

Native scroll phases detect user input on iOS 18/macOS 15/visionOS 2 and newer. macOS 14 also
observes wheel events without consuming them; visionOS 1 supports dragging. Accessibility
scroll actions page the existing map and release camera ownership on all supported platforms.

## Floating controls and content margins

```swift
map
    .levelMapContentMargins(.bottom, panelHeight)
    .overlay(alignment: .bottom) { Panel() }
    .levelMapRecenterButton { recenter in
        Button("Back to you", systemImage: "location.fill", action: recenter)
    }
```

The map draws under content margins, but automatic framing and avatar visibility use the
uncovered area. Changing margins does not force a scroll. The recenter button stays clear of
the margins and hides while the camera follows the avatar. For other visibility-dependent
content, use ``SwiftUICore/View/onLevelMapAvatarVisibilityChange(_:)``.

For overlapping margin edges, the modifier closest to the map wins, following environment
precedence. Different edges accumulate:

```swift
map.levelMapContentMargins(.top, 10)
   .levelMapContentMargins(.top, 20)    // top remains 10
   .levelMapContentMargins(.bottom, 30) // bottom is 30
```

## Animation ownership

Caller animations take precedence over the map's defaults. `Transaction.disablesAnimations`
prevents fallback insertion without stripping an explicit animation. To suppress both for an update:

```swift
var transaction = Transaction(animation: nil)
transaction.disablesAnimations = true
withTransaction(transaction) {
    reached = destination
}
```

A nil animation without `disablesAnimations` allows the map's walking and camera defaults.
For live progress, a linear animation matching the update interval keeps the avatar and camera
moving together.

## Topics

### Content

- ``LevelMapNodeContext``
- ``LevelPlacement``
- ``LevelMapGeometry``
- ``LevelMapLayerPlacement``
- ``LevelMapMarkPlacement``

### Camera

- ``LevelMapCameraPosition``
- ``SwiftUICore/View/levelMapRecenterButton(alignment:)``
- ``SwiftUICore/View/onLevelMapAvatarVisibilityChange(_:)``
