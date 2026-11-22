# Changelog

## Unreleased

- Added `LevelMapCameraPosition` and a `position:` binding on all map initializers for automatic,
  fractional-level and avatar-follow framing. User scrolling writes back camera ownership.
- Bound framing takes precedence over legacy following; existing unbound camera APIs are unchanged.
  Recenter controls also work with the binding. Trail demonstrates the new API.

- Added collection initializers with explicit `id:` or `Identifiable` elements, including slices.
- Added `LevelMapDataSource.levelID(at:)`, with a positional default for existing sources.
- Node identities now follow model IDs within their lazy chunk. Moving across chunk boundaries
  may recreate local view state; store durable state in the model.
- Caller transaction animations take precedence over default camera and node animations.
  Disabled animation transactions and Reduce Motion suppress default map animations.


## 0.3.0 (2026-11-21)

### Added

- `levelMapRecenterButton(alignment:)` and `levelMapRecenterButton(alignment:_:)`, a "Back to
  you" button that appears while the avatar is off screen and the camera isn't following it.
- `levelMapContentMargins(_:_:)`, for panels that float over the map. The current level rests
  in the middle of what is left uncovered, and the avatar counts as off screen once it is under
  a panel.
- `levelMapMarks(_:at:placement:content:)` and `LevelMapMarkPlacement`, for views placed along
  the road that take touches, such as collectibles.
- A Lessons sample in the demo app: a course path in the style of language-learning apps, with no
  visible road, unit banners across the map and illustrations beside the path.
- The demo's `-clean` launch argument hides its controls, for screenshots.
- An examples gallery in the README.

### Changed

- The Trail demo uses `levelMapRecenterButton` in place of its own overlay.
- Faster updates while scrolling: distance checks against the road use an index, the avatar's
  visibility is worked out without redrawing the layers, and chunk scenes are reused within an
  update instead of being rebuilt for every visible chunk.

### Fixed

- When following stops, the zoom out and the scroll back to the avatar run as one animation
  instead of two that pull against each other.
- With content margins set, a level near either end of the map can scroll clear of the panel
  covering that edge, as `contentMargins` lets a list do.

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
