# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

16-bit style 2D fly fishing game set on the Madison River, Montana. Built in Godot 4 with GDScript. See `GDD.md` for the full design specification.

**Engine:** Godot 4
**Language:** GDScript
**Targets:** Linux, Windows (initial), Android/iOS (future)

## Session Conventions

Every session produces two documents before implementation work begins or resumes:
- **Transcript**: `flyfishinggame-transcript session N.txt` — decision log with rationale, suitable for future reference
- **Blog draft**: `flyfishinggame-planning session N.txt` — narrative post for external audience

Both committed and tagged `planning-session-N` (or `implementation-session-N` for build sessions) at session end.

## Implementation

See `TASKS.md` for the phased agentic implementation plan. Each phase is self-contained and ends in a runnable, testable state. Always complete the current phase's testable condition before starting the next.

## Commands

All commands go through `run.sh`. Keep `run.sh` up to date when platforms,
plugin versions, or build steps change.

```bash
./run.sh setup            # Download godot-sqlite plugin (first-time setup)
./run.sh run              # Run the game (native Godot, needs GPU)
./run.sh editor           # Open Godot editor (native)
./run.sh export linux     # Export Linux build via Podman container
./run.sh export windows   # Export Windows build via Podman container
./run.sh export all       # Export all platforms
./run.sh shell            # Interactive shell in export container
./run.sh clean            # Remove builds/
```

**Native (run/editor):** requires Godot 4.3 on PATH (`godot4`, `godot`, or `Godot`).
**Container (export/shell):** requires Podman. Uses `barichello/godot-ci:4.3`.
**Export prerequisite:** `export_presets.cfg` must exist — create via editor: Project → Export.

Key versions (update in `run.sh` when upgrading):
- `GODOT_VERSION` — currently `4.3`
- `GODOT_SQLITE_VERSION` — currently `4.3` (bin.zip = libraries, demo.zip = plugin.cfg + .gdextension + .gd)

## Architecture

### Core Systems

| System | Responsibility |
|---|---|
| `RiverWorld` | Scene root (`scenes/RiverWorld.tscn`, `scripts/river/river_world.gd`) — generates river, renders tilemap, updates sky strip, owns camera |
| `RiverConstants` | `scripts/river/river_constants.gd` — all tile IDs, sizes, colors. Access as `RiverConstants.TILE_SIZE` etc. |
| `RiverData` | `scripts/river/river_data.gd` — plain data struct: depth_profile, current_map, tile_map, hold_scores, structures, top_holds |
| `RiverGenerator` | `scripts/river/river_generator.gd` — full pipeline: depth profile (FastNoiseLite) → tile map → current map → structure placement → eddy currents → hold scoring → top holds. Seeded deterministically. |
| `RiverRenderer` | `scripts/river/river_renderer.gd` — extends TileMap, builds programmatic placeholder tileset, renders RiverData to 3 layers (Base/Structures/Debug) |
| `RiverCamera` | `scripts/camera/river_camera.gd` — horizontal-only Camera2D, section-clamped. Phase 3 will call `set_anchor(world_x)` to constrain scout range |
| `Angler` | `scenes/Angler.tscn`, `scripts/angler/angler.gd` — Player movement (bank/wading), vibration radius, standing-still signal. Shadow cone is a child Node2D. |
| `CastingController` | Line feed/strip state, false cast rhythm (speed scales with line length), rod arc HUD (unified: direction cue + loop quality + line length indicator), mouse mend detection (upstream/downstream), complete-cast trigger, cast quality → spook chance output |
| `DriftController` | Tracks drag accumulation on fly during drift, applies take probability modifier, receives mend events from `CastingController` to reset drag |
| `HooksetController` | Strike window state per fly type — floating ball indicator pause (nymph) or rise/splash (dry), asymmetric too-early/too-late logic, emits catch or spook event |
| `FishRenderer` | Procedural fish visual generation at spawn (species-specific attribute variation seeded from fish instance ID), snapshot render for catch log photos |
| `FishAI` | Spook state machine (FEEDING→ALERT→SPOOKED→RELOCATING→HOLDING), intrusion memory, feeding edge logic, relocation |
| `FishVisionCone` | `scripts/fish/fish_vision_cone.gd` (Phase 5) — approach angle calculation, blind spot detection, cone width per fish size/difficulty |
| `SpookCalculator` | `scripts/fish/spook_calculator.gd` — Radius formula: `base × size × cover × time_of_day × approach_angle × difficulty`. Never bypass this — all spook checks route through here. Also exposes `approach_modifier()` for FishVisionCone. |
| `HatchManager` | Time-of-day hatch state machine (No Hatch→Pre-Hatch→Emerger→Peak→Spinner Fall), insect spawn, fish feeding mode shifts |
| `FlyMatcher` | Weighted closeness score between fly profile and active insect profile. Outputs take probability and intrusion memory delta |
| `NetSampler` | Stand-still timer, depth layer sampling, insect abundance results by proximity to structures |
| `TimeOfDay` | Dawn/Morning/Midday/Afternoon/Dusk/Night cycle. Drives lighting, hatch windows, spook modifiers, shadow direction, fish visibility. Time scale configurable (1 min/hr default → real-time). Emits `dawn` signal for large fish lockdown reset |
| `CatchLog` | Records catch data (species, size, fly, hatch state, time, seed+location). Generates pixel art fish photo snapshot. Logbook UI accessible from pause menu |
| `DifficultyConfig` | Resource passed to SpookCalculator, FishAI, FlyMatcher, RiverGenerator — all difficulty-variable values live here, never hardcoded elsewhere. Values loaded from DB on startup via DatabaseManager |
| `DatabaseManager` | Autoload. Opens/creates `user://flyfishing.db` on startup, runs schema migrations, seeds default difficulty presets and settings. All persistence routes through here — no other system writes directly to disk |

### Database Schema

Managed by `DatabaseManager`. DB lives at `user://flyfishing.db`.

| Table | Purpose |
|---|---|
| `settings` | Key/value store — time scale, session start hour, active difficulty tier, input remaps |
| `difficulty_presets` | One row per tier (ARCADE/STANDARD/SIM), all `DifficultyConfig` fields. Seeded from hardcoded defaults, user-editable later |
| `sessions` | seed, start_hour, difficulty_tier, time_scale, started_at, ended_at |
| `catches` | species, size_cm, fly_name, fly_stage, hatch_state, time_of_day, section_index, position_x, fish_variant_seed, session_id FK |

**Plugin:** godot-sqlite by 2shady4u — must be installed in `addons/godot-sqlite/` and enabled in Project Settings → Plugins.

### Key Design Constraints

- **All spook radius checks route through `SpookCalculator`** — never compute proximity directly in AI or movement code
- **All difficulty-variable values live in `DifficultyConfig` resource** — never hardcode Arcade/Standard/Sim values in other systems
- **All persistence routes through `DatabaseManager`** — no other system writes directly to disk
- **Fish size class is a property on the fish** — small/medium/large determines intrusion memory limits, vision cone width, cooldown timers
- **Wading and bank fishing have separate spook profiles** — do not merge into a generic proximity check
- **Fly matching uses `FlyMatcher` closeness score** — wrong-stage rejection adds +0.5 intrusion memory; never add intrusion directly in fly/cast code
- **Large fish lockdown resets on `TimeOfDay.dawn` signal** — not a timer, not a session flag reset
- **Rod arc is the only line length indicator** — no separate HUD meter; direction change cue, loop quality, and line length all read from the arc animation
- **Drag accumulation lives in `DriftController`** — mend events route through `CastingController` → `DriftController`, never bypass this
- **Hookset too-early = hard spook** (+1 intrusion memory) — routes through `FishAI` same as any other hard intrusion
- **Fish visual attributes seeded from fish instance ID** — same fish always generates same appearance; `FishRenderer` handles this, not `FishAI`
- **River sections are stateless once despawned** — section state is not saved; same seed always regenerates identically

### Critical State Machines

**Casting:**
```
IDLE → AIMING → LINE_FEED → FALSE_CASTING (loop) → PRESENTATION → RESULT
```
- Timing window speed scales continuously with line length — no fixed stages
- Player exits FALSE_CASTING by pressing complete-cast button
- Result quality (clean/sloppy/bad) feeds into `SpookCalculator` as cast quality modifier

**Fish:**
```
FEEDING → ALERT → SPOOKED → RELOCATING → HOLDING → FEEDING
```
All transitions driven by `SpookCalculator` output and `FlyMatcher` rejection events.

**Hatch:**
```
NO_HATCH → PRE_HATCH → EMERGER → PEAK_HATCH → SPINNER_FALL → NO_HATCH
```
Fish feeding mode (subsurface vs surface) and `FlyMatcher` best-match fly shift per hatch state.

### Angler World Coordinates

TileMap starts at world y=0. Key y positions (TILE_SIZE=32):
- `BANK_Y = 80.0` — angler reference point on bank (centre of bottom bank row)
- `WADE_ENTRY_Y = 96` — water surface (row 3 = `BANK_H_TILES * TILE_SIZE`)
- `MAX_WADE_Y = 256` — 5 tiles below surface (hard cap; actual river depth may be shallower)

Camera follows `Angler.position.x` (with smoothing). `set_anchor()` constrains limits to ±3 screen widths from angler x. When `follow_target` is null, Phase 2 free-pan mode is active.

### SpookCalculator conventions

- Fish always face upstream → `Vector2(-1, 0)` in world space
- Blind spot = downstream (behind fish tail); `angle_from_tail=0°` → modifier 0.1
- Head-on = upstream (facing fish mouth); `angle_from_tail=180°` → modifier 1.6
- Wading vibration is handled as a separate omnidirectional radius — `max(directional_r, vibration_r)`. The vibration component is what reduces blind spot advantage when wading.

### Fish Visibility Rendering

- Deep water: fish sprite opacity = `depth_factor × inverse(light_level)`, desaturated
- Shallow water: ripple particle on movement
- Silhouette contrast boosted via shader parameter at midday
- Sim difficulty: no telegraph color shifts on spook states
