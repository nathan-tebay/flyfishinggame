class_name ShadowCone
extends Node2D

# Directional shadow projected from the angler onto the water surface.
# Angle driven by TimeOfDay.sun_angle. Only drawn on bank (not while wading).
# Visibility controlled by DifficultyConfig.show_shadow_cone.

const SHADOW_LENGTH_MAX := 280.0  # pixels at dawn/dusk (low sun)
const SHADOW_LENGTH_MIN :=  60.0  # pixels at midday (high sun)
const SHADOW_HALF_ANGLE :=  20.0  # degrees — half the cone width

const SHADOW_FILL  := Color(0.10, 0.05, 0.30, 0.30)
const SHADOW_EDGE  := Color(0.10, 0.05, 0.30, 0.55)

var visible_to_player: bool = true  # set by Angler._refresh_shadow_visibility()


func _ready() -> void:
	TimeOfDay.period_changed.connect(func(_p: int) -> void: queue_redraw())


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var angler := get_parent() as Angler
	if not visible_to_player or angler == null or angler.is_wading:
		return

	var dir    := _shadow_dir()
	var length := _shadow_length()
	var hr     := deg_to_rad(SHADOW_HALF_ANGLE)

	var left_tip  := dir.rotated(-hr) * length
	var right_tip := dir.rotated( hr) * length

	draw_polygon(
		PackedVector2Array([Vector2.ZERO, left_tip, right_tip]),
		PackedColorArray([SHADOW_FILL, SHADOW_FILL, SHADOW_FILL])
	)
	draw_line(Vector2.ZERO, left_tip,  SHADOW_EDGE, 1.5)
	draw_line(Vector2.ZERO, right_tip, SHADOW_EDGE, 1.5)


# Shadow direction in world space (x right = downstream, y down = deeper).
# Sun travels east→overhead→west, so shadow sweeps west→down→east.
func _shadow_dir() -> Vector2:
	# sun_angle: 0 = east/dawn (right), 90 = midday (up), 180 = dusk (west/left)
	# Sun vector:    ( cos(a), -sin(a) ) — (1,0)→(0,-1)→(-1,0)
	# Shadow vector: (-cos(a),  sin(a) ) — points opposite to sun
	var a := deg_to_rad(TimeOfDay.sun_angle)
	var shadow := Vector2(-cos(a), sin(a))
	# Always ensure at least a small downward component so cone enters the water
	shadow.y = maxf(shadow.y, 0.15)
	return shadow.normalized()


# Shadow is longest when sun is low (dawn/dusk), shortest at midday.
func _shadow_length() -> float:
	var t := sin(deg_to_rad(TimeOfDay.sun_angle))  # 0 at dawn/dusk, 1 at midday
	return lerpf(SHADOW_LENGTH_MAX, SHADOW_LENGTH_MIN, t)
