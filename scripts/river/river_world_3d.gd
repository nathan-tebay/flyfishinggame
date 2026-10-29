class_name RiverWorld3D
extends Node3D

const DifficultyConfig = preload("res://resources/difficulty_config.gd")
const CastingMinigamePanelScript = preload("res://scripts/ui/casting_minigame_panel.gd")
const PauseMenuScript = preload("res://scripts/ui/pause_menu.gd")
const LowerMadisonReachScript = preload("res://scripts/river/lower_madison_reach.gd")
const River3DBuilderScript = preload("res://scripts/river/river_3d_builder.gd")
const FirstPersonAnglerScript = preload("res://scripts/player/first_person_angler.gd")
const LoopPhysicsEngine = preload("res://scripts/casting/loop_physics_engine.gd")
const CastingLineRenderer = preload("res://scripts/casting/casting_line_renderer.gd")
const CastingStateManager = preload("res://scripts/casting/casting_state_manager.gd")
const CAST_TARGET_TEXTURE_PATH := "res://assets/3d/textures/cast_target_trout.png"
const AdultInsectScript = preload("res://scripts/models/adult_insect_3d.gd")
const MAT_FLY_LINE = preload("res://assets/3d/materials/fly_line.tres")
const MAT_LEADER = preload("res://assets/3d/materials/leader.tres")
const MAT_MEADOW = preload("res://assets/3d/materials/meadow_grass.tres")
const MAT_MOUNTAIN = preload("res://assets/3d/materials/distant_mountain.tres")
const MAT_WATER = preload("res://assets/3d/materials/river_water.tres")
const FLY_OPTIONS := [
	{"name": "Blue-Winged Olive Dun", "species": "Mayfly", "phase": "Adult", "kind": 0, "surface": true, "depth_layer": "surface"},
	{"name": "Elk Hair Caddis", "species": "Caddis", "phase": "Adult", "kind": 1, "surface": true, "depth_layer": "surface"},
	{"name": "Hare's Ear Nymph", "species": "Mayfly", "phase": "Nymph", "kind": 0, "surface": false, "depth_layer": "bottom"},
	{"name": "Soft Hackle Emerger", "species": "Mayfly", "phase": "Emerger", "kind": 0, "surface": false, "depth_layer": "mid"},
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
const CAST_LINE_SEGMENTS := 18
const CAST_LINE_RIBBON_HALF_WIDTH := 0.018
const LEADER_RIBBON_HALF_WIDTH := 0.006
const AERIAL_LINE_SEGMENTS := 24
const AERIAL_LOOP_HEIGHT := 2.4
const AERIAL_LOOP_DEPTH := 1.8
const AERIAL_LOOP_LAG := 0.22
const CAST_LINE_CURRENT_BOW := 0.34
const CAST_LINE_SAG := 0.55
const CAST_LEADER_TRANSITION_BLEND := 0.12
const CAST_LINE_REBUILD_DISTANCE_SQUARED := 0.0025
const CAST_LINE_LENGTH_MIN := 3.0
const CAST_LINE_LENGTH_MAX := 38.0
const CAST_LINE_LENGTH_STEP := 1.5
const DEFAULT_LINE_LENGTH   := 3.0
# Form drag: loop quality scales delivery distance (wide loops fall short)
const LOOP_DRAG_FACTOR := {
	"tight": 1.0,
	"adequate": 0.94,
	"wide": 0.76,
	"tailing": 0.60,
	"none": 0.85,
}
# Line tension vs slack: line the load can cleanly turn over
const CARRY_LIMIT_MIN := 6.0
const CARRY_LIMIT_MAX := 32.0
# Loop turnover visual duration
const TURNOVER_DURATION := 0.45
const FISH_TAKE_RADIUS := 2.45
const FISH_TAKE_MIN_AGE := 0.35
const FISH_TAKE_WINDOW_FALLBACK := 1.15
const FISH_ALERT_RECOVERY_RATE := 0.18
const FISH_SPOOK_RECOVERY_RATE := 0.07
const FISH_FEEDING_ALERT_LIMIT := 0.38
const NET_SAMPLE_COOLDOWN := 2.0
const CAST_STANCE_MOVE_SCALE := 0.28
const OVERHEAD_LIFT_THRESHOLD           := 4.0
const OVERHEAD_LIFT_START_ELEV          := 0.28
@export var backcast_load_elev          := 1.12   # how high the rod must rise to load a backcast
const OVERHEAD_BACKCAST_RELEASE_ELEV    := 0.58
@export var forward_commit_elev         := 0.10   # how low the rod must drop to finish a forward stroke
const OVERHEAD_ARC_MAX_ELEV             := 1.42
const FORWARD_ARC_MAX_ELEV              := 1.05
# False-cast rhythm: the line unrolls over a half-period that scales with how much
# line is out (longer line = slower rhythm). The player reverses each stroke when
# the loop is straight (~progress 1.0). Delivery only fires once the line is loaded.
@export var delivery_load_min           := 0.90
@export var delivery_timing_min         := 0.70   # the delivery stroke must let the loop straighten first
@export var tight_load_gain             := 0.30   # line load added per well-timed (tight) stroke
@export var unroll_time_min             := 0.45   # seconds, short line
@export var unroll_time_max             := 1.30   # seconds, full line out
const AMBIENT_UPDATE_INTERVAL := 0.10
const FISH_AI_UPDATE_INTERVAL := 0.12
const FISH_VISUAL_UPDATE_INTERVAL := 0.06
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

var _minigame_panel: Control = null
var _pause_menu: PauseMenu = null

var reach: LowerMadisonReachScript = null
var _cast_line: MeshInstance3D = null
var _leader_line: MeshInstance3D = null
var _cast_marker: Node3D = null
var _last_cast_line_origin := Vector3.ZERO
var _last_cast_line_target := Vector3.ZERO
var _last_cast_line_state := ""
var _last_cast_line_fly_index := -1
var _cast_line_cache_valid := false
var _fly_line_mat: Material = null
var _leader_mat: Material = null
var _aerial_line_node: MeshInstance3D = null
var _aerial_pts: PackedVector3Array = PackedVector3Array()  # temporally smoothed loop
var _aerial_phase: String = ""
var _casting_state_mgr: CastingStateManager = null
var _line_renderer: CastingLineRenderer = null
var _cast_target_marker: MeshInstance3D = null
var _cast_target_marker_mesh: QuadMesh = null
var _cast_target_marker_material: StandardMaterial3D = null
var _cast_target_texture: Texture2D = null
var _selected_cast_target: Dictionary = {}
# Last delivered target, kept so raising the rod can pick up the line and recast
# in place (no need to re-click water between casts).
var _last_cast_target: Dictionary = {}
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
var _fish_visual_update_accumulator := 0.0
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
var ambient_effect_density := 1.0
var _drag_refusal_fired: bool = false
var _gesture_state: String = "idle"  # presentation mirror of CastingStateManager phase
# Loop turnover visual
var _loop_apex_height_cached: float = 0.8
var _turnover_timer: float = 0.0
var _turnover_origin: Vector3 = Vector3.ZERO
var _turnover_landing: Vector3 = Vector3.ZERO
var _turnover_apex_h: float = 0.4
var _fighting: bool = false
var _fight_timer: float = 0.0
var _fight_duration: float = 0.0
var _fight_tension: float = 0.5
var _fighting_fish: Dictionary = {}
var _fighting_fly_name: String = ""
@export var audio_cue_streams: Dictionary = {}
var _audio_player: AudioStreamPlayer = null


func _ready() -> void:
	process_priority = 20
	_audio_player = AudioStreamPlayer.new()
	_audio_player.name = "AudioCuePlayer"
	add_child(_audio_player)
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
	angler.line_feed_requested.connect(_on_line_feed_requested)
	angler.line_retrieve_requested.connect(_on_line_retrieve_requested)
	angler.hookset_requested.connect(_on_hookset_requested)
	angler.fly_change_requested.connect(_on_fly_change_requested)
	_show_cast_message("Walk to river · click water to choose target · LMB/RMB strips line · MMB hookset · Tab exits cast", 5.0)
	_init_fly_line_materials()
	_init_loop_physics()
	_update_hud()


func _process(delta: float) -> void:
	_update_time_critical_state(delta)
	_update_scheduled_systems(delta)
	_refresh_cast_line_attachment()


func _update_time_critical_state(delta: float) -> void:
	_update_dry_fly_drift(delta)
	_update_fish_fight(delta)
	_drive_casting_loop(delta)
	_update_aerial_cast_line(delta)
	_update_turnover(delta)
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

	_fish_visual_update_accumulator += delta
	if _fish_visual_update_accumulator >= FISH_VISUAL_UPDATE_INTERVAL:
		_fish_visual_update_accumulator = 0.0
		_update_visible_fish_animation()

	_hud_update_accumulator += delta
	if _hud_update_accumulator >= HUD_UPDATE_INTERVAL:
		_update_hud()
		_hud_update_accumulator = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if not _selected_cast_target.is_empty() and mouse_button.pressed:
			if mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP:
				_adjust_cast_line_length(1)
				get_viewport().set_input_as_handled()
				return
			elif mouse_button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_adjust_cast_line_length(-1)
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
		if event.is_action_pressed("cast_line_longer"):
			_adjust_cast_line_length(1)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("cast_line_shorter"):
			_adjust_cast_line_length(-1)
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
	return not _selected_cast_target.is_empty() or _fighting


func casting_movement_scale() -> float:
	if _fighting:
		return 0.0
	if not _selected_cast_target.is_empty():
		return CAST_STANCE_MOVE_SCALE
	return 1.0


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
		_start_fish_fight(fish, fly_name)
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
	if builder == null or builder.fish_hold_entries.is_empty():
		return
	var tick := int(Time.get_ticks_msec() / 733) + GameManager.session_seed
	var fish := _surface_rise_fish_for_tick(tick)
	if fish.is_empty():
		return
	var depth := float(fish.get("depth", 0.0))
	if depth < 0.22:
		return
	var offset := Vector3(sin(float(tick) * 0.87) * 0.38, 0.0, cos(float(tick) * 0.61) * 0.28)
	var center := fish.get("surface_position", reach.position_at(float(fish["fraction"]), float(fish["lateral"]), LowerMadisonReachScript.WATER_HEIGHT + 0.027)) as Vector3
	center += offset
	var rise_weight := float(fish.get("surface_rise_weight", 0.5))
	_spawn_surface_rise_at(center, 0.46 + clampf(depth, 0.0, 0.85) * 0.52 + rise_weight * 0.22)


func _surface_rise_fish_for_tick(tick: int) -> Dictionary:
	var fish_count := builder.fish_hold_entries.size()
	for attempt in range(fish_count):
		var fish := builder.fish_hold_entries[posmod(tick + attempt * 3, fish_count)] as Dictionary
		if not bool(fish.get("available", true)):
			continue
		if String(fish.get("state", "feeding")) == "spooked":
			continue
		var rise_weight := float(fish.get("surface_rise_weight", 0.5))
		var roll := float(posmod(tick + attempt * 29 + int(float(fish.get("length", 0.4)) * 100.0), 100)) / 100.0
		if roll <= rise_weight:
			return fish
	var fallback := builder.fish_hold_entries[posmod(tick, fish_count)] as Dictionary
	if bool(fallback.get("available", true)) and String(fallback.get("state", "feeding")) not in ["spooked", "hooked", "landed"]:
		return fallback
	return {}


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
	_minigame_panel = CastingMinigamePanelScript.new()
	_minigame_panel.name = "CastingMinigamePanel"
	_minigame_panel.anchor_left = 0.0
	_minigame_panel.anchor_right = 1.0
	_minigame_panel.anchor_top = 0.75
	_minigame_panel.anchor_bottom = 1.0
	_minigame_panel.offset_left = 0.0
	_minigame_panel.offset_right = 0.0
	_minigame_panel.offset_top = 0.0
	_minigame_panel.offset_bottom = 0.0
	_minigame_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_minigame_panel.visible = false
	$HUD.add_child(_minigame_panel)

	# ESC pause / config menu (built with live references to world + angler).
	_pause_menu = PauseMenuScript.new()
	_pause_menu.name = "PauseMenu"
	_pause_menu.world = self
	_pause_menu.angler = angler
	$HUD.add_child(_pause_menu)


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


func _on_line_feed_requested(amount: float) -> void:
	if _selected_cast_target.is_empty():
		return
	var current := float(_selected_cast_target.get("line_length", DEFAULT_LINE_LENGTH))
	_selected_cast_target["line_length"] = clampf(current + amount, CAST_LINE_LENGTH_MIN, CAST_LINE_LENGTH_MAX)
	var new_len := float(_selected_cast_target["line_length"])
	var target: Vector3 = _selected_cast_target["target"]
	_rebuild_cast_line(_current_rod_tip(), target + Vector3(0.0, DRY_FLY_SURFACE_OFFSET, 0.0))
	_cast_state = "TARGET SET · line %.0fm · lower rod to deliver" % new_len
	_post_cast_state = _cast_state


func _on_line_retrieve_requested(amount: float) -> void:
	if _selected_cast_target.is_empty():
		return
	var current := float(_selected_cast_target.get("line_length", DEFAULT_LINE_LENGTH))
	_selected_cast_target["line_length"] = clampf(current - amount, CAST_LINE_LENGTH_MIN, CAST_LINE_LENGTH_MAX)
	var new_len := float(_selected_cast_target["line_length"])
	var target: Vector3 = _selected_cast_target["target"]
	_rebuild_cast_line(_current_rod_tip(), target + Vector3(0.0, DRY_FLY_SURFACE_OFFSET, 0.0))
	_cast_state = "TARGET SET · line %.0fm · lower rod to deliver" % new_len
	_post_cast_state = _cast_state


func _on_hookset_requested() -> void:
	if not _pending_take.is_empty():
		try_hookset()
		return
	if _fighting:
		_show_cast_message("Fighting fish — keep tension!", 1.5)
		return
	if _fly_is_on_water():
		_active_drift.clear()
		_pending_take.clear()
		_drift_readout = ""
		_clear_cast_visuals()
		_cast_state = "FLY LIFTED — click water for new target"
		_post_cast_state = _cast_state
		_show_cast_message("Fly lifted. Click water to select a new target.", 2.0)
		return


func _on_drag_refusal(fly_position: Vector3) -> void:
	_drag_refusal_fired = true
	for i in range(builder.fish_hold_entries.size()):
		var fish := builder.fish_hold_entries[i] as Dictionary
		if not bool(fish.get("available", true)):
			continue
		if String(fish.get("state", "feeding")) == "spooked":
			continue
		if (fish["position"] as Vector3).distance_squared_to(fly_position) > FISH_TAKE_RADIUS * FISH_TAKE_RADIUS * 4.0:
			continue
		fish["alert"] = maxf(float(fish.get("alert", 0.0)), 0.72)
		fish["state"] = "alert"
		builder.fish_hold_entries[i] = fish
	_cast_state = "DRAG — FISH ALERTED"
	_post_cast_state = "READY TO CAST"
	_cast_state_timer = 2.0
	_finish_dry_fly_drift("Fly dragged. Fish alerted — give the run a minute before casting again.")


func _start_fish_fight(fish: Dictionary, fly_name: String) -> void:
	_fighting = true
	_fight_timer = 0.0
	_fight_tension = 0.5
	_fighting_fish = fish
	_fighting_fly_name = fly_name
	var species := int(fish.get("species", 0))
	match species:
		0: _fight_duration = 4.0
		1: _fight_duration = 5.0
		_: _fight_duration = 2.5
	_cast_state = "FIGHTING — HOLD ON"
	_post_cast_state = "FIGHTING — HOLD ON"


func _update_fish_fight(delta: float) -> void:
	if not _fighting:
		return
	_fight_timer += delta
	_fight_tension = 0.5 + 0.45 * sin(_fight_timer * 3.5)
	_cast_state = "FIGHTING — TENSION: %d%%" % int(_fight_tension * 100.0)
	if _fight_tension <= 0.05:
		_fighting = false
		_cast_state = "FISH OFF — SLACK LINE"
		_post_cast_state = "READY TO CAST"
		_cast_state_timer = 2.5
		_show_cast_message("Fish threw the hook on slack line.", 3.0)
		return
	if _fight_timer >= _fight_duration:
		_fighting = false
		_land_hooked_fish(_fighting_fish, _fighting_fly_name)


func _tween_visible_fish_to(fish: Dictionary, fly_position: Vector3) -> void:
	var hold_pos: Vector3 = fish.get("position", Vector3.ZERO)
	var best_node: Node3D = null
	var best_dist_sq := INF
	for node in get_tree().get_nodes_in_group("visible_fish"):
		if not node is Node3D:
			continue
		var dist_sq := (node as Node3D).global_position.distance_squared_to(hold_pos)
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best_node = node as Node3D
	if best_node == null or best_dist_sq > 4.0:
		return
	var tween := create_tween()
	tween.tween_property(best_node, "position", fly_position, 0.3)


func select_cast_target(origin: Vector3, target: Vector3) -> bool:
	_active_drift.clear()
	_pending_take.clear()
	_drift_readout = ""
	_clear_cast_visuals()
	var clamped_target := _clamp_to_world_bounds(target)
	var landing := reach.sample(clamped_target)
	if not bool(landing["is_water"]):
		_selected_cast_target.clear()
		_restore_cast_fov()
		_cast_state = "READY TO CAST"
		_post_cast_state = "READY TO CAST"
		return false
	clamped_target.y = LowerMadisonReachScript.WATER_HEIGHT
	_selected_cast_target = {
		"origin": origin,
		"target": clamped_target,
		"landing": landing,
		"line_length": DEFAULT_LINE_LENGTH,
	}
	_cast_state = "TARGET SET · LMB strip line · RMB retrieve · raise rod · lower to deliver"
	_post_cast_state = _cast_state
	_cast_state_timer = 0.0
	_render_cast_target(origin, clamped_target)
	_enter_casting_zoom(clamped_target)
	var selected := FLY_OPTIONS[_selected_fly_index] as Dictionary
	var target_dist := origin.distance_to(clamped_target)
	_show_cast_message("Target %.0fm — strip out %.0fm more line with LMB, then raise rod to cast." % [target_dist, maxf(target_dist - DEFAULT_LINE_LENGTH, 0.0)], 4.2)
	return true


func perform_selected_cast(style: String) -> bool:
	if _selected_cast_target.is_empty():
		return false
	var cast_style := _normalized_cast_style(style)
	# Load/quality are owned by the casting seam; slack is derived here from them.
	var line_load: float = _casting_state_mgr.get_line_load() if _casting_state_mgr != null else 0.0
	var loop_quality: String = _casting_state_mgr.get_loop_quality() if _casting_state_mgr != null else "none"
	var pending_slack := 0.0
	var origin := _current_rod_tip()
	var target: Vector3 = _selected_cast_target["target"]
	var landing: Dictionary = reach.sample(target)
	if not bool(landing["is_water"]):
		_selected_cast_target.clear()
		_exit_casting_zoom()
		_restore_cast_fov()
		_clear_cast_visuals()
		_show_cast_message("Selected target is no longer on water. Choose another target.", 2.2)
		return false
	# Landing point = rod direction × technique distance
	var intended_dist := float(_selected_cast_target.get("line_length", origin.distance_to(target)))
	# Line tension vs slack: line beyond the load's carry limit piles up short.
	var carry_limit: float = lerpf(CARRY_LIMIT_MIN, CARRY_LIMIT_MAX, clampf(line_load, 0.0, 1.0))
	pending_slack = maxf(intended_dist - carry_limit, 0.0)
	if pending_slack > 0.0:
		intended_dist = carry_limit + pending_slack * 0.35
	var cast_dir := _current_cast_direction()
	var actual_dist: float
	if line_load > 0.0 and line_load < 0.5:
		actual_dist = intended_dist * (line_load / 0.5)
	elif line_load > 1.1:
		actual_dist = intended_dist * (1.0 + (line_load - 1.0) * 0.28)
	else:
		actual_dist = intended_dist
	# Form drag: wide/tailing loops shed distance.
	var drag_factor: float = float(LOOP_DRAG_FACTOR.get(loop_quality, 0.85))
	actual_dist *= drag_factor
	var actual_target := _clamp_to_world_bounds(origin + cast_dir * actual_dist)
	actual_target.y = LowerMadisonReachScript.WATER_HEIGHT
	landing = reach.sample(actual_target)
	if not bool(landing["is_water"]):
		actual_target = target
		landing = reach.sample(actual_target)
	_exit_casting_zoom()
	angler.play_cast_animation(cast_style)
	_clear_cast_target_marker()
	# Loop turnover visual: nose unrolls from rod tip to landing (skipped headless).
	# Set before _render_cast so the on-water line stays hidden until the loop arrives.
	if DisplayServer.get_name() != "headless":
		_turnover_timer = TURNOVER_DURATION
		_turnover_origin = origin
		_turnover_landing = actual_target
		_turnover_apex_h = _loop_apex_height_cached
	_render_cast(origin, actual_target)
	_post_cast_state = "DRIFTING • %s" % cast_style.to_upper()
	_cast_state = "CASTING • %s" % cast_style.to_upper()
	_cast_state_timer = 0.72
	var water_name: String = landing["habitat"]
	var hold_distance := reach.nearest_hold_distance(actual_target)
	var quality := _cast_quality(origin.distance_to(actual_target))
	if line_load >= 0.9 and line_load <= 1.1 and quality != "Clean":
		quality = "Clean"
	var selected := FLY_OPTIONS[_selected_fly_index] as Dictionary
	# Sloppy aerial loop / slack line presents worse on the water.
	var initial_drag := 0.0
	if loop_quality == "wide":
		initial_drag = 0.10
	elif loop_quality == "tailing":
		initial_drag = 0.18
	if pending_slack > 2.0:
		initial_drag += 0.15
	_start_dry_fly_drift(origin, actual_target, landing, selected, cast_style, initial_drag)
	_apply_cast_disturbance(actual_target, _style_cast_quality(quality, cast_style))
	var load_note := ""
	if line_load < 0.5:
		load_note = " Short cast — fly landed close."
	elif line_load >= 0.9 and line_load <= 1.1:
		load_note = " Loaded perfectly — clean presentation."
	elif line_load > 1.1:
		load_note = " Over-loaded — fly ran past target."
	if pending_slack > 2.0:
		load_note += " Too much line for the load — it piled up short. Tighter loops to turn it over."
	elif drag_factor < 0.85:
		load_note += " Drag pulled it up short of the mark."
	var message := "%s %s cast: %s drifting through %s.%s" % [quality, cast_style, selected["name"], water_name, load_note]
	if cast_style == "roll":
		message += " Low loop keeps it under cover."
	elif hold_distance <= 3.2:
		message += " Fish moved under it."
	elif hold_distance <= 9.0:
		message += " Good holding water nearby."
	_show_cast_message(message, 3.5)
	_last_cast_target = _selected_cast_target.duplicate(true)
	_selected_cast_target.clear()
	_restore_cast_fov()
	return true


func _normalized_cast_style(style: String) -> String:
	return "roll" if style.to_lower() == "roll" else "overhead"


func _style_cast_quality(quality: String, style: String) -> String:
	if style != "roll":
		return quality
	return "Short" if quality == "Long" else quality


func _initial_cast_line_length(origin: Vector3, target: Vector3) -> float:
	var horizontal_origin := Vector2(origin.x, origin.z)
	var horizontal_target := Vector2(target.x, target.z)
	return clampf(horizontal_origin.distance_to(horizontal_target), CAST_LINE_LENGTH_MIN, CAST_LINE_LENGTH_MAX)


func _adjust_cast_line_length(direction: int) -> void:
	if _selected_cast_target.is_empty():
		return
	var current_length := float(_selected_cast_target.get("line_length", CAST_LINE_LENGTH_MIN))
	var next_length := clampf(current_length + float(direction) * CAST_LINE_LENGTH_STEP, CAST_LINE_LENGTH_MIN, CAST_LINE_LENGTH_MAX)
	_selected_cast_target["line_length"] = next_length
	_show_cast_message("Line length %.0fm. Target stays fixed on the water; aim with rod and feet." % next_length, 1.6)


func _restore_cast_fov() -> void:
	if angler == null:
		return
	angler.set_camera_fov(_default_camera_fov)


func _render_cast_target(origin: Vector3, target: Vector3) -> void:
	_rebuild_cast_line(origin, target + Vector3(0.0, DRY_FLY_SURFACE_OFFSET, 0.0))
	_ensure_cast_target_marker()
	_cast_target_marker.position = Vector3(target.x, LowerMadisonReachScript.WATER_HEIGHT + 0.006, target.z)
	_cast_target_marker.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	_cast_target_marker.visible = true


func _ensure_cast_target_marker() -> void:
	if _cast_target_marker != null and is_instance_valid(_cast_target_marker):
		return
	if _cast_target_marker_mesh == null:
		_cast_target_marker_mesh = QuadMesh.new()
		_cast_target_marker_mesh.size = Vector2(1.35, 1.35)
	_cast_target_marker = MeshInstance3D.new()
	_cast_target_marker.name = "CastTargetMarker"
	_cast_target_marker.mesh = _cast_target_marker_mesh
	_cast_target_marker.material_override = _target_marker_material()
	_cast_target_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_cast_target_marker)


func _target_marker_material() -> Material:
	if _cast_target_marker_material != null:
		return _cast_target_marker_material
	_cast_target_marker_material = StandardMaterial3D.new()
	_cast_target_marker_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cast_target_marker_material.albedo_texture = _target_marker_texture()
	_cast_target_marker_material.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	_cast_target_marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_cast_target_marker_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cast_target_marker_material.emission_enabled = true
	_cast_target_marker_material.emission_texture = _target_marker_texture()
	_cast_target_marker_material.emission = Color(1.0, 1.0, 1.0, 1.0)
	_cast_target_marker_material.emission_energy_multiplier = 0.85
	return _cast_target_marker_material


func _target_marker_texture() -> Texture2D:
	if _cast_target_texture != null:
		return _cast_target_texture
	_cast_target_texture = load(CAST_TARGET_TEXTURE_PATH) as Texture2D
	return _cast_target_texture


func _render_cast(origin: Vector3, target: Vector3) -> void:
	_clear_cast_visuals()
	if _turnover_timer <= 0.0:
		_rebuild_cast_line(origin, target + Vector3(0.0, DRY_FLY_SURFACE_OFFSET, 0.0))

	var selected := FLY_OPTIONS[_selected_fly_index] as Dictionary
	_cast_marker = AdultInsectScript.new()
	_cast_marker.name = "SelectedAdultDryFly"
	_cast_marker.configure(int(selected["kind"]), 0.10, false)
	_cast_marker.position = target + Vector3(0.0, DRY_FLY_SURFACE_OFFSET, 0.0)
	_cast_marker.visible = _turnover_timer <= 0.0
	add_child(_cast_marker)


func _start_dry_fly_drift(origin: Vector3, target: Vector3, landing: Dictionary, selected: Dictionary, cast_style: String = "overhead", initial_drag: float = 0.0) -> void:
	var flow: Vector3 = landing["current_vector"]
	var is_surface := bool(selected.get("surface", true))
	var depth_layer := String(selected.get("depth_layer", "surface"))
	var fly_y_offset: float
	if not is_surface:
		fly_y_offset = -0.40 if depth_layer == "bottom" else -0.25
	else:
		fly_y_offset = DRY_FLY_SURFACE_OFFSET
	_drag_refusal_fired = false
	_active_drift = {
		"origin": origin,
		"position": target + Vector3(0.0, fly_y_offset, 0.0),
		"age": 0.0,
		"duration": DRY_FLY_DRIFT_DURATION,
		"drag": clampf(initial_drag, 0.0, DRY_FLY_MAX_DRAG),
		"previous_flow": flow,
		"fly_name": String(selected["name"]),
		"cast_style": cast_style,
		"habitat": String(landing["habitat"]),
		"current_strength": float(landing["current_strength"]),
		"surface": is_surface,
		"fly_y_offset": fly_y_offset,
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
	if drag >= 0.72 and not _drag_refusal_fired:
		_on_drag_refusal(position)
		return
	var next_position := position + flow * DRY_FLY_FLOW_SCALE * delta
	next_position = _clamp_to_world_bounds(next_position)
	var fly_y_offset: float = float(_active_drift.get("fly_y_offset", DRY_FLY_SURFACE_OFFSET))
	next_position.y = LowerMadisonReachScript.WATER_HEIGHT + fly_y_offset
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
		var lane_radius := maxf(float(fish.get("feeding_lane_radius", FISH_TAKE_RADIUS)), FISH_TAKE_RADIUS)
		if fly_position.distance_squared_to(fish_position) > lane_radius * lane_radius:
			continue
		var distance := fly_position.distance_to(fish_position)
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
	var feeding_bonus := 0.15 if TimeOfDay.is_feeding_window() else 0.0
	return distance_score * 0.36 + current_score * 0.18 + hatch_score * 0.24 + affinity_score * 0.20 + species_bias + feeding_bonus - drag_penalty - alert_penalty >= 0.52


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
	if bool(_active_drift.get("surface", true)):
		_spawn_surface_rise_at(fly_position, 0.82)
	_play_sound_cue("fish_take")
	_show_cast_message("Take! %s rose to the %s." % [String(fish["name"]), String(_active_drift["fly_name"])], 2.0)
	_tween_visible_fish_to(fish, fly_position)


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


func _update_visible_fish_animation() -> void:
	var elapsed := Time.get_ticks_msec() * 0.0022
	for node in get_tree().get_nodes_in_group("visible_fish"):
		if node is Node3D and node.has_method("animate_swim"):
			node.call("animate_swim", elapsed)


func _update_fish_ai(delta: float) -> void:
	if builder == null or builder.fish_hold_entries.is_empty():
		return
	var player_pos := angler.global_position
	var player_wading := is_wading(player_pos)
	var selected_hatch_score := _selected_fly_hatch_score()
	for i in range(builder.fish_hold_entries.size()):
		var fish := builder.fish_hold_entries[i] as Dictionary
		if not bool(fish.get("available", true)):
			builder.fish_hold_entries[i] = fish
			continue
		var fish_pos: Vector3 = fish["position"]
		var distance_sq := fish_pos.distance_squared_to(player_pos)
		var spook_radius := _fish_spook_radius(fish)
		var alert := float(fish.get("alert", 0.0))
		if player_wading:
			var vibration_radius := spook_radius
			if GameManager.difficulty != null:
				vibration_radius = maxf(vibration_radius, float(GameManager.difficulty.wading_vibration_radius))
			if distance_sq < vibration_radius * vibration_radius:
				var distance := sqrt(distance_sq)
				alert = maxf(alert, 1.0 - distance / maxf(vibration_radius, 0.1))
		if distance_sq < spook_radius * 0.55 * spook_radius * 0.55:
			alert = 1.0
		var state := String(fish.get("state", "feeding"))
		if alert >= 0.88:
			state = "spooked"
		elif alert >= FISH_FEEDING_ALERT_LIMIT:
			state = "alert"
		elif selected_hatch_score >= 0.44:
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
		var distance_sq := (fish["position"] as Vector3).distance_squared_to(target)
		if distance_sq > splash_radius * splash_radius:
			continue
		var distance := sqrt(distance_sq)
		fish["alert"] = maxf(float(fish.get("alert", 0.0)), 1.0 - distance / maxf(splash_radius, 0.1))
		if float(fish["alert"]) >= 0.82:
			fish["state"] = "spooked"
			spooked_count += 1
		builder.fish_hold_entries[i] = fish
	if spooked_count > 0:
		_session_stats["spooked"] = int(_session_stats.get("spooked", 0)) + spooked_count
		_play_sound_cue("cast_splash")


func _update_cast_visuals(origin: Vector3, target: Vector3) -> void:
	# While the loop is turning over, the unrolling aerial loop owns the visuals.
	if _turnover_timer > 0.0:
		return
	if _cast_marker != null and is_instance_valid(_cast_marker):
		_cast_marker.global_position = target
		_cast_marker.visible = true
	_rebuild_cast_line(origin, target)


func _refresh_cast_line_attachment() -> void:
	if _turnover_timer > 0.0:
		return
	if _cast_line == null and _leader_line == null:
		return
	if _cast_marker != null and is_instance_valid(_cast_marker):
		_update_cast_visuals(_current_rod_tip(), _cast_marker.global_position)
		return
	if not _selected_cast_target.is_empty() and _fly_is_on_water():
		var target: Vector3 = _selected_cast_target["target"]
		_rebuild_cast_line(_current_rod_tip(), target + Vector3(0.0, DRY_FLY_SURFACE_OFFSET, 0.0))


func _rebuild_cast_line(origin: Vector3, target: Vector3) -> void:
	if not _should_rebuild_cast_line(origin, target):
		return

	var fly_position := target
	var fly_sample := reach.sample(fly_position)
	var leader_start_t := _leader_start_fraction_for_line(origin, fly_position)
	var line_points := _build_line_points(origin, fly_position, fly_sample, 0.0, leader_start_t, leader_start_t)
	var leader_points := _build_line_points(origin, fly_position, fly_sample, leader_start_t, 1.0, leader_start_t)
	var line_mesh := _build_ribbon_mesh(line_points, CAST_LINE_RIBBON_HALF_WIDTH, _fly_line_mat)
	var leader_mesh := _build_ribbon_mesh(leader_points, LEADER_RIBBON_HALF_WIDTH, _leader_mat)

	if _cast_line == null or not is_instance_valid(_cast_line):
		_cast_line = MeshInstance3D.new()
		_cast_line.name = "CastLine"
		_cast_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_cast_line)
	_cast_line.mesh = line_mesh
	# Ribbon meshes weld/offset their triangle vertices, so the raw vertex array no
	# longer maps to the line path. Expose the source centerline for callers and
	# tests that validate rod-tip attachment, the line→leader seam, and the fly end.
	_cast_line.set_meta("centerline", line_points)

	if _leader_line == null or not is_instance_valid(_leader_line):
		_leader_line = MeshInstance3D.new()
		_leader_line.name = "CastLeader"
		_leader_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_leader_line)
	_leader_line.mesh = leader_mesh
	_leader_line.set_meta("centerline", leader_points)
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


func _leader_start_fraction_for_line(origin: Vector3, fly_position: Vector3) -> float:
	var distance := origin.distance_to(fly_position)
	if distance <= 0.001:
		return 1.0
	var leader_length := minf(LEADER_LENGTH, distance * 0.42)
	return clampf(1.0 - (leader_length / distance), 0.0, 1.0)


func _init_fly_line_materials() -> void:
	if MAT_FLY_LINE is StandardMaterial3D:
		var mat := (MAT_FLY_LINE as StandardMaterial3D).duplicate() as StandardMaterial3D
		mat.emission_enabled = true
		mat.emission = Color(0.55, 0.62, 0.28)
		mat.emission_energy_multiplier = 0.35
		# Double-sided: the camera-facing aerial ribbon can wind either way per segment.
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_fly_line_mat = mat
	else:
		_fly_line_mat = MAT_FLY_LINE
	_leader_mat = MAT_LEADER


func _init_loop_physics() -> void:
	_casting_state_mgr = CastingStateManager.new()
	add_child(_casting_state_mgr)
	_casting_state_mgr.delivered.connect(_on_cast_delivered)
	_casting_state_mgr.false_cast.connect(_on_cast_false_cast)
	_casting_state_mgr.stroke_scored.connect(_on_cast_stroke_scored)
	_line_renderer = CastingLineRenderer.new()
	add_child(_line_renderer)


func _build_ribbon_mesh(points: PackedVector3Array, half_width: float, material: Material) -> ArrayMesh:
	if DisplayServer.get_name() == "headless":
		return ArrayMesh.new()

	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := points.size()
	for i in range(n - 1):
		var a := points[i]
		var b := points[i + 1]
		var seg_dir := (b - a).normalized()
		var up := Vector3.UP
		var right := seg_dir.cross(up).normalized()
		if right.length_squared() < 0.001:
			right = seg_dir.cross(Vector3.FORWARD).normalized()
		var offset := right * half_width
		var a0 := a - offset
		var a1 := a + offset
		var b0 := b - offset
		var b1 := b + offset
		tool.set_normal(up)
		tool.add_vertex(a0)
		tool.add_vertex(b0)
		tool.add_vertex(b1)
		tool.add_vertex(a0)
		tool.add_vertex(b1)
		tool.add_vertex(a1)
	tool.generate_normals()
	return tool.commit()


func _build_line_points(origin: Vector3, fly_position: Vector3, fly_sample: Dictionary, start_t: float, end_t: float, leader_start_t: float) -> PackedVector3Array:
	var points := PackedVector3Array()
	for i in range(CAST_LINE_SEGMENTS + 1):
		var local_t := float(i) / float(CAST_LINE_SEGMENTS)
		var t := lerpf(start_t, end_t, local_t)
		points.append(_cast_curve_point(origin, fly_position, fly_sample, t, leader_start_t))
	return points


func _cast_curve_point(origin: Vector3, fly_position: Vector3, fly_sample: Dictionary, t: float, leader_start_t: float) -> Vector3:
	var point := origin.lerp(fly_position, t)
	var blend_start := maxf(0.0, leader_start_t - CAST_LEADER_TRANSITION_BLEND)
	var blend_end := minf(1.0, leader_start_t + CAST_LEADER_TRANSITION_BLEND)
	var leader_weight := smoothstep(blend_start, blend_end, t)
	var sag_scale := lerpf(1.0, 0.28, leader_weight)
	point.y -= sin(t * PI) * CAST_LINE_SAG * sag_scale
	if bool(fly_sample.get("is_water", false)):
		var flow: Vector3 = fly_sample.get("current_vector", Vector3.ZERO)
		if flow.length_squared() > 0.0001:
			var bow_scale := lerpf(1.0, 0.65, leader_weight)
			var bow := sin(t * PI) * float(fly_sample.get("current_strength", 0.0)) * CAST_LINE_CURRENT_BOW * bow_scale
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
	_clear_aerial_cast_line()
	_cast_line = null
	_leader_line = null
	_cast_marker = null
	_invalidate_cast_line_cache()


func _update_aerial_cast_line(delta: float) -> void:
	# During turnover the aerial node is owned by _update_turnover.
	if _turnover_timer > 0.0:
		return
	if _selected_cast_target.is_empty() or _gesture_state == "idle":
		_clear_aerial_cast_line()
		return
	if _gesture_state not in ["backcast", "forward", "lifting_roll"]:
		_clear_aerial_cast_line()
		return
	var origin := _current_rod_tip()
	var target: Vector3 = _selected_cast_target["target"]
	var phase := "backcast" if _gesture_state in ["backcast", "lifting_roll"] else "forward"
	var progress: float = clampf(_casting_state_mgr.get_unroll_progress(), 0.0, 1.3) if _casting_state_mgr != null else 0.0
	_ensure_aerial_line_node()

	# Hide static cast line during aerial stroke
	if _cast_line != null and is_instance_valid(_cast_line):
		_cast_line.visible = false
	if _aerial_line_node != null:
		_aerial_line_node.visible = true

	_rebuild_aerial_line(origin, target, phase, progress, delta)


func _update_turnover(delta: float) -> void:
	if _turnover_timer <= 0.0:
		return
	_turnover_timer = maxf(_turnover_timer - delta, 0.0)
	var apex_t := clampf(1.0 - _turnover_timer / TURNOVER_DURATION, 0.0, 1.0)
	# Loop nose travels from rod tip toward the landing, flattening as it arrives.
	var apex := _turnover_origin.lerp(_turnover_landing, apex_t)
	apex.y += _turnover_apex_h * (1.0 - apex_t)
	var points := PackedVector3Array()
	var rod_segs: int = AERIAL_LINE_SEGMENTS / 2
	for i in range(rod_segs + 1):
		points.append(_turnover_origin.lerp(apex, float(i) / float(rod_segs)))
	var fly_segs: int = AERIAL_LINE_SEGMENTS - rod_segs
	for i in range(1, fly_segs + 1):
		var ft := float(i) / float(fly_segs)
		var p := apex.lerp(_turnover_landing, ft)
		p.y += sin(ft * PI) * _turnover_apex_h * 0.4 * (1.0 - apex_t)
		points.append(p)
	_ensure_aerial_line_node()
	_aerial_line_node.mesh = _build_ribbon_mesh(points, CAST_LINE_RIBBON_HALF_WIDTH, _fly_line_mat)
	if _turnover_timer <= 0.0:
		# Hand off to the normal bowed cast line + visible fly next frame.
		_clear_aerial_cast_line()


func _ensure_aerial_line_node() -> void:
	if _aerial_line_node != null and is_instance_valid(_aerial_line_node):
		return
	_aerial_line_node = MeshInstance3D.new()
	_aerial_line_node.name = "AerialCastLine"
	_aerial_line_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_aerial_line_node)


func _clear_aerial_cast_line() -> void:
	if _aerial_line_node != null and is_instance_valid(_aerial_line_node):
		_aerial_line_node.queue_free()
	_aerial_line_node = null
	_aerial_pts = PackedVector3Array()
	_aerial_phase = ""

	# Restore static cast line visibility
	if _cast_line != null and is_instance_valid(_cast_line):
		_cast_line.visible = true


func _rebuild_aerial_line(origin: Vector3, target: Vector3, phase: String, progress: float, delta: float) -> void:
	# The casting state machine is advanced once per frame in _drive_casting_loop;
	# here we only read the current loop geometry for rendering.
	if _casting_state_mgr != null:
		var loop_state = _casting_state_mgr.get_loop_state()

		# Cast direction and extension (not toward target, but along cast stroke)
		var cast_dir := _current_cast_direction()
		cast_dir.y = 0.0
		if cast_dir.length() < 0.01:
			cast_dir = Vector3.FORWARD
		cast_dir = cast_dir.normalized()
		var leg_dir := cast_dir if phase == "forward" else -cast_dir

		# Line extends along cast direction, grows as stroke progresses
		var distance := origin.distance_to(target)
		var reach := distance * (0.7 if phase == "backcast" else 1.0)
		var ext := reach * (0.12 + 0.88 * (progress if progress <= 1.0 else 1.0))  # extension distance

		# Calculate perpendicular (up) for loop bulge
		var perpendicular := Vector3.UP
		var side_vec := leg_dir.cross(perpendicular).normalized()
		if side_vec.length_squared() < 0.001:
			side_vec = Vector3.RIGHT

		# Build line path with parabolic loop bulge
		var target_pts := PackedVector3Array()
		target_pts.resize(AERIAL_LINE_SEGMENTS + 1)

		var loop_position = loop_state.position_along_line  # [0, 1]
		var loop_width = loop_state.width  # meters

		for i in range(AERIAL_LINE_SEGMENTS + 1):
			var t = float(i) / float(AERIAL_LINE_SEGMENTS)  # [0, 1] along line

			# Base position: along cast direction, not toward target
			var base_pos: Vector3 = origin + leg_dir * ext * t

			# Parabolic offset from loop: distance to loop center, falloff by width
			var dist_to_loop = absf(t - loop_position)
			var bulge_factor = maxf(1.0 - (dist_to_loop / maxf(loop_width, 0.05)), 0.0)
			# Taper the bulge to zero at both ends so the line meets the rod tip (t=0)
			# and the fly (t=1) cleanly instead of kinking up off the tip.
			var end_anchor := smoothstep(0.0, 0.12, t) * (1.0 - smoothstep(0.85, 1.0, t))
			var bulge_amount = bulge_factor * bulge_factor * loop_width * 4.0 * end_anchor

			# Apply perpendicular offset (both up and slightly to side for visual interest)
			var offset = perpendicular * bulge_amount + side_vec * bulge_amount * 0.3
			target_pts[i] = base_pos + offset

		# Temporal smoothing — but keep the near-tip segment locked to the current rod
		# tip (k -> 1 at t=0) so the line never visibly detaches as the tip moves; the
		# fly end is smoothed normally.
		if _aerial_pts.size() != target_pts.size() or _aerial_phase != phase:
			_aerial_pts = target_pts.duplicate()
		else:
			var base_k := minf(delta * 14.0, 1.0)
			for i in range(target_pts.size()):
				var ti := float(i) / float(AERIAL_LINE_SEGMENTS)
				var k := lerpf(1.0, base_k, smoothstep(0.0, 0.4, ti))
				_aerial_pts[i] = _aerial_pts[i].lerp(target_pts[i], k)

		_aerial_phase = phase
		_aerial_pts[0] = origin  # hard-anchor to rod tip

		# Use loop-aware ribbon renderer (camera-facing so the loop nose doesn't spike)
		if _line_renderer != null:
			var cam := get_viewport().get_camera_3d()
			var cam_pos := cam.global_position if cam != null else Vector3.INF
			var cam_right := cam.global_transform.basis.x if cam != null else Vector3.ZERO
			_aerial_line_node.mesh = _line_renderer.build_ribbon_with_loop(
				_aerial_pts,
				CAST_LINE_RIBBON_HALF_WIDTH,
				loop_state,
				_fly_line_mat,
				cam_pos,
				cam_right
			)
		else:
			_aerial_line_node.mesh = _build_ribbon_mesh(_aerial_pts, CAST_LINE_RIBBON_HALF_WIDTH, _fly_line_mat)


func _cubic3(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var u := 1.0 - t
	return (u * u * u) * p0 + (3.0 * u * u * t) * p1 + (3.0 * u * t * t) * p2 + (t * t * t) * p3


func _clear_cast_target_marker() -> void:
	if _cast_target_marker != null and is_instance_valid(_cast_target_marker):
		_cast_target_marker.visible = false


func _cast_quality(distance: float) -> String:
	if distance < 8.0:
		return "Short"
	if distance <= 34.0:
		return "Clean"
	return "Long"


func _on_fly_change_requested() -> void:
	_selected_fly_index = (_selected_fly_index + 1) % FLY_OPTIONS.size()
	_exit_casting_zoom()
	_selected_cast_target.clear()
	_active_drift.clear()
	_pending_take.clear()
	_drift_readout = ""
	_clear_cast_visuals()
	_restore_cast_fov()
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
	var mode_str := "CASTING" if (angler != null and angler.has_method("is_in_cast_mode") and angler.is_in_cast_mode()) else "EXPLORING"
	var control_hint: String
	if not _selected_cast_target.is_empty():
		var line_length := float(_selected_cast_target.get("line_length", DEFAULT_LINE_LENGTH))
		var target_dist := float(_selected_cast_target.get("origin", angler.global_position).distance_to(_selected_cast_target.get("target", angler.global_position)))
		control_hint = "%s · line %.0fm / %.0fm target · LMB strip · RMB retrieve · mouse rod · lower to deliver · Tab exit" % [mode_str, line_length, target_dist]
	elif _fighting:
		control_hint = "%s · FISH ON · mouse rod tension · MMB hookset · Tab exit" % mode_str
	elif mode_str == "CASTING":
		control_hint = "CASTING · click water for target · Tab to return to explore · Q fly · 0-5 debug"
	else:
		control_hint = "EXPLORING · WASD move · mouse look · click water to cast · Q fly · N net · 0-5 debug · Esc mouse"
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
	var fly_type := "dry" if bool(selected.get("surface", true)) else "[SUBSURFACE] %s" % String(selected.get("depth_layer", "mid"))
	fly_label.text = "%s\n%s · %s · %s" % [selected["name"], selected["species"], selected["phase"], fly_type]
	cast_state_label.text = _cast_state if _drift_readout.is_empty() else "%s\n%s" % [_cast_state, _drift_readout]
	hatch_label.text = _surface_life_label()
	_update_casting_loop_hud()
	_update_debug_label(sample)


func _update_casting_loop_hud() -> void:
	_update_minigame_panel()


func _update_minigame_panel() -> void:
	if _minigame_panel == null:
		return
	var show := not _selected_cast_target.is_empty()
	_minigame_panel.visible = show
	if not show:
		return
	_minigame_panel.gesture_state = _gesture_state
	if _casting_state_mgr != null:
		_minigame_panel.line_load = _casting_state_mgr.get_line_load()
		_minigame_panel.loop_quality = _casting_state_mgr.get_loop_quality()
		_minigame_panel.unroll_progress = _casting_state_mgr.get_unroll_progress()
		_minigame_panel.stroke_dir = _casting_state_mgr.get_stroke_dir()
		_minigame_panel.ready_to_deliver = _casting_state_mgr.is_ready_to_deliver()

	# Loop physics feedback
	if _casting_state_mgr != null:
		var loop_state = _casting_state_mgr.get_loop_state()
		_minigame_panel.loop_position = loop_state.position_along_line
		_minigame_panel.loop_width = loop_state.width

	_minigame_panel.queue_redraw()


func _reset_cast_loop_state() -> void:
	# Stroke/load/quality state now lives in the casting seam.
	if _casting_state_mgr != null:
		_casting_state_mgr.reset_to_setup()
	_gesture_state = "idle"
	_loop_apex_height_cached = 0.8


func _enter_casting_zoom(target: Vector3) -> void:
	_reset_cast_loop_state()
	if angler != null and angler.has_method("enter_casting_stance"):
		angler.enter_casting_stance(target)


# Pick up the line and re-arm the last delivered target so the player can recast
# without re-selecting water. Triggered by raising the rod after a delivery.
func _try_cast_pickup() -> void:
	if _fighting or _last_cast_target.is_empty():
		return
	if angler == null or angler.rod == null or not angler.is_in_cast_mode():
		return
	if angler.rod.get_elevation_offset() < OVERHEAD_LIFT_START_ELEV:
		return
	_active_drift.clear()
	_pending_take.clear()
	_clear_cast_visuals()
	_selected_cast_target = _last_cast_target.duplicate(true)
	_reset_cast_loop_state()
	_render_cast_target(_current_rod_tip(), _selected_cast_target["target"])
	_show_cast_message("Line picked up — backcast to recast.", 1.2)


func _exit_casting_zoom() -> void:
	if _casting_state_mgr != null:
		_casting_state_mgr.reset_to_setup()
	_gesture_state = "idle"
	if angler != null and angler.rod != null:
		angler.rod.set_live_cast_load("idle", 0.0)
	if _minigame_panel != null:
		_minigame_panel.visible = false


func _rod_elevation() -> float:
	if angler == null or angler.rod == null:
		return 0.0
	return angler.rod.get_elevation_offset()


func _current_cast_direction() -> Vector3:
	var fwd := -angler.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	if angler.has_method("get_rod_aim_yaw"):
		var yaw: float = angler.get_rod_aim_yaw()
		fwd = fwd.rotated(Vector3.UP, yaw)
	return fwd


func _fly_is_on_water() -> bool:
	return not _active_drift.is_empty()


func _elevation_to_arc(elev: float, max_elev: float) -> float:
	return clampf(elev / maxf(max_elev, 0.01), 0.0, 1.0)


# --- Casting loop integration: feed the CastingStateManager seam and react to its
# events. The module owns phase/load/quality/delivery; the world owns the rod visual,
# HUD strings, reach landing, drift and fish spook. ---

func _drive_casting_loop(delta: float) -> void:
	if _selected_cast_target.is_empty():
		_try_cast_pickup()
		if _selected_cast_target.is_empty():
			return
	if angler == null or angler.rod == null or _casting_state_mgr == null:
		return
	var elev: float = _rod_elevation()
	var cast_input: Dictionary = angler.get_cast_input_state()
	var line_length := float(_selected_cast_target.get("line_length", DEFAULT_LINE_LENGTH))
	var lateral: float = angler.get_rod_aim_yaw() if angler.has_method("get_rod_aim_yaw") else 0.0
	_casting_state_mgr.set_cast_context(line_length, lateral, _fly_is_on_water(), angler.rod.get_peak_lift_speed())
	_casting_state_mgr.update(delta, elev, float(cast_input.get("mouse_dy", 0.0)))
	_sync_casting_presentation(elev)


# Mirrors the module phase into the presentation state the rod/HUD/aerial-line code
# reads, and drives the per-phase rod flex visual and HUD prompts.
func _sync_casting_presentation(elev: float) -> void:
	var prev := _gesture_state
	_gesture_state = _gesture_state_for_phase(_casting_state_mgr.get_phase_name())
	# Peak lift speed is consumed at the SETUP decision; reset it once a stroke begins
	# so the next lift is re-measured.
	if prev == "idle" and _gesture_state != "idle" and angler.rod != null:
		angler.rod.reset_peak_lift_speed()
	match _gesture_state:
		"backcast":
			angler.rod.set_live_cast_load("backcast", _elevation_to_arc(elev, OVERHEAD_ARC_MAX_ELEV))
			if prev != "backcast":
				_set_cast_state("BACKCAST — reverse when the loop straightens (green)")
				if prev == "idle":
					_show_cast_message("Backcast — raise the rod, reverse when the loop turns green.", 1.6)
		"forward":
			angler.rod.set_live_cast_load("forward", _elevation_to_arc(elev, FORWARD_ARC_MAX_ELEV))
			if prev != "forward":
				_set_cast_state("FORWARD — false-cast to load, deliver when LOADED")
		"lifting_roll":
			if prev != "lifting_roll":
				_show_cast_message("Gentle lift — D-loop forming. Sweep forward to roll cast.", 1.8)
		_:
			angler.rod.set_live_cast_load("idle", 0.0)


func _gesture_state_for_phase(phase_name: String) -> String:
	match phase_name:
		"BACKCAST":
			return "backcast"
		"FORWARD":
			return "forward"
		"ROLL":
			return "lifting_roll"
		_:
			return "idle"


func _set_cast_state(text: String) -> void:
	_cast_state = text
	_post_cast_state = text


func _apex_for_quality(quality: String) -> float:
	match quality:
		"tight":
			return 0.35
		"adequate":
			return 0.80
		"tailing":
			return 0.15
		"wide":
			return 2.0
		_:
			return 0.8


func _on_cast_delivered(style: String, _line_load_value: float, _loop_quality_value: String) -> void:
	if style == "roll":
		_loop_apex_height_cached = 0.80
	perform_selected_cast(style)
	if angler != null and angler.rod != null:
		angler.rod.set_live_cast_load("idle", 0.0)
		angler.rod.reset_elevation()


func _on_cast_false_cast(count: int) -> void:
	if not _selected_cast_target.is_empty():
		_apply_false_cast_spook(_selected_cast_target["target"], count)


func _on_cast_stroke_scored(quality: String, line_load_value: float) -> void:
	_loop_apex_height_cached = _apex_for_quality(quality)
	match quality:
		"tight":
			_show_cast_message("Tight loop — %d%% loaded." % int(line_load_value * 100.0), 0.7)
		"adequate":
			_show_cast_message("Adequate loop — %d%% loaded." % int(line_load_value * 100.0), 0.7)
		"tailing":
			_show_cast_message("Tailing — reversed too early. Let the line straighten in the air.", 1.3)
		"wide":
			_show_cast_message("Wide — waited too long, the loop collapsed. Reverse on green.", 1.3)


func _apply_false_cast_spook(target: Vector3, count: int) -> void:
	if count < 3 or builder == null:
		return
	var radius_sq := FISH_TAKE_RADIUS * FISH_TAKE_RADIUS * 4.0
	if count == 3:
		var best_i := -1
		var best_sq := radius_sq
		for i in range(builder.fish_hold_entries.size()):
			var fish := builder.fish_hold_entries[i] as Dictionary
			var d := (fish["position"] as Vector3).distance_squared_to(target)
			if d < best_sq:
				best_sq = d
				best_i = i
		if best_i >= 0:
			var fish := builder.fish_hold_entries[best_i] as Dictionary
			fish["alert"] = minf(float(fish.get("alert", 0.0)) + 0.15, 1.0)
			builder.fish_hold_entries[best_i] = fish
		return
	for i in range(builder.fish_hold_entries.size()):
		var fish := builder.fish_hold_entries[i] as Dictionary
		if (fish["position"] as Vector3).distance_squared_to(target) > radius_sq:
			continue
		fish["alert"] = minf(float(fish.get("alert", 0.0)) + 0.25, 1.0)
		if count >= 6:
			fish["state"] = "spooked"
		builder.fish_hold_entries[i] = fish


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
	if _audio_player == null or not is_instance_valid(_audio_player):
		return
	if not audio_cue_streams.has(cue_name):
		return
	var stream := audio_cue_streams[cue_name] as AudioStream
	if stream == null:
		return
	_audio_player.stream = stream
	_audio_player.play()
