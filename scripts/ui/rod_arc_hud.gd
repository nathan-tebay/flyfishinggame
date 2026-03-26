class_name RodArcHUD
extends Node2D

# Bottom-left HUD — draws rod arc, fly line, loop quality indicator,
# line-length bar, and cast state hint text. All via _draw().

const ROD_LEN  := 65.0
const ROD_W    := 3.5
const LINE_LEN := 90.0
const BAR_H    := 46.0   # line length indicator bar height

const C_ROD   := Color(0.55, 0.38, 0.18)   # wood brown
const C_LINE  := Color(0.88, 0.84, 0.72)   # cream
const C_TIGHT := Color(0.20, 0.90, 0.35)   # green
const C_SLOPPY:= Color(0.95, 0.82, 0.15)  # yellow
const C_BAD   := Color(0.90, 0.22, 0.18)   # red
const C_FLY   := Color(0.85, 0.38, 0.10)   # orange-brown

var casting: CastingController = null
var drift: DriftController = null


func _ready() -> void:
	var vp  := get_viewport_rect().size
	position = Vector2(72.0, vp.y - 25.0)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font

	if casting == null:
		_draw_rod(100.0)
		_draw_idle_line()
		_draw_status(font, "casting inactive")
		_draw_bar()
		return

	match casting.state:
		CastingController.State.IDLE:
			_draw_rod(100.0)
			_draw_idle_line()
			_draw_status(font, "F:feed  R:strip  ↓/↑:cast")

		CastingController.State.FALSE_CASTING:
			_draw_false_casting(font)

		CastingController.State.PRESENTATION:
			_draw_rod(68.0)
			draw_line(_rod_tip(68.0), _rod_tip(68.0) + Vector2(LINE_LEN, 0.0), C_LINE, 1.5)
			_draw_status(font, "Presenting…")

		CastingController.State.RESULT:
			var qcol := _quality_color()
			_draw_rod(72.0)
			var tip := _rod_tip(72.0)
			draw_line(tip, tip + Vector2(LINE_LEN, 0.0), qcol, 2.0)
			draw_circle(tip + Vector2(LINE_LEN, 0.0), 6.0, qcol)
			var qlabels := ["TIGHT LOOP!", "SLOPPY LOOP", "BAD CAST"]
			_draw_status(font, qlabels[casting.cast_quality], qcol)

		CastingController.State.DRIFT:
			_draw_drift(font)

	_draw_bar()


# ---------------------------------------------------------------------------
# Draw helpers
# ---------------------------------------------------------------------------

func _rod_tip(angle_deg: float) -> Vector2:
	var a := deg_to_rad(angle_deg)
	return Vector2(cos(a), -sin(a)) * ROD_LEN


func _draw_rod(angle_deg: float) -> void:
	draw_line(Vector2.ZERO, _rod_tip(angle_deg), C_ROD, ROD_W, true)


func _draw_idle_line() -> void:
	var tip := _rod_tip(100.0)
	draw_line(tip, tip + Vector2(LINE_LEN * 0.45, 12.0), C_LINE, 1.5)


func _draw_false_casting(font: Font) -> void:
	var rod_angle := 126.0 if casting._stroke_dir == -1 else 62.0
	_draw_rod(rod_angle)
	var tip := _rod_tip(rod_angle)
	var dir := Vector2(cos(deg_to_rad(rod_angle)), -sin(deg_to_rad(rod_angle)))

	# Line extends as stroke timer approaches load time
	var load     := casting._load_time()
	var progress := clampf(casting._stroke_timer / load, 0.0, 1.0)
	var line_end := tip + dir * (LINE_LEN * progress)

	# Color shifts to yellow approaching the timing cue
	var line_col := C_LINE.lerp(Color.YELLOW, maxf(0.0, (progress - 0.75) / 0.25))
	draw_line(tip, line_end, line_col, 1.5)

	# Dot at line tip; highlighted when timing window is active (>80%)
	if progress >= 0.80:
		draw_circle(line_end, 5.0, Color(1.0, 1.0, 0.0, 0.88))
	else:
		draw_circle(line_end, 3.0, C_LINE)

	_draw_status(font, "↓/↑:rhythm  SPACE:release [%d/%d]" % [
		casting._false_cast_count, CastingController.MIN_FALSE_CASTS
	])


func _draw_drift(font: Font) -> void:
	_draw_rod(78.0)
	var tip  := _rod_tip(78.0)
	var mid  := tip + Vector2(LINE_LEN * 0.55, 10.0)
	var end  := tip + Vector2(LINE_LEN, 22.0)

	var drag := 0.0
	if drift != null:
		drag = drift.drag_factor
	var line_col := C_LINE.lerp(C_BAD, drag)

	draw_line(tip, mid, line_col, 1.5)
	draw_line(mid, end, line_col, 1.5)
	draw_circle(end, 3.5, C_FLY)

	_draw_status(font, "mouse:mend  R:retrieve  drag:%d%%" % int(drag * 100.0))


func _quality_color() -> Color:
	if casting == null:
		return C_LINE
	match casting.cast_quality:
		CastingController.CastQuality.TIGHT:  return C_TIGHT
		CastingController.CastQuality.SLOPPY: return C_SLOPPY
		_:                                    return C_BAD


func _draw_status(font: Font, text: String, col: Color = Color(0.70, 0.70, 0.70)) -> void:
	draw_string(font, Vector2(-12.0, -82.0), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col)


# Vertical bar on the left: filled proportional to line length
func _draw_bar() -> void:
	if casting == null:
		return
	const BX   := -24.0
	var fill := (casting.line_length - CastingController.LINE_MIN) / \
		(CastingController.LINE_MAX - CastingController.LINE_MIN)
	draw_line(Vector2(BX, 3.0), Vector2(BX, -BAR_H),        Color(0.22, 0.22, 0.22), 5.0)
	draw_line(Vector2(BX, 3.0), Vector2(BX, -BAR_H * fill), Color(0.55, 0.80, 1.00), 5.0)
