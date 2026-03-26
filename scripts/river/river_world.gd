extends Node2D

const RC := RiverConstants

@onready var camera:     RiverCamera    = $Camera2D
@onready var tilemap:    RiverRenderer  = $TileMap
@onready var sky_strip:  ColorRect      = $SkyLayer/SkyStrip

var river_data: RiverData
var _show_debug := false


func _ready() -> void:
	# Ensure an active session exists (fall back to test seed if none started)
	if GameManager.session_id < 0:
		GameManager.new_session(12345, 6.0, DifficultyConfig.Tier.STANDARD)

	_generate_river()
	_update_sky()
	TimeOfDay.period_changed.connect(_on_period_changed)

	print("RiverWorld ready | seed=%d | top holds=%d | structures=%d" % [
		river_data.seed,
		river_data.top_holds.size(),
		river_data.structures.size(),
	])


func _input(event: InputEvent) -> void:
	# D key toggles hold-score debug overlay during development
	if event is InputEventKey and event.pressed:
		if event.physical_keycode == KEY_COMMA:
			_show_debug = not _show_debug
			if _show_debug:
				tilemap.show_hold_debug(river_data)
			else:
				tilemap.hide_hold_debug()


# ---------------------------------------------------------------------------
# River generation
# ---------------------------------------------------------------------------

func _generate_river() -> void:
	var generator := RiverGenerator.new()
	river_data     = generator.generate(GameManager.session_seed, GameManager.difficulty)
	tilemap.render(river_data)


# ---------------------------------------------------------------------------
# Sky strip — updates colour to match current time of day period
# ---------------------------------------------------------------------------

func _update_sky() -> void:
	var idx := int(TimeOfDay.current_period)
	sky_strip.color = RC.SKY_COLORS[idx]


func _on_period_changed(_period: int) -> void:
	_update_sky()
	print("Period: %s  light=%.2f  sun=%.1f°" % [
		TimeOfDay.period_name(),
		TimeOfDay.light_level,
		TimeOfDay.sun_angle,
	])
