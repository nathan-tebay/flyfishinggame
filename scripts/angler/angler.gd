class_name Angler
extends Node2D

const _SpriteCatalog = preload("res://scripts/assets/sprite_catalog.gd")

# Player-controlled angler. Handles bank/wading movement, vibration radius,
# and standing-still detection. Shadow cone visibility driven by DifficultyConfig.


# Movement speeds (pixels per second)
const BANK_SPEED      := 120.0
const WADE_SPEED_H    :=  60.0   # horizontal, slower in water
const WADE_SPEED_V    :=  40.0   # entering / exiting water

# Y positions in world space (TileMap starts at world y = 0)
const BANK_Y          := (RiverConstants.BANK_H_TILES - 0.5) * RiverConstants.TILE_SIZE  # 80.0
const WADE_ENTRY_Y    := RiverConstants.BANK_H_TILES * RiverConstants.TILE_SIZE           # 96
const MAX_WADE_DEPTH  := 10  # tiles below surface — shallow fords (≤10 tiles) are crossable

const STILL_THRESHOLD := 3.0  # seconds motionless before signal
const ANIM_IDLE := &"idle"
const ANIM_CAST_OVERHEAD := &"cast_overhead"
const CAST_FPS := 12.0
const MOVE_FPS := 6.0
const ANGLER_SCENE_SCALE := 0.67
const MOVING_RENDER_HEIGHT := 64.0
const MOVING_VISIBLE_HEIGHT := 64.0
const MOVING_FRAME_SIZE := Vector2i(64, 64)
const DIRECTION_ROWS := {
	"north": 0,
	"south": 1,
	"west": 2,
	"east": 3,
}
const TERRAIN_COLUMNS := {
	"land": [0, 1, 2, 3],
	"shallow": [4, 5, 6, 7],
	"mid": [8, 9, 10, 11],
}

signal standing_still

var is_wading: bool = false
var wading_depth: float = 0.0      # 0.0 = at surface, 1.0 = max wading depth
var vibration_radius: float = 0.0  # read by SpookCalculator; 0 when still or on bank
var casting_active: bool = false   # set by RiverWorld; blocks movement during casting

var river_data: RiverData          # assigned by RiverWorld; updated on section crossing
var section_start_x: float = 0.0  # world x of the current section's left edge

var _still_timer: float = 0.0
var _was_still: bool = false
var is_moving: bool = false   # public — read by FishAI for SpookCalculator
var _movement_input := Vector2.ZERO
var _last_facing := "south"
var _visual_locked_by_cast := false

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	position = Vector2(240.0, BANK_Y)
	z_index = 5   # render above all bank/river overlays (max renderer z_index = 2)
	_setup_cast_sprite()
	_refresh_shadow_visibility()


func _process(delta: float) -> void:
	is_moving = _handle_movement(delta)
	_sync_wading_state()
	_snap_to_bank_surface()
	_sync_vibration()
	_tick_still_timer(delta)
	_update_movement_animation()
	if _sprite == null or _sprite.sprite_frames == null:
		queue_redraw()


func play_cast_overhead() -> void:
	if _sprite == null or _sprite.sprite_frames == null:
		return
	_visual_locked_by_cast = true
	_sprite.scale = Vector2.ONE * ANGLER_SCENE_SCALE
	_sprite.position = Vector2(0.0, _sprite_anchor_y(_SpriteCatalog.ANGLER_CAST_FRAME_SIZE.y))
	_sprite.play(ANIM_CAST_OVERHEAD)


func reset_visual_state() -> void:
	_visual_locked_by_cast = false
	if _sprite == null or _sprite.sprite_frames == null:
		queue_redraw()
		return
	_update_movement_animation(true)


func _setup_cast_sprite() -> void:
	if _sprite == null:
		return

	var cast_texture := load(_SpriteCatalog.ANGLER_CAST_OVERHEAD) as Texture2D
	var moving_texture := load(_SpriteCatalog.ANGLER_MOVING_TRANSPARENT) as Texture2D
	if cast_texture == null and moving_texture == null:
		push_warning("Angler cast sprite texture could not be loaded.")
		_sprite.visible = false
		return

	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	if moving_texture != null:
		_add_movement_animations(frames, moving_texture)
	else:
		push_warning("Angler moving sprite texture could not be loaded; using cast ready frame for idle.")
		frames.add_animation(ANIM_IDLE)
		frames.set_animation_loop(ANIM_IDLE, true)
		frames.set_animation_speed(ANIM_IDLE, 1.0)
		frames.add_frame(ANIM_IDLE, _atlas_frame(cast_texture, 0, _SpriteCatalog.ANGLER_CAST_FRAME_SIZE))

	if cast_texture != null:
		frames.add_animation(ANIM_CAST_OVERHEAD)
		frames.set_animation_loop(ANIM_CAST_OVERHEAD, false)
		frames.set_animation_speed(ANIM_CAST_OVERHEAD, CAST_FPS)
		for i in _SpriteCatalog.ANGLER_CAST_FRAMES:
			frames.add_frame(ANIM_CAST_OVERHEAD,
					_atlas_frame(cast_texture, i, _SpriteCatalog.ANGLER_CAST_FRAME_SIZE))

	_sprite.sprite_frames = frames
	_sprite.centered = true
	_update_movement_animation(true)


func _add_movement_animations(frames: SpriteFrames, texture: Texture2D) -> void:
	for terrain in TERRAIN_COLUMNS.keys():
		for direction in DIRECTION_ROWS.keys():
			var anim := _movement_anim_name(terrain as String, direction as String)
			frames.add_animation(anim)
			frames.set_animation_loop(anim, true)
			frames.set_animation_speed(anim, MOVE_FPS)
			for col in TERRAIN_COLUMNS[terrain]:
				frames.add_frame(anim, _moving_atlas_frame(
						texture,
						DIRECTION_ROWS[direction],
						col as int
				))

	frames.add_animation(ANIM_IDLE)
	frames.set_animation_loop(ANIM_IDLE, true)
	frames.set_animation_speed(ANIM_IDLE, 1.0)
	frames.add_frame(ANIM_IDLE, _moving_atlas_frame(
			texture,
			DIRECTION_ROWS["south"],
			(TERRAIN_COLUMNS["land"] as Array)[0] as int
	))


func _atlas_frame(texture: Texture2D, frame_index: int, frame_size: Vector2i) -> AtlasTexture:
	var frame := AtlasTexture.new()
	frame.atlas = texture
	frame.region = Rect2(
		float(frame_index * frame_size.x),
		0.0,
		float(frame_size.x),
		float(frame_size.y)
	)
	return frame


func _moving_atlas_frame(texture: Texture2D, row: int, col: int) -> AtlasTexture:
	var frame := AtlasTexture.new()
	frame.atlas = texture
	frame.region = Rect2(
		float(col * MOVING_FRAME_SIZE.x),
		float(row * MOVING_FRAME_SIZE.y),
		float(MOVING_FRAME_SIZE.x),
		float(MOVING_FRAME_SIZE.y)
	)
	return frame


func _update_movement_animation(force: bool = false) -> void:
	if _visual_locked_by_cast or _sprite == null or _sprite.sprite_frames == null:
		return

	if _movement_input != Vector2.ZERO:
		if absf(_movement_input.x) > absf(_movement_input.y):
			_last_facing = "east" if _movement_input.x > 0.0 else "west"
		else:
			_last_facing = "south" if _movement_input.y > 0.0 else "north"

	var terrain := "land"
	if is_wading:
		terrain = "mid" if wading_depth >= 0.55 else "shallow"

	var anim := _movement_anim_name(terrain, _last_facing)
	_sprite.scale = Vector2.ONE * _movement_sprite_scale()
	_sprite.position = Vector2(0.0, _sprite_anchor_y(MOVING_FRAME_SIZE.y))

	if force or _sprite.animation != anim:
		_sprite.play(anim)

	if is_moving:
		if not _sprite.is_playing():
			_sprite.play(anim)
	else:
		_sprite.stop()
		_sprite.frame = 0


func _movement_anim_name(terrain: String, direction: String) -> StringName:
	return StringName("%s_%s" % [terrain, direction])


func _sprite_anchor_y(frame_height: int) -> float:
	return -float(frame_height) * _sprite.scale.y * 0.5


func _movement_sprite_scale() -> float:
	return MOVING_RENDER_HEIGHT / MOVING_VISIBLE_HEIGHT


# ---------------------------------------------------------------------------
# Movement
# ---------------------------------------------------------------------------

func _handle_movement(delta: float) -> bool:
	if casting_active:
		_movement_input = Vector2.ZERO
		return false

	var dx := 0.0
	if Input.is_action_pressed("move_right"):
		dx = 1.0
	elif Input.is_action_pressed("move_left"):
		dx = -1.0

	var dy := 0.0
	if Input.is_action_pressed("move_down"):
		dy = 1.0
	elif Input.is_action_pressed("move_up"):
		dy = -1.0

	_movement_input = Vector2(dx, dy)

	# Horizontal — current slows wading; bank walking is always full speed
	if dx != 0.0:
		var spd: float
		if is_wading:
			# Faster current = more resistance. At current=0.95: ~18 px/s. At current=0.25: ~48 px/s.
			var current: float = _current_at_position()
			spd = WADE_SPEED_H * maxf(0.25, 1.0 - current * 0.80)
		else:
			spd = BANK_SPEED
		var new_x := maxf(position.x + dx * spd * delta, 0.0)

		# When on the far bank, only allow horizontal movement if the destination column
		# also has a bank tile at the current row. Prevents walking off the ford edge
		# into deep water, which causes a two-frame y-teleport through the river.
		var new_col := clampi(int((new_x - section_start_x) / RiverConstants.TILE_SIZE),
				0, river_data.width - 1)
		var cur_row := clampi(int(position.y / RiverConstants.TILE_SIZE),
				0, river_data.height - 1)
		var tile_ahead: int = river_data.tile_map[new_col][cur_row] \
				if river_data != null else RiverConstants.TILE_BANK
		var on_far_bank := not is_wading and _is_on_far_bank()
		if on_far_bank:
			# Far bank — only allow movement where a bank tile continues
			if tile_ahead == RiverConstants.TILE_BANK or tile_ahead == RiverConstants.TILE_AIR:
				position.x = new_x
		elif tile_ahead == RiverConstants.TILE_DEEP or tile_ahead == RiverConstants.TILE_BOULDER:
			# Impassable tile at current depth — block horizontal movement rather than teleporting
			pass
		else:
			position.x = new_x

	# Vertical — check the destination tile each step; block on TILE_DEEP / TILE_BOULDER.
	if dy > 0.0:
		if _is_on_far_bank():
			position.y = minf(position.y + BANK_SPEED * delta, _far_bank_bottom_y())
		else:
			var spd := WADE_SPEED_V if is_wading else BANK_SPEED
			var new_y := position.y + spd * delta
			if _tile_at_y(new_y) not in [RiverConstants.TILE_DEEP, RiverConstants.TILE_BOULDER, RiverConstants.TILE_AIR]:
				position.y = new_y
	elif dy < 0.0:
		if is_wading:
			var new_y := position.y - WADE_SPEED_V * delta
			if _tile_at_y(new_y) not in [RiverConstants.TILE_DEEP, RiverConstants.TILE_BOULDER]:
				position.y = new_y
		elif _is_on_far_bank():
			position.y -= BANK_SPEED * delta
		else:
			position.y = maxf(position.y - BANK_SPEED * delta, RiverConstants.TILE_SIZE * 0.5)

	return dx != 0.0 or dy != 0.0


# Tile type at the angler's current column and the given world y.
func _tile_at_y(world_y: float) -> int:
	if river_data == null:
		return RiverConstants.TILE_DEEP
	var col := clampi(int((position.x - section_start_x) / RiverConstants.TILE_SIZE),
			0, river_data.width - 1)
	var row := clampi(int(world_y / RiverConstants.TILE_SIZE), 0, river_data.height - 1)
	return river_data.tile_map[col][row]


# Maximum y the angler can reach in the current column.
# Only TILE_BANK (far bank) and TILE_BOULDER are impassable — everything else is wadable.
func _max_wade_y() -> float:
	if river_data == null:
		return BANK_Y + float(4 * RiverConstants.TILE_SIZE)

	var col := clampi(int((position.x - section_start_x) / RiverConstants.TILE_SIZE),
			0, river_data.width - 1)

	var water_start: int = RiverConstants.BANK_H_TILES
	if river_data.top_bank_profile.size() > col:
		water_start = river_data.top_bank_profile[col]

	for row in range(water_start, river_data.height):
		var t: int = river_data.tile_map[col][row]
		match t:
			RiverConstants.TILE_DEEP, RiverConstants.TILE_BOULDER:
				if row == water_start:
					return _near_bank_edge_y()
				return float(row - 1) * RiverConstants.TILE_SIZE + RiverConstants.TILE_SIZE * 0.5
			RiverConstants.TILE_BANK:
				return float(row) * RiverConstants.TILE_SIZE + RiverConstants.TILE_SIZE * 0.5

	# Fallback — should not be reached with a valid tile map
	return float(water_start + MAX_WADE_DEPTH) * RiverConstants.TILE_SIZE


# Y-position of the near-bank surface (bottom bank row, adjacent to water) at the angler's column.
# Varies as the river curves; the angler walks along this line automatically via snap.
func _near_bank_edge_y() -> float:
	if river_data == null:
		return BANK_Y
	var col := clampi(int((position.x - section_start_x) / RiverConstants.TILE_SIZE),
			0, river_data.width - 1)
	if river_data.top_bank_profile.size() > col:
		var tbh: int = river_data.top_bank_profile[col]
		return float(tbh - 1) * RiverConstants.TILE_SIZE + RiverConstants.TILE_SIZE * 0.5
	return BANK_Y


# ---------------------------------------------------------------------------
# State sync
# ---------------------------------------------------------------------------

func _sync_wading_state() -> void:
	# Tile-based: angler is wading whenever they are NOT on a TILE_BANK or TILE_AIR cell.
	# This correctly handles far-bank fishing — standing on the far bank = not wading.
	var current_tile := RiverConstants.TILE_BANK
	if river_data != null:
		var col := clampi(int((position.x - section_start_x) / RiverConstants.TILE_SIZE),
				0, river_data.width - 1)
		var row := clampi(int(position.y / RiverConstants.TILE_SIZE), 0, river_data.height - 1)
		current_tile = river_data.tile_map[col][row]
		is_wading = (current_tile != RiverConstants.TILE_BANK and current_tile != RiverConstants.TILE_AIR \
				and current_tile != RiverConstants.TILE_BOULDER)
	else:
		is_wading = position.y > BANK_Y + 1.0

	if is_wading:
		# Depth based on tile type — reflects actual water depth, not distance from bank.
		# TILE_SURFACE = shallow edges/riffles; TILE_MID_DEPTH = medium; TILE_DEEP = deep channel.
		match current_tile:
			RiverConstants.TILE_SURFACE:          wading_depth = 0.25
			RiverConstants.TILE_MID_DEPTH:        wading_depth = 0.60
			RiverConstants.TILE_DEEP:             wading_depth = 1.00
			RiverConstants.TILE_WEED_BED:         wading_depth = 0.30
			RiverConstants.TILE_GRAVEL_BAR:       wading_depth = 0.30
			RiverConstants.TILE_ROCK:             wading_depth = 0.50
			RiverConstants.TILE_BOULDER:          wading_depth = 0.55
			_:                                    wading_depth = 0.20
	else:
		wading_depth = 0.0


# Returns the current speed (0-1) at the angler's tile position. Zero when not wading.
func _current_at_position() -> float:
	if river_data == null or not is_wading:
		return 0.0
	var col := clampi(int((position.x - section_start_x) / RiverConstants.TILE_SIZE),
			0, river_data.width - 1)
	var row := clampi(int(position.y / RiverConstants.TILE_SIZE), 0, river_data.height - 1)
	return river_data.current_map[col][row]


# Keeps the angler within valid bank tile bounds as the river profile curves.
# Near bank: y stays between row 0 and the water edge. Far bank: y stays within
# the far bank tile rows. Does NOT pin to the water edge — the player can walk
# anywhere on the bank.
func _snap_to_bank_surface() -> void:
	if is_wading or river_data == null:
		return

	var col := clampi(int((position.x - section_start_x) / RiverConstants.TILE_SIZE),
			0, river_data.width - 1)

	var near_edge_y := _near_bank_edge_y()
	if _is_on_far_bank():
		# Far bank — clamp bottom (don't walk into air) and track curves
		# when walking horizontally. If the angler has moved ABOVE the far
		# bank top (pressing up toward water), don't pull them back.
		var fb_top := _far_bank_top_y()
		var fb_bot := _far_bank_bottom_y()
		if position.y >= fb_top:
			position.y = clampf(position.y, fb_top, fb_bot)
		else:
			position.y = minf(position.y, fb_bot)
	else:
		# Near bank — clamp top (don't walk above screen) and track curves
		# when walking horizontally. If the angler has moved PAST the bank
		# edge (pressing down toward water), don't pull them back — let
		# _sync_wading_state detect the water tile once they reach the next row.
		var top_y := RiverConstants.TILE_SIZE * 0.5
		if position.y <= near_edge_y:
			position.y = clampf(position.y, top_y, near_edge_y)
		else:
			position.y = maxf(position.y, top_y)


# True when the angler stands on far-bank tiles (below the river).
# Uses tile lookup — only true when the actual tile is BANK and row >= bottom_bank_profile.
func _is_on_far_bank() -> bool:
	if river_data == null:
		return false
	var col := clampi(int((position.x - section_start_x) / RiverConstants.TILE_SIZE),
			0, river_data.width - 1)
	if river_data.bottom_bank_profile.size() <= col:
		return false
	var fb_start: int = river_data.bottom_bank_profile[col]
	var row := clampi(int(position.y / RiverConstants.TILE_SIZE), 0, river_data.height - 1)
	return row >= fb_start and river_data.tile_map[col][row] == RiverConstants.TILE_BANK


# Y of the top-most far bank row centre (water-side edge) at the angler's column.
func _far_bank_top_y() -> float:
	if river_data == null:
		return position.y
	var col := clampi(int((position.x - section_start_x) / RiverConstants.TILE_SIZE),
			0, river_data.width - 1)
	if river_data.bottom_bank_profile.size() <= col:
		return position.y
	var fb_start: int = river_data.bottom_bank_profile[col]
	return float(fb_start) * RiverConstants.TILE_SIZE + RiverConstants.TILE_SIZE * 0.5


# Y of the bottom-most far bank row centre (air-side edge) at the angler's column.
# Scans downward from bottom_bank_profile until a non-BANK tile (AIR or end of map).
func _far_bank_bottom_y() -> float:
	if river_data == null:
		return position.y
	var col := clampi(int((position.x - section_start_x) / RiverConstants.TILE_SIZE),
			0, river_data.width - 1)
	if river_data.bottom_bank_profile.size() <= col:
		return position.y
	var fb_start: int = river_data.bottom_bank_profile[col]
	var last_bank_row: int = fb_start
	for row in range(fb_start, river_data.height):
		if river_data.tile_map[col][row] == RiverConstants.TILE_BANK:
			last_bank_row = row
		else:
			break
	return float(last_bank_row) * RiverConstants.TILE_SIZE + RiverConstants.TILE_SIZE * 0.5


func _sync_vibration() -> void:
	vibration_radius = GameManager.difficulty.wading_vibration_radius \
		if (is_wading and is_moving) else 0.0


# ---------------------------------------------------------------------------
# Standing-still detection
# ---------------------------------------------------------------------------

func _tick_still_timer(delta: float) -> void:
	if is_moving:
		_still_timer = 0.0
		_was_still = false
	else:
		_still_timer += delta
		if _still_timer >= STILL_THRESHOLD and not _was_still:
			_was_still = true
			standing_still.emit()


# ---------------------------------------------------------------------------
# Shadow cone visibility
# ---------------------------------------------------------------------------

func _refresh_shadow_visibility() -> void:
	var cone := get_node_or_null("ShadowCone") as ShadowCone
	if cone:
		cone.visible_to_player = GameManager.difficulty.show_shadow_cone


# ---------------------------------------------------------------------------
# Placeholder rendering
# ---------------------------------------------------------------------------

func _draw() -> void:
	if _sprite != null and _sprite.sprite_frames != null:
		return

	var body_color := Color(0.85, 0.55, 0.25)  # tan/khaki angler
	var leg_color  := Color(0.45, 0.32, 0.18)
	var head_color := Color(0.92, 0.78, 0.60)

	if is_wading:
		body_color = Color(0.42, 0.60, 0.80)  # blue waders
		leg_color  = Color(0.28, 0.42, 0.65)

	# Legs (feet at y=0)
	draw_rect(Rect2(-5.0, -14.0, 4.0, 14.0), leg_color)
	draw_rect(Rect2( 1.0, -14.0, 4.0, 14.0), leg_color)

	# Body
	draw_rect(Rect2(-7.0, -30.0, 14.0, 16.0), body_color)

	# Head
	draw_circle(Vector2(0.0, -34.0), 6.0, head_color)

	# Rod (thin line extending up-right from hand)
	draw_line(Vector2(6.0, -26.0), Vector2(22.0, -52.0), Color(0.55, 0.38, 0.20), 1.5)

	# Wading depth indicator — blue bar on left side
	if is_wading:
		var bar_h := wading_depth * 30.0
		draw_rect(Rect2(-14.0, -30.0, 4.0, bar_h), Color(0.30, 0.55, 0.95, 0.70))
