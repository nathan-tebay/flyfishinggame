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

	# Line management
	_key("feed_line",  KEY_F)
	_axis("feed_line",  JOY_AXIS_TRIGGER_RIGHT,  1.0)
	_key("strip_line", KEY_R)
	_axis("strip_line", JOY_AXIS_TRIGGER_LEFT,   1.0)

	# Casting rhythm (right stick Y / arrow keys)
	_key_and_axis("cast_back",    KEY_DOWN, JOY_AXIS_RIGHT_Y,  1.0)
	_key_and_axis("cast_forward", KEY_UP,   JOY_AXIS_RIGHT_Y, -1.0)

	# Context-sensitive confirm (complete cast / hookset)
	_key_and_button("complete_cast", KEY_SPACE, JOY_BUTTON_A)
	_key_and_button("hookset",       KEY_SPACE, JOY_BUTTON_A)

	# Other actions
	_key_and_button("net_sample", KEY_N,      JOY_BUTTON_B)
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
