# TalkBack + IMDF Accessibility Bridge for Godot Engine

A Godot 4 addon that bridges a dynamically rendered indoor map (IMDF — Indoor Mapping Data Format)
to Android's native accessibility framework, so **Android TalkBack** can navigate and activate
map rooms using standard accessibility actions instead of custom gesture detection.

> Developed as an academic project undertaken as part of the **Samsung PRISM** program. See
> [LICENSE](./LICENSE) — this repository is public for portfolio and demonstration purposes; it is
> not released under a permissive open-source license.

## The problem this solves

The map is drawn as raw pixels — rectangles, polygons, text — using Godot's low-level 2D drawing
API (`_draw()`). Screen readers have no visibility into pixels; they can only see real UI nodes
that the OS accessibility framework knows about. Without a bridge, a blind user pointed at a
beautifully rendered indoor map would hear nothing at all.

## The fix

An invisible layer of real `Button` nodes is placed exactly on top of each rendered room —
invisible to sighted users, but fully visible to Android's accessibility framework, so TalkBack can
focus each room, read its name aloud, and activate it, while the pixels underneath are drawn
exactly as before.

## Architecture

![System architecture](docs/architecture.png)

- **`imdf_parser.gd`** — parses IMDF JSON into typed data, builds a navigation graph, and finds
  accessible routes between rooms via BFS.
- **`dynamic_mapview.gd`** — the main `Control`. `_draw()` renders rooms/POIs (unchanged, pixel
  rendering). The **Native UI Bridge** builds and synchronizes an invisible accessibility overlay
  alongside it.
- **`talkback_gesture_handler.gd`** — a prototype gesture-based screen-reader simulator, kept for
  editor/non-Android testing and automatically bypassed when a real screen reader is detected.
- **`test_native_accessibility_validation.gd`** — a white-box validation suite that calls the same
  handler functions Android's native accessibility actions invoke, directly.

Rendering and accessibility are two parallel systems, kept in sync by re-using the exact same
zoom/pan transform math — accessibility is never derived from pixels, and pixels are never derived
from the accessibility tree.

See [`addons/talkback_imdf_system/IMPLEMENTATION_GUIDE.md`](addons/talkback_imdf_system/IMPLEMENTATION_GUIDE.md)
for the full technical design, and [`docs/engine-fix.md`](docs/engine-fix.md) for the Phase 1
engine-level context this addon depends on.

## Key design decisions

| Decision | Why |
|---|---|
| Invisible `Button` overlay parallel to `_draw()` | Keeps the existing, verified rendering pipeline completely untouched; accessibility is additive, not a rewrite. |
| Accessibility node creation order follows the IMDF navigation graph (BFS), with a geometric fallback | Verified directly from Godot's engine source that Android's accessibility traversal follows scene-tree child order, not `focus_neighbor_*` (which only drives keyboard/gamepad navigation). |
| Validation suite calls handler functions directly instead of simulating touch/gesture input | Real TalkBack bypasses Godot's `InputEvent` pipeline entirely (native `ACTION_FOCUS`/`ACTION_CLICK`), so simulating input events would test a path TalkBack doesn't actually use. |
| BFS for route-finding | Unweighted graph, small room counts — gives the shortest hop-count route without the added complexity of Dijkstra/A*. |

## Running it

1. Open this folder as a project in the **official Godot 4.7 Stable Editor**.
2. Confirm the plugin **TalkBack + IMDF System** is enabled under *Project → Project Settings → Plugins*.
3. Open and run `map_view_test.tscn`.
4. In the Editor, `Tab`/`Shift+Tab` move accessibility focus forward/backward between rooms (this
   uses the same scene-tree order mechanism Android's accessibility tree relies on); `Enter`
   activates the focused room.

## Validation

Three explicitly separated validation tiers were used, since a Samsung embedded MapView / physical
device environment was not available during development:

1. **Code-level** — verified by direct source inspection (this addon's GDScript and the relevant
   Godot engine C++).
2. **Editor-level** — the addon running inside the official Godot 4.7 Stable Editor: correct node
   creation, correct properties, correct signal behavior, Tab/Shift+Tab/Enter interaction, no
   drift after zoom/pan/resize/reload.
3. **Android runtime** — real TalkBack gesture behavior, spoken announcements, and the AccessKit
   Android adapter's internal traversal logic were **not verified on a physical device** and would
   require Samsung's embedded environment to confirm.

Run `addons/talkback_imdf_system/test/test_native_accessibility_validation.gd` (attach it to a bare
`Node` in a scene and run it) for the automated, code-level validation suite.

## Repository scope

This repository contains only the addon and the minimal Godot project needed to run it — it is not
a fork of the Godot Engine source tree. A small, prior fix to Godot's own C++ AccessKit driver
(Phase 1 of this project) is documented, not redistributed, in [`docs/engine-fix.md`](docs/engine-fix.md).

## License

See [LICENSE](./LICENSE). All rights reserved — published for demonstration and portfolio purposes.
