class_name StrikeIndicator
extends Node2D

# Floating ball strike indicator.
# Nymph: cream ball visible during drift, dips on take.
# Dry fly: invisible during drift, expanding ring on take.
#
# Position managed by HooksetController (x drifts left, y set at spawn).
# _ready() records base_y for dip animation.

var _taking:    bool  = false
var _is_nymph:  bool  = false
var _anim_time: float = 0.0
var _base_y:    float = 108.0


func _ready() -> void:
	_base_y = position.y


func start_take(is_nymph: bool) -> void:
	_taking    = true
	_is_nymph  = is_nymph
	_anim_time = 0.0


func _process(delta: float) -> void:
	if _taking:
		_anim_time += delta
		if _is_nymph:
			var dip := minf(_anim_time / 0.3, 1.0) * 20.0
			position.y = _base_y + dip
	queue_redraw()


func _draw() -> void:
	if _taking and not _is_nymph:
		# Expanding ring for dry fly rise / splash
		var r     := _anim_time * 40.0 + 5.0
		var alpha := maxf(0.0, 1.0 - _anim_time * 1.8)
		draw_circle(Vector2.ZERO, r, Color(0.95, 0.92, 0.75, alpha * 0.4))
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 20,
			Color(0.90, 0.72, 0.28, alpha), 2.0)
	elif _is_nymph or not _taking:
		# Floating ball (nymph only during drift; both during dip)
		var col := Color(0.95, 0.95, 0.85) if not _taking else Color(1.0, 0.45, 0.12)
		draw_circle(Vector2.ZERO, 5.5, col)
		draw_circle(Vector2.ZERO, 5.5, Color(0.20, 0.20, 0.25), false, 1.2)
		# Tippet line above
		draw_line(Vector2(0.0, -5.5), Vector2(0.0, -20.0),
			Color(0.70, 0.65, 0.55, 0.7), 1.0)
