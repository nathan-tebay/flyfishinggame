extends Node

# Programmatic input map — all actions remappable at runtime.
# Gamepad assumed to be XInput/generic layout (A=0, B=1, Start=6).
# Triggers: Left=axis 4, Right=axis 5.
# Left stick: X=axis 0, Y=axis 1. Right stick: X=axis 2, Y=axis 3.

func _ready() -> void:
	_setup_actions()


func _setup_actions() -> void:
	# Movement
	_key_and_axis("move_left",  KEY_A, JOY_AXIS_LEFT_X, -1.0)
	_key_and_axis("move_right", KEY_D, JOY_AXIS_LEFT_X,  1.0)
	_key_and_axis("move_up",    KEY_W, JOY_AXIS_LEFT_Y, -1.0)
	_key_and_axis("move_down",  KEY_S, JOY_AXIS_LEFT_Y,  1.0)

	# Cast
	_key_and_button("select_cast_target", KEY_SPACE, JOY_BUTTON_A)
	_key_and_button("back_cast", KEY_B, JOY_BUTTON_LEFT_STICK)
	_key_and_button("forward_cast", KEY_F, JOY_BUTTON_RIGHT_STICK)
	_key_and_button("overhead_cast", KEY_O, JOY_BUTTON_RIGHT_SHOULDER)
	_key_and_button("roll_cast", KEY_R, JOY_BUTTON_LEFT_SHOULDER)
	_key_and_button("complete_cast", KEY_SPACE, JOY_BUTTON_A)
	_key("cycle_fly", KEY_Q)
	_key("cast_zoom_in", KEY_Z)
	_key("cast_zoom_out", KEY_X)

	# Mouse capture / pause
	_key_and_button("pause_game", KEY_ESCAPE, JOY_BUTTON_START)


# --- Helpers ---

func _ensure(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)


func _key(action: String, keycode: Key) -> void:
	_ensure(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	InputMap.action_add_event(action, ev)


func _button(action: String, button: JoyButton) -> void:
	_ensure(action)
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)


func _axis(action: String, axis: JoyAxis, value: float) -> void:
	_ensure(action)
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = value
	InputMap.action_add_event(action, ev)


func _key_and_button(action: String, keycode: Key, button: JoyButton) -> void:
	_key(action, keycode)
	_button(action, button)


func _key_and_axis(action: String, keycode: Key, axis: JoyAxis, value: float) -> void:
	_key(action, keycode)
	_axis(action, axis, value)
