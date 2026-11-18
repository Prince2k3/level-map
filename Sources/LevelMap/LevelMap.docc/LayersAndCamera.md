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

``LevelMap/LevelMap/init(_:route:axis:startsAtEnd:current:placedNode:)`` passes each node a
``LevelPlacement``: how far across the map the level is, and which way the road runs through it.
Put a label on the side away from the edge:

```swift
LevelMap(stops, route: .serpentine(), current: arrived) { stop, index, state, placement in
    StopPin(state: state)
        .overlay(alignment: placement.side == .trailing ? .trailing : .leading) {
            Text(stop.name)
                .fixedSize()
                .offset(x: placement.side == .trailing ? -40 : 40)
        }
}
```

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
@State private var avatarVisible = true
@State private var recenter = 0

LevelMap(...) { ... }
    .levelMapAvatar { Walker() }
    .onLevelMapAvatarVisibilityChange { avatarVisible = $0 }
    .levelMapRecenter(on: recenter)
    .overlay(alignment: .bottomTrailing) {
        if !avatarVisible {
            Button("Back to you", systemImage: "location.fill") { recenter += 1 }
        }
    }
```

If cards float over the bottom of the map, ``SwiftUICore/View/levelMapFocusOffset(_:)`` moves
where the current level rests so it stays clear of them.

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
