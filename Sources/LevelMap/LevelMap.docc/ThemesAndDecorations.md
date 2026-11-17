# Themes and decorations

Give the map ground, a road and scenery, and change the look every chapter.

## Overview

A ``LevelMapTheme`` describes everything drawn under the level nodes:

- **Background:** a flat colour or a gradient across the map (``MapBackground``).
- **Road:** width, colours for the completed and remaining parts, an outline, a centre line, or
  a shader (``RoadStyle``).
- **Decorations:** SF Symbols or images scattered beside the road (``Decoration``).

The library ships only ``LevelMapTheme/plain``, which draws no ground, so your themes are yours.
Declare them as static properties so they read like built-ins:

```swift
extension LevelMapTheme {
    static let meadow = LevelMapTheme(
        background: .gradient([Color(red: 0.47, green: 0.74, blue: 0.38),
                               Color(red: 0.58, green: 0.82, blue: 0.45),
                               Color(red: 0.47, green: 0.74, blue: 0.38)]),
        road: RoadStyle(width: 28,
                        color: Color(red: 0.94, green: 0.87, blue: 0.66),
                        completedColor: Color(red: 0.99, green: 0.74, blue: 0.32),
                        outline: Color(red: 0.62, green: 0.48, blue: 0.30), outlineWidth: 3),
        decorations: [
            .symbol("tree.fill", color: .green, size: 30...46, weight: 3),
            .symbol("leaf.fill", color: .mint, size: 14...20, weight: 2),
        ],
        decorationDensity: 0.7, seed: 1)
}
```

Apply one with ``SwiftUICore/View/levelMapTheme(_:)``:

```swift
LevelMap(levels, route: .serpentine()) { ... }
    .levelMapTheme(.meadow)
```

## Backgrounds

``MapBackground/gradient(_:)`` runs across the map (left to right on a vertical map), so it
tiles without seams however long the map gets. Starting and ending on the same colour, as above,
gives soft edges.

## The road

The road up to the current level uses ``RoadStyle/completedColor``; the rest uses
``RoadStyle/color``. Add an ``RoadStyle/outline`` for edges, or a dashed
``RoadStyle/CenterLine`` for a desert track:

```swift
RoadStyle(width: 26,
          color: Color(red: 0.72, green: 0.52, blue: 0.34),
          completedColor: Color(red: 0.88, green: 0.38, blue: 0.20),
          centerLine: .init(color: .white, width: 3, dash: [10, 12]))
```

For a textured road, set ``RoadStyle/shader`` to a Metal shader made with `ShaderLibrary`; it
fills the remaining road in place of the colour.

## Decorations

Decorations are scattered at random beside the road, but the same theme always gives the same
scenery: the positions come from ``LevelMapTheme/seed`` and the chunk being drawn, using
``SeededRandom``. Change the seed to reshuffle them.

- ``Decoration/weight`` sets how often one decoration is picked relative to the others.
- ``Decoration/size`` is a range each placed decoration picks from.
- ``LevelMapTheme/decorationDensity`` is roughly how many decorations land per 100 × 100 points.
- ``LevelMapTheme/roadClearance`` keeps a strip each side of the road free, so scenery never
  covers a node. Make it at least half your node size.

Use ``Decoration/image(_:color:size:weight:)`` for your own artwork; template images are tinted
with the decoration's colour.

## Chapters

A long map can change its look every few levels. ``SwiftUICore/View/levelMapChapters(every:_:)``
splits the map into chapters and asks you for each chapter's theme:

```swift
LevelMap(EndlessLevels(), route: .forest, startsAtEnd: true, current: current) { ... }
    .levelMapChapters(every: 20) { chapter in
        [LevelMapTheme.meadow, .desert, .snow][chapter % 3]
    }
    .levelMapChapterTransition(.fade(length: 260))
```

Chapters override ``SwiftUICore/View/levelMapTheme(_:)``. The ground blends between chapters over
the fade's length, centred on the boundary; use ``ChapterTransition/cut`` for a hard edge. The
closure is called often while scrolling, so keep it cheap: look the theme up rather than build it.
