extends Node

var difficulty: DifficultyConfig
var session_id: int = -1
var session_seed: int = 0
var session_start_hour: float = 6.0


func _ready() -> void:
	var tier_name := DatabaseManager.get_setting("active_difficulty_tier", "STANDARD")
	difficulty = DatabaseManager.load_difficulty(tier_name)

	var saved_hour := DatabaseManager.get_setting("session_start_hour", "6.0")
	session_start_hour = float(saved_hour)


func set_difficulty(tier: DifficultyConfig.Tier) -> void:
	difficulty = DatabaseManager.load_difficulty(DifficultyConfig.Tier.keys()[tier])
	DatabaseManager.set_setting("active_difficulty_tier", difficulty.tier_name())


func new_session(seed: int, start_hour: float, tier: DifficultyConfig.Tier) -> void:
	session_seed = seed
	session_start_hour = start_hour
	set_difficulty(tier)

	var scale := DatabaseManager.get_setting("time_scale_seconds_per_hour", "60.0")
	session_id = DatabaseManager.save_session(
		seed,
		start_hour,
		difficulty.tier_name(),
		float(scale)
	)

	TimeOfDay.set_start_hour(start_hour)

	DatabaseManager.set_setting("session_start_hour", str(start_hour))


func end_session() -> void:
	if session_id >= 0:
		DatabaseManager.end_session(session_id)
		session_id = -1
