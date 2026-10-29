# 3D Rework Current State — Authoritative Guardrail

As of 2026-05-28, this memory supersedes older `task_notes/3d_rework_*` notes when they conflict.

## Supported Runtime
- The project is 3D-only.
- `scenes/SessionConfig.tscn` starts `res://scenes/RiverWorld3D.tscn`.
- Legacy 2D support and selectable classic mode were removed on 2026-05-27 by explicit user direction.

## River / Terrain
- Visible runtime uses authored Lower Madison / Black's Ford Bend reach data in `scripts/river/lower_madison_reach.gd`.
- `scripts/river/river_3d_builder.gd` builds continuous bounded water, carved cobble bed, bank terrain, wet shoreline blends, grounded gravel bars/aprons, props, fish, and insects from authored reach queries.
- Do not treat older seeded `RiverData`/tilemap/2D renderer notes as current runtime guidance.
- Current depth/current model includes wadable-depth limits, deep pools, outside-bend/seam/boulder/shoal effects, depth bands, turbulence, foam tendency, curvature, and surface flow direction.
- Player movement is blocked in non-wadable water; casts use bounds-only clamp.

## Water / Foam / Shards
- Separate bright foam/riffle decal meshes were removed/suppressed after white-shard feedback.
- Turbulence should be integrated into `assets/3d/shaders/river_water.gdshader` and `assets/3d/materials/river_water.tres`.
- Water shader uses `assets/3d/textures/river_flow_streaks.png` and `river_micro_normals.png` helper textures.
- Maintain upward-facing water/bed/bank normals, no folded water/banks, and no water under dry exposed bar footprints.
- Fish fins were identified as a source of bright triangular shards and changed to opaque matte/darker smaller fins; do not revert to translucent large fish-fin panels without explicit reason.

## Visual Models / HUD
- Procedural 3D fish models: rainbow trout, brown trout, mountain whitefish.
- Adult insects: mayfly and caddis models.
- Player uses full-length fly rod model with guides/reel/line and rod-tip cast origin.
- HUD shows selected fly/adult phase, casting state, local depth/current, and debug water views (0 off, 1 depth, 2 current, 3 turbulence/foam, 4 curvature, 5 normal flow).

## Validation Baseline
- `godot4 --headless --path . --scene res://scenes/RiverWorld3D.tscn --quit`
- `godot4 --headless --path . --scene res://scenes/SessionConfig.tscn --quit` when startup touched
- `git diff --check`
- Reach/mesh/water focused checks when relevant: dry spawn/bar classification, required habitats, no folds, upward normals, no dry-water tris, wading block behavior.
- Interactive screenshot/GPU review still required for visual realism acceptance.