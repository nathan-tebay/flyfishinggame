# 3D Rework Submerged Weed / Remaining Shard Suppression

Follow-up on 2026-05-28 after user confirmed bright shard artifacts persisted after fish fin darkening.

## Diagnosis
Remaining large pale shards matched `FixedWeedEdges`: submerged weed blade quads. The shader used `UV.y` as tip height, but builder `_add_vertex()` supplied world-space UVs (`point.xz * 0.14`), so tip height/sway/alpha were not normalized. With `blend_mix` + `depth_prepass_alpha`, weed blade planes could render as bright/transparent panels in clear water.

## Fix
- `assets/3d/shaders/submerged_weeds.gdshader`
  - Removed alpha blending/depth prepass; weed material is now opaque matte/dark.
  - Clamps tip-height UV and lowers sway strongly.
- `assets/3d/materials/submerged_weeds.tres`
  - Dark matte color and low sway parameters.
- `scripts/river/river_3d_builder.gd`
  - Replaced vertical submerged weed blades with low bed-hugging weed mats using `FixedWeedEdges`, so no upright panels remain in the water column.
  - Added `_add_weed_patch_quad()` and `_weed_patch_point()`.
  - Left old `_add_blade()` helper unused for now.
- `assets/3d/materials/insect_wing.tres`
  - Removed alpha transparency from insect wings too, eliminating the last non-water transparent triangle material.

## Validation
- `grep -R "transparency = 1\|depth_prepass_alpha\|blend_mix"` under 3D materials/shaders/scripts now only finds old unused `foam_flow.gdshader` and active `river_water.gdshader`; no non-water alpha triangle materials remain.
- `godot4 --headless --path . --scene res://scenes/RiverWorld3D.tscn --quit`: pass.
- `godot4 --headless --path . --quit`: pass.
- `git diff --check` on touched files: pass.

Need user GPU screenshot to confirm. No commit was made.