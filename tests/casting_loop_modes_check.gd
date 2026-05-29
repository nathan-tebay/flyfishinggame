extends SceneTree

const SCENE := "res://scenes/RiverWorld3D.tscn"

func _fail(message: String) -> void:
	printerr("casting_loop_modes_check: FAIL - %s" % message)
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

	if not world.has_method("select_cast_target"):
		_fail("world needs select_cast_target(origin, target) for target-first casting")
		return
	if not world.has_method("perform_selected_cast"):
		_fail("world needs perform_selected_cast(style) for overhead/roll casts")
		return
	if not world.has_method("practice_cast_loop"):
		_fail("world needs practice_cast_loop(phase) for forward/backcast loop keybinds")
		return

	var origin: Vector3 = world.angler.rod.tip_global_position()
	var target := _water_target(world, origin)
	if target == Vector3.INF:
		_fail("could not find water target")
		return

	if not world.select_cast_target(origin, target):
		_fail("select_cast_target rejected a valid water target")
		return
	if world._active_drift.size() != 0:
		_fail("selecting a target should not immediately start drift")
		return
	if world.get_node_or_null("CastTargetMarker") == null:
		_fail("target selection should show a CastTargetMarker")
		return
	if String(world._cast_state).find("TARGET") < 0:
		_fail("HUD cast state should mention selected target")
		return
	if not world.practice_cast_loop("back"):
		_fail("backcast loop keybind should work after selecting target")
		return
	if String(world._cast_state).find("BACKCAST") < 0:
		_fail("backcast loop state should be visible")
		return
	if not world.practice_cast_loop("forward"):
		_fail("forward cast loop keybind should work after selecting target")
		return
	if String(world._cast_state).find("FORWARD") < 0:
		_fail("forward loop state should be visible")
		return

	if not world.perform_selected_cast("overhead"):
		_fail("overhead cast did not launch from selected target")
		return
	if world._active_drift.size() == 0:
		_fail("overhead cast should start dry-fly drift")
		return
	if String(world._active_drift.get("cast_style", "")) != "overhead":
		_fail("active drift did not record overhead cast style")
		return
	if world.get_node_or_null("CastTargetMarker") != null:
		_fail("target marker should clear after cast launch")
		return

	origin = world.angler.rod.tip_global_position()
	target = _water_target(world, origin)
	if not world.select_cast_target(origin, target):
		_fail("second target selection failed")
		return
	if not world.perform_selected_cast("roll"):
		_fail("roll cast did not launch from selected target")
		return
	if String(world._active_drift.get("cast_style", "")) != "roll":
		_fail("active drift did not record roll cast style")
		return
	if String(world._cast_message).to_lower().find("roll") < 0:
		_fail("cast feedback should name the roll cast")
		return

	print("casting_loop_modes_check: PASS (target-first overhead and roll casts launch drift)")
	quit(0)
