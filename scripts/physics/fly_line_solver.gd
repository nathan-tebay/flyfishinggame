class_name FlyLineSolver
extends RefCounted

## Fixed-step XPBD chain. Particle 0 follows the physical rod tip; all remaining
## particles carry positive mass. The fly is the last particle, never a target.
const CONFIG_PATH := "res://scripts/physics/fly_line_config_v1.json"

var config: Dictionary = {}
var positions: PackedVector3Array = PackedVector3Array()
var velocities: PackedVector3Array = PackedVector3Array()
var masses: PackedFloat32Array = PackedFloat32Array()
var tags: PackedStringArray = PackedStringArray()
var rest_lengths: PackedFloat32Array = PackedFloat32Array()
var contact_state: PackedByteArray = PackedByteArray()
var rod_tip_position := Vector3.ZERO
var rod_tip_velocity := Vector3.ZERO
var rod_tip_acceleration := Vector3.ZERO
var elapsed_steps := 0
var fixture_seed := 0
var first_contact_step := -1
var previous_positions := PackedVector3Array()
var max_stretch_error := 0.0
var attachment_error := 0.0
var contact_height := -INF
var contact_restitution := 0.0
var contact_friction := 0.18
var _previous_tip_velocity := Vector3.ZERO


func _init() -> void:
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	assert(file != null, "Missing fly line configuration")
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert(parsed is Dictionary and int(parsed.get("schema_version", 0)) == 1)
	config = parsed


func reset(tip: Vector3, direction: Vector3 = Vector3.FORWARD, seed: int = 0) -> void:
	var axis := direction.normalized()
	if axis.length_squared() < 0.5:
		axis = Vector3.FORWARD
	positions = PackedVector3Array([tip])
	velocities = PackedVector3Array([Vector3.ZERO])
	masses = PackedFloat32Array([0.0])
	tags = PackedStringArray(["rod_tip"])
	rest_lengths = PackedFloat32Array()
	contact_state = PackedByteArray([0])
	var line_count := int(config["line_segments"])
	var line_step := float(config["line_length_m"]) / float(line_count)
	for i in range(line_count):
		var density := _line_density((float(i) + 0.5) / float(line_count))
		_append_particle(line_step, density * line_step, "fly_line", axis)
	var total_line_mass := 0.0
	for i in range(1, line_count + 1):
		total_line_mass += masses[i]
	assert(absf(total_line_mass - float(config["line_total_mass_kg"])) < 0.000001)
	var leader_count := int(config["leader_segments"])
	var leader_step := float(config["leader_length_m"]) / float(leader_count)
	for i in range(leader_count):
		_append_particle(leader_step, float(config["leader_kg_per_m"]) * leader_step,
				"leader", axis)
	_append_particle(0.0, float(config["fly_mass_kg"]), "fly", axis)
	previous_positions = positions.duplicate()
	fixture_seed = seed
	first_contact_step = -1
	rod_tip_position = tip
	rod_tip_velocity = Vector3.ZERO
	rod_tip_acceleration = Vector3.ZERO
	_previous_tip_velocity = Vector3.ZERO
	elapsed_steps = 0
	max_stretch_error = 0.0
	attachment_error = 0.0


func _append_particle(length: float, mass: float, tag: String, axis: Vector3) -> void:
	positions.append(positions[-1] + axis * length)
	velocities.append(Vector3.ZERO)
	masses.append(mass)
	tags.append(tag)
	rest_lengths.append(length)
	contact_state.append(0)


func _line_density(fraction: float) -> float:
	var taper: Array = config["line_taper"]
	for i in range(taper.size() - 1):
		var a: Dictionary = taper[i]
		var b: Dictionary = taper[i + 1]
		if fraction <= float(b["at"]):
			var weight := (fraction - float(a["at"])) / (float(b["at"]) - float(a["at"]))
			return lerpf(float(a["kg_per_m"]), float(b["kg_per_m"]), weight)
	return float(taper[-1]["kg_per_m"])


func step_fixed(tip: Vector3, wind: Vector3 = Vector3.ZERO) -> void:
	_step_fixed(tip, wind, 1.0 / float(config["solver_hz"]))


func _step_fixed(tip: Vector3, wind: Vector3, dt: float) -> void:
	assert(positions.size() > 1, "Call reset before stepping")
	var old := positions.duplicate()
	previous_positions = old
	rod_tip_velocity = (tip - rod_tip_position) / dt
	rod_tip_acceleration = (rod_tip_velocity - _previous_tip_velocity) / dt
	_previous_tip_velocity = rod_tip_velocity
	rod_tip_position = tip
	positions[0] = tip
	velocities[0] = rod_tip_velocity
	var drag := _drag_accelerations(wind)
	for i in range(1, positions.size()):
		velocities[i] += (Vector3.DOWN * float(config["gravity_m_per_s2"]) + drag[i]) * dt
		positions[i] += velocities[i] * dt
	var lambdas := PackedFloat32Array()
	lambdas.resize(rest_lengths.size())
	var alpha := float(config["stretch_compliance"]) / (dt * dt)
	for iteration in range(int(config["solver_iterations"])):
		positions[0] = tip
		for j in range(rest_lengths.size()):
			var offset := positions[j + 1] - positions[j]
			var distance := offset.length()
			if distance < 0.000001:
				continue
			var c := distance - rest_lengths[j]
			var inv_a := 0.0 if j == 0 else 1.0 / masses[j]
			var inv_b := 1.0 / masses[j + 1]
			var delta_lambda := (-c - alpha * lambdas[j]) / (inv_a + inv_b + alpha)
			lambdas[j] += delta_lambda
			var correction := offset / distance * delta_lambda
			if j > 0:
				positions[j] -= correction * inv_a
			positions[j + 1] += correction * inv_b
		_apply_contact()
	max_stretch_error = 0.0
	for j in range(rest_lengths.size()):
		max_stretch_error = maxf(max_stretch_error,
				absf(positions[j].distance_to(positions[j + 1]) - rest_lengths[j]))
	attachment_error = positions[0].distance_to(tip)
	for i in range(1, positions.size()):
		velocities[i] = (positions[i] - old[i]) / dt
		if contact_state[i] != 0 and velocities[i].y < 0.0:
			velocities[i].y *= -contact_restitution
			velocities[i].x *= 1.0 - contact_friction
			velocities[i].z *= 1.0 - contact_friction
	elapsed_steps += 1


func _drag_accelerations(wind: Vector3) -> PackedVector3Array:
	var result := PackedVector3Array()
	result.resize(positions.size())
	for j in range(rest_lengths.size()):
		var tangent := (positions[j + 1] - positions[j]).normalized()
		var relative := (velocities[j] + velocities[j + 1]) * 0.5 - wind
		var parallel := tangent * relative.dot(tangent)
		var perpendicular := relative - parallel
		var is_leader := j >= int(config["line_segments"])
		var parallel_drag := float(config["leader_drag_parallel"]) if is_leader else float(config["drag_parallel"])
		var transverse_drag := float(config["leader_drag_perpendicular"]) if is_leader else float(config["drag_perpendicular"])
		var force := (-parallel * parallel_drag - perpendicular * transverse_drag) * rest_lengths[j]
		for index in [j, j + 1]:
			if index > 0:
				result[index] += force * 0.5 / masses[index]
	return result


func _apply_contact() -> void:
	for i in range(1, positions.size()):
		contact_state[i] = 0
		if positions[i].y <= contact_height:
			positions[i].y = contact_height
			contact_state[i] = 1
			if first_contact_step < 0:
				first_contact_step = elapsed_steps + 1


func momentum_partitions() -> Dictionary:
	var line := Vector3.ZERO
	var leader := Vector3.ZERO
	var fly := Vector3.ZERO
	for i in range(1, positions.size()):
		var momentum := velocities[i] * masses[i]
		match tags[i]:
			"fly_line": line += momentum
			"leader": leader += momentum
			"fly": fly += momentum
	return {"fly_line": line, "leader": leader, "fly": fly,
			"total": line + leader + fly}


func snapshot() -> Dictionary:
	return {"schema_version": 1, "fixture_seed": fixture_seed, "step": elapsed_steps,
			"time_seconds": float(elapsed_steps) / float(config["solver_hz"]),
			"positions": positions.duplicate(), "previous_positions": previous_positions.duplicate(),
			"velocities": velocities.duplicate(), "masses": masses.duplicate(),
			"tags": tags.duplicate(), "rest_lengths": rest_lengths.duplicate(),
			"contact_state": contact_state.duplicate(), "first_contact_step": first_contact_step,
			"rod_tip_position": rod_tip_position,
			"rod_tip_velocity": rod_tip_velocity, "rod_tip_acceleration": rod_tip_acceleration,
			"max_stretch_error": max_stretch_error, "attachment_error": attachment_error,
			"momentum": momentum_partitions()}


func inspect() -> String:
	var p := momentum_partitions()
	return "step=%d tip=%s particles=%d stretch=%.5f attachment=%.5f P(line/leader/fly)=%s/%s/%s" % [
		elapsed_steps, rod_tip_position, positions.size(), max_stretch_error,
		attachment_error, p["fly_line"], p["leader"], p["fly"]]
