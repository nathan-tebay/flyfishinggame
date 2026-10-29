class_name LoopPhysicsEngine
extends Node

# Tuning knobs (exported for inspector tweaking)
@export var rod_bend_speed_scale := 2.0  # rad/s — normalize elevation velocity
@export var rod_accel_scale := 100.0  # px/frame² — normalize mouse acceleration
@export var line_base_speed := 10.0  # m/s — loop propagation rate
@export var base_loop_width := 0.08  # m — resting loop width
@export var tightness_divisor := 5.0  # higher = less tightness effect
@export var loop_apex_height := 0.8  # m — how high loop nose rises

# LoopState: immutable snapshot of loop physics at a moment
class LoopState:
	var position_along_line: float  # [0, 1] where 0=rod tip, 1=fly
	var travel_speed: float  # m/s down the line
	var width: float  # m, loop bulge width
	var bend_amount: float  # [0, 1] normalized rod flex
	var bend_speed: float  # rad/s elevation velocity
	var has_delivered: bool  # true once position >= 0.99

	func _init(p: float, s: float, w: float, b: float, bs: float, d: bool = false) -> void:
		position_along_line = clampf(p, 0.0, 1.0)
		travel_speed = s
		width = w
		bend_amount = b
		bend_speed = bs
		has_delivered = d


var _prev_elevation_offset: float = 0.0
var _prev_mouse_dy: float = 0.0
var _loop_state: LoopState = LoopState.new(0.0, 0.0, base_loop_width, 0.0, 0.0)


func _ready() -> void:
	_loop_state = LoopState.new(0.0, 0.0, base_loop_width, 0.0, 0.0)


# Called per frame by casting manager with current rod elevation state
func update(delta: float, elevation_offset: float, mouse_dy_current: float) -> LoopState:
	if delta <= 0.0:
		return _loop_state

	# Calculate elevation velocity and acceleration
	var bend_speed_raw: float = (elevation_offset - _prev_elevation_offset) / delta
	var mouse_accel: float = (mouse_dy_current - _prev_mouse_dy) / delta

	# Compute bend amount from combined velocity + acceleration
	var bend_amount = _bend_from_input(bend_speed_raw, mouse_accel)

	# Compute loop travel speed from bend state
	var travel_speed = _speed_from_bend(bend_amount, bend_speed_raw)

	# Compute loop width from speed (higher speed = tighter loop)
	var loop_width = _width_from_speed(travel_speed)

	# Advance loop position along the line (placeholder: assume 1.0m line length for now)
	var line_length = 2.74  # rod length + some extended line; will be parameterized
	var new_position = _advance_loop_position(
		_loop_state.position_along_line,
		travel_speed,
		line_length,
		delta
	)

	# Check delivery (loop reached fly)
	var has_delivered = _loop_state.has_delivered or new_position >= 0.99

	# Update state
	_loop_state = LoopState.new(new_position, travel_speed, loop_width, bend_amount, bend_speed_raw, has_delivered)
	_prev_elevation_offset = elevation_offset
	_prev_mouse_dy = mouse_dy_current

	return _loop_state


# Reset loop state (called at start of backcast)
func reset_loop() -> void:
	_loop_state = LoopState.new(0.0, 0.0, base_loop_width, 0.0, 0.0, false)
	_prev_elevation_offset = 0.0
	_prev_mouse_dy = 0.0


# Public getter
func get_loop_state() -> LoopState:
	return _loop_state


# ============================================================================
# Private Physics Formulas
# ============================================================================

func _bend_from_input(bend_speed_raw: float, mouse_accel: float) -> float:
	# Combine elevation velocity + mouse acceleration into normalized bend amount
	# Higher speed (faster raise/lower) = more bend
	# Higher accel = more aggressive bend
	var normalized_speed = absf(bend_speed_raw) / rod_bend_speed_scale
	var normalized_accel = absf(mouse_accel) / rod_accel_scale

	var bend = normalized_speed + normalized_accel * 0.5
	return clampf(bend, 0.0, 1.0)


func _speed_from_bend(bend_amount: float, bend_speed_raw: float) -> float:
	# Loop travels faster when rod bends more and moves faster
	var bend_contribution = bend_amount * bend_amount  # quadratic for emphasis
	var speed_contribution = absf(bend_speed_raw) / rod_bend_speed_scale * 0.5

	var total = (bend_contribution + speed_contribution) * line_base_speed
	return maxf(total, 0.0)


func _width_from_speed(travel_speed: float) -> float:
	# Loop tightens (width shrinks) as speed increases
	var tightness = 1.0 + (travel_speed / tightness_divisor)
	var width = base_loop_width / tightness

	return clampf(width, 0.02, 0.15)  # visual sanity bounds


func _advance_loop_position(prev_pos: float, speed: float, line_length: float, delta: float) -> float:
	# Move loop down the line based on travel speed and elapsed time
	if line_length <= 0.0:
		return prev_pos

	var distance_traveled = speed * delta
	var position_delta = distance_traveled / line_length
	var new_pos = prev_pos + position_delta

	return clampf(new_pos, 0.0, 1.0)
