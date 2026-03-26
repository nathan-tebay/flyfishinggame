class_name SpookCalculator
extends RefCounted

# Central formula for all fish spook radius calculations.
# All spook checks in the game MUST route through here — never compute directly.
#
# Formula:
#   effective_radius = max(
#     base × size_mult × cover_mod × time_mod × approach_mod,   ← directional
#     vibration_radius × size_mult × speed_normalized            ← omnidirectional
#   )
#
# Fish always face upstream = Vector2(-1, 0) in world space.
# Approach angle is measured from the fish's tail (blind spot = 0°, head-on = 180°).

enum FishSize { SMALL, MEDIUM, LARGE }

const _SIZE_MULTIPLIERS := {
	FishSize.SMALL:  1.0,
	FishSize.MEDIUM: 1.3,
	FishSize.LARGE:  1.8,
}


# Returns the effective spook radius in world pixels.
# Phase 5 FishAI calls this each frame to check FEEDING → ALERT → SPOOKED.
#
#   fish_size               — FishSize enum (SMALL / MEDIUM / LARGE)
#   cover_value             — 0.0–1.0 from RiverConstants.STRUCTURE_COVER at fish tile
#   angler_pos              — world position of angler (feet reference point)
#   fish_pos                — world position of fish
#   is_wading               — whether angler is in the water
#   angler_speed_normalized — 0.0 = standing still, 1.0 = full-speed movement
static func calculate(
	config: DifficultyConfig,
	fish_size: int,
	cover_value: float,
	angler_pos: Vector2,
	fish_pos: Vector2,
	is_wading: bool,
	angler_speed_normalized: float
) -> float:
	var size_mult := _SIZE_MULTIPLIERS.get(fish_size, 1.0) as float
	var cover_mod := 1.0 - config.deep_cover_reduction * clampf(cover_value, 0.0, 1.0)
	var time_mod  := _time_modifier(config)
	var approach  := _approach_modifier(angler_pos, fish_pos, config)

	var directional_r := config.base_spook_radius * size_mult * cover_mod * time_mod * approach

	# Wading vibration — omnidirectional, does not use approach modifier.
	# This is what reduces blind spot advantage when wading quickly.
	var vibration_r := 0.0
	if is_wading and angler_speed_normalized > 0.0:
		vibration_r = config.wading_vibration_radius * size_mult * angler_speed_normalized

	return maxf(directional_r, vibration_r)


# Returns true if the angler is within the fish's spook radius.
static func is_within_radius(
	config: DifficultyConfig,
	fish_size: int,
	cover_value: float,
	angler_pos: Vector2,
	fish_pos: Vector2,
	is_wading: bool,
	angler_speed_normalized: float
) -> bool:
	var r := calculate(
		config, fish_size, cover_value,
		angler_pos, fish_pos,
		is_wading, angler_speed_normalized
	)
	return angler_pos.distance_to(fish_pos) <= r


# Returns the approach modifier alone (0.1 blind spot → 1.6 head-on).
# Used by FishVisionCone (Phase 5) and debug overlays.
static func approach_modifier(
	angler_pos: Vector2,
	fish_pos: Vector2,
	config: DifficultyConfig
) -> float:
	return _approach_modifier(angler_pos, fish_pos, config)


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

static func _time_modifier(config: DifficultyConfig) -> float:
	if TimeOfDay.is_feeding_window():
		return 1.0 - config.dawn_dusk_wariness_reduction
	return 1.0


# Approach angle modifier.
# Fish face upstream = (-1, 0). Blind spot is DOWNSTREAM (behind tail).
#
#   angle_from_tail 0°   = angler directly downstream (blind spot)   → 0.1
#   angle_from_tail 90°  = angler broadside                          → 1.0
#   angle_from_tail 180° = angler directly upstream (head-on)        → 1.6
static func _approach_modifier(
	angler_pos: Vector2,
	fish_pos: Vector2,
	config: DifficultyConfig
) -> float:
	if angler_pos.is_equal_approx(fish_pos):
		return 1.6  # worst case if overlapping

	var fish_facing   := Vector2(-1.0, 0.0)
	var dir_to_angler := (angler_pos - fish_pos).normalized()

	# dot = -1: angler downstream = blind spot (tail)
	# dot =  1: angler upstream   = head-on (mouth)
	var dot       := dir_to_angler.dot(fish_facing)
	var angle_deg := rad_to_deg(acos(clampf(-dot, -1.0, 1.0)))  # 0° blind spot, 180° head-on
	var blind_deg := config.blind_spot_half_angle

	if angle_deg < blind_deg:
		return 0.1
	elif angle_deg < 90.0:
		var t := (angle_deg - blind_deg) / (90.0 - blind_deg)
		return lerpf(0.1, 1.0, t)
	else:
		var t := (angle_deg - 90.0) / 90.0
		return lerpf(1.0, 1.6, t)
