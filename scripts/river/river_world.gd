extends Node2D


@onready var camera:       RiverCamera       = $Camera2D
@onready var tilemap:      RiverRenderer     = $TileMap
@onready var sky_strip:    ColorRect         = $SkyLayer/SkyStrip
@onready var angler:       Angler            = $Angler
@onready var casting:      CastingController = $CastingController
@onready var drift:        DriftController   = $DriftController
@onready var rod_arc_hud:  RodArcHUD         = $HUD/RodArcHUD
@onready var fly_selector: FlySelector       = $HUD/FlySelector
@onready var net_sampler:       NetSampler         = $NetSampler
@onready var sample_panel:      SamplePanel        = $HUD/SamplePanel
@onready var insect_layer:      CanvasLayer        = $InsectLayer
@onready var hookset_controller: HooksetController = $HooksetController
@onready var logbook_panel:     LogbookPanel       = $HUD/LogbookPanel

# World pixels in one section
const SECTION_W_PX := RiverConstants.SECTION_W_TILES * RiverConstants.TILE_SIZE
# Pre-generate next section once angler reaches this fraction through the current one
const PRELOAD_AT := 0.70
# Minimum world-space gap between fish spawn points
const MIN_FISH_DIST := 48.0

# river_data for the section the angler is currently in (updated on crossing)
var river_data: RiverData

# All currently loaded sections.
# Each entry: { index:int, data:RiverData, renderer:Node, fish_list:Array, start_px:float }
var _sections: Array = []

var _current_section_idx: int = 0
var _catch_log: CatchLog = null
var _fish_list: Array = []    # all active fish across loaded sections
var _show_debug := false


func _ready() -> void:
	# Session always pre-initialized by SessionConfig; guard for direct scene launch in editor
	if GameManager.session_id < 0:
		GameManager.new_session(12345, 6.0, DifficultyConfig.Tier.STANDARD)

	_spawn_section(0)
	var s0: Dictionary = _sections[0]
	river_data = s0["data"] as RiverData

	# Angler + camera
	angler.river_data    = river_data
	angler.section_start_x = 0.0
	camera.follow_target = angler
	camera.set_anchor(angler.position.x)

	# Casting system
	casting.angler      = angler
	rod_arc_hud.casting = casting
	rod_arc_hud.drift   = drift

	casting.drift_started.connect(drift.on_drift_started)
	casting.drift_ended.connect(drift.on_drift_ended)
	casting.mend_upstream.connect(drift.on_mend.bind(-1))
	casting.mend_downstream.connect(drift.on_mend.bind(1))
	casting.cast_result.connect(_on_cast_result)

	# Net sampler
	net_sampler.angler     = angler
	net_sampler.river_data = river_data
	angler.standing_still.connect(net_sampler.on_standing_still)
	net_sampler.sample_complete.connect(_on_sample_complete)

	# Catch log + logbook
	_catch_log = CatchLog.new()
	logbook_panel.catch_log = _catch_log

	# Hookset controller
	hookset_controller.casting      = casting
	hookset_controller.fly_selector = fly_selector
	casting.drift_started.connect(hookset_controller.on_drift_started)
	casting.drift_ended.connect(hookset_controller.on_drift_ended)
	hookset_controller.catch_confirmed.connect(_on_catch_confirmed)
	hookset_controller.hard_spook.connect(_on_hard_spook)
	hookset_controller.miss_late.connect(_on_miss_late)

	# Hatch system
	HatchManager.hatch_state_changed.connect(_on_hatch_state_changed)
	_spawn_insects(HatchManager.current_state)

	_update_sky()
	TimeOfDay.period_changed.connect(_on_period_changed)
	angler.standing_still.connect(_on_angler_standing_still)

	if OS.is_debug_build():
		print("RiverWorld ready | seed=%d | top holds=%d | structures=%d" % [
			river_data.seed, river_data.top_holds.size(), river_data.structures.size(),
		])


func _process(_delta: float) -> void:
	camera.set_anchor(angler.global_position.x)
	_check_section_transition()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if (event as InputEventKey).physical_keycode == KEY_COMMA:
			_show_debug = not _show_debug
			var renderer := _current_renderer()
			if _show_debug and renderer != null:
				renderer.show_hold_debug(river_data)
			elif renderer != null:
				renderer.hide_hold_debug()


# ---------------------------------------------------------------------------
# Section lifecycle
# ---------------------------------------------------------------------------

func _section_seed(idx: int) -> int:
	return abs(hash(GameManager.session_seed + idx * 999983))


func _has_section(idx: int) -> bool:
	for s in _sections:
		if (s as Dictionary)["index"] == idx:
			return true
	return false


func _spawn_section(idx: int) -> void:
	if _has_section(idx):
		return

	var seed_val   := _section_seed(idx)
	var generator  := RiverGenerator.new()
	var data       := generator.generate(seed_val, GameManager.difficulty)
	var start_px   := float(idx * SECTION_W_PX)

	var renderer: RiverRenderer
	if idx == 0:
		renderer = tilemap
		tilemap.render(data)
	else:
		renderer = RiverRenderer.new()
		renderer.position = Vector2(start_px, 0.0)
		add_child(renderer)
		renderer.render(data)

	var fish_list := _spawn_section_fish(data, idx, start_px)
	_sections.append({
		"index":     idx,
		"data":      data,
		"renderer":  renderer,
		"fish_list": fish_list,
		"start_px":  start_px,
	})

	if OS.is_debug_build():
		print("RiverWorld: loaded section %d | seed=%d | fish=%d" % [
			idx, data.seed, fish_list.size()
		])


func _despawn_section(idx: int) -> void:
	for i in range(_sections.size() - 1, -1, -1):
		var sd: Dictionary = _sections[i]
		if (sd["index"] as int) != idx:
			continue

		var renderer: Node = sd["renderer"]
		if renderer == tilemap:
			tilemap.visible = false   # never queue_free the static scene node
		else:
			renderer.queue_free()

		var fl: Array = sd["fish_list"]
		for f in fl:
			if is_instance_valid(f):
				_fish_list.erase(f)
				(f as FishAI).queue_free()

		_sections.remove_at(i)
		if OS.is_debug_build():
			print("RiverWorld: despawned section %d" % idx)
		return


func _current_renderer() -> RiverRenderer:
	for s in _sections:
		var sd: Dictionary = s
		if (sd["index"] as int) == _current_section_idx:
			return sd["renderer"] as RiverRenderer
	return null


# ---------------------------------------------------------------------------
# Section transition — called each frame from _process
# ---------------------------------------------------------------------------

func _check_section_transition() -> void:
	var angler_x     := angler.position.x
	var local_x      := angler_x - float(_current_section_idx * SECTION_W_PX)
	var next_idx     := _current_section_idx + 1
	var section_w_f  := float(SECTION_W_PX)

	# Pre-load next section when PRELOAD_AT fraction into current
	if local_x >= section_w_f * PRELOAD_AT and not _has_section(next_idx):
		_spawn_section(next_idx)
		camera.update_section_limit(float((next_idx + 1) * SECTION_W_PX))

	# Cross boundary into next section
	if local_x >= section_w_f:
		_current_section_idx = next_idx
		_update_angler_section(_current_section_idx)
		_despawn_section(_current_section_idx - 2)


func _update_angler_section(idx: int) -> void:
	for s in _sections:
		var sd: Dictionary = s
		if (sd["index"] as int) != idx:
			continue
		river_data             = sd["data"] as RiverData
		angler.river_data      = river_data
		angler.section_start_x = sd["start_px"] as float
		net_sampler.river_data = river_data
		# Interrupt any active cast/hookset when crossing sections
		hookset_controller.reset()
		drift.on_drift_ended()
		casting.state = CastingController.State.IDLE
		return


# ---------------------------------------------------------------------------
# Fish spawning
# ---------------------------------------------------------------------------

func _spawn_section_fish(data: RiverData, section_idx: int, start_px: float) -> Array:
	var fish_scene := load("res://scenes/Fish.tscn") as PackedScene
	var count      := 0
	var placed: Array = []
	var result: Array = []

	for hold in data.top_holds:
		if count >= GameManager.difficulty.fish_per_section:
			break

		var hx: int = hold["x"]
		var hy: int = hold["y"]
		var wp := Vector2(
			start_px + float(hx) * RiverConstants.TILE_SIZE + RiverConstants.TILE_SIZE * 0.5,
			float(hy) * RiverConstants.TILE_SIZE + RiverConstants.TILE_SIZE * 0.5
		)

		var skip := false
		for pp in placed:
			var ppv: Vector2 = pp
			if wp.distance_to(ppv) < MIN_FISH_DIST:
				skip = true
				break
		if skip:
			continue

		var fish := fish_scene.instantiate() as FishAI
		var rng  := RandomNumberGenerator.new()
		rng.seed = hash(data.seed + count * 997)

		# Species distribution: 50% Brown, 40% Rainbow, 10% Whitefish
		var sr := rng.randf()
		if sr < 0.50:
			fish.species = FishAI.Species.BROWN_TROUT
		elif sr < 0.90:
			fish.species = FishAI.Species.RAINBOW_TROUT
		else:
			fish.species = FishAI.Species.WHITEFISH

		# Size distribution: 60% Small, 30% Medium, 10% Large
		var sz := rng.randf()
		if sz < 0.60:
			fish.size_class = SpookCalculator.FishSize.SMALL
		elif sz < 0.90:
			fish.size_class = SpookCalculator.FishSize.MEDIUM
		else:
			fish.size_class = SpookCalculator.FishSize.LARGE

		fish.variant_seed    = hash(data.seed + count * 7919)
		fish.hold_pos        = wp
		fish.section_start_px = start_px
		fish.angler          = angler
		fish.river_data      = data

		fish.take_fly.connect(hookset_controller.on_fish_take.bind(fish))
		add_child(fish)
		placed.append(wp)
		result.append(fish)
		_fish_list.append(fish)
		count += 1

	if OS.is_debug_build():
		print("RiverWorld: spawned %d fish in section %d" % [count, section_idx])
	return result


# ---------------------------------------------------------------------------
# Sky strip
# ---------------------------------------------------------------------------

func _update_sky() -> void:
	var idx := int(TimeOfDay.current_period)
	sky_strip.color = RiverConstants.SKY_COLORS[idx]


func _on_period_changed(_period: int) -> void:
	_update_sky()
	if OS.is_debug_build():
		print("Period: %s  light=%.2f  sun=%.1f°" % [
			TimeOfDay.period_name(),
			TimeOfDay.light_level,
			TimeOfDay.sun_angle,
		])


# ---------------------------------------------------------------------------
# Angler events
# ---------------------------------------------------------------------------

func _on_angler_standing_still() -> void:
	if OS.is_debug_build():
		print("Angler standing still | x=%.0f y=%.0f | wading=%s depth=%.2f | vibration=%.0fpx" % [
			angler.position.x,
			angler.position.y,
			angler.is_wading,
			angler.wading_depth,
			angler.vibration_radius,
		])


# ---------------------------------------------------------------------------
# Hatch system
# ---------------------------------------------------------------------------

func _on_hatch_state_changed(state: int) -> void:
	_spawn_insects(state)


func _spawn_insects(state: int) -> void:
	for child in insect_layer.get_children():
		child.queue_free()

	var profiles: Array = HatchManager.active_profiles
	if profiles.is_empty():
		return

	var vp_w := get_viewport_rect().size.x
	const INSECTS_PER_PROFILE := 18

	for p in profiles:
		var pdict: Dictionary     = p
		var color:     Color      = pdict["color"]
		var movement:  String     = pdict["movement"]
		var abundance: float      = pdict["abundance"]
		var depth_layer: String   = pdict["depth_layer"]

		var y_min: float
		var y_max: float
		match depth_layer:
			"surface": y_min = 98.0;  y_max = 128.0
			"mid":     y_min = 148.0; y_max = 196.0
			_:         y_min = 210.0; y_max = 248.0

		var n := int(INSECTS_PER_PROFILE * abundance)
		for _i in range(n):
			var ip   := InsectParticle.new()
			var sx   := randf_range(-32.0, vp_w + 32.0)
			var sy   := randf_range(y_min, y_max)
			var vx   := randf_range(-18.0, -6.0)
			var vy   := randf_range(-1.0, 1.0)
			ip.setup(color, movement, Vector2(sx, sy),
					 Vector2(vx, vy), -32.0, vp_w + 32.0)
			insect_layer.add_child(ip)


# ---------------------------------------------------------------------------
# Net sampler
# ---------------------------------------------------------------------------

func _on_sample_complete(results: Array) -> void:
	sample_panel.show_results(results, GameManager.difficulty.show_sample_abundance_bars)


# ---------------------------------------------------------------------------
# Casting events
# ---------------------------------------------------------------------------

func _on_cast_result(quality: int, target_x: float, target_y: float) -> void:
	if OS.is_debug_build():
		var names := ["TIGHT", "SLOPPY", "BAD"]
		print("RiverWorld: cast %s → target x=%.0f" % [names[quality], target_x])
	var target_pos := Vector2(target_x, target_y)
	for fish in _fish_list:
		var f: FishAI = fish
		f.on_fly_presented(fly_selector.fly_name(), fly_selector.fly_stage(),
						   quality, target_pos)


# ---------------------------------------------------------------------------
# Hookset / catch events
# ---------------------------------------------------------------------------

func _on_catch_confirmed(fish: FishAI) -> void:
	_catch_log.record_catch(fish, fly_selector.fly_name(), fly_selector.fly_stage())
	logbook_panel.queue_redraw()
	_fish_list.erase(fish)
	fish.queue_free()
	hookset_controller.reset()
	drift.on_drift_ended()
	casting.state = CastingController.State.IDLE
	if OS.is_debug_build():
		print("RiverWorld: catch confirmed! Logbook: %d entries. Press L to view." \
			% _catch_log.catches.size())


func _on_hard_spook(fish: FishAI) -> void:
	fish.receive_hard_spook()


func _on_miss_late(fish: FishAI) -> void:
	fish.receive_miss_late()
