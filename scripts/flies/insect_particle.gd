class_name InsectParticle
extends Node2D

# Lightweight animated insect dot. Lives in InsectLayer (CanvasLayer) so
# position is in screen coordinates — no camera transform needed.

var _color:    Color  = Color.WHITE
var _movement: String = "drift"
var _vel:      Vector2 = Vector2.ZERO
var _skitter_timer: float = 0.0
var _wrap_min_x: float = 0.0
var _wrap_max_x: float = 1920.0


func setup(color: Color, movement: String, start_pos: Vector2,
		   vel: Vector2, wrap_min: float, wrap_max: float) -> void:
	_color      = color
	_movement   = movement
	_vel        = vel
	_wrap_min_x = wrap_min
	_wrap_max_x = wrap_max
	position    = start_pos


func _process(delta: float) -> void:
	if _movement == "skitter":
		_skitter_timer -= delta
		if _skitter_timer <= 0.0:
			_skitter_timer = randf_range(0.15, 0.60)
			_vel.x = randf_range(-30.0, 10.0)
			_vel.y = randf_range(-5.0,  5.0)

	position += _vel * delta

	# Wrap within screen strip
	if position.x < _wrap_min_x - 32.0:
		position.x = _wrap_max_x + 16.0
	elif position.x > _wrap_max_x + 32.0:
		position.x = _wrap_min_x - 16.0

	queue_redraw()


func _draw() -> void:
	draw_circle(Vector2.ZERO, 2.5, _color)
	# Wing hint for adult / skittering insects
	if _movement == "skitter":
		var wc := _color.lightened(0.35)
		draw_line(Vector2(-4.0, -1.5), Vector2(4.0, -1.5), wc, 1.0)
