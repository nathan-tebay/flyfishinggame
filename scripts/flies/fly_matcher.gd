class_name FlyMatcher
extends RefCounted

# Weighted closeness scoring between active fly and current hatch insect profiles.
# All fly matching routes through here — never compute take probability elsewhere.

const TAKE_EXACT         := 0.85
const TAKE_CLOSE         := 0.55
const TAKE_GENERIC       := 0.18   # same species, neutral stage
const TAKE_WRONG_STAGE   := 0.06
const TAKE_WRONG_SPECIES := 0.02

const INTRUSION_WRONG_STAGE := 0.5   # +0.5 intrusion memory per wrong-stage presentation


# Returns { "take_probability": float, "intrusion_delta": float }
static func evaluate(fly_name: String, fly_stage: String,
					  difficulty: DifficultyConfig) -> Dictionary:
	var profiles: Array = HatchManager.active_profiles
	if profiles.is_empty():
		# No hatch — attractor baseline, no intrusion
		return { "take_probability": TAKE_GENERIC, "intrusion_delta": 0.0 }

	var best_take:      float = 0.0
	var best_intrusion: float = 0.0

	for p in profiles:
		var pdict: Dictionary = p
		var result: Dictionary = _score(fly_name, fly_stage, pdict, difficulty)
		var tp: float = result["take_probability"]
		if tp > best_take:
			best_take      = tp
			best_intrusion = result["intrusion_delta"]

	return { "take_probability": best_take, "intrusion_delta": best_intrusion }


static func _score(fly_name: String, fly_stage: String,
				   profile: Dictionary, difficulty: DifficultyConfig) -> Dictionary:
	var p_species: String = profile["species"]
	var p_stage:   String = profile["stage"]
	var fly_species: String = _fly_to_species(fly_name)

	if fly_species != p_species:
		return {
			"take_probability": TAKE_WRONG_SPECIES,
			"intrusion_delta":  difficulty.wrong_species_intrusion_delta,
		}

	# Same species — score by stage closeness
	var stage_score: int = _stage_closeness(fly_stage, p_stage)
	match stage_score:
		2:   return { "take_probability": TAKE_EXACT,       "intrusion_delta": 0.0 }
		1:   return { "take_probability": TAKE_CLOSE,       "intrusion_delta": 0.0 }
		0:   return { "take_probability": TAKE_GENERIC,     "intrusion_delta": 0.0 }
		_:   return { "take_probability": TAKE_WRONG_STAGE, "intrusion_delta": INTRUSION_WRONG_STAGE }


static func _fly_to_species(fly_name: String) -> String:
	if "Caddis" in fly_name or "caddis" in fly_name:
		return "caddis"
	return "unknown"


# Returns: 2 = exact, 1 = close, 0 = generic/neutral, -1 = wrong stage
static func _stage_closeness(fly_stage: String, insect_stage: String) -> int:
	match fly_stage:
		"dry":
			match insect_stage:
				"adult":   return 2   # EHC vs adult caddis — exact match
				"spinner": return 1   # EHC works on spinner falls
				"emerger": return 1   # EHC in the film — close
				"pupa":    return -1  # wrong stage — subsurface insect
				"nymph":   return -1  # wrong stage
		"emerger":
			match insect_stage:
				"pupa":    return 2   # Caddis Pupa vs pupa — exact
				"emerger": return 2   # Caddis Pupa vs film emerger — exact
				"nymph":   return 1   # subsurface works for nymphs
				"adult":   return -1  # wrong stage — dry needed
				"spinner": return -1  # wrong stage
	return 0  # unknown fly stage — treat as generic attractor
