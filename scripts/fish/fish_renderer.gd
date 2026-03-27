class_name FishRenderer
extends Node2D

# Procedural placeholder fish rendering.
# Body color and size vary by species and variant seed.
# Opacity scales with tile depth and time-of-day light level.
# State debug label shown above the fish.

# Body half-dimensions [width, height] per size class (SMALL=0, MEDIUM=1, LARGE=2)
const BODY_HALF: Array = [
	Vector2(10.0, 4.5),
	Vector2(16.0, 6.5),
	Vector2(24.0, 9.5),
]

# Base hue / saturation / value per species (BROWN_TROUT=0, RAINBOW=1, WHITEFISH=2)
const BASE_HUE: Array = [0.07, 0.55, 0.15]
const BASE_SAT: Array = [0.65, 0.35, 0.20]
const BASE_VAL: Array = [0.65, 0.80, 0.75]

# Debug state label colors (indexed by FishAI.State int value)
const STATE_LABEL_COLORS: Array = [
	Color(0.30, 0.90, 0.30),   # FEEDING
	Color(1.00, 0.82, 0.10),   # ALERT
	Color(0.92, 0.15, 0.10),   # SPOOKED
	Color(0.92, 0.15, 0.10),   # RELOCATING
	Color(0.70, 0.40, 0.85),   # HOLDING
]

const STATE_NAMES: Array = ["FEEDING", "ALERT", "SPOOKED", "RELOCATING", "HOLDING"]

var _species: int = 0
var _size_class: int = 0
var _river_data: RiverData = null
var _section_start_px: float = 0.0

var _display_state: int = 0
var _intrusion_memory: float = 0.0

var _body_w: float = 16.0
var _body_h: float = 6.5
var _base_color: Color = Color.WHITE


func initialize(species: int, size_class: int, seed: int, river_data: RiverData,
		section_start_px: float = 0.0) -> void:
	_species          = species
	_size_class       = size_class
	_river_data       = river_data
	_section_start_px = section_start_px

	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var hue_shift := rng.randf_range(-0.04, 0.04)

	var sz: Vector2 = BODY_HALF[size_class]
	_body_w = sz.x
	_body_h = sz.y

	var hue: float = (BASE_HUE[species] as float) + hue_shift
	var sat: float = BASE_SAT[species] as float
	var val: float = BASE_VAL[species] as float
	_base_color = Color.from_hsv(fmod(hue, 1.0), sat, val)


func update(display_state: int, intrusion_memory: float) -> void:
	_display_state   = display_state
	_intrusion_memory = intrusion_memory
	queue_redraw()


func _draw() -> void:
	var opacity := _compute_opacity()
	var body_col := _base_color

	# Telegraph tint: color shifts toward red as intrusion memory builds
	var telegraph: float = GameManager.difficulty.fish_telegraph_strength
	if telegraph > 0.0 and _intrusion_memory > 0.0:
		var t := clampf(_intrusion_memory * 0.25, 0.0, 1.0) * telegraph
		body_col = body_col.lerp(Color(0.88, 0.15, 0.12), t)

	# State tint
	if _display_state == 1:   # ALERT
		body_col = body_col.lerp(Color(1.0, 0.82, 0.1), 0.30 * telegraph)
	elif _display_state == 2 or _display_state == 3:  # SPOOKED / RELOCATING
		body_col = body_col.lerp(Color(1.0, 0.05, 0.05), 0.45 * telegraph)

	body_col.a = opacity

	# Body ellipse (12 points)
	var pts := PackedVector2Array()
	for i in 12:
		var a := float(i) / 12.0 * TAU
		pts.append(Vector2(cos(a) * _body_w, sin(a) * _body_h))
	draw_colored_polygon(pts, body_col)

	# Tail fin pointing downstream (+x = right, fish face left)
	var tail_col := Color(body_col.r, body_col.g, body_col.b, opacity * 0.82)
	draw_colored_polygon(PackedVector2Array([
		Vector2(_body_w * 0.65, 0.0),
		Vector2(_body_w + 7.0, -_body_h * 0.80),
		Vector2(_body_w + 7.0,  _body_h * 0.80),
	]), tail_col)

	_draw_state_label()


func _draw_state_label() -> void:
	var font  := ThemeDB.fallback_font
	var label := STATE_NAMES[_display_state] as String
	var col: Color = STATE_LABEL_COLORS[_display_state]
	draw_string(font, Vector2(-18.0, -_body_h - 10.0), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 9, col)

	if _intrusion_memory > 0.0:
		var mem := "mem:%.0f" % _intrusion_memory
		draw_string(font, Vector2(-12.0, -_body_h - 1.0), mem,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1.0, 0.60, 0.30))


func _compute_opacity() -> float:
	var depth_factor := 0.82
	if _river_data != null:
		var gp := global_position
		var tx := clampi(int((gp.x - _section_start_px) / RiverConstants.TILE_SIZE), 0, _river_data.width - 1)
		var ty := clampi(int(gp.y / RiverConstants.TILE_SIZE), 0, _river_data.height - 1)
		var tile: int = _river_data.tile_map[tx][ty]
		match tile:
			RiverConstants.TILE_SURFACE:   depth_factor = 0.92
			RiverConstants.TILE_MID_DEPTH: depth_factor = 0.76
			RiverConstants.TILE_DEEP:      depth_factor = 0.56
			RiverConstants.TILE_RIVERBED:  depth_factor = 0.38
			_:                             depth_factor = 0.82

	var light_factor := 0.28 + TimeOfDay.light_level * 0.72
	return clampf(depth_factor * light_factor, 0.12, 1.0)
