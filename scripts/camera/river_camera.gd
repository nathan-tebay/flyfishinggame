class_name RiverCamera
extends Camera2D

# Horizontal-only camera for river sections.
# Phase 3+: follows Angler (follow_target) with scout range ±3 screen widths.
# Phase 2 free-pan mode retained when follow_target is null (for testing).

const PAN_SPEED   := 600.0  # pixels per second (free-pan mode only)
const SCOUT_RANGE := 3      # screen widths the player can scout from angler

var follow_target: Node2D = null  # set by RiverWorld after angler is spawned

var _section_px: float
var _viewport_half_w: float
var _viewport_half_h: float


func _ready() -> void:
	_section_px      = float(RiverConstants.SECTION_W_TILES * RiverConstants.TILE_SIZE)
	var vp           := get_viewport_rect().size
	_viewport_half_w = vp.x * 0.5
	_viewport_half_h = vp.y * 0.5

	global_position  = Vector2(_viewport_half_w, _viewport_half_h)

	limit_left   = 0
	limit_right  = int(_section_px)
	limit_top    = 0
	limit_bottom = int(get_viewport_rect().size.y)

	position_smoothing_enabled = true
	position_smoothing_speed   = 10.0


func _process(delta: float) -> void:
	if follow_target:
		_follow()
	else:
		_pan(delta)


# Follow the target's x position; y stays fixed at viewport centre.
func _follow() -> void:
	position.x = follow_target.position.x


# Free-pan with move_left/move_right — Phase 2 testing mode, used when no follow_target.
func _pan(delta: float) -> void:
	var dir := 0.0
	if Input.is_action_pressed("move_right"):
		dir += 1.0
	if Input.is_action_pressed("move_left"):
		dir -= 1.0

	if dir == 0.0:
		return

	var new_x := global_position.x + dir * PAN_SPEED * delta
	new_x = clampf(new_x, _viewport_half_w, _section_px - _viewport_half_w)
	global_position.x = new_x


# Constrains camera limits to ±SCOUT_RANGE screen widths around the angler.
# Called by RiverWorld._process() each frame.
func set_anchor(world_x: float) -> void:
	var vp_w      := get_viewport_rect().size.x
	var range_px  := vp_w * SCOUT_RANGE
	limit_left  = int(maxf(0.0,         world_x - range_px - _viewport_half_w))
	limit_right = int(minf(_section_px, world_x + range_px + _viewport_half_w))
