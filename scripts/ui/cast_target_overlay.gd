class_name CastTargetOverlay
extends Node2D

# World-space position of the cast target. Set to Vector2(-1, -1) when cleared.
var target:        Vector2 = Vector2(-1.0, -1.0)
var required_line: float   = 0.0   # tiles — line length needed to reach target
var angler_pos:    Vector2 = Vector2.ZERO

const C_TARGET := Color(0.70, 0.95, 0.40, 0.90)   # yellow-green


func _process(_delta: float) -> void:
	if target.x >= 0.0:
		queue_redraw()


func _draw() -> void:
	if target.x < 0.0:
		return

	# Thin guide line from angler to target
	draw_line(angler_pos, target, Color(C_TARGET.r, C_TARGET.g, C_TARGET.b, 0.22), 1.0)

	# Landing ring
	draw_arc(target, 10.0, 0.0, TAU, 28, C_TARGET, 1.5)
	draw_circle(target, 3.0, Color(C_TARGET.r, C_TARGET.g, C_TARGET.b, 0.30))

	# Crosshair
	draw_line(target + Vector2(-16.0, 0.0), target + Vector2(-6.0, 0.0),  C_TARGET, 1.2)
	draw_line(target + Vector2( 6.0,  0.0), target + Vector2(16.0, 0.0),  C_TARGET, 1.2)
	draw_line(target + Vector2(0.0, -16.0), target + Vector2(0.0,  -6.0), C_TARGET, 1.2)
	draw_line(target + Vector2(0.0,   6.0), target + Vector2(0.0,  16.0), C_TARGET, 1.2)

	# Downstream drift arrow — fly floats right (+x) after landing
	var drift_len := 28.0
	var dt := target + Vector2(drift_len, 0.0)
	draw_line(target + Vector2(12.0, 0.0), dt, Color(C_TARGET.r, C_TARGET.g, C_TARGET.b, 0.55), 1.2)
	draw_line(dt, dt + Vector2(-5.0, -3.5), Color(C_TARGET.r, C_TARGET.g, C_TARGET.b, 0.55), 1.2)
	draw_line(dt, dt + Vector2(-5.0,  3.5), Color(C_TARGET.r, C_TARGET.g, C_TARGET.b, 0.55), 1.2)

	# Required distance label (convert tiles to approximate feet: 1 tile ≈ 3 ft)
	var font := ThemeDB.fallback_font
	var label := "~%.0f ft" % (required_line * 3.0)
	draw_string(font, target + Vector2(14.0, -6.0), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, C_TARGET)
