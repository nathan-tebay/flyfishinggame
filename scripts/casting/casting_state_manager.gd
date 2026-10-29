class_name CastingStateManager
extends Node

# Manages the casting FSM: setup → backcast → forward → delivery
# Drives loop lifecycle and phase transitions based on rod state.

enum Phase { SETUP, BACKCAST, FORWARD, DELIVERY, LIFTING_ROLL }

# Hysteresis on the descending test, matching FlyRod3D.is_rod_descending(): the rod
# elevation is damped mouse input, so a raw sign test on the per-frame delta flips
# ascending/descending on jitter, thrashing the phase machine. The rod must drop by
# more than this (radians/frame-ish) to count as descending.
const ELEV_DESCEND_DEADBAND := 0.002

# Discrete cast events. The world owns reach/builder/drift and reacts to these;
# this module never touches the scene. See docs/plans/2026-06-02-collapse-casting-loop.md.
signal delivered(style: String, line_load: float, loop_quality: String)
signal false_cast(count: int)
signal stroke_scored(quality: String, line_load: float)  # one shot per scored stroke (HUD feedback)

# --- Stroke timing / elevation thresholds (mirrors river_world_3d.gd defaults) ---
@export var lift_start_elev: float = 0.28        # rod must rise past this to begin a backcast
@export var lift_speed_threshold: float = 4.0    # peak rod-lift speed for a quick backcast while the fly is on water
@export var backcast_load_elev: float = 1.12     # how high the rod must rise to load a backcast
@export var backcast_release_elev: float = 0.58  # backcast considered released below this on reversal
@export var forward_commit_elev: float = 0.10    # how low the rod must drop to finish a forward stroke
@export var delivery_load_min: float = 0.90      # line load gate for delivery
@export var delivery_timing_min: float = 0.70    # delivery stroke must let the loop straighten first
@export var tight_load_gain: float = 0.30        # line load added per well-timed (tight) stroke
@export var unroll_time_min: float = 0.45        # seconds, short line
@export var unroll_time_max: float = 1.30        # seconds, full line out
@export var line_length_min: float = 3.0         # for unroll-time scaling (mirrors CAST_LINE_LENGTH_MIN)
@export var line_length_max: float = 38.0        # mirrors CAST_LINE_LENGTH_MAX

var _current_phase: Phase = Phase.SETUP
var _loop_physics: LoopPhysicsEngine = null
var _phase_entered_at: float = 0.0
var _prev_rod_elevation: float = 0.0

# --- Gameplay stroke state (migrated from river_world_3d gesture machine) ---
var _line_load: float = 0.0              # proportion of target distance loaded (0-1.2)
var _loop_quality: String = "none"       # tight / adequate / tailing / wide / none
var _false_cast_count: int = 0
var _stroke_clock: float = 0.0           # seconds since the last stroke reversal
var _unroll_time: float = 0.6            # half-period the current loop needs to straighten
var _stroke_dir: String = ""             # "back" or "forward"
var _pending_line_penalty: float = 0.0   # penalty carried from a mistimed stroke
var _lateral_at_backcast_load: float = 0.0  # rod off-plane drift sampled at backcast load
var _reached_load: bool = false          # backcast reached the load height
var _reached_bottom: bool = false        # forward stroke reached the delivery height

# --- Per-frame context, fed by the world before update() (keeps this module pure) ---
var _fly_on_water: bool = false          # whether the fly is already drifting on the water
var _lateral: float = 0.0                # rod off-plane yaw (radians)
var _peak_lift_speed: float = 0.0        # peak rod-lift speed since the last reset
var _line_length: float = 3.0            # current cast line length (metres)


func _ready() -> void:
	_loop_physics = LoopPhysicsEngine.new()
	add_child(_loop_physics)


# Update casting state based on rod elevation and gesture inputs.
# Returns the current loop state.
func update(delta: float, rod_elevation: float, mouse_dy: float) -> LoopPhysicsEngine.LoopState:
	if _loop_physics == null:
		return LoopPhysicsEngine.LoopState.new(0.0, 0.0, 0.08, 0.0, 0.0)

	var loop_state = _loop_physics.update(delta, rod_elevation, mouse_dy)
	_advance_phase(delta, rod_elevation)
	_prev_rod_elevation = rod_elevation
	return loop_state


# Per-frame context the world feeds before update(); keeps this module pure (no
# angler/reach/builder references). Defaults are safe for a standalone unit test.
func set_cast_context(line_length: float, lateral: float, fly_on_water: bool, peak_lift_speed: float = 0.0) -> void:
	_line_length = line_length
	_lateral = lateral
	_fly_on_water = fly_on_water
	_peak_lift_speed = peak_lift_speed


# Drives the false-cast rhythm from rod elevation: raise to load a backcast,
# reverse when the loop straightens, lower a loaded forward stroke to deliver.
# Ported from river_world_3d._update_gesture_state_machine. The roll path and the
# delivered/false_cast signal emits are wired in a later task.
func _advance_phase(delta: float, elev: float) -> void:
	var descending := (elev - _prev_rod_elevation) < -ELEV_DESCEND_DEADBAND
	match _current_phase:
		Phase.SETUP:
			if elev >= lift_start_elev:
				var is_quick := _peak_lift_speed > lift_speed_threshold
				if is_quick or not _fly_on_water:
					_begin_stroke("back")
				else:
					# Gentle lift with the fly on water: form a D-loop for a roll cast.
					_current_phase = Phase.LIFTING_ROLL

		Phase.LIFTING_ROLL:
			# Sweep the rod forward (descending through the D-loop band) to commit the
			# roll; lift hard instead to convert to an overhead backcast.
			if descending and elev >= 0.25 and elev <= 0.50:
				_commit_roll_cast()
			elif elev >= backcast_load_elev:
				_begin_stroke("back")
			elif elev < 0.15:
				_current_phase = Phase.SETUP

		Phase.BACKCAST:
			# Rod rising; the previous loop unrolls. Reverse (start descending) once
			# the rod is high AND the loop has straightened (timing scored).
			_stroke_clock += delta
			if elev >= backcast_load_elev:
				_reached_load = true
			if _reached_load and descending:
				_complete_stroke("backcast")
				_begin_stroke("forward")
			elif elev < 0.15 and not _reached_load:
				_current_phase = Phase.SETUP

		Phase.FORWARD:
			# Rod descending; line loads each well-timed stroke. Under-loaded forward
			# strokes stay aerial (false cast); once LOADED, lowering delivers.
			_stroke_clock += delta
			if elev <= forward_commit_elev:
				_reached_bottom = true
			var loop_straight := get_unroll_progress() >= delivery_timing_min
			if _reached_bottom and descending and _line_load >= delivery_load_min and loop_straight:
				# Loaded AND the loop had time to straighten -> clean delivery.
				_complete_stroke("forward")
				_current_phase = Phase.DELIVERY
				delivered.emit("overhead", _line_load, _loop_quality)
			elif _reached_bottom and not descending:
				# Under-loaded forward stroke stays aerial -> false cast.
				_complete_stroke("forward")
				_false_cast_count += 1
				false_cast.emit(_false_cast_count)
				_begin_stroke("back")
			elif not _reached_bottom and elev >= backcast_load_elev:
				# Aborted the forward stroke by lifting again -> treat as a new backcast.
				_begin_stroke("back")

		Phase.DELIVERY:
			# Cast complete; re-arm a backcast when the rod is raised again.
			if elev >= lift_start_elev and not descending:
				_begin_stroke("back")


# Half-period the current loop needs to straighten, scaled by line length.
func _compute_unroll_time() -> float:
	var span := maxf(line_length_max - line_length_min, 0.01)
	var t := clampf((_line_length - line_length_min) / span, 0.0, 1.0)
	return lerpf(unroll_time_min, unroll_time_max, t)


# Starts a new stroke ("back"/"forward"), resetting the unroll clock so its timing
# is scored at the next reversal.
func _begin_stroke(dir: String) -> void:
	_stroke_dir = dir
	_stroke_clock = 0.0
	_unroll_time = _compute_unroll_time()
	if dir == "back":
		_current_phase = Phase.BACKCAST
		_reached_load = false
		_lateral_at_backcast_load = _lateral
		if _loop_physics != null:
			_loop_physics.reset_loop()
	else:
		_current_phase = Phase.FORWARD
		_reached_bottom = false


# Scores a completed stroke by how straight the loop was (time since the last
# reversal vs the line-length-scaled unroll time) and loads/penalises the line.
func _complete_stroke(phase: String) -> void:
	var progress := get_unroll_progress()
	if phase == "backcast":
		var lateral_drift := absf(_lateral - _lateral_at_backcast_load)
		var tracking_penalty := clampf(lateral_drift / deg_to_rad(12.0), 0.0, 1.0) * 0.12
		if tracking_penalty > 0.04:
			_pending_line_penalty -= tracking_penalty
	_apply_stroke_quality(progress)
	stroke_scored.emit(_loop_quality, _line_load)


# Commits a roll cast from the D-loop: a roll always lays down an adequate loop and
# carries a baseline load. Ported from river_world_3d._evaluate_roll_cast_commit
# (the rod animation / reset stays world-side, driven by the delivered signal).
func _commit_roll_cast() -> void:
	_loop_quality = "adequate"
	_line_load = minf(maxf(_line_load, 0.6) + 0.20, 1.2)
	_current_phase = Phase.DELIVERY
	delivered.emit("roll", _line_load, _loop_quality)


# Converts how close the reversal was to the loop straightening (progress ~1.0)
# into a loop quality and a line-load delta.
func _apply_stroke_quality(progress: float) -> void:
	if progress >= 0.82 and progress <= 1.18:
		_loop_quality = "tight"
		_line_load = minf(_line_load + tight_load_gain + _pending_line_penalty, 1.2)
		_pending_line_penalty = 0.0
	elif progress >= 0.62 and progress <= 1.45:
		_loop_quality = "adequate"
		_line_load = minf(_line_load + 0.16 + _pending_line_penalty, 1.2)
		_pending_line_penalty = 0.0
	elif progress < 0.62:
		_loop_quality = "tailing"
		_pending_line_penalty = -0.06
	else:
		_loop_quality = "wide"
		_line_load = maxf(_line_load - 0.05, 0.0)
		_pending_line_penalty = -0.10


# Public getters
func get_current_phase() -> Phase:
	return _current_phase


func get_phase_name() -> String:
	match _current_phase:
		Phase.SETUP:
			return "SETUP"
		Phase.BACKCAST:
			return "BACKCAST"
		Phase.FORWARD:
			return "FORWARD"
		Phase.DELIVERY:
			return "DELIVERY"
		Phase.LIFTING_ROLL:
			return "ROLL"
		_:
			return "UNKNOWN"


func get_loop_state() -> LoopPhysicsEngine.LoopState:
	if _loop_physics == null:
		return LoopPhysicsEngine.LoopState.new(0.0, 0.0, 0.08, 0.0, 0.0)
	return _loop_physics.get_loop_state()


# --- Continuous gameplay getters (HUD reads these each frame) ---
func get_line_load() -> float:
	return _line_load


func get_loop_quality() -> String:
	return _loop_quality


func get_false_cast_count() -> int:
	return _false_cast_count


func get_stroke_dir() -> String:
	return _stroke_dir


func get_unroll_progress() -> float:
	return _stroke_clock / maxf(_unroll_time, 0.05)


func is_ready_to_deliver() -> bool:
	return _line_load >= delivery_load_min


func reset_to_setup() -> void:
	_current_phase = Phase.SETUP
	_prev_rod_elevation = 0.0
	_line_load = 0.0
	_loop_quality = "none"
	_false_cast_count = 0
	_stroke_clock = 0.0
	_unroll_time = 0.6
	_stroke_dir = ""
	_pending_line_penalty = 0.0
	_lateral_at_backcast_load = 0.0
	_reached_load = false
	_reached_bottom = false
	_fly_on_water = false
	_lateral = 0.0
	_peak_lift_speed = 0.0
	_line_length = line_length_min
	if _loop_physics != null:
		_loop_physics.reset_loop()
