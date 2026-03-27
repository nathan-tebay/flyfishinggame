class_name RodArcHUD
extends Node2D

## Casting indicator — centered at screen bottom.
## Shows: rod with grip/reel/forearm, fly line loop rolling out, timing cue, drag sag.

const ROD_LEN  := 88.0   # grip to tip
const ROD_W    := 3.5

# Rod angles (degrees from +x, using Vector2(cos(a), -sin(a)) for screen coords)
# _stroke_dir==-1 (backcast, line RIGHT) → rod at ANGLE_BACK (tip upper-left)
# _stroke_dir==1  (fwd cast, line LEFT)  → rod at ANGLE_FORWARD (tip upper-right)
const ANGLE_FORWARD  := 58.0   # forward stop: rod tip upper-right
const ANGLE_BACK     := 132.0  # backcast stop: rod tip upper-left
const ANGLE_IDLE     := 74.0   # idle/drift
const ANGLE_PRESENT  := 52.0   # presentation: rod lower toward water

const C_ROD   := Color(0.55, 0.38, 0.18)
const C_LINE  := Color(0.88, 0.84, 0.72)
const C_TIGHT := Color(0.20, 0.90, 0.35)
const C_SLOPPY:= Color(0.95, 0.82, 0.15)
const C_BAD   := Color(0.90, 0.22, 0.18)
const C_FLY   := Color(0.85, 0.38, 0.10)
const C_CUE    := Color(1.00, 0.95, 0.30)  # timing cue highlight
const C_TARGET := Color(0.70, 0.95, 0.40)  # yellow-green target notch

var casting: CastingController = null
var drift:   DriftController   = null
var target_line_length: float  = -1.0   # tiles; -1 = no target


func _ready() -> void:
	var vp  := get_viewport_rect().size
	position = Vector2(vp.x * 0.5, vp.y - 110.0)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font

	if casting == null:
		_draw_rod(ANGLE_IDLE, 0.0)
		var idle_tip := _rod_tip(ANGLE_IDLE)
		draw_line(idle_tip, idle_tip + Vector2(-_line_len() * 0.20, 10.0), C_LINE, 1.5)
		return

	match casting.state:
		CastingController.State.IDLE:
			_draw_rod(ANGLE_IDLE, 0.0)
			var tip := _rod_tip(ANGLE_IDLE)
			draw_line(tip, tip + Vector2(-_line_len() * 0.20, 10.0), C_LINE, 1.5)
			_draw_status(font, "F: feed     R: strip     ↓/↑: cast")

		CastingController.State.FALSE_CASTING:
			_draw_false_casting(font)

		CastingController.State.PRESENTATION:
			_draw_rod(ANGLE_PRESENT, 0.0)
			var tip     := _rod_tip(ANGLE_PRESENT)
			var far_end := tip + Vector2(-_line_len(), 0.0)
			draw_line(tip, far_end, C_LINE, 1.5)
			draw_circle(far_end, 4.0, C_FLY)
			_draw_status(font, "Presenting…")

		CastingController.State.RESULT:
			# The loop shows how well the timing was:
			#   TIGHT  — tiny loop, fly almost at loop apex (upper and lower legs nearly parallel)
			#   SLOPPY — medium loop, fly a quarter-line back from the loop
			#   BAD    — wide loop, fly halfway back toward the rod
			var qcol:   Color = _quality_color()
			var qloop_h: float = ([6.0, 24.0, 44.0] as Array)[casting.cast_quality]
			_draw_rod(ANGLE_PRESENT, 0.0)
			var tip     := _rod_tip(ANGLE_PRESENT)
			var len     := _line_len()
			var loop_r  := qloop_h * 0.5
			# Upper leg: rod tip → loop (going left, the forward-cast direction)
			var top_end := tip + Vector2(-len + loop_r, 0.0)
			var bot_end := top_end + Vector2(0.0, qloop_h)
			var lc      := top_end + Vector2(0.0, loop_r)
			draw_line(tip, top_end, qcol, 2.0)
			draw_arc(lc, loop_r, PI * 0.5, PI * 1.5, 14, qcol, 2.2)
			# Lower leg: loop bottom → fly (going right, back toward angler)
			# Length depends on timing quality — tight cast = fly right at loop; bad = fly way back
			var lower_fracs: Array = [0.04, 0.28, 0.56]
			var lower_len: float = (lower_fracs as Array)[casting.cast_quality] * len
			var fly_pos := bot_end + Vector2(lower_len, 0.0)
			draw_line(bot_end, fly_pos, qcol, 2.0)
			draw_circle(fly_pos, 4.0, C_FLY)
			var qlabels: Array = ["TIGHT LOOP", "SLOPPY LOOP", "BAD CAST"]
			_draw_status(font, qlabels[casting.cast_quality] as String, qcol)

		CastingController.State.DRIFT:
			_draw_drift(font)

	_draw_bar()


# ---------------------------------------------------------------------------
# False casting — line rolls out as a loop (two legs + semicircle at leading edge)
# ---------------------------------------------------------------------------

func _draw_false_casting(font: Font) -> void:
	var rod_angle := ANGLE_BACK if casting._stroke_dir == -1 else ANGLE_FORWARD
	var load      := casting._load_time()
	# raw_t is unclipped so we can detect overshoot (player waited too long)
	var raw_t:    float = casting._stroke_timer / load
	var progress: float = clampf(raw_t, 0.0, 1.0)

	# Rod tip trails behind grip — bends away from cast direction (tip lags due to line inertia)
	var flex := clampf((progress - 0.70) / 0.30, 0.0, 1.0)
	_draw_rod(rod_angle, flex * (-1 if casting._stroke_dir == -1 else 1))

	var tip      := _rod_tip(rod_angle)
	var line_dir := Vector2(1.0, 0.0) if casting._stroke_dir == -1 else Vector2(-1.0, 0.0)
	var max_len  := _line_len()

	# past_grace: seconds elapsed after the 0.25s grace period following full extension.
	# During the grace window the loop stays tight — 0.25s of "line straight" hold time.
	var past_grace: float = maxf(0.0, casting._stroke_timer - load - 0.25)

	# Loop height: narrows to 4 px at full extension, stays tight during grace, then widens.
	var loop_h: float
	if past_grace <= 0.0:
		loop_h = lerpf(40.0, 4.0, progress)
	else:
		loop_h = lerpf(4.0, 40.0, clampf(past_grace / 0.5, 0.0, 1.0))
	var loop_r := loop_h * 0.5

	# Color: neutral → green approaching window → hold green during grace → red after
	var line_col: Color
	var loop_col: Color
	if past_grace > 0.0:
		var t: float = clampf(past_grace / 0.30, 0.0, 1.0)
		line_col = C_TIGHT.lerp(C_BAD, t)
	elif raw_t < 0.78:
		line_col = C_LINE
	else:
		var t: float = clampf((raw_t - 0.78) / 0.27, 0.0, 1.0)
		line_col = C_LINE.lerp(C_TIGHT, t)
	loop_col = line_col

	# Line length is constant throughout the stroke.
	# The loop divides it into two parallel legs:
	#   upper leg: rod tip → loop leading edge    (grows as loop advances)
	#   lower leg: loop trailing edge → fly       (shrinks as loop advances)
	# When upper_len == max_len the lower_len is 0: line is straight, fly meets the loop.
	var upper_len: float = progress * max_len
	var lower_len: float = (1.0 - progress) * max_len

	if upper_len < loop_r * 2.0:
		# Loop hasn't formed yet — show fly at starting position
		var fly_start := tip - line_dir * lower_len
		draw_circle(fly_start, 4.0, C_FLY)
	else:
		# Upper leg sag: gentle droop proportional to length; extra sag once grace expires
		var upper_sag: float = upper_len * 0.010 + past_grace * upper_len * 0.04
		# Lower leg sag: fly-leg droops more (less taut, older part of line)
		var lower_sag: float = lower_len * 0.022 * (1.0 - progress * 0.6) + past_grace * lower_len * 0.06

		# Loop position at leading edge of cast
		var loop_top := tip + line_dir * upper_len + Vector2(0.0, upper_sag)
		var loop_bot := loop_top + Vector2(0.0, loop_h)
		var loop_ctr := loop_top + Vector2(0.0, loop_r)

		# Fly trails behind the loop, going opposite to cast direction
		var fly_pos := loop_bot - line_dir * lower_len + Vector2(0.0, lower_sag)

		# Upper leg: rod tip → loop top (cast direction)
		draw_line(tip, loop_top, line_col, 1.8)
		# Lower leg: loop bottom → fly (back toward and past rod, opposite direction)
		draw_line(loop_bot, fly_pos, line_col, 1.8)

		# Semicircle at the leading edge — the loop turning point
		if casting._stroke_dir == -1:
			draw_arc(loop_ctr, loop_r, -PI * 0.5, PI * 0.5, 14, loop_col, 2.2)
		else:
			draw_arc(loop_ctr, loop_r, PI * 0.5, PI * 1.5, 14, loop_col, 2.2)

		# Fly at the trailing end of the lower leg
		draw_circle(fly_pos, 4.0, C_FLY)

	# Status and timing cue
	if raw_t >= 0.85 and past_grace <= 0.0:
		# Window: line straight, grace period still active — show green cue
		var cue_pt := tip + line_dir * max_len + Vector2(0.0, 4.0)
		draw_circle(cue_pt, 7.0, Color(C_TIGHT.r, C_TIGHT.g, C_TIGHT.b, 0.85))
		_draw_status(font, "← change direction →", C_TIGHT)
	elif past_grace > 0.0:
		_draw_status(font, "← too late — wide loop →", C_BAD)
	else:
		_draw_status(font, "↓/↑: rhythm   SPACE: release  [%d/%d]" % [
			casting._false_cast_count, CastingController.MIN_FALSE_CASTS
		])


# ---------------------------------------------------------------------------
# Drift — line sags with drag
# ---------------------------------------------------------------------------

func _draw_drift(font: Font) -> void:
	_draw_rod(ANGLE_IDLE, 0.0)
	var tip  := _rod_tip(ANGLE_IDLE)
	var drag := 0.0
	if drift != null:
		drag = drift.drag_factor

	# Line sags in a quadratic droop; more sag = more drag = brighter red
	var line_len := _line_len()
	var end      := tip + Vector2(-line_len, drag * 50.0)
	var ctrl     := tip + Vector2(-line_len * 0.5, drag * 75.0)
	var line_col := C_LINE.lerp(C_BAD, drag * 0.8)

	var pts := PackedVector2Array()
	for i in 12:
		var t   := float(i) / 11.0
		var mt  := 1.0 - t
		pts.append(mt * mt * tip + 2.0 * mt * t * ctrl + t * t * end)
	draw_polyline(pts, line_col, 1.8, true)
	draw_circle(end, 4.0, C_FLY)

	_draw_status(font, "mouse: mend     R: retrieve     drag: %d%%" % int(drag * 100.0))


# ---------------------------------------------------------------------------
# Rod drawing — blank, cork grip, reel, forearm to elbow
# ---------------------------------------------------------------------------

# angle_deg : angle from +x axis; Vector2(cos(a), -sin(a)) gives the tip direction in screen coords
# flex      : signed; positive bows the rod body in the +perp direction (right of rod axis)
func _draw_rod(angle_deg: float, flex: float) -> void:
	var a       := deg_to_rad(angle_deg)
	var rod_dir := Vector2(cos(a), -sin(a))
	var tip     := rod_dir * ROD_LEN
	var butt    := -rod_dir   # direction from grip toward reel end

	# ── Forearm — elbow tracks the butt (opposite end from tip) so the arm sweeps with the rod ──
	# Gravity bias (+y) keeps the elbow from floating unrealistically high on steep backcast angles
	var elbow := butt * 44.0 + Vector2(0.0, 10.0)
	draw_line(Vector2.ZERO, elbow, Color(0.60, 0.48, 0.36), 5.0, true)

	# ── Cork grip — slightly wider and lighter than the blank ──
	var grip_end := butt * 16.0
	draw_line(Vector2.ZERO, grip_end, Color(0.80, 0.70, 0.54), ROD_W + 2.5, true)

	# ── Reel — three concentric circles at the butt end ──
	var reel_pos := butt * 27.0
	draw_circle(reel_pos, 9.5, Color(0.26, 0.26, 0.28))   # outer frame
	draw_circle(reel_pos, 6.5, Color(0.46, 0.46, 0.50))   # spool face
	draw_circle(reel_pos, 2.5, Color(0.20, 0.20, 0.22))   # centre axle

	# ── Rod blank ──
	if absf(flex) < 0.05:
		draw_line(Vector2.ZERO, tip, C_ROD, ROD_W, true)
		return

	# Quadratic Bezier: P0=grip, P1=control, P2=tip
	# Control point displaced perpendicular to rod in the flex direction
	var perp := Vector2(sin(a), cos(a))
	var ctrl := tip * 0.45 + perp * (flex * 22.0)

	var pts := PackedVector2Array()
	for i in 10:
		var t  := float(i) / 9.0
		var mt := 1.0 - t
		pts.append(mt * mt * Vector2.ZERO + 2.0 * mt * t * ctrl + t * t * tip)
	draw_polyline(pts, C_ROD, ROD_W, true)


func _rod_tip(angle_deg: float) -> Vector2:
	var a := deg_to_rad(angle_deg)
	return Vector2(cos(a), -sin(a)) * ROD_LEN


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _line_len() -> float:
	# Scale from ~5% to ~45% of screen width so max line reaches near half-screen
	var half_vp := get_viewport_rect().size.x * 0.45
	if casting == null:
		return half_vp * 0.06
	var t := (casting.line_length - CastingController.LINE_MIN) / \
		(CastingController.LINE_MAX - CastingController.LINE_MIN)
	return lerpf(half_vp * 0.06, half_vp, t)


func _quality_color() -> Color:
	if casting == null:
		return C_LINE
	match casting.cast_quality:
		CastingController.CastQuality.TIGHT:  return C_TIGHT
		CastingController.CastQuality.SLOPPY: return C_SLOPPY
		_:                                    return C_BAD


func _draw_status(font: Font, text: String, col: Color = Color(0.68, 0.68, 0.68)) -> void:
	# y=52 clears the reel (which sits ~35 px below origin for most rod angles)
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	draw_string(font, Vector2(-w * 0.5, 52.0), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)


# Vertical line-length bar beside the grip
func _draw_bar() -> void:
	if casting == null:
		return
	const BX:    float = 32.0
	const BAR_H: float = 50.0
	var font := ThemeDB.fallback_font

	var fill := (casting.line_length - CastingController.LINE_MIN) / \
			(CastingController.LINE_MAX - CastingController.LINE_MIN)

	# Background track
	draw_line(Vector2(BX, 4.0), Vector2(BX, -BAR_H), Color(0.22, 0.22, 0.22), 5.0)

	# Fill — color shifts toward target color when line is close to required length
	var bar_col := Color(0.55, 0.80, 1.00)
	if target_line_length > 0.0:
		var err := absf(casting.line_length - target_line_length) / \
				(CastingController.LINE_MAX - CastingController.LINE_MIN)
		bar_col = bar_col.lerp(C_TARGET, clampf(1.0 - err * 6.0, 0.0, 1.0))

	draw_line(Vector2(BX, 4.0), Vector2(BX, -BAR_H * fill), bar_col, 5.0)

	# Target notch — horizontal tick showing required line length
	if target_line_length > 0.0:
		var t_frac := (target_line_length - CastingController.LINE_MIN) / \
				(CastingController.LINE_MAX - CastingController.LINE_MIN)
		var notch_y := -BAR_H * t_frac
		draw_line(Vector2(BX - 5.0, notch_y), Vector2(BX + 5.0, notch_y), C_TARGET, 2.0)
		# Small label
		draw_string(font, Vector2(BX + 7.0, notch_y + 4.0), "%.0f" % target_line_length,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 9, C_TARGET)

	draw_string(font, Vector2(BX + 4.0, -BAR_H + 4.0), "%.0f" % casting.line_length,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.65, 0.75, 0.88))
