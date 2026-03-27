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
const MAX_WADE_DEPTH  := 8  # tiles below surface — shallow fords (≤8 tiles) are crossable

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

	# Horizontal — upper bound is effectively unlimited; camera limits constrain scouting
	if dx != 0.0:
		var spd := WADE_SPEED_H if is_wading else BANK_SPEED
		position.x = maxf(position.x + dx * spd * delta, 0.0)

	# Vertical — move up/down freely; wading state is derived from position in _sync_wading_state
	if dy > 0.0:
		position.y = minf(position.y + WADE_SPEED_V * delta, _max_wade_y())
	elif dy < 0.0:
		position.y = maxf(position.y - WADE_SPEED_V * delta, BANK_Y)

	return dx != 0.0 or dy != 0.0


# Maximum y the angler can reach in the current column.
# Hard cap = MAX_WADE_DEPTH tiles from surface (prevents crossing deep water).
# In ford sections (riverbed within cap) the angler can reach the far bank.
func _max_wade_y() -> float:
	var depth_cap := float(WADE_ENTRY_Y + MAX_WADE_DEPTH * RiverConstants.TILE_SIZE)

	if river_data == null:
		return depth_cap

	var col := clampi(int((position.x - section_start_x) / RiverConstants.TILE_SIZE), 0, river_data.width - 1)

	# Scan downward to find the first TILE_BANK or TILE_RIVERBED (bottom boundary)
	for row in range(RiverConstants.BANK_H_TILES, river_data.height):
		var t: int = river_data.tile_map[col][row]
		if t == RiverConstants.TILE_RIVERBED:
			# Riverbed found: allow wading to just past it (into far bank) if shallow enough
			var riverbed_y := float(row + 1) * RiverConstants.TILE_SIZE
			return minf(riverbed_y, depth_cap)
		if t == RiverConstants.TILE_BANK and row > RiverConstants.BANK_H_TILES:
			# Far bank tile (bottom bank) reached
			var far_bank_y := float(row) * RiverConstants.TILE_SIZE + RiverConstants.TILE_SIZE * 0.5
			return minf(far_bank_y, depth_cap)

	return depth_cap


# ---------------------------------------------------------------------------
# State sync
# ---------------------------------------------------------------------------

func _sync_wading_state() -> void:
	# Wading is fully position-driven — no separate flag needed
	is_wading = position.y > BANK_Y + 1.0
	if is_wading:
		wading_depth = clampf(
			(position.y - WADE_ENTRY_Y) / float(MAX_WADE_DEPTH * RiverConstants.TILE_SIZE),
			0.0, 1.0
		)
	else:
		wading_depth = 0.0


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
