# Removed 2D Runtime

On 2026-05-27 the user explicitly directed `remove 2d support`, superseding the previous requirement to preserve/select classic 2D mode.

## Changes
- `scripts/ui/session_config.gd` no longer exposes runtime mode selection and always enters `res://scenes/RiverWorld3D.tscn`.
- Deleted legacy 2D scenes: `scenes/RiverWorld.tscn`, `scenes/Angler.tscn`, `scenes/Fish.tscn`, `scenes/Main.tscn`.
- Deleted legacy Node2D implementation under `scripts/angler`, `scripts/camera`, `scripts/casting`, `scripts/catching`, `scripts/fish`, `scripts/flies`, old river generator/renderer/data/atlas scripts, 2D UI panels/overlays, and tile extraction/generation tools.
- Deleted tracked legacy sprite/tiled terrain asset trees and old tile-planning docs; deleted unused old `river_shallow`, `river_mid`, and `river_deep` legacy 3D materials.
- Retained shared database/session/time/hatch services and difficulty config for the supported 3D runtime. `scripts/autoloads/input_setup.gd` now registers only movement, complete-cast, and pause controls needed by 3D.
- Updated README/CLAUDE as 3D-only documentation and marked GDD/TASKS as historical 2D archives. Session 8 notes record that the follow-up removal supersedes earlier selectable-classic notes.
- Cleared ignored local `.godot/editor` state containing paths to deleted 2D scenes/scripts so editor rescans no longer report those missing resources.

## Verification
- Live-source grep: no runtime/source references to removed 2D files or asset folders; only deliberate negative statement in `CLAUDE.md` remains.
- `git diff --check` passes.
- `godot4 --headless --path . --script /tmp/test_reach_queries.gd` passes: fixed reach length 509.31, dry start and dry exposed bar, all seven habitat zones.
- `godot4 --headless --path . --scene res://scenes/SessionConfig.tscn --quit` passes.
- `godot4 --headless --path . --scene res://scenes/RiverWorld3D.tscn --quit` passes.
- `godot4 --headless --editor --path . --quit-after 5` no longer emits missing 2D resource errors after clearing stale layout state; the third-party GDSQLite editor shutdown still logs `Can't close database if connection is not open!`, unrelated to removed runtime.