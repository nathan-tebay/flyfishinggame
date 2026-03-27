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
const C_CUE   := Color(1.00, 0.95, 0.30)  # timing cue highlight

var casting: CastingController = null
var drift:   DriftController   = null


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
			var tip := _rod_tip(ANGLE_PRESENT)
			draw_line(tip, tip + Vector2(-_line_len(), 0.0), C_LINE, 1.5)
			_draw_status(font, "Presenting…")

		CastingController.State.RESULT:
			var qcol    := _quality_color()
			var qloop_h: float = ([10.0, 22.0, 38.0] as Array)[casting.cast_quality]
			_draw_rod(ANGLE_PRESENT, 0.0)
			var tip      := _rod_tip(ANGLE_PRESENT)
			var len      := _line_len()
			var loop_r   := qloop_h * 0.5
			var top_end  := tip + Vector2(-len + loop_r, 0.0)
			var bot_end  := top_end + Vector2(0.0, qloop_h)
			var lc       := top_end + Vector2(0.0, loop_r)
			draw_line(tip, top_end, qcol, 2.0)
			draw_line(tip + Vector2(0.0, qloop_h), bot_end, qcol, 2.0)
			draw_arc(lc, loop_r, PI * 0.5, PI * 1.5, 14, qcol, 2.2)
			draw_circle(lc, 5.0, qcol)
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
	var progress  := clampf(casting._stroke_timer / load, 0.0, 1.0)

	# Rod tip trails behind grip — bends away from cast direction (tip lags due to line inertia)
	# _stroke_dir==-1 (backcast, rod tip upper-left): tip trails RIGHT → perp bows body right → negative flex
	# _stroke_dir==1  (fwd cast, rod tip upper-right): tip trails LEFT → perp bows body left → positive flex
	var flex := clampf((progress - 0.70) / 0.30, 0.0, 1.0)
	_draw_rod(rod_angle, flex * (-1 if casting._stroke_dir == -1 else 1))

	var tip := _rod_tip(rod_angle)

	# _stroke_dir==-1 → backcast, line unrolls RIGHT (+x)
	# _stroke_dir==1  → forward cast, line unrolls LEFT (-x)
	var line_dir := Vector2(1.0, 0.0) if casting._stroke_dir == -1 else Vector2(-1.0, 0.0)
	var max_len  := _line_len()
	var cur_len  := max_len * progress

	# Loop geometry: two legs (rod-leg above, fly-leg below) joined by a semicircle at the leading edge.
	# Physics: loop tightens as it travels outward (wide near rod = energy still forming,
	# narrow at full extension = tight efficient loop).  Legs droop slightly under gravity.
	var loop_h := lerpf(28.0, 12.0, progress)  # narrows from 28→12 px as line extends
	var loop_r  := loop_h * 0.5

	var line_col := C_LINE if progress < 0.88 else C_CUE
	var loop_col := C_LINE.lerp(C_CUE, maxf(0.0, (progress - 0.75) / 0.25))

	if cur_len < loop_r * 2.0:
		draw_circle(tip, 3.0, C_LINE)
	else:
		# Slight gravitational sag — line droops under its own weight over long distances
		var sag := cur_len * 0.014

		# Leading-edge endpoints: where the semicircle connects to each leg
		var top_end     := tip + line_dir * (cur_len - loop_r) + Vector2(0.0, sag)
		var bot_end     := top_end + Vector2(0.0, loop_h)
		var loop_center := top_end + Vector2(0.0, loop_r)

		# Rod-leg — runs from rod tip toward the loop (the freshly moving strand)
		draw_line(tip, top_end, line_col, 1.8)
		# Fly-leg — runs parallel below (the strand being pulled in from the previous stroke)
		draw_line(tip + Vector2(0.0, loop_h), bot_end, line_col, 1.8)

		# Semicircle loop at the leading edge — opens toward the rod (trailing side)
		# Backcast (right): arc from top (-PI/2) to bottom (PI/2) CCW = curves rightward, opens left
		# Fwd cast (left): arc from bottom (PI/2) to top (3PI/2) CCW = curves leftward, opens right
		if casting._stroke_dir == -1:
			draw_arc(loop_center, loop_r, -PI * 0.5, PI * 0.5, 14, loop_col, 2.2)
		else:
			draw_arc(loop_center, loop_r, PI * 0.5, PI * 1.5, 14, loop_col, 2.2)

	# Timing cue — bright dot at full extension signals direction-change window
	if progress >= 0.88:
		var cue_pt := tip + line_dir * max_len + Vector2(0.0, loop_r)
		draw_circle(cue_pt, 7.0, Color(C_CUE.r, C_CUE.g, C_CUE.b, 0.82))
		_draw_status(font, "← change direction →", C_CUE)
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

	# ── Forearm — connects grip (origin) to elbow (fixed body position) ──
	# Elbow sits to the right/downstream of the grip, representing the casting arm
	var elbow := Vector2(44.0, 24.0)
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
	const BX    := 32.0
	const BAR_H := 50.0
	var fill := (casting.line_length - CastingController.LINE_MIN) / \
		(CastingController.LINE_MAX - CastingController.LINE_MIN)
	draw_line(Vector2(BX, 4.0),  Vector2(BX, -BAR_H),         Color(0.22, 0.22, 0.22), 5.0)
	draw_line(Vector2(BX, 4.0),  Vector2(BX, -BAR_H * fill),  Color(0.55, 0.80, 1.00), 5.0)
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(BX + 4.0, -BAR_H + 4.0), "%.0f" % casting.line_length,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.65, 0.75, 0.88))
