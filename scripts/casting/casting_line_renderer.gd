class_name CastingLineRenderer
extends Node

# Render the fly line as a ribbon mesh, with dynamic width based on loop position and bulge.
# Takes line control points and loop physics state, produces a 3D ribbon mesh.

const SEGMENTS := 24  # Matches AERIAL_LINE_SEGMENTS


# Build a ribbon mesh from line points with loop-aware width modulation.
# - points: centerline positions from rod tip to fly
# - base_half_width: ribbon half-width at rest (away from loop)
# - loop_state: LoopPhysicsEngine.LoopState with position, width, bulge
# - material: Material to apply to mesh
func build_ribbon_with_loop(
	points: PackedVector3Array,
	base_half_width: float,
	loop_state: LoopPhysicsEngine.LoopState,
	material: Material,
	camera_pos: Vector3 = Vector3.INF,
	camera_right: Vector3 = Vector3.ZERO
) -> ArrayMesh:

	if DisplayServer.get_name() == "headless":
		return ArrayMesh.new()

	if points.size() < 2:
		return ArrayMesh.new()

	var mesh := ArrayMesh.new()
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Build ribbon: for each segment, create a quad with width modulated by loop
	var n = points.size()
	for i in range(n - 1):
		var p0 := points[i]
		var p1 := points[i + 1]

		# Skip zero-length segments (can occur after temporal smoothing).
		var seg := p1 - p0
		if seg.length_squared() < 1e-8:
			continue
		var seg_dir := seg.normalized()
		# Camera-facing ribbon width so the strip presents its face from the
		# over-shoulder camera (which looks roughly along the line). Stays defined on
		# vertical loop-nose segments (no spiky flip) and keeps on-screen width even
		# when a segment is end-on. Material is double-sided so winding can't cull it.
		var right := _ribbon_right(seg_dir, (p0 + p1) * 0.5, camera_pos, camera_right)

		# Width modulation: wider near loop, normal elsewhere
		var t0 = float(i) / float(n - 1)  # normalized position along line
		var t1 = float(i + 1) / float(n - 1)
		var w0 = _width_at_position(t0, loop_state, base_half_width)
		var w1 = _width_at_position(t1, loop_state, base_half_width)

		# Quad vertices: left and right sides
		var v0l: Vector3 = p0 - right * w0
		var v0r: Vector3 = p0 + right * w0
		var v1l: Vector3 = p1 - right * w1
		var v1r: Vector3 = p1 + right * w1

		# UV coordinates for texture mapping
		var uv0 := Vector2(0.0, t0)
		var uv1 := Vector2(1.0, t0)
		var uv2 := Vector2(1.0, t1)
		var uv3 := Vector2(0.0, t1)

		# Add quad (two triangles)
		tool.set_uv(uv0)
		tool.add_vertex(v0l)
		tool.set_uv(uv1)
		tool.add_vertex(v0r)
		tool.set_uv(uv2)
		tool.add_vertex(v1r)

		tool.set_uv(uv0)
		tool.add_vertex(v0l)
		tool.set_uv(uv2)
		tool.add_vertex(v1r)
		tool.set_uv(uv3)
		tool.add_vertex(v1l)

	tool.set_material(material)
	tool.commit(mesh)
	return mesh


# Stable ribbon-width direction. Prefers a camera-facing perpendicular so the strip
# always presents its face and never flips where the line runs vertical; falls back
# to a horizontal perpendicular when no camera is supplied or the view is edge-on.
func _ribbon_right(seg_dir: Vector3, mid: Vector3, camera_pos: Vector3, camera_right: Vector3) -> Vector3:
	if camera_pos != Vector3.INF:
		var view_dir := camera_pos - mid
		if view_dir.length_squared() > 1e-6:
			var r := seg_dir.cross(view_dir.normalized())
			if r.length_squared() > 1e-6:
				return r.normalized()
		# Segment is end-on to the camera: use the camera's screen-right (projected
		# perpendicular to the segment) so the strip keeps visible on-screen width.
		if camera_right.length_squared() > 1e-6:
			var cr := camera_right - seg_dir * seg_dir.dot(camera_right)
			if cr.length_squared() > 1e-6:
				return cr.normalized()
	var r_up := seg_dir.cross(Vector3.UP)
	if r_up.length_squared() > 1e-6:
		return r_up.normalized()
	return Vector3.RIGHT


# Calculate ribbon width at a point along the line, based on loop proximity.
# Wider near the loop apex, normal elsewhere.
func _width_at_position(t: float, loop_state: LoopPhysicsEngine.LoopState, base_width: float) -> float:
	var loop_pos = loop_state.position_along_line
	var loop_width = loop_state.width

	# Distance from this point to the loop center
	var dist_to_loop = absf(t - loop_pos)

	# Parabolic bulge: widens near loop, falls off smoothly
	# Similar to the line offset calculation, but for ribbon width
	var bulge_factor = maxf(1.0 - (dist_to_loop / maxf(loop_width, 0.05)), 0.0)
	var width_modulation = bulge_factor * bulge_factor  # parabolic

	# Width increases near loop (up to 2x base width)
	var modulated_width = base_width * (1.0 + width_modulation * 1.5)
	return clampf(modulated_width, base_width * 0.5, base_width * 2.5)
