class_name InsectParticle
extends Node2D

const _SpriteCatalog = preload("res://scripts/assets/sprite_catalog.gd")

# Lightweight animated insect dot. Lives in world space as a child of RiverWorld.
# Drifts downstream with the current; wraps within a world-space x range.

const NYMPH_REGION := Rect2i(873, 191, 93, 155)
const ADULT_REGION := Rect2i(1206, 200, 157, 150)
const FLY_REGION := Rect2i(197, 607, 140, 120)

var _color:    Color  = Color.WHITE
var _movement: String = "drift"
var _vel:      Vector2 = Vector2.ZERO
var _skitter_timer: float = 0.0
var _wrap_min_x: float = 0.0
var _wrap_max_x: float = 1920.0
var _life_texture: Texture2D = null
var _fly_texture: Texture2D = null


func setup(color: Color, movement: String, start_pos: Vector2,
		   vel: Vector2, wrap_min: float, wrap_max: float) -> void:
	_color      = color
	_movement   = movement
	_vel        = vel
	_wrap_min_x = wrap_min
	_wrap_max_x = wrap_max
	position    = start_pos
	_life_texture = load(_SpriteCatalog.AQUATIC_INSECTS_LIFECYCLE) as Texture2D
	_fly_texture = load(_SpriteCatalog.AQUATIC_INSECTS_FLIES_TOPDOWN) as Texture2D


func _process(delta: float) -> void:
	if _movement == "skitter":
		_skitter_timer -= delta
		if _skitter_timer <= 0.0:
			_skitter_timer = randf_range(0.15, 0.60)
			# Erratic but net-downstream: bias positive x so they still drift with current
			_vel.x = randf_range(10.0, 60.0)
			_vel.y = randf_range(-5.0,  5.0)

	position += _vel * delta

	# Wrap within world-space x range
	if position.x < _wrap_min_x - 32.0:
		position.x = _wrap_max_x + 16.0
	elif position.x > _wrap_max_x + 32.0:
		position.x = _wrap_min_x - 16.0

	queue_redraw()


func _draw() -> void:
	if _draw_sprite_particle():
		return

	draw_circle(Vector2.ZERO, 2.5, _color)
	if _movement == "skitter":
		var wc := _color.lightened(0.35)
		draw_line(Vector2(-4.0, -1.5), Vector2(4.0, -1.5), wc, 1.0)


func _draw_sprite_particle() -> bool:
	var texture := _fly_texture if _movement == "skitter" else _life_texture
	if texture == null:
		return false

	var region := FLY_REGION if _movement == "skitter" else NYMPH_REGION
	var target_w := 9.0 if _movement == "skitter" else 6.0
	var scale := target_w / float(region.size.x)
	var size := Vector2(float(region.size.x), float(region.size.y)) * scale
	var rect := Rect2(-size * 0.5, size)
	var alpha := clampf(_color.a, 0.35, 1.0)
	draw_texture_rect_region(texture, rect, region, Color(1.0, 1.0, 1.0, alpha))
	return true
