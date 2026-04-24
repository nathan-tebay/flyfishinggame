# Sprite Implementation Plan

Branch: `sprites`

## Context

The sprite pack is located under `assets/sprites/` and includes one uniform casting strip plus several large cleaned atlas sheets. The current game mostly renders visuals procedurally, so the work should be integrated incrementally instead of replacing all rendering at once.

## Progress Legend

- `[ ]` Not started
- `[~]` In progress
- `[x]` Complete

## Session Plan

| Status | Session | Scope | Thinking Level |
| --- | --- | --- | --- |
| `[x]` | 1 | Add/import sprite assets, set Godot import settings, create reusable sprite constants/resources, commit baseline asset import state. | `medium` |
| `[x]` | 2 | Replace angler placeholder drawing with `AnimatedSprite2D`; implement `cast_overhead`; wire casting signals to animation state. | `medium` |
| `[x]` | 3 | Implement angler movement/wading sprite regions from `angler_moving_*`; choose frame regions manually and support directional/wading animations. | `high` |
| `[x]` | 4 | Replace or augment fish procedural rendering with species sprite atlas regions; preserve opacity/depth/state telegraph behavior. | `high` |
| `[x]` | 5 | Add dry-fly, insect, and rise/splash sprites where they fit existing drift/hookset flow. | `medium` |
| `[x]` | 6 | Add props from trees/boulders/river features as decorative `Sprite2D` overlays while keeping the procedural river renderer. | `high` |
| `[ ]` | 7 | Optional larger refactor: convert terrain/water sheets into TileSet/TileMap layers. This conflicts with the current continuous depth-field renderer, so it should be its own design session. | `xhigh` |

## Step Tracking

### Session 1: Baseline Asset Import

- `[x]` Add sprite pack under `assets/sprites/`.
- `[x]` Add Godot `.import` sidecars for all sprite PNGs.
- `[x]` Add a reusable sprite path catalog.
- `[x]` Run Godot headless import/startup validation.

### Session 2: Angler Cast Sprite

- `[x]` Add an `AnimatedSprite2D` node to `Angler.tscn`.
- `[x]` Generate `idle` and `cast_overhead` `SpriteFrames` from `angler_cast_overhead_48x96_strip.png`.
- `[x]` Replace procedural angler drawing when the sprite node is available.
- `[x]` Wire casting signals to play/reset the cast animation.
- `[x]` Run Godot headless startup validation.

### Session 3: Angler Movement/Wading Sprites

- `[x]` Identify reliable frame regions in `angler_moving_original.png` or `angler_moving_transparent.png`.
- `[x]` Define movement animation names and frame mappings.
- `[x]` Drive animation by movement direction and wading state.
- `[x]` Verify bank, shallow, and mid-depth movement readability.

Session 3 notes:

- Uses `angler_moving_transparent.png`.
- Uses columns 0-2 for land, 3-5 for shallow wading, and 6-8 for mid-depth wading.
- Uses rows 0, 2, 4, and 6 as north, east, south, and west directional animation rows.
- Keeps cast animation locked during casting and returns to movement/idle animation after cancel or drift start.

### Session 4: Fish Sprites

- `[x]` Select atlas regions for brown trout, rainbow trout, and mountain whitefish.
- `[x]` Add sprite-based fish rendering while preserving depth opacity.
- `[x]` Preserve alert/spooked visual telegraph behavior.
- `[x]` Verify fish scale by size class.

Session 4 notes:

- Uses hand-selected top-down swim-frame regions from the brown trout, rainbow trout, and mountain whitefish sheets.
- Rotates atlas fish -90 degrees at draw time so their heads face upstream/left, matching existing FishAI assumptions.
- Scales sprite length by fish size class and keeps procedural rendering as a fallback if sprite loading fails.
- Preserves depth/time opacity, intrusion memory tint, and alert/spooked/recovering telegraph tint.

### Session 5: Insects, Flies, and Rise Effects

- `[x]` Select regions for visible fly, insect particles, and rise/splash effects.
- `[x]` Replace or augment procedural insect dots.
- `[x]` Replace or augment dry-fly float and rise indicator visuals.
- `[x]` Verify hookset timing remains clear.

Session 5 notes:

- Uses `aquatic_insects_lifecycle_transparent_sheet.png` for drifting nymph-style insect particles.
- Uses `aquatic_insects_flies_topdown_transparent_sheet.png` for skittering adult particles and the visible dry fly.
- Uses a splash/rise region from `rainbow_trout_transparent_sheet.png` layered under the existing dry-fly rise ring.
- Keeps the hookset controller state machine and timing unchanged; this is visual-only integration.

### Session 6: Decorative Props

- `[x]` Select tree, boulder, and river feature regions.
- `[x]` Add sprite overlay placement while preserving procedural river generation.
- `[x]` Add Y-sort/collision considerations for large props.
- `[x]` Verify section generation performance.

Session 6 notes:

- Uses selected regions from `trees_transparent_sheet.png`, `boulders_transparent_sheet.png`, and `river_environment_features_transparent_sheet.png`.
- Replaces generated bank trees/boulders with sprite overlays when textures are available, with procedural drawing retained as fallback.
- Adds sprite overlays for grass/bank cover, submerged weed beds, and log structures while preserving the continuous river renderer.
- Uses z-index ordering for visual layering; no collision was added because movement remains tile-based and these are decorative props.
- Verified with a 60-frame RiverWorld generation/runtime check.

### Session 7: Optional TileSet Refactor

- `[ ]` Decide whether atlas-driven terrain should replace the procedural depth renderer.
- `[ ]` Prototype TileSet/TileMap layers from water and terrain sheets.
- `[ ]` Compare visual quality/performance against the current renderer.
- `[ ]` Keep or discard as a separate design decision.

## Recommended Path

Complete sessions 1-6 incrementally and defer session 7 unless the goal is to replace the procedural river look with atlas-driven tile layers.
