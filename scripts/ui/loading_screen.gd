extends Node2D

# Full-screen loading overlay drawn via _draw() — shown while the first section
# generates and renders.  Matches the SessionConfig colour palette.

func _draw() -> void:
	var vp   := get_viewport_rect().size
	var cx   := vp.x * 0.5
	var cy   := vp.y * 0.5
	var font := ThemeDB.fallback_font

	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.05, 0.09, 0.16))

	draw_string(font, Vector2(cx - 210.0, cy - 14.0),
		"GENERATING RIVER...",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(0.55, 0.70, 0.88))

	draw_string(font, Vector2(cx - 124.0, cy + 24.0),
		"reading the water",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.38, 0.52, 0.64))
