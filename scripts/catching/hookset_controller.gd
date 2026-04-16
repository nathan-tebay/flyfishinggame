class_name HooksetController
extends Node

# Hookset state machine.
# IDLE → WATCHING (drift active) → PRE_TAKE (fish rising, 0.3s) → STRIKE_OPEN → IDLE
#
# Wired by RiverWorld:
#   casting.drift_started  → on_drift_started()
#   casting.drift_ended    → on_drift_ended()
#   fish.take_fly.bind(f)  → on_fish_take(f)
#   catch_confirmed        → RiverWorld._on_catch_confirmed()
#   hard_spook             → RiverWorld._on_hard_spook()
#   miss_late              → RiverWorld._on_miss_late()

enum HookState { IDLE, WATCHING, PRE_TAKE, STRIKE_OPEN }

signal catch_confirmed(fish: FishAI)
signal hard_spook(fish: FishAI)
signal miss_late(fish: FishAI)

const PRE_TAKE_DUR      := 0.30    # rise animation window; hookset here = too early
const INDICATOR_DRIFT_X := -14.0   # px/s the indicator drifts downstream

var casting:      CastingController = null
var fly_selector: FlySelector       = null

var _state:    HookState        = HookState.IDLE
var _timer:    float            = 0.0
var _is_nymph: bool             = false

var _taking_fish: FishAI        = null
var _indicator:   StrikeIndicator = null


func on_drift_started() -> void:
	if _state != HookState.IDLE:
		return
	_is_nymph = fly_selector != null and not fly_selector.is_dry_fly()
	_state    = HookState.WATCHING
	_spawn_indicator()
	if OS.is_debug_build():
		print("HooksetController: watching | %s" % ("nymph indicator" if _is_nymph else "dry fly"))


func on_drift_ended() -> void:
	if _state == HookState.STRIKE_OPEN or _state == HookState.PRE_TAKE:
		if _taking_fish:
			miss_late.emit(_taking_fish)
	_reset()


func on_fish_take(fish: FishAI) -> void:
	if _state != HookState.WATCHING:
		return
	_taking_fish = fish
	_state       = HookState.PRE_TAKE
	_timer       = PRE_TAKE_DUR
	if _indicator:
		_indicator.visible = true
		_indicator.start_take(_is_nymph)
	if OS.is_debug_build():
		var cue := "DRY — RISE! SPLASH!" if not _is_nymph else "NYMPH — indicator dipping!"
		print("HooksetController: %s  (%.2fs pre-take)" % [cue, PRE_TAKE_DUR])


func reset() -> void:
	_reset()


func _process(delta: float) -> void:
	match _state:
		HookState.WATCHING:
			_drift_indicator(delta)
			if Input.is_action_just_pressed("hookset"):
				_handle_early_hookset()

		HookState.PRE_TAKE:
			_drift_indicator(delta)
			_timer -= delta
			if Input.is_action_just_pressed("hookset"):
				if OS.is_debug_build():
					print("HooksetController: TOO EARLY — hard spook!")
				if _taking_fish:
					hard_spook.emit(_taking_fish)
				_reset()
			elif _timer <= 0.0:
				_open_strike_window()

		HookState.STRIKE_OPEN:
			_timer -= delta
			if Input.is_action_just_pressed("hookset"):
				if OS.is_debug_build():
					print("HooksetController: HOOKSET — catch confirmed!")
				if _taking_fish:
					catch_confirmed.emit(_taking_fish)
				_reset()
			elif _timer <= 0.0:
				if OS.is_debug_build():
					print("HooksetController: too late — fish spit the fly, returns to feeding")
				if _taking_fish:
					miss_late.emit(_taking_fish)
				_reset()


func _drift_indicator(delta: float) -> void:
	if _indicator:
		_indicator.position.x += INDICATOR_DRIFT_X * delta


func _handle_early_hookset() -> void:
	if OS.is_debug_build():
		print("HooksetController: hookset while drifting — no fish on the line")


func _open_strike_window() -> void:
	_state = HookState.STRIKE_OPEN
	_timer = GameManager.difficulty.hookset_window_duration
	if OS.is_debug_build():
		print("HooksetController: STRIKE WINDOW OPEN (%.1fs) — press Space/A!" % _timer)


func _spawn_indicator() -> void:
	if _indicator:
		_indicator.queue_free()
		_indicator = null
	if casting == null:
		return

	var fly_pos := casting.get_fly_pos()
	var ind     := StrikeIndicator.new()
	ind.position = Vector2(fly_pos.x, 108.0)
	ind.visible  = true
	if _is_nymph:
		pass   # nymph ball draws by default
	else:
		ind.start_dry_float()   # subtle hackle dot until take
	_indicator = ind
	get_parent().add_child(ind)


func _reset() -> void:
	_state       = HookState.IDLE
	_taking_fish = null
	_timer       = 0.0
	if _indicator:
		_indicator.queue_free()
		_indicator = null
