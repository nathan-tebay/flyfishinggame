# Over-Shoulder Realistic Casting Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Replace the current too-twitchy first-person casting control feel with a more realistic angler-perspective casting stance: slower rod control, longer stroke arc, cast commit when the rod is lowered through the forward stroke, and an optional behind-the-shoulder camera that shows the rod, line, water target, and surrounding scene during casting.

**Architecture:** Keep the normal walking/wading runtime first-person. When a water target is selected, enter a dedicated casting stance that can use an over-the-shoulder camera rig attached to the angler. Mouse input drives rod yaw/elevation through a smoothed, damped controller instead of directly rotating the head/camera. RiverWorld3D remains responsible for casting state, target validation, line load, drift, fish spook/take logic, and HUD messaging; FirstPersonAngler3D owns camera stance and rod input filtering; FlyRod3D owns rod arc kinematics.

**Tech Stack:** Godot 4.3, GDScript, existing `RiverWorld3D.tscn`, `FirstPersonAngler.tscn`, `scripts/player/first_person_angler.gd`, `scripts/player/fly_rod_3d.gd`, `scripts/river/river_world_3d.gd`, existing headless smoke checks.

---

## Recommendation on 3rd-person perspective

Use a temporary over-the-shoulder casting camera, not a full-time third-person mode.

Why:
- It solves the user experience problem better than first-person: the player can see the rod load, rod tip path, fly line loop, target ring, current seam, nearby rises, and fishy water in one frame.
- It preserves the project identity as a first-person wading/fishing environment outside the cast.
- It avoids making movement, collision, and regular exploration feel like a third-person game.
- It directly addresses the current complaint: mouse feels too responsive because in first-person the same input moves the view and rod. In over-the-shoulder casting, the camera can be damped and mostly stable while the rod moves independently.

Target camera behavior:
- Normal play: first-person camera as now.
- Target selected: tween to an over-right-shoulder camera about 1.1 m behind, 0.45 m to the rod-hand side, and 0.25 m above the angler head, looking over the rod hand toward the selected water target.
- During cast: camera uses damped follow/aim, not raw mouse motion. Rod responds to mouse with inertia and slower sensitivity.
- Cast complete or target cancelled: tween back to first-person camera.

This can coexist with the existing target hover camera code, but the plan below recommends making over-shoulder the default casting camera and leaving target-hover as a debug/alternate mode only if needed.

---

## Current behavior found in code

Relevant files:
- `scripts/player/first_person_angler.gd`
  - `MOUSE_SENSITIVITY := 0.0025` drives both normal look and casting rod yaw.
  - `apply_cast_mouse_motion(relative)` directly changes `_rod_aim_yaw`, `head.rotation.y`, `rod.set_cast_aim()`, and `rod.apply_mouse_elevation()` with no smoothing.
  - `enter_casting_stance(target_world_pos)` only narrows FOV; it does not currently move to a behind-shoulder camera.
  - `tween_camera_to_hover()` already supports top-level camera tweening and can be refactored/reused.
- `scripts/player/fly_rod_3d.gd`
  - `ROD_CAST_SENSITIVITY := 0.005` makes full stroke in roughly 200 px, which is too responsive.
  - Rod elevation is directly mutated in `apply_mouse_elevation()`.
  - `is_rod_descending()` already exists and is used by the gesture state machine.
- `scripts/river/river_world_3d.gd`
  - `_update_gesture_state_machine()` already commits overhead cast when rod descends to `elev <= 0.18` in `forward_stroke`, matching the requirement that the cast completes when the angler lowers the rod.
  - However, keyboard/manual commit still exists through `_on_cast_commit_requested(style)` and `FirstPersonAngler3D._request_cast_style()` on O/R/right click.
  - Existing thresholds create a fairly short arc: overhead loads at `elev >= 0.90`, transitions at `elev <= 0.40`, commits at `elev <= 0.18`.

---

## Design targets

1. Casting stance is a physically readable mode:
   - Camera leaves first-person only while a target is selected.
   - Camera frames angler shoulder, rod hand, rod tip, line, target ring, and water surface.
   - Camera motion is damped; mouse does not whip the view around.

2. Mouse controls rod, not camera, during casting:
   - Horizontal mouse input sets rod plane/yaw through a damped target.
   - Vertical mouse input sets rod elevation through a damped target.
   - Raw deltas are scaled down compared to normal look.
   - Add acceleration/velocity limits so a big mouse jerk does not instantly traverse the cast arc.

3. Cast arc is stretched and fluid:
   - Require a deeper backcast lift before loading.
   - Require a longer forward stroke before commit.
   - Commit happens on lowering through the forward release threshold, not on O key / Space / click.
   - Rod animation follows the player’s current elevation/yaw rather than snapping to canned 0.56 s flexes.

4. Keep current gameplay systems intact:
   - Target validation still uses `LowerMadisonReach` through `RiverWorld3D`.
   - Cast line/leader still attach to live rod tip and active drift.
   - Fish alert/spook/take logic stays in `RiverWorld3D`.
   - No 2D runtime or legacy river tiles.

---

## Task 1: Add camera mode constants and state to FirstPersonAngler3D

**Objective:** Prepare the player controller to support a dedicated over-shoulder casting camera without changing behavior yet.

**Files:**
- Modify: `scripts/player/first_person_angler.gd`

**Implementation notes:**
Add constants near the existing camera/cast constants:

```gdscript
const CAST_CAMERA_OVER_SHOULDER_OFFSET := Vector3(0.55, 0.28, 1.15)
const CAST_CAMERA_LOOK_HEIGHT := 0.55
const CAST_CAMERA_FOV := 58.0
const CAST_CAMERA_TWEEN_TIME := 0.45
const CAST_CAMERA_RESTORE_TIME := 0.32
const CAST_CAMERA_FOLLOW_RATE := 5.0
```

Add state vars:

```gdscript
var _casting_camera_active := false
var _casting_camera_target := Vector3.ZERO
var _casting_camera_offset := CAST_CAMERA_OVER_SHOULDER_OFFSET
```

**Verification:**
Run:

```bash
godot4 --headless --path . --scene res://scenes/RiverWorld3D.tscn --quit
```

Expected: scene loads without parse errors.

---

## Task 2: Implement over-shoulder camera enter/exit helpers

**Objective:** Move the camera behind the angler’s casting shoulder when a target is selected, and restore it cleanly afterward.

**Files:**
- Modify: `scripts/player/first_person_angler.gd`

**Implementation details:**
Add helper:

```gdscript
func enter_over_shoulder_cast_camera(target_world_pos: Vector3) -> void:
	if camera == null:
		return
	_saved_camera_transform = camera.global_transform
	_saved_camera_fov = camera.fov
	_casting_camera_active = true
	_casting_camera_target = target_world_pos
	camera.set_as_top_level(true)
	var desired := _over_shoulder_camera_transform(target_world_pos)
	if _camera_tween != null and _camera_tween.is_valid():
		_camera_tween.kill()
	_camera_tween = create_tween()
	_camera_tween.set_ease(Tween.EASE_OUT)
	_camera_tween.set_trans(Tween.TRANS_CUBIC)
	_camera_tween.tween_property(camera, "global_transform", desired, CAST_CAMERA_TWEEN_TIME)
	_camera_tween.parallel().tween_property(camera, "fov", CAST_CAMERA_FOV, CAST_CAMERA_TWEEN_TIME)
```

Add helper:

```gdscript
func exit_over_shoulder_cast_camera() -> void:
	if camera == null or not _casting_camera_active:
		return
	if _camera_tween != null and _camera_tween.is_valid():
		_camera_tween.kill()
	_camera_tween = create_tween()
	_camera_tween.set_ease(Tween.EASE_IN_OUT)
	_camera_tween.set_trans(Tween.TRANS_CUBIC)
	_camera_tween.tween_property(camera, "global_transform", _saved_camera_transform, CAST_CAMERA_RESTORE_TIME)
	_camera_tween.parallel().tween_property(camera, "fov", _saved_camera_fov, CAST_CAMERA_RESTORE_TIME)
	_camera_tween.tween_callback(func():
		camera.set_as_top_level(false)
		_casting_camera_active = false
	)
```

Add transform helper:

```gdscript
func _over_shoulder_camera_transform(target_world_pos: Vector3) -> Transform3D:
	var right := global_transform.basis.x.normalized()
	var back := global_transform.basis.z.normalized()
	var up := Vector3.UP
	var camera_pos := head.global_position + right * _casting_camera_offset.x + up * _casting_camera_offset.y + back * _casting_camera_offset.z
	var look_at_pos := target_world_pos + Vector3(0.0, CAST_CAMERA_LOOK_HEIGHT, 0.0)
	var look_dir := (look_at_pos - camera_pos).normalized()
	return Transform3D(Basis.looking_at(look_dir, Vector3.UP), camera_pos)
```

Add an update in `_physics_process(delta)` or `_process(delta)`:

```gdscript
func _process(delta: float) -> void:
	_update_casting_camera(delta)
```

If `_process` already exists later, merge into it; do not create duplicate functions.

```gdscript
func _update_casting_camera(delta: float) -> void:
	if not _casting_camera_active or camera == null:
		return
	if _camera_tween != null and _camera_tween.is_valid():
		return
	var desired := _over_shoulder_camera_transform(_casting_camera_target)
	var t := minf(delta * CAST_CAMERA_FOLLOW_RATE, 1.0)
	camera.global_transform = camera.global_transform.interpolate_with(desired, t)
```

**Verification:**
Run headless scene smoke. If Godot complains about duplicate `_process`, merge the function body with the existing process hook.

---

## Task 3: Wire casting stance to over-shoulder camera

**Objective:** Enter over-shoulder mode when a target is selected and restore first-person after cast/cancel.

**Files:**
- Modify: `scripts/player/first_person_angler.gd`
- Modify: `scripts/river/river_world_3d.gd`

**Implementation details:**
In `FirstPersonAngler3D.enter_casting_stance(target_world_pos)` replace the current FOV-only casting camera behavior with:

```gdscript
enter_over_shoulder_cast_camera(target_world_pos)
```

Keep existing target-facing and rod stance reset logic.

In `FirstPersonAngler3D.exit_casting_stance()`, call:

```gdscript
exit_over_shoulder_cast_camera()
```

instead of only tweening FOV.

In `RiverWorld3D.select_cast_target(origin, target)`, it already calls `_enter_casting_zoom(clamped_target)`. Confirm `_enter_casting_zoom()` calls `angler.enter_casting_stance(target)`; if not, update it to do so.

In `RiverWorld3D.perform_selected_cast(style)`, ensure the existing `_exit_casting_zoom()` path remains before drift starts. That should restore camera via `angler.exit_casting_stance()`.

**Verification:**
Run:

```bash
godot4 --headless --path . --scene res://scenes/RiverWorld3D.tscn --quit
godot4 --headless --path . --quit
```

Expected: both pass.

---

## Task 4: Split normal look sensitivity from casting rod sensitivity

**Objective:** Make mouse less responsive in casting without hurting normal first-person look.

**Files:**
- Modify: `scripts/player/first_person_angler.gd`
- Modify: `scripts/player/fly_rod_3d.gd`

**Implementation details:**
In `first_person_angler.gd`, add:

```gdscript
const CAST_MOUSE_YAW_SENSITIVITY := 0.00095
const CAST_MOUSE_YAW_RESPONSE := 7.5
const CAST_MOUSE_MAX_YAW_SPEED := deg_to_rad(115.0)

var _rod_aim_yaw_target := 0.0
var _pending_cast_mouse_motion := Vector2.ZERO
```

Change `apply_cast_mouse_motion(relative)` so it accumulates input instead of immediately rotating the head:

```gdscript
func apply_cast_mouse_motion(relative: Vector2) -> void:
	_pending_cast_mouse_motion += relative
```

Add update helper called every frame/physics frame:

```gdscript
func _update_cast_rod_control(delta: float) -> void:
	if not _is_casting_control_locked():
		_pending_cast_mouse_motion = Vector2.ZERO
		return
	if _pending_cast_mouse_motion != Vector2.ZERO:
		_rod_aim_yaw_target = clampf(
			_rod_aim_yaw_target - _pending_cast_mouse_motion.x * CAST_MOUSE_YAW_SENSITIVITY,
			-ROD_CAST_MAX_YAW,
			ROD_CAST_MAX_YAW
		)
		rod.apply_mouse_elevation(_pending_cast_mouse_motion.y)
		_pending_cast_mouse_motion = Vector2.ZERO
	var max_step := CAST_MOUSE_MAX_YAW_SPEED * delta
	_rod_aim_yaw = move_toward(_rod_aim_yaw, _rod_aim_yaw_target, max_step)
	_rod_aim_yaw = lerpf(_rod_aim_yaw, _rod_aim_yaw_target, minf(delta * CAST_MOUSE_YAW_RESPONSE, 1.0))
	head.rotation.y = lerpf(head.rotation.y, _rod_aim_yaw * 0.18, minf(delta * 4.0, 1.0))
	rod.set_cast_aim(_rod_aim_yaw)
```

Call `_update_cast_rod_control(delta)` from `_physics_process(delta)` before movement is evaluated.

In `fly_rod_3d.gd`, reduce rod elevation sensitivity:

```gdscript
const ROD_CAST_SENSITIVITY := 0.0022
```

This makes full stroke closer to 450 px instead of ~200 px.

**Verification:**
Run headless smoke. Then run interactively with `./run.sh run` and confirm normal look still feels unchanged while target-selected rod movement is slower.

---

## Task 5: Add rod elevation damping and velocity limiting inside FlyRod3D

**Objective:** Make vertical rod control fluid and weighted instead of direct 1:1 mouse-to-rotation.

**Files:**
- Modify: `scripts/player/fly_rod_3d.gd`

**Implementation details:**
Add constants:

```gdscript
const ROD_ELEVATION_RESPONSE := 8.0
const ROD_ELEVATION_MAX_SPEED := deg_to_rad(180.0)
```

Add state:

```gdscript
var _elevation_target: float = 0.0
```

Change `apply_mouse_elevation(delta_pixels)`:

```gdscript
func apply_mouse_elevation(delta_pixels: float) -> void:
	if delta_pixels < 0.0:
		_peak_lift_speed = maxf(_peak_lift_speed, abs(delta_pixels))
	var min_elev := ELEV_MIN if _casting_stance_active else 0.0
	_elevation_target = clampf(_elevation_target - delta_pixels * ROD_CAST_SENSITIVITY, min_elev, ELEV_MAX)
```

In `_process(delta)`, before using `_elevation_offset`, update:

```gdscript
_prev_elevation_offset = _elevation_offset
var max_step := ROD_ELEVATION_MAX_SPEED * delta
_elevation_offset = move_toward(_elevation_offset, _elevation_target, max_step)
_elevation_offset = lerpf(_elevation_offset, _elevation_target, minf(delta * ROD_ELEVATION_RESPONSE, 1.0))
_cast_aim.x = _elevation_offset
```

Do not also set `_prev_elevation_offset` later in the same function.

Update reset methods:

```gdscript
func reset_elevation() -> void:
	_elevation_offset = 0.0
	_elevation_target = 0.0
	_prev_elevation_offset = 0.0
	_peak_lift_speed = 0.0
	_cast_aim.x = 0.0
```

In `enter_casting_stance()`, reset `_elevation_target` too.

**Verification:**
Headless smoke. Manual check: small mouse movement should not instantly trip from idle to backcast; rod should lag slightly and visibly settle.

---

## Task 6: Stretch the overhead casting arc thresholds

**Objective:** Require a longer, more realistic lift/backcast/forward stroke before commit.

**Files:**
- Modify: `scripts/river/river_world_3d.gd`

**Implementation details:**
Add constants near `OVERHEAD_LIFT_THRESHOLD`:

```gdscript
const OVERHEAD_LIFT_START_ELEV := 0.28
const OVERHEAD_BACKCAST_LOAD_ELEV := 1.12
const OVERHEAD_BACKCAST_RELEASE_ELEV := 0.58
const OVERHEAD_FORWARD_COMMIT_ELEV := 0.10
const OVERHEAD_ARC_MAX_ELEV := 1.42
const FORWARD_ARC_MAX_ELEV := 1.05
```

Replace literals in `_update_gesture_state_machine()`:
- idle starts when `elev >= OVERHEAD_LIFT_START_ELEV` instead of `0.20`.
- overhead loads when `elev >= OVERHEAD_BACKCAST_LOAD_ELEV` instead of `0.90`.
- `_elevation_to_arc(elev, OVERHEAD_ARC_MAX_ELEV)` instead of `1.30`.
- backcast transitions when `descending and elev <= OVERHEAD_BACKCAST_RELEASE_ELEV` instead of `0.40`.
- forward cursor uses `_elevation_to_arc(elev, FORWARD_ARC_MAX_ELEV)` instead of `0.90`.
- cast commits when `descending and elev <= OVERHEAD_FORWARD_COMMIT_ELEV` instead of `0.18`.

Update HUD/status strings so they say:
- `BACKCAST — raise high, then lower into forward stroke`
- `FORWARD — lower rod to deliver cast`

**Verification:**
Run headless smoke. Manual check: the cast should not launch until the rod is lowered near the delivery position.

---

## Task 7: Disable keyboard/button instant commit for overhead casts while in target-selected casting stance

**Objective:** Enforce “cast completes when angler lowers rod, not on key press.”

**Files:**
- Modify: `scripts/player/first_person_angler.gd`
- Modify: `scripts/river/river_world_3d.gd`
- Modify: `scripts/autoloads/input_setup.gd` only if input hints need cleanup; avoid deleting actions unless tests require it.

**Implementation details:**
In `FirstPersonAngler3D._physics_process(delta)`, avoid calling `_request_cast_style("overhead")` when casting controls are active:

```gdscript
var casting_control_active := _is_casting_control_locked()
if Input.is_action_just_pressed("overhead_cast") and not casting_control_active:
	_request_cast_style("overhead")
```

For roll cast, decide whether to keep R as an explicit alternate technique or require a gentle lift/lower gesture. Recommended for this pass:
- Keep R/right-click only for roll-cast mode if fly is already on water, but do not let O/Space launch overhead in casting stance.
- Future pass can add a dedicated roll gesture.

In `RiverWorld3D._on_cast_commit_requested(style)`, guard overhead while target is selected:

```gdscript
if style.to_lower() != "roll" and not _selected_cast_target.is_empty():
	_show_cast_message("Lower the rod through the forward stroke to deliver the overhead cast.", 2.2)
	return
```

Update user-facing messages currently saying `O/R cast`, `O overhead`, or `click or Space casts` to emphasize gesture delivery:
- Target message: `Raise rod for backcast, then lower forward to deliver. Wheel changes line. R roll-casts when fly is on water.`
- Startup message: `Click/Space selects water target; cast by moving the rod.`

**Verification:**
Manual check:
- Select target.
- Press O: no overhead cast launches; message explains lower rod.
- Raise rod, then lower: overhead cast launches.
- Existing hookset click/Space behavior still works when fish takes.

---

## Task 8: Make rod animation follow the live casting arc instead of canned cast timers during gesture casting

**Objective:** Avoid visual mismatch where lowering rod triggers a canned `play_cast_animation()` that snaps/overrides player-controlled rod pose.

**Files:**
- Modify: `scripts/player/fly_rod_3d.gd`
- Modify: `scripts/river/river_world_3d.gd`

**Implementation details:**
In `FlyRod3D`, add live load state:

```gdscript
var _live_cast_load := 0.0
var _live_cast_phase := "idle"

func set_live_cast_load(phase: String, load: float) -> void:
	_live_cast_phase = phase
	_live_cast_load = clampf(load, 0.0, 1.0)
```

In `_process(delta)`, when `_cast_timer <= 0.0`, add subtle flex based on live load:

```gdscript
var base := _current_base_rotation() + _cast_aim
var flex := _live_cast_load * 0.16
if _live_cast_phase == "backcast":
	base += Vector3(flex * 0.45, -flex * 0.06, flex * 0.10)
elif _live_cast_phase == "forward":
	base += Vector3(-flex * 0.55, flex * 0.08, -flex * 0.08)
rotation = rotation.lerp(base, minf(delta * 10.0, 1.0))
```

In `RiverWorld3D._update_gesture_state_machine()`, call:

```gdscript
angler.rod.set_live_cast_load("backcast", _arc_cursor)
```

while backcast is loading, and:

```gdscript
angler.rod.set_live_cast_load("forward", _arc_cursor)
```

while forward stroke is active.

When gesture state returns to idle or cast performs, call:

```gdscript
angler.rod.set_live_cast_load("idle", 0.0)
```

Reduce calls to `angler.play_cast_animation("back")` / `("forward")` inside gesture state machine. Keep `play_cast_animation("roll")` for explicit roll cast if it still looks acceptable. The live pose should dominate overhead gesture casting.

**Verification:**
Manual check: the rod tip tracks the player’s stroke continuously. It should not snap into a canned animation when the backcast/forward state changes.

---

## Task 9: Add a shoulder/arm/rod silhouette for over-shoulder framing if needed

**Objective:** Ensure the over-shoulder camera actually shows an angler perspective instead of a disembodied rod.

**Files:**
- Modify: `scenes/FirstPersonAngler.tscn`
- Modify or create: `scripts/player/first_person_angler.gd` helpers if building procedurally

**Implementation options:**
Prefer procedural child nodes in `FirstPersonAngler.tscn` if simple:
- Add `Node3D` named `CastingBodyVisual` under `Head` or player root.
- Add simple low-poly shoulder/chest/forearm meshes with neutral fishing-jacket material.
- Hide in first-person normal mode if it clips the camera.
- Show only when `_casting_camera_active` is true.

Minimal fallback:
- Keep only the existing rod visible and rely on camera placement, but this is less convincing.

**Verification:**
Manual visual check in over-shoulder stance. Headless smoke will only catch scene syntax.

---

## Task 10: Make the fly line visible and animate it with player casting actions

**Objective:** Replace the currently hard-to-see/static fly-line presentation with an always-visible casting line that follows the rod tip, forms aerial loops during the player’s backcast/forward stroke, and settles into the existing current-bowed drift line after delivery.

**Files:**
- Modify: `scripts/river/river_world_3d.gd`
- Modify: `scripts/player/fly_rod_3d.gd` if exposing rod tip velocity or cast phase helps
- Modify or create materials under `assets/3d/materials/` only if the current `fly_line.tres` / `leader.tres` are too transparent or too thin

**Current code issue:**
`RiverWorld3D` already has `_cast_line` and `_leader_line`, but they are built with `ImmediateMesh.PRIMITIVE_LINE_STRIP` in `_build_line_strip_mesh()`. In Godot 3D this often renders as a 1-pixel line with poor visibility, especially against bright water. It also only rebuilds from rod tip to target/drifting fly; it does not visualize the aerial loop during the player’s casting stroke.

**Implementation details:**
Add a dedicated visible line renderer instead of relying on raw line strips:

```gdscript
const CAST_LINE_VISUAL_RADIUS := 0.018
const LEADER_VISUAL_RADIUS := 0.006
const AERIAL_LINE_SEGMENTS := 24
const AERIAL_LOOP_HEIGHT := 2.4
const AERIAL_LOOP_DEPTH := 1.8
const AERIAL_LOOP_LAG := 0.22
```

Preferred rendering approach:
- Build fly line and leader as short cylinder/tube segments between sampled curve points, or use a small `ArrayMesh` ribbon facing the camera.
- Keep two materials: opaque/high-visibility fly line and thinner semi-transparent leader.
- Disable shadows on line mesh instances.
- Make fly line color visible against water, e.g. pale olive/chartreuse with emission multiplier around `0.25–0.45`, while keeping leader subtle.

Add state for animated aerial line:

```gdscript
var _aerial_cast_line: MeshInstance3D = null
var _aerial_leader_line: MeshInstance3D = null
var _cast_line_animation_phase := "idle"
var _cast_line_animation_t := 0.0
var _cast_line_loop_quality := "none"
```

Add public/internal methods in `RiverWorld3D`:

```gdscript
func _start_aerial_line_phase(phase: String) -> void:
	_cast_line_animation_phase = phase
	_cast_line_animation_t = 0.0
	_cast_line_loop_quality = _loop_quality
	_ensure_aerial_line_nodes()

func _update_aerial_cast_line(delta: float) -> void:
	if _selected_cast_target.is_empty():
		_clear_aerial_cast_line()
		return
	if _cast_line_animation_phase == "idle":
		_update_line_to_selected_target_preview()
		return
	_cast_line_animation_t = minf(_cast_line_animation_t + delta, 1.0)
	_rebuild_aerial_line_mesh(_current_rod_tip(), _selected_cast_target["target"], _cast_line_animation_phase, _cast_line_animation_t)
```

Call `_update_aerial_cast_line(delta)` from `_process(delta)` or `_update_time_critical_state(delta)` so the line follows the live rod tip every frame.

Aerial curve behavior:
- During `lifting_overhead` / `backcast_loaded`, the line should unroll behind and above the angler.
- During `forward_stroke`, it should form a loop traveling forward toward the selected water target.
- Use `_arc_cursor`, rod elevation, and `_line_load` to shape the loop.
- Tight loop: narrow loop, more forward extension.
- Wide/late loop: larger belly and lower sag.
- Tailing loop: crossing/tucked section that visibly dips under the forward leg.

Example point sampler for the forward aerial loop:

```gdscript
func _aerial_line_point(origin: Vector3, target: Vector3, phase: String, t: float, progress: float) -> Vector3:
	var cast_dir := _current_cast_direction()
	var right := cast_dir.cross(Vector3.UP).normalized()
	var distance := origin.distance_to(target)
	var reach_t := clampf(progress - AERIAL_LOOP_LAG * sin(t * PI), 0.0, 1.0)
	var point := origin.lerp(target, t * reach_t)
	var loop_height := sin(t * PI) * AERIAL_LOOP_HEIGHT * clampf(_line_load, 0.35, 1.15)
	var loop_belly := sin(t * TAU + progress * PI) * AERIAL_LOOP_DEPTH * 0.18
	if phase == "backcast":
		point = origin - cast_dir * distance * t * clampf(progress, 0.15, 1.0)
	point.y += loop_height
	point += right * loop_belly
	return point
```

Do not copy this blindly if it fights current coordinate assumptions; it is a starting shape. The key requirement is that the line is anchored to `_current_rod_tip()` and its loop changes continuously as the player moves the rod.

Integrate with existing gesture state:
- In `lifting_overhead` when elevation first starts, call `_start_aerial_line_phase("pickup")` or show preview line from rod tip to target.
- In `backcast_loaded`, call/update phase `"backcast"`.
- In `forward_stroke`, call/update phase `"forward"`.
- On successful `perform_selected_cast()`, clear aerial nodes and let existing drift `_cast_line` / `_leader_line` take over.
- On target cancel, `_clear_cast_visuals()` must also clear aerial line nodes.

Improve the existing drift line visibility:
- Replace `_build_line_strip_mesh()` with a tube/ribbon mesh builder, or add a `_build_visible_line_mesh(points, radius, material)` helper.
- Increase `CAST_LINE_SEGMENTS` from `7` to at least `18` for smoother bow/sag.
- Include `_cast_line_animation_phase`, `_arc_cursor`, and line-load changes in cache invalidation if aerial meshes reuse the same nodes.

**Verification:**
Manual visual checks are required because headless cannot prove visibility:
1. Select a water target: a visible line preview should run from rod tip toward/near the target or picked-up fly.
2. Lift into backcast: line should rise and unroll behind the rod, visible from over-shoulder camera.
3. Lower into forward stroke: loop should travel forward with the rod motion.
4. Delivery: aerial line disappears/settles into the existing rod-tip-to-dry-fly drift line.
5. Drift: line remains visible, attached to live rod tip, with transparent leader near the fly.
6. Against bright water, fly line remains readable without looking like a neon rope.

Headless/syntax checks:

```bash
godot4 --headless --path . --scene res://scenes/RiverWorld3D.tscn --quit
godot4 --headless --path . --quit
git diff --check
```

---

## Task 11: Update casting HUD and prompts

**Objective:** Align the instructions with gesture-based casting and slower rod control.

**Files:**
- Modify: `scripts/river/river_world_3d.gd`
- Modify: `scripts/ui/casting_minigame_panel.gd`
- Modify: `docs/specs/2026-05-30-casting-loop-minigame.md` if the spec should remain current

**Implementation details:**
Update text that currently references pressing O to commit overhead. Examples to search:

```bash
rg "O/R|O overhead|Space casts|press O|CAST" scripts docs
```

Expected new language:
- `Click/Space selects water. Raise and lower rod to cast.`
- `Backcast: lift high and pause.`
- `Forward: lower rod to deliver.`
- `Wheel: line length.`
- `R: roll cast when fly is on water.`

**Verification:**
Run headless smoke and manually verify HUD copy during target selection.

---

## Task 12: Add/adjust casting gesture and line-animation probe tests

**Objective:** Lock in the new behavior so future changes do not reintroduce key-press commit, twitchy input, invisible line rendering, or non-animated casting line visuals.

**Files:**
- Modify: `tests/casting_loop_modes_check.gd`
- Modify: `tests/casting_zoom_controls_check.gd`
- Create: `tests/over_shoulder_casting_check.gd` if current tests are too broad
- Create or extend: `tests/casting_line_visibility_check.gd`

**Test cases:**
1. Target selection enters casting control and over-shoulder camera state.
2. O/overhead action while target selected does not call `perform_selected_cast()`.
3. Rod elevation below load threshold does not enter `backcast_loaded`.
4. Rod elevation above `OVERHEAD_BACKCAST_LOAD_ELEV`, then descending through `OVERHEAD_BACKCAST_RELEASE_ELEV`, enters forward stroke.
5. Cast performs only after descending through `OVERHEAD_FORWARD_COMMIT_ELEV`.
6. `apply_cast_mouse_motion(Vector2(1000, 0))` does not instantly set `_rod_aim_yaw` to the final target in one frame; yaw changes are speed-limited.
7. Selecting a target creates visible fly-line preview nodes with non-null meshes/materials.
8. Entering backcast/forward-stroke changes aerial line mesh vertices over time while the rod tip remains the first anchor point.
9. Cast commit clears aerial line nodes and leaves drift line/leader nodes visible and attached to the dry fly.

**Verification commands:**
Use existing project pattern for tests. If these are SceneTree wrapper scripts, run examples like:

```bash
godot4 --headless --path . --script res://tests/casting_loop_modes_check.gd
godot4 --headless --path . --script res://tests/casting_zoom_controls_check.gd
godot4 --headless --path . --script res://tests/over_shoulder_casting_check.gd
```

Then run:

```bash
godot4 --headless --path . --scene res://scenes/RiverWorld3D.tscn --quit
godot4 --headless --path . --quit
git diff --check
```

---

## Task 13: Manual tuning pass

**Objective:** Tune the feel after the implementation is functional.

**Files likely modified:**
- `scripts/player/first_person_angler.gd`
- `scripts/player/fly_rod_3d.gd`
- `scripts/river/river_world_3d.gd`

**Tuning checklist:**
- Rod yaw requires a deliberate mouse sweep but does not feel sluggish.
- Rod elevation takes roughly a real casting gesture length: a clear lift, stop/load, forward lower.
- Camera shows target ring and rod tip at the same time.
- Camera does not clip water, terrain, or player body.
- Cast line remains visible and attached to rod tip during target, aerial cast, delivery, and drift.
- Cast launches only on lowering rod.
- Roll cast remains available and does not conflict with overhead gesture.

Suggested starting values:
- `CAST_MOUSE_YAW_SENSITIVITY`: `0.00075` to `0.00110`
- `ROD_CAST_SENSITIVITY`: `0.0018` to `0.0026`
- `ROD_ELEVATION_RESPONSE`: `6.0` to `10.0`
- `OVERHEAD_BACKCAST_LOAD_ELEV`: `1.05` to `1.20`
- `OVERHEAD_FORWARD_COMMIT_ELEV`: `0.06` to `0.14`
- Over-shoulder offset: x `0.45–0.65`, y `0.15–0.40`, z `0.90–1.35`

---

## Acceptance criteria

- Selecting a water target moves into an over-the-shoulder angler perspective by default.
- Mouse no longer directly rotates the camera/head during casting; it drives a damped rod controller.
- The rod requires a larger motion to traverse the casting arc.
- Overhead cast cannot be completed by pressing O/Space/click while target is selected.
- Overhead cast completes when the rod is lowered through the forward stroke threshold.
- Cast line/leader and dry-fly drift behavior remain intact.
- Fly line is visible during target preview, backcast, forward stroke, delivery, and drift; it animates from the player’s rod motion instead of appearing only after cast commit.
- Headless scene and project smoke checks pass.
- `git diff --check` passes.

---

## Notes / risk controls

- Do not change LowerMadisonReach or rebuild terrain logic for this feature.
- Do not reintroduce 2D `RiverWorld.tscn` or procedural river tiles.
- Be careful with camera `set_as_top_level(true)`: always restore `set_as_top_level(false)` on exit/cancel/commit.
- Keep normal first-person look sensitivity unchanged.
- Existing working tree has uncommitted changes; do not overwrite unrelated edits and do not commit unless explicitly requested.
