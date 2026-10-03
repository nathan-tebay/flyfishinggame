extends SceneTree

const SOLVER = preload("res://scripts/physics/fly_line_solver.gd")
const ROD = preload("res://scripts/player/fly_rod_3d.gd")
const VIEW = preload("res://scripts/debug/fly_line_debug_view.gd")


func _fail(message: String) -> void:
	printerr("physics_foundation_check: FAIL - %s" % message)
	quit(1)


func _initialize() -> void:
	var solver = SOLVER.new()
	solver.reset(Vector3(0.0, 3.0, 0.0))
	var initial := solver.snapshot()
	if initial["positions"].size() != 45 or initial["tags"][-1] != "fly":
		_fail("expected 36 line, 7 leader, and 1 fly segments")
		return
	var line_length := 0.0
	var leader_length := 0.0
	for i in range(initial["rest_lengths"].size()):
		var length: float = initial["rest_lengths"][i]
		if i < 36:
			line_length += length
		else:
			leader_length += length
		if initial["masses"][i + 1] <= 0.0:
			_fail("nonpositive moving mass")
			return
	if absf(line_length - 18.0) > 0.0001 or absf(leader_length - 2.45) > 0.0001:
		_fail("line or leader rest length changed")
		return
	if initial["masses"][8] <= initial["masses"][36]:
		_fail("fly line taper does not reduce toward leader")
		return
	var trace: Array[Dictionary] = []
	for run in range(2):
		solver.reset(Vector3(0.0, 3.0, 0.0))
		for step in range(180):
			var time := float(step) / 120.0
			var tip := Vector3(0.4 * sin(time * 5.0), 3.0 + 0.2 * sin(time * 7.0),
					0.3 * cos(time * 5.0))
			solver.step_fixed(tip)
		var state: Dictionary = solver.snapshot()
		if run == 0:
			trace.append(state)
		elif state["positions"] != trace[0]["positions"] or state["velocities"] != trace[0]["velocities"]:
			_fail("same tip sequence produced different state")
			return
		if state["attachment_error"] > 0.000001 or state["max_stretch_error"] > 0.12:
			_fail("attachment or stretch bound exceeded")
			return
		for position in state["positions"]:
			if not is_finite(position.x) or not is_finite(position.y) or not is_finite(position.z):
				_fail("nonfinite position")
				return
		var partition: Dictionary = state["momentum"]
		if (partition["fly_line"] + partition["leader"] + partition["fly"] - partition["total"]).length() > 0.000001:
			_fail("momentum partitions do not sum")
			return
	solver.reset(Vector3(0.0, 3.0, 0.0), Vector3.FORWARD, 23)
	solver.contact_height = 2.0
	for step in range(200):
		solver.step_fixed(Vector3(0.0, 3.0, 0.0))
	if solver.first_contact_step < 0 or solver.snapshot()["fixture_seed"] != 23:
		_fail("contact or deterministic fixture metadata missing")
		return
	solver.contact_height = -INF
	var rod = ROD.new()
	root.add_child(rod)
	await process_frame
	rod.play_cast("roll")
	rod.set_line_tension(3.0)
	var curve: PackedVector3Array = rod.centerline()
	var frames: Array[Basis] = rod.transport_frames()
	if curve[-1].distance_to(rod.to_local(rod.tip_global_position())) > 0.000001:
		_fail("physical tip differs from rendered centerline")
		return
	var arc := 0.0
	for i in range(1, curve.size()):
		arc += curve[i].distance_to(curve[i - 1])
		if frames[i].x.dot(frames[i - 1].x) < 0.95:
			_fail("parallel transport frame flipped")
			return
	if absf(arc - 2.74) > 0.0001:
		_fail("rod arc length is not 2.74 m")
		return
	var debug_view = VIEW.new()
	root.add_child(debug_view)
	debug_view.bind_solver(solver)
	await process_frame
	if not (debug_view.get_child(0) as Label).text.contains("particles=45"):
		_fail("debug view did not expose particle state")
		return
	for style in ["back", "forward", "roll", "overhead"]:
		for frame_index in range(12):
			rod.sample_stroke(style, float(frame_index) * 0.05, 4.0)
			curve = rod.centerline()
			frames = rod.transport_frames()
			if curve[-1].distance_to(rod.to_local(rod.tip_global_position())) > 0.000001:
				_fail("tip diverged during stroke")
				return
			for i in range(1, frames.size()):
				if frames[i].x.dot(frames[i - 1].x) < 0.95:
					_fail("frame flipped during stroke")
					return
	print("physics_foundation_check: PASS (%s)" % solver.inspect())
	quit(0)
