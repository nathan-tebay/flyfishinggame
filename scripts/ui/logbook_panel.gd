class_name LogbookPanel
extends Node2D

# Catch logbook HUD panel.
# [L] — open / close
# [S] — cycle sort mode (Caught / Size / Species)
# Shows up to MAX_VISIBLE entries with mini fish photos.

const ENTRY_H    := 72.0
const PANEL_W    := 520.0
const MAX_VISIBLE := 6

var catch_log: CatchLog = null


func _ready() -> void:
	visible = false
	var vp  := get_viewport_rect().size
	position = Vector2(vp.x * 0.5, vp.y * 0.5)


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and (event as InputEventKey).pressed):
		return
	var kc := (event as InputEventKey).physical_keycode
	if kc == KEY_L:
		visible = not visible
		queue_redraw()
	elif visible and kc == KEY_S:
		if catch_log:
			catch_log.cycle_sort()
			queue_redraw()


func _draw() -> void:
	var font    := ThemeDB.fallback_font
	var catches: Array = []
	if catch_log:
		catches = catch_log.sorted_catches()

	var rows    := mini(catches.size(), MAX_VISIBLE)
	var ph      := 50.0 + (maxf(float(rows), 1.0)) * ENTRY_H
	var px      := -PANEL_W * 0.5
	var py      := -ph * 0.5

	# Background + border
	draw_rect(Rect2(px, py, PANEL_W, ph), Color(0.04, 0.04, 0.08, 0.93))
	draw_rect(Rect2(px, py, PANEL_W, ph), Color(0.55, 0.55, 0.60, 0.65), false, 1.5)

	# Title bar
	var sort_name := catch_log.sort_mode_name() if catch_log else "CAUGHT"
	var count     := catches.size()
	var title := "LOGBOOK  (%d caught)   Sort: %s [S]" % [count, sort_name]
	draw_string(font, Vector2(px + 10.0, py + 20.0), title,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.85, 0.85, 0.90))
	draw_line(Vector2(px, py + 26.0), Vector2(px + PANEL_W, py + 26.0),
		Color(0.38, 0.38, 0.44, 0.8), 1.0)

	if catches.is_empty():
		draw_string(font, Vector2(px + 16.0, py + 56.0),
			"No catches yet — go fish!",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.50, 0.50, 0.58))
	else:
		for i in range(rows):
			var e: Dictionary = catches[i]
			_draw_entry(font, e, px + 8.0, py + 34.0 + float(i) * ENTRY_H)

	# Footer
	var footer := "[L] close"
	draw_string(font, Vector2(-font.get_string_size(footer, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x * 0.5,
		py + ph - 8.0), footer, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.40, 0.40, 0.48))


func _draw_entry(font: Font, e: Dictionary, ex: float, ey: float) -> void:
	# Mini fish photo
	var photo: Dictionary = e["photo"]
	if not photo.is_empty():
		_draw_mini_fish(photo, ex + 32.0, ey + 32.0)

	# Entry text
	var tx         := ex + 72.0
	var species: String = e["species"]
	var size_cm: float  = e["size_cm"]
	var fly:     String = e["fly_name"]
	var fly_stg: String = e["fly_stage"]
	var tod:     String = e["time_of_day"]
	var hatch:   String = (e["hatch_state"] as String).replace("_", " ").capitalize()

	draw_string(font, Vector2(tx, ey + 16.0),
		"%s — %.0f cm" % [species, size_cm],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.92, 0.88, 0.65))
	draw_string(font, Vector2(tx, ey + 32.0),
		"Fly: %s (%s)" % [fly, fly_stg],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.75, 0.75, 0.82))
	draw_string(font, Vector2(tx, ey + 46.0),
		"%s  |  Hatch: %s" % [tod, hatch],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.58, 0.65, 0.72))

	# Row separator
	draw_line(Vector2(ex - 4.0, ey + ENTRY_H - 4.0),
			  Vector2(ex + PANEL_W - 16.0, ey + ENTRY_H - 4.0),
			  Color(0.25, 0.25, 0.30, 0.55), 1.0)


func _draw_mini_fish(photo: Dictionary, cx: float, cy: float) -> void:
	var bw:  float = (photo["body_w"] as float) * 0.55
	var bh:  float = (photo["body_h"] as float) * 0.55
	var col: Color = photo["base_color"]
	col.a = 0.92

	var pts := PackedVector2Array()
	for i in 10:
		var a := float(i) / 10.0 * TAU
		pts.append(Vector2(cx + cos(a) * bw, cy + sin(a) * bh))
	draw_colored_polygon(pts, col)

	var tcol := Color(col.r, col.g, col.b, 0.72)
	draw_colored_polygon(PackedVector2Array([
		Vector2(cx + bw * 0.65, cy),
		Vector2(cx + bw + 5.0,  cy - bh * 0.85),
		Vector2(cx + bw + 5.0,  cy + bh * 0.85),
	]), tcol)
