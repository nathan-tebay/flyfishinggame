extends SceneTree

const SCENE := "res://scenes/RiverWorld3D.tscn"

func _fail(message: String) -> void:
	printerr("casting_loop_check: FAIL - %s" % message)
	quit(1)

func _first_line_vertex(line: MeshInstance3D) -> Vector3:
	if line == null or line.mesh == null or line.mesh.get_surface_count() <= 0:
		return Vector3.INF
	var arrays := line.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if vertices.is_empty():
		return Vector3.INF
	return vertices[0]

func _initialize() -> void:
	var packed: PackedScene = load(SCENE)
	var world: Node = packed.instantiate()
	root.add_child(world)
	await process_frame
	await process_frame

	var rod = world.angler.rod
	var origin: Vector3 = rod.tip_global_position()
	var target: Vector3 = origin + Vector3(0.0, -8.0, -16.0)
	var water_y: float = world.reach.WATER_HEIGHT
	target.y = water_y
	target = world._clamp_to_world_bounds(target)
	var landing: Dictionary = world.reach.sample(target)
	if not bool(landing.get("is_water", false)):
		var holds: Array = world.reach.hold_points()
		if holds.is_empty():
			_fail("reach has no water hold points")
			return
		var hold := holds[0] as Dictionary
		target = world.reach.position_at(float(hold["fraction"]), float(hold["lateral"]), water_y)
		landing = world.reach.sample(target)
	if not bool(landing.get("is_water", false)):
		_fail("could not find water target for cast")
		return

	var selected: Dictionary = world.FLY_OPTIONS[world._selected_fly_index]
	world._render_cast(origin, target)
	world._start_dry_fly_drift(origin, target, landing, selected)

	rod.play_cast()
	await process_frame
	await process_frame

	var line: MeshInstance3D = world.get_node_or_null("CastLine")
	if line == null:
		_fail("expected visible fly line named CastLine")
		return
	var animated_tip: Vector3 = rod.tip_global_position()
	var first_vertex := _first_line_vertex(line)
	if first_vertex.distance_to(animated_tip) > 0.08:
		_fail("fly line is not attached to current rod tip after automatic rod animation update")
		return

	rod.position += Vector3(0.35, 0.0, 0.0)
	await process_frame
	var moved_tip: Vector3 = rod.tip_global_position()
	line = world.get_node_or_null("CastLine")
	if line == null:
		_fail("expected visible fly line after rod transform update")
		return
	first_vertex = _first_line_vertex(line)
	if first_vertex.distance_to(moved_tip) > 0.08:
		_fail("fly line is not attached to current rod tip after rod transform update")
		return

	var leader: MeshInstance3D = world.get_node_or_null("CastLeader")
	if leader == null:
		_fail("expected separate transparent leader section named CastLeader")
		return
	var line_arrays := line.mesh.surface_get_arrays(0)
	var line_vertices: PackedVector3Array = line_arrays[Mesh.ARRAY_VERTEX]
	var leader_arrays := leader.mesh.surface_get_arrays(0)
	var leader_vertices: PackedVector3Array = leader_arrays[Mesh.ARRAY_VERTEX]
	if line_vertices.size() < 2 or leader_vertices.size() < 2:
		_fail("line/leader sections have no endpoint vertices")
		return
	var seam_gap := line_vertices[line_vertices.size() - 1].distance_to(leader_vertices[0])
	if seam_gap > 0.025:
		_fail("line-to-leader seam has a visible position gap")
		return
	var line_tangent := (line_vertices[line_vertices.size() - 1] - line_vertices[line_vertices.size() - 2]).normalized()
	var leader_tangent := (leader_vertices[1] - leader_vertices[0]).normalized()
	if line_tangent.dot(leader_tangent) < 0.70:
		_fail("line-to-leader transition has a visible kink")
		return
	var fly_position: Vector3 = world._cast_marker.global_position
	if leader_vertices[leader_vertices.size() - 1].distance_to(fly_position) > 0.08:
		_fail("fly is not attached at the end of leader")
		return

	print("casting_loop_check: PASS (line anchored to rod tip, leader transition smooth, leader ends at fly)")
	quit(0)
