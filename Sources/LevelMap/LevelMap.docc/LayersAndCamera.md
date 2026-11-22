# Layers, placement and the camera

Draw your own things in step with the road, place labels by where a level sits, and follow the
player as they walk.

## Overview

The theme covers the ground, the road and scattered scenery. When a map needs more, such as
terrain, a highlighted stretch of road, a goal marker between levels, or a camera that follows
a walker, use the hooks in this article. The Trail sample in the demo app uses all of them.

## Draw a layer

``SwiftUICore/View/levelMapLayer(_:content:)`` draws any view in step with the map. Its closure
is given a ``LevelMapGeometry`` that turns positions along the road, in levels, into points:

```swift
LevelMap(stops, route: .serpentine(), current: arrived) { ... }
    .levelMapLayer(.belowRoad) { map in
        // Today's leg, as a soft band under the road.
        map.roadPath(from: 4, to: 6)
            .stroke(.green.opacity(0.25), style: StrokeStyle(lineWidth: 18, lineCap: .round))
    }
    .levelMapLayer(.aboveNodes) { map in
        if map.levels.contains(6), let point = map.point(atLevel: 6) {
            GoalPennant().position(x: point.x + 40, y: point.y - 20)
        }
    }
```

- ``LevelMapLayerPlacement`` picks where the layer goes: under the road, between the road and
  the nodes, or over the nodes.
- Positions may fall between levels: `4.5` is halfway from level 4 to level 5.
- A layer covers only the part of the map that is laid out. Draw what belongs to
  ``LevelMapGeometry/levels``; the layer is rebuilt as the map scrolls.
- ``LevelMapGeometry/distanceToRoad(from:)`` keeps your own scenery clear of the road.
- Layers don't take touches, and VoiceOver skips them.

A layer that draws a lot, such as terrain, should be an `Equatable` view compared on
``LevelMapGeometry/levels`` and ``LevelMapGeometry/size``, so it isn't redrawn while the avatar
moves. Draw it with shapes and paths rather than a `Canvas`: a canvas is a bitmap, and on a map
that runs bottom-up, one as tall as several chunks is cut off at the edge of what was on screen.

## Place labels by side

The node content builder receives a ``LevelMapNodeContext``. Its `placement` is a
``LevelPlacement``: how far across the map the level is, and which way the road runs through it.
Put a label on the side away from the edge:

```swift
LevelMap(stops, route: .serpentine(), current: arrived) { context in
    StopPin(state: context.state)
        .overlay(alignment: context.placement.side == .trailing ? .trailing : .leading) {
            Text(context.level.name)
                .fixedSize()
                .offset(x: context.placement.side == .trailing ? -40 : 40)
        }
}
```

### Layout direction

Placement uses SwiftUI's logical coordinates. On a vertical map, `side == .leading` means
left in a left-to-right layout and right in a right-to-left layout. `crossFraction` remains
zero at leading and one at trailing. SwiftUI mirrors both positioned nodes and path layers;
do not negate their x coordinates or offsets a second time.

On a horizontal map, the cross axis is vertical. For compatibility, `.leading` identifies
the top half and `.trailing` the bottom half; language direction does not swap them.
`startsAtEnd` reverses travel along the road, not these cross-axis sides.

Nodes and layer geometry receive `layoutDirection` from the environment, including an override:

```swift
LevelMap(stops, route: .serpentine()) { context in
    StopPin(stop: context.level, state: context.state)
        .overlay(alignment: context.placement.side == .leading ? .leading : .trailing) {
            Text(context.level.name)
                .fixedSize()
                .offset(x: context.placement.side == .leading ? 40 : -40)
        }
}
.environment(\.layoutDirection, .rightToLeft)
```

Use `physicalSide` (`.left`, `.right`, `.top`, `.bottom`) or `physicalCrossFraction` when
integrating with physical screen coordinates. Construct a placement from such coordinates
with `LevelPlacement(physicalCrossFraction:heading:axis:layoutDirection:)`. For example, a
physical fraction of 0.2 lies on `.trailing` in a vertical RTL map. The original
`LevelPlacement(crossFraction:heading:)` initializer still uses logical coordinates and defaults
to a vertical left-to-right context. `.inside` and `.outside` marks stay towards the centre
and the nearer edge respectively in either reading direction.

## API naming and compatibility

Use `.levelMapSpacing(130)` alongside the other `levelMap…` modifiers. The original
`.levelSpacing(130)` remains an alias with the same defaults and modifier-order behavior.

Prefer a single context argument for node content:

```swift
LevelMap(stops, route: .serpentine()) { context in
    StopPin(stop: context.level, state: context.state)
}
.levelMapSpacing(130)
```

The `content:` builder works with custom data sources, arrays, ranges, endless levels,
and collection initializers with `id:` or `Identifiable` elements. It also accepts the camera
binding. `context.index` is always a zero-based road offset; use `context.level` for the model.
`context.placement` carries the map's axis and layout direction.

Existing `node:` builders with three arguments and `placedNode:` builders with four arguments
remain supported, including trailing-closure syntax. They adapt to the same context internally.
No migration or deprecation warnings are required for existing callers.

## Style the road

``RoadStyle`` can draw a dotted or dashed road that turns solid as it is completed, with a
different width and a glow for the completed part:

```swift
LevelMapTheme(
    background: .color(.black),
    road: .dotted(.white.opacity(0.4), completed: .green, dotSize: 5, gap: 10))
```

For other looks, set ``RoadStyle/lineCap``, ``RoadStyle/dash``, ``RoadStyle/completedWidth`` and
``RoadStyle/completedGlow`` yourself.

## Follow the player

``SwiftUICore/View/levelMapFollowsAvatar(_:zoom:anchor:scalesMarkers:)`` zooms in on the avatar
and keeps it in place while it moves, for showing a walk as it happens. Scrolling is off
meanwhile; when following stops, the map zooms back out and rests on the avatar.

```swift
LevelMap(stops, route: .serpentine(), current: arrived) { ... }
    .levelMapAvatar { Walker() }
    .levelMapProgress(toNext: walked)
    .levelMapFollowsAvatar(session.isLive)
```

The camera glides between progress updates, taking as long as the gap since the last one, so
it moves at an even pace when updates arrive steadily, such as from location fixes. Animate
the progress with a linear animation of the same length, as the demo does, to keep the avatar
still on screen.

Nodes and the avatar keep their size while the ground grows. Views in a layer can do the same
by dividing by ``LevelMapGeometry/zoom``; nodes that scale themselves can read
``SwiftUICore/EnvironmentValues/levelMapZoom``. With Reduce Motion on, the map doesn't zoom.

## Offer a way back

When the player scrolls away from the avatar, offer to bring them back:

```swift
LevelMap(...) { ... }
    .levelMapAvatar { Walker() }
    .levelMapRecenterButton()
```

The button appears while the avatar is off screen and the camera isn't following it. Pass a
closure to draw your own, calling `recenter` when it's tapped:

```swift
.levelMapRecenterButton(alignment: .bottomLeading) { recenter in
    Button("Back to you", systemImage: "location.fill", action: recenter)
        .buttonStyle(.bordered)
}
```

To drive the scroll from elsewhere, use ``SwiftUICore/View/onLevelMapAvatarVisibilityChange(_:)``
and ``SwiftUICore/View/levelMapRecenter(on:)`` instead.

## Make room for floating content

If a panel or cards float over the bottom of the map, tell it how much they cover:

```swift
LevelMap(...) { ... }
    .levelMapContentMargins(.bottom, panelHeight)
```

The current level then rests in the middle of what is still visible, the avatar counts as off
screen once it slides under the panel, and the recenter button sits above it. The map itself
still fills the space, so it shows through a translucent panel, and changing the margins
doesn't scroll it. ``SwiftUICore/View/levelMapFocusOffset(_:)`` nudges the resting point
further.

## Mark the road

Marks are views placed along the road, such as gems to collect or signs. Unlike layers, they
take touches and VoiceOver reads them:

```swift
LevelMap(...) { ... }
    .levelMapMarks(gems, at: \.level, placement: .outside()) { gem in
        Button { collect(gem) } label: { GemBubble(gem: gem) }
    }
```

Positions are in levels, so `2.5` sits halfway between levels 2 and 3. A mark placed
``LevelMapMarkPlacement/outside(spacing:)`` sits beside the road on the side nearer the edge
and is kept inside the map; ``LevelMapMarkPlacement/inside(spacing:)`` takes the other side.

## Topics

### Layers

- ``SwiftUICore/View/levelMapLayer(_:content:)``
- ``LevelMapLayerPlacement``
- ``LevelMapGeometry``

### Placement

- ``LevelPlacement``

### Camera

- ``SwiftUICore/View/levelMapFollowsAvatar(_:zoom:anchor:scalesMarkers:)``
- ``SwiftUICore/EnvironmentValues/levelMapZoom``
- ``SwiftUICore/View/onLevelMapAvatarVisibilityChange(_:)``
- ``SwiftUICore/View/levelMapRecenter(on:)``
- ``SwiftUICore/View/levelMapFocusOffset(_:)``
- ``SwiftUICore/View/levelMapRecenterButton(alignment:)``
- ``SwiftUICore/View/levelMapRecenterButton(alignment:_:)``
- ``SwiftUICore/View/levelMapContentMargins(_:_:)``

### Marks

- ``SwiftUICore/View/levelMapMarks(_:at:placement:content:)``
- ``LevelMapMarkPlacement``

## Collection identity and animation ownership

For changing collections, pass stable IDs, or use `Identifiable` elements:

```swift
LevelMap(stops, id: \.id, route: .serpentine(), current: arrived) { context in
    StopPin(stop: context.level, state: context.state)
}
```

Random-access collections, including slices with nonzero indices, work directly with `id:`.
`current` and the node's index are always zero-based road offsets. Existing arrays, ranges,
and custom data sources still work. Custom sources can implement `levelID(at:)`; its default
uses the road offset. IDs must be unique and stable. Lazy chunks remain separate containers,
so moving an element between chunks can recreate its local view state. Keep durable state
in the model, keyed by its ID.

Use `withAnimation` or a value animation on the map to supply the animation for an update.
The map uses its existing walking and camera defaults only when there is no caller animation.
To disable those defaults for an update, set `disablesAnimations` on the transaction:

```swift
var transaction = Transaction(animation: nil)
transaction.disablesAnimations = true
withTransaction(transaction) {
    arrived = destination
}
```

A plain transaction with a nil animation still allows the map's compatibility defaults.
Reduce Motion suppresses map-generated animations.

## Control the camera with a binding

Keep camera ownership separate from the player's reached level:

```swift
@State private var position: LevelMapCameraPosition = .automatic

var body: some View {
    LevelMap(stops, id: \.id, route: .serpentine(), current: reachedLevel,
             position: $position) { context in
        StopPin(stop: context.level, state: context.state)
    }
    .levelMapAvatar { Walker() }
    .levelMapProgress(toNext: walked)
}
```

Assign `.level(12.5)` to view halfway between levels 12 and 13, or
`.avatar(zoom: 2.2, anchor: UnitPoint(x: 0.5, y: 0.45))` to follow the player.
Assign `.automatic` to return to the player's position without magnifying. Use `withAnimation`
to choose the transition; disabled transactions and Reduce Motion are respected.

Manual scrolling writes a position with `positionedByUser == true`. In that state, player
updates no longer move the camera. The binding reports ownership, not a measured viewport:
`level` is only populated for explicit level requests. Following locks manual scrolling,
just as the existing follow modifier does. On iOS 17/macOS 14/visionOS 1, manual ownership
is detected from dragging; newer systems use native scroll phases as well.

When `position` is supplied, it takes precedence over `levelMapFollowsAvatar`. The existing
recenter button and recenter trigger assign `.automatic` to the binding. Focus offsets and
content margins still apply to automatic framing; explicit level anchors refer to the whole
visible map. A finite map clamps an out-of-range target to its last level without rewriting
the request. Endless maps load enough chunks to reach the requested level. `current` remains
player progress and is never changed by the camera.

Omit `position` to retain the existing behavior of all camera modifiers. Collection and
placed-node initializers accept the binding too.
