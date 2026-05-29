class_name FlyRod3D
extends Node3D

const MAT_BLANK = preload("res://assets/3d/materials/rod.tres")
const MAT_CORK = preload("res://assets/3d/materials/rod_cork.tres")
const MAT_METAL = preload("res://assets/3d/materials/rod_metal.tres")
const MAT_REEL_LINE = preload("res://assets/3d/materials/rod_reel_line.tres")
const MAT_FLY_LINE = preload("res://assets/3d/materials/fly_line.tres")

const ROD_LENGTH := 2.74
const GUIDE_POSITIONS := [0.46, 0.76, 1.08, 1.41, 1.75, 2.08, 2.36, 2.60, 2.72]

var _tip: Marker3D = null
var _rest_rotation := Vector3.ZERO
var _cast_timer := 0.0
var _cast_style := "overhead"
var force_headless_build := false


func _ready() -> void:
	_rest_rotation = rotation
	_tip = Marker3D.new()
	_tip.name = "RodTip"
	_tip.position = Vector3(0.0, ROD_LENGTH, -0.012)
	add_child(_tip)
	if DisplayServer.get_name() == "headless" and not force_headless_build:
		return
	_build_grip_and_blank()
	_build_reel()
	_build_guides()
	_build_threaded_line()


func _process(delta: float) -> void:
	if _cast_timer <= 0.0:
		rotation = rotation.lerp(_rest_rotation, minf(delta * 10.0, 1.0))
		return
	_cast_timer = maxf(_cast_timer - delta, 0.0)
	var cast_progress := 1.0 - _cast_timer / 0.56
	var flex := sin(cast_progress * PI) * 0.20
	if _cast_style == "back":
		rotation = _rest_rotation + Vector3(flex * 0.75, -flex * 0.10, flex * 0.16)
		return
	if _cast_style == "forward":
		rotation = _rest_rotation + Vector3(-flex * 0.88, flex * 0.12, -flex * 0.12)
		return
	if _cast_style == "roll":
		var sweep := sin(cast_progress * PI) * 0.28
		rotation = _rest_rotation + Vector3(-flex * 0.35, sweep, -flex * 0.18)
		return
	rotation = _rest_rotation + Vector3(-flex, flex * 0.10, -flex * 0.08)


func play_cast(style: String = "overhead") -> void:
	_cast_style = style
	_cast_timer = 0.56


func tip_global_position() -> Vector3:
	return global_position if _tip == null else _tip.global_position


func _build_grip_and_blank() -> void:
	_add_cylinder("CorkGrip", 0.28, 0.028, 0.041, 0.14, MAT_CORK, 12)
	_add_cylinder("ButtCap", 0.028, 0.043, 0.043, -0.014, MAT_METAL, 10)
	var segment_lengths := [0.56, 0.63, 0.63, 0.64]
	var segment_radii := [
		Vector2(0.0090, 0.0072),
		Vector2(0.0072, 0.0053),
		Vector2(0.0053, 0.0035),
		Vector2(0.0035, 0.0015),
	]
	var start := 0.28
	for i in segment_lengths.size():
		var segment_length: float = segment_lengths[i]
		var radii: Vector2 = segment_radii[i]
		_add_cylinder("GraphiteBlankSection%d" % (i + 1), segment_length,
				radii.y, radii.x, start + segment_length * 0.5, MAT_BLANK, 9)
		start += segment_length


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
		var guide_mesh := TorusMesh.new()
		var guide_radius := lerpf(0.020, 0.008, float(i) / float(GUIDE_POSITIONS.size() - 1))
		guide_mesh.inner_radius = guide_radius * 0.72
		guide_mesh.outer_radius = guide_radius
		guide_mesh.rings = 7
		guide_mesh.ring_segments = 10
		guide.name = "SnakeGuide%02d" % (i + 1)
		guide.mesh = guide_mesh
		guide.material_override = MAT_METAL
		guide.position = Vector3(0.0, float(GUIDE_POSITIONS[i]), -guide_radius)
		add_child(guide)


func _build_threaded_line() -> void:
	var line_mesh := ImmediateMesh.new()
	line_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, MAT_FLY_LINE)
	line_mesh.surface_add_vertex(Vector3(0.0, 0.035, -0.13))
	for guide_position in GUIDE_POSITIONS:
		line_mesh.surface_add_vertex(Vector3(0.0, float(guide_position), -0.012))
	line_mesh.surface_add_vertex(Vector3(0.0, ROD_LENGTH, -0.012))
	line_mesh.surface_add_vertex(Vector3(0.0, ROD_LENGTH + 0.25, -0.09))
	line_mesh.surface_end()
	var line := MeshInstance3D.new()
	line.name = "LineThroughGuides"
	line.mesh = line_mesh
	add_child(line)


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
