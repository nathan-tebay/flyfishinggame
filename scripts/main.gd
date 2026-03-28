extends Node2D


func _ready() -> void:
	if OS.is_debug_build():
		print("=== FlyFishingGame Started ===")
		print("Difficulty: ", GameManager.difficulty.tier_name())
		print("Time scale: %.0f s/hr  |  Start hour: %.1f" % [
			TimeOfDay.seconds_per_hour,
			TimeOfDay.current_hour,
		])
		print("Period: %s  |  Light: %.2f  |  Sun angle: %.1f°" % [
			TimeOfDay.period_name(),
			TimeOfDay.light_level,
			TimeOfDay.sun_angle,
		])

	TimeOfDay.period_changed.connect(_on_period_changed)
	TimeOfDay.dawn.connect(_on_dawn)

	# Start a test session so we can verify DB writes
	GameManager.new_session(12345, TimeOfDay.current_hour, GameManager.difficulty.tier)
	if OS.is_debug_build():
		print("Session ID: ", GameManager.session_id)


func _on_period_changed(period: TimeOfDay.Period) -> void:
	if OS.is_debug_build():
		print("[%s] Period → %s  |  Light: %.2f  |  Sun: %.1f°  |  Feeding window: %s" % [
			"%.1f" % TimeOfDay.current_hour,
			TimeOfDay.period_name(),
			TimeOfDay.light_level,
			TimeOfDay.sun_angle,
			str(TimeOfDay.is_feeding_window()),
		])


func _on_dawn() -> void:
	if OS.is_debug_build():
		print("*** DAWN — large fish lockdown resets ***")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		GameManager.end_session()
		DatabaseManager.close()
