# Fly Fishing Game

16-bit style 2D fly fishing game set on the Madison River, Montana. Built in Godot 4 with GDScript. Grounded in realistic fly fishing principles — hatch-driven fish behavior, edge feeding philosophy, and skill-based casting.

See [`GDD.md`](GDD.md) for the full game design specification.

**Engine:** Godot 4.3  
**Language:** GDScript  
**Target platforms:** Linux, Windows (initial), Android/iOS (future)

## Quick start

```bash
./run.sh setup     # Download godot-sqlite plugin (first-time setup)
./run.sh run       # Run the game (requires Godot 4.3 and GPU)
./run.sh editor    # Open Godot editor
```

**Native (run/editor):** requires Godot 4.3 on PATH (`godot4`, `godot`, or `Godot`).

## All commands

```bash
./run.sh setup            # Download godot-sqlite plugin
./run.sh run              # Run the game
./run.sh editor           # Open Godot editor
./run.sh export linux     # Export Linux build (via Podman container)
./run.sh export windows   # Export Windows build (via Podman container)
./run.sh export all       # Export all platforms
./run.sh shell            # Interactive shell in export container
./run.sh clean            # Remove builds/
```

**Container (export/shell):** requires Podman. Uses `barichello/godot-ci:4.3`.  
**Export prerequisite:** `export_presets.cfg` must exist — create via Godot editor: Project → Export.

## Validation (headless)

```bash
godot4 --headless --path /mnt/LargeNVMe/Projects/GitHub/personal/flyfishinggame --quit
```

## Gameplay overview

1. **Scout** — pan the camera (up to 3 screen widths) to locate feeding fish at the right depth layer
2. **Approach** — wade or stay on bank; manage shadow and vibration spook risk
3. **Cast** — false cast to load line, present the fly at the right time and position
4. **Mend** — adjust drag during the drift to keep the fly natural
5. **Strike** — hookset timing differs for dry fly (rise/splash visual cue) and nymph (floating indicator)
6. **Land** — successfully hooked fish go into the catch log with a procedurally generated fish photo

Difficulty is configurable — all spook thresholds, fly match tolerances, and fish behavior parameters load from the database.

## Project structure

```
flyfishinggame/
├── scenes/
│   ├── RiverWorld.tscn      # Main scene
│   ├── Angler.tscn          # Player character
│   ├── Fish.tscn            # Fish entity
│   ├── Main.tscn            # Entry point
│   └── SessionConfig.tscn   # Session setup
├── scripts/
│   ├── river/               # RiverData, RiverGenerator, RiverRenderer, RiverCamera
│   ├── angler/              # Player movement, shadow, vibration
│   ├── casting/             # CastingController, DriftController
│   ├── fish/                # FishAI, FishVisionCone, SpookCalculator
│   ├── catching/            # HooksetController, CatchLog
│   ├── flies/               # FlySelector, FlyMatcher
│   ├── ui/                  # RodArcHUD, FlySelector UI
│   ├── autoloads/           # DatabaseManager, HatchManager, TimeOfDay
│   └── main.gd
├── assets/
│   ├── sprites/             # Angler, fish, insects, props (source art)
│   └── terrain/             # River terrain atlas and TileSet
├── addons/                  # godot-sqlite plugin
├── GDD.md                   # Full game design document
├── project.godot
└── run.sh                   # All build/run/export commands
```

## Core systems

| System | Description |
|---|---|
| `RiverGenerator` | Procedural river: depth profile (FastNoiseLite) → tile map → current map → structure placement → hold scoring |
| `RiverRenderer` | Depth-field rendering pipeline with box blur, current lightening, rock wakes, and debug hold overlay |
| `CastingController` | State machine: IDLE → FALSE_CASTING → PRESENTATION → RESULT → DRIFT. Rod arc HUD with timing cue |
| `FishAI` | Spook state machine: FEEDING → ALERT → SPOOKED → RELOCATING → HOLDING. Feeding edge logic, intrusion memory |
| `HatchManager` | Time-of-day hatch state machine driving insect spawns and fish feeding modes |
| `SpookCalculator` | Unified spook radius: base × size × cover × time_of_day × approach_angle × difficulty |
| `CatchLog` | Records all catches with procedurally generated fish photo snapshots |
| `DatabaseManager` | Autoload. SQLite persistence for difficulty presets, settings, and catch history |
| `DifficultyConfig` | Resource passed to all difficulty-variable systems — values never hardcoded |
| `TimeOfDay` | Dawn/Morning/Midday/Afternoon/Dusk/Night cycle; drives lighting, hatch windows, spook modifiers |

## Design documentation

- [`GDD.md`](GDD.md) — game design document (overview, visual style, all core systems)
- `flyfishinggame-planning session N.txt` — session design narratives (7 sessions)
- `flyfishinggame-transcript session N.txt` — decision logs with rationale (7 sessions)
