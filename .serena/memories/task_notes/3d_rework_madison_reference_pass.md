# 3D Rework Madison Reference Pass

2026-05-26:
- Used web references from Montana Angler describing Madison River visual/habitat traits: Upper Madison/50-Mile Riffle, shallow swift riffles, huge glacial boulders, islands/side channels, cut banks, gravel depressions, broad valley flanked by Madison/Gravelly/Tobacco Root ranges; rocks produce soft water and gravel bars behind them.
- `assets/3d/shaders/river_water.gdshader`: made water opaque/darker blue-green, no alpha sky blending; reduced foam/emission further.
- `assets/3d/materials/river_water.tres`: synced darker shader params.
- Added `assets/3d/materials/river_cobble.tres`.
- `scripts/river/river_3d_builder.gd`: added Madison gravel bars, cobble beds, extra midriver boulders; reduced foam density/size and removed default foam from all shallow surface tiles.
- `scripts/river/river_world_3d.gd`: pushed/lowered/lightened mountain ridges, increased cool fog slightly so they blend instead of forming a gray wall.
- Verified clean: `godot4 --headless --path . --scene res://scenes/RiverWorld3D.tscn --quit` and `godot4 --headless --path . --quit`. Forced mesh build produced 103 builder children with expected dummy-renderer warnings only.