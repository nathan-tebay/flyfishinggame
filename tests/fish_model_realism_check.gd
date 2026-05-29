extends SceneTree

const FishModel3D = preload("res://scripts/models/fish_model_3d.gd")

var failures: Array[String] = []

func _init() -> void:
	_run_checks()
	if failures.is_empty():
		print("fish_model_realism_check: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _run_checks() -> void:
	var model := FishModel3D.new()
	model.configure(FishModel3D.Species.RAINBOW_TROUT, 0.72, 0.0)
	root.add_child(model)
	model._ready()
	_check_required_anatomy(model)
	_check_animation_wave(model)


func _check_required_anatomy(model: Node3D) -> void:
	var required := [
		"MidBodySway",
		"CaudalPeduncle",
		"CaudalTail",
		"LeftPelvicFin",
		"RightPelvicFin",
		"AnalFin",
		"LeftGillPlate",
		"RightGillPlate",
		"Mouth"
	]
	for node_name in required:
		if model.find_child(node_name, true, false) == null:
			failures.append("Expected realistic fish anatomy node '%s' to exist." % node_name)

	var body := model.find_child("RainbowTroutBody", true, false) as MeshInstance3D
	if body == null or body.mesh == null:
		failures.append("Expected generated rainbow trout body mesh to exist.")
		return
	var arrays := body.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if vertices.size() < 540:
		failures.append("Expected smoother fish body mesh with at least 540 vertices; got %d." % vertices.size())


func _check_animation_wave(model: Node3D) -> void:
	var mid := model.find_child("MidBodySway", true, false) as Node3D
	var peduncle := model.find_child("CaudalPeduncle", true, false) as Node3D
	var tail := model.find_child("CaudalTail", true, false) as Node3D
	if mid == null or peduncle == null or tail == null:
		return
	model.animate_swim(1.25)
	var mid_y: float = abs(mid.rotation.y)
	var peduncle_y: float = abs(peduncle.rotation.y)
	var tail_y: float = abs(tail.rotation.y)
	if not (mid_y > 0.01 and peduncle_y > mid_y and tail_y > peduncle_y):
		failures.append("Expected swimming wave to increase from body to peduncle to tail; got %.4f, %.4f, %.4f." % [mid_y, peduncle_y, tail_y])
	if abs(model.rotation.z) <= 0.002:
		failures.append("Expected whole fish to roll subtly during swim animation.")
