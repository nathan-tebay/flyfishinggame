class_name SessionConfig
extends Node2D

## Session configuration screen — shown at startup before entering RiverWorld.
## Tab to cycle fields, ←/→ to change value, number keys to type seed, Enter to start.

const HOURS: Array        = [4.0, 5.0, 6.0, 7.0, 8.0, 10.0, 14.0, 17.0, 18.0, 20.0]
const HOUR_LABELS: Array  = ["4am","5am","6am","7am","8am","10am","2pm","5pm","6pm","8pm"]
const TIME_SCALES: Array  = [60.0, 120.0, 300.0, 600.0]
const SCALE_LABELS: Array = ["1 min/hr","2 min/hr","5 min/hr","10 min/hr"]
const TIER_LABELS: Array  = ["Arcade", "Standard", "Sim"]
const TIER_DESCS: Array   = [
	"Wide strike window · 18 fish/section · visual aids on",
	"Balanced challenge — recommended starting point",
	"Tight windows · 7 fish · no overlays · wrong species adds intrusion",
]

var _seed_str: String = "12345"
var _hour_idx: int    = 2    # default: 6am
var _tier_idx: int    = 1    # default: Standard
var _scale_idx: int   = 0    # default: 60 sec/hr

# 0=seed 1=start_hour 2=difficulty 3=time_scale
var _focused: int = 0


func _ready() -> void:
	_seed_str = DatabaseManager.get_setting("last_seed", "12345")
	var tier_name := DatabaseManager.get_setting("active_difficulty_tier", "STANDARD")
	var tier_names: Array = ["ARCADE", "STANDARD", "SIM"]
	_tier_idx = tier_names.find(tier_name)
	if _tier_idx < 0:
		_tier_idx = 1


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and (event as InputEventKey).pressed):
		return
	var key := (event as InputEventKey).physical_keycode
	match key:
		KEY_TAB:
			_focused = (_focused + 1) % 4
		KEY_ENTER, KEY_KP_ENTER:
			_start_session()
			return
		KEY_LEFT:
			_shift_field(-1)
		KEY_RIGHT:
			_shift_field(1)
		KEY_BACKSPACE:
			if _focused == 0 and _seed_str.length() > 1:
				_seed_str = _seed_str.left(_seed_str.length() - 1)
			elif _focused == 0:
				_seed_str = "0"
		_:
			if _focused == 0:
				var digit := key - KEY_0
				if digit >= 0 and digit <= 9 and _seed_str.length() < 10:
					if _seed_str == "0":
						_seed_str = str(digit)
					else:
						_seed_str += str(digit)
	queue_redraw()


func _shift_field(dir: int) -> void:
	match _focused:
		1: _hour_idx  = (_hour_idx  + dir + HOURS.size())  % HOURS.size()
		2: _tier_idx  = (_tier_idx  + dir + 3)             % 3
		3: _scale_idx = (_scale_idx + dir + TIME_SCALES.size()) % TIME_SCALES.size()


func _start_session() -> void:
	var seed       := int(_seed_str) if _seed_str.is_valid_int() else 12345
	var start_hour : float = HOURS[_hour_idx]
	var tier       : DifficultyConfig.Tier = _tier_idx as DifficultyConfig.Tier
	var time_scale : float = TIME_SCALES[_scale_idx]

	DatabaseManager.set_setting("last_seed", str(seed))
	DatabaseManager.set_setting("time_scale_seconds_per_hour", str(time_scale))
	TimeOfDay.set_time_scale(time_scale)

	GameManager.new_session(seed, start_hour, tier)
	get_tree().change_scene_to_file("res://scenes/RiverWorld.tscn")


func _draw() -> void:
	var vp   := get_viewport_rect().size
	var cx   := vp.x * 0.5
	var font := ThemeDB.fallback_font

	# Background
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.05, 0.09, 0.16))

	# Title
	draw_string(font, Vector2(cx - 300.0, 110.0),
		"MADISON RIVER  ·  FLY FISHING",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 36, Color(0.88, 0.78, 0.50))
	draw_string(font, Vector2(cx - 90.0, 150.0),
		"Session Setup",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.55, 0.70, 0.88))

	# Field rows
	var fields: Array = [
		["Seed",        _seed_str],
		["Start Time",  HOUR_LABELS[_hour_idx]],
		["Difficulty",  TIER_LABELS[_tier_idx]],
		["Time Scale",  SCALE_LABELS[_scale_idx]],
	]

	var row_y := 240.0
	for i in fields.size():
		var field: Array  = fields[i]
		var label: String = field[0]
		var value: String = field[1]
		var focused       := i == _focused

		if focused:
			draw_rect(Rect2(cx - 320.0, row_y - 24.0, 640.0, 40.0),
				Color(0.14, 0.22, 0.38, 0.85))

		var lcol := Color(0.75, 0.85, 0.95) if focused else Color(0.45, 0.55, 0.68)
		var vcol := Color(1.00, 0.94, 0.65) if focused else Color(0.78, 0.88, 0.96)

		draw_string(font, Vector2(cx - 300.0, row_y),
			label, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, lcol)
		draw_string(font, Vector2(cx + 50.0, row_y),
			value, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, vcol)

		if focused and i > 0:
			draw_string(font, Vector2(cx + 20.0, row_y), "<",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.60, 0.72, 0.90))
			draw_string(font, Vector2(cx + 220.0, row_y), ">",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.60, 0.72, 0.90))

		row_y += 60.0

	# Difficulty description
	draw_string(font, Vector2(cx - 300.0, row_y + 16.0),
		TIER_DESCS[_tier_idx] as String,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.52, 0.68, 0.52))

	# Controls hint
	draw_string(font, Vector2(cx - 300.0, row_y + 52.0),
		"Tab — next field     ←/→ — change value     0-9 — type seed     Enter — start",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.42, 0.50, 0.60))
