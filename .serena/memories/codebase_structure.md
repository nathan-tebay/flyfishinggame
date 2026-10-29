# Codebase Structure — Current 3D-Only Runtime

```
flyfishinggame/
├── project.godot
├── run.sh
├── README.md / CLAUDE.md
├── docs/
│   └── LOWER_MADISON_REACH.md
├── scenes/
│   ├── SessionConfig.tscn      # entry/config scene
│   ├── RiverWorld3D.tscn       # supported game runtime
│   └── FirstPersonAngler.tscn  # first-person player scene
├── scripts/
│   ├── autoloads/
│   │   ├── database_manager.gd
│   │   ├── game_manager.gd
│   │   ├── hatch_manager.gd
│   │   ├── input_setup.gd
│   │   └── time_of_day.gd
│   ├── models/
│   │   ├── adult_insect_3d.gd
│   │   └── fish_model_3d.gd
│   ├── player/
│   │   ├── first_person_angler.gd
│   │   └── fly_rod_3d.gd
│   ├── river/
│   │   ├── lower_madison_reach.gd
│   │   ├── river_3d_builder.gd
│   │   └── river_world_3d.gd
│   └── ui/
│       └── session_config.gd
├── resources/
│   └── difficulty_config.gd
└── assets/3d/
    ├── geodata/       # archived NHD/3DEP sources and runtime sample data
    ├── materials/     # Godot materials for river, terrain, fish, insects, rod
    ├── pbr/           # ambientCG PBR maps, if present/imported
    ├── shaders/       # water, bed, terrain, vegetation shaders
    └── textures/      # authored/generated flow helper textures
```

## Removed / Historical
- Legacy 2D scenes/scripts/assets were removed on 2026-05-27.
- Do not reference deleted `RiverWorld.tscn`, `Angler.tscn`, `Fish.tscn`, `Main.tscn`, old 2D fish/casting/river renderer scripts, or tile/sprite terrain assets as active runtime.

## Autoloads
- `DatabaseManager` — persistence / SQLite.
- `GameManager` — session lifecycle.
- `HatchManager` — hatch/adult insect state.
- `InputSetup` — movement, cast, fly-cycle, pause bindings.
- `TimeOfDay` — time cycle/signals.

## DB
SQLite via godot-sqlite plugin at `user://flyfishing.db`. Treat plugin shutdown warning about closing unopened DB as known third-party noise if no new errors appear.