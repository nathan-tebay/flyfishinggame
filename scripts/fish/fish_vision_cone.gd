class_name FishVisionCone
extends Node2D

# Top-down fish vision display.
# Draws the forward danger oval — the region the fish can see through Snell's
# window.  Red tint signals "don't approach from here."
# Opacity scales with difficulty telegraph strength.

var _half_blind_rad: float = deg_to_rad(30.0)   # half-angle of rear blind zone (clips arc)
var _vis_rx: float   = 120.0   # forward oval x-radius (along body axis)
var _vis_ry: float   =  55.0   # forward oval y-radius (lateral spread)
var _fill_alpha: float = 0.12
var _edge_alpha: float = 0.30


func setup(config: DifficultyConfig) -> void:
	_half_blind_rad = deg_to_rad(config.blind_spot_half_angle)
	# Forward oval: lateral spread scales with vision_cone_half_angle.
	# Wider cone angle → fish sees more to the sides → larger oval y-radius.
	var cone_rad := deg_to_rad(config.vision_cone_half_angle)
	_vis_rx = 120.0                              # fixed forward depth (px)
	_vis_ry = _vis_rx * sin(cone_rad) * 0.75    # lateral spread from angle
	_vis_ry = clampf(_vis_ry, 35.0, 80.0)
	# Larger telegraph = more visible cues for the player
	_fill_alpha = 0.07 + config.fish_telegraph_strength * 0.14
	_edge_alpha = _fill_alpha * 2.2
	queue_redraw()


func _draw() -> void:
	# --- Forward danger oval (Snell's window projection) — red tint ----------
	# Built as a half-ellipse arc in front of the fish (-x side),
	# clipped by the blind-spot edge angles so it doesn't overlap.
	var danger_col_fill := Color(0.90, 0.18, 0.12, _fill_alpha * 0.85)
	var danger_col_edge := Color(0.90, 0.18, 0.12, _edge_alpha)

	# Blind spot spans ±_half_blind_rad around +x (tail direction, angle 0).
	# The danger arc is everything outside that wedge, centred on -x (head = PI).
	# Going from just below the +x blind-spot edge, all the way around the front
	# (-x) and back up to just above the +x blind-spot edge.
	var start_a := _half_blind_rad         # bottom edge of blind spot (≈ 30°)
	var end_a   := TAU - _half_blind_rad   # top edge of blind spot (≈ 330°)

	const STEPS := 28
	var arc_pts := PackedVector2Array()
	arc_pts.append(Vector2.ZERO)
	for i in (STEPS + 1):
		var t := float(i) / float(STEPS)
		var a := start_a + t * (end_a - start_a)
		# Oval biased forward: x-radius is full vis_rx, y-radius is narrower
		arc_pts.append(Vector2(cos(a) * _vis_rx, sin(a) * _vis_ry))
	draw_colored_polygon(arc_pts, danger_col_fill)

	# Boundary lines from fish centre to the edges of the danger arc
	var edge_bot := Vector2(cos(start_a) * _vis_rx, sin(start_a) * _vis_ry)
	var edge_top := Vector2(cos(end_a)   * _vis_rx, sin(end_a)   * _vis_ry)
	draw_line(Vector2.ZERO, edge_bot, danger_col_edge, 1.0)
	draw_line(Vector2.ZERO, edge_top, danger_col_edge, 1.0)
