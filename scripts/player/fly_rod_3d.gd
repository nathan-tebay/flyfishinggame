class_name FlyRod3D
extends Node3D

const MAT_BLANK = preload("res://assets/3d/materials/rod.tres")
const MAT_CORK = preload("res://assets/3d/materials/rod_cork.tres")
const MAT_METAL = preload("res://assets/3d/materials/rod_metal.tres")
const MAT_REEL_LINE = preload("res://assets/3d/materials/rod_reel_line.tres")
const MAT_FLY_LINE = preload("res://assets/3d/materials/fly_line.tres")

const ROD_LENGTH := 2.74
const GUIDE_POSITIONS := [0.46, 0.76, 1.08, 1.41, 1.75, 2.08, 2.36, 2.60, 2.72]
const CURVE_STEPS := 24

var _tip: Marker3D
var _cast_age := 0.56
var _cast_style := "overhead"
var _line_tension := 0.0
var _blank_segments: Array[MeshInstance3D] = []
var _guides: Array[MeshInstance3D] = []
var _threaded_line: MeshInstance3D
var _centerline := PackedVector3Array()
var _frames: Array[Basis] = []
var force_headless_build := false


func _ready() -> void:
	_tip = Marker3D.new()
	_tip.name = "RodTip"
	add_child(_tip)
	if DisplayServer.get_name() != "headless" or force_headless_build:
		_build_grip()
		_build_reel()
		_build_blank()
		_build_guides()
		_threaded_line = MeshInstance3D.new()
		_threaded_line.name = "LineThroughGuides"
		add_child(_threaded_line)
	_update_curve()


func _process(delta: float) -> void:
	_cast_age = minf(_cast_age + delta, 0.56)
	_update_curve()


func play_cast(style: String = "overhead") -> void:
	sample_stroke(style, 0.0, _line_tension)


func sample_stroke(style: String, time_seconds: float, line_tension_newtons: float) -> void:
	_cast_style = style
	_cast_age = clampf(time_seconds, 0.0, 0.56)
	_line_tension = clampf(line_tension_newtons, 0.0, 15.0)
	_update_curve()


func set_line_tension(newtons: float) -> void:
	_line_tension = clampf(newtons, 0.0, 15.0)
	_update_curve()


func tip_global_position() -> Vector3:
	return global_position if _tip == null else _tip.global_position


func centerline() -> PackedVector3Array:
	return _centerline.duplicate()


func transport_frames() -> Array[Basis]:
	return _frames.duplicate()


func _stroke_bend() -> Vector2:
	if _cast_age >= 0.56:
		return Vector2.ZERO
	var phase := _cast_age / 0.56
	var pulse := sin(phase * PI)
	match _cast_style:
		"back": return Vector2(-0.24 * pulse, 0.07 * pulse)
		"forward": return Vector2(0.28 * pulse, -0.06 * pulse)
		"roll": return Vector2(0.13 * pulse, 0.25 * pulse)
		_: return Vector2(0.29 * pulse, 0.04 * pulse)


func _update_curve() -> void:
	var stroke := _stroke_bend()
	var load_bend := minf(_line_tension * 0.025, 0.30)
	var controls: Array[Vector3] = [
		Vector3.ZERO,
		Vector3(0.0, 0.91, 0.0),
		Vector3(stroke.x * 0.30, 1.83, stroke.y * 0.30 - load_bend * 0.22),
		Vector3(stroke.x, ROD_LENGTH, -0.012 + stroke.y - load_bend)
	]
	_centerline = PackedVector3Array()
	for segment in range(3):
		for i in range(8):
			_centerline.append(_catmull_rom(controls[maxi(0, segment - 1)],
					controls[segment], controls[segment + 1],
					controls[mini(3, segment + 2)], float(i) / 8.0))
	_centerline.append(controls[3])
	var arc_length := 0.0
	for i in range(1, _centerline.size()):
		arc_length += _centerline[i].distance_to(_centerline[i - 1])
	var scale := ROD_LENGTH / arc_length
	for i in range(_centerline.size()):
		_centerline[i] *= scale
	_update_frames()
	_tip.position = _centerline[-1]
	_update_geometry()


func _catmull_rom(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t
			+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t
			+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t)


func _update_frames() -> void:
	_frames.clear()
	var previous_tangent := (_centerline[1] - _centerline[0]).normalized()
	var normal := Vector3.FORWARD
	for i in range(_centerline.size()):
		var tangent: Vector3
		if i == 0:
			tangent = previous_tangent
		elif i == _centerline.size() - 1:
			tangent = (_centerline[i] - _centerline[i - 1]).normalized()
		else:
			tangent = (_centerline[i + 1] - _centerline[i - 1]).normalized()
		if i > 0:
			if previous_tangent.dot(tangent) < -0.999:
				normal = Basis(Vector3.RIGHT, PI) * normal
			else:
				normal = Quaternion(previous_tangent, tangent) * normal
		var side := tangent.cross(normal).normalized()
		normal = side.cross(tangent).normalized()
		_frames.append(Basis(side, tangent, normal))
		previous_tangent = tangent


func _point_at_distance(distance: float) -> Vector3:
	var traversed := 0.0
	for i in range(1, _centerline.size()):
		var span := _centerline[i].distance_to(_centerline[i - 1])
		if traversed + span >= distance:
			return _centerline[i - 1].lerp(_centerline[i], (distance - traversed) / span)
		traversed += span
	return _centerline[-1]


func _build_grip() -> void:
	_add_cylinder("CorkGrip", 0.28, 0.028, 0.041, 0.14, MAT_CORK, 12)
	_add_cylinder("ButtCap", 0.028, 0.043, 0.043, -0.014, MAT_METAL, 10)


func _build_blank() -> void:
	for i in range(CURVE_STEPS):
		var piece := MeshInstance3D.new()
		piece.name = "GraphiteBlankSection%02d" % (i + 1)
		var mesh := CylinderMesh.new()
		var t := float(i) / float(CURVE_STEPS)
		mesh.bottom_radius = lerpf(0.009, 0.0015, t)
		mesh.top_radius = lerpf(0.009, 0.0015, float(i + 1) / float(CURVE_STEPS))
		mesh.radial_segments = 8
		piece.mesh = mesh
		piece.material_override = MAT_BLANK
		add_child(piece)
		_blank_segments.append(piece)


func _update_geometry() -> void:
	for i in range(_blank_segments.size()):
		var a := _centerline[i]
		var b := _centerline[i + 1]
		var piece := _blank_segments[i]
		(piece.mesh as CylinderMesh).height = a.distance_to(b)
		piece.position = (a + b) * 0.5
		piece.basis = _frames[i]
	for i in range(_guides.size()):
		var guide_position := _point_at_distance(float(GUIDE_POSITIONS[i]))
		var frame := _frames[mini(_frames.size() - 1,
				roundi(float(GUIDE_POSITIONS[i]) / ROD_LENGTH * CURVE_STEPS))]
		_guides[i].position = guide_position + frame.z * -0.012
		_guides[i].basis = frame
	if _threaded_line != null:
		var mesh := ImmediateMesh.new()
		mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, MAT_FLY_LINE)
		mesh.surface_add_vertex(Vector3(0.0, 0.035, -0.13))
		for guide in _guides:
			mesh.surface_add_vertex(guide.position)
		mesh.surface_add_vertex(_tip.position)
		mesh.surface_end()
		_threaded_line.mesh = mesh


func _build_reel() -> void:
	var reel := MeshInstance3D.new()
	var spool := CylinderMesh.new()
	spool.top_radius = 0.060
	spool.bottom_radius = 0.060
	spool.height = 0.045
	spool.radial_segments = 16
	reel.name = "FlyReelSpool"
	reel.mesh = spool
	reel.material_override = MAT_METAL
	reel.position = Vector3(0.0, 0.035, -0.080)
	reel.rotation.z = PI * 0.5
	add_child(reel)

	var backing := MeshInstance3D.new()
	var backing_mesh := CylinderMesh.new()
	backing_mesh.top_radius = 0.046
	backing_mesh.bottom_radius = 0.046
	backing_mesh.height = 0.048
	backing_mesh.radial_segments = 15
	backing.name = "VisibleReelBacking"
	backing.mesh = backing_mesh
	backing.material_override = MAT_REEL_LINE
	backing.position = Vector3(0.0, 0.035, -0.080)
	backing.rotation.z = PI * 0.5
	add_child(backing)


func _build_guides() -> void:
	for i in GUIDE_POSITIONS.size():
		var guide := MeshInstance3D.new()
		var mesh := TorusMesh.new()
		var radius := lerpf(0.020, 0.008, float(i) / float(GUIDE_POSITIONS.size() - 1))
		mesh.inner_radius = radius * 0.72
		mesh.outer_radius = radius
		mesh.rings = 7
		mesh.ring_segments = 10
		guide.name = "SnakeGuide%02d" % (i + 1)
		guide.mesh = mesh
		guide.material_override = MAT_METAL
		add_child(guide)
		_guides.append(guide)


func _add_cylinder(part_name: String, length: float, top_radius: float, bottom_radius: float,
		center_y: float, material: Material, segments: int) -> void:
	var instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = length
	mesh.radial_segments = segments
	instance.name = part_name
	instance.mesh = mesh
	instance.material_override = material
	instance.position = Vector3(0.0, center_y, 0.0)
	add_child(instance)
