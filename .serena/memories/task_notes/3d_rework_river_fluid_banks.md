# 3D Rework River/Bank/Fluid Pass

2026-05-26:
- Updated `scripts/river/river_3d_builder.gd` to generate flow-aware 3D water and richer bank features.
- `River3DBuilder` now encodes water vertex color channels as R=current speed, G=shallow/deep blend, B=bank-edge turbulence, A=foam seed. Water drag uses depth+current.
- Added `assets/3d/shaders/river_water.gdshader` and changed `assets/3d/materials/river_water.tres` to a ShaderMaterial with animated wave displacement, flow streaks, foam mixing, transparency, roughness/specular changes.
- Added `assets/3d/shaders/foam_flow.gdshader` and changed `assets/3d/materials/foam.tres` to animated foam/eddy ShaderMaterial.
- Added `assets/3d/materials/bank_soil.tres` and `willow_leaf.tres`.
- Banks now have terraced height, undercut soil faces, gravel edge patches, grass tufts, willow shrubs, exposed root tangles, reeds, trees, rocks/logs.
- `scripts/river/river_world_3d.gd` now uses `builder.ground_height_at()` for player surface height and HUD shows local current.
- Verified clean: `godot4 --headless --path . --scene res://scenes/RiverWorld3D.tscn --quit` and `godot4 --headless --path . --quit`.
- Forced mesh-build smoke with `/tmp/validate_river_3d_builder.gd` created 92 builder children; dummy renderer gave expected mesh warnings but no script/runtime errors.