# CLAUDE.md

## Project

First-person Godot 4.3 Forward+ fly fishing environment representing a compressed, USGS-derived Lower Madison bend immediately upstream of Black's Ford, Montana.

Only the 3D runtime is supported. Do not reintroduce `RiverWorld.tscn`, procedural 2D river tiles, pixel-art assets, or classic-runtime selection.

## Commands

```bash
./run.sh setup
./run.sh run
./run.sh editor
./run.sh export linux
./run.sh export windows
./run.sh export all
./run.sh clean
```

Headless smoke checks:

```bash
godot4 --headless --path . --scene res://scenes/RiverWorld3D.tscn --quit
godot4 --headless --path . --quit
```

## Current architecture

| System | File | Responsibility |
| --- | --- | --- |
| Session setup | `scenes/SessionConfig.tscn`, `scripts/ui/session_config.gd` | Chooses seed/time/difficulty; always launches 3D reach |
| 3D world | `scenes/RiverWorld3D.tscn`, `scripts/river/river_world_3d.gd` | Dynamic time-of-day lighting, movement/wading, selected-fly/cast HUD with target-first casting loop controls, rod-attached fly line with current-bowed transparent leader ending at the dry fly, overhead/roll cast launch after target selection, adult dry-fly landing/current-driven drift, fish AI alert/spook/feeding state, fly-species affinity scoring, first-pass fish take + hookset + landed-catch logging, net sampling / hatch abundance readout, first-pass sound cue hooks, surface rise rings, drifting foam flecks, distant bird flock |
| Reach interface | `scripts/river/lower_madison_reach.gd` | Fixed public-data geometry, water/land/depth/current/habitat/hold queries |
| Mesh builder | `scripts/river/river_3d_builder.gd` | Continuous bed/water/banks, relief, batched static prop/vegetation MultiMesh instances, cached build-time reach queries and gravel-bar frames, build-profile timings, density knobs for non-gameplay visuals, seeded modeled fish with gameplay AI hold metadata, adult insects |
| Wildlife models | `scripts/models/` | Rainbow/brown/whitefish geometry and adult mayfly/caddis models |
| Player/tackle | `scenes/FirstPersonAngler.tscn`, `scripts/player/` | First-person controls and 2.74 m guided fly rod/line |
| Persistence/time | `scripts/autoloads/` | Session/database, time, hatch state, current input actions |

## World constraints

- Reach terrain and props are fixed across seeds.
- Seed may vary fish occupancy and session behavior only.
- Water interaction must query `LowerMadisonReach`, not recreate tile maps.
- Keep a dry accessible player start and bounded visible water channel.
- Source real geometry only from documented public data; Google imagery is not a terrain/texture source.

## Assets

- Geography/source records: `assets/3d/geodata/`, `docs/LOWER_MADISON_REACH.md`.
- Runtime surface assets: imported CC0 ambientCG PBR maps under `assets/3d/pbr/ambientcg/`.
- License record: `assets/3d/pbr/ambientcg/LICENSE_SOURCES.md`.

## Coding rules

- GDScript naming: `snake_case` members/functions, `PascalCase` class names, `UPPER_SNAKE_CASE` constants.
- Guard clauses over deep nesting.
- Wrap runtime debug `print()` calls with `OS.is_debug_build()`.
- Route persistence through `DatabaseManager`.
- Do not commit unless explicitly requested.
