class_name FirstPersonAngler3D
extends CharacterBody3D

signal cast_target_requested(origin: Vector3, direction: Vector3)
signal line_feed_requested(amount: float)
signal line_retrieve_requested(amount: float)
signal hookset_requested
signal fly_change_requested

enum GameMode { EXPLORE, CAST }

const WALK_SPEED := 5.2
const WADE_SPEED := 2.4
@export var mouse_sensitivity := 0.0025
const MIN_PITCH := deg_to_rad(-72.0)
const MAX_PITCH := deg_to_rad(58.0)

# Cast mode camera — two presets toggled with `cast_camera_toggle` (V).
#   close: shoulder-height behind the angler, shows the arm/rod stroke up close.
#   far:   ~15 m elevated overview for reading the whole casting lane / plane.
# Each preset: [back_m, up_m, look_ahead_m, look_height_m, fov]
# close = over-shoulder; far = pulled-back overview. Per preset: [back, up, look_ahead, look_height, fov]
@export var cam_close_back := 2.0
@export var cam_close_up   := 3.0
@export var cam_far_back   := 10.0
@export var cam_far_up     := 5.0
const CAST_CAM_LOOK_AHEAD  := 5.5
const CAST_CAM_LOOK_HEIGHT := 0.9
const CAST_CAM_CLOSE_FOV   := 65.0
const CAST_CAM_FAR_FOV     := 70.0
const CAST_CAM_ENTRY_DELAY := 0.55
const CAST_CAM_FOLLOW      := 6.0

# Rod aim in cast mode — lateral (casting plane) made easy to hold straight:
# lower sensitivity, a jitter deadzone, and self-centering back toward the
# target-aligned vertical plane (lateral 0) when the player isn't steering.
@export var cast_rod_lateral_sens := 0.0010
const CAST_ROD_ELEVATION_SENS := 0.0022
const CAST_ROD_LATERAL_DEADZONE := 1.5     # px of horizontal jitter ignored per frame
@export var cast_plane_center_rate := 3.0  # spring rate back to vertical plane

# Casting-arm skeleton drive — whole right arm sweeps the casting arc.
# Ready stance (elevation 0) mirrors a real fly-casting grip: upper arm hangs
# slightly forward and tucked, elbow flexed so the forearm comes up in front, and
# the wrist cocks the rod up-and-forward (~1 o'clock). Raising elevation lifts the
# whole arm up and back into the backcast; the forward stroke drops it.
@export var arm_shoulder_pitch_rest := 0.35  # shoulder/elbow forward-down at rest (rad)
@export var arm_shoulder_pitch_gain := 0.65  # elevation lifts shoulder & elbow up
@export var arm_elbow_flex          := 2.20  # constant elbow bend holding the rod up
const ARM_PLANE_YAW_GAIN      := 0.35      # rod lateral -> shoulder yaw
const ARM_TORSO_TWIST_GAIN    := 0.12
const ARM_POSE_RESPONSE       := 9.0       # bone-pose damping
# The rod continues the forearm line; a flipped grip socket aligns the rod (built
# along +Y) with the forearm's down-Y so it reads as held in the fist.
const GRIP_SOCKET_ROTATION    := Vector3(PI, 0.0, 0.0)

# Line management
const LINE_STRIP_AMOUNT  := 0.46
const LINE_FEED_RATE     := 1.8
const LINE_RETRIEVE_RATE := 1.8

# Cast mode movement
const CAST_SPEED_SCALE := 0.35

var river_world: Node = null

var _game_mode: GameMode = GameMode.EXPLORE
var _pitch := 0.0

# Cast camera state
var _cast_camera: Camera3D = null
var _cast_camera_ready := false

# Rod aim (CAST mode)
var _cast_mouse_dx := 0.0
var _cast_mouse_dy := 0.0
var _prev_cast_mouse_dy := 0.0
var _rod_lateral := 0.0
var _rod_lateral_target := 0.0

# Line hold (CAST mode)
var _line_feed_held := false
var _line_retrieve_held := false

# Hover camera (fish viewing)
var _camera_hover_active := false
var _camera_tween: Tween = null
var _saved_camera_transform := Transform3D.IDENTITY
var _saved_camera_fov := 68.0

# Angler body / skeleton (cast mode only)
var _angler_body: Node3D = null
var _skeleton: Skeleton3D = null
var _bone_idx := {}                       # bone name -> index
var _hand_r_attach: BoneAttachment3D = null
var _grip_socket: Node3D = null
var _arm_pose := {}                       # cached current pose euler per bone for damping

# Cast camera preset state
var _cast_view_far := false

# Rod home (explore-mode) parent + local transform, for reparent on/off the hand bone
var _rod_home_parent: Node = null
var _rod_home_xform := Transform3D.IDENTITY

# Cast motion capture (dev tuning tool): record the consumed cast input per frame,
# export to CSV, and replay identical motion so constants can be A/B tuned.
const CAST_CAPTURE_DIR := "user://cast_captures"
var _last_cast_motion := Vector2.ZERO
var _capturing := false
var _replaying := false
var _capture_clock := 0.0
var _capture_frames: Array[Dictionary] = []
var _replay_frames: Array[Dictionary] = []
var _replay_index := 0

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var rod = $Head/Camera3D/RodPivot


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if rod != null:
		_rod_home_parent = rod.get_parent()
		_rod_home_xform = rod.transform
	_build_cast_camera()
	_build_angler_body()


func _build_cast_camera() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_cast_camera = Camera3D.new()
	_cast_camera.name = "CastCamera"
	_cast_camera.fov = CAST_CAM_CLOSE_FOV
	_cast_camera.current = false
	add_child(_cast_camera)


func _cast_preset() -> Array:
	if _cast_view_far:
		return [cam_far_back, cam_far_up, CAST_CAM_LOOK_AHEAD, CAST_CAM_LOOK_HEIGHT, CAST_CAM_FAR_FOV]
	return [cam_close_back, cam_close_up, CAST_CAM_LOOK_AHEAD, CAST_CAM_LOOK_HEIGHT, CAST_CAM_CLOSE_FOV]


func _build_angler_body() -> void:
	_angler_body = Node3D.new()
	_angler_body.name = "AnglerBody"
	_angler_body.visible = false
	add_child(_angler_body)

	_skeleton = Skeleton3D.new()
	_skeleton.name = "AnglerSkeleton"
	_angler_body.add_child(_skeleton)
	_build_skeleton_bones()
	_skeleton.reset_bone_poses()

	# Visual meshes are skipped under the headless dummy renderer (it rejects mesh
	# resources). The Skeleton3D + bones still exist so cast-arm math stays testable.
	if DisplayServer.get_name() == "headless":
		return
	_build_body_meshes()


func _build_skeleton_bones() -> void:
	# Joint offsets are local to each bone's parent (skeleton space, -Z forward).
	# Closed right-handed stance: left foot forward toward the target.
	_add_bone("Hips",      "",          Vector3(0.0, 0.92, 0.0))
	_add_bone("Spine",     "Hips",      Vector3(0.0, 0.20, 0.0))
	_add_bone("Chest",     "Spine",     Vector3(0.0, 0.20, 0.0))
	_add_bone("Shoulders", "Chest",     Vector3(0.0, 0.18, 0.0))
	_add_bone("Head",      "Shoulders", Vector3(0.0, 0.16, 0.0))
	# Right (casting) arm — driven each frame in cast mode
	_add_bone("UpperArmR", "Chest",     Vector3( 0.19, 0.15, 0.0))
	_add_bone("ForearmR",  "UpperArmR", Vector3(0.0, -0.30, 0.0))
	_add_bone("HandR",     "ForearmR",  Vector3(0.0, -0.28, 0.0))
	# Left (line) arm — static relaxed hang
	_add_bone("UpperArmL", "Chest",     Vector3(-0.19, 0.15, 0.0))
	_add_bone("ForearmL",  "UpperArmL", Vector3(0.0, -0.28, 0.0))
	_add_bone("HandL",     "ForearmL",  Vector3(0.0, -0.26, 0.0))
	# Legs — static
	_add_bone("ThighL",    "Hips",      Vector3(-0.10, -0.07, -0.08))
	_add_bone("ShinL",     "ThighL",    Vector3(0.0, -0.42, 0.0))
	_add_bone("ThighR",    "Hips",      Vector3( 0.10, -0.07,  0.08))
	_add_bone("ShinR",     "ThighR",    Vector3(0.0, -0.42, 0.0))


func _add_bone(bone_name: String, parent_name: String, local_offset: Vector3) -> void:
	var idx := _skeleton.add_bone(bone_name)
	_bone_idx[bone_name] = idx
	if parent_name != "" and _bone_idx.has(parent_name):
		_skeleton.set_bone_parent(idx, int(_bone_idx[parent_name]))
	_skeleton.set_bone_rest(idx, Transform3D(Basis.IDENTITY, local_offset))


func _build_body_meshes() -> void:
	var waders := StandardMaterial3D.new()
	waders.albedo_color = Color(0.18, 0.22, 0.16)
	waders.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	var jacket := StandardMaterial3D.new()
	jacket.albedo_color = Color(0.52, 0.44, 0.32)
	jacket.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.76, 0.58, 0.44)
	skin.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL

	# Torso column (cylinders centred on their bone)
	_attach_cylinder("Hips",      waders, 0.18, 0.19, 0.19, 0.04)
	_attach_cylinder("Spine",     jacket, 0.30, 0.15, 0.18, 0.09)
	_attach_cylinder("Shoulders", jacket, 0.12, 0.21, 0.21, 0.02)
	_attach_sphere("Head", skin, 0.115, 0.0)

	# Arms / legs — cylinders span from the joint downward toward the child joint.
	_attach_limb("UpperArmR", waders, 0.30, 0.040)
	_attach_limb("ForearmR",  jacket, 0.28, 0.036)
	_attach_limb("UpperArmL", waders, 0.28, 0.040)
	_attach_limb("ForearmL",  jacket, 0.26, 0.036)
	_attach_limb("ThighL",    waders, 0.42, 0.055)
	_attach_limb("ShinL",     waders, 0.42, 0.050)
	_attach_limb("ThighR",    waders, 0.42, 0.055)
	_attach_limb("ShinR",     waders, 0.42, 0.050)

	# Rod mount on the right hand — rod reparents to the grip socket in cast mode.
	_hand_r_attach = _attach_to_bone("HandR")
	_grip_socket = Node3D.new()
	_grip_socket.name = "GripSocket"
	_grip_socket.rotation = GRIP_SOCKET_ROTATION
	_hand_r_attach.add_child(_grip_socket)


func _attach_to_bone(bone_name: String) -> BoneAttachment3D:
	var att := BoneAttachment3D.new()
	att.name = bone_name + "Attach"
	_skeleton.add_child(att)
	att.bone_name = bone_name
	return att


func _attach_cylinder(bone_name: String, mat: Material, height: float,
		top_r: float, bot_r: float, local_y: float) -> void:
	var att := _attach_to_bone(bone_name)
	var node := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.height = height
	cyl.top_radius = top_r
	cyl.bottom_radius = bot_r
	cyl.radial_segments = 10
	node.mesh = cyl
	node.material_override = mat
	node.position = Vector3(0.0, local_y, 0.0)
	att.add_child(node)


func _attach_sphere(bone_name: String, mat: Material, radius: float, local_y: float) -> void:
	var att := _attach_to_bone(bone_name)
	var node := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 10
	sphere.rings = 6
	node.mesh = sphere
	node.material_override = mat
	node.position = Vector3(0.0, local_y, 0.0)
	att.add_child(node)


func _attach_limb(bone_name: String, mat: Material, length: float, radius: float) -> void:
	var att := _attach_to_bone(bone_name)
	var node := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.height = length
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.radial_segments = 8
	node.mesh = cyl
	node.material_override = mat
	node.position = Vector3(0.0, -length * 0.5, 0.0)  # span from joint downward
	att.add_child(node)


# Drives the whole right arm through the casting arc via Skeleton3D bone poses:
# the shoulder lifts and the elbow flexes with rod elevation, so the entire arm
# (and the hand-mounted rod) sweeps rather than the rod swinging on a fixed grip.
func _update_cast_arm(delta: float) -> void:
	if _skeleton == null or rod == null:
		return
	var elev: float = rod.get_elevation_offset() if rod.has_method("get_elevation_offset") else 0.0
	var phase: String = str(rod._live_cast_phase)
	# Rod continues the forearm; the shoulder lift sweeps it through the arc while
	# the elbow holds a constant bend keeping the rod up out of the fist.
	var shoulder_pitch := arm_shoulder_pitch_rest + elev * arm_shoulder_pitch_gain
	var plane_yaw := -_rod_lateral * ARM_PLANE_YAW_GAIN
	var twist := 0.0
	if phase == "backcast":
		twist = elev * ARM_TORSO_TWIST_GAIN
	elif phase == "forward":
		twist = -elev * (ARM_TORSO_TWIST_GAIN * 0.6)

	_pose_bone("Chest", Vector3(0.0, twist, 0.0), delta)
	_pose_bone("UpperArmR", Vector3(shoulder_pitch, plane_yaw, 0.0), delta)
	_pose_bone("ForearmR", Vector3(arm_elbow_flex, 0.0, 0.0), delta)


func _pose_bone(bone_name: String, target_euler: Vector3, delta: float) -> void:
	if not _bone_idx.has(bone_name):
		return
	var cur: Vector3 = _arm_pose.get(bone_name, Vector3.ZERO)
	cur = cur.lerp(target_euler, minf(delta * ARM_POSE_RESPONSE, 1.0))
	_arm_pose[bone_name] = cur
	_skeleton.set_bone_pose_rotation(int(_bone_idx[bone_name]), Quaternion.from_euler(cur))


func _process(delta: float) -> void:
	if _game_mode == GameMode.CAST:
		_update_cast_camera(delta)
		if _replaying:
			_feed_replay_frame()
		_update_rod_aim(delta)
		if _capturing:
			_record_capture_frame(delta)
		_update_line_hold(delta)
		_update_cast_arm(delta)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cycle_fly"):
		fly_change_requested.emit()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("exit_cast_mode") and _game_mode == GameMode.CAST:
		enter_explore_mode()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("cast_camera_toggle") and _game_mode == GameMode.CAST:
		toggle_cast_camera_view()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("cast_record_toggle"):
		toggle_cast_capture()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("cast_replay_toggle"):
		toggle_cast_replay()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			get_viewport().set_input_as_handled()
			return
		if _game_mode == GameMode.EXPLORE:
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				_request_target_selection()
				get_viewport().set_input_as_handled()
				return
		elif _game_mode == GameMode.CAST:
			if mb.button_index == MOUSE_BUTTON_LEFT:
				_line_feed_held = mb.pressed
				if mb.pressed:
					line_feed_requested.emit(LINE_STRIP_AMOUNT)
				get_viewport().set_input_as_handled()
				return
			if mb.button_index == MOUSE_BUTTON_RIGHT:
				_line_retrieve_held = mb.pressed
				if mb.pressed:
					line_retrieve_requested.emit(LINE_STRIP_AMOUNT)
				get_viewport().set_input_as_handled()
				return
			if mb.pressed and mb.button_index == MOUSE_BUTTON_MIDDLE:
				hookset_requested.emit()
				get_viewport().set_input_as_handled()
				return

	if not (event is InputEventMouseMotion):
		return
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		return
	if _camera_hover_active:
		return
	var motion := event as InputEventMouseMotion
	if _game_mode == GameMode.EXPLORE:
		rotate_y(-motion.relative.x * mouse_sensitivity)
		_pitch = clampf(_pitch - motion.relative.y * mouse_sensitivity, MIN_PITCH, MAX_PITCH)
		head.rotation.x = _pitch
	elif _game_mode == GameMode.CAST and not _replaying:
		_cast_mouse_dx += motion.relative.x
		_cast_mouse_dy += motion.relative.y


func _physics_process(_delta: float) -> void:
	var speed_scale := CAST_SPEED_SCALE if _game_mode == GameMode.CAST else 1.0

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
	speed *= speed_scale

	velocity.x = move_dir.x * speed
	velocity.y = 0.0
	velocity.z = move_dir.z * speed
	move_and_slide()

	if river_world == null or not river_world.has_method("clamp_player_position"):
		return
	var clamped: Vector3 = river_world.clamp_player_position(global_position)
	if river_world.has_method("surface_height"):
		clamped.y = river_world.surface_height(clamped)
	global_position = clamped


# --- Mode transitions ---

func enter_cast_mode(target_world_pos: Vector3) -> void:
	_game_mode = GameMode.CAST
	_cast_mouse_dx = 0.0
	_cast_mouse_dy = 0.0
	_rod_lateral = 0.0
	_rod_lateral_target = 0.0
	_line_feed_held = false
	_line_retrieve_held = false
	_cast_view_far = false
	face_toward(target_world_pos)
	rod.enter_casting_stance()
	_mount_rod_on_hand()
	_enter_cast_camera(target_world_pos)
	if _angler_body != null:
		_angler_body.visible = true


func enter_explore_mode() -> void:
	_game_mode = GameMode.EXPLORE
	_line_feed_held = false
	_line_retrieve_held = false
	_unmount_rod_from_hand()
	if rod != null:
		rod.exit_casting_stance()
		rod.set_cast_aim(0.0)
		if rod.has_method("enter_explore_rest"):
			rod.enter_explore_rest()
	if _angler_body != null:
		_angler_body.visible = false
	_exit_cast_camera()


# Reparents the rod from the first-person camera onto the right-hand bone, so the
# casting arm physically carries it. No-op headless (no hand attachment built).
func _mount_rod_on_hand() -> void:
	if rod == null or _grip_socket == null:
		return
	if rod.get_parent() == _grip_socket:
		return
	rod.reparent(_grip_socket, false)
	rod.transform = Transform3D(Basis.IDENTITY, Vector3.ZERO)


func _unmount_rod_from_hand() -> void:
	if rod == null or _grip_socket == null or _rod_home_parent == null:
		return
	if rod.get_parent() != _grip_socket:
		return
	rod.reparent(_rod_home_parent, false)
	rod.transform = _rod_home_xform


# Backward-compat wrappers called by river_world_3d
func enter_casting_stance(target_world_pos: Vector3) -> void:
	enter_cast_mode(target_world_pos)


func exit_casting_stance() -> void:
	enter_explore_mode()


# --- Cast camera ---

func _enter_cast_camera(target_world_pos: Vector3) -> void:
	if _cast_camera == null:
		return
	_saved_camera_fov = camera.fov
	_saved_camera_transform = camera.global_transform
	camera.current = false
	_cast_camera.current = true
	_cast_camera_ready = false
	var start_pos := _cast_camera_world_pos()
	_cast_camera.global_position = start_pos
	var look_dir := (_cast_look_ahead_point() - start_pos).normalized()
	if look_dir.length_squared() > 0.001:
		_cast_camera.global_transform.basis = Basis.looking_at(look_dir, Vector3.UP)
	var t := create_tween()
	t.tween_interval(CAST_CAM_ENTRY_DELAY)
	t.tween_callback(func(): _cast_camera_ready = true)


func _exit_cast_camera() -> void:
	if _cast_camera == null:
		return
	_cast_camera.current = false
	camera.current = true
	_cast_camera_ready = false


func _cast_camera_world_pos() -> Vector3:
	var preset := _cast_preset()
	var back_basis := Basis(Vector3.UP, global_rotation.y)
	var back_offset := back_basis * Vector3(0.0, 0.0, float(preset[0]))
	return global_position + back_offset + Vector3(0.0, float(preset[1]), 0.0)


func _cast_look_ahead_point() -> Vector3:
	var preset := _cast_preset()
	var forward := -global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() > 0.001:
		forward = forward.normalized()
	return global_position + forward * float(preset[2]) + Vector3(0.0, float(preset[3]), 0.0)


func _update_cast_camera(delta: float) -> void:
	if _cast_camera == null:
		return
	var follow := minf(delta * CAST_CAM_FOLLOW, 1.0)
	var target_pos := _cast_camera_world_pos()
	_cast_camera.global_position = _cast_camera.global_position.lerp(target_pos, follow)
	var look_at := _cast_look_ahead_point()
	var look_dir := (look_at - _cast_camera.global_position).normalized()
	if look_dir.length_squared() > 0.001:
		_cast_camera.global_transform.basis = _cast_camera.global_transform.basis.slerp(
			Basis.looking_at(look_dir, Vector3.UP), follow
		)
	_cast_camera.fov = lerpf(_cast_camera.fov, float(_cast_preset()[4]), follow)


func toggle_cast_camera_view() -> void:
	_cast_view_far = not _cast_view_far


# --- Rod aim (CAST mode) ---

func _update_rod_aim(delta: float) -> void:
	_last_cast_motion = Vector2(_cast_mouse_dx, _cast_mouse_dy)
	# Lateral (casting plane): deadzone ignores jitter; deliberate horizontal input
	# steers, otherwise the plane springs back to the target-aligned vertical (0).
	if absf(_cast_mouse_dx) > CAST_ROD_LATERAL_DEADZONE:
		_rod_lateral_target += _cast_mouse_dx * cast_rod_lateral_sens
	else:
		_rod_lateral_target = lerpf(_rod_lateral_target, 0.0, minf(delta * cast_plane_center_rate, 1.0))
	# Vertical (elevation): mouse up raises the rod (push the rod up to backcast).
	if rod != null and _cast_mouse_dy != 0.0:
		rod.apply_mouse_elevation(-_cast_mouse_dy)
	_prev_cast_mouse_dy = _cast_mouse_dy
	_cast_mouse_dx = 0.0
	_cast_mouse_dy = 0.0
	_rod_lateral = lerpf(_rod_lateral, _rod_lateral_target, minf(delta * 8.0, 1.0))
	if rod != null:
		rod.set_cast_aim(_rod_lateral)


# --- Line hold (CAST mode) ---

func _update_line_hold(delta: float) -> void:
	if _line_feed_held:
		line_feed_requested.emit(LINE_FEED_RATE * delta)
	if _line_retrieve_held:
		line_retrieve_requested.emit(LINE_RETRIEVE_RATE * delta)


# --- Cast motion capture (dev tuning tool: F9 record, F10 replay) ---

func toggle_cast_capture() -> void:
	if _replaying:
		_capture_notify("Stop replay before recording.")
		return
	if _capturing:
		_capturing = false
		var path := _write_capture_csv()
		_capture_notify("Capture saved (%d frames): %s" % [_capture_frames.size(), path])
		return
	_capture_frames.clear()
	_capture_clock = 0.0
	_capturing = true
	_capture_notify("Recording cast motion… F9 to stop.")


func _record_capture_frame(delta: float) -> void:
	_capture_clock += delta
	_capture_frames.append({
		"t": _capture_clock,
		"dx": _last_cast_motion.x,
		"dy": _last_cast_motion.y,
		"elev": _rod_elevation_value(),
		"lateral": _rod_lateral,
		"state": _world_str("_gesture_state"),
		"arc": _world_num("_arc_cursor"),
		"loop": _world_str("_loop_quality"),
	})


func _write_capture_csv() -> String:
	DirAccess.make_dir_recursive_absolute(CAST_CAPTURE_DIR)
	var file_path := "%s/cast_%d.csv" % [CAST_CAPTURE_DIR, int(Time.get_unix_time_from_system())]
	var f := FileAccess.open(file_path, FileAccess.WRITE)
	if f == null:
		return "(write failed)"
	f.store_line("t,dx,dy,elev,lateral,state,arc,loop")
	for fr in _capture_frames:
		f.store_line("%.4f,%.2f,%.2f,%.4f,%.4f,%s,%.3f,%s" % [
			fr["t"], fr["dx"], fr["dy"], fr["elev"], fr["lateral"], fr["state"], fr["arc"], fr["loop"]])
	f.close()
	return ProjectSettings.globalize_path(file_path)


func toggle_cast_replay() -> void:
	if _capturing:
		_capture_notify("Stop recording before replay.")
		return
	if _replaying:
		_end_replay("Replay cancelled.")
		return
	if _game_mode != GameMode.CAST:
		_capture_notify("Select a water target first, then F10 to replay.")
		return
	var frames: Array[Dictionary] = _capture_frames if not _capture_frames.is_empty() else _load_latest_capture()
	if frames.is_empty():
		_capture_notify("No capture to replay. Record one with F9 first.")
		return
	_replay_frames = frames
	_replay_index = 0
	_replaying = true
	_cast_mouse_dx = 0.0
	_cast_mouse_dy = 0.0
	_rod_lateral = 0.0
	_rod_lateral_target = 0.0
	if rod != null:
		rod.enter_casting_stance()
	_capture_notify("Replaying %d frames…" % _replay_frames.size())


func _feed_replay_frame() -> void:
	if _replay_index >= _replay_frames.size():
		_end_replay("Replay complete.")
		return
	var fr: Dictionary = _replay_frames[_replay_index]
	_cast_mouse_dx = float(fr["dx"])
	_cast_mouse_dy = float(fr["dy"])
	_replay_index += 1


func _end_replay(message: String) -> void:
	_replaying = false
	_replay_index = 0
	_cast_mouse_dx = 0.0
	_cast_mouse_dy = 0.0
	_capture_notify(message)


func _load_latest_capture() -> Array[Dictionary]:
	var frames: Array[Dictionary] = []
	var dir := DirAccess.open(CAST_CAPTURE_DIR)
	if dir == null:
		return frames
	var latest := ""
	for file_name in dir.get_files():
		if file_name.ends_with(".csv") and file_name > latest:
			latest = file_name
	if latest == "":
		return frames
	var f := FileAccess.open("%s/%s" % [CAST_CAPTURE_DIR, latest], FileAccess.READ)
	if f == null:
		return frames
	f.get_line()  # header
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line == "":
			continue
		var cols := line.split(",")
		if cols.size() < 3:
			continue
		frames.append({"dx": float(cols[1]), "dy": float(cols[2])})
	f.close()
	return frames


func _rod_elevation_value() -> float:
	if rod != null and rod.has_method("get_elevation_offset"):
		return rod.get_elevation_offset()
	return 0.0


func _world_str(prop: String) -> String:
	if river_world == null:
		return ""
	var v = river_world.get(prop)
	return str(v) if v != null else ""


func _world_num(prop: String) -> float:
	if river_world == null:
		return 0.0
	var v = river_world.get(prop)
	return float(v) if v != null else 0.0


func _capture_notify(message: String) -> void:
	if river_world != null and river_world.has_method("_show_cast_message"):
		river_world._show_cast_message(message, 2.5)
	if OS.is_debug_build():
		print("[cast-capture] ", message)


# --- Shared helpers ---

func is_in_cast_mode() -> bool:
	return _game_mode == GameMode.CAST


func get_rod_aim_yaw() -> float:
	return _rod_lateral


func get_cast_input_state() -> Dictionary:
	# For casting simulation: return rod elevation and mouse acceleration
	return {
		"elevation": rod.get_elevation_offset() if rod != null else 0.0,
		"mouse_dy": _prev_cast_mouse_dy
	}


func apply_cast_mouse_motion(relative: Vector2) -> void:
	if _game_mode == GameMode.CAST:
		_cast_mouse_dx += relative.x
		_cast_mouse_dy += relative.y


func set_initial_pitch(pitch: float) -> void:
	_pitch = clampf(pitch, MIN_PITCH, MAX_PITCH)
	head.rotation.x = _pitch


func play_cast_animation(style: String = "overhead") -> void:
	if rod != null:
		rod.play_cast(style)


func face_toward(world_pos: Vector3) -> void:
	var flat_target := Vector3(world_pos.x, global_position.y, world_pos.z)
	if flat_target.distance_squared_to(global_position) < 0.001:
		return
	look_at(flat_target, Vector3.UP)
	_pitch = clampf(deg_to_rad(-18.0), MIN_PITCH, MAX_PITCH)
	head.rotation.x = _pitch


func set_camera_fov(target_fov: float) -> void:
	if camera != null:
		camera.fov = target_fov


func camera_fov() -> float:
	if camera == null:
		return 68.0
	return camera.fov


func tween_camera_to_hover(target_world_pos: Vector3, hover_height: float = 2.2, target_fov: float = 52.0, duration: float = 0.6) -> void:
	if camera == null:
		return
	if _cast_camera != null:
		_cast_camera.current = false
	camera.current = true
	_saved_camera_transform = camera.global_transform
	_saved_camera_fov = camera.fov
	camera.set_as_top_level(true)
	_camera_hover_active = true
	var clamped_height := maxf(hover_height, 0.3)
	var hover_pos := Vector3(target_world_pos.x, target_world_pos.y + clamped_height, target_world_pos.z)
	var look_dir := (target_world_pos - hover_pos).normalized()
	var hover_basis := Basis.looking_at(look_dir, Vector3.UP)
	var target_transform := Transform3D(hover_basis, hover_pos)
	if _camera_tween != null and _camera_tween.is_valid():
		_camera_tween.kill()
	_camera_tween = create_tween()
	_camera_tween.set_ease(Tween.EASE_IN_OUT)
	_camera_tween.set_trans(Tween.TRANS_CUBIC)
	_camera_tween.tween_property(camera, "global_transform", target_transform, duration)
	_camera_tween.parallel().tween_property(camera, "fov", target_fov, duration)


func restore_camera(duration: float = 0.4) -> void:
	if camera == null or not _camera_hover_active:
		return
	if _camera_tween != null and _camera_tween.is_valid():
		_camera_tween.kill()
	_camera_tween = create_tween()
	_camera_tween.set_ease(Tween.EASE_IN_OUT)
	_camera_tween.set_trans(Tween.TRANS_CUBIC)
	_camera_tween.tween_property(camera, "global_transform", _saved_camera_transform, duration)
	_camera_tween.parallel().tween_property(camera, "fov", _saved_camera_fov, duration)
	_camera_tween.tween_callback(func():
		camera.set_as_top_level(false)
		_camera_hover_active = false
	)


func _request_target_selection() -> void:
	if camera == null:
		return
	var origin: Vector3 = rod.tip_global_position()
	var direction := -camera.global_transform.basis.z.normalized()
	cast_target_requested.emit(origin, direction)
