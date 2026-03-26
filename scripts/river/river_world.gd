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

var river_data: RiverData
var catch_log:  CatchLog = null
var _fish_list: Array = []
var _show_debug := false


func _ready() -> void:
	if GameManager.session_id < 0:
		GameManager.new_session(12345, 6.0, DifficultyConfig.Tier.STANDARD)

	_generate_river()
	_spawn_fish()

	# Angler + camera
	angler.river_data    = river_data
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
	catch_log = CatchLog.new()
	logbook_panel.catch_log = catch_log

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

	print("RiverWorld ready | seed=%d | top holds=%d | structures=%d" % [
		river_data.seed,
		river_data.top_holds.size(),
		river_data.structures.size(),
	])


func _process(_delta: float) -> void:
	camera.set_anchor(angler.global_position.x)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.physical_keycode == KEY_COMMA:
			_show_debug = not _show_debug
			if _show_debug:
				tilemap.show_hold_debug(river_data)
			else:
				tilemap.hide_hold_debug()


# ---------------------------------------------------------------------------
# River generation
# ---------------------------------------------------------------------------

func _generate_river() -> void:
	var generator := RiverGenerator.new()
	river_data    = generator.generate(GameManager.session_seed, GameManager.difficulty)
	tilemap.render(river_data)


# ---------------------------------------------------------------------------
# Fish spawning
# ---------------------------------------------------------------------------

const MIN_FISH_DIST := 48.0   # minimum world-space distance between fish

func _spawn_fish() -> void:
	var fish_scene := load("res://scenes/Fish.tscn") as PackedScene
	var count      := 0
	var placed: Array = []

	for hold in river_data.top_holds:
		if count >= GameManager.difficulty.fish_per_section:
			break

		var hx: int = hold["x"]
		var hy: int = hold["y"]
		var wp := Vector2(
			float(hx) * RiverConstants.TILE_SIZE + RiverConstants.TILE_SIZE * 0.5,
			float(hy) * RiverConstants.TILE_SIZE + RiverConstants.TILE_SIZE * 0.5
		)

		# Skip if too close to an already-placed fish
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
		rng.seed = hash(river_data.seed + count * 997)

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

		fish.variant_seed = hash(river_data.seed + count * 7919)
		fish.hold_pos     = wp
		fish.angler       = angler
		fish.river_data   = river_data

		fish.take_fly.connect(hookset_controller.on_fish_take.bind(fish))
		add_child(fish)
		placed.append(wp)
		_fish_list.append(fish)
		count += 1

	print("RiverWorld: spawned %d fish" % count)


# ---------------------------------------------------------------------------
# Sky strip
# ---------------------------------------------------------------------------

func _update_sky() -> void:
	var idx := int(TimeOfDay.current_period)
	sky_strip.color = RiverConstants.SKY_COLORS[idx]


func _on_period_changed(_period: int) -> void:
	_update_sky()
	print("Period: %s  light=%.2f  sun=%.1f°" % [
		TimeOfDay.period_name(),
		TimeOfDay.light_level,
		TimeOfDay.sun_angle,
	])


# ---------------------------------------------------------------------------
# Angler events
# ---------------------------------------------------------------------------

func _on_angler_standing_still() -> void:
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
	# Clear previous insect particles
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
			_:         y_min = 210.0; y_max = 248.0  # bottom

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

# ---------------------------------------------------------------------------
# Hookset / catch events
# ---------------------------------------------------------------------------

func _on_catch_confirmed(fish: FishAI) -> void:
	catch_log.record_catch(fish, fly_selector.fly_name(), fly_selector.fly_stage())
	logbook_panel.queue_redraw()
	_fish_list.erase(fish)
	fish.queue_free()
	# Reset casting state without re-triggering hookset signals
	hookset_controller.reset()
	drift.on_drift_ended()
	casting.state = CastingController.State.IDLE
	print("RiverWorld: catch confirmed! Logbook: %d entries. Press L to view." \
		% catch_log.catches.size())


func _on_hard_spook(fish: FishAI) -> void:
	fish.receive_hard_spook()


func _on_miss_late(fish: FishAI) -> void:
	fish.receive_miss_late()


func _on_cast_result(quality: int, target_x: float, target_y: float) -> void:
	var names := ["TIGHT", "SLOPPY", "BAD"]
	print("RiverWorld: cast %s → target x=%.0f" % [names[quality], target_x])
	var target_pos := Vector2(target_x, target_y)
	for fish in _fish_list:
		var f: FishAI = fish
		f.on_fly_presented(fly_selector.fly_name(), fly_selector.fly_stage(),
						   quality, target_pos)
