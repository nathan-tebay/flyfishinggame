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
| `[ ]` | 3 | Implement angler movement/wading sprite regions from `angler_moving_*`; choose frame regions manually and support directional/wading animations. | `high` |
| `[ ]` | 4 | Replace or augment fish procedural rendering with species sprite atlas regions; preserve opacity/depth/state telegraph behavior. | `high` |
| `[ ]` | 5 | Add dry-fly, insect, and rise/splash sprites where they fit existing drift/hookset flow. | `medium` |
| `[ ]` | 6 | Add props from trees/boulders/river features as decorative `Sprite2D` overlays while keeping the procedural river renderer. | `high` |
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

- `[ ]` Identify reliable frame regions in `angler_moving_original.png` or `angler_moving_transparent.png`.
- `[ ]` Define movement animation names and frame mappings.
- `[ ]` Drive animation by movement direction and wading state.
- `[ ]` Verify bank, shallow, and mid-depth movement readability.

### Session 4: Fish Sprites

- `[ ]` Select atlas regions for brown trout, rainbow trout, and mountain whitefish.
- `[ ]` Add sprite-based fish rendering while preserving depth opacity.
- `[ ]` Preserve alert/spooked visual telegraph behavior.
- `[ ]` Verify fish scale by size class.

### Session 5: Insects, Flies, and Rise Effects

- `[ ]` Select regions for visible fly, insect particles, and rise/splash effects.
- `[ ]` Replace or augment procedural insect dots.
- `[ ]` Replace or augment dry-fly float and rise indicator visuals.
- `[ ]` Verify hookset timing remains clear.

### Session 6: Decorative Props

- `[ ]` Select tree, boulder, and river feature regions.
- `[ ]` Add sprite overlay placement while preserving procedural river generation.
- `[ ]` Add Y-sort/collision considerations for large props.
- `[ ]` Verify section generation performance.

### Session 7: Optional TileSet Refactor

- `[ ]` Decide whether atlas-driven terrain should replace the procedural depth renderer.
- `[ ]` Prototype TileSet/TileMap layers from water and terrain sheets.
- `[ ]` Compare visual quality/performance against the current renderer.
- `[ ]` Keep or discard as a separate design decision.

## Recommended Path

Complete sessions 1-6 incrementally and defer session 7 unless the goal is to replace the procedural river look with atlas-driven tile layers.
