# 3D Rework First-Person Prototype

2026-05-26 on branch `3d-rework`:
- Added first-person 3D path via `scenes/RiverWorld3D.tscn` and `scenes/FirstPersonAngler.tscn`.
- `scripts/ui/session_config.gd` now starts `res://scenes/RiverWorld3D.tscn` and updates title/hint text.
- Added `scripts/player/first_person_angler.gd` for WASD movement, mouse look, click/Space casting, Esc mouse release.
- Added `scripts/river/river_world_3d.gd` to generate seeded river data, build scene, place player, HUD, simple cast line/fly marker, and hold-water cast feedback.
- Added `scripts/river/river_3d_builder.gd` to convert existing `RiverData` into 3D runtime meshes: water skin, depth-color bed bands, banks, foam seams, reeds, rocks/boulders, driftwood logs, fish-shadow hold markers, and cottonwood-style trees. Headless rendering skips mesh construction to avoid Godot dummy-renderer mesh errors during CI-style checks.
- Added material assets in `assets/3d/materials/` plus `assets/3d/README.md`.
- Verified `godot4 --headless --path . --scene res://scenes/RiverWorld3D.tscn --quit` clean after mesh-skip guard. Also verified main startup scene with `godot4 --headless --path . --quit` before final facing adjustment.