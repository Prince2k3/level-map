# Changelog

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
