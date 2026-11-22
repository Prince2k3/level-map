# Quick start

Put a scrolling level map on screen, mark the player's progress and give it a look.

## Add the package

In Xcode choose **File › Add Package Dependencies…** and enter the repository URL, or add it to
`Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/<you>/level-map.git", from: "0.2.0"),
],
targets: [
    .target(name: "MyGame", dependencies: [
        .product(name: "LevelMap", package: "level-map"),
    ]),
]
```

LevelMap needs iOS 18, macOS 14 or visionOS 1.

## Show a map

A ``LevelMap/LevelMap`` takes your levels, a route and a view for each level node:

```swift
import LevelMap
import SwiftUI

struct WorldScreen: View {
    @State private var current = 0

    var body: some View {
        LevelMap(0..<100, route: .serpentine(), current: current) { context in
            LevelNode(number: context.index + 1, state: context.state)
        }
    }
}
```

- **Levels.** Arrays and `Range<Int>` work as they are. Use ``EndlessLevels`` when levels never
  run out, or conform your own type to ``LevelMapDataSource``.
- **Route.** The road the levels sit on. ``LevelRoute/serpentine(amplitude:levelsPerWave:)``,
  ``LevelRoute/zigzag(amplitude:levelsPerWave:)``, ``LevelRoute/straight`` and
  ``LevelRoute/spline(_:levelsPerRepeat:)`` are ready to use; <doc:DesigningRoutes> shows how
  to build your own.
- **Node.** Your view for one level. It receives a ``LevelMapNodeContext`` with the model in
  `level`, a zero-based road `index`, its `state` (`.completed`, `.current` or `.locked`), and
  `placement` for side, heading and layout direction. The original three- and four-argument
  builders are still supported.

The map scrolls to `current` when it first appears and again whenever `current` changes.

## Draw the level nodes

The map places each node on the road, centred on the level's position. Nodes can be any view:

```swift
struct LevelNode: View {
    let number: Int
    let state: LevelState

    var body: some View {
        Text("\(number)")
            .font(.headline.monospacedDigit())
            .foregroundStyle(state == .locked ? .secondary : Color.white)
            .frame(width: 52, height: 52)
            .background(Circle().fill(fill))
    }

    private var fill: Color {
        switch state {
        case .completed: .orange
        case .current: .pink
        case .locked: Color(white: 0.9)
        }
    }
}
```

VoiceOver reads each node with its state ("Completed", "Current level" or "Locked") in road
order, whichever way the map runs, and the map adds a "Current level" rotor so players can jump
straight to where they are. Give your node an accessibility label if its content doesn't say
which level it is.

## Climb up the map

Most level maps start at the bottom and climb. Pass `startsAtEnd: true` to put level 0 at the
bottom (or at the trailing edge of a horizontal map):

```swift
LevelMap(levels, route: .serpentine(), startsAtEnd: true, current: current) { ... }
```

Pass `axis: .horizontal` for a map that scrolls sideways.

## Add a look and an avatar

Modifiers set the spacing between levels, the theme and the player's avatar:

```swift
LevelMap(levels, route: .serpentine(), startsAtEnd: true, current: current) { ... }
    .levelMapSpacing(120)
    .levelMapTheme(.meadow)
    .levelMapAvatar {
        Image(systemName: "figure.walk.circle.fill")
            .font(.largeTitle)
            .offset(y: -44)
    }
```

When `current` moves on, the completed part of the road grows and the avatar walks to the new
level. Change the animation with ``SwiftUICore/View/levelMapUnlockAnimation(_:)``, or pass `nil`
to switch it off. With Reduce Motion on, the avatar moves at once.

The library ships only ``LevelMapTheme/plain``; `.meadow` above is a theme you declare yourself.
<doc:ThemesAndDecorations> shows how.

## Show progress towards the next level

The avatar doesn't have to jump from level to level. Use
``SwiftUICore/View/levelMapProgress(toNext:)`` to place it part of the way along the road to the
next level, from 0 (standing on `current`) to 1 (at the next level). The completed road follows
it.

This suits apps where a level is a real goal, such as a place the user walks to. Work out how
far along the current leg the user is, for example from Core Location, and pass that fraction:

```swift
struct WalkScreen: View {
    let current: Int
    let metresLeft: Double   // From your location code.
    let legLength: Double    // The distance from level `current` to the next one.

    var body: some View {
        LevelMap(0..<20, route: .serpentine(), startsAtEnd: true, current: current) { context in
            LevelNode(number: context.index + 1, state: context.state)
        }
        .levelMapProgress(toNext: 1 - metresLeft / legLength)
        .levelMapAvatar { Image(systemName: "figure.walk.circle.fill").font(.largeTitle) }
    }
}
```

- To glide between updates instead of jumping, change the value inside `withAnimation`.
- When the user arrives, increment `current` and set the progress back to 0 in the same update.
  The avatar then stays on the node instead of walking past it.
- Values are clamped to 0...1, and progress past the last level of a finite map is ignored.
- The map scrolls only when `current` changes, not when the progress does.

To find where the avatar is on the road yourself, use
``ResolvedRoute/distance(ofLevel:progress:)`` with ``ResolvedRoute/sample(atDistance:)``.

## Next steps

- <doc:DesigningRoutes>: build a road from segments, or design one by dragging it on screen.
- <doc:ThemesAndDecorations>: ground, road and scenery, and a new look every chapter.
- <doc:EndlessMapsAndPaging>: maps with thousands of levels, or no end at all.
- <doc:LayersAndCamera>: draw your own layers, place labels, and follow the player as they walk.
