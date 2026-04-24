class_name FishRenderer
extends Node2D

const _SpriteCatalog = preload("res://scripts/assets/sprite_catalog.gd")

# Top-down fish rendering.
# Fish face upstream (left, -x). Tail is downstream (+x).
# Body shape: tapered fusiform silhouette with dorsal ridge, pectoral fins,
# forked caudal fin, lateral line, and species-specific spots/markings.
# Opacity scales with tile depth and time-of-day light level.

# Body half-length and half-width per size class (SMALL=0, MEDIUM=1, LARGE=2)
# x = half-length (head to caudal peduncle), y = max half-width (behind pectorals)
const BODY_HALF: Array = [
	Vector2(11.0, 4.0),
	Vector2(17.0, 6.0),
	Vector2(26.0, 9.0),
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
const SPRITE_TARGET_LENGTH: Array = [34.0, 48.0, 68.0]

# Regions are hand-selected top-down swim frames. Atlas fish face upward; drawing rotates
# them -90 degrees so they match the existing upstream-left gameplay orientation.
const SPRITE_REGIONS: Array = [
	[
		Rect2i(82, 122, 92, 296),
		Rect2i(282, 124, 92, 298),
		Rect2i(492, 124, 94, 294),
		Rect2i(692, 130, 98, 292),
	],
	[
		Rect2i(48, 82, 72, 206),
		Rect2i(180, 84, 72, 210),
		Rect2i(318, 84, 72, 206),
		Rect2i(452, 88, 78, 204),
	],
	[
		Rect2i(80, 126, 108, 300),
		Rect2i(280, 126, 108, 304),
		Rect2i(490, 126, 108, 300),
		Rect2i(690, 132, 110, 294),
	],
]

var _species: int = 0
var _size_class: int = 0
var _river_data: RiverData = null
var _section_start_px: float = 0.0

var _display_state: int = 0
var _intrusion_memory: float = 0.0

var _body_len: float = 17.0   # half-length
var _body_wid: float = 6.0    # max half-width
var _base_color: Color = Color.WHITE
var _variant_seed: int = 0
var _sprite_texture: Texture2D = null
var _sprite_regions: Array = []
var _sprite_anim_offset: int = 0


func initialize(species: int, size_class: int, seed: int, river_data: RiverData,
		section_start_px: float = 0.0) -> void:
	_species          = species
	_size_class       = size_class
	_variant_seed     = seed
	_river_data       = river_data
	_section_start_px = section_start_px

	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var hue_shift := rng.randf_range(-0.04, 0.04)

	var sz: Vector2 = BODY_HALF[size_class]
	_body_len = sz.x
	_body_wid = sz.y

	var hue: float = (BASE_HUE[species] as float) + hue_shift
	var sat: float = BASE_SAT[species] as float
	var val: float = BASE_VAL[species] as float
	_base_color = Color.from_hsv(fmod(hue, 1.0), sat, val)
	_sprite_texture = _load_species_texture(species)
	_sprite_regions = SPRITE_REGIONS[species] as Array if species < SPRITE_REGIONS.size() else []
	_sprite_anim_offset = absi(seed) % maxi(_sprite_regions.size(), 1)


func update(display_state: int, intrusion_memory: float) -> void:
	_display_state    = display_state
	_intrusion_memory = intrusion_memory
	queue_redraw()


func _draw() -> void:
	var opacity  := _compute_opacity()
	var body_col := _base_color

	# Telegraph tint: shifts toward red as intrusion memory builds
	var telegraph: float = GameManager.difficulty.fish_telegraph_strength
	if telegraph > 0.0 and _intrusion_memory > 0.0:
		var t := clampf(_intrusion_memory * 0.25, 0.0, 1.0) * telegraph
		body_col = body_col.lerp(Color(0.88, 0.15, 0.12), t)

	# State tint
	if _display_state == 1:   # ALERT
		body_col = body_col.lerp(Color(1.0, 0.82, 0.1), 0.30 * telegraph)
	elif _display_state == 2 or _display_state == 3:   # SPOOKED / RELOCATING
		body_col = body_col.lerp(Color(1.0, 0.05, 0.05), 0.45 * telegraph)

	body_col.a = opacity

	if _draw_sprite_fish(opacity):
		_draw_state_label()
		return

	var shadow_col := Color(0.0, 0.0, 0.0, opacity * 0.28)
	var fin_col    := Color(body_col.r * 0.80, body_col.g * 0.80, body_col.b * 0.75, opacity * 0.88)
	var belly_col  := Color(
		body_col.r * 1.0 + 0.14,
		body_col.g * 1.0 + 0.10,
		body_col.b * 1.0 + 0.06,
		opacity * 0.70
	)

	var L  := _body_len
	var W  := _body_wid

	# -------------------------------------------------------------------
	# 1. Drop shadow (offset slightly down-right)
	# -------------------------------------------------------------------
	var shadow_pts := _body_polygon(L, W, 1.5, 1.8)
	draw_colored_polygon(shadow_pts, shadow_col)

	# -------------------------------------------------------------------
	# 2. Caudal (tail) fin — forked, downstream (+x) end
	#    Two lobes fanning out from the caudal peduncle
	# -------------------------------------------------------------------
	var ped_x := L * 0.72         # caudal peduncle start
	var fork_x := L + W * 1.10   # fork tip x
	var lobe_y := W * 1.20        # lobe spread

	draw_colored_polygon(PackedVector2Array([
		Vector2(ped_x,  W * 0.18),
		Vector2(ped_x, -W * 0.18),
		Vector2(fork_x, -lobe_y),
		Vector2(fork_x, -lobe_y * 0.40),
	]), fin_col)
	draw_colored_polygon(PackedVector2Array([
		Vector2(ped_x, -W * 0.18),
		Vector2(ped_x,  W * 0.18),
		Vector2(fork_x,  lobe_y),
		Vector2(fork_x,  lobe_y * 0.40),
	]), fin_col)

	# -------------------------------------------------------------------
	# 3. Main body — fusiform top-down silhouette
	# -------------------------------------------------------------------
	var body_pts := _body_polygon(L, W)
	draw_colored_polygon(body_pts, body_col)

	# -------------------------------------------------------------------
	# 4. Belly highlight — lighter central strip along the body centreline
	# -------------------------------------------------------------------
	var belly_pts := _body_polygon(L * 0.88, W * 0.44)
	draw_colored_polygon(belly_pts, belly_col)

	# -------------------------------------------------------------------
	# 5. Pectoral fins — flare out just behind the head on each side
	# -------------------------------------------------------------------
	var pec_x_root := -L * 0.38   # attachment point (behind head)
	var pec_x_tip  := -L * 0.08
	var pec_y_root := W * 0.62
	var pec_y_tip  := W * 1.30

	# Top (negative y in our coord) pectoral
	draw_colored_polygon(PackedVector2Array([
		Vector2(pec_x_root, -pec_y_root),
		Vector2(pec_x_tip,  -pec_y_tip),
		Vector2(pec_x_tip + L * 0.24, -pec_y_root * 0.55),
	]), fin_col)
	# Bottom pectoral
	draw_colored_polygon(PackedVector2Array([
		Vector2(pec_x_root, pec_y_root),
		Vector2(pec_x_tip,  pec_y_tip),
		Vector2(pec_x_tip + L * 0.24, pec_y_root * 0.55),
	]), fin_col)

	# -------------------------------------------------------------------
	# 6. Dorsal fin ridge — narrow dark strip along the back centreline
	# -------------------------------------------------------------------
	var dors_col := Color(body_col.r * 0.55, body_col.g * 0.55, body_col.b * 0.50, opacity * 0.75)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-L * 0.20,  W * 0.14),
		Vector2(-L * 0.20, -W * 0.14),
		Vector2( L * 0.50, -W * 0.10),
		Vector2( L * 0.50,  W * 0.10),
	]), dors_col)

	# -------------------------------------------------------------------
	# 7. Lateral line — thin dashed stroke along mid-body
	# -------------------------------------------------------------------
	var ll_col := Color(body_col.r * 0.60, body_col.g * 0.65, body_col.b * 0.70, opacity * 0.60)
	var dash_len := maxf(2.5, L * 0.09)
	var gap_len  := dash_len * 0.8
	var lx: float = -L * 0.70
	while lx < L * 0.65:
		draw_line(Vector2(lx, 0.0), Vector2(lx + dash_len, 0.0), ll_col, 0.8)
		lx += dash_len + gap_len

	# -------------------------------------------------------------------
	# 8. Species-specific markings
	# -------------------------------------------------------------------
	_draw_markings(opacity)

	# -------------------------------------------------------------------
	# 9. Eye — upper-left of head, marks facing direction clearly
	# -------------------------------------------------------------------
	var eye_x := -L * 0.72
	var eye_y := -W * 0.42
	var eye_r  := maxf(W * 0.28, 1.5)
	draw_circle(Vector2(eye_x, eye_y), eye_r, Color(0.06, 0.06, 0.06, opacity))
	draw_circle(Vector2(eye_x + eye_r * 0.28, eye_y - eye_r * 0.28),
		eye_r * 0.32, Color(0.85, 0.85, 0.85, opacity * 0.70))   # iris highlight

	_draw_state_label()


# Build the fusiform body outline as a PackedVector2Array.
# offset_x / offset_y allow a cheap shadow by translating.
func _body_polygon(half_len: float, half_wid: float,
		offset_x: float = 0.0, offset_y: float = 0.0) -> PackedVector2Array:
	# Parameterised by t in [-1, 1]: t=-1 = tail end (+x), t=1 = head (-x).
	# Width profile: grows from 0 at tail, peaks around t=0.35 (shoulder), tapers to snout.
	var pts := PackedVector2Array()
	const STEPS := 24
	# Top edge: t from -1 (tail/+x) to +1 (head/-x)
	for i in (STEPS + 1):
		var t := -1.0 + float(i) / float(STEPS) * 2.0
		var w := _body_width_at(t, half_len, half_wid)
		pts.append(Vector2(-t * half_len + offset_x, -w + offset_y))
	# Bottom edge: t from +1 back to -1
	for i in (STEPS + 1):
		var t := 1.0 - float(i) / float(STEPS) * 2.0
		var w := _body_width_at(t, half_len, half_wid)
		pts.append(Vector2(-t * half_len + offset_x, w + offset_y))
	return pts


# Returns half-width at normalised body position t ∈ [-1, 1].
# t = -1 → tail (+x), t = 0 → mid-body, t = 1 → snout (-x).
func _body_width_at(t: float, _half_len: float, half_wid: float) -> float:
	# Clamp-safe: tail tapers to 0, head tapers more steeply
	var tail_side  := clampf((t + 1.0) * 0.5, 0.0, 1.0)   # 0 at tail, 1 at head
	var head_side  := clampf((1.0 - t) * 0.5, 0.0, 1.0)   # 0 at head, 1 at tail
	# Shoulder peak near t = 0.25 (just behind head)
	var shoulder   := pow(clampf(tail_side, 0.0, 1.0), 0.55)
	var taper      := pow(clampf(head_side, 0.0, 1.0), 0.40)
	return half_wid * shoulder * taper


# Draw species-specific spots / markings
func _draw_markings(opacity: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _variant_seed ^ 0xF15B
	var L := _body_len
	var W := _body_wid

	match _species:
		0:  # Brown Trout — red and black spots
			var spot_count := 6 + _size_class * 3
			for _i in spot_count:
				var sx := rng.randf_range(-L * 0.60, L * 0.55)
				var sy := rng.randf_range(-W * 0.75, W * 0.75)
				var sr := rng.randf_range(W * 0.12, W * 0.26)
				# Only draw if inside body silhouette
				var tw := _body_width_at(-sx / L, L, W)
				if absf(sy) > tw * 1.05:
					continue
				var is_red := rng.randf() > 0.55
				var sc: Color
				if is_red:
					sc = Color(0.82, 0.18, 0.08, opacity * 0.72)
				else:
					sc = Color(0.10, 0.08, 0.06, opacity * 0.65)
				draw_circle(Vector2(sx, sy), sr, sc)
				# Pale halo around red spots
				if is_red:
					draw_arc(Vector2(sx, sy), sr + 0.8, 0.0, TAU, 8,
						Color(0.90, 0.80, 0.55, opacity * 0.35), 0.7)

		1:  # Rainbow Trout — pink lateral band + small dark spots
			# Pink iridescent mid-body stripe
			var stripe_col := Color(0.90, 0.40, 0.55, opacity * 0.38)
			draw_colored_polygon(PackedVector2Array([
				Vector2(-L * 0.65, -W * 0.22),
				Vector2(-L * 0.65,  W * 0.22),
				Vector2( L * 0.58,  W * 0.16),
				Vector2( L * 0.58, -W * 0.16),
			]), stripe_col)
			# Small dark spots scattered above and below stripe
			var spot_count := 8 + _size_class * 4
			for _i in spot_count:
				var sx := rng.randf_range(-L * 0.55, L * 0.50)
				var sy := rng.randf_range(-W * 0.80, W * 0.80)
				var sr := rng.randf_range(W * 0.08, W * 0.18)
				var tw := _body_width_at(-sx / L, L, W)
				if absf(sy) > tw * 1.05:
					continue
				draw_circle(Vector2(sx, sy), sr,
					Color(0.12, 0.12, 0.14, opacity * 0.60))

		2:  # Mountain Whitefish — plain silver, faint scale shimmer
			var shimmer_col := Color(0.92, 0.92, 0.88, opacity * 0.18)
			var scale_rows := 3
			for row in scale_rows:
				var row_y := (float(row) / float(scale_rows) - 0.5) * W * 1.20
				var step := L * 0.22
				var x := -L * 0.55 + rng.randf() * step * 0.5
				while x < L * 0.50:
					var tw := _body_width_at(-x / L, L, W)
					if absf(row_y) < tw:
						draw_arc(Vector2(x, row_y), W * 0.14, 0.0, PI,
							5, shimmer_col, 0.6)
					x += step


func _draw_state_label() -> void:
	if not OS.is_debug_build():
		return
	var font  := ThemeDB.fallback_font
	var label := STATE_NAMES[_display_state] as String
	var col: Color = STATE_LABEL_COLORS[_display_state]
	draw_string(font, Vector2(-18.0, -_body_wid - 10.0), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 9, col)

	if _intrusion_memory > 0.0:
		var mem := "mem:%.0f" % _intrusion_memory
		draw_string(font, Vector2(-12.0, -_body_wid - 1.0), mem,
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
			_:                             depth_factor = 0.82

	var light_factor := 0.28 + TimeOfDay.light_level * 0.72
	return clampf(depth_factor * light_factor, 0.12, 1.0)


func _draw_sprite_fish(opacity: float) -> bool:
	if _sprite_texture == null or _sprite_regions.is_empty():
		return false

	var frame_idx := (int(Time.get_ticks_msec() / 220) + _sprite_anim_offset) % _sprite_regions.size()
	var region := _sprite_regions[frame_idx] as Rect2i
	var target_length := SPRITE_TARGET_LENGTH[_size_class] as float
	var scale := target_length / float(region.size.y)
	var draw_size := Vector2(float(region.size.x), float(region.size.y))
	var draw_rect := Rect2(-draw_size * 0.5, draw_size)

	draw_set_transform(Vector2(1.8, 2.2), -PI * 0.5, Vector2(scale, scale))
	draw_texture_rect_region(
			_sprite_texture,
			draw_rect,
			region,
			Color(0.0, 0.0, 0.0, opacity * 0.25)
	)

	draw_set_transform(Vector2.ZERO, -PI * 0.5, Vector2(scale, scale))
	draw_texture_rect_region(
			_sprite_texture,
			draw_rect,
			region,
			_sprite_modulate(opacity)
	)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	return true


func _sprite_modulate(opacity: float) -> Color:
	var telegraph: float = GameManager.difficulty.fish_telegraph_strength
	var modulate := Color(1.0, 1.0, 1.0, opacity)

	if telegraph > 0.0 and _intrusion_memory > 0.0:
		var t := clampf(_intrusion_memory * 0.25, 0.0, 1.0) * telegraph
		modulate = modulate.lerp(Color(1.0, 0.50, 0.44, opacity), t)

	if _display_state == 1:
		modulate = modulate.lerp(Color(1.0, 0.92, 0.45, opacity), 0.30 * telegraph)
	elif _display_state == 2 or _display_state == 3:
		modulate = modulate.lerp(Color(1.0, 0.42, 0.36, opacity), 0.45 * telegraph)

	modulate.a = opacity
	return modulate


func _load_species_texture(species: int) -> Texture2D:
	var path := _SpriteCatalog.FISH_BY_SPECIES.get(species, "") as String
	if path.is_empty():
		return null
	return load(path) as Texture2D
