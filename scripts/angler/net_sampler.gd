class_name NetSampler
extends Node

# Net sampling mechanic. The angler must stand still before sampling is possible;
# then pressing net_sample starts a countdown. Movement cancels it.
#
# Wired by RiverWorld:
#   angler.standing_still → on_standing_still()
#   sample_complete        → RiverWorld._on_sample_complete()

signal sample_complete(results: Array)

const SAMPLE_DURATION := 4.0   # seconds of stillness required

var angler: Angler = null
var river_data: RiverData = null

var _can_sample: bool  = false
var _sampling:   bool  = false
var _timer:      float = 0.0


func on_standing_still() -> void:
	_can_sample = true
	print("NetSampler: standing still — press N to sample")


func _process(delta: float) -> void:
	if angler == null:
		return

	if angler.is_moving:
		if _sampling:
			_cancel()
		_can_sample = false
		return

	if _sampling:
		_timer -= delta
		if _timer <= 0.0:
			_finish()
		return

	if _can_sample and Input.is_action_just_pressed("net_sample"):
		_start()


func _start() -> void:
	_sampling = true
	_timer    = SAMPLE_DURATION
	print("NetSampler: sampling... (%.0f s)" % SAMPLE_DURATION)


func _cancel() -> void:
	_sampling = false
	_timer    = 0.0
	print("NetSampler: cancelled — must stand still")


func _finish() -> void:
	_sampling   = false
	_can_sample = false   # must stand still again for next sample
	var results: Array = _compute_results()
	print("NetSampler: complete — %d insect type(s)" % results.size())
	for entry in results:
		var e: Dictionary = entry
		print("  %s %s @ %s: %.0f%%" % [
			e["stage"], e["species"], e["depth_layer"], e["abundance"] * 100.0
		])
	sample_complete.emit(results)


func _compute_results() -> Array:
	var results: Array = []
	var profiles: Array = HatchManager.active_profiles

	if profiles.is_empty():
		results.append({
			"species":     "caddis",
			"stage":       "nymph",
			"depth_layer": "bottom",
			"abundance":   0.20,
		})
		return results

	for p in profiles:
		var pdict: Dictionary = p
		var abundance: float  = pdict["abundance"]
		abundance = _apply_structure_bonus(abundance)
		results.append({
			"species":     pdict["species"],
			"stage":       pdict["stage"],
			"depth_layer": pdict["depth_layer"],
			"abundance":   clampf(abundance, 0.0, 1.0),
		})

	return results


func _apply_structure_bonus(base: float) -> float:
	if river_data == null or angler == null:
		return base

	var col := clampi(
		int(angler.position.x / RiverConstants.TILE_SIZE),
		0, river_data.width - 1
	)
	var bonus := 0.0

	for s in river_data.structures:
		var sdict: Dictionary = s
		var sx: int = sdict["x"]
		if abs(sx - col) < 5:
			var stype: int = sdict["type"]
			var hw: float = RiverConstants.STRUCTURE_HATCH.get(stype, 0.0) as float
			bonus += hw * 0.25

	return base + minf(bonus, 0.40)


# Returns 0.0..1.0 progress through current sample (0 if not sampling)
func sample_progress() -> float:
	if not _sampling:
		return 0.0
	return 1.0 - (_timer / SAMPLE_DURATION)
