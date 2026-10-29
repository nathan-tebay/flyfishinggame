# 3D Rework Realistic Current-Reach Flow

Implemented on 2026-05-27 for the authored Lower Madison Black's Ford reach.

## Changes
- `scripts/river/lower_madison_reach.gd`
  - Added fixed `WADABLE_DEPTH_LIMIT := 0.82` and depth debug max.
  - Added authored `DEEP_POOLS` for boulder-pocket holes, outside-bend pools, deep seam pool, bank-pocket hole, and main-run hole.
  - `sample()` now returns `is_wadable`, `depth_band`, `surface_flow_direction`, `visual_turbulence`, `foam_tendency`, and `curvature`.
  - Depth model now combines base reach depth, outside seam, pool extra depth, boulder scour, and point-bar shoal lift.
  - Current strength, turbulence, foam tendency, curvature, and surface flow include pool/curvature/boulder/shoal effects.
- `scripts/river/river_3d_builder.gd`
  - Water vertex colors now pack current/depth/turbulence/curvature for shader and debug views.
  - Bed/depth color scale uses reach debug max.
  - Shoreline and point-bar apron/lift values lowered so bars and wet edges sit into the water more naturally.
- `assets/3d/shaders/river_water.gdshader` + `assets/3d/materials/river_water.tres`
  - Water shader now uses generated tileable flow-streak and micro-normal textures.
  - Deep water darkens/absorbs; shallow water stays clearer; foam is muted and gated to high turbulence.
  - Added `debug_view` modes for depth, current, turbulence/foam, curvature, and normal-flow texture.
- New generated textures committed under `assets/3d/textures/`:
  - `river_flow_streaks.png` + `.import`
  - `river_micro_normals.png` + `.import`
- `scripts/river/river_world_3d.gd`
  - Player movement speed returns 0 in non-wadable water.
  - `clamp_player_position()` now blocks deep water by returning last wadable position; casts use bounds-only clamp.
  - Runtime HUD reports depth band/current and adds number-key debug controls (`0` off, `1` depth, `2` current, `3` turbulence/foam, `4` curvature, `5` normal flow).
  - Debug readout label shows local habitat, depth, wadable flag, current vector, turbulence, foam, curvature, station, and lateral.

## Validation
- `godot4 --headless --path . --script /tmp/test_reach_flow.gd`: `max_depth=1.064`, `max_turbulence=0.910`, `deep=49`, `wadable=838`, `bars_dry=true`.
- `godot4 --headless --path . --scene res://scenes/RiverWorld3D.tscn --quit`: pass.
- `godot4 --headless --path . --script /tmp/test_reach_mesh_clean.gd`: `normal_down=0`, `dry_water_tris=0`, `transition_span=0.718`; dummy renderer emits expected mesh shutdown warnings after exit.
- `godot4 --headless --path . --script /tmp/test_wading_block.gd`: deep seam `depth=1.032`, `wadable=false`, `blocked=true`.
- `godot4 --headless --path . --quit`: pass.
- Whitespace check on touched text files: pass.

No commit was made.