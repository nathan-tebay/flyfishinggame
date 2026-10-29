# Collapse the Duplicate Casting Loop — Implementation Plan

> **Status (2026-06-02):** Tasks 1–6 implemented and verified headless. Task 6 was
> done **before** Task 5 (retarget the test first, then delete the old machine, so
> nothing depended on it). Notable deviations from the original draft: `delivered`
> dropped `pending_slack` (derived world-side); a `stroke_scored` signal was added
> for the one-shot loop-quality toasts; `_gesture_state` / `_loop_apex_height_cached`
> are kept as a presentation mirror driven from the seam (not deleted). Interactive
> playtest of cast feel still pending (project rule).

**Goal:** Make `CastingStateManager` the single seam for a cast. Migrate the
gameplay stroke logic (line load, stroke quality, false-cast counting, delivery
decision, roll commit) out of `river_world_3d.gd` and behind the casting module.
Delete the inline gesture state machine. `RiverWorld3D` becomes a thin applier that
reacts to one `CastOutcome`.

**Why:** Two cast phase machines currently run off the same rod-elevation input —
the inline gesture machine (`_update_gesture_state_machine`) owns gameplay; the new
`CastingStateManager` + `LoopPhysicsEngine` own only the visual loop. They have
independent transition thresholds and will desync. See `CONTEXT.md` (Casting) and
the 2026-06-02 architecture review.

**Decision (locked):** `CastingStateManager` absorbs gameplay. Module decides
*when / how well* to deliver; the world owns all `reach`/`builder` coupling and
applies the result. Signals for discrete events, getters for continuous HUD state.

**Tech:** Godot 4.3, GDScript. Files:
`scripts/casting/casting_state_manager.gd`, `scripts/casting/loop_physics_engine.gd`,
`scripts/river/river_world_3d.gd`, `tests/over_shoulder_casting_check.gd`,
`tests/casting_loop_modes_check.gd`, `tests/loop_physics_engine_check.gd`.

---

## Seam contract (target end-state)

`CastingStateManager`:

- **Input each frame** — `update(delta, input: Dictionary)` where input carries
  `{ elevation, lateral, mouse_dy, line_length, fly_on_water }`.
- **Continuous getters** (HUD reads these): `get_phase_name()`, `get_line_load()`,
  `get_loop_quality()`, `get_unroll_progress()`, `get_stroke_dir()`,
  `is_ready_to_deliver()`, `get_loop_state()`.
- **Discrete signals** (world connects these):
  - `delivered(style: String, line_load: float, loop_quality: String)` — the world
    derives `pending_slack` from line load + target distance, so it is not a signal arg.
  - `false_cast(count: int)`
- **No references** to `reach`, `builder`, `angler`, or any scene node. Pure given
  its inputs — testable with `CastingStateManager.new()`.

`RiverWorld3D` keeps: `perform_selected_cast(style)` (now driven by the `delivered`
signal), false-cast spook application (driven by `false_cast`), the visual turnover
(`_update_turnover`, `_turnover_*` — visual only), reach/landing/drift/HUD-text.

---

## Task 1 — Add gameplay state + contract to CastingStateManager

**Files:** `scripts/casting/casting_state_manager.gd`

Add fields the gesture machine currently keeps in the world: `_line_load`,
`_loop_quality`, `_false_cast_count`, `_stroke_clock`, `_unroll_time`,
`_pending_line_penalty`, `_stroke_dir`, `_lateral_at_backcast_load`. (`_pending_slack`
stays world-side — it becomes a local in `perform_selected_cast`, derived from line
load + target distance.)

Add the two signals (`delivered`, `false_cast`) and the continuous getters listed in
the seam contract. Add a `configure(...)` setter or constants mirroring the
delivery/quality thresholds currently in `river_world_3d.gd`
(`DELIVERY_LOAD_MIN`/`delivery_load_min`, `LOOP_DRAG_FACTOR` stays world-side since
it affects distance, `CARRY_LIMIT_*` stays world-side).

**Verify:** `godot4 --headless --path . --scene res://scenes/RiverWorld3D.tscn --quit`
parses clean.

## Task 2 — Port stroke scoring into the phase machine

**Files:** `scripts/casting/casting_state_manager.gd`

Move the bodies of `_compute_unroll_time`, `_begin_stroke`, `_complete_stroke`, and
`_apply_stroke_quality` (currently `river_world_3d.gd:2229–2300`) into the manager's
phase transitions:

- On entering BACKCAST/FORWARD: reset `_stroke_clock`, recompute `_unroll_time` from
  `line_length`.
- On reversal: score `progress = _stroke_clock / _unroll_time`, classify loop
  quality, apply the line-load delta + carried penalty (table in
  `docs/specs/2026-05-30-casting-loop-minigame.md`).
- Track the backcast lateral-drift (tracking) penalty from `input.lateral`.

Phase machine now uses the **elevation thresholds** the gameplay relied on
(`OVERHEAD_LIFT_START_ELEV`, `OVERHEAD_BACKCAST_LOAD_ELEV`,
`OVERHEAD_FORWARD_COMMIT_ELEV`) — not the placeholder `elevation_delta ±0.05`. This
is the merge that removes the desync.

**Verify:** parses clean; `loop_physics_engine_check.gd` still green (engine
untouched).

## Task 3 — Emit delivery + false-cast as signals

**Files:** `scripts/casting/casting_state_manager.gd`

- FORWARD stroke reaches commit while `LOADED` → emit
  `delivered("overhead", line_load, loop_quality)`, lock DELIVERY.
- FORWARD stroke reaches commit while **under**-loaded → false cast: increment
  `_false_cast_count`, emit `false_cast(_false_cast_count)`, return to BACKCAST.
- Roll path: when `input.fly_on_water` and the lift/D-loop descends → emit
  `delivered("roll", ...)` (port `_evaluate_roll_cast_commit`'s load bump into the
  emit). Roll while fly **not** on water → no emit (world shows the "cast overhead
  first" message via a getter/flag).

## Task 4 — Rewire RiverWorld3D to feed + react

**Files:** `scripts/river/river_world_3d.gd`

- In `_update_time_critical_state`, replace the `_update_gesture_state_machine`
  call with building the `CastInput` dict and calling `_casting_state_mgr.update`.
  Drive it only while a target is selected.
- Connect in `_init_loop_physics`:
  - `delivered` → `perform_selected_cast(style)` (read load/quality/slack from the
    signal args instead of the deleted `_line_load`/`_loop_quality`/`_pending_slack`
    fields).
  - `false_cast` → a new `_on_false_cast(count)` that calls the existing spook
    application (`_apply_false_cast_spook` body — it stays in the world because it
    touches `builder.fish_hold_entries`).
- `_update_minigame_panel` reads the manager getters only (drop the direct
  `_gesture_state`/`_line_load`/`_loop_quality`/`_stroke_clock` field reads).

**Verify:** scene smoke; interactive sanity (raise→lower delivers; O does not fire).

## Task 5 — Delete the inline gesture machine

**Files:** `scripts/river/river_world_3d.gd`

Delete: `_update_gesture_state_machine`, `_begin_stroke`, `_complete_stroke`,
`_apply_stroke_quality`, `_compute_unroll_time`, `_evaluate_roll_cast_commit`, and
the now-unused cast-loop fields (`_cast_loop_state`, `_line_load`, `_false_cast_count`,
`_arc_cursor`, `_arc_phase_active`, `_loop_quality`, `_pending_line_penalty`,
`_gesture_state`, `_elevation_at_peak`, `_lateral_at_backcast_load`, `_lift_peak_elev`,
`_lift_had_dip`, `_forward_stroke_age`, `_pending_slack`, `_stroke_clock`,
`_unroll_time`, `_reached_load`, `_reached_bottom`, `_stroke_dir`). Update
`_reset_cast_loop_state` to reset via `_casting_state_mgr.reset_to_setup()`.

**Keep** (visual, world-owned): `_update_turnover`, `_turnover_*`,
`_loop_apex_*`, `_update_aerial_cast_line`. `_apply_false_cast_spook` stays as the
`false_cast` handler.

**Verify:** scene smoke; `git diff --check`; grep confirms zero remaining refs to
deleted symbols.

## Task 6 — Retarget the tests onto the seam

**Files:** `tests/over_shoulder_casting_check.gd` (rewrite),
`tests/casting_loop_modes_check.gd` (keep)

- Rewrite `over_shoulder_casting_check.gd` to drive `CastingStateManager.new()`
  directly (no `RiverWorld3D.tscn`), mirroring `loop_physics_engine_check.gd`: feed
  scripted elevation sequences, assert phase transitions, line-load accumulation,
  loop-quality classification, and that `delivered` / `false_cast` fire correctly.
- Keep `casting_loop_modes_check.gd` — it still exercises `perform_selected_cast`
  on the world (the applier path) for overhead + roll.

**Verify (full suite, code changed):**
```bash
godot4 --headless --path . --scene res://scenes/RiverWorld3D.tscn --quit
godot4 --headless --path . --script res://tests/loop_physics_engine_check.gd
godot4 --headless --path . --script res://tests/over_shoulder_casting_check.gd
godot4 --headless --path . --script res://tests/casting_loop_modes_check.gd
godot4 --headless --path . --script res://tests/casting_loop_check.gd
git diff --check
```

Interactive acceptance still required (over-shoulder feel, loop animation, delivery
on lower-through-forward) per project playtesting rules.

---

## Out of scope / follow-ups

- Drift extraction (`DriftSimulation`) and fish evaluator (`TroutBehaviour`) — see
  the same review; build after this (#1 → #3 → #2).
- Fly-line ribbon builders (`_build_ribbon_mesh`, `_build_line_points`,
  `_cast_curve_point`) could later move fully into `CastingLineRenderer`; left in the
  world here to bound this change to the state-machine merge.
