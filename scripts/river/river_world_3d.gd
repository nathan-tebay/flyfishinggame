class_name RiverWorld3D
extends Node3D

const DifficultyConfig = preload("res://resources/difficulty_config.gd")
const LowerMadisonReachScript = preload("res://scripts/river/lower_madison_reach.gd")
const River3DBuilderScript = preload("res://scripts/river/river_3d_builder.gd")
const FirstPersonAnglerScript = preload("res://scripts/player/first_person_angler.gd")
const AdultInsectScript = preload("res://scripts/models/adult_insect_3d.gd")
const MAT_FLY_LINE = preload("res://assets/3d/materials/fly_line.tres")
const MAT_LEADER = preload("res://assets/3d/materials/leader.tres")
const MAT_MEADOW = preload("res://assets/3d/materials/meadow_grass.tres")
const MAT_MOUNTAIN = preload("res://assets/3d/materials/distant_mountain.tres")
const MAT_WATER = preload("res://assets/3d/materials/river_water.tres")
const FLY_OPTIONS := [
	{"name": "Blue-Winged Olive Dun", "species": "Mayfly", "phase": "Adult", "kind": 0},
	{"name": "Elk Hair Caddis", "species": "Caddis", "phase": "Adult", "kind": 1},
]
const DEBUG_VIEW_NAMES := [
	"off",
	"depth",
	"current",
	"turbulence / foam",
	"curvature",
	"normal flow",
]
const DRY_FLY_DRIFT_DURATION := 8.0
const DRY_FLY_FLOW_SCALE := 1.85
const DRY_FLY_SURFACE_OFFSET := 0.065
const DRY_FLY_MAX_DRAG := 1.0
const LEADER_LENGTH := 2.45
const CAST_LINE_SEGMENTS := 7
const CAST_LINE_CURRENT_BOW := 0.34
const CAST_LINE_SAG := 0.55
const CAST_LEADER_TRANSITION_BLEND := 0.12
const CAST_LINE_REBUILD_DISTANCE_SQUARED := 0.0025
const FISH_TAKE_RADIUS := 2.45
const FISH_TAKE_MIN_AGE := 0.35
const FISH_TAKE_WINDOW_FALLBACK := 1.15
const FISH_ALERT_RECOVERY_RATE := 0.18
const FISH_SPOOK_RECOVERY_RATE := 0.07
const FISH_FEEDING_ALERT_LIMIT := 0.38
const NET_SAMPLE_COOLDOWN := 2.0
const CAST_TARGET_NUDGE_SPEED := 6.8
const CAST_ZOOM_FOVS := [68.0, 48.0, 32.0]
const AMBIENT_UPDATE_INTERVAL := 0.10
const FISH_AI_UPDATE_INTERVAL := 0.12
const HUD_UPDATE_INTERVAL := 0.25
const LIGHT_UPDATE_INTERVAL := 0.50
const FOAM_FLECK_SPAWN_INTERVAL := 0.28
const MAX_FOAM_FLECKS := 36
const MAX_POOLED_FOAM_FLECKS := 48
const MAX_POOLED_RISE_RINGS := 16
const RISE_RING_SEGMENTS := 36

@onready var builder: River3DBuilderScript = $River3DBuilder
@onready var angler: FirstPersonAnglerScript = $FirstPersonAngler
@onready var status_label: Label = $HUD/StatusLabel
@onready var cast_label: Label = $HUD/CastLabel
@onready var fly_label: Label = $HUD/TacklePanel/Margin/VBox/FlyLabel
@onready var cast_state_label: Label = $HUD/TacklePanel/Margin/VBox/CastStateLabel
@onready var hatch_label: Label = $HUD/TacklePanel/Margin/VBox/HatchLabel

var _casting_loop_label: Label = null

var reach: LowerMadisonReachScript = null
var _cast_line: MeshInstance3D = null
var _leader_line: MeshInstance3D = null
var _cast_marker: Node3D = null
var _last_cast_line_origin := Vector3.ZERO
var _last_cast_line_target := Vector3.ZERO
var _last_cast_line_state := ""
var _last_cast_line_fly_index := -1
var _cast_line_cache_valid := false
var _cast_target_marker: MeshInstance3D = null
var _selected_cast_target: Dictionary = {}
var _cast_message := ""
var _cast_message_timer := 0.0
var _selected_fly_index := 0
var _cast_state := "READY TO CAST"
var _post_cast_state := "READY TO CAST"
var _cast_state_timer := 0.0
var _debug_view := 0
var _debug_label: Label = null
var _last_wadable_player_position := Vector3.ZERO
var _sun: DirectionalLight3D = null
var _environment: Environment = null
var _sky_material: ProceduralSkyMaterial = null
var _rise_material: StandardMaterial3D = null
var _foam_material: StandardMaterial3D = null
var _bird_material: StandardMaterial3D = null
var _rise_ring_mesh: ImmediateMesh = null
var _foam_fleck_mesh: ArrayMesh = null
var _surface_rises: Array[Dictionary] = []
var _foam_flecks: Array[Dictionary] = []
var _surface_rise_pool: Array[MeshInstance3D] = []
var _foam_fleck_pool: Array[MeshInstance3D] = []
var _rise_timer := 0.0
var _foam_timer := 0.0
var _ambient_update_accumulator := 0.0
var _fish_ai_update_accumulator := 0.0
var _hud_update_accumulator := 0.0
var _light_update_accumulator := 0.0
var _bird_flock: Node3D = null
var _bird_entries: Array[Dictionary] = []
var _active_drift: Dictionary = {}
var _drift_readout := ""
var _pending_take: Dictionary = {}
var _session_stats := {
	"hooked": 0,
	"landed": 0,
	"missed": 0,
	"spooked": 0,
	"samples": 0,
	"last_catch": "",
}
var _last_net_sample: Dictionary = {}
var _net_sample_timer := 0.0
var _last_sound_cue := ""
var _default_camera_fov := 68.0
var _cast_zoom_index := 0
var ambient_effect_density := 1.0


func _ready() -> void:
	process_priority = 20
	_ensure_session()
	_setup_lighting()
	_generate_river()
	_build_background_landscape()
	_build_bird_flock()
	_setup_casting_loop_hud()
	_setup_debug_hud()
	_place_player()
	angler.river_world = self
	_default_camera_fov = angler.camera_fov()
	angler.cast_target_requested.connect(_on_cast_target_requested)
	angler.cast_loop_requested.connect(_on_cast_loop_requested)
	angler.cast_commit_requested.connect(_on_cast_commit_requested)
	angler.fly_change_requested.connect(_on_fly_change_requested)
	_show_cast_message("Black's Ford Bend loaded. Q changes adult dry fly; click or Space casts.", 5.0)
	_update_hud()


func _process(delta: float) -> void:
	_update_time_critical_state(delta)
	_update_scheduled_systems(delta)
	_refresh_cast_line_attachment()


func _update_time_critical_state(delta: float) -> void:
	_update_dry_fly_drift(delta)
	_update_cast_target_controls(delta)
	_net_sample_timer = maxf(_net_sample_timer - delta, 0.0)
	if _cast_message_timer > 0.0:
		_cast_message_timer = maxf(_cast_message_timer - delta, 0.0)
		if _cast_message_timer <= 0.0:
			_cast_message = ""
	if _cast_state_timer > 0.0:
		_cast_state_timer = maxf(_cast_state_timer - delta, 0.0)
		if _cast_state_timer <= 0.0:
			_cast_state = _post_cast_state


func _update_scheduled_systems(delta: float) -> void:
	_light_update_accumulator += delta
	if _light_update_accumulator >= LIGHT_UPDATE_INTERVAL:
		_update_living_light()
		_light_update_accumulator = 0.0

	_ambient_update_accumulator += delta
	if _ambient_update_accumulator >= AMBIENT_UPDATE_INTERVAL:
		var ambient_delta := _ambient_update_accumulator
		_ambient_update_accumulator = 0.0
		_update_surface_rises(ambient_delta)
		_update_foam_flecks(ambient_delta)
		_update_bird_flock(ambient_delta)

	_fish_ai_update_accumulator += delta
	if _fish_ai_update_accumulator >= FISH_AI_UPDATE_INTERVAL:
		var fish_delta := _fish_ai_update_accumulator
		_fish_ai_update_accumulator = 0.0
		_update_fish_ai(fish_delta)

	_hud_update_accumulator += delta
	if _hud_update_accumulator >= HUD_UPDATE_INTERVAL:
		_update_hud()
		_hud_update_accumulator = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if _selected_cast_target.is_empty() or not mouse_button.pressed:
			pass
		elif mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_adjust_cast_zoom(1)
			get_viewport().set_input_as_handled()
			return
		elif mouse_button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_adjust_cast_zoom(-1)
			get_viewport().set_input_as_handled()
			return
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed:
		return
	if key.echo:
		return
	if not _selected_cast_target.is_empty():
		if event.is_action_pressed("cast_zoom_in"):
			_adjust_cast_zoom(1)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("cast_zoom_out"):
			_adjust_cast_zoom(-1)
			get_viewport().set_input_as_handled()
			return
	if key.physical_keycode == KEY_N:
		try_net_sample()
		get_viewport().set_input_as_handled()
		return
	var requested_view := _debug_view_for_key(key.physical_keycode)
	if requested_view < 0:
		return
	_set_debug_view(requested_view)
	get_viewport().set_input_as_handled()


func is_casting_control_active() -> bool:
	return not _selected_cast_target.is_empty()


func movement_speed_at(world_pos: Vector3, walk_speed: float, wade_speed: float) -> float:
	var sample := reach.sample(world_pos)
	if not bool(sample["is_water"]):
		return walk_speed
	if not bool(sample["is_wadable"]):
		return 0.0
	var drag := clampf(float(sample["depth"]) * 0.62 + float(sample["current_strength"]) * 0.38, 0.0, 1.0)
	return lerpf(walk_speed, wade_speed, drag)


func clamp_player_position(world_pos: Vector3) -> Vector3:
	world_pos = _clamp_to_world_bounds(world_pos)
	var sample := reach.sample(world_pos)
	if _can_player_stand(sample):
		_last_wadable_player_position = world_pos
		return world_pos
	return _last_wadable_player_position


func _clamp_to_world_bounds(world_pos: Vector3) -> Vector3:
	var bounds := builder.world_bounds()
	world_pos.x = clampf(world_pos.x, bounds.position.x, bounds.position.x + bounds.size.x)
	world_pos.z = clampf(world_pos.z, bounds.position.y, bounds.position.y + bounds.size.y)
	return world_pos


func _can_player_stand(sample: Dictionary) -> bool:
	if not bool(sample["is_water"]):
		return true
	return bool(sample["is_wadable"])


func _debug_view_for_key(keycode: Key) -> int:
	match keycode:
		KEY_0:
			return 0
		KEY_1:
			return 1
		KEY_2:
			return 2
		KEY_3:
			return 3
		KEY_4:
			return 4
		KEY_5:
			return 5
	return -1


func _set_debug_view(view: int) -> void:
	_debug_view = clampi(view, 0, DEBUG_VIEW_NAMES.size() - 1)
	if MAT_WATER is ShaderMaterial:
		(MAT_WATER as ShaderMaterial).set_shader_parameter("debug_view", _debug_view)
	if _debug_label == null:
		return
	_debug_label.visible = _debug_view > 0


func surface_height(world_pos: Vector3) -> float:
	var sample := reach.sample(world_pos)
	return float(sample["bed_height"]) if bool(sample["is_water"]) else reach.terrain_height_at(world_pos)


func is_wading(world_pos: Vector3) -> bool:
	var sample := reach.sample(world_pos)
	if not bool(sample["is_water"]):
		return false
	return bool(sample["is_wadable"])


func get_session_stats() -> Dictionary:
	return _session_stats.duplicate(true)


func try_net_sample() -> Dictionary:
	if _net_sample_timer > 0.0 and not _last_net_sample.is_empty():
		return _last_net_sample.duplicate(true)
	var profiles: Array[Dictionary] = []
	for profile in HatchManager.active_profiles:
		var hatch := (profile as Dictionary).duplicate(true)
		hatch["bar"] = _abundance_bar(float(hatch.get("abundance", 0.0)))
		profiles.append(hatch)
	var summary := "Net sample: sparse surface life"
	if not profiles.is_empty():
		var parts: Array[String] = []
		for hatch in profiles:
			parts.append("%s %s %s" % [String(hatch["bar"]), String(hatch["species"]).capitalize(), String(hatch["stage"])])
		summary = "Net sample: %s" % "; ".join(parts)
	_last_net_sample = {
		"profiles": profiles,
		"summary": summary,
		"hour": TimeOfDay.current_hour,
		"state": HatchManager.hatch_state_name(),
	}
	_session_stats["samples"] = int(_session_stats.get("samples", 0)) + 1
	_net_sample_timer = NET_SAMPLE_COOLDOWN
	_show_cast_message(summary, 4.2)
	_play_sound_cue("net_sample")
	return _last_net_sample.duplicate(true)


func try_hookset() -> bool:
	if _pending_take.is_empty():
		return false
	var fish_name := String(_pending_take.get("fish_name", "fish"))
	var fly_name := String(_active_drift.get("fly_name", "dry fly"))
	var window := _hookset_window_duration()
	var elapsed := float(_pending_take.get("age", 0.0))
	var hooked := elapsed <= window
	var fish := _pending_take.get("fish", {}) as Dictionary
	_pending_take.clear()
	_active_drift.clear()
	_drift_readout = ""
	_cast_state = "READY TO CAST"
	_post_cast_state = "READY TO CAST"
	_cast_state_timer = 0.0
	if hooked:
		_session_stats["hooked"] = int(_session_stats.get("hooked", 0)) + 1
		_land_hooked_fish(fish, fly_name)
	else:
		_session_stats["missed"] = int(_session_stats.get("missed", 0)) + 1
		_play_sound_cue("missed_take")
		_show_cast_message("Late hookset. The %s boiled and missed the %s." % [fish_name, fly_name], 3.2)
	return true


func _ensure_session() -> void:
	if GameManager.session_id >= 0:
		return
	GameManager.new_session(12345, 6.0, DifficultyConfig.Tier.STANDARD)


func _setup_lighting() -> void:
	var world_environment := WorldEnvironment.new()
	_environment = Environment.new()
	var sky := Sky.new()
	_sky_material = ProceduralSkyMaterial.new()
	_sky_material.sky_curve = 0.16
	_sky_material.ground_curve = 0.12
	_sky_material.sun_angle_max = 2.2
	_sky_material.sun_curve = 0.10
	sky.sky_material = _sky_material
	_environment.background_mode = Environment.BG_SKY
	_environment.sky = sky
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_environment.fog_enabled = true
	_environment.fog_density = 0.00035
	_environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_environment.adjustment_enabled = true
	_environment.adjustment_contrast = 1.08
	_environment.adjustment_saturation = 1.02
	world_environment.environment = _environment
	add_child(world_environment)

	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 180.0
	add_child(_sun)

	_rise_material = StandardMaterial3D.new()
	_rise_material.albedo_color = Color(0.82, 0.90, 0.96, 0.56)
	_rise_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_rise_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	_foam_material = StandardMaterial3D.new()
	_foam_material.albedo_color = Color(0.86, 0.94, 0.94, 0.34)
	_foam_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_foam_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_foam_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	_bird_material = StandardMaterial3D.new()
	_bird_material.albedo_color = Color(0.025, 0.030, 0.035, 1.0)
	_bird_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_rise_ring_mesh = _build_unit_rise_ring_mesh()
	_foam_fleck_mesh = _build_unit_foam_fleck_mesh()
	_update_living_light()


func _update_living_light() -> void:
	var daylight := clampf(TimeOfDay.light_level, 0.0, 1.0)
	var dawn_dusk := 1.0 - absf(clampf((TimeOfDay.current_hour - 12.0) / 7.0, -1.0, 1.0))
	var warm_edge := clampf(1.0 - daylight + dawn_dusk * 0.24, 0.0, 1.0)
	if _sun != null:
		var sun_t := clampf((TimeOfDay.current_hour - 5.4) / 13.2, 0.0, 1.0)
		var elevation := sin(sun_t * PI)
		var azimuth := lerpf(-82.0, 98.0, sun_t)
		_sun.rotation_degrees = Vector3(lerpf(-8.0, -58.0, elevation), azimuth, 0.0)
		_sun.light_energy = lerpf(0.10, 1.06, daylight)
		_sun.light_color = Color(1.0, lerpf(0.72, 0.96, daylight), lerpf(0.55, 0.86, daylight))
	if _sky_material != null:
		_sky_material.sky_top_color = Color(lerpf(0.045, 0.10, daylight), lerpf(0.070, 0.25, daylight), lerpf(0.13, 0.46, daylight))
		_sky_material.sky_horizon_color = Color(lerpf(0.22, 0.40, daylight) + warm_edge * 0.18, lerpf(0.25, 0.56, daylight) + warm_edge * 0.06, lerpf(0.31, 0.70, daylight))
		_sky_material.ground_bottom_color = Color(0.08, lerpf(0.10, 0.14, daylight), 0.10)
		_sky_material.ground_horizon_color = Color(lerpf(0.18, 0.37, daylight), lerpf(0.24, 0.46, daylight), lerpf(0.20, 0.40, daylight))
	if _environment != null:
		_environment.ambient_light_color = Color(lerpf(0.24, 0.54, daylight), lerpf(0.30, 0.60, daylight), lerpf(0.36, 0.61, daylight))
		_environment.ambient_light_energy = lerpf(0.18, 0.47, daylight)
		_environment.fog_light_color = Color(lerpf(0.28, 0.60, daylight) + warm_edge * 0.12, lerpf(0.33, 0.68, daylight) + warm_edge * 0.04, lerpf(0.42, 0.72, daylight))
		_environment.adjustment_brightness = lerpf(0.54, 0.87, daylight)


func _ambient_density_factor() -> float:
	return clampf(ambient_effect_density, 0.0, 2.0)


func _ambient_spawn_interval(base_interval: float, density: float) -> float:
	if density <= 0.0:
		return base_interval * 4.0
	return base_interval / density


func _ambient_foam_limit() -> int:
	return int(round(float(MAX_FOAM_FLECKS) * _ambient_density_factor()))


func _update_surface_rises(delta: float) -> void:
	if DisplayServer.get_name() == "headless" or reach == null:
		return
	_rise_timer -= delta
	var density := _ambient_density_factor()
	if _rise_timer <= 0.0:
		if density > 0.0:
			_spawn_surface_rise()
		_rise_timer = _ambient_spawn_interval(lerpf(0.75, 2.20, 1.0 - clampf(TimeOfDay.light_level, 0.0, 1.0)), density)
	for i in range(_surface_rises.size() - 1, -1, -1):
		var rise := _surface_rises[i]
		var age := float(rise["age"]) + delta
		var duration := float(rise["duration"])
		if age >= duration:
			var old_node := rise["node"] as MeshInstance3D
			if old_node != null and is_instance_valid(old_node):
				_release_rise_ring(old_node)
			_surface_rises.remove_at(i)
			continue
		rise["age"] = age
		_update_rise_ring(rise)
		_surface_rises[i] = rise


func _spawn_surface_rise() -> void:
	var holds := reach.hold_points()
	if holds.is_empty():
		return
	var tick := int(Time.get_ticks_msec() / 733) + GameManager.session_seed
	var hold := holds[posmod(tick, holds.size())] as Dictionary
	var fraction := float(hold["fraction"])
	var lateral := float(hold["lateral"])
	var depth := reach.water_depth_at(fraction, lateral)
	if depth < 0.22:
		return
	var offset := Vector3(sin(float(tick) * 0.87) * 0.38, 0.0, cos(float(tick) * 0.61) * 0.28)
	var center := reach.position_at(fraction, lateral, LowerMadisonReachScript.WATER_HEIGHT + 0.027) + offset
	_spawn_surface_rise_at(center, 0.58 + clampf(depth, 0.0, 0.7) * 0.58)


func _spawn_surface_rise_at(center: Vector3, max_radius: float) -> void:
	if DisplayServer.get_name() == "headless" or _rise_material == null:
		return
	var ring := _acquire_rise_ring()
	var rise := {
		"node": ring,
		"material": ring.material_override,
		"center": center,
		"age": 0.0,
		"duration": 1.55,
		"max_radius": max_radius,
	}
	_update_rise_ring(rise)
	_surface_rises.append(rise)


func _update_rise_ring(rise: Dictionary) -> void:
	var ring := rise["node"] as MeshInstance3D
	if ring == null or not is_instance_valid(ring):
		return
	var age := float(rise["age"])
	var duration := float(rise["duration"])
	var progress := clampf(age / duration, 0.0, 1.0)
	var radius := lerpf(0.10, float(rise["max_radius"]), progress)
	ring.position = rise["center"] as Vector3
	ring.scale = Vector3(radius, 1.0, radius)
	ring.visible = true
	var mat := rise["material"] as StandardMaterial3D
	if mat != null:
		mat.albedo_color = Color(0.82, 0.90, 0.96, 0.56 * (1.0 - progress))


func _update_foam_flecks(delta: float) -> void:
	if DisplayServer.get_name() == "headless" or reach == null:
		return
	_foam_timer -= delta
	var density := _ambient_density_factor()
	if _foam_timer <= 0.0:
		if density > 0.0:
			_spawn_foam_fleck()
		_foam_timer = _ambient_spawn_interval(FOAM_FLECK_SPAWN_INTERVAL, density)
	for i in range(_foam_flecks.size() - 1, -1, -1):
		var fleck := _foam_flecks[i]
		var age := float(fleck["age"]) + delta
		var duration := float(fleck["duration"])
		var node := fleck["node"] as MeshInstance3D
		if age >= duration or node == null or not is_instance_valid(node):
			if node != null and is_instance_valid(node):
				_release_foam_fleck(node)
			_foam_flecks.remove_at(i)
			continue
		var velocity := fleck["velocity"] as Vector3
		node.position += velocity * delta
		var progress := clampf(age / duration, 0.0, 1.0)
		var mat := fleck["material"] as StandardMaterial3D
		if mat != null:
			mat.albedo_color = Color(0.86, 0.94, 0.94, 0.32 * sin(progress * PI))
		fleck["age"] = age
		_foam_flecks[i] = fleck


func _spawn_foam_fleck() -> void:
	if _foam_flecks.size() >= _ambient_foam_limit():
		return
	var tick := int(Time.get_ticks_msec() / 227) + GameManager.session_seed * 3
	var fraction := 0.08 + fmod(float(tick) * 0.071, 0.84)
	var side := -1.0 if tick % 2 == 0 else 1.0
	var lateral := side * reach.half_width_at(fraction) * lerpf(0.42, 0.88, fmod(float(tick) * 0.37, 1.0))
	var foam_tendency := reach.foam_tendency_at(fraction, lateral)
	if foam_tendency < 0.10 and tick % 4 != 0:
		return
	var depth := reach.water_depth_at(fraction, lateral)
	if depth < 0.08:
		return
	var flow := reach.surface_flow_at(fraction, lateral)
	var speed := maxf(flow.length(), 0.18)
	var length := 0.12 + foam_tendency * 0.18
	var width := 0.035 + foam_tendency * 0.05
	var position := reach.position_at(fraction, lateral, LowerMadisonReachScript.WATER_HEIGHT + 0.034)
	position += Vector3(sin(float(tick) * 1.7), 0.0, cos(float(tick) * 1.1)) * 0.18
	var fleck := _acquire_foam_fleck()
	fleck.position = position
	fleck.scale = Vector3(length, 1.0, width)
	fleck.rotation = Vector3.ZERO
	if flow.length_squared() > 0.001:
		fleck.rotation.y = atan2(flow.x, flow.z)
	_foam_flecks.append({
		"node": fleck,
		"material": fleck.material_override,
		"age": 0.0,
		"duration": lerpf(4.0, 7.0, foam_tendency),
		"velocity": flow.normalized() * speed * 0.42,
	})


func _build_unit_foam_fleck_mesh() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var points := PackedVector3Array([
		Vector3(-1.0, 0.0, -1.0),
		Vector3(1.0, 0.0, 0.0),
		Vector3(-0.38, 0.0, 1.0),
	])
	for point in points:
		tool.add_vertex(point)
	tool.generate_normals()
	return tool.commit()


func _build_unit_rise_ring_mesh() -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, _rise_material)
	for segment in RISE_RING_SEGMENTS:
		var angle_a := TAU * float(segment) / float(RISE_RING_SEGMENTS)
		var angle_b := TAU * float(segment + 1) / float(RISE_RING_SEGMENTS)
		mesh.surface_add_vertex(Vector3(cos(angle_a), 0.0, sin(angle_a) * 0.62))
		mesh.surface_add_vertex(Vector3(cos(angle_b), 0.0, sin(angle_b) * 0.62))
	mesh.surface_end()
	return mesh


func _acquire_rise_ring() -> MeshInstance3D:
	var ring: MeshInstance3D = null
	while not _surface_rise_pool.is_empty() and ring == null:
		var candidate := _surface_rise_pool.pop_back() as MeshInstance3D
		if candidate != null and is_instance_valid(candidate):
			ring = candidate
	if ring == null:
		ring = MeshInstance3D.new()
		ring.name = "FishRiseRing"
		ring.mesh = _rise_ring_mesh
		ring.material_override = _rise_material.duplicate() as StandardMaterial3D
		add_child(ring)
	ring.visible = true
	return ring


func _release_rise_ring(ring: MeshInstance3D) -> void:
	ring.visible = false
	if _surface_rise_pool.size() >= MAX_POOLED_RISE_RINGS:
		ring.queue_free()
		return
	_surface_rise_pool.append(ring)


func _acquire_foam_fleck() -> MeshInstance3D:
	var fleck: MeshInstance3D = null
	while not _foam_fleck_pool.is_empty() and fleck == null:
		var candidate := _foam_fleck_pool.pop_back() as MeshInstance3D
		if candidate != null and is_instance_valid(candidate):
			fleck = candidate
	if fleck == null:
		fleck = MeshInstance3D.new()
		fleck.name = "DriftingFoamFleck"
		fleck.mesh = _foam_fleck_mesh
		fleck.material_override = _foam_material.duplicate() as StandardMaterial3D
		add_child(fleck)
	fleck.visible = true
	var mat := fleck.material_override as StandardMaterial3D
	if mat != null:
		mat.albedo_color = Color(0.86, 0.94, 0.94, 0.32)
	return fleck


func _release_foam_fleck(fleck: MeshInstance3D) -> void:
	fleck.visible = false
	if _foam_fleck_pool.size() >= MAX_POOLED_FOAM_FLECKS:
		fleck.queue_free()
		return
	_foam_fleck_pool.append(fleck)


func _build_bird_flock() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var bounds := builder.world_bounds()
	var center := Vector3(bounds.position.x + bounds.size.x * 0.50, 18.0, bounds.position.y + bounds.size.y * 0.52)
	_bird_flock = Node3D.new()
	_bird_flock.name = "DistantSwallows"
	add_child(_bird_flock)
	var bird_mesh := _bird_silhouette_mesh()
	for i in range(9):
		var bird := MeshInstance3D.new()
		bird.name = "CirclingSwallow%02d" % i
		bird.mesh = bird_mesh
		bird.material_override = _bird_material
		_bird_flock.add_child(bird)
		_bird_entries.append({
			"node": bird,
			"center": center + Vector3(float(i % 3 - 1) * 7.0, float(i % 2) * 1.4, float(i / 3 - 1) * 6.0),
			"angle": float(i) * 0.74,
			"radius": 11.0 + float(i % 4) * 2.1,
			"speed": 0.045 + float(i % 5) * 0.008,
			"height": 9.0 + float(i % 3) * 1.3,
		})


func _update_bird_flock(delta: float) -> void:
	if _bird_entries.is_empty():
		return
	for i in _bird_entries.size():
		var entry := _bird_entries[i]
		var bird := entry["node"] as MeshInstance3D
		if bird == null or not is_instance_valid(bird):
			continue
		var angle := float(entry["angle"]) + float(entry["speed"]) * delta
		var radius := float(entry["radius"])
		var center := entry["center"] as Vector3
		bird.position = center + Vector3(cos(angle) * radius, float(entry["height"]) + sin(angle * 2.1) * 0.55, sin(angle) * radius * 0.58)
		bird.rotation_degrees = Vector3(-8.0 + sin(angle * 3.0) * 6.0, -rad_to_deg(angle) + 90.0, sin(angle * 5.0) * 10.0)
		entry["angle"] = angle
		_bird_entries[i] = entry


func _bird_silhouette_mesh() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.add_vertex(Vector3(0.0, 0.0, 0.0))
	tool.add_vertex(Vector3(-0.46, 0.04, 0.10))
	tool.add_vertex(Vector3(-0.08, -0.02, 0.05))
	tool.add_vertex(Vector3(0.0, 0.0, 0.0))
	tool.add_vertex(Vector3(0.08, -0.02, 0.05))
	tool.add_vertex(Vector3(0.46, 0.04, 0.10))
	tool.generate_normals()
	return tool.commit()


func _generate_river() -> void:
	reach = LowerMadisonReachScript.new()
	builder.build(reach, GameManager.session_seed)


func _build_background_landscape() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var bounds := builder.world_bounds()
	var x0 := bounds.position.x - 40.0
	var x1 := bounds.position.x + bounds.size.x + 120.0
	var near_z := bounds.position.y - 18.0
	var far_z := bounds.position.y + bounds.size.y + 24.0
	_add_meadow_plane("NearMeadow", x0, x1, near_z - 120.0, near_z, 0.31)
	_add_meadow_plane("FarMeadow", x0, x1, far_z, far_z + 180.0, 0.31)
	_add_mountain_ridge("FarMadisonRange", x0, x1, far_z + 185.0, 4.8, 2.7)
	_add_mountain_ridge("NearBenchHills", x0, x1, near_z - 120.0, 2.2, 1.2)


func _add_meadow_plane(node_name: String, x0: float, x1: float, z0: float, z1: float, y: float) -> void:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_landscape_quad(tool, x0, z0, x1, z1, y)
	tool.generate_normals()
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = tool.commit()
	instance.material_override = MAT_MEADOW
	add_child(instance)


func _add_mountain_ridge(node_name: String, x0: float, x1: float, z: float, base_h: float, relief: float) -> void:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments := 32
	var front_z := z - 54.0
	var rear_z := z + 45.0
	var last_front := Vector3(x0, 0.25, front_z)
	var last_high := Vector3(x0, base_h + sin(x0 * 0.013) * relief, z)
	var last_rear := Vector3(x0, 0.05, rear_z)
	for i in range(1, segments + 1):
		var t := float(i) / float(segments)
		var x := lerpf(x0, x1, t)
		var high := Vector3(x, base_h + sin(x * 0.013) * relief + sin(x * 0.041) * relief * 0.35, z)
		var front := Vector3(x, 0.25, front_z)
		var rear := Vector3(x, 0.05, rear_z)
		tool.add_vertex(last_front)
		tool.add_vertex(last_high)
		tool.add_vertex(high)
		tool.add_vertex(last_front)
		tool.add_vertex(high)
		tool.add_vertex(front)
		tool.add_vertex(last_high)
		tool.add_vertex(last_rear)
		tool.add_vertex(rear)
		tool.add_vertex(last_high)
		tool.add_vertex(rear)
		tool.add_vertex(high)
		last_front = front
		last_high = high
		last_rear = rear
	tool.generate_normals()
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = tool.commit()
	instance.material_override = MAT_MOUNTAIN
	add_child(instance)


func _add_landscape_quad(tool: SurfaceTool, x0: float, z0: float, x1: float, z1: float, y: float) -> void:
	tool.set_uv(Vector2(0.0, 0.0))
	tool.add_vertex(Vector3(x0, y, z0))
	tool.set_uv(Vector2(1.0, 1.0))
	tool.add_vertex(Vector3(x1, y, z1))
	tool.set_uv(Vector2(1.0, 0.0))
	tool.add_vertex(Vector3(x1, y, z0))
	tool.set_uv(Vector2(0.0, 0.0))
	tool.add_vertex(Vector3(x0, y, z0))
	tool.set_uv(Vector2(0.0, 1.0))
	tool.add_vertex(Vector3(x0, y, z1))
	tool.set_uv(Vector2(1.0, 1.0))
	tool.add_vertex(Vector3(x1, y, z1))


func _setup_casting_loop_hud() -> void:
	_casting_loop_label = Label.new()
	_casting_loop_label.name = "CastingLoopHUD"
	_casting_loop_label.offset_left = 22.0
	_casting_loop_label.offset_top = 148.0
	_casting_loop_label.offset_right = 520.0
	_casting_loop_label.offset_bottom = 300.0
	_casting_loop_label.add_theme_color_override("font_color", Color(0.74, 0.94, 1.0, 0.96))
	_casting_loop_label.add_theme_color_override("font_outline_color", Color(0.02, 0.04, 0.05, 0.88))
	_casting_loop_label.add_theme_constant_override("outline_size", 3)
	$HUD.add_child(_casting_loop_label)


func _setup_debug_hud() -> void:
	_debug_label = Label.new()
	_debug_label.name = "DebugReadout"
	_debug_label.anchor_left = 1.0
	_debug_label.anchor_right = 1.0
	_debug_label.offset_left = -430.0
	_debug_label.offset_top = 18.0
	_debug_label.offset_right = -22.0
	_debug_label.offset_bottom = 190.0
	_debug_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_debug_label.add_theme_color_override("font_color", Color(0.72, 0.95, 0.88, 1.0))
	_debug_label.add_theme_color_override("font_outline_color", Color(0.02, 0.04, 0.04, 0.90))
	_debug_label.add_theme_constant_override("outline_size", 4)
	_debug_label.visible = false
	$HUD.add_child(_debug_label)
	_set_debug_view(0)


func _place_player() -> void:
	angler.global_position = builder.start_position()
	_last_wadable_player_position = angler.global_position
	var look_target := builder.look_target_from_start()
	angler.rotation.y = atan2(-(look_target.x - angler.global_position.x), -(look_target.z - angler.global_position.z))
	angler.set_initial_pitch(deg_to_rad(-8.0))


func _on_cast_target_requested(origin: Vector3, direction: Vector3) -> void:
	if direction.y >= -0.02:
		_show_cast_message("Aim down toward the river before choosing a casting target.", 2.0)
		return
	var distance_to_water := (LowerMadisonReachScript.WATER_HEIGHT - origin.y) / direction.y
	if distance_to_water <= 0.0 or distance_to_water > 70.0:
		_show_cast_message("Target selection missed the water.", 2.0)
		return
	var target := origin + direction * distance_to_water
	if select_cast_target(origin, target):
		return
	_show_cast_message("Target landed on the bank. Aim closer to current.", 2.2)


func _on_cast_loop_requested(phase: String) -> void:
	if practice_cast_loop(phase):
		return
	_show_cast_message("Select a water target before practicing forward/backcasts.", 2.2)


func _on_cast_commit_requested(style: String) -> void:
	if perform_selected_cast(style):
		return
	_show_cast_message("Select a water target first, then press O for overhead or R for roll cast.", 2.4)


func _on_cast_requested(origin: Vector3, direction: Vector3) -> void:
	_on_cast_target_requested(origin, direction)
	perform_selected_cast("overhead")


func select_cast_target(origin: Vector3, target: Vector3) -> bool:
	_active_drift.clear()
	_pending_take.clear()
	_drift_readout = ""
	_clear_cast_visuals()
	var clamped_target := _clamp_to_world_bounds(target)
	var landing := reach.sample(clamped_target)
	if not bool(landing["is_water"]):
		_selected_cast_target.clear()
		_restore_cast_zoom()
		_cast_state = "READY TO CAST"
		_post_cast_state = "READY TO CAST"
		return false
	clamped_target.y = LowerMadisonReachScript.WATER_HEIGHT
	_selected_cast_target = {
		"origin": origin,
		"target": clamped_target,
		"landing": landing,
	}
	_cast_state = "TARGET SELECTED • WASD AIM • Z/X ZOOM • O/R CAST"
	_post_cast_state = _cast_state
	_cast_state_timer = 0.0
	if _cast_zoom_index == 0:
		_cast_zoom_index = 1
	_apply_cast_zoom()
	_render_cast_target(origin, clamped_target)
	var selected := FLY_OPTIONS[_selected_fly_index] as Dictionary
	_show_cast_message("Target selected for %s. WASD fine-tunes the cast zone; Z/X or wheel changes zoom; O overhead, R roll." % selected["name"], 4.0)
	return true


func practice_cast_loop(phase: String) -> bool:
	if _selected_cast_target.is_empty():
		return false
	var loop_phase := "BACKCAST" if phase.to_lower().begins_with("back") else "FORWARD CAST"
	var rod_style := "back" if loop_phase == "BACKCAST" else "forward"
	angler.play_cast_animation(rod_style)
	_cast_state = "LOOP • %s" % loop_phase
	_post_cast_state = "TARGET SELECTED • WASD AIM • Z/X ZOOM • O/R CAST"
	_cast_state_timer = 0.62
	var target: Vector3 = _selected_cast_target["target"]
	_rebuild_cast_line(_current_rod_tip(), target + Vector3(0.0, DRY_FLY_SURFACE_OFFSET, 0.0))
	_show_cast_message("%s: load the rod, then finish with O overhead or R roll." % loop_phase.capitalize(), 1.8)
	return true


func perform_selected_cast(style: String) -> bool:
	if _selected_cast_target.is_empty():
		return false
	var cast_style := _normalized_cast_style(style)
	var origin := _current_rod_tip()
	var target: Vector3 = _selected_cast_target["target"]
	var landing: Dictionary = reach.sample(target)
	if not bool(landing["is_water"]):
		_selected_cast_target.clear()
		_restore_cast_zoom()
		_clear_cast_visuals()
		_show_cast_message("Selected target is no longer on water. Choose another target.", 2.2)
		return false
	angler.play_cast_animation(cast_style)
	_clear_cast_target_marker()
	_render_cast(origin, target)
	_post_cast_state = "DRIFTING • %s" % cast_style.to_upper()
	_cast_state = "CASTING • %s" % cast_style.to_upper()
	_cast_state_timer = 0.72
	var water_name: String = landing["habitat"]
	var hold_distance := reach.nearest_hold_distance(target)
	var quality := _cast_quality(origin.distance_to(target))
	var selected := FLY_OPTIONS[_selected_fly_index] as Dictionary
	_start_dry_fly_drift(origin, target, landing, selected, cast_style)
	_apply_cast_disturbance(target, _style_cast_quality(quality, cast_style))
	var message := "%s %s cast: %s drifting through %s." % [quality, cast_style, selected["name"], water_name]
	if cast_style == "roll":
		message += " Low loop keeps it under cover."
	elif hold_distance <= 3.2:
		message += " Fish moved under it."
	elif hold_distance <= 9.0:
		message += " Good holding water nearby."
	_show_cast_message(message, 3.5)
	_selected_cast_target.clear()
	_restore_cast_zoom()
	return true


func _normalized_cast_style(style: String) -> String:
	return "roll" if style.to_lower() == "roll" else "overhead"


func _style_cast_quality(quality: String, style: String) -> String:
	if style != "roll":
		return quality
	return "Short" if quality == "Long" else quality


func _update_cast_target_controls(delta: float) -> void:
	if _selected_cast_target.is_empty():
		return
	var input_vector := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input_vector.length_squared() <= 0.0001:
		return
	_nudge_selected_cast_target(input_vector, delta)


func _nudge_selected_cast_target(input_vector: Vector2, delta: float) -> bool:
	if _selected_cast_target.is_empty():
		return false
	var target: Vector3 = _selected_cast_target["target"]
	var right := angler.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	var forward := -angler.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var speed := _cast_control_speed()
	var candidate := target + (right * input_vector.x + forward * -input_vector.y) * speed * delta
	candidate = _clamp_to_world_bounds(candidate)
	candidate.y = LowerMadisonReachScript.WATER_HEIGHT
	var water_target := _water_target_from_candidate(candidate)
	if water_target == Vector3.INF:
		return false
	var landing := reach.sample(water_target)
	_selected_cast_target["target"] = water_target
	_selected_cast_target["landing"] = landing
	_cast_state = "TARGET SELECTED • WASD AIM • Z/X ZOOM • O/R CAST"
	_post_cast_state = _cast_state
	_render_cast_target(_current_rod_tip(), water_target)
	return true


func _water_target_from_candidate(candidate: Vector3) -> Vector3:
	var sample := reach.sample(candidate)
	if bool(sample["is_water"]):
		candidate.y = LowerMadisonReachScript.WATER_HEIGHT
		return candidate
	var fraction := clampf(float(sample["fraction"]), 0.0, 1.0)
	var half_width := float(sample["half_width"])
	var lateral := clampf(float(sample["lateral"]), -half_width * 0.94, half_width * 0.94)
	var projected := reach.position_at(fraction, lateral, LowerMadisonReachScript.WATER_HEIGHT)
	if bool(reach.sample(projected)["is_water"]):
		return projected
	return Vector3.INF


func _cast_control_speed() -> float:
	var zoom_scale := 1.0 - float(_cast_zoom_index) * 0.22
	return CAST_TARGET_NUDGE_SPEED * clampf(zoom_scale, 0.48, 1.0)


func _adjust_cast_zoom(direction: int) -> void:
	if _selected_cast_target.is_empty():
		return
	_cast_zoom_index = clampi(_cast_zoom_index + direction, 0, CAST_ZOOM_FOVS.size() - 1)
	_apply_cast_zoom()
	_show_cast_message("Cast-zone zoom: %s. WASD fine-tunes the target; O overhead or R roll to cast." % _cast_zoom_label(), 1.6)


func _apply_cast_zoom() -> void:
	if angler == null:
		return
	var target_fov := _cast_zoom_fov()
	angler.set_camera_fov(target_fov)


func _restore_cast_zoom() -> void:
	_cast_zoom_index = 0
	if angler == null:
		return
	angler.set_camera_fov(_default_camera_fov)


func _cast_zoom_fov() -> float:
	if _cast_zoom_index <= 0:
		return _default_camera_fov
	return float(CAST_ZOOM_FOVS[_cast_zoom_index])


func _cast_zoom_label() -> String:
	match _cast_zoom_index:
		0:
			return "wide"
		1:
			return "focused"
		_:
			return "tight"


func _render_cast_target(origin: Vector3, target: Vector3) -> void:
	_clear_cast_target_marker()
	_rebuild_cast_line(_current_rod_tip(), target + Vector3(0.0, DRY_FLY_SURFACE_OFFSET, 0.0))
	var ring := TorusMesh.new()
	ring.inner_radius = 0.18
	ring.outer_radius = 0.24
	ring.rings = 6
	ring.ring_segments = 28
	_cast_target_marker = MeshInstance3D.new()
	_cast_target_marker.name = "CastTargetMarker"
	_cast_target_marker.mesh = ring
	_cast_target_marker.material_override = _target_marker_material()
	_cast_target_marker.position = target + Vector3(0.0, DRY_FLY_SURFACE_OFFSET + 0.018, 0.0)
	_cast_target_marker.rotation.x = PI * 0.5
	add_child(_cast_target_marker)


func _target_marker_material() -> Material:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.30, 0.86, 1.0, 0.62)
	material.emission_enabled = true
	material.emission = Color(0.18, 0.62, 1.0, 1.0)
	material.emission_energy_multiplier = 0.45
	return material


func _render_cast(origin: Vector3, target: Vector3) -> void:
	_clear_cast_visuals()
	_rebuild_cast_line(origin, target + Vector3(0.0, DRY_FLY_SURFACE_OFFSET, 0.0))

	var selected := FLY_OPTIONS[_selected_fly_index] as Dictionary
	_cast_marker = AdultInsectScript.new()
	_cast_marker.name = "SelectedAdultDryFly"
	_cast_marker.configure(int(selected["kind"]), 0.10, false)
	_cast_marker.position = target + Vector3(0.0, DRY_FLY_SURFACE_OFFSET, 0.0)
	add_child(_cast_marker)


func _start_dry_fly_drift(origin: Vector3, target: Vector3, landing: Dictionary, selected: Dictionary, cast_style: String = "overhead") -> void:
	var flow: Vector3 = landing["current_vector"]
	_active_drift = {
		"origin": origin,
		"position": target + Vector3(0.0, DRY_FLY_SURFACE_OFFSET, 0.0),
		"age": 0.0,
		"duration": DRY_FLY_DRIFT_DURATION,
		"drag": 0.0,
		"previous_flow": flow,
		"fly_name": String(selected["name"]),
		"cast_style": cast_style,
		"habitat": String(landing["habitat"]),
		"current_strength": float(landing["current_strength"]),
	}
	_update_drift_readout(landing)


func _update_dry_fly_drift(delta: float) -> void:
	if _active_drift.is_empty():
		return
	if not _pending_take.is_empty():
		_update_cast_visuals(_current_rod_tip(), _active_drift["position"])
		_update_pending_take(delta)
		return
	var position: Vector3 = _active_drift["position"]
	var sample := reach.sample(position)
	if not bool(sample["is_water"]):
		_finish_dry_fly_drift("Fly skated onto the bank. Pick up and cast again.")
		return

	var age := float(_active_drift["age"]) + delta
	if age >= float(_active_drift["duration"]):
		_finish_dry_fly_drift("Drift ended. Pick up and cast again.")
		return

	var flow: Vector3 = sample["current_vector"]
	var previous_flow: Vector3 = _active_drift["previous_flow"]
	var drag := minf(float(_active_drift["drag"]) + _drift_drag_delta(previous_flow, flow, delta), DRY_FLY_MAX_DRAG)
	var next_position := position + flow * DRY_FLY_FLOW_SCALE * delta
	next_position = _clamp_to_world_bounds(next_position)
	next_position.y = LowerMadisonReachScript.WATER_HEIGHT + DRY_FLY_SURFACE_OFFSET
	var next_sample := reach.sample(next_position)
	if not bool(next_sample["is_water"]):
		_finish_dry_fly_drift("Fly drifted out of the current and onto dry ground.")
		return

	_active_drift["position"] = next_position
	_active_drift["age"] = age
	_active_drift["drag"] = drag
	_active_drift["previous_flow"] = flow
	_active_drift["habitat"] = String(next_sample["habitat"])
	_active_drift["current_strength"] = float(next_sample["current_strength"])
	_update_drift_readout(next_sample)
	_update_cast_visuals(_current_rod_tip(), next_position)
	_evaluate_fish_take(next_position, next_sample)


func _evaluate_fish_take(fly_position: Vector3, sample: Dictionary) -> void:
	if float(_active_drift.get("age", 0.0)) < FISH_TAKE_MIN_AGE:
		return
	if float(_active_drift.get("drag", 0.0)) >= 0.72:
		return
	for i in range(builder.fish_hold_entries.size()):
		var fish := builder.fish_hold_entries[i] as Dictionary
		if not bool(fish.get("available", true)):
			continue
		if String(fish.get("state", "feeding")) == "spooked":
			continue
		var fish_position: Vector3 = fish["position"]
		var distance := fly_position.distance_to(fish_position)
		var lane_radius := maxf(float(fish.get("feeding_lane_radius", FISH_TAKE_RADIUS)), FISH_TAKE_RADIUS)
		if distance > lane_radius:
			continue
		if not _fish_will_take(fish, sample, distance):
			continue
		fish["available"] = false
		fish["state"] = "hooked"
		builder.fish_hold_entries[i] = fish
		_start_fish_take(fish, fly_position)
		return


func _fish_will_take(fish: Dictionary, sample: Dictionary, distance: float) -> bool:
	var drag_penalty := float(_active_drift.get("drag", 0.0)) * 0.26
	var distance_score := 1.0 - clampf(distance / maxf(float(fish.get("feeding_lane_radius", FISH_TAKE_RADIUS)), 0.1), 0.0, 1.0)
	var current_score := 1.0 - absf(float(sample["current_strength"]) - 0.52)
	var hatch_score := _selected_fly_hatch_score()
	var affinity_score := _fish_fly_affinity_score(fish)
	var alert_penalty := float(fish.get("alert", 0.0)) * 0.36
	var species_bias := 0.08 if int(fish["species"]) == 2 else 0.18
	return distance_score * 0.36 + current_score * 0.18 + hatch_score * 0.24 + affinity_score * 0.20 + species_bias - drag_penalty - alert_penalty >= 0.52


func _selected_fly_hatch_score() -> float:
	var selected := FLY_OPTIONS[_selected_fly_index] as Dictionary
	var selected_species := String(selected["species"]).to_lower()
	for profile in HatchManager.active_profiles:
		var hatch := profile as Dictionary
		if String(hatch.get("stage", "")) != "adult":
			continue
		if String(hatch.get("species", "")).to_lower() == selected_species:
			return clampf(0.42 + float(hatch.get("abundance", 0.5)) * 0.58, 0.0, 1.0)
	return 0.34


func _fish_fly_affinity_score(fish: Dictionary) -> float:
	var selected := FLY_OPTIONS[_selected_fly_index] as Dictionary
	var fly_species := String(selected["species"]).to_lower()
	var fish_species := int(fish.get("species", 0))
	var base := 0.52
	if fish_species == 0:
		base = 0.88 if fly_species == "mayfly" else 0.72
	elif fish_species == 1:
		base = 0.82 if fly_species == "caddis" else 0.74
	else:
		base = 0.50 if fly_species == "mayfly" else 0.58
	var intrusion_delta := 0.18
	if GameManager.difficulty != null:
		intrusion_delta = float(GameManager.difficulty.wrong_species_intrusion_delta)
	if base < 0.62:
		base -= intrusion_delta
	return clampf(base, 0.0, 1.0)


func _start_fish_take(fish: Dictionary, fly_position: Vector3) -> void:
	_pending_take = {
		"age": 0.0,
		"fish_name": String(fish["name"]),
		"window": _hookset_window_duration(),
		"fish": fish.duplicate(true),
	}
	_cast_state = "FISH UP • SET HOOK"
	_post_cast_state = "FISH UP • SET HOOK"
	_drift_readout = "%s ate it — click/Space now! %.1fs window" % [String(fish["name"]), float(_pending_take["window"])]
	_spawn_surface_rise_at(fly_position, 0.82)
	_play_sound_cue("fish_take")
	_show_cast_message("Take! %s rose to the %s." % [String(fish["name"]), String(_active_drift["fly_name"])], 2.0)


func _update_pending_take(delta: float) -> void:
	var age := float(_pending_take.get("age", 0.0)) + delta
	_pending_take["age"] = age
	var window := float(_pending_take.get("window", _hookset_window_duration()))
	var remaining := maxf(window - age, 0.0)
	_drift_readout = "%s on top — set hook %.1fs" % [String(_pending_take.get("fish_name", "Fish")), remaining]
	if age <= window:
		return
	var fish_name := String(_pending_take.get("fish_name", "Fish"))
	_pending_take.clear()
	_active_drift.clear()
	_drift_readout = ""
	_cast_state = "READY TO CAST"
	_post_cast_state = "READY TO CAST"
	_show_cast_message("Missed take. The %s refused after the hookset window." % fish_name, 3.0)


func _hookset_window_duration() -> float:
	if GameManager.difficulty == null:
		return FISH_TAKE_WINDOW_FALLBACK
	return maxf(float(GameManager.difficulty.hookset_window_duration), 0.25)


func _land_hooked_fish(fish: Dictionary, fly_name: String) -> void:
	var fish_name := String(fish.get("name", "fish"))
	var length_m := float(fish.get("length", 0.46))
	var length_cm := length_m * 100.0
	var summary := "%s %.0fcm on %s" % [fish_name, length_cm, fly_name]
	_session_stats["landed"] = int(_session_stats.get("landed", 0)) + 1
	_session_stats["last_catch"] = summary
	var selected := FLY_OPTIONS[_selected_fly_index] as Dictionary
	if GameManager.session_id >= 0:
		DatabaseManager.save_catch(GameManager.session_id, {
			"species": fish_name,
			"size_cm": length_cm,
			"fly_name": fly_name,
			"fly_stage": String(selected.get("phase", "Adult")),
			"hatch_state": HatchManager.hatch_state_name(),
			"time_of_day": "%.1f" % TimeOfDay.current_hour,
			"section_index": 0,
			"position_x": float(fish.get("fraction", 0.0)),
			"fish_variant_seed": int(GameManager.session_seed + int(float(fish.get("fraction", 0.0)) * 1000.0)),
		})
	_play_sound_cue("fish_landed")
	_show_cast_message("Landed %s. Photo logged; release complete." % summary, 4.5)


func _drift_drag_delta(previous_flow: Vector3, current_flow: Vector3, delta: float) -> float:
	if previous_flow.length_squared() <= 0.0001 or current_flow.length_squared() <= 0.0001:
		return 0.015 * delta
	var speed_change := absf(previous_flow.length() - current_flow.length()) * 0.18
	var angle_change := previous_flow.normalized().angle_to(current_flow.normalized()) * 0.22
	return (speed_change + angle_change) * delta


func _update_drift_readout(sample: Dictionary) -> void:
	var drag := float(_active_drift.get("drag", 0.0))
	var drag_word := "clean"
	if drag > 0.62:
		drag_word = "dragging"
	elif drag > 0.30:
		drag_word = "slight drag"
	_drift_readout = "Drift %.1fs · %s · %s · current %.2f" % [
		float(_active_drift.get("age", 0.0)),
		drag_word,
		String(sample["habitat"]),
		float(sample["current_strength"]),
	]


func _finish_dry_fly_drift(message: String) -> void:
	_active_drift.clear()
	_drift_readout = ""
	_cast_state = "READY TO CAST"
	_post_cast_state = "READY TO CAST"
	_cast_state_timer = 0.0
	_show_cast_message(message, 2.5)


func _update_fish_ai(delta: float) -> void:
	if builder == null or builder.fish_hold_entries.is_empty():
		return
	var player_pos := angler.global_position
	var player_wading := is_wading(player_pos)
	for i in range(builder.fish_hold_entries.size()):
		var fish := builder.fish_hold_entries[i] as Dictionary
		if not bool(fish.get("available", true)):
			builder.fish_hold_entries[i] = fish
			continue
		var fish_pos: Vector3 = fish["position"]
		var distance := fish_pos.distance_to(player_pos)
		var spook_radius := _fish_spook_radius(fish)
		var alert := float(fish.get("alert", 0.0))
		if player_wading:
			var vibration_radius := spook_radius
			if GameManager.difficulty != null:
				vibration_radius = maxf(vibration_radius, float(GameManager.difficulty.wading_vibration_radius))
			if distance < vibration_radius:
				alert = maxf(alert, 1.0 - distance / maxf(vibration_radius, 0.1))
		if distance < spook_radius * 0.55:
			alert = 1.0
		var state := String(fish.get("state", "feeding"))
		if alert >= 0.88:
			state = "spooked"
		elif alert >= FISH_FEEDING_ALERT_LIMIT:
			state = "alert"
		elif _selected_fly_hatch_score() >= 0.44:
			state = "feeding"
		else:
			state = "holding"
		var recovery := FISH_SPOOK_RECOVERY_RATE if state == "spooked" else FISH_ALERT_RECOVERY_RATE
		alert = maxf(alert - recovery * delta, 0.0)
		fish["alert"] = alert
		fish["state"] = state
		builder.fish_hold_entries[i] = fish


func _fish_spook_radius(fish: Dictionary) -> float:
	var radius := float(fish.get("spook_radius", 5.8))
	if GameManager.difficulty != null:
		radius = maxf(radius, float(GameManager.difficulty.base_spook_radius))
		radius *= lerpf(1.0, float(GameManager.difficulty.large_fish_radius_multiplier), clampf(float(fish.get("length", 0.48)) - 0.42, 0.0, 0.35) / 0.35)
	return radius


func _apply_cast_disturbance(target: Vector3, quality: String) -> void:
	var splash_radius := 2.2 if quality == "Clean" else 4.8
	if GameManager.difficulty != null:
		splash_radius *= lerpf(0.85, 1.25, float(GameManager.difficulty.bad_cast_spook_chance))
	var spooked_count := 0
	for i in range(builder.fish_hold_entries.size()):
		var fish := builder.fish_hold_entries[i] as Dictionary
		if not bool(fish.get("available", true)):
			continue
		var distance := (fish["position"] as Vector3).distance_to(target)
		if distance > splash_radius:
			continue
		fish["alert"] = maxf(float(fish.get("alert", 0.0)), 1.0 - distance / maxf(splash_radius, 0.1))
		if float(fish["alert"]) >= 0.82:
			fish["state"] = "spooked"
			spooked_count += 1
		builder.fish_hold_entries[i] = fish
	if spooked_count > 0:
		_session_stats["spooked"] = int(_session_stats.get("spooked", 0)) + spooked_count
		_play_sound_cue("cast_splash")


func _update_cast_visuals(origin: Vector3, target: Vector3) -> void:
	if _cast_marker != null and is_instance_valid(_cast_marker):
		_cast_marker.global_position = target
	_rebuild_cast_line(origin, target)


func _refresh_cast_line_attachment() -> void:
	if _cast_line == null and _leader_line == null:
		return
	if _cast_marker != null and is_instance_valid(_cast_marker):
		_update_cast_visuals(_current_rod_tip(), _cast_marker.global_position)
		return
	if not _selected_cast_target.is_empty():
		var target: Vector3 = _selected_cast_target["target"]
		_rebuild_cast_line(_current_rod_tip(), target + Vector3(0.0, DRY_FLY_SURFACE_OFFSET, 0.0))


func _rebuild_cast_line(origin: Vector3, target: Vector3) -> void:
	if not _should_rebuild_cast_line(origin, target):
		return

	var fly_position := target
	var leader_start_t := _leader_start_fraction_for_line(origin, fly_position)
	var line_mesh := _build_line_strip_mesh(origin, fly_position, 0.0, leader_start_t, leader_start_t, MAT_FLY_LINE)
	var leader_mesh := _build_line_strip_mesh(origin, fly_position, leader_start_t, 1.0, leader_start_t, MAT_LEADER)

	if _cast_line == null or not is_instance_valid(_cast_line):
		_cast_line = MeshInstance3D.new()
		_cast_line.name = "CastLine"
		add_child(_cast_line)
	_cast_line.mesh = line_mesh

	if _leader_line == null or not is_instance_valid(_leader_line):
		_leader_line = MeshInstance3D.new()
		_leader_line.name = "CastLeader"
		add_child(_leader_line)
	_leader_line.mesh = leader_mesh
	_last_cast_line_origin = origin
	_last_cast_line_target = target
	_last_cast_line_state = _cast_state
	_last_cast_line_fly_index = _selected_fly_index
	_cast_line_cache_valid = true


func _should_rebuild_cast_line(origin: Vector3, target: Vector3) -> bool:
	if not _cast_line_cache_valid:
		return true
	if _cast_line == null or not is_instance_valid(_cast_line):
		return true
	if _leader_line == null or not is_instance_valid(_leader_line):
		return true
	if _last_cast_line_state != _cast_state:
		return true
	if _last_cast_line_fly_index != _selected_fly_index:
		return true
	if _last_cast_line_origin.distance_squared_to(origin) >= CAST_LINE_REBUILD_DISTANCE_SQUARED:
		return true
	if _last_cast_line_target.distance_squared_to(target) >= CAST_LINE_REBUILD_DISTANCE_SQUARED:
		return true
	return false


func _invalidate_cast_line_cache() -> void:
	_cast_line_cache_valid = false
	_last_cast_line_state = ""
	_last_cast_line_fly_index = -1


func _current_rod_tip() -> Vector3:
	if angler != null and angler.rod != null:
		return angler.rod.tip_global_position()
	return _active_drift.get("origin", Vector3.ZERO)


func _leader_start_for_line(origin: Vector3, fly_position: Vector3) -> Vector3:
	var leader_start_t := _leader_start_fraction_for_line(origin, fly_position)
	return _cast_curve_point(origin, fly_position, leader_start_t, leader_start_t)


func _leader_start_fraction_for_line(origin: Vector3, fly_position: Vector3) -> float:
	var distance := origin.distance_to(fly_position)
	if distance <= 0.001:
		return 1.0
	var leader_length := minf(LEADER_LENGTH, distance * 0.42)
	return clampf(1.0 - (leader_length / distance), 0.0, 1.0)


func _build_line_strip_mesh(origin: Vector3, fly_position: Vector3, start_t: float, end_t: float, leader_start_t: float, material: Material) -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, material)
	for i in range(CAST_LINE_SEGMENTS + 1):
		var local_t := float(i) / float(CAST_LINE_SEGMENTS)
		var t := lerpf(start_t, end_t, local_t)
		mesh.surface_add_vertex(_cast_curve_point(origin, fly_position, t, leader_start_t))
	mesh.surface_end()
	return mesh


func _cast_curve_point(origin: Vector3, fly_position: Vector3, t: float, leader_start_t: float) -> Vector3:
	var point := origin.lerp(fly_position, t)
	var blend_start := maxf(0.0, leader_start_t - CAST_LEADER_TRANSITION_BLEND)
	var blend_end := minf(1.0, leader_start_t + CAST_LEADER_TRANSITION_BLEND)
	var leader_weight := smoothstep(blend_start, blend_end, t)
	var sag_scale := lerpf(1.0, 0.28, leader_weight)
	point.y -= sin(t * PI) * CAST_LINE_SAG * sag_scale
	var sample := reach.sample(fly_position)
	if bool(sample.get("is_water", false)):
		var flow: Vector3 = sample.get("current_vector", Vector3.ZERO)
		if flow.length_squared() > 0.0001:
			var bow_scale := lerpf(1.0, 0.65, leader_weight)
			var bow := sin(t * PI) * float(sample.get("current_strength", 0.0)) * CAST_LINE_CURRENT_BOW * bow_scale
			point += flow.normalized() * bow
	return point


func _clear_cast_visuals() -> void:
	if _cast_line != null and is_instance_valid(_cast_line):
		_cast_line.queue_free()
	if _leader_line != null and is_instance_valid(_leader_line):
		_leader_line.queue_free()
	if _cast_marker != null and is_instance_valid(_cast_marker):
		_cast_marker.queue_free()
	_clear_cast_target_marker()
	_cast_line = null
	_leader_line = null
	_cast_marker = null
	_invalidate_cast_line_cache()


func _clear_cast_target_marker() -> void:
	if _cast_target_marker != null and is_instance_valid(_cast_target_marker):
		if _cast_target_marker.get_parent() != null:
			_cast_target_marker.get_parent().remove_child(_cast_target_marker)
		_cast_target_marker.queue_free()
	_cast_target_marker = null


func _cast_quality(distance: float) -> String:
	if distance < 8.0:
		return "Short"
	if distance <= 34.0:
		return "Clean"
	return "Long"


func _on_fly_change_requested() -> void:
	_selected_fly_index = (_selected_fly_index + 1) % FLY_OPTIONS.size()
	_selected_cast_target.clear()
	_active_drift.clear()
	_pending_take.clear()
	_drift_readout = ""
	_clear_cast_visuals()
	_restore_cast_zoom()
	_cast_state = "READY TO CAST"
	_post_cast_state = "READY TO CAST"
	_cast_state_timer = 0.0
	var selected := FLY_OPTIONS[_selected_fly_index] as Dictionary
	_show_cast_message("Tied on %s — %s %s imitation." % [
		selected["name"], selected["species"], selected["phase"]
	], 2.8)


func _update_hud() -> void:
	var sample := reach.sample(angler.global_position)
	var tile_name: String = sample["habitat"]
	var speed_word := _movement_word(sample)
	var current: float = sample["current_strength"]
	var depth: float = sample["depth"]
	var depth_band: String = sample["depth_band"]
	var control_hint := "WASD move · mouse look · click/Space target · B backcast · F forward · O overhead · R roll · Q fly · 0-5 debug · Esc mouse"
	if not _selected_cast_target.is_empty():
		control_hint = "CAST MODE: player locked · WASD adjust cast zone · Z/X or wheel zoom (%s) · B/F loop · O/R cast" % _cast_zoom_label()
	status_label.text = "Lower Madison · Black's Ford Bend · %s · %s · depth %.2fm %s · current %.2f · %.1f hr
%s" % [
		tile_name,
		speed_word,
		depth,
		depth_band,
		current,
		TimeOfDay.current_hour,
		control_hint,
	]
	cast_label.text = _cast_message
	var selected := FLY_OPTIONS[_selected_fly_index] as Dictionary
	fly_label.text = "%s\n%s · %s dry" % [selected["name"], selected["species"], selected["phase"]]
	cast_state_label.text = _cast_state if _drift_readout.is_empty() else "%s\n%s" % [_cast_state, _drift_readout]
	hatch_label.text = _surface_life_label()
	_update_casting_loop_hud()
	_update_debug_label(sample)


func _update_casting_loop_hud() -> void:
	if _casting_loop_label == null:
		return
	var mode := "AIM"
	var diagram := "  o\n /|\\__ rod\n / \\    ~~~ line"
	var bind_line := "Space/LMB set target"
	if not _selected_cast_target.is_empty():
		mode = "TARGET LOCKED · ZOOM %s" % _cast_zoom_label().to_upper()
		diagram = "  o   ↶ backcast\n /|\\====> forward loop\n / \\      • target"
		bind_line = "WASD cast-zone aim · Z/X zoom · B/F loop · O overhead · R/RMB roll"
	elif not _active_drift.is_empty():
		mode = "DRIFTING"
		var style := String(_active_drift.get("cast_style", "overhead")).to_upper()
		diagram = "  o--rod~~~~ leader•\n /|\\       %s" % style
		bind_line = "Click/Space hookset or retarget after drift"
	_casting_loop_label.text = "CASTING LOOP · %s\n%s\n%s" % [mode, diagram, bind_line]


func _movement_word(sample: Dictionary) -> String:
	if not bool(sample["is_water"]):
		return "walking"
	if bool(sample["is_wadable"]):
		return "wading"
	return "non-wadable"


func _update_debug_label(sample: Dictionary) -> void:
	if _debug_label == null:
		return
	if _debug_view <= 0:
		return
	var flow: Vector3 = sample["surface_flow_direction"]
	_debug_label.text = "Debug %d: %s
habitat %s
depth %.2fm %s · wadable %s
current %.2f · flow %.2f %.2f
turb %.2f · foam %.2f · curve %.2f
station %.3f · lateral %.1f / %.1f" % [
		_debug_view,
		DEBUG_VIEW_NAMES[_debug_view],
		String(sample["habitat"]),
		float(sample["depth"]),
		String(sample["depth_band"]),
		"yes" if bool(sample["is_wadable"]) else "no",
		float(sample["current_strength"]),
		flow.x,
		flow.z,
		float(sample["visual_turbulence"]),
		float(sample["foam_tendency"]),
		float(sample["curvature"]),
		float(sample["fraction"]),
		float(sample["lateral"]),
		float(sample["half_width"]),
	]


func _surface_life_label() -> String:
	var active_adults: Array[String] = []
	var abundance_lines: Array[String] = []
	for profile in HatchManager.active_profiles:
		var hatch := profile as Dictionary
		var label := "%s %s" % [String(hatch["species"]).capitalize(), String(hatch["stage"])]
		if hatch["stage"] == "adult":
			active_adults.append(label)
		if GameManager.difficulty == null or bool(GameManager.difficulty.show_sample_abundance_bars):
			abundance_lines.append("%s %s" % [_abundance_bar(float(hatch.get("abundance", 0.0))), label])
	var pattern_hint := "Q cycle pattern · N net sample"
	if not _last_net_sample.is_empty():
		pattern_hint = "%s\n%s" % [String(_last_net_sample.get("summary", "")), pattern_hint]
	elif not abundance_lines.is_empty():
		pattern_hint = "%s\n%s" % ["; ".join(abundance_lines), pattern_hint]
	if active_adults.is_empty():
		return "Surface life: sparse adult mayflies / caddis\n%s" % pattern_hint
	return "Active: %s\n%s" % [", ".join(active_adults), pattern_hint]


func _abundance_bar(value: float) -> String:
	var filled := clampi(roundi(clampf(value, 0.0, 1.0) * 5.0), 0, 5)
	return "[%s%s]" % ["|".repeat(filled), ".".repeat(5 - filled)]


func _show_cast_message(message: String, seconds: float) -> void:
	_cast_message = message
	_cast_message_timer = seconds


func _play_sound_cue(cue_name: String) -> void:
	_last_sound_cue = cue_name
	if OS.is_debug_build():
		print("RiverWorld3D sound cue: %s" % cue_name)


func _sky_color() -> Color:
	var hour := TimeOfDay.current_hour
	if hour < 7.0:
		return Color(0.58, 0.70, 0.84)
	if hour > 19.0:
		return Color(0.30, 0.38, 0.50)
	return Color(0.48, 0.66, 0.86)


func _sun_color() -> Color:
	var hour := TimeOfDay.current_hour
	if hour < 7.0 or hour > 18.0:
		return Color(1.0, 0.86, 0.68)
	return Color(1.0, 0.96, 0.86)
