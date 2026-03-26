class_name CastingController
extends Node

## Full casting loop state machine.
## IDLE → FALSE_CASTING → PRESENTATION → RESULT → DRIFT → IDLE

enum State { IDLE, FALSE_CASTING, PRESENTATION, RESULT, DRIFT }
enum CastQuality { TIGHT, SLOPPY, BAD }

signal cast_started
signal cast_result(quality: int, target_x: float, target_y: float)
signal mend_upstream
signal mend_downstream
signal drift_started
signal drift_ended

const LINE_MIN        := 2.0    # minimum castable line (tiles)
const LINE_MAX        := 20.0   # maximum castable line (tiles)
const LINE_FEED_RATE  := 3.0    # tiles per second when feeding
const LINE_STRIP_RATE := 5.0    # tiles per second when stripping

# Load time: how long until line fully straightens per stroke, scales with line length
const LOAD_MIN        := 0.40   # sec at LINE_MIN
const LOAD_MAX        := 0.90   # sec at LINE_MAX
# Stroke is "on time" if direction changes within ±TIMING_TOL fraction of load time
const TIMING_TOL      := 0.28

# Direction reversals required before SPACE completes the cast
const MIN_FALSE_CASTS := 2

const PRESENTATION_DUR := 0.5   # seconds line is in air before landing
const RESULT_DUR       := 1.2   # seconds cast quality is displayed
const MEND_THRESHOLD   := 40.0  # mouse pixels of movement to trigger a mend

var state: State = State.IDLE
var line_length: float = 6.0
var cast_quality: CastQuality = CastQuality.TIGHT

var angler: Node2D = null   # set by RiverWorld after spawn

# False casting internals
var _in_stroke: bool = false
var _stroke_dir: int = 0         # -1 = backcast  +1 = forward cast
var _stroke_timer: float = 0.0
var _good_strokes: int = 0
var _total_strokes: int = 0
var _false_cast_count: int = 0   # number of direction reversals completed

# Shared timer for timed states
var _state_timer: float = 0.0

# Computed cast target in world space
var _target_x: float = 0.0
var _target_y: float = 0.0

# Mouse accumulator for mend detection during drift
var _mend_accum: float = 0.0


func _input(event: InputEvent) -> void:
	if state == State.DRIFT and event is InputEventMouseMotion:
		_mend_accum += (event as InputEventMouseMotion).relative.x
		if _mend_accum <= -MEND_THRESHOLD:
			_mend_accum = 0.0
			mend_upstream.emit()
			print("CastingController: mend upstream")
		elif _mend_accum >= MEND_THRESHOLD:
			_mend_accum = 0.0
			mend_downstream.emit()
			print("CastingController: mend downstream")


func _process(delta: float) -> void:
	match state:
		State.IDLE:
			_process_idle(delta)
		State.FALSE_CASTING:
			_process_false_casting(delta)
		State.PRESENTATION:
			_state_timer += delta
			if _state_timer >= PRESENTATION_DUR:
				_enter_result()
		State.RESULT:
			_state_timer += delta
			if _state_timer >= RESULT_DUR:
				_enter_drift()
		State.DRIFT:
			_process_drift()


# ---------------------------------------------------------------------------
# IDLE — feed/strip line, start casting
# ---------------------------------------------------------------------------

func _process_idle(delta: float) -> void:
	if Input.is_action_pressed("feed_line"):
		line_length = minf(line_length + LINE_FEED_RATE * delta, LINE_MAX)
	elif Input.is_action_pressed("strip_line"):
		line_length = maxf(line_length - LINE_STRIP_RATE * delta, LINE_MIN)

	if Input.is_action_just_pressed("cast_back"):
		_begin_false_casting(-1)
	elif Input.is_action_just_pressed("cast_forward"):
		_begin_false_casting(1)


# ---------------------------------------------------------------------------
# FALSE_CASTING — alternating stroke rhythm
# ---------------------------------------------------------------------------

func _begin_false_casting(first_dir: int) -> void:
	state             = State.FALSE_CASTING
	_in_stroke        = true
	_stroke_dir       = first_dir
	_stroke_timer     = 0.0
	_good_strokes     = 0
	_total_strokes    = 0
	_false_cast_count = 0
	cast_started.emit()
	print("CastingController: false cast started | line=%.1f tiles" % line_length)


func _load_time() -> float:
	var t := (line_length - LINE_MIN) / (LINE_MAX - LINE_MIN)
	return lerpf(LOAD_MIN, LOAD_MAX, t)


func _process_false_casting(delta: float) -> void:
	if _in_stroke:
		_stroke_timer += delta

	if Input.is_action_pressed("feed_line"):
		line_length = minf(line_length + LINE_FEED_RATE * delta, LINE_MAX)
	elif Input.is_action_pressed("strip_line"):
		line_length = maxf(line_length - LINE_STRIP_RATE * delta, LINE_MIN)

	var new_dir := 0
	if Input.is_action_just_pressed("cast_back"):
		new_dir = -1
	elif Input.is_action_just_pressed("cast_forward"):
		new_dir = 1

	if new_dir != 0 and new_dir != _stroke_dir:
		_finish_stroke()
		_stroke_dir   = new_dir
		_stroke_timer = 0.0
		_in_stroke    = true

	if Input.is_action_just_pressed("complete_cast"):
		if _false_cast_count >= MIN_FALSE_CASTS:
			if _in_stroke:
				_finish_stroke()
			_enter_presentation()
		else:
			print("CastingController: need %d more direction change(s) before releasing" % \
				(MIN_FALSE_CASTS - _false_cast_count))


func _finish_stroke() -> void:
	if not _in_stroke:
		return
	_in_stroke         = false
	_false_cast_count += 1
	_total_strokes    += 1

	var load := _load_time()
	var lo   := load * (1.0 - TIMING_TOL)
	var hi   := load * (1.0 + TIMING_TOL)
	var good := _stroke_timer >= lo and _stroke_timer <= hi
	if good:
		_good_strokes += 1
	print("CastingController: stroke %d | timer=%.2fs window=%.2f-%.2f  %s" % [
		_false_cast_count, _stroke_timer, lo, hi,
		"GOOD" if good else "MISS"
	])


# ---------------------------------------------------------------------------
# PRESENTATION → RESULT
# ---------------------------------------------------------------------------

func _enter_presentation() -> void:
	state        = State.PRESENTATION
	_state_timer = 0.0
	_compute_target()


func _enter_result() -> void:
	state        = State.RESULT
	_state_timer = 0.0
	cast_quality = _evaluate_quality()
	var names    := ["TIGHT", "SLOPPY", "BAD"]
	print("CastingController: result = %s | line=%.1f tiles | target_x=%.0f" % [
		names[cast_quality], line_length, _target_x
	])
	cast_result.emit(cast_quality, _target_x, _target_y)


func _compute_target() -> void:
	if angler:
		var dist   := line_length * float(RiverConstants.TILE_SIZE)
		_target_x   = maxf(angler.position.x - dist, 0.0)
		_target_y   = float(RiverConstants.BANK_H_TILES * RiverConstants.TILE_SIZE)
	else:
		_target_x = 0.0
		_target_y = 96.0


func _evaluate_quality() -> CastQuality:
	if _total_strokes == 0:
		return CastQuality.BAD
	var ratio := float(_good_strokes) / float(_total_strokes)
	if ratio >= 0.67:
		return CastQuality.TIGHT
	elif ratio >= 0.34:
		return CastQuality.SLOPPY
	return CastQuality.BAD


# ---------------------------------------------------------------------------
# DRIFT — fly on water; mend via mouse, retrieve with R
# ---------------------------------------------------------------------------

func _enter_drift() -> void:
	state       = State.DRIFT
	_mend_accum = 0.0
	drift_started.emit()
	print("CastingController: drift started | mouse to mend | R to retrieve")


func _process_drift() -> void:
	if Input.is_action_just_pressed("strip_line"):
		state = State.IDLE
		drift_ended.emit()
		print("CastingController: line retrieved")


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

# Returns the world-space fly landing position (valid once RESULT state has run)
func get_fly_pos() -> Vector2:
	return Vector2(_target_x, _target_y)
