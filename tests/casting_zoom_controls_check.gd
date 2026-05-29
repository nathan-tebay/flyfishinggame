extends SceneTree

const SCENE := "res://scenes/RiverWorld3D.tscn"

func _fail(message: String) -> void:
	printerr("casting_zoom_controls_check: FAIL - %s" % message)
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

	if not world.has_method("is_casting_control_active"):
		_fail("world should expose casting-control lock state")
		return

	var origin: Vector3 = world.angler.rod.tip_global_position()
	var target := _water_target(world, origin)
	if target == Vector3.INF:
		_fail("could not find water target")
		return

	var start_fov: float = world.angler.camera_fov()
	if not world.select_cast_target(origin, target):
		_fail("select_cast_target rejected valid water target")
		return
	if not bool(world.is_casting_control_active()):
		_fail("selecting a target should lock player movement for cast controls")
		return
	if world.angler.camera_fov() >= start_fov:
		_fail("selecting a target should zoom in on the cast zone")
		return
	if String(world._cast_message).find("WASD") < 0 or String(world._cast_message).find("Z/X") < 0:
		_fail("target feedback should present WASD cast controls and zoom options")
		return

	var before: Vector3 = world._selected_cast_target["target"]
	if not world._nudge_selected_cast_target(Vector2(1.0, 0.0), 0.5):
		_fail("WASD cast-zone nudge should adjust selected water target")
		return
	var after: Vector3 = world._selected_cast_target["target"]
	if before.distance_to(after) <= 0.05:
		_fail("cast-zone nudge did not move the target")
		return
	if not bool(world.reach.sample(after).get("is_water", false)):
		_fail("nudged cast target should remain on water")
		return

	world._adjust_cast_zoom(1)
	if world.angler.camera_fov() >= start_fov:
		_fail("zoom-in control should keep camera tighter than default")
		return
	if String(world._cast_message).to_lower().find("zoom") < 0:
		_fail("zoom control should update cast feedback")
		return

	if not world.perform_selected_cast("overhead"):
		_fail("overhead cast failed after target controls")
		return
	if bool(world.is_casting_control_active()):
		_fail("casting control lock should release after cast launch")
		return
	if absf(world.angler.camera_fov() - start_fov) > 0.01:
		_fail("camera FOV should restore after cast launch")
		return

	print("casting_zoom_controls_check: PASS (WASD cast-zone controls, zoom options, and movement lock)")
	quit(0)
