class_name FishModel3D
extends Node3D

enum Species { RAINBOW_TROUT, BROWN_TROUT, MOUNTAIN_WHITEFISH }

const MAT_RAINBOW = preload("res://assets/3d/materials/fish_rainbow_body.tres")
const MAT_BROWN = preload("res://assets/3d/materials/fish_brown_body.tres")
const MAT_WHITEFISH = preload("res://assets/3d/materials/fish_whitefish_body.tres")
const MAT_FIN = preload("res://assets/3d/materials/fish_fin.tres")
const MAT_RAINBOW_STRIPE = preload("res://assets/3d/materials/fish_rainbow_stripe.tres")
const MAT_BROWN_SPOT = preload("res://assets/3d/materials/fish_brown_spot.tres")
const MAT_RED_SPOT = preload("res://assets/3d/materials/fish_red_spot.tres")
const MAT_EYE = preload("res://assets/3d/materials/fish_eye.tres")

var species: int = Species.RAINBOW_TROUT
var body_length := 0.72
var animation_phase := 0.0
var _mid_body: Node3D = null
var _caudal_peduncle: Node3D = null
var _tail: Node3D = null
var _left_pectoral: Node3D = null
var _right_pectoral: Node3D = null
var _rest_rotation_z := 0.0


func configure(model_species: int, length_m: float, phase: float) -> void:
	species = model_species
	body_length = length_m
	animation_phase = phase


func _ready() -> void:
	_rest_rotation_z = rotation.z
	_build_animation_rig()
	_build_body()
	_build_fins()
	_build_eyes()
	_build_head_details()
	_build_species_markings()


func _process(_delta: float) -> void:
	animate_swim(Time.get_ticks_msec() * 0.0022)


func animate_swim(elapsed_seconds: float) -> void:
	var wave := elapsed_seconds + animation_phase
	var body_wave := sin(wave)
	var peduncle_wave := sin(wave + 0.45)
	var tail_wave := sin(wave + 1.10)
	if _mid_body != null:
		_mid_body.rotation.y = body_wave * 0.035
	if _caudal_peduncle != null:
		_caudal_peduncle.rotation.y = peduncle_wave * 0.090
	if _tail != null:
		_tail.rotation.y = tail_wave * 0.220
	if _left_pectoral != null:
		_left_pectoral.rotation.z = -0.20 + sin(wave * 0.70 + 0.40) * 0.035
	if _right_pectoral != null:
		_right_pectoral.rotation.z = 0.20 - sin(wave * 0.70 + 0.40) * 0.035
	rotation.z = _rest_rotation_z + body_wave * 0.018


func species_name() -> String:
	match species:
		Species.BROWN_TROUT:
			return "Brown Trout"
		Species.MOUNTAIN_WHITEFISH:
			return "Mountain Whitefish"
		_:
			return "Rainbow Trout"


func _build_animation_rig() -> void:
	_mid_body = Node3D.new()
	_mid_body.name = "MidBodySway"
	add_child(_mid_body)

	_caudal_peduncle = Node3D.new()
	_caudal_peduncle.name = "CaudalPeduncle"
	_caudal_peduncle.position = Vector3(0.0, 0.0, body_length * 0.300)
	add_child(_caudal_peduncle)


func _build_body() -> void:
	var body := MeshInstance3D.new()
	body.name = "%sBody" % species_name().replace(" ", "")
	body.mesh = _body_mesh()
	body.material_override = _body_material()
	_mid_body.add_child(body)


func _body_material() -> Material:
	match species:
		Species.BROWN_TROUT:
			return MAT_BROWN
		Species.MOUNTAIN_WHITEFISH:
			return MAT_WHITEFISH
		_:
			return MAT_RAINBOW


func _body_mesh() -> ArrayMesh:
	var slices := [
		Vector3(0.018, 0.014, -0.535),
		Vector3(0.070, 0.060, -0.465),
		Vector3(0.122, 0.094, -0.355),
		Vector3(0.152, 0.112, -0.205),
		Vector3(0.148, 0.106, -0.020),
		Vector3(0.127, 0.092, 0.145),
		Vector3(0.090, 0.070, 0.285),
		Vector3(0.052, 0.045, 0.390),
		Vector3(0.026, 0.026, 0.475),
		Vector3(0.012, 0.015, 0.520),
	]
	var radial_segments := 18
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for section in range(slices.size() - 1):
		var current: Vector3 = slices[section] * body_length
		var next: Vector3 = slices[section + 1] * body_length
		for edge in radial_segments:
			var angle_a := TAU * float(edge) / float(radial_segments)
			var angle_b := TAU * float(edge + 1) / float(radial_segments)
			var a := Vector3(sin(angle_a) * current.x, cos(angle_a) * current.y, current.z)
			var b := Vector3(sin(angle_b) * next.x, cos(angle_b) * next.y, next.z)
			var c := Vector3(sin(angle_a) * next.x, cos(angle_a) * next.y, next.z)
			var d := Vector3(sin(angle_b) * current.x, cos(angle_b) * current.y, current.z)
			_add_body_quad(tool, a, b, c, d, float(edge) / radial_segments, float(section) / slices.size())
	tool.generate_normals()
	return tool.commit()


func _add_body_quad(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		u: float, v: float) -> void:
	tool.set_uv(Vector2(u, v))
	tool.add_vertex(a)
	tool.set_uv(Vector2(u, v + 0.10))
	tool.add_vertex(c)
	tool.set_uv(Vector2(u + 0.055, v + 0.10))
	tool.add_vertex(b)
	tool.set_uv(Vector2(u, v))
	tool.add_vertex(a)
	tool.set_uv(Vector2(u + 0.055, v + 0.10))
	tool.add_vertex(b)
	tool.set_uv(Vector2(u + 0.055, v))
	tool.add_vertex(d)


func _build_fins() -> void:
	var length := body_length
	_add_fin("DorsalFin", PackedVector3Array([
		Vector3(-0.005, 0.090, -0.135) * length,
		Vector3(0.0, 0.165, 0.035) * length,
		Vector3(0.006, 0.085, 0.200) * length,
	]))
	_add_fin("AdiposeFin", PackedVector3Array([
		Vector3(-0.004, 0.055, 0.270) * length,
		Vector3(0.0, 0.078, 0.330) * length,
		Vector3(0.004, 0.045, 0.382) * length,
	]))
	_left_pectoral = _add_fin("LeftPectoralFin", PackedVector3Array([
		Vector3(-0.102, -0.005, -0.185) * length,
		Vector3(-0.194, -0.045, -0.035) * length,
		Vector3(-0.076, -0.036, 0.060) * length,
	]))
	_right_pectoral = _add_fin("RightPectoralFin", PackedVector3Array([
		Vector3(0.102, -0.005, -0.185) * length,
		Vector3(0.076, -0.036, 0.060) * length,
		Vector3(0.194, -0.045, -0.035) * length,
	]))
	_add_fin("LeftPelvicFin", PackedVector3Array([
		Vector3(-0.072, -0.060, 0.030) * length,
		Vector3(-0.125, -0.135, 0.115) * length,
		Vector3(-0.038, -0.080, 0.165) * length,
	]))
	_add_fin("RightPelvicFin", PackedVector3Array([
		Vector3(0.072, -0.060, 0.030) * length,
		Vector3(0.038, -0.080, 0.165) * length,
		Vector3(0.125, -0.135, 0.115) * length,
	]))
	_add_fin("AnalFin", PackedVector3Array([
		Vector3(-0.006, -0.074, 0.175) * length,
		Vector3(0.0, -0.145, 0.280) * length,
		Vector3(0.006, -0.066, 0.345) * length,
	]))
	_tail = Node3D.new()
	_tail.name = "CaudalTail"
	_tail.position = Vector3(0.0, 0.0, body_length * 0.150)
	_caudal_peduncle.add_child(_tail)
	_add_tail_fin(PackedVector3Array([
		Vector3(0.0, 0.0, 0.0),
		Vector3(-0.022, 0.135, 0.188) * length,
		Vector3(-0.008, 0.012, 0.115) * length,
	]))
	_add_tail_fin(PackedVector3Array([
		Vector3(0.0, 0.0, 0.0),
		Vector3(-0.008, -0.012, 0.115) * length,
		Vector3(-0.022, -0.135, 0.188) * length,
	]))


func _add_fin(fin_name: String, points: PackedVector3Array, parent: Node3D = null) -> Node3D:
	var fin_pivot := Node3D.new()
	fin_pivot.name = fin_name
	var fin := MeshInstance3D.new()
	fin.name = "%sSurface" % fin_name
	fin.mesh = _double_sided_triangle(points)
	fin.material_override = MAT_FIN
	fin_pivot.add_child(fin)
	var target_parent := parent if parent != null else self
	target_parent.add_child(fin_pivot)
	return fin_pivot


func _add_tail_fin(points: PackedVector3Array) -> void:
	var fin := MeshInstance3D.new()
	fin.name = "TailLobe"
	fin.mesh = _double_sided_triangle(points)
	fin.material_override = MAT_FIN
	_tail.add_child(fin)


func _double_sided_triangle(points: PackedVector3Array) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.add_vertex(points[0])
	tool.add_vertex(points[1])
	tool.add_vertex(points[2])
	tool.add_vertex(points[0])
	tool.add_vertex(points[2])
	tool.add_vertex(points[1])
	tool.generate_normals()
	return tool.commit()


func _build_eyes() -> void:
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = body_length * 0.012
		eye_mesh.height = body_length * 0.024
		eye_mesh.radial_segments = 10
		eye_mesh.rings = 5
		eye.name = "Eye"
		eye.mesh = eye_mesh
		eye.material_override = MAT_EYE
		eye.position = Vector3(float(side) * body_length * 0.078,
				body_length * 0.035, -body_length * 0.355)
		add_child(eye)


func _build_head_details() -> void:
	for side in [-1.0, 1.0]:
		var plate := MeshInstance3D.new()
		var plate_mesh := SphereMesh.new()
		plate_mesh.radius = body_length * 0.045
		plate_mesh.height = body_length * 0.010
		plate_mesh.radial_segments = 10
		plate_mesh.rings = 4
		plate.name = "LeftGillPlate" if side < 0.0 else "RightGillPlate"
		plate.mesh = plate_mesh
		plate.material_override = _body_material()
		plate.position = Vector3(float(side) * body_length * 0.112, body_length * 0.020,
				-body_length * 0.255)
		plate.rotation.z = float(side) * PI * 0.5
		add_child(plate)

	var mouth := MeshInstance3D.new()
	var mouth_mesh := CapsuleMesh.new()
	mouth_mesh.radius = body_length * 0.010
	mouth_mesh.height = body_length * 0.090
	mouth_mesh.radial_segments = 8
	mouth_mesh.rings = 2
	mouth.name = "Mouth"
	mouth.mesh = mouth_mesh
	mouth.material_override = MAT_EYE
	mouth.position = Vector3(0.0, -body_length * 0.010, -body_length * 0.520)
	mouth.rotation.z = PI * 0.5
	add_child(mouth)


func _build_species_markings() -> void:
	match species:
		Species.RAINBOW_TROUT:
			_add_rainbow_stripes()
		Species.BROWN_TROUT:
			_add_brown_spots()
		Species.MOUNTAIN_WHITEFISH:
			_add_whitefish_sail()


func _add_rainbow_stripes() -> void:
	for side in [-1.0, 1.0]:
		var stripe := MeshInstance3D.new()
		var stripe_mesh := CapsuleMesh.new()
		stripe_mesh.radius = body_length * 0.013
		stripe_mesh.height = body_length * 0.57
		stripe_mesh.radial_segments = 8
		stripe_mesh.rings = 3
		stripe.name = "RoseFlankStripe"
		stripe.mesh = stripe_mesh
		stripe.material_override = MAT_RAINBOW_STRIPE
		stripe.position = Vector3(float(side) * body_length * 0.125, 0.0, -body_length * 0.04)
		stripe.rotation.x = PI * 0.5
		_mid_body.add_child(stripe)


func _add_brown_spots() -> void:
	var locations := [
		Vector3(-0.125, 0.045, -0.19), Vector3(-0.137, 0.048, 0.02),
		Vector3(-0.112, 0.058, 0.19), Vector3(0.125, 0.045, -0.12),
		Vector3(0.137, 0.050, 0.10), Vector3(0.104, 0.058, 0.23),
	]
	for i in locations.size():
		var spot := MeshInstance3D.new()
		var spot_mesh := SphereMesh.new()
		spot_mesh.radius = body_length * (0.014 if i % 2 == 0 else 0.011)
		spot_mesh.height = body_length * 0.012
		spot_mesh.radial_segments = 7
		spot_mesh.rings = 3
		spot.name = "RedHaloSpot" if i == 2 or i == 4 else "DarkSpot"
		spot.mesh = spot_mesh
		spot.material_override = MAT_RED_SPOT if i == 2 or i == 4 else MAT_BROWN_SPOT
		spot.position = (locations[i] as Vector3) * body_length
		_mid_body.add_child(spot)


func _add_whitefish_sail() -> void:
	_add_fin("WhitefishSailDorsal", PackedVector3Array([
		Vector3(-0.006, 0.09, -0.16) * body_length,
		Vector3(0.0, 0.165, -0.055) * body_length,
		Vector3(0.006, 0.08, 0.16) * body_length,
	]))
