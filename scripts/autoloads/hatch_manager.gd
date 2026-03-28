extends Node

# Mother's Day Caddis hatch state machine.
# Drives insect profile availability for FlyMatcher and NetSampler.
# Visual insect particles are spawned by RiverWorld in response to hatch_state_changed.

enum HatchState { NO_HATCH, PRE_HATCH, EMERGER, PEAK_HATCH, SPINNER_FALL }

signal hatch_state_changed(state: int)

var current_state: int = -1   # sentinel; forces profile build on first _update_state()
# active_profiles: Array of Dictionaries
#   { species, stage, size, depth_layer, abundance, movement, color }
var active_profiles: Array = []


func _ready() -> void:
	TimeOfDay.period_changed.connect(_on_period_changed)
	_update_state()


func _on_period_changed(_period: int) -> void:
	_update_state()


func _update_state() -> void:
	var new_state: int = _period_to_hatch_state(TimeOfDay.current_period)
	if new_state == current_state:
		return
	current_state  = new_state
	active_profiles = _build_profiles(current_state)
	hatch_state_changed.emit(current_state)
	if OS.is_debug_build():
		print("HatchManager: %s | %d active profile(s)" % [
			hatch_state_name(), active_profiles.size()
		])


func _period_to_hatch_state(period: int) -> int:
	match period:
		TimeOfDay.Period.DAWN:      return HatchState.NO_HATCH
		TimeOfDay.Period.MORNING:   return HatchState.PRE_HATCH
		TimeOfDay.Period.MIDDAY:    return HatchState.EMERGER
		TimeOfDay.Period.AFTERNOON: return HatchState.PEAK_HATCH
		TimeOfDay.Period.DUSK:      return HatchState.SPINNER_FALL
		_:                          return HatchState.NO_HATCH  # NIGHT


func _build_profiles(state: int) -> Array:
	match state:
		HatchState.NO_HATCH:
			return [_p("caddis", "nymph",   "small",  "bottom",  0.30,
					   "drift",   Color(0.32, 0.28, 0.12))]
		HatchState.PRE_HATCH:
			return [
				_p("caddis", "nymph", "small",  "bottom", 0.60,
				   "drift", Color(0.32, 0.28, 0.12)),
				_p("caddis", "pupa",  "medium", "mid",    0.50,
				   "drift", Color(0.42, 0.35, 0.16)),
			]
		HatchState.EMERGER:
			return [
				_p("caddis", "pupa",    "medium", "mid",     0.70,
				   "drift", Color(0.42, 0.35, 0.16)),
				_p("caddis", "emerger", "medium", "surface", 0.45,
				   "drift", Color(0.52, 0.42, 0.18)),
			]
		HatchState.PEAK_HATCH:
			return [_p("caddis", "adult",   "medium", "surface", 0.90,
					   "skitter", Color(0.62, 0.50, 0.22))]
		HatchState.SPINNER_FALL:
			return [_p("caddis", "spinner", "medium", "surface", 0.70,
					   "drift",   Color(0.55, 0.40, 0.18))]
		_:
			return []


func _p(species: String, stage: String, size: String,
		depth_layer: String, abundance: float,
		movement: String, color: Color) -> Dictionary:
	return {
		"species":     species,
		"stage":       stage,
		"size":        size,
		"depth_layer": depth_layer,
		"abundance":   abundance,
		"movement":    movement,
		"color":       color,
	}


func hatch_state_name() -> String:
	if current_state < 0 or current_state >= HatchState.size():
		return "No Hatch"
	return HatchState.keys()[current_state]
