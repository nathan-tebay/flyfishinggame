class_name RodArcHUD
extends Node2D

## Casting indicator — centered at screen bottom.
## Shows: rod arc with flex, fly line rolling out with loop, timing cue, drag sag.

const ROD_LEN  := 88.0   # grip to tip
const ROD_W    := 3.5

# Rod angles (degrees from +x, counterclockwise = upward in screen coords)
# Angler faces upstream (left), so forward cast goes left, backcast goes right.
const ANGLE_FORWARD  := 58.0   # forward cast: rod upper-left
const ANGLE_BACK     := 132.0  # backcast:     rod upper-right
const ANGLE_IDLE     := 74.0   # idle/drift:   rod slightly left of vertical
const ANGLE_PRESENT  := 52.0   # presentation: rod reaching toward water

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
	position = Vector2(vp.x * 0.5, vp.y - 100.0)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font

	if casting == null:
		_draw_rod(ANGLE_IDLE, 0.0)
		var idle_tip := _rod_tip(ANGLE_IDLE)
		draw_line(idle_tip, idle_tip + Vector2(-30.0, 12.0), C_LINE, 1.5)
		return

	match casting.state:
		CastingController.State.IDLE:
			_draw_rod(ANGLE_IDLE, 0.0)
			var tip := _rod_tip(ANGLE_IDLE)
			draw_line(tip, tip + Vector2(-_line_len() * 0.35, 12.0), C_LINE, 1.5)
			_draw_status(font, "F: feed     R: strip     ↓/↑: cast")

		CastingController.State.FALSE_CASTING:
			_draw_false_casting(font)

		CastingController.State.PRESENTATION:
			_draw_rod(ANGLE_PRESENT, 0.0)
			var tip := _rod_tip(ANGLE_PRESENT)
			# Line unrolling toward target (left/upstream)
			draw_line(tip, tip + Vector2(-_line_len(), 0.0), C_LINE, 1.5)
			_draw_status(font, "Presenting…")

		CastingController.State.RESULT:
			var qcol := _quality_color()
			_draw_rod(ANGLE_PRESENT, 0.0)
			var tip := _rod_tip(ANGLE_PRESENT)
			var line_end := tip + Vector2(-_line_len(), 0.0)
			draw_line(tip, line_end, qcol, 2.0)
			draw_circle(line_end, 6.0, qcol)
			var qlabels := ["TIGHT LOOP", "SLOPPY LOOP", "BAD CAST"]
			_draw_status(font, qlabels[casting.cast_quality], qcol)

		CastingController.State.DRIFT:
			_draw_drift(font)

	_draw_bar()


# ---------------------------------------------------------------------------
# False casting — line rolls out then lies flat, rod flexes under load
# ---------------------------------------------------------------------------

func _draw_false_casting(font: Font) -> void:
	var rod_angle := ANGLE_BACK if casting._stroke_dir == -1 else ANGLE_FORWARD
	var load      := casting._load_time()
	var progress  := clampf(casting._stroke_timer / load, 0.0, 1.0)

	# Rod flexes when loaded (line is fully stretched and pulling)
	var flex := clampf((progress - 0.70) / 0.30, 0.0, 1.0)
	_draw_rod(rod_angle, flex * (1 if casting._stroke_dir == -1 else -1))

	var tip := _rod_tip(rod_angle)

	# Line extends in the cast direction as it rolls out
	# Backcast goes RIGHT (+x), forward cast goes LEFT (-x)
	var line_dir := Vector2(1.0, 0.0) if casting._stroke_dir == -1 else Vector2(-1.0, 0.0)
	var max_len  := _line_len()
	var cur_len  := max_len * progress

	if cur_len < 8.0:
		# Line just leaving rod tip
		draw_circle(tip, 3.0, C_LINE)
	else:
		# Laid-out portion of line (behind the rolling loop)
		var loop_r  := 9.0
		var loop_pt := tip + line_dir * (cur_len - loop_r * 2.0)
		loop_pt.y  -= loop_r * 0.4  # slight vertical offset for arc shape
		draw_line(tip, loop_pt, C_LINE if progress < 0.88 else C_CUE, 1.8)

		# Rolling loop at leading edge — a small half-arc
		var loop_col := C_LINE.lerp(C_CUE, maxf(0.0, (progress - 0.75) / 0.25))
		if casting._stroke_dir == -1:
			draw_arc(loop_pt, loop_r, -PI * 0.5, PI * 0.5, 12, loop_col, 2.0)
		else:
			draw_arc(loop_pt, loop_r, PI * 0.5, PI * 1.5, 12, loop_col, 2.0)

	# ── Timing cue ──
	# When line is flat (fully extended) the loop lands and line lies perpendicular
	# to the rod. Bright cue dot + brightened line signal the direction-change window.
	if progress >= 0.88:
		var flat_pt := tip + line_dir * max_len
		flat_pt.y  -= 2.0
		draw_circle(flat_pt, 7.0, Color(C_CUE.r, C_CUE.g, C_CUE.b, 0.82))
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
	var tip   := _rod_tip(ANGLE_IDLE)
	var drag  := 0.0
	if drift != null:
		drag = drift.drag_factor

	# Line sags in a quadratic droop; more sag = more drag = brighter red
	var line_len := _line_len()
	var end      := tip + Vector2(-line_len, drag * 40.0)
	var ctrl     := tip + Vector2(-line_len * 0.5, drag * 60.0)
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
# Rod drawing with Bezier flex
# ---------------------------------------------------------------------------

# angle_deg: angle from +x axis (counterclockwise = up on screen)
# flex:  signed flex amount; positive bends rod to the right, negative to the left
func _draw_rod(angle_deg: float, flex: float) -> void:
	var a   := deg_to_rad(angle_deg)
	var tip := Vector2(cos(a), -sin(a)) * ROD_LEN

	if absf(flex) < 0.05:
		draw_line(Vector2.ZERO, tip, C_ROD, ROD_W, true)
		return

	# Quadratic Bezier: P0=grip, P1=control, P2=tip
	# Control point displaced perpendicular to the rod, in the flex direction
	var perp := Vector2(sin(a), cos(a))  # perpendicular (rotated 90°)
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
	if casting == null:
		return 80.0
	var t := (casting.line_length - CastingController.LINE_MIN) / \
		(CastingController.LINE_MAX - CastingController.LINE_MIN)
	return lerpf(52.0, 155.0, t)


func _quality_color() -> Color:
	if casting == null:
		return C_LINE
	match casting.cast_quality:
		CastingController.CastQuality.TIGHT:  return C_TIGHT
		CastingController.CastQuality.SLOPPY: return C_SLOPPY
		_:                                    return C_BAD


func _draw_status(font: Font, text: String, col: Color = Color(0.68, 0.68, 0.68)) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	draw_string(font, Vector2(-w * 0.5, 28.0), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)


# Vertical line-length bar beside the grip
func _draw_bar() -> void:
	if casting == null:
		return
	const BX   := 28.0
	const BAR_H := 50.0
	var fill := (casting.line_length - CastingController.LINE_MIN) / \
		(CastingController.LINE_MAX - CastingController.LINE_MIN)
	draw_line(Vector2(BX, 4.0),  Vector2(BX, -BAR_H),         Color(0.22, 0.22, 0.22), 5.0)
	draw_line(Vector2(BX, 4.0),  Vector2(BX, -BAR_H * fill),  Color(0.55, 0.80, 1.00), 5.0)
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(BX + 4.0, -BAR_H + 4.0), "%.0f" % casting.line_length,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.65, 0.75, 0.88))
