class_name FlyLineDebugView
extends CanvasLayer

## Attach to a test scene and call bind_solver. Reads only public solver state.
var solver
var _label: Label


func _ready() -> void:
	_label = Label.new()
	_label.position = Vector2(12.0, 12.0)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_label)


func bind_solver(value) -> void:
	solver = value


func _process(_delta: float) -> void:
	if _label == null:
		return
	_label.text = "Fly line: no solver" if solver == null else solver.inspect()
