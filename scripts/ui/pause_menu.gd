class_name PauseMenu
extends Control

# ESC pause / config menu. Standard items (resume, master volume, fullscreen, look
# sensitivity, restart, quit) plus a Developer Parameters submenu that live-tunes the
# casting-feel values. Built procedurally; runs while the tree is paused.

const SESSION_SCENE := "res://scenes/SessionConfig.tscn"

var world: Node = null      # RiverWorld3D
var angler: Node = null     # FirstPersonAngler3D

var _main_page: VBoxContainer = null
var _dev_page: VBoxContainer = null
var _dev_scroll: ScrollContainer = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause_game"):
		return
	if visible and _dev_scroll.visible:
		_show_page(true)          # ESC backs out of the dev submenu first
	elif visible:
		_resume()
	else:
		_open()
	get_viewport().set_input_as_handled()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.04, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(440.0, 0.0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 22)
	panel.add_child(margin)

	var holder := VBoxContainer.new()
	holder.add_theme_constant_override("separation", 8)
	margin.add_child(holder)

	_main_page = _make_main_page()
	holder.add_child(_main_page)
	_dev_page = _make_dev_page()
	_dev_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dev_scroll = ScrollContainer.new()
	_dev_scroll.custom_minimum_size = Vector2(440.0, 470.0)
	_dev_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_dev_scroll.add_child(_dev_page)
	holder.add_child(_dev_scroll)
	_show_page(true)


func _make_main_page() -> VBoxContainer:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 8)
	_title(page, "PAUSED")
	_button(page, "Resume", _resume)
	_volume_slider(page)
	_fullscreen_toggle(page)
	if angler != null:
		_param_slider(page, "Look sensitivity", angler, "mouse_sensitivity", 0.0008, 0.0060, 0.0002)
	_button(page, "Developer Parameters  ▸", func(): _show_page(false))
	_button(page, "Restart Session", _restart)
	_button(page, "Quit Game", func(): _quit())
	return page


func _make_dev_page() -> VBoxContainer:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 6)
	_title(page, "DEVELOPER PARAMETERS")

	_section(page, "Input / feel")
	if angler != null and angler.rod != null:
		_param_slider(page, "Rod elevation sensitivity", angler.rod, "rod_cast_sensitivity", 0.0006, 0.0030, 0.0001)
		_param_slider(page, "Rod elevation response", angler.rod, "rod_elevation_response", 3.0, 16.0, 0.5)
	if angler != null:
		_param_slider(page, "Cast lateral sensitivity", angler, "cast_rod_lateral_sens", 0.0004, 0.0024, 0.0001)
		_param_slider(page, "Plane self-center rate", angler, "cast_plane_center_rate", 0.0, 8.0, 0.25)

	_section(page, "Casting rhythm")
	if world != null:
		_param_slider(page, "Backcast load height", world, "backcast_load_elev", 0.70, 1.50, 0.02)
		_param_slider(page, "Forward commit height", world, "forward_commit_elev", 0.02, 0.40, 0.02)
		_param_slider(page, "Delivery load min", world, "delivery_load_min", 0.40, 1.20, 0.05)
		_param_slider(page, "Delivery timing min", world, "delivery_timing_min", 0.30, 1.00, 0.05)
		_param_slider(page, "Tight-loop load gain", world, "tight_load_gain", 0.05, 0.50, 0.01)
		_param_slider(page, "Unroll time — short line", world, "unroll_time_min", 0.20, 1.00, 0.05)
		_param_slider(page, "Unroll time — full line", world, "unroll_time_max", 0.60, 2.00, 0.05)

	_section(page, "Arm pose")
	if angler != null:
		_param_slider(page, "Shoulder pitch (rest)", angler, "arm_shoulder_pitch_rest", -0.40, 1.20, 0.02)
		_param_slider(page, "Shoulder pitch gain", angler, "arm_shoulder_pitch_gain", 0.0, 1.50, 0.02)
		_param_slider(page, "Elbow flex", angler, "arm_elbow_flex", 1.20, 3.00, 0.02)

	_section(page, "Cast camera")
	if angler != null:
		_param_slider(page, "Close — back (m)", angler, "cam_close_back", 0.5, 8.0, 0.25)
		_param_slider(page, "Close — up (m)", angler, "cam_close_up", 0.5, 8.0, 0.25)
		_param_slider(page, "Far — back (m)", angler, "cam_far_back", 4.0, 30.0, 0.5)
		_param_slider(page, "Far — up (m)", angler, "cam_far_up", 2.0, 25.0, 0.5)

	_button(page, "◂ Back", func(): _show_page(true))
	return page


func _section(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.62, 0.80, 0.95, 0.95))
	parent.add_child(label)


# --- Widgets ---

func _title(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 22)
	parent.add_child(label)


func _button(parent: Control, text: String, on_press: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0.0, 32.0)
	b.pressed.connect(on_press)
	parent.add_child(b)


func _param_slider(parent: Control, label_text: String, obj: Object, prop: String,
		lo: float, hi: float, step: float) -> void:
	var row := VBoxContainer.new()
	var head := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = label_text
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var value_label := Label.new()
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(name_label)
	head.add_child(value_label)
	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.value = float(obj.get(prop))
	slider.custom_minimum_size = Vector2(380.0, 0.0)
	value_label.text = _fmt(slider.value, step)
	slider.value_changed.connect(func(v: float):
		obj.set(prop, v)
		value_label.text = _fmt(v, step)
	)
	row.add_child(head)
	row.add_child(slider)
	parent.add_child(row)


func _volume_slider(parent: Control) -> void:
	var bus := AudioServer.get_bus_index("Master")
	var row := VBoxContainer.new()
	var head := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = "Master volume"
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var value_label := Label.new()
	head.add_child(name_label)
	head.add_child(value_label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = db_to_linear(AudioServer.get_bus_volume_db(bus)) if bus >= 0 else 1.0
	slider.custom_minimum_size = Vector2(380.0, 0.0)
	value_label.text = "%d%%" % int(slider.value * 100.0)
	slider.value_changed.connect(func(v: float):
		if bus >= 0:
			AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(v, 0.0001)))
		value_label.text = "%d%%" % int(v * 100.0)
	)
	row.add_child(head)
	row.add_child(slider)
	parent.add_child(row)


func _fullscreen_toggle(parent: Control) -> void:
	var cb := CheckButton.new()
	cb.text = "Fullscreen"
	cb.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	cb.toggled.connect(func(on: bool):
		DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)
	)
	parent.add_child(cb)


func _fmt(v: float, step: float) -> String:
	if step >= 1.0:
		return "%d" % int(round(v))
	if step >= 0.01:
		return "%.2f" % v
	return "%.4f" % v


# --- Actions ---

func _show_page(main: bool) -> void:
	_main_page.visible = main
	_dev_scroll.visible = not main


func _open() -> void:
	visible = true
	_show_page(true)
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _resume() -> void:
	visible = false
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _restart() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(SESSION_SCENE)


func _quit() -> void:
	get_tree().paused = false
	get_tree().quit()
