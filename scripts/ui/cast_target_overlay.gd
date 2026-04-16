class_name CastTargetOverlay
extends Node2D

# World-space position of the cast target. Set to Vector2(-1, -1) when cleared.
var target:        Vector2 = Vector2(-1.0, -1.0)
var required_line: float   = 0.0   # tiles — line length needed to reach target
var line_fraction: float   = 0.0   # 0 = min cast, 1 = max cast
var angler_pos:    Vector2 = Vector2.ZERO

const C_NEAR := Color(0.30, 0.90, 0.30, 0.90)   # green — short cast
const C_FAR  := Color(0.95, 0.20, 0.15, 0.90)   # red   — max cast


func _process(_delta: float) -> void:
	if target.x >= 0.0:
		queue_redraw()


func _draw() -> void:
	if target.x < 0.0:
		return

	var c: Color = C_NEAR.lerp(C_FAR, line_fraction)
	var c_dim := Color(c.r, c.g, c.b, 0.22)
	var c_mid := Color(c.r, c.g, c.b, 0.55)
	var c_dot := Color(c.r, c.g, c.b, 0.30)

	# Thin guide line from angler to target
	draw_line(angler_pos, target, c_dim, 1.0)

	# Landing ring
	draw_arc(target, 10.0, 0.0, TAU, 28, c, 1.5)
	draw_circle(target, 3.0, c_dot)

	# Crosshair
	draw_line(target + Vector2(-16.0, 0.0), target + Vector2(-6.0, 0.0),  c, 1.2)
	draw_line(target + Vector2( 6.0,  0.0), target + Vector2(16.0, 0.0),  c, 1.2)
	draw_line(target + Vector2(0.0, -16.0), target + Vector2(0.0,  -6.0), c, 1.2)
	draw_line(target + Vector2(0.0,   6.0), target + Vector2(0.0,  16.0), c, 1.2)

	# Downstream drift arrow
	var drift_len := 28.0
	var dt := target + Vector2(drift_len, 0.0)
	draw_line(target + Vector2(12.0, 0.0), dt, c_mid, 1.2)
	draw_line(dt, dt + Vector2(-5.0, -3.5), c_mid, 1.2)
	draw_line(dt, dt + Vector2(-5.0,  3.5), c_mid, 1.2)

	# Required distance label
	var font := ThemeDB.fallback_font
	var label := "~%.0f ft" % (required_line * RiverConstants.FEET_PER_TILE)
	draw_string(font, target + Vector2(14.0, -6.0), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, c)
