# Implementation Tasks

Phased agentic implementation plan for the fly fishing game PoC. Each phase is a self-contained session designed to fit within token limits. Always read `CLAUDE.md` and `GDD.md` before starting a phase.

**Rules for each session:**
- Start from the current state of the repo — never assume prior session context
- Update `CLAUDE.md` with any new systems, constraints, or file paths added
- Mark the phase checkbox when complete
- Each phase ends in a runnable, testable Godot scene

---

## Phase 1 — Project Foundation
**Goal:** Runnable Godot project with input, config, SQLite persistence, and time-of-day scaffolding in place. Every subsequent phase builds on this.

**Plugin requirement:** godot-sqlite by 2shady4u must be installed before running.
Place the addon in `addons/godot-sqlite/`. Enable in Project → Project Settings → Plugins.
Releases: https://github.com/2shady4u/godot-sqlite/releases

**Deliverables:**
- [x] Godot 4 project initialized (`project.godot`, folder structure)
- [x] Folder structure: `scenes/`, `scripts/`, `assets/placeholder/`, `resources/`, `addons/`
- [x] `.gitignore` — excludes `.godot/`, `*.translation`, `export_presets.cfg`
- [x] `DifficultyConfig` resource (`resources/difficulty_config.gd`) — all three tiers (Arcade/Standard/Sim) with every difficulty-variable value from GDD difficulty table. Static factory methods `arcade()`, `standard()`, `sim()`. Values loaded from DB on startup, DB seeded from these defaults if not present.
- [x] `DatabaseManager` autoload (`scripts/autoloads/database_manager.gd`) — opens/creates `user://flyfishing.db` on startup, runs schema migration, seeds default difficulty presets and settings. Provides typed save/load methods used by all other systems.
- [x] Database schema (created by DatabaseManager):
  - `settings` — key/value store for all user preferences
  - `difficulty_presets` — one row per tier, all DifficultyConfig fields, user-editable later
  - `sessions` — seed, start_hour, difficulty_tier, time_scale, started_at, ended_at
  - `catches` — species, size_cm, fly_name, fly_stage, hatch_state, time_of_day, section_index, position_x, fish_variant_seed, session_id FK
- [x] `GameManager` autoload (`scripts/autoloads/game_manager.gd`) — loads active `DifficultyConfig` from DB, holds session state (seed, start hour), exposes `new_session()` and `end_session()`
- [x] Input map configured via `InputSetup` autoload (`scripts/autoloads/input_setup.gd`) — programmatic setup of all actions: move_left/right/up/down, feed_line, strip_line, complete_cast, cast_back, cast_forward, hookset, net_sample, pause_game. Keyboard + gamepad defaults, all remappable.
- [x] `TimeOfDay` autoload (`scripts/autoloads/time_of_day.gd`) — full cycle (Dawn→Morning→Midday→Afternoon→Dusk→Night), configurable time scale (default 1 min/hr), session start time, emits `dawn` signal, exposes current period, light level (0.0–1.0), sun angle (degrees)
- [x] `Main.tscn` + `scripts/main.gd` — loads and runs without errors, prints TimeOfDay state each period change to confirm all autoloads are working

**Testable when:** Project opens in Godot, runs without errors. TimeOfDay period changes print to console. DB file created at `user://flyfishing.db` with correct schema and seeded difficulty presets verifiable via DB browser.

**GDD sections:** Difficulty Settings, Time of Day

---

## Phase 2 — River Generation & Rendering
**Goal:** A seeded, procedurally generated river section visible on screen with depth layers, structures, and hold scores calculated.

**Deliverables:**
- [x] `RiverConstants` (`scripts/river/river_constants.gd`) — tile types, sizes, colors, sky colors, structure properties
- [x] `RiverData` (`scripts/river/river_data.gd`) — data structure returned by generator
- [x] `RiverGenerator` (`scripts/river/river_generator.gd`) — full pipeline:
  - Simplex noise depth profile via FastNoiseLite
  - Base tile map from depth profile (BANK/SURFACE/MID_DEPTH/DEEP/RIVERBED)
  - Current map (shallow=fast, deep=slow)
  - Structure placement (weed beds, rocks, boulders, undercut banks, gravel bars) with density from DifficultyConfig
  - Eddy currents downstream of rocks/boulders
  - Hold evaluation: `cover + depth_score + slow_score + seam_score`
  - Top hold candidates for Phase 5 fish spawn
- [x] `RiverRenderer` (`scripts/river/river_renderer.gd`) — TileMap script with programmatic placeholder colour tiles, 3 layers (Base/Structures/Debug), hold score debug overlay toggle (`,` key)
- [x] `RiverCamera` (`scripts/camera/river_camera.gd`) — horizontal pan with arrow keys, section-clamped limits, `set_anchor()` stub for Phase 3
- [x] `RiverWorld.tscn` — Camera2D + TileMap + CanvasLayer sky strip, RiverWorld.gd controller
- [x] Seed input exposed — same seed always produces same river
- [x] Section length: 24 screen widths (1440 tiles)
- [x] Camera pans full section width (Phase 3 will constrain to ±3 screens from angler)

**Testable when:** Running the scene shows a river with visually distinct depth layers and structures. Changing the seed changes the layout. Camera pans with mouse/input.

**GDD sections:** Procedural River Generation

---

## Phase 3 — Angler Movement & Spook Geometry
**Goal:** Angler moves through the world. Shadow cone and vibration radius are computed and visualized (debug overlay).

**Deliverables:**
- [x] `Angler.tscn` + `scripts/angler/angler.gd` — placeholder sprite, bank/wading movement
  - Bank movement: horizontal walk along top of water
  - Wading: enters water, movement slowed, depth tracked
  - Movement speed affects vibration radius
  - Standing still for 3+ seconds triggers `standing_still` signal (used by net sampler later)
- [x] `ShadowCone` (`scripts/angler/shadow_cone.gd`) — directional cone projected from angler, angle driven by `TimeOfDay` sun position, visible as debug overlay on Casual difficulty
- [x] `SpookCalculator` (`scripts/fish/spook_calculator.gd`) — full formula implementation:
  `base × size_multiplier × cover_reduction × time_of_day_modifier × approach_angle_modifier × difficulty_modifier`
  Wading vibration adds omnidirectional component that reduces blind spot advantage (does not fully cancel)
- [x] Angler placed in `RiverWorld.tscn`, moves through the generated river

**Testable when:** Angler walks along bank and wades into river. Debug overlay shows shadow cone rotating with time of day. SpookCalculator returns expected values for test inputs.

**GDD sections:** Angler Movement, Fish Vision & Approach, Spook Radius Calculation

---

## Phase 4 — Casting Mechanic
**Goal:** Full casting loop playable — feed line, false cast with rod arc feedback, mend, complete cast. Cast quality output available for downstream systems.

**Deliverables:**
- [x] `CastingController` (`scripts/casting/casting_controller.gd`) — state machine:
  `IDLE → FALSE_CASTING → PRESENTATION → RESULT → DRIFT → IDLE`
  - Line feed/strip via input actions
  - False cast rhythm — timing window speed scales with line length
  - Line straighten detection → direction change cue (yellow dot at 80% of load time)
  - Loop quality calculated (tight/sloppy/bad) from timing accuracy
  - Mouse movement during drift detected as mend (upstream/downstream)
  - Complete cast input triggers PRESENTATION → RESULT
  - Emits `cast_result(quality, target_position)` signal
- [x] `DriftController` (`scripts/casting/drift_controller.gd`)
  - Tracks drag accumulation during fly drift
  - Receives mend events, resets drag accumulation
  - Exposes `drag_factor` (0.0 = natural drift, 1.0 = full drag)
- [x] `RodArcHUD` (`scripts/ui/rod_arc_hud.gd`) — bottom-left HUD element:
  - Animated rod arc showing line in air
  - Line straighten visual cue (line tip turns yellow at timing window)
  - Result quality shown by line color (green/yellow/red)
  - Line length bar on left side
- [x] `FlySelector` UI (`scripts/ui/fly_selector.gd`) — bottom-right, shows active fly, swap with Tab
- [x] Casting integrated into `RiverWorld.tscn`

**Testable when:** Player can feed line, false cast with visual feedback on loop quality, mend during drift, and complete a cast to a target position. Cast quality (tight/sloppy/bad) prints to console.

**GDD sections:** Casting Mechanic, Line drag & mending

---

## Phase 5 — Fish AI & Vision
**Goal:** Fish spawn from hold scores, move to feeding edges, respond to angler presence via vision cone and spook state machine.

**Deliverables:**
- [x] `Fish.tscn` + `scripts/fish/fish_ai.gd` — state machine:
  `FEEDING → ALERT → SPOOKED → RELOCATING → HOLDING → FEEDING`
  - Species (Brown/Rainbow/Whitefish), size class, variant seed stored as properties
  - Hold position assigned from RiverGenerator top_holds
  - Feeding edge: scans ±7×3 tiles for faster seam, moves there at dawn/dusk
  - Cooldown timers per size class; intrusion memory counter; lockdown at threshold
  - Relocation: picks hold far from angler + deeper water via score
  - Lockdown resets on `TimeOfDay.dawn` signal
- [x] `FishVisionCone` (`scripts/fish/fish_vision_cone.gd`)
  - Draws blind spot cone (green triangle behind tail); opacity scales with telegraph strength
  - Blind spot half-angle from DifficultyConfig
- [x] `FishRenderer` (`scripts/fish/fish_renderer.gd`)
  - Procedural color from species + variant seed (hue shift ±0.04)
  - Depth + light level opacity scaling
  - State debug label + intrusion memory counter drawn above fish
  - State telegraph tint (color shifts toward red as memory builds, scaled by difficulty)
- [x] Fish spawned dynamically in `RiverWorld._spawn_fish()` at top hold positions

**Testable when:** Fish visible at hold positions, move to feeding edges at dawn/dusk. Approaching fish causes Alert then Spook transitions (visible via debug state label). Vision cone approach angle affects spook distance. Large fish locks down after 3 spooks and resets at dawn.

**GDD sections:** Fish AI, Fish Vision & Approach, Fish Visibility, Intrusion Memory

---

## Phase 6 — Hatch System, Fly Matching & Net Sampling
**Goal:** Full hatch cycle drives insect visibility and fish feeding mode. Fly matching affects take probability. Net sampling reveals subsurface insects.

**Deliverables:**
- [x] `HatchManager` autoload (`scripts/autoloads/hatch_manager.gd`)
  - Full state machine: `NO_HATCH → PRE_HATCH → EMERGER → PEAK_HATCH → SPINNER_FALL → NO_HATCH`
  - Mother's Day Caddis timing driven by `TimeOfDay`
  - Insect spawning per hatch state and depth layer
  - Insect movement patterns (caddis skitter, mayflies drift upright)
  - Exposes active insect profile list for `FlyMatcher`
- [x] `FlyMatcher` (`scripts/flies/fly_matcher.gd`)
  - Fly profile resource (species, stage, size, color)
  - Weighted closeness score vs active insect profile
  - Returns take probability modifier and intrusion memory delta (+0.5 for wrong stage, +1 for wrong species on Sim)
- [x] `NetSampler` (`scripts/angler/net_sampler.gd`)
  - Activates on input when `Angler.standing_still` signal received
  - 3–5 second sample timer, interrupted by movement
  - Samples depth layer at current position, weighted by nearby structures
  - Emits `sample_complete(results)` with insect abundance data
- [x] Net sample result UI panel — abundance bars (Casual/Normal), names only (Sim)
- [x] `FlySelector` updated — available flies filtered to current hatch-relevant patterns
- [x] Fish `FEEDING` state uses `FlyMatcher` result to determine take or rejection

**Testable when:** Insect sprites appear at correct depth layers during each hatch phase. Standing still and sampling returns correct insect data. Presenting wrong fly causes fish to reject. Exact match produces take event.

**GDD sections:** Hatch System, Fly Selection & Matching, Net Sampling

---

## Phase 7 — Hookset, Catch & Logbook
**Goal:** Complete catch loop — strike signal, hookset timing, catch confirmation, procedural fish photo, logbook entry.

**Deliverables:**
- [x] `HooksetController` (`scripts/catching/hookset_controller.gd`)
  - Dry fly: rise + splash sound + fly disappears → strike window opens
  - Nymph: floating ball strike indicator spawned on line during drift, pauses/dips on take → strike window opens
  - Hookset input detected within window
  - Too early: emits `hard_spook` to `FishAI` (+1 intrusion memory), fish gone
  - Perfect: emits `catch_confirmed`
  - Too late: emits `miss_late`, fish returns to FEEDING
  - Strike window duration configurable per difficulty
- [x] Floating ball strike indicator sprite — follows line drift, animates on take
- [x] `CatchLog` (`scripts/catching/catch_log.gd`)
  - On `catch_confirmed`: captures species, size, fly, hatch state, time of day, section seed, position
  - Triggers `FishRenderer` snapshot for fish photo
  - Stores entries in session array
- [x] Logbook UI scene — accessible from pause menu
  - Photo gallery of caught fish
  - Per-entry: species, size, fly, time, location
  - Sortable by species and size

**Testable when:** Fish take triggers visible strike indicator behavior. Hookset at correct timing produces catch photo and logbook entry. Too-early hookset spooks fish. Logbook shows all session catches.

**GDD sections:** Hookset Mechanic, Session Structure & Catch Log

---

## Phase 8 — Integration & First Playable Session
**Goal:** All systems wired together. Difficulty config flows through every system. Seamless section streaming works. First fully playable PoC session.

**Deliverables:**
- [ ] `DifficultyConfig` verified flowing through: `SpookCalculator`, `FishAI`, `FishVisionCone`, `FlyMatcher`, `HooksetController`, `RiverGenerator`, `NetSampler` UI
- [ ] Seamless section streaming — next section pre-generates offscreen, previous despawns; seed chain: `hash(base_seed + section_index)`
- [ ] Session config screen — seed input, start time, difficulty, time scale
- [ ] All three difficulty tiers produce meaningfully different play experiences
- [ ] Placeholder art pass — distinct readable sprites for: angler, brown trout, rainbow trout, caddis adult, caddis pupa, strike indicator, weed bed, rock, boulder
- [ ] `CLAUDE.md` updated with final file paths and any architecture decisions made during implementation
- [ ] No placeholder `print()` debug output remaining in release path

**Testable when:** A complete fishing session is playable from session config → explore river → locate fish → approach → cast → drift → hookset → catch → logbook. All three difficulties feel distinct.

**GDD sections:** All

---

## Notes for Agentic Sessions

- **Always read `CLAUDE.md` first** — it contains system constraints that must not be violated
- **Each phase assumes prior phases are complete** — check that required signals/classes exist before implementing dependents
- **If a design decision is ambiguous**, refer to `GDD.md` first, then make the most conservative/simple choice and note it in `CLAUDE.md`
- **Prefer signals over direct references** between systems — keeps phases independently testable
- **Update `CLAUDE.md`** at the end of each phase with any new file paths, added constraints, or design decisions made during implementation
- **Do not begin the next phase** if the current phase's testable condition is not met
