# Designing routes

Describe the road as a list of segments that fits any screen.

## Overview

A ``LevelRoute`` describes the road's shape, not its pixels. Positions across the map are
fractions of its width (0 is the leading edge, 1 the trailing edge), and distance along the map
comes from how many levels each segment holds times the spacing between levels. The same route
fits an iPhone SE, an iPad and a Mac window.

```swift
extension LevelRoute {
    static let forest = LevelRoute {
        Start(x: 0.5)
        Straight(levels: 2)
        Serpentine(levels: 10, amplitude: 0.32)
        Detour(around: .leading, levels: 3)
        Zigzag(levels: 6, amplitude: 0.25, halfWaves: 2)
        Repeat { Serpentine(levels: 6, halfWaves: 2) }
    }
}
```

The segments are joined into one smooth curve, so neighbouring segments meet without kinks.
Levels are spread evenly along each segment by arc length, so they are just as far apart on a
bend as on a straight.

## Segments

| Segment | Shape |
| --- | --- |
| ``Start`` | Where the road begins across the map. Defaults to the middle. |
| ``Straight`` | A straight run, optionally drifting to a new `toX`. |
| ``Serpentine`` | A smooth wave from side to side. `amplitude` is a fraction of the width; `halfWaves` sets how many times it swings. |
| ``Zigzag`` | Like a serpentine, with sharp corners. |
| ``Detour`` | A loop out towards one edge and back, for a level that sits off to the side. |
| ``Spline`` | A smooth curve through your own points. `x` is a fraction of the width, `y` a fraction of the segment's length. |
| ``Polyline`` | A road through traced points that keeps its drawn proportions. Used by the importers. |

## Endless routes

A route without a ``Repeat`` holds exactly the sum of its segments' levels, and the map stops
there. Ending a route with `Repeat { ... }` makes it endless: the repeated segments carry on
forever after the others.

```swift
LevelRoute {
    Start(x: 0.2)
    Spline(levels: 7, through: [.init(x: 0.2, y: 0), .init(x: 0.8, y: 0.5), .init(x: 0.5, y: 1)])
    Repeat {
        Serpentine(levels: 6, halfWaves: 2)
        Straight(levels: 2)
    }
}
```

The ready-made routes ``LevelRoute/serpentine(amplitude:levelsPerWave:)``,
``LevelRoute/zigzag(amplitude:levelsPerWave:)``, ``LevelRoute/straight`` and
``LevelRoute/spline(_:levelsPerRepeat:)`` are all endless.

## Conditions and loops

The route builder supports `if`, `switch` and `for`, so you can generate a route:

```swift
LevelRoute {
    for world in 0..<5 {
        Serpentine(levels: 10, amplitude: world.isMultiple(of: 2) ? 0.3 : 0.4)
        Detour(around: world.isMultiple(of: 2) ? .leading : .trailing, levels: 3)
    }
    if hasBonusLevels {
        Zigzag(levels: 6)
    }
}
```

## Spacing

Levels are 110 points apart along the scroll axis by default. Change it for the whole map with
``SwiftUICore/View/levelSpacing(_:)``:

```swift
LevelMap(levels, route: .forest) { ... }
    .levelSpacing(140)
```

``Polyline`` segments are the exception: they keep the proportions they were drawn with.

## Your own segments

Conform to ``RouteSegment`` to add a shape of your own. Return the waypoints after `start`, in
points, with `y` increasing along the scroll axis. The map smooths them into the road.

```swift
struct Staircase: RouteSegment {
    var levelCount: Int

    func waypoints(from start: CGPoint, in context: RouteContext) -> [RouteWaypoint] {
        let step = context.length(forLevels: levelCount) / 4
        return (1...4).map { i in
            let x = i.isMultiple(of: 2) ? context.width * 0.25 : context.width * 0.75
            return RouteWaypoint(CGPoint(x: x, y: start.y + step * CGFloat(i)), isCorner: true)
        }
    }
}
```

Custom segments work everywhere a built-in one does, except ``RouteJSON``, which only knows the
built-in types.

## Design a route by dragging it

The `LevelMapEditor` product is a debug tool for designing routes on a live map: drag the
road's control points, add and reorder segments, try spacing and themes, then copy the result
as Swift code or JSON.

```swift
#if DEBUG
import LevelMapEditor

struct DesignScreen: View {
    var body: some View {
        LevelMapEditor(route: .forest, name: "forest",
                       themes: [NamedTheme("meadow", .meadow), NamedTheme("snow", .snow)])
    }
}
#endif
```

The exported Swift is a `LevelRoute` extension plus a `View` modifier for its spacing and
themes, ready to paste into your app. Ship the exported code, not the editor.

## Saving routes as data

``RouteJSON`` is the route as plain data, for a level designer's file or a server:

```swift
let data = try JSONEncoder().encode(RouteJSON(LevelRoute.forest))
let route = try JSONDecoder().decode(RouteJSON.self, from: data).route()
```

## Measuring a route

To place something of your own on the road, resolve the route for a width and spacing and ask
where a level is:

```swift
let road = LevelRoute.forest.resolved(width: 390, spacing: 110)
road.level(5_000)?.position   // CGPoint
road.level(5_000)?.angle      // the road's direction there
```
