# ``LevelMapEditor``

Design a level map's road by dragging it on a live map, then export it as Swift or JSON.

## Overview

`LevelMapEditor` is a debug tool. Add it to a debug-only screen of your app, design the road on
a real device, and paste the exported code into your app. Ship the exported code, not the
editor.

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

The editor has three tabs:

- **Segments.** Add, reorder and remove segments, move them in and out of the repeating part,
  and set their level counts and shapes.
- **Look.** Spacing, which end the map starts at, and the themes, with chapters when you
  pick more than one.
- **Export.** Copy the design as Swift (a `LevelRoute` extension plus a `View` modifier for its
  look) or as `RouteJSON` from the `LevelMap` module.

On the map, drag the flag to move the road's start, and drag the handles to move spline and
polyline points, where a straight ends and how close a detour gets to the edge. Tap a segment's
label to select it.

Pass ``NamedTheme`` values using the names of the static properties that declare your themes, so
the exported code refers to them correctly. A route with segment types of your own has no JSON
form, so the editor opens on ``LevelMapDesign/starterRoute`` instead.

To keep a design between launches, store a ``LevelMapDesign`` (it is `Codable`) and pass a
binding to it with ``LevelMapEditor/LevelMapEditor/init(design:themes:)``.

## Topics

### The editor

- ``LevelMapEditor/LevelMapEditor``
- ``NamedTheme``

### Designs and exports

- ``LevelMapDesign``
- ``LevelMapExporter``
