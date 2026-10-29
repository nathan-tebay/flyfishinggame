class_name CastingMinigamePanel
extends Control

# Side-view casting guide. Draws a simplified angler and the fly line unfurling on
# each stroke. The line runs RED while the loop is still curled and turns GREEN as
# it straightens — green is the cue to reverse the stroke. Forward strokes unfurl in
# front of the angler, backcasts behind. A load bar tracks how loaded the line is;
# once LOADED, lowering the rod on a forward stroke delivers the cast.

var gesture_state: String = "idle"
var line_load: float = 0.0
var loop_quality: String = "none"
var unroll_progress: float = 0.0     # 0 = just reversed, ~1 = loop straight (reverse now)
var stroke_dir: String = ""          # "back" or "forward"
var ready_to_deliver: bool = false
var loop_position: float = 0.0       # [0, 1] where loop is along the line
var loop_width: float = 0.08         # meters, for visual feedback on tightness

const COL_BG        := Color(0.02, 0.05, 0.03, 0.55)
const COL_TEXT      := Color(0.82, 0.96, 0.82, 0.96)
const COL_TEXT_DIM  := Color(0.55, 0.64, 0.55, 0.75)
const COL_PHASE     := Color(0.74, 0.94, 1.00, 0.96)
const COL_ANGLER    := Color(0.62, 0.66, 0.60, 0.95)
const COL_ROD       := Color(0.85, 0.82, 0.70, 0.98)
const COL_RED       := Color(0.93, 0.27, 0.22, 1.0)
const COL_YELLOW    := Color(0.95, 0.85, 0.25, 1.0)
const COL_GREEN     := Color(0.32, 0.92, 0.36, 1.0)
const COL_ORANGE    := Color(0.98, 0.55, 0.18, 1.0)
const COL_LOAD_FILL := Color(0.30, 0.78, 0.35, 1.0)
const COL_LOAD_OVER := Color(0.95, 0.45, 0.20, 1.0)
const COL_LOAD_TGT  := Color(1.00, 0.93, 0.23, 1.0)


func _draw() -> void:
	var w := size.x
	var h := size.y
	if w < 40.0 or h < 30.0:
		return
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, size), COL_BG, true)

	var casting := gesture_state in ["backcast", "forward", "lifting_roll"]
	# Short angler tucked low-centre; the rod + line own the panel.
	var ground_y := h * 0.90
	var angler_x := w * 0.46
	var tip := _draw_angler(angler_x, ground_y, h * 0.42)

	if casting:
		var dir := -1.0 if stroke_dir == "back" else 1.0
		_draw_unfurling_line(tip, dir, w)
		_draw_loop_indicator(tip, dir, w, h)
		draw_string(font, Vector2(16.0, h * 0.18), _phase_text(),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COL_PHASE)
		if unroll_progress >= 0.82 and unroll_progress <= 1.18:
			draw_string(font, Vector2(w * 0.46 - 36.0, h * 0.18), "REVERSE",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 15, COL_GREEN)
	else:
		draw_string(font, Vector2(16.0, h * 0.18), "RAISE ROD (mouse up) TO START CASTING",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COL_TEXT_DIM)

	_draw_load_bar(Rect2(w * 0.66, h * 0.14, w * 0.26, 12.0))

	draw_string(font, Vector2(16.0, h - 8.0),
		"Reverse each stroke as the line turns GREEN  ·  false-cast to load  ·  deliver on a forward stroke when LOADED",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 9, COL_TEXT_DIM)


# Draws a small side-view angler; returns the rod-tip position. `s` ~ figure height.
func _draw_angler(ax: float, ground_y: float, s: float) -> Vector2:
	var hip := Vector2(ax, ground_y - s * 0.42)
	var shoulder := Vector2(ax, ground_y - s * 0.88)
	draw_line(hip, Vector2(ax - s * 0.16, ground_y), COL_ANGLER, 2.5)
	draw_line(hip, Vector2(ax + s * 0.16, ground_y), COL_ANGLER, 2.5)
	draw_line(hip, shoulder, COL_ANGLER, 3.0)
	draw_circle(shoulder + Vector2(0.0, -s * 0.12), s * 0.10, COL_ANGLER)
	# Casting arm + a prominent rod angled up-forward from the hand.
	var elbow := shoulder + Vector2(s * 0.16, s * 0.16)
	var hand := elbow + Vector2(s * 0.22, -s * 0.04)
	draw_line(shoulder, elbow, COL_ANGLER, 2.5)
	draw_line(elbow, hand, COL_ANGLER, 2.5)
	var tip := hand + Vector2(s * 0.34, -s * 0.92)
	draw_line(hand, tip, COL_ROD, 2.5)
	return tip


# Draws the fly line as a smooth cubic-Bézier loop unrolling from the rod tip in the
# stroke direction. The loop opens (high nose, fly trailing) when freshly reversed and
# flattens into a taut straight line as unroll_progress -> 1, recolouring red -> green.
func _draw_unfurling_line(tip: Vector2, dir: float, w: float) -> void:
	var prog := clampf(unroll_progress, 0.0, 1.45)
	var straight := clampf(prog, 0.0, 1.0)
	var reach := minf(w * 0.42, 360.0)
	var col := _unfurl_color(prog)

	var loop_h := (1.0 - straight) * (reach * 0.34) + 5.0   # nose height; flattens taut
	var ext := reach * (0.05 + 0.95 * straight)             # how far the fly has shot out
	var p0 := tip
	var p1 := tip + Vector2(dir * reach * 0.38, -loop_h * 0.75)
	var p2 := tip + Vector2(dir * (reach * 0.26 + ext * 0.62), -loop_h)
	var p3 := tip + Vector2(dir * ext, -5.0)                 # fly

	var segs := 40
	var pts := PackedVector2Array()
	pts.resize(segs + 1)
	for i in range(segs + 1):
		pts[i] = _cubic(p0, p1, p2, p3, float(i) / float(segs))
	draw_polyline(pts, col, 2.5, true)
	draw_circle(p3, 3.0, col)


func _cubic(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var u := 1.0 - t
	return (u * u * u) * p0 + (3.0 * u * u * t) * p1 + (3.0 * u * t * t) * p2 + (t * t * t) * p3


func _unfurl_color(prog: float) -> Color:
	if prog <= 1.0:
		return COL_RED.lerp(COL_YELLOW, clampf(prog / 0.6, 0.0, 1.0)).lerp(
			COL_GREEN, clampf((prog - 0.6) / 0.4, 0.0, 1.0))
	if prog <= 1.18:
		return COL_GREEN
	return COL_GREEN.lerp(COL_ORANGE, clampf((prog - 1.18) / 0.4, 0.0, 1.0))


func _draw_load_bar(rect: Rect2) -> void:
	var font := ThemeDB.fallback_font
	draw_string(font, rect.position + Vector2(0.0, -4.0), "LINE LOAD",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 8, COL_TEXT_DIM)
	var bar := Rect2(rect.position + Vector2(0.0, 4.0), Vector2(rect.size.x, rect.size.y))
	draw_rect(bar, Color(0.06, 0.10, 0.06, 0.85), true)
	var fill := clampf(line_load / 1.2, 0.0, 1.0)
	var fill_col := COL_LOAD_OVER if line_load > 1.1 else COL_LOAD_FILL
	if fill > 0.0:
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * fill, bar.size.y)), fill_col, true)
	# Loaded gate marker at 90%
	var x90 := bar.position.x + bar.size.x * (0.9 / 1.2)
	draw_line(Vector2(x90, bar.position.y - 2.0), Vector2(x90, bar.position.y + bar.size.y + 2.0), COL_LOAD_TGT, 1.4)
	var status := "DELIVER!" if ready_to_deliver else "%d%%" % int(line_load * 100.0)
	var status_col := COL_GREEN if ready_to_deliver else COL_TEXT
	draw_string(font, rect.position + Vector2(rect.size.x + 8.0, rect.size.y),
		status, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, status_col)


func _phase_text() -> String:
	match gesture_state:
		"backcast":
			return "BACKCAST"
		"forward":
			return "FORWARD" + (" — DELIVER" if ready_to_deliver else " (false cast)")
		"lifting_roll":
			return "ROLL — sweep forward"
		_:
			return ""


func _draw_loop_indicator(tip: Vector2, dir: float, w: float, h: float) -> void:
	# Draw loop position indicator below the line
	var font := ThemeDB.fallback_font
	var loop_line_length := w * 0.35
	var indicator_y := h * 0.45

	# Base line showing full line extent
	var base_start := tip + Vector2(dir * 12.0, 0.0)
	var base_end := base_start + Vector2(dir * loop_line_length, 0.0)
	draw_line(base_start, base_end, COL_TEXT_DIM, 1.0)

	# Loop position indicator
	var loop_x = base_start.x + (base_end.x - base_start.x) * loop_position
	var loop_y = indicator_y

	# Color: red (wide/slow) → yellow (medium) → green (tight/fast)
	var loop_color = _color_for_width(loop_width)
	draw_circle(Vector2(loop_x, loop_y), 5.0, loop_color)
	draw_circle(Vector2(loop_x, loop_y), 4.0, Color.BLACK)

	# Label
	var label = "%.0f%%" % (loop_position * 100.0)
	draw_string(font, Vector2(loop_x - 12.0, loop_y + 10.0), label,
		HORIZONTAL_ALIGNMENT_CENTER, -1, 10, COL_TEXT_DIM)


func _color_for_width(width: float) -> Color:
	# Red (wide, slow) → Yellow (medium) → Green (tight, fast)
	# Tighter loop = higher quality
	if width > 0.10:
		return COL_RED
	elif width > 0.06:
		return COL_YELLOW
	else:
		return COL_GREEN
