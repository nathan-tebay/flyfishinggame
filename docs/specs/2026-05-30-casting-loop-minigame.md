# Casting Spec — Over-Shoulder Gesture Casting

_Originally drafted 2026-05-30 as a keypress rhythm minigame. Rewritten 2026-05-31
to document the shipped design: the keypress/rhythm/hover-camera version was
replaced by mouse-gesture casting per the over-shoulder casting plan
(`docs/plans/2026-05-30-over-shoulder-realistic-casting.md`)._

## Overview

When the player selects a water target, the camera moves to an over-the-shoulder
angler view and the rod comes under direct mouse control. The player casts by
**moving the mouse like a fly rod in hand** in a back-and-forth **false-casting
rhythm**: raise the mouse for the backcast, lower it for the forward stroke, and
reverse each stroke when the loop has straightened. Each well-timed stroke loads
the line; once the line is **LOADED** (`_line_load ≥ DELIVERY_LOAD_MIN`), lowering
the rod on a forward stroke **delivers** the fly. Under-loaded forward strokes stay
aerial (false casts).

Timing is the mechanic: the loop takes a **line-length-scaled** time to unroll
(`UNROLL_TIME_MIN`→`UNROLL_TIME_MAX`; the more line out, the slower the rhythm).
A bottom side-view meter shows the line unfurling and recolouring **red → green**
as it straightens — green is the cue to reverse. Reversing too early = tailing,
too late = wide. After a delivery the player can **pick up and recast in place**
(raise the rod again to re-arm the last target). Fish spook pressure and line
tangles remain dormant / future-phase.

---

## Confirmed Design Decisions

| Topic | Decision |
|---|---|
| Core mechanic | Mouse-as-rod false-cast rhythm — reverse each stroke as the loop straightens; well-timed strokes load the line |
| Camera | Over-the-shoulder rig behind the casting shoulder while a target is selected |
| Timing | Loop unroll time scales with line length (`UNROLL_TIME_MIN`→`MAX`); stroke scored by time-since-reversal vs unroll time |
| Commit | Delivery fires when the line is LOADED (`_line_load ≥ DELIVERY_LOAD_MIN`) and the rod is lowered on a forward stroke; under-loaded forward strokes stay aerial |
| Recast | After delivery, raising the rod picks the line up and re-arms the last target in place |
| Failure model | No hard fail — only cast quality (short / loaded / over, loop tightness from timing) |
| Spook / tangles | Code present but dormant; activated in a later phase |
| HUD | Bottom side-view meter: angler + line unfurling red→green, stroke phase, line-load bar |

---

## Camera Behaviour

On target selection (`FirstPersonAngler3D.enter_casting_stance`):
- The body faces the target; the camera detaches (`set_as_top_level`) and tweens to
  an over-the-shoulder position behind/above the angler
  (`CAST_CAMERA_OVER_SHOULDER_OFFSET`), looking toward the target zone.
- FOV tweens to `CAST_CAMERA_FOV`. The first-person rod mesh is hidden while the
  over-shoulder rig is active.
- The camera follows with damping (`CAST_CAMERA_FOLLOW_RATE`); it is not whipped by
  raw mouse motion.
- On cast delivery or target cancel, the camera tweens back and `set_as_top_level`
  is restored to `false`.
- Player movement is locked while a target is selected.

---

## Gesture Mechanic

Mouse motion during casting is filtered, not applied 1:1:
- Horizontal mouse → damped rod yaw (`CAST_MOUSE_YAW_SENSITIVITY`,
  speed-limited by `CAST_MOUSE_MAX_YAW_SPEED`).
- Vertical mouse → rod elevation target, damped in `FlyRod3D._process`
  (`ROD_ELEVATION_RESPONSE`, `ROD_ELEVATION_MAX_SPEED`).

The gesture state machine (`river_world_3d.gd._update_gesture_state_machine`):

```
idle
  → [elev ≥ OVERHEAD_LIFT_START_ELEV] → backcast   (or lifting_roll for a gentle lift with fly on water)
backcast  (rod rising; reset stroke clock on entry)
  → [reached OVERHEAD_BACKCAST_LOAD_ELEV, then descending] → _complete_stroke("backcast") → forward
forward   (rod descending; reset stroke clock on entry)
  → [reached OVERHEAD_FORWARD_COMMIT_ELEV, descending, LOADED] → _complete_stroke + perform_selected_cast("overhead") → drift
  → [reached commit, then rising]  → _complete_stroke("forward") → backcast   (false cast, stays aerial)
lifting_roll
  → [descending in D-loop band] → perform_selected_cast("roll")
```

Each `_begin_stroke()` resets `_stroke_clock` and recomputes `_unroll_time` from the
current line length. `_complete_stroke()` (fired at each reversal) scores
`progress = _stroke_clock / _unroll_time` and loads/penalises the line.

### Line load and loop quality (timing-based)

`_apply_stroke_quality(progress)` converts how close the reversal was to the loop
straightening (progress ≈ 1.0) into a loop quality and a line-load delta:

| Loop quality | progress window | Line-load effect |
|---|---|---|
| tight | 0.82–1.18 (reversed on green) | +0.32 |
| adequate | 0.62–1.45 | +0.20 |
| tailing | < 0.62 (reversed too early) | +0.05, −0.05 penalty carried to next stroke |
| wide | > 1.45 (waited too long) | +0.02, −0.10 penalty carried to next stroke |

Backcast strokes also carry a lateral-drift (tracking) penalty if the rod leaves
the vertical plane. `_line_load` (0–1.2) gates delivery (`DELIVERY_LOAD_MIN`) and
still drives where the fly lands (short / loaded / over).

`_line_load` (0–1.2) is the proportion of the target distance carried. At
delivery (`perform_selected_cast`):
- `< 0.5` → fly lands short of the target.
- `0.9–1.1` → loaded; cast quality upgraded to Clean.
- `> 1.1` → overshoots past the target.

### Roll cast

`R` (or right-click) delivers a roll cast, but only when the fly is already on
the water (`_fly_is_on_water`). Otherwise the player is told to cast overhead
first.

### Dormant systems

`_apply_false_cast_spook` and the false-cast escalation (`_false_cast_count`
3 / 4+ / 6+) remain in the code but are effectively inert during normal single
casts. They are not wired as active fail states yet — bad cast quality is the
only consequence the player feels today.

---

## HUD

`scripts/ui/casting_minigame_panel.gd` is a semi-transparent strip anchored to the
bottom of the screen (`anchor_top = 0.75`), shown only while a target is selected.
It draws a **simplified side-view of the angler** with the **fly line unfurling**
on the current stroke:
- The loop unfurls in front for a forward stroke, behind for a backcast.
- The line is coloured **red while curled → green as it straightens**; green (and a
  "REVERSE" prompt) is the cue to reverse the stroke. Past straight it shifts
  toward orange (the loop has fallen — too late).
- **Stroke phase** (BACKCAST / FORWARD / FORWARD–DELIVER / ROLL) top-left.
- **Line-load bar** (right) with a 90 % LOADED gate marker and a `DELIVER!`
  read-out once loaded.

Fed each frame from `river_world_3d._update_minigame_panel`: `gesture_state`,
`line_load`, `loop_quality`, `unroll_progress`, `stroke_dir`, `ready_to_deliver`.

---

## Fly Line Rendering

- Drift line and leader build as flat ribbon meshes (`_build_ribbon_mesh`,
  `CAST_LINE_SEGMENTS = 18`) rather than 1-px line strips, with shadows off and a
  brightened emissive fly-line material.
- An aerial line (`_update_aerial_cast_line`) animates a loop following the rod tip
  during the lift / backcast / forward stroke, then hands off to the drift line on
  delivery.

---

## Files

| File | Role |
|---|---|
| `scripts/player/first_person_angler.gd` | Over-shoulder camera, damped rod input |
| `scripts/player/fly_rod_3d.gd` | Rod elevation/yaw kinematics, live flex |
| `scripts/river/river_world_3d.gd` | Gesture state machine, line load, drift, delivery, HUD feed |
| `scripts/ui/casting_minigame_panel.gd` | Bottom feedback strip |

---

## Validation

- `godot4 --headless --path . --scene res://scenes/RiverWorld3D.tscn --quit`
- `godot4 --headless --path . --script res://tests/casting_loop_modes_check.gd`
- `godot4 --headless --path . --script res://tests/over_shoulder_casting_check.gd`
- Interactive: target select enters over-shoulder view; raising then lowering the
  mouse delivers the cast; pressing O while a target is selected does **not** fire;
  fly line is visible through lift / backcast / forward / drift.
