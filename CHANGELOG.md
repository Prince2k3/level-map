# Changelog

## 0.2.0 (2026-11-18)

### Added

- `levelMapLayer(_:content:)`, which draws your own views under the road, over it or over the
  nodes. The closure gets a `LevelMapGeometry` with `point(atLevel:)`, `heading(atLevel:)`,
  `roadPath(from:to:)`, `distanceToRoad(from:)` and `placement(ofLevel:)`.
- A `LevelMap` init whose node closure also gets a `LevelPlacement`: how far across the map the
  level is, which side it is on, and the road's heading.
- `RoadStyle` options: `lineCap`, `dash`, `completedWidth` and `completedGlow`, and the
  `.dotted(_:completed:dotSize:gap:completedWidth:glow:)` preset.
- `levelMapFollowsAvatar(_:zoom:anchor:scalesMarkers:)`, a camera that zooms in on the avatar
  and follows it, and `EnvironmentValues.levelMapZoom`.
- `onLevelMapAvatarVisibilityChange(_:)`, `levelMapRecenter(on:)` and `levelMapFocusOffset(_:)`.
- A "Layers, placement and the camera" DocC article.
- A Trail sample in the demo app that uses all of these. It runs bottom-up and follows the walker as it climbs.

### Fixed

- Scrolling to a level deep in an endless map no longer stalls for seconds while every earlier
  chunk is built. This was the freeze and snap seen each time a walk arrived at a level.
- While the avatar walks, the map glides along with it instead of waiting and catching up on
  arrival. It only does this while the avatar is on screen, so a player who has scrolled away
  isn't pulled back.
- Deep in long maps, `onLevelMapAvatarVisibilityChange(_:)` reported the avatar as off screen
  while it was in view.
- A walk no longer pauses on arriving at a level: each step moves at the same pace, and the
  camera aims at how far the avatar has walked rather than the level it is heading to.
- A finite map is exactly as long as its road, so it no longer scrolls on past its last level.
- While the camera follows the avatar, the magnified map no longer takes touches meant for the
  views around it. In the Trail demo, this made Stop and every other control stop working
  during a walk.
- Layers are given a steady size, so an `Equatable` layer isn't redrawn on every frame while
  the map glides.
- In the demo, the walker sits on the road instead of floating above it, and the Trail sample is
  endless. Its terrain is drawn with paths, so it covers every chunk that pages in.

## 0.1.0 (2026-11-17)

The first release.

### LevelMap

- `LevelMap`, a scrolling level map for any data source: arrays, ranges, `EndlessLevels` or your
  own `LevelMapDataSource`. It works vertically or horizontally, from either end.
- `LevelRoute`, a result builder with these segments:
  - `Start`
  - `Straight`
  - `Serpentine`
  - `Zigzag`
  - `Detour`
  - `Spline`
  - `Polyline`
  - `Repeat`
  - your own `RouteSegment` types
- Ready-made routes: `.serpentine`, `.zigzag`, `.straight`, `.spline` and `.points`.
- `ResolvedRoute`, which measures a route and finds level positions without drawing it.
- The map is built in chunks only as they come into view, and endless maps page.
- `LevelMapTheme`:
  - backgrounds;
  - `RoadStyle`, with an outline, a centre line and an optional shader;
  - seeded `Decoration` scenery that stays clear of the road;
  - a new theme every chapter, with transitions.
- Progress: `LevelState`, a completed road that grows, an avatar that walks, and
  `levelMapUnlockAnimation`. Reduce Motion is respected.
- `levelMapProgress(toNext:)`, which places the avatar and the completed road part of the way to
  the next level, and `ResolvedRoute.distance(ofLevel:progress:)`.
- VoiceOver: nodes are read in road order with their state, and there is a "Current level" rotor.
- `RouteJSON`, a Codable form of built-in routes.
- DocC guides:
  - Quick start
  - Designing routes
  - Themes and decorations
  - Endless maps and paging

### Fixes found by the UI tests

- On arriving at a level while walking, the avatar is placed from the progress it held rather
  than the new level's progress, so it can't briefly run back along the leg it just walked. This
  is defensive: the demo's walk didn't reproduce the back-run.
- The road is drawn in one layer behind every chunk's levels. Each chunk used to draw its own
  road, so a later chunk's road could cover the last levels of the chunk before it. This was
  most visible when a walk arrived at a level and the chunks redrew.
- `levelMapEdgeInset(_:)` sets how close levels may come to the map's edges. It is
  `RouteContext.edgeInset` and `resolved(width:spacing:edgeInset:)` in the route API, and
  defaults to half the spacing. Routes that stray inside it are scaled in across the map. The
  first and last levels get at least that margin along the scroll axis too, so the start node no
  longer clips at the edge.

### LevelMapEditor

- `LevelMapEditor`, a debug view for designing a route on a live map. You can drag handles, edit
  segments, set the look and chapters, and export to Swift or JSON.
