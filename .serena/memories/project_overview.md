# Fly Fishing Game — Current Project Overview

Godot 4.3 / GDScript project. Current supported runtime is a **3D-only first-person fly fishing game** set on an authored Lower Madison River / Black's Ford Bend reach.

## Current Runtime
- Entry scene: `scenes/SessionConfig.tscn`.
- Session start loads `res://scenes/RiverWorld3D.tscn`.
- Player scene: `scenes/FirstPersonAngler.tscn`.
- Legacy 2D runtime support was explicitly removed on 2026-05-27.
- Do not restore classic 2D selection or preserve removed 2D scenes/scripts unless user explicitly asks.

## Current Source of Truth
- `scripts/river/lower_madison_reach.gd` — authored reach geometry, water/land classification, habitats, current, fish holds, dry start.
- `scripts/river/river_3d_builder.gd` — visible 3D river/terrain/props/models built from authored reach.
- `scripts/river/river_world_3d.gd` — world orchestration, HUD, casting/drift state, environment.
- `scripts/player/first_person_angler.gd` and `scripts/player/fly_rod_3d.gd` — movement, camera, cast origin, rod/line.
- `scripts/models/fish_model_3d.gd` and `scripts/models/adult_insect_3d.gd` — procedural wildlife/insect models.
- Shared services retained: `DatabaseManager`, `GameManager`, `HatchManager`, `InputSetup`, `TimeOfDay`, `DifficultyConfig`.

## Docs
- Current docs: `README.md`, `CLAUDE.md`, `docs/LOWER_MADISON_REACH.md`, `assets/3d/README.md`.
- `GDD.md` and `TASKS.md` are historical 2D planning archives unless explicitly refreshed for 3D.

## Session / Commit Policy
- Routine tasks do **not** require transcript/blog docs.
- Create planning/session docs only for major planning sessions or when user asks.
- Never commit or tag unless user explicitly asks.