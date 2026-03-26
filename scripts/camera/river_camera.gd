class_name RiverCamera
extends Camera2D

# Horizontal-only camera for river sections.
# Phase 2: pans freely with arrow keys across the full section.
# Phase 3: will be constrained to ±3 screen widths around the angler.

const RC          := RiverConstants
const PAN_SPEED   := 600.0   # pixels per second
const SCOUT_RANGE := 3       # screen widths player can scout from angler (Phase 3)

var _section_px: float
var _viewport_half_w: float
var _viewport_half_h: float


func _ready() -> void:
	_section_px      = float(RC.SECTION_W_TILES * RC.TILE_SIZE)
	var vp           := get_viewport_rect().size
	_viewport_half_w = vp.x * 0.5
	_viewport_half_h = vp.y * 0.5

	# Fix vertical position so the full river height is always visible
	# Camera y = half-screen, river TileMap starts at y=0 in world space
	global_position  = Vector2(_viewport_half_w, _viewport_half_h)

	limit_left   = 0
	limit_right  = int(_section_px)
	limit_top    = 0
	limit_bottom = int(get_viewport_rect().size.y)

	position_smoothing_enabled = true
	position_smoothing_speed   = 10.0


func _process(delta: float) -> void:
	_pan(delta)


func _pan(delta: float) -> void:
	var dir := 0.0
	if Input.is_action_pressed("move_right"):
		dir += 1.0
	if Input.is_action_pressed("move_left"):
		dir -= 1.0

	if dir == 0.0:
		return

	var new_x := global_position.x + dir * PAN_SPEED * delta
	# Clamp so camera never shows beyond section bounds
	new_x = clampf(new_x, _viewport_half_w, _section_px - _viewport_half_w)
	global_position.x = new_x


# Called by Phase 3 Angler to anchor the scout range around the player.
func set_anchor(world_x: float) -> void:
	var vp_w  := get_viewport_rect().size.x
	var range_px := vp_w * SCOUT_RANGE
	limit_left  = int(maxf(0.0,            world_x - range_px - _viewport_half_w))
	limit_right = int(minf(_section_px,    world_x + range_px + _viewport_half_w))
