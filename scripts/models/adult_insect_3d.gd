class_name AdultInsect3D
extends Node3D

enum Kind { MAYFLY, CADDIS }

const MAT_MAYFLY = preload("res://assets/3d/materials/insect_mayfly_body.tres")
const MAT_CADDIS = preload("res://assets/3d/materials/insect_caddis_body.tres")
const MAT_WING = preload("res://assets/3d/materials/insect_wing.tres")
const MAT_DETAIL = preload("res://assets/3d/materials/insect_detail.tres")

var kind: int = Kind.MAYFLY
var display_scale := 1.0
var animates := true
var animation_phase := 0.0
var _anchor := Vector3.ZERO
var _wing_left: Node3D = null
var _wing_right: Node3D = null
var _left_rest_rotation := Vector3.ZERO
var _right_rest_rotation := Vector3.ZERO


func configure(adult_kind: int, size_scale: float, moving: bool, phase: float = 0.0) -> void:
	kind = adult_kind
	display_scale = size_scale
	animates = moving
	animation_phase = phase


func _ready() -> void:
	_anchor = position
	if kind == Kind.MAYFLY:
		_build_mayfly()
	else:
		_build_caddis()


func _process(_delta: float) -> void:
	if not animates:
		return
	var time := Time.get_ticks_msec() * 0.001 + animation_phase
	position = _anchor + Vector3(sin(time * 0.84) * 0.16, sin(time * 2.3) * 0.035, cos(time * 0.72) * 0.10)
	var flap := sin(time * 15.0) * 0.17
	if _wing_left != null:
		_wing_left.rotation = _left_rest_rotation + Vector3(0.0, 0.0, flap)
	if _wing_right != null:
		_wing_right.rotation = _right_rest_rotation - Vector3(0.0, 0.0, flap)


func display_name() -> String:
	return "Mayfly Dun · Adult" if kind == Kind.MAYFLY else "Caddis · Adult"


func _build_mayfly() -> void:
	name = "AdultMayfly"
	var size := display_scale
	_add_body_segment("MayflyThorax", Vector3(0.0, 0.0, 0.0), 0.010 * size, 0.022 * size, MAT_MAYFLY)
	_add_body_segment("MayflyAbdomen", Vector3(0.0, 0.0, 0.030 * size), 0.005 * size, 0.070 * size, MAT_MAYFLY)
	_add_mayfly_wings(size)
	_add_lines(PackedVector3Array([
		Vector3(-0.002, 0.0, 0.062) * size, Vector3(-0.020, -0.004, 0.140) * size,
		Vector3(0.002, 0.0, 0.062) * size, Vector3(0.020, -0.004, 0.140) * size,
		Vector3(0.0, 0.0, 0.064) * size, Vector3(0.0, 0.002, 0.148) * size,
	]), "MayflyTails")


func _build_caddis() -> void:
	name = "AdultCaddis"
	var size := display_scale
	_add_body_segment("CaddisThorax", Vector3(0.0, 0.0, -0.004 * size), 0.012 * size, 0.025 * size, MAT_CADDIS)
	_add_body_segment("CaddisAbdomen", Vector3(0.0, 0.0, 0.022 * size), 0.007 * size, 0.052 * size, MAT_CADDIS)
	_add_caddis_wings(size)
	_add_lines(PackedVector3Array([
		Vector3(-0.005, 0.002, -0.016) * size, Vector3(-0.036, 0.006, -0.085) * size,
		Vector3(0.005, 0.002, -0.016) * size, Vector3(0.036, 0.006, -0.085) * size,
	]), "CaddisAntennae")


func _add_body_segment(segment_name: String, at: Vector3, radius: float, segment_length: float,
		material: Material) -> void:
	var instance := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = segment_length
	mesh.radial_segments = 7
	mesh.rings = 3
	instance.name = segment_name
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	instance.rotation.x = PI * 0.5
	add_child(instance)


func _add_mayfly_wings(size: float) -> void:
	_wing_left = Node3D.new()
	_wing_right = Node3D.new()
	_wing_left.name = "LeftUprightWing"
	_wing_right.name = "RightUprightWing"
	_wing_left.rotation.z = -0.16
	_wing_right.rotation.z = 0.16
	_left_rest_rotation = _wing_left.rotation
	_right_rest_rotation = _wing_right.rotation
	add_child(_wing_left)
	add_child(_wing_right)
	var left_points := PackedVector3Array([
		Vector3(-0.002, 0.005, 0.006) * size,
		Vector3(-0.011, 0.068, 0.016) * size,
		Vector3(-0.009, 0.035, 0.058) * size,
	])
	var right_points := PackedVector3Array([
		Vector3(0.002, 0.005, 0.006) * size,
		Vector3(0.009, 0.035, 0.058) * size,
		Vector3(0.011, 0.068, 0.016) * size,
	])
	_wing_left.add_child(_wing_mesh("LeftWingMembrane", left_points))
	_wing_right.add_child(_wing_mesh("RightWingMembrane", right_points))


func _add_caddis_wings(size: float) -> void:
	_wing_left = Node3D.new()
	_wing_right = Node3D.new()
	_wing_left.name = "LeftTentWing"
	_wing_right.name = "RightTentWing"
	_left_rest_rotation = _wing_left.rotation
	_right_rest_rotation = _wing_right.rotation
	add_child(_wing_left)
	add_child(_wing_right)
	var left_points := PackedVector3Array([
		Vector3(-0.002, 0.010, -0.008) * size,
		Vector3(-0.034, 0.006, 0.056) * size,
		Vector3(-0.004, 0.010, 0.066) * size,
	])
	var right_points := PackedVector3Array([
		Vector3(0.002, 0.010, -0.008) * size,
		Vector3(0.004, 0.010, 0.066) * size,
		Vector3(0.034, 0.006, 0.056) * size,
	])
	_wing_left.add_child(_wing_mesh("LeftTentMembrane", left_points))
	_wing_right.add_child(_wing_mesh("RightTentMembrane", right_points))


func _wing_mesh(wing_name: String, points: PackedVector3Array) -> MeshInstance3D:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.add_vertex(points[0])
	tool.add_vertex(points[1])
	tool.add_vertex(points[2])
	tool.add_vertex(points[0])
	tool.add_vertex(points[2])
	tool.add_vertex(points[1])
	tool.generate_normals()
	var wing := MeshInstance3D.new()
	wing.name = wing_name
	wing.mesh = tool.commit()
	wing.material_override = MAT_WING
	return wing


func _add_lines(points: PackedVector3Array, node_name: String) -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, MAT_DETAIL)
	for point in points:
		mesh.surface_add_vertex(point)
	mesh.surface_end()
	var lines := MeshInstance3D.new()
	lines.name = node_name
	lines.mesh = mesh
	add_child(lines)
