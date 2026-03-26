class_name FishVisionCone
extends Node2D

# Draws the fish's blind spot as a faint green cone behind the tail.
# The blind spot is the safe approach zone — green = approach here.
# Visibility opacity scales with difficulty telegraph strength.

var _half_blind_rad: float = deg_to_rad(30.0)
var _cone_length: float = 110.0
var _fill_alpha: float = 0.15
var _edge_alpha: float = 0.38


func setup(config: DifficultyConfig) -> void:
	_half_blind_rad = deg_to_rad(config.blind_spot_half_angle)
	# More visible on casual (higher telegraph = easier to read)
	_fill_alpha = 0.08 + config.fish_telegraph_strength * 0.16
	_edge_alpha = _fill_alpha * 2.5
	queue_redraw()


func _draw() -> void:
	# Fish faces upstream (left). Tail points downstream (+x). Blind spot is behind tail.
	var e1 := Vector2.from_angle(-_half_blind_rad) * _cone_length
	var e2 := Vector2.from_angle( _half_blind_rad) * _cone_length

	draw_colored_polygon(
		PackedVector2Array([Vector2.ZERO, e1, e2]),
		Color(0.22, 0.85, 0.35, _fill_alpha)
	)
	draw_line(Vector2.ZERO, e1, Color(0.22, 0.85, 0.35, _edge_alpha), 1.0)
	draw_line(Vector2.ZERO, e2, Color(0.22, 0.85, 0.35, _edge_alpha), 1.0)
