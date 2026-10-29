extends SceneTree

# Covers the cast-stance control surface under the over-shoulder gesture model:
# slow movement while a target is held, a textured water-surface target marker,
# Z/X (and wheel) line-length adjustment, and casting-control release on delivery.

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
		_fail("selecting a target should enter casting controls")
		return
	if not world.has_method("casting_movement_scale"):
		_fail("world should expose slow cast-stance movement scale")
		return
	if float(world.casting_movement_scale()) <= 0.0 or float(world.casting_movement_scale()) >= 1.0:
		_fail("cast stance should allow slow WASD movement, not a full movement lock")
		return

	# Rod stands straight above the angler's head when casting controls begin.
	var stance_rotation: Vector3 = world.angler.rod.rotation
	if stance_rotation.length() > 0.01:
		_fail("rod should stand straight above the angler's head when casting controls begin")
		return

	# Cast camera presets: V toggles close <-> far overview, moving the framing point.
	var close_pos: Vector3 = world.angler._cast_camera_world_pos()
	world.angler.toggle_cast_camera_view()
	if not world.angler._cast_view_far:
		_fail("cast_camera toggle should switch to the far overview preset")
		return
	var far_pos: Vector3 = world.angler._cast_camera_world_pos()
	if close_pos.distance_to(far_pos) < 5.0:
		_fail("far cast-camera preset should sit much farther back/up than the close preset")
		return
	world.angler.toggle_cast_camera_view()
	if world.angler._cast_view_far:
		_fail("cast_camera toggle should switch back to the close preset")
		return

	# Cast target renders a textured quad sitting on the water surface.
	var marker: MeshInstance3D = world.get_node_or_null("CastTargetMarker")
	if marker == null:
		_fail("cast target should render a water-surface marker")
		return
	if not (marker.mesh is QuadMesh):
		_fail("cast target marker should be a textured quad on the water surface")
		return
	if absf(marker.global_position.y - (world.reach.WATER_HEIGHT + 0.006)) > 0.002:
		_fail("cast target marker should sit directly on the water surface")
		return
	if marker.material_override == null or not (marker.material_override as StandardMaterial3D).albedo_texture:
		_fail("cast target marker should use the trout target texture")
		return

	# Z/X (and mouse wheel) feed line out / in without moving the fixed target.
	var before: Vector3 = world._selected_cast_target["target"]
	world._adjust_cast_line_length(-1)
	var length_before := float(world._selected_cast_target.get("line_length", 0.0))
	world._adjust_cast_line_length(1)
	var length_after := float(world._selected_cast_target.get("line_length", 0.0))
	if length_after <= length_before:
		_fail("line-length adjustment should feed line out")
		return
	var after: Vector3 = world._selected_cast_target["target"]
	if before.distance_to(after) > 0.01:
		_fail("selected cast target should stay stationary on the water while line length changes")
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

	print("casting_zoom_controls_check: PASS (textured water target, line length, slow cast-stance movement)")
	quit(0)
