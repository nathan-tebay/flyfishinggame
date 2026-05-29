# Fly Fishing Game

First-person 3D fly fishing environment set on a compressed real bend of the Lower Madison River immediately upstream of Black's Ford, Montana. Built in Godot 4.3 with GDScript and Forward+ desktop rendering.

## Current vertical slice

- Walk a dry riparian bank and wade into moving water.
- Select adult mayfly or caddis dry-fly imitations and cast into authored habitat zones.
- Read local habitat/current, selected fly, casting state, and nearby fish-hold response in the HUD.
- Observe modeled rainbow trout, brown trout, mountain whitefish, and sparse adult surface insects.
- Explore a fixed USGS-derived bend with gravel shelves, exposed bars, submerged cobble, weed edges, boulders, willows, cottonwoods, and valley relief.

Session seeds change fish-hold occupancy/session conditions, not terrain or prop geometry.

## Quick start

```bash
./run.sh setup     # Download godot-sqlite plugin (first-time setup)
./run.sh run       # Run the game (requires Godot 4.3 and GPU)
./run.sh editor    # Open Godot editor
```

Controls: `WASD` move, mouse look, click or `Space` cast, `Q` cycle adult dry fly, `Esc` release/capture mouse.

## Validation

```bash
godot4 --headless --path . --scene res://scenes/RiverWorld3D.tscn --quit
godot4 --headless --path . --quit
```

## Project structure

```
flyfishinggame/
├── scenes/
│   ├── SessionConfig.tscn       # Session setup / entry
│   ├── RiverWorld3D.tscn        # Playable first-person river world
│   └── FirstPersonAngler.tscn   # First-person controller
├── scripts/
│   ├── river/
│   │   ├── lower_madison_reach.gd  # Fixed reach data/query interface
│   │   ├── river_3d_builder.gd     # Authored terrain/channel/props mesh build
│   │   └── river_world_3d.gd       # Scene/gameplay integration
│   ├── models/                  # Procedural fish and adult insect models
│   ├── player/                  # First-person controller and modeled fly rod
│   ├── ui/session_config.gd
│   └── autoloads/              # Session persistence/time/hatch/input services
├── assets/3d/
│   ├── geodata/                # Archived NHD/3DEP sources and runtime samples
│   ├── materials/ + shaders/   # Godot rendering resources
│   └── pbr/ambientcg/          # Imported CC0 surface maps/license record
├── docs/LOWER_MADISON_REACH.md
├── resources/difficulty_config.gd
├── project.godot
└── run.sh
```

## Data and assets

- River/terrain geometry: public USGS NHD and 3DEP data. See [`docs/LOWER_MADISON_REACH.md`](docs/LOWER_MADISON_REACH.md).
- PBR surfaces: ambientCG CC0 assets. See [`assets/3d/pbr/ambientcg/LICENSE_SOURCES.md`](assets/3d/pbr/ambientcg/LICENSE_SOURCES.md).

The previous 2D/tile runtime and its sprite/terrain assets have been removed; only the first-person 3D runtime is supported.
