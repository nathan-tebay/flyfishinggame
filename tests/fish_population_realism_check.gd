extends SceneTree

const LowerMadisonReachScript = preload("res://scripts/river/lower_madison_reach.gd")
const River3DBuilderScript = preload("res://scripts/river/river_3d_builder.gd")

var failures: Array[String] = []


func _init() -> void:
	var builder := River3DBuilderScript.new()
	var reach := LowerMadisonReachScript.new()
	root.add_child(builder)
	builder.build(reach, 12345)
	_check_population(builder)
	_check_visual_depth(builder)
	builder.queue_free()
	if failures.is_empty():
		print("fish_population_realism_check: PASS (%d holding fish)" % builder.fish_hold_entries.size())
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _check_population(builder: Node) -> void:
	var entries: Array = builder.fish_hold_entries
	if entries.size() < 5:
		failures.append("Expected at least 5 holding fish in a single run; got %d." % entries.size())
	var species_seen := {}
	var small_seen := false
	var medium_seen := false
	var large_seen := false
	for entry in entries:
		var fish := entry as Dictionary
		species_seen[int(fish["species"])] = true
		var length := float(fish["length"])
		if length < 0.36:
			small_seen = true
		elif length < 0.54:
			medium_seen = true
		else:
			large_seen = true
		if float(fish["depth"]) < 0.50 and length >= 0.54:
			failures.append("Large fish %.2fm should not be assigned to shallow %.2fm water outside a strong hatch." % [length, float(fish["depth"])])
	if species_seen.size() < 2:
		failures.append("Expected mixed species in hold population; got %d species." % species_seen.size())
	if not (small_seen and medium_seen and large_seen):
		failures.append("Expected small, medium, and large fish classes across holds.")


func _check_visual_depth(builder: Node) -> void:
	var entries: Array = builder.fish_hold_entries
	var deep_checked := false
	for entry in entries:
		var fish := entry as Dictionary
		var length := float(fish["length"])
		var visual_length := float(fish.get("visual_length", length))
		if visual_length > length:
			failures.append("Visual fish length %.2fm should not exceed gameplay length %.2fm." % [visual_length, length])
		var depth := float(fish["depth"])
		var position := fish["position"] as Vector3
		var surface := LowerMadisonReachScript.WATER_HEIGHT
		if depth >= 0.62:
			deep_checked = true
			if position.y > surface - 0.36:
				failures.append("Deep-water fish should sit well below the surface; depth %.2fm y %.2f." % [depth, position.y])
	if not deep_checked:
		failures.append("Expected at least one deep-water fish to verify hidden/deep placement.")
