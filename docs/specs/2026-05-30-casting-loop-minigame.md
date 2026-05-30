# Casting Loop Minigame — Design Spec
_2026-05-30_

## Overview

When the player selects a cast target, the game enters a false-casting minigame. The camera repositions to hover above the target zone so the player can read feeding fish and drifting insects before committing. False casts charge the fly line toward the target distance via a rhythm/timing mechanic: press B (backcast) and F (forward cast) when the rod arc cursor enters the green stop zone. Committing too early (line underloaded) lands short; casting too many times spooks nearby fish.

---

## Confirmed Design Decisions

| Topic | Decision |
|---|---|
| Core mechanic | Rhythm/timing — press in the green arc zone |
| False cast model | Open-ended, sweet spot at 2–4 good casts |
| Camera | Repositions to hover above target zone |
| HUD layout | Full-screen zoom + casting overlay at screen edges |
| Timing indicator | Arc zone underlaid on stickman + mini timing bar below |

---

## Camera Behaviour

On target selection:
- The `FirstPersonAngler` camera tweens (0.6 s ease-in-out) from the angler head position forward and down to a point 1.8–2.5 m above the target, pitched ~55° downward toward the water surface.
- FOV narrows from 68° to 52° during the tween.
- The angler body, rod, and fly line remain visible in the lower portion of the frame.
- On cast commit or target cancel, camera tweens back to head position (0.4 s).
- Player movement is locked during the minigame (existing `_is_casting_control_locked` covers this).

The hover height is clamped so the camera never clips below `WATER_HEIGHT + 0.3`.

---

## False Cast Rhythm Mechanic

### Rod arc timing

Each false cast consists of two phases: **backcast** (B key) and **forward cast** (F key).

During each phase:
1. A sweep cursor travels along the rod's arc path over ~0.7 s.
2. A green zone marks the correct stop point (roughly 80–110° of the arc sweep, matching real rod-stop mechanics).
3. Red zones on either end mark "too early" (tailing loop) and "too late" (dump / collapsed loop).
4. The player presses B or F when the cursor is in the green zone.

**Timing result → loop quality:**

| Zone hit | Quality | Line load delta | Effect |
|---|---|---|---|
| Green centre | Tight loop | +14% | Clean carry |
| Green edge | Adequate loop | +8% | Slight wobble |
| Red early | Tailing loop | +2% | Possible tangle (-5% on next cast) |
| Red late | Dump | +1% | Line collapses, -10% on next cast |
| Missed entirely | No loop | 0% | HUD shows "No backcast / No forward cast" |

### Line load meter

A vertical bar in the HUD centre tracks line loaded as a percentage of the distance to the target.

- **< 50%**: Fly will land short if committed. HUD: `LINE SHORT`.
- **50–90%**: Valid commit window. HUD: `READY`.
- **90–110%**: Sweet spot — optimal accuracy bonus. HUD: `LOADED ✓`.
- **> 110%**: Overshoot risk. Fly may land beyond the target, increasing drag probability.

### Spook pressure

Each false cast passes line over the target zone. Fish in the target area accumulate alert:

- False cast 1–2: No penalty.
- False cast 3: Nearest fish alert +0.15.
- False cast 4+: All fish within `FISH_TAKE_RADIUS × 2` get alert +0.25 per cast. HUD warning: `⚠ LINE OVERHEAD — FISH ALERT`.
- False cast 6+: Fish spook (state = "spooked"). HUD: `FISH SPOOKED — PICK UP`.

### Rod bend visual

The stickman rod is drawn as a two-segment bezier:
- **Butt section**: straight, follows arm direction.
- **Tip section**: lags behind under line weight — bend depth scales with current line load (more load = deeper flex).
- At the stop point the rod straightens, giving visual confirmation of a clean stop.
- A coloured glow arc overlays the flex zone: amber on backcast, blue on forward cast.

---

## HUD Layout (full-screen zoom active)

```
┌─────────────────────────────────────────────────────────┐
│  ◀ BACKCAST [B]              │  FORWARD CAST [F] ▶       │
│  [stickman + arc zone]  LINE │  [stickman + arc zone]   │
│  [timing bar]           METER│  [timing bar]            │
│                         65%  │                          │
│  LOOP: TIGHT ✓          ↑    │  COMMIT: O overhead      │
│                       TARGET │          R roll cast     │
└─────────────────────────────────────────────────────────┘
  Camera looks down at river target zone (fills background)
  Fish and insects visible through the HUD
```

The existing `_casting_loop_label` label is replaced by a structured `CastingMinigamePanel` Control node containing:
- `BackcastPanel` (left third): stickman SVG-equivalent mesh, arc overlay, timing bar.
- `LineMeterPanel` (centre strip): vertical charge bar, target marker, false cast count, spook warning.
- `ForwardCastPanel` (right third): mirror of backcast panel.
- `ResultBar` (bottom edge): last loop quality, line % readout, commit hint.

All panels are semi-transparent so the river scene shows through.

---

## State Machine

The minigame sits inside the existing cast flow:

```
READY TO CAST
  → [target selected] → CASTING_LOOP_IDLE
    → [B pressed, in green zone] → BACKCAST_COMPLETE
      → [F pressed, in green zone] → FORWARD_CAST_COMPLETE (false cast counted)
        → [loop again] → CASTING_LOOP_IDLE
        → [O/R pressed, line >= 50%] → CAST_COMMIT → existing drift flow
        → [O/R pressed, line < 50%] → SHORT_CAST (land short, reduced take chance)
    → [Esc / target cancel] → READY TO CAST (camera tweens back)
```

New state var: `_cast_loop_state: String` with values `"idle"`, `"backcast_pending"`, `"backcast_complete"`, `"forward_pending"`, `"forward_complete"`.

New state vars:
- `_line_load: float` — 0.0–1.2 (proportion of target distance loaded).
- `_false_cast_count: int` — resets when drift starts or target cancelled.
- `_arc_cursor: float` — 0.0–1.0, sweeps during each phase.
- `_loop_quality: String` — "tight", "adequate", "tailing", "dump", "none".

---

## Files to Create / Modify

| File | Change |
|---|---|
| `scripts/river/river_world_3d.gd` | Add minigame state vars, `_update_cast_loop_minigame(delta)`, `_enter_casting_zoom()`, `_exit_casting_zoom()`, `_evaluate_loop_timing()`, spook pressure per false cast, short-cast landing modifier |
| `scripts/player/first_person_angler.gd` | Camera tween to target hover position; expose `tween_camera_to(pos, pitch, fov)` |
| `scenes/RiverWorld3D.tscn` | Replace `_casting_loop_label` with `CastingMinigamePanel` Control subtree |
| `scripts/ui/casting_minigame_panel.gd` | New script: draws stickman + arc zones + timing bars + result bar via `_draw()` or `CanvasItem` |

No new autoloads. No new resources needed beyond the panel script.

---

## Validation Checklist

- [ ] Camera tween reaches target hover cleanly and returns to head on cancel/commit.
- [ ] Arc cursor completes sweep in ~0.7 s; green zone registeres press correctly.
- [ ] Line load meter fills correctly over 2–4 good false casts.
- [ ] Spook pressure applies at cast 3, 4+, 6+.
- [ ] Short cast (< 50%) lands fly visibly short of target ring.
- [ ] Committing with ≥ 90% load applies accuracy bonus to existing `_cast_quality`.
- [ ] Existing overhead/roll/drift/take/fight flow unchanged after commit.
- [ ] Headless smoke: `godot4 --headless --path . --scene res://scenes/RiverWorld3D.tscn --quit` passes.
