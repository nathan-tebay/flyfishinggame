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
const MAX_WADE_DEPTH  := 5  # tiles below surface the angler can wade
const MAX_WADE_Y      := WADE_ENTRY_Y + MAX_WADE_DEPTH * RiverConstants.TILE_SIZE  # 256

const STILL_THRESHOLD := 3.0  # seconds motionless before signal

signal standing_still

var is_wading: bool = false
var wading_depth: float = 0.0      # 0.0 = at surface, 1.0 = max wading depth
var vibration_radius: float = 0.0  # read by SpookCalculator; 0 when still or on bank

var river_data: RiverData  # assigned by RiverWorld after river is generated

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

	# Horizontal
	if dx != 0.0:
		var spd := WADE_SPEED_H if is_wading else BANK_SPEED
		var max_x := float(RiverConstants.SECTION_W_TILES * RiverConstants.TILE_SIZE)
		position.x = clampf(position.x + dx * spd * delta, 0.0, max_x)

	# Vertical — entering / leaving water
	if dy > 0.0:
		if not is_wading:
			is_wading = true
		position.y = minf(position.y + WADE_SPEED_V * delta, _max_wade_y())
	elif dy < 0.0 and is_wading:
		var new_y := position.y - WADE_SPEED_V * delta
		if new_y <= BANK_Y:
			is_wading = false
			position.y = BANK_Y
		else:
			position.y = new_y

	return dx != 0.0 or dy != 0.0


# Maximum y the angler can reach in the current column, respecting river depth and cap.
func _max_wade_y() -> float:
	var depth_cap := float(WADE_ENTRY_Y + MAX_WADE_DEPTH * RiverConstants.TILE_SIZE)

	if river_data == null:
		return depth_cap

	var col := clampi(int(position.x / RiverConstants.TILE_SIZE), 0, river_data.width - 1)
	var river_bottom_y := float(WADE_ENTRY_Y)
	for row in range(RiverConstants.BANK_H_TILES, river_data.height):
		var t: int = river_data.tile_map[col][row]
		if t == RiverConstants.TILE_AIR or t == RiverConstants.TILE_RIVERBED:
			break
		river_bottom_y = float(row) * RiverConstants.TILE_SIZE + RiverConstants.TILE_SIZE * 0.5

	# Stay one tile above riverbed; also respect absolute cap
	return minf(river_bottom_y, depth_cap)


# ---------------------------------------------------------------------------
# State sync
# ---------------------------------------------------------------------------

func _sync_wading_state() -> void:
	# Correct any drift: if position somehow crept above bank level, exit water
	if is_wading and position.y < WADE_ENTRY_Y - 0.5:
		is_wading = false
		position.y = BANK_Y

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
	var w := 16.0
	var h := 28.0
	# Body — magenta rectangle, feet at y=0 (angler's reference point)
	draw_rect(Rect2(-w * 0.5, -h, w, h), Color(0.9, 0.2, 0.6))
	# Wading depth indicator — cyan bar on left edge
	if is_wading:
		var bar_h := wading_depth * h
		draw_rect(Rect2(-w * 0.5 - 8.0, -h, 4.0, bar_h), Color(0.3, 0.6, 0.95))
