class_name FlySelector
extends Node2D

# Bottom-right HUD — shows active fly, swap with Tab.
# Phase 4: display only. Phase 6 wires this into FlyMatcher.

const FLIES: Array  = ["Elk Hair Caddis", "Caddis Pupa"]
const STAGES: Array = ["dry", "emerger"]

var active_fly: int = 0

var _fly_colors: Array = [Color(0.80, 0.60, 0.25), Color(0.35, 0.55, 0.28)]


func fly_name() -> String:
	return FLIES[active_fly]


func fly_stage() -> String:
	return STAGES[active_fly]


func is_dry_fly() -> bool:
	return active_fly == 0


func _ready() -> void:
	var vp  := get_viewport_rect().size
	position = Vector2(vp.x - 120.0, vp.y - 30.0)


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("swap_fly"):
		active_fly = (active_fly + 1) % FLIES.size()
		print("FlySelector: %s (%s)" % [fly_name(), fly_stage()])
		queue_redraw()


func _draw() -> void:
	var font  := ThemeDB.fallback_font
	var name  := fly_name()
	var fsize := 13

	var tw  := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	var bw  := maxf(tw + 28.0, 110.0)
	var bx  := -bw * 0.5

	# Background panel
	draw_rect(Rect2(bx, -26.0, bw, 30.0), Color(0.08, 0.08, 0.10, 0.75))
	draw_rect(Rect2(bx, -26.0, bw, 30.0), Color(0.45, 0.45, 0.50, 0.5), false, 1.0)

	# Fly color dot
	var fcol: Color = _fly_colors[active_fly]
	draw_circle(Vector2(bx + 10.0, -11.0), 5.0, fcol)

	# Fly name
	draw_string(font, Vector2(bx + 20.0, -8.0), name,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color.WHITE)

	# Swap hint
	var hint := "[Tab] swap"
	var hw   := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	draw_string(font, Vector2(-hw * 0.5, 6.0), hint,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.50, 0.50, 0.55))
