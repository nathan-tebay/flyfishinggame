extends Node2D


@onready var camera:       RiverCamera       = $Camera2D
@onready var tilemap:      RiverRenderer     = $TileMap
@onready var sky_strip:    ColorRect         = $SkyLayer/SkyStrip
@onready var angler:       Angler            = $Angler
@onready var casting:      CastingController = $CastingController
@onready var drift:        DriftController   = $DriftController
@onready var rod_arc_hud:  RodArcHUD         = $HUD/RodArcHUD
@onready var fly_selector: FlySelector       = $HUD/FlySelector

var river_data: RiverData
var _show_debug := false


func _ready() -> void:
	if GameManager.session_id < 0:
		GameManager.new_session(12345, 6.0, DifficultyConfig.Tier.STANDARD)

	_generate_river()

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
# Casting events
# ---------------------------------------------------------------------------

func _on_cast_result(quality: int, target_x: float, _target_y: float) -> void:
	var names := ["TIGHT", "SLOPPY", "BAD"]
	print("RiverWorld: cast %s → target x=%.0f" % [names[quality], target_x])
