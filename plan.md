# Sprite Implementation Plan

Branch: `sprites`

## Context

The sprite pack is located under `assets/sprites/` and includes one uniform casting strip plus several large cleaned atlas sheets. The regenerated terrain TileSet pack now lives under `assets/terrain/river_atlas/`. The current game still uses a custom renderer for production river visuals, so terrain atlas work should stay explicit about whether it is prototype/editor support or live runtime integration.

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
| `[x]` | 7 | Optional larger refactor: convert terrain/water sheets into TileSet/TileMap layers. This conflicts with the current continuous depth-field renderer, so it should be its own design session. | `xhigh` |
| `[x]` | 8 | Create a strict river sprite atlas catalog and remove old `assets/tiles` dependencies from river rendering/prototype definitions. | `high` |
| `[x]` | 9 | Replace the production base river/bank chunk bake with a sprite-only atlas compositor, including water/bank/depth variation rules. | `xhigh` |
| `[x]` | 10 | Replace remaining generated in-river structure effects with sprite-only overlays/animated atlas effects. | `high` |
| `[x]` | 11 | Tune scale, draw order, transitions, and performance for the sprite-only river renderer. | `high` |

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

- `[x]` Decide whether atlas-driven terrain should replace the procedural depth renderer.
- `[x]` Prototype TileSet/TileMap layers from water and terrain sheets.
- `[x]` Compare visual quality/performance against the current renderer.
- `[x]` Keep or discard as a separate design decision.

Session 7 notes:

- Added `RiverAtlasTilePrototype`, a standalone `TileMap` prototype that builds a runtime `TileSet` from selected atlas/source tile regions and renders existing `RiverData`.
- The prototype rendered one full generated section: 1,440 columns by 30 rows, 43,200 cells.
- Decision: keep the current continuous depth-field `RiverRenderer` as the production renderer. It gives smoother organic transitions, preserves rock wake effects, and avoids visible grid seams.
- Keep the atlas TileMap prototype as a comparison/development tool only. Do not wire it into `RiverWorld` unless a future design pass explicitly chooses a tile-based river style.

### Post-Session Visual Corrections

- `[x]` Reduce the angler sprite scale by roughly 50% relative to the scene read, using a 0.67 render scale and adjusted foot anchoring.
- `[x]` Replace production river chunk baking with atlas/source tile blits when sprite assets are available, so water/river tiles visibly use sprite art instead of the continuous procedural colour field.
- `[x]` Replace in-river procedural rock/boulder polygons with boulder-sheet sprites while preserving wake seam effects.
- `[x]` Reduce log and weed-bed enlargement and enable linear texture filtering to avoid visibly pixelated over-scaling.
- `[x]` Remove old `assets/tiles` references from river base definitions; bank, gravel, and undercut base art now resolve through sprite-sheet atlas regions.

### Session 8: Strict River Sprite Atlas Source

- `[x]` Add a centralized `RiverSpriteAtlas` catalog for river base tiles and prop regions.
- `[x]` Move river base definitions to `assets/sprites/spritesheets/*` atlas regions only.
- `[x]` Wire `RiverRenderer` base chunk selection through `RiverSpriteAtlas`.
- `[x]` Remove the conditional procedural colour-field fallback from active chunk rendering.
- `[x]` Wire the TileMap prototype through the same sprite atlas catalog so it cannot drift back to old tile files.
- `[x]` Verify no river renderer/prototype code references `assets/tiles`.
- `[x]` Session 9 follow-up: improve atlas compositing quality with sprite variation and transition selection instead of one repeated 32x32 sample per tile type.

### Session 9: Sprite-Only Base Compositor

- `[x]` Add large atlas source blocks for bank grass, bank soil, gravel, shallow/mid/deep water, high-current water, and depth transitions.
- `[x]` Add deterministic 32x32 subregion sampling from larger sprite blocks so adjacent sections avoid one repeated tile crop.
- `[x]` Select bank edge art separately from bank interior grass.
- `[x]` Select high-current/ripple water art from the sprite sheet when current is strong.
- `[x]` Select shallow-to-mid, mid-to-deep, and shallow-to-deep transition source blocks from neighboring depth classes.
- `[x]` Route weed, log, rock, and boulder base cells through in-water feature blocks by depth class.
- `[x]` Keep the compositor strict: all production base art still resolves through `assets/sprites` atlas regions.
- `[x]` Session 10 follow-up: replace remaining generated wake/seam and fallback structure drawing paths with sprite-only overlays/effects.

### Session 10: Sprite-Only Structure Effects

- `[x]` Remove the inactive procedural depth-field renderer from `RiverRenderer`.
- `[x]` Remove generated rock/boulder polygon fallback drawing.
- `[x]` Remove generated wake seam `Line2D` effects behind rocks/boulders.
- `[x]` Remove generated driftwood/log fallback drawing.
- `[x]` Remove generated tree, bush, and bank-boulder fallback drawing.
- `[x]` Keep debug hold overlays separate; debug still uses temporary polygons only when the debug overlay is enabled.
- `[x]` Session 11 follow-up: tune sprite scale, density, z-ordering, and performance now that the production path is sprite-only.

### Session 11: Sprite Scale, Density, and Ordering

- `[x]` Reduce bank prop density so large sections do not spawn excessive overlay nodes.
- `[x]` Make bank tree/grass/boulder placement deterministic by tile hash instead of dense sequential random placement.
- `[x]` Reduce tree, grass, boulder, weed-bed, log, and in-river rock target scales to limit pixelation and overdraw.
- `[x]` Enable Y-sort on the river renderer and make prop z-indexes absolute for clearer layering.
- `[x]` Keep water/base chunks as 24 baked sprites per section while limiting dynamic overlay count.
- `[ ]` Follow-up outside the sprite implementation plan: review the game visually in the editor and tune individual atlas crop choices if any selected source block reads poorly in motion.

## Recommended Path

Sessions 1-11 are complete. The current production direction is still the custom sprite-atlas river renderer: `RiverData` remains the gameplay map, while river base visuals and structure overlays resolve through `assets/sprites` source sheets. The regenerated terrain TileSet pack under `assets/terrain/river_atlas/` is kept as a normalized comparison/editor asset path until a future runtime integration pass adopts it deliberately.
