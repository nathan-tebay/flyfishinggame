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
| `RiverCamera` | `scripts/camera/river_camera.gd` — horizontal-only Camera2D, section-clamped. `set_anchor(world_x)` constrains scout range to ±3 screen widths |
| `Angler` | `scenes/Angler.tscn`, `scripts/angler/angler.gd` — Player movement (bank/wading), vibration radius, standing-still signal. Shadow cone is a child Node2D. |
| `CastingController` | `scripts/casting/casting_controller.gd` — State machine IDLE→FALSE_CASTING→PRESENTATION→RESULT→DRIFT→IDLE. Line feed/strip, false cast rhythm (scales with line length), mouse mend detection, emits `cast_result(quality, target_x, target_y)` and mend signals |
| `DriftController` | `scripts/casting/drift_controller.gd` — Tracks drag_factor during drift (0=natural, 1=full drag). Receives mend events via `on_mend(direction)` to reset drag. Connected to CastingController signals by RiverWorld |
| `RodArcHUD` | `scripts/ui/rod_arc_hud.gd` — bottom-left CanvasLayer HUD, _draw()-based. Shows rod arc, fly line state, timing cue (yellow dot at 80% load time), quality color on result, line-length bar |
| `FlySelector` | `scripts/ui/fly_selector.gd` — bottom-right CanvasLayer HUD. Two flies: Elk Hair Caddis (dry) and Caddis Pupa (emerger). Tab/Y-button to swap. Exposes `fly_name()`, `fly_stage()`, `is_dry_fly()` |
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

### Phase 8 — Session Config & Section Streaming

**Session config screen** (`scenes/SessionConfig.tscn`, `scripts/ui/session_config.gd`)
- Main scene. Keyboard-driven `_draw()` UI: Tab=cycle fields, ←/→=change value, 0-9=seed digits, Enter=start.
- Reads last settings from DB; saves before `GameManager.new_session()`. Calls `TimeOfDay.set_time_scale()` directly.
- Changes scene to `RiverWorld.tscn` on start.

**Section streaming** (in `river_world.gd`)
- Sections tracked in `_sections: Array` of `{index, data, renderer, fish_list, start_px}` Dicts.
- `SECTION_W_PX = 1440 × 32 = 46 080 px`. Section N starts at world x = N × SECTION_W_PX.
- Seed chain: `abs(hash(session_seed + idx × 999983))`.
- Pre-generate next section at 70% through current; despawn section two behind current.
- Section 0 renderer = `tilemap` @onready (never freed; hidden on despawn). Section 1+ = `RiverRenderer.new()` nodes.
- On section crossing: update `angler.river_data`, `angler.section_start_x`, `net_sampler.river_data`, interrupt active cast.
- Camera right limit expanded via `camera.update_section_limit(right_px)`.

**Tile coordinate conventions (Phase 8)**
- `fish.section_start_px` — world x of the fish's section left edge; set by `_spawn_section_fish`.
- `FishAI._local_tile_x(world_x)` / `_local_tile_y(world_y)` — convert world coords to river_data tile indices.
- `FishAI._tile_to_world_x(tx)` — reverse: local tile column → world x (tile centre).
- `FishRenderer._section_start_px` — passed via `initialize(..., section_start_px)`.
- `angler.section_start_x` — used in `_max_wade_y()` col calculation; updated on section crossing.
- Angler horizontal x is unconstrained (camera limits control scouting range).

**Debug print policy**
- All `print()` calls in release-path code wrapped with `if OS.is_debug_build():`.
- Applies to: FishAI state/lockdown/take messages, RiverWorld section events, cast results, angler standing-still.
