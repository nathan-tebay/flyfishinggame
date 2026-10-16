extends SceneTree

const SOLVER = preload("res://scripts/physics/fly_line_solver.gd")
const OUTPUT := "res://docs/physics/candidate_trace_v1.json"


func _vectors(values: PackedVector3Array) -> Array:
	var result := []
	for v in values:
		result.append([v.x, v.y, v.z])
	return result


func _state(solver) -> Dictionary:
	var snap: Dictionary = solver.snapshot()
	var momentum: Dictionary = snap["momentum"]
	return {"step": snap["step"], "positions": _vectors(snap["positions"]),
		"velocities": _vectors(snap["velocities"]),
		"rod_tip_position": _vectors(PackedVector3Array([snap["rod_tip_position"]]))[0],
		"rod_tip_velocity": _vectors(PackedVector3Array([snap["rod_tip_velocity"]]))[0],
		"rod_tip_acceleration": _vectors(PackedVector3Array([snap["rod_tip_acceleration"]]))[0],
		"max_stretch_error": snap["max_stretch_error"],
		"attachment_error": snap["attachment_error"],
		"contact_state": Array(snap["contact_state"]),
		"momentum": {"fly_line": _vectors(PackedVector3Array([momentum["fly_line"]]))[0],
			"leader": _vectors(PackedVector3Array([momentum["leader"]]))[0],
			"fly": _vectors(PackedVector3Array([momentum["fly"]]))[0],
			"total": _vectors(PackedVector3Array([momentum["total"]]))[0]}}


func _initialize() -> void:
	var solver = SOLVER.new()
	solver.reset(Vector3(0.0, 3.0, 0.0))
	var trace := {"schema_version": 1, "fixture": "sinusoidal_rod_tip_180_steps",
		"dt": 1.0 / 120.0, "config": solver.config,
		"masses": Array(solver.masses), "tags": Array(solver.tags),
		"rest_lengths": Array(solver.rest_lengths), "samples": [_state(solver)]}
	for step in range(180):
		var time := float(step) / 120.0
		var tip := Vector3(0.4 * sin(time * 5.0), 3.0 + 0.2 * sin(time * 7.0),
				0.3 * cos(time * 5.0))
		solver.step_fixed(tip)
		if (step + 1) % 30 == 0:
			trace["samples"].append(_state(solver))
	var file := FileAccess.open(OUTPUT, FileAccess.WRITE)
	if file == null:
		printerr("physics_candidate_trace: failed to open output")
		quit(1)
		return
	file.store_string(JSON.stringify(trace, "  ") + "\n")
	file.close()
	print("physics_candidate_trace: wrote %s (%d samples)" % [OUTPUT, trace["samples"].size()])
	quit(0)
