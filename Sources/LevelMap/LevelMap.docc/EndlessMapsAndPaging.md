# Endless maps and paging

Show thousands of levels, or a map with no end, without slowing down.

## Overview

A ``LevelMap/LevelMap`` never lays out the whole map at once. It splits the road into chunks of
levels (10 by default) and only builds the chunks near the screen. Each chunk draws its own
stretch of ground, road and scenery, so a map opened on level 5,000 does the same work as one
opened on level 5.

## How many levels a map shows

Two things limit the number of levels: your data and your route.

| Data | Route | Levels shown |
| --- | --- | --- |
| Array or range | Ends | The smaller of the two counts |
| Array or range | Ends in a ``Repeat`` | The data's count |
| ``EndlessLevels`` | Ends | The route's count |
| ``EndlessLevels`` | Ends in a ``Repeat`` | No end |

## Endless levels

``EndlessLevels`` makes levels on demand from their index:

```swift
LevelMap(EndlessLevels { index in Level(number: index + 1) }, route: .serpentine(),
         startsAtEnd: true, current: progress) { level, index, state in
    LevelNode(level: level, state: state)
}
```

`EndlessLevels()` with no closure gives each level its index, which is all many games need.

For levels that come from somewhere else, such as a database or a server, conform your own type
to ``LevelMapDataSource``. ``LevelMapDataSource/level(at:)`` is called as chunks come into view,
so return quickly; return a placeholder and fill it in later if loading is slow.

## Paging

An endless map can't have an infinite scroll view, so it pages. It starts with the chunks up to
six past the current level's, and adds six more whenever the last two come into view. Chunks are
created lazily, so chunks far behind the player cost nothing until they are scrolled to.

## Chunk size

``SwiftUICore/View/levelMapChunkSize(_:)`` sets how many levels each chunk holds. Smaller chunks
mean less drawing per chunk but more chunks on screen. The default of 10 suits nodes about 50
points across with the default spacing; try 20 for small nodes packed close together.

## Opening on the right level

The map opens with `current` on screen, and scrolls to it whenever it changes. To rebuild the
map, for example when switching routes, give it a new identity so it opens on the current level
again:

```swift
LevelMap(EndlessLevels(), route: route, startsAtEnd: true, current: current) { ... }
    .id(routeName)
```

## Finding a level's position

``ResolvedRoute`` answers questions about the road without drawing it, such as where level
5,000 is or how long a finite route is:

```swift
let road = route.resolved(width: 390, spacing: 110)
road.isEndless             // true for a route ending in Repeat
road.levelCount            // nil when endless
road.level(5_000)?.position
```

Positions are in route coordinates: `x` across the map and `y` along the scroll axis from the
start of the road, before `startsAtEnd` flips the map.
