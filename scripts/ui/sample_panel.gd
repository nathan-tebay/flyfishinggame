class_name SamplePanel
extends Node2D

# Context popup showing net sample insect abundance.
# Abundance bars shown on Arcade/Standard; names only on Sim.
# Auto-dismisses after DISPLAY_DURATION seconds.

const DISPLAY_DURATION := 8.0
const BAR_MAX_W        := 90.0
const LINE_H           := 22.0
const PANEL_W          := 230.0

var _results:   Array = []
var _show_bars: bool  = true
var _timer:     float = 0.0


func show_results(results: Array, show_bars: bool) -> void:
	_results   = results
	_show_bars = show_bars
	_timer     = DISPLAY_DURATION
	visible    = true
	queue_redraw()


func _ready() -> void:
	visible = false
	var vp  := get_viewport_rect().size
	position = Vector2(vp.x * 0.5, 120.0)


func _process(delta: float) -> void:
	if _timer > 0.0:
		_timer -= delta
		if _timer <= 0.0:
			visible = false


func _draw() -> void:
	if _results.is_empty():
		return

	var font    := ThemeDB.fallback_font
	var rows: int = _results.size()
	var panel_h := 36.0 + rows * LINE_H
	var px := -PANEL_W * 0.5

	# Background
	draw_rect(Rect2(px, 0.0, PANEL_W, panel_h),
		Color(0.05, 0.05, 0.10, 0.88))
	draw_rect(Rect2(px, 0.0, PANEL_W, panel_h),
		Color(0.55, 0.55, 0.60, 0.65), false, 1.5)

	# Title
	draw_string(font, Vector2(px + 10.0, 18.0), "NET SAMPLE",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.85, 0.85, 0.90))

	for i in range(rows):
		var e: Dictionary = _results[i]
		var stage:     String = e["stage"]
		var species:   String = e["species"]
		var abundance: float  = e["abundance"]
		var label := "%s %s" % [stage.capitalize(), species.capitalize()]
		var ry := 36.0 + i * LINE_H

		draw_string(font, Vector2(px + 8.0, ry + 13.0), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.80, 0.80, 0.85))

		if _show_bars:
			var bar_x  := px + 128.0
			var bar_w  := BAR_MAX_W * abundance
			# Track
			draw_rect(Rect2(bar_x, ry + 3.0, BAR_MAX_W, 10.0),
				Color(0.18, 0.18, 0.22))
			# Fill
			var fill_col := Color(0.28, 0.72, 0.45)
			if abundance < 0.35:
				fill_col = Color(0.55, 0.72, 0.28)
			draw_rect(Rect2(bar_x, ry + 3.0, bar_w, 10.0), fill_col)
