class_name Angler
extends Node2D

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

signal standing_still

var is_wading: bool = false
var wading_depth: float = 0.0      # 0.0 = at surface, 1.0 = max wading depth
var vibration_radius: float = 0.0  # read by SpookCalculator; 0 when still or on bank

var river_data: RiverData          # assigned by RiverWorld; updated on section crossing
var section_start_x: float = 0.0  # world x of the current section's left edge

var _still_timer: float = 0.0
var _was_still: bool = false
var is_moving: bool = false   # public — read by FishAI for SpookCalculator


func _ready() -> void:
	position = Vector2(240.0, BANK_Y)
	_refresh_shadow_visibility()


func _process(delta: float) -> void:
	is_moving = _handle_movement(delta)
	_sync_wading_state()
	_snap_to_bank_surface()
	_sync_vibration()
	_tick_still_timer(delta)
	queue_redraw()


# ---------------------------------------------------------------------------
# Movement
# ---------------------------------------------------------------------------

func _handle_movement(delta: float) -> bool:
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

	# Horizontal — current slows wading; bank walking is always full speed
	if dx != 0.0:
		var spd: float
		if is_wading:
			# Faster current = more resistance. At current=0.95: ~18 px/s. At current=0.25: ~48 px/s.
			var current: float = _current_at_position()
			spd = WADE_SPEED_H * maxf(0.25, 1.0 - current * 0.80)
		else:
			spd = BANK_SPEED
		position.x = maxf(position.x + dx * spd * delta, 0.0)
		# After moving to a new column, clamp y to that column's wading limit.
		# Prevents drifting into TILE_AIR when walking from a deep section into a ford.
		position.y = minf(position.y, _max_wade_y())

	# Vertical — down enters/deepens in water; up exits water or re-enters from far bank.
	# Near bank surface position is managed by _snap_to_bank_surface, not the UP key.
	if dy > 0.0:
		position.y = minf(position.y + WADE_SPEED_V * delta, _max_wade_y())
	elif dy < 0.0:
		var ne_y := _near_bank_edge_y()
		if is_wading:
			# Exiting water toward near bank — cap at near bank edge
			position.y = maxf(position.y - WADE_SPEED_V * delta, ne_y)
		elif position.y > ne_y + RiverConstants.TILE_SIZE * 2.0:
			# On far bank — move freely upward to re-enter water
			position.y -= WADE_SPEED_V * delta

	return dx != 0.0 or dy != 0.0


# Maximum y the angler can reach in the current column.
# Scans tile-by-tile from the near bank downward:
#   TILE_DEEP → angler stops at the last passable row above it (dark blue = not wadable)
#   TILE_RIVERBED without TILE_DEEP → ford/shallow crossing, angler can reach far bank
#   TILE_BANK (far bank) → crossable, land on it
# Fords always lack TILE_DEEP (depth_val ≤ 0.35 generates no deep tiles), so they are
# always fully crossable. Weed beds and gravel bars sit on surface/mid tiles — passable.
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
			RiverConstants.TILE_DEEP:
				# Stop at the center of the last passable row (one above TILE_DEEP)
				if row == water_start:
					return _near_bank_edge_y()  # deep starts immediately — can't enter
				return float(row - 1) * RiverConstants.TILE_SIZE + RiverConstants.TILE_SIZE * 0.5
			RiverConstants.TILE_RIVERBED:
				# No TILE_DEEP in this column — ford or shallow section, far bank reachable
				if river_data.bottom_bank_profile.size() > col:
					var fbr: int = river_data.bottom_bank_profile[col]
					return float(fbr) * RiverConstants.TILE_SIZE + RiverConstants.TILE_SIZE * 0.5
				return float(row) * RiverConstants.TILE_SIZE
			RiverConstants.TILE_BANK:
				# Far bank tile reached directly — land on it
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
	var col := 0
	if river_data != null:
		col = clampi(int((position.x - section_start_x) / RiverConstants.TILE_SIZE),
				0, river_data.width - 1)
		var row := clampi(int(position.y / RiverConstants.TILE_SIZE), 0, river_data.height - 1)
		var tile: int = river_data.tile_map[col][row]
		is_wading = (tile != RiverConstants.TILE_BANK and tile != RiverConstants.TILE_AIR)
	else:
		is_wading = position.y > BANK_Y + 1.0

	if is_wading:
		# Scale depth against this column's actual water height (near bank → far bank).
		# Deep pools max out at ~0.4 (blocked by TILE_DEEP). Fords reach 1.0 at the far bank.
		# This ensures shallower columns show lower readings, not a fixed-scale fraction.
		var tbh_val := RiverConstants.BANK_H_TILES
		if river_data != null and river_data.top_bank_profile.size() > col:
			tbh_val = river_data.top_bank_profile[col]
		var water_surface_y := float(tbh_val) * RiverConstants.TILE_SIZE
		var water_height_y  := float(MAX_WADE_DEPTH) * float(RiverConstants.TILE_SIZE)
		if river_data != null and river_data.bottom_bank_profile.size() > col:
			var fbr: int = river_data.bottom_bank_profile[col]
			water_height_y = float(fbr - tbh_val) * float(RiverConstants.TILE_SIZE)
		wading_depth = clampf(
			(position.y - water_surface_y) / maxf(water_height_y, 1.0),
			0.0, 1.0
		)
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


# Snaps angler to the bank-water boundary as the river profile curves.
# Near bank: tracks top_bank_profile (water edge). Far bank: tracks bottom_bank_profile.
func _snap_to_bank_surface() -> void:
	if is_wading or river_data == null:
		return
	if Input.is_action_pressed("move_down"):
		return   # player is entering the water — don't snap

	var col := clampi(int((position.x - section_start_x) / RiverConstants.TILE_SIZE),
			0, river_data.width - 1)

	# Determine which bank the angler is on. Near bank is always above the water surface;
	# anything beyond near_edge_y + one tile is far-bank territory.
	var near_edge_y := _near_bank_edge_y()
	if position.y <= near_edge_y + RiverConstants.TILE_SIZE:
		# Near bank — snap to the bank-water boundary (follows river curves)
		position.y = lerpf(position.y, near_edge_y, 0.25)
		return

	# Far bank — snap to bottom_bank_profile row centre.
	# Also handles TILE_AIR when curved far bank shifts the row beneath the angler.
	if river_data.bottom_bank_profile.size() > col:
		var fbr: int = river_data.bottom_bank_profile[col]
		var fb_y := float(fbr) * RiverConstants.TILE_SIZE + RiverConstants.TILE_SIZE * 0.5
		if absf(position.y - fb_y) < RiverConstants.TILE_SIZE * 6.0:
			position.y = lerpf(position.y, fb_y, 0.25)


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
