# ``LevelMap``

Scrolling level maps for SwiftUI, with roads described in code instead of drawn in SVG.

## Overview

LevelMap draws the "world map" screen of a puzzle game: a road winding through scenery with a
node for every level, the road filled in up to the player's current level, and an avatar
standing on it.

```swift
import LevelMap
import SwiftUI

struct WorldScreen: View {
    let progress: Int

    var body: some View {
        LevelMap(EndlessLevels(), route: .serpentine(), startsAtEnd: true, current: progress) { level, index, state in
            LevelNode(number: index + 1, state: state)
        }
        .levelMapTheme(.meadow)
    }
}
```

The road is a ``LevelRoute``: a short list of segments such as ``Serpentine``, ``Detour`` and
``Spline`` that is laid out to fit whatever screen the map is shown on. Because a route can end
in a ``Repeat``, a map can be endless, and it is built lazily in chunks, so level 5,000 costs no
more than level 5.

## Topics

### Essentials

- <doc:QuickStart>
- ``LevelMap/LevelMap``
- ``LevelState``
- ``SwiftUICore/View/levelMapProgress(toNext:)``

### Routes

- <doc:DesigningRoutes>
- ``LevelRoute``
- ``RouteBuilder``
- ``Start``
- ``Repeat``
- ``RouteComponent``

### Segments

- ``Straight``
- ``Serpentine``
- ``Zigzag``
- ``Detour``
- ``Spline``
- ``Polyline``
- ``RouteSegment``
- ``RouteContext``
- ``RouteWaypoint``
- ``RoutePoint``
- ``RouteSide``

### Themes and decorations

- <doc:ThemesAndDecorations>
- ``LevelMapTheme``
- ``MapBackground``
- ``RoadStyle``
- ``Decoration``
- ``ChapterTransition``
- ``SeededRandom``

### Levels and paging

- <doc:EndlessMapsAndPaging>
- ``LevelMapDataSource``
- ``EndlessLevels``

### Importing routes

- ``RouteJSON``

### Measuring a route

- ``ResolvedRoute``
- ``RouteSample``
