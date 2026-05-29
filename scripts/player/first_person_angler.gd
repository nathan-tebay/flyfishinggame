class_name FirstPersonAngler3D
extends CharacterBody3D

signal cast_target_requested(origin: Vector3, direction: Vector3)
signal cast_loop_requested(phase: String)
signal cast_commit_requested(style: String)
signal fly_change_requested

const WALK_SPEED := 5.2
const WADE_SPEED := 2.4
const MOUSE_SENSITIVITY := 0.0025
const MIN_PITCH := deg_to_rad(-72.0)
const MAX_PITCH := deg_to_rad(58.0)

var river_world: Node = null
var _pitch := 0.0
var _movement_locked := false

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var rod = $Head/Camera3D/RodPivot


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_action_pressed("pause_game"):
		_toggle_mouse_capture()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("cycle_fly"):
		fly_change_requested.emit()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			get_viewport().set_input_as_handled()
			return
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_request_target_selection()
			get_viewport().set_input_as_handled()
			return
		if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			_request_cast_style("roll")
			get_viewport().set_input_as_handled()
			return

	if not (event is InputEventMouseMotion):
		return
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		return

	var motion := event as InputEventMouseMotion
	rotate_y(-motion.relative.x * MOUSE_SENSITIVITY)
	_pitch = clampf(_pitch - motion.relative.y * MOUSE_SENSITIVITY, MIN_PITCH, MAX_PITCH)
	head.rotation.x = _pitch


func _physics_process(_delta: float) -> void:
	if Input.is_action_just_pressed("select_cast_target") or Input.is_action_just_pressed("complete_cast"):
		_request_target_selection()
	if Input.is_action_just_pressed("back_cast"):
		_request_cast_loop("back")
	if Input.is_action_just_pressed("forward_cast"):
		_request_cast_loop("forward")
	if Input.is_action_just_pressed("overhead_cast"):
		_request_cast_style("overhead")
	if Input.is_action_just_pressed("roll_cast"):
		_request_cast_style("roll")

	_movement_locked = _is_casting_control_locked()
	if _movement_locked:
		velocity = Vector3.ZERO
		move_and_slide()
		return

	var input_vector := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var forward := -global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()

	var right := global_transform.basis.x
	right.y = 0.0
	right = right.normalized()

	var move_dir := right * input_vector.x + forward * -input_vector.y
	if move_dir.length_squared() > 1.0:
		move_dir = move_dir.normalized()

	var speed := WALK_SPEED
	if river_world != null and river_world.has_method("movement_speed_at"):
		speed = river_world.movement_speed_at(global_position, WALK_SPEED, WADE_SPEED)

	velocity.x = move_dir.x * speed
	velocity.y = 0.0
	velocity.z = move_dir.z * speed
	move_and_slide()

	if river_world == null:
		return
	if not river_world.has_method("clamp_player_position"):
		return

	var clamped: Vector3 = river_world.clamp_player_position(global_position)
	if river_world.has_method("surface_height"):
		clamped.y = river_world.surface_height(clamped)
	global_position = clamped


func set_initial_pitch(pitch: float) -> void:
	_pitch = clampf(pitch, MIN_PITCH, MAX_PITCH)
	head.rotation.x = _pitch


func play_cast_animation(style: String = "overhead") -> void:
	rod.play_cast(style)


func set_camera_fov(target_fov: float) -> void:
	if camera == null:
		return
	camera.fov = target_fov


func camera_fov() -> float:
	if camera == null:
		return 68.0
	return camera.fov


func _request_target_selection() -> void:
	if river_world != null and river_world.has_method("try_hookset"):
		if river_world.try_hookset():
			return
	if camera == null:
		return
	var origin: Vector3 = rod.tip_global_position()
	var direction := -camera.global_transform.basis.z.normalized()
	cast_target_requested.emit(origin, direction)


func _request_cast_loop(phase: String) -> void:
	cast_loop_requested.emit(phase)


func _request_cast_style(style: String) -> void:
	cast_commit_requested.emit(style)


func _is_casting_control_locked() -> bool:
	if river_world == null:
		return false
	if not river_world.has_method("is_casting_control_active"):
		return false
	return bool(river_world.is_casting_control_active())


func _request_cast() -> void:
	_request_target_selection()


func _toggle_mouse_capture() -> void:
	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
