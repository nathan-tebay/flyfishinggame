extends SceneTree

const SCENE := "res://scenes/RiverWorld3D.tscn"

func _fail(message: String) -> void:
	printerr("over_shoulder_casting_check: FAIL - %s" % message)
	quit(1)

func _water_target(world: Node, origin: Vector3) -> Vector3:
	var target := origin + Vector3(0.0, -8.0, -16.0)
	target.y = world.reach.WATER_HEIGHT
	target = world._clamp_to_world_bounds(target)
	var landing: Dictionary = world.reach.sample(target)
	if bool(landing.get("is_water", false)):
		return target
	var holds: Array = world.reach.hold_points()
	if holds.is_empty():
		return Vector3.INF
	var hold := holds[0] as Dictionary
	return world.reach.position_at(float(hold["fraction"]), float(hold["lateral"]), world.reach.WATER_HEIGHT)

func _initialize() -> void:
	var packed: PackedScene = load(SCENE)
	var world: Node = packed.instantiate()
	root.add_child(world)
	await process_frame
	await process_frame

	var angler = world.angler

	# 1. Target selection enters over-shoulder camera
	var origin: Vector3 = angler.rod.tip_global_position()
	var target := _water_target(world, origin)
	if target == Vector3.INF:
		_fail("no valid water target found")
		return
	world.select_cast_target(origin, target)
	await process_frame
	if not angler.is_in_cast_mode():
		_fail("selecting cast target must enter cast mode")
		return

	# 2. Hookset with no pending take should not start drift
	var drift_size_before: int = world._active_drift.size()
	world._on_hookset_requested()
	await process_frame
	if world._active_drift.size() != drift_size_before:
		_fail("hookset with no fish pending must not launch a drift")
		return

	# Casting now flows through the CastingStateManager seam, driven each frame by
	# world._drive_casting_loop(). These cases exercise that real path end-to-end
	# (drive -> module -> delivered/false_cast signal -> perform_selected_cast),
	# staging the module's gameplay state the way the old white-box test did.
	var mgr = world._casting_state_mgr
	if mgr == null:
		_fail("world must own a CastingStateManager seam")
		return

	# Signal spies: prove the discrete events actually fire on the new path.
	var delivered_count := [0]
	var false_cast_count := [0]
	mgr.delivered.connect(func(_s, _l, _q): delivered_count[0] += 1)
	mgr.false_cast.connect(func(_c): false_cast_count[0] += 1)

	# 3. Raising from idle begins a backcast; reaching load then descending -> forward
	mgr.reset_to_setup()
	world._active_drift.clear()
	angler.rod._elevation_offset = 0.40  # >= lift_start_elev (0.28)
	world._drive_casting_loop(0.016)
	if mgr.get_phase_name() != "BACKCAST":
		_fail("raising the rod from idle must begin a backcast")
		return
	angler.rod._elevation_offset = 1.20  # reach the load height
	world._drive_casting_loop(0.016)
	angler.rod._elevation_offset = 1.00  # now descending after load
	world._drive_casting_loop(0.016)
	if mgr.get_phase_name() != "FORWARD":
		_fail("reaching load then descending must enter the forward stroke")
		return

	# 4. Under-loaded forward stroke does NOT deliver — it false-casts back to backcast
	mgr._current_phase = CastingStateManager.Phase.FORWARD
	mgr._reached_bottom = false
	mgr._line_load = 0.20
	mgr._prev_rod_elevation = 0.50
	world._active_drift.clear()
	angler.rod._elevation_offset = 0.06  # descend through the commit height
	world._drive_casting_loop(0.016)
	if not world._active_drift.is_empty():
		_fail("an under-loaded forward stroke must not deliver a cast")
		return
	angler.rod._elevation_offset = 0.20  # reverse upward at the bottom
	world._drive_casting_loop(0.016)
	if mgr.get_phase_name() != "BACKCAST":
		_fail("under-loaded bottom reversal must false-cast back into a backcast")
		return
	if false_cast_count[0] < 1:
		_fail("a false cast must emit the false_cast signal")
		return

	# 5. A loaded forward stroke delivers only after the loop has straightened.
	world.select_cast_target(origin, target)
	mgr._current_phase = CastingStateManager.Phase.FORWARD
	mgr._reached_bottom = false
	mgr._line_load = 0.95  # loaded past delivery_load_min
	mgr._stroke_clock = 0.0  # rushed: loop not straight yet
	mgr._prev_rod_elevation = 0.50
	world._active_drift.clear()
	angler.rod._elevation_offset = 0.06
	world._drive_casting_loop(0.016)
	if not world._active_drift.is_empty():
		_fail("dropping the rod before the loop straightens must not deliver")
		return
	# Letting the loop straighten (timing past delivery_timing_min) then delivering.
	mgr._current_phase = CastingStateManager.Phase.FORWARD
	mgr._reached_bottom = false
	mgr._stroke_clock = mgr._unroll_time
	mgr._prev_rod_elevation = 0.50
	angler.rod._elevation_offset = 0.06
	world._drive_casting_loop(0.016)
	if world._active_drift.is_empty():
		_fail("a loaded, well-timed forward stroke must deliver and start a drift")
		return
	if delivered_count[0] < 1:
		_fail("a completed delivery must emit the delivered signal")
		return

	# 6. Cast mouse yaw is speed-limited — a single large delta must not snap
	# instantly to the clamped target. Check that the final yaw is strictly
	# less than the maximum allowed yaw (ROD_CAST_MAX_YAW) after one frame.
	world.select_cast_target(origin, target)
	await process_frame
	angler._rod_lateral = 0.0
	angler._rod_lateral_target = 0.0
	angler.apply_cast_mouse_motion(Vector2(1000.0, 0.0))
	angler._update_rod_aim(0.016)
	var yaw_after: float = angler._rod_lateral
	if absf(yaw_after) >= PI * 0.4:
		_fail("cast yaw must be speed-limited; large mouse delta must not snap to full angle in one frame")
		return

	# 7. A real Skeleton3D rig exists and the whole right arm sweeps with elevation.
	var skel: Skeleton3D = angler._skeleton
	if skel == null or skel.get_bone_count() == 0:
		_fail("angler should build a Skeleton3D rig with bones")
		return
	var upper_r: int = int(angler._bone_idx.get("UpperArmR", -1))
	if upper_r < 0:
		_fail("skeleton should contain a right upper-arm bone (UpperArmR)")
		return
	angler.rod._elevation_offset = 0.05
	for _i in 24:
		angler._update_cast_arm(0.016)
	var low_pose: Quaternion = skel.get_bone_pose_rotation(upper_r)
	angler.rod._elevation_offset = 1.30
	for _j in 24:
		angler._update_cast_arm(0.016)
	var high_pose: Quaternion = skel.get_bone_pose_rotation(upper_r)
	if low_pose.angle_to(high_pose) < deg_to_rad(20.0):
		_fail("right arm shoulder bone must sweep noticeably between low and high rod elevation")
		return

	# 8. Cast plane self-centers toward vertical (lateral 0) when not steering.
	angler._rod_lateral = 0.0
	angler._rod_lateral_target = 0.6
	for _k in 40:
		angler._update_rod_aim(0.016)
	if absf(angler._rod_lateral_target) > 0.2:
		_fail("cast plane should self-center toward 0 when no lateral input is given")
		return

	print("over_shoulder_casting_check: PASS")
	quit(0)
