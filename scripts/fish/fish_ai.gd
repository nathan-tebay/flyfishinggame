class_name FishAI
extends Node2D

# Fish spook state machine. All radius checks route through SpookCalculator.
# FEEDING → ALERT → SPOOKED → RELOCATING → HOLDING → FEEDING

enum State { FEEDING, ALERT, SPOOKED, RELOCATING, HOLDING }
enum Species { BROWN_TROUT, RAINBOW_TROUT, WHITEFISH }

const SPECIES_NAMES: Array = ["Brown Trout", "Rainbow Trout", "Mtn Whitefish"]

# Alert zone: angler within ALERT_MULT × spook_radius → ALERT (not yet SPOOKED)
const ALERT_MULT := 1.5

# Cooldown / settle times indexed by SpookCalculator.FishSize (SMALL=0 MED=1 LARGE=2)
const ALERT_COOLDOWNS: Array = [10.0, 15.0, 30.0]
const SETTLE_TIMES: Array    = [8.0,  15.0, 25.0]

# Intrusion memory lockdown thresholds. -1 = never locks down (SMALL).
const LOCKDOWN_THRESH: Array = [-1, 5, 3]

const FEEDING_SPEED := 22.0   # px/s moving toward feeding edge / hold
const FLEE_SPEED    := 88.0   # px/s when relocating after spook

# Radii for fly presentation checks
const FLY_STRIKE_RADIUS := 96.0    # px — fly within reach of fish
const BAD_CAST_RADIUS   := 160.0   # px — line-slap disturbance range

# --- Signals ---
signal take_fly   # fish decided to take; Phase 7 HooksetController connects here

# --- Public: set by RiverWorld before add_child ---
var species: int = Species.BROWN_TROUT
var size_class: int = SpookCalculator.FishSize.MEDIUM
var variant_seed: int = 0
var hold_pos: Vector2 = Vector2.ZERO
# Exposure factor from RiverData (via hold dict): 0.0 = sheltered pool belly, 1.0 = exposed tailout/riffle.
# Passed to SpookCalculator — exposed fish have a larger effective spook radius.
var exposure_factor: float = 0.5

# World x at which this fish's section starts (0 for section 0).
# Used to convert world position to local tile coordinates.
var section_start_px: float = 0.0

var angler: Angler = null
var river_data: RiverData = null

# --- Observable state (read by RiverWorld debug etc.) ---
var state: State = State.FEEDING
var intrusion_memory: float = 0.0

# --- Internal ---
var _state_timer: float = 0.0
var _locked_down: bool = false
var _feeding_pos: Vector2 = Vector2.ZERO
var _relocation_pos: Vector2 = Vector2.ZERO
var _target_pos: Vector2 = Vector2.ZERO

var _renderer: FishRenderer = null
var _vision_cone: FishVisionCone = null


func _ready() -> void:
	position    = hold_pos
	_feeding_pos = _find_feeding_edge()
	_target_pos  = hold_pos

	_renderer    = get_node("FishRenderer") as FishRenderer
	_vision_cone = get_node("FishVisionCone") as FishVisionCone

	if _renderer:
		_renderer.initialize(species, size_class, variant_seed, river_data, section_start_px)
	if _vision_cone:
		_vision_cone.setup(GameManager.difficulty)

	TimeOfDay.dawn.connect(_on_dawn)
	TimeOfDay.period_changed.connect(_on_period_changed)


func _process(delta: float) -> void:
	_state_timer += delta

	match state:
		State.FEEDING, State.ALERT:
			_check_angler(delta)
		State.SPOOKED:
			# SPOOKED is momentary: record intrusion, compute flee target, enter RELOCATING
			intrusion_memory += 1.0
			_check_lockdown()
			_compute_relocation()
			_set_state(State.RELOCATING)
		State.RELOCATING:
			if position.distance_to(_target_pos) < 10.0:
				_set_state(State.HOLDING)
		State.HOLDING:
			if _state_timer >= _settle_time():
				if not _locked_down:
					_set_state(State.FEEDING)

	_move_toward_target(delta)

	if _renderer:
		_renderer.update(state, intrusion_memory)


func _set_state(new_state: State) -> void:
	if state == new_state:
		return
	# Log spook-related transitions (key testable behaviour)
	if OS.is_debug_build() and (new_state == State.ALERT or new_state == State.SPOOKED or \
			new_state == State.RELOCATING or state == State.ALERT or state == State.SPOOKED):
		var sz_name: String = SpookCalculator.FishSize.keys()[size_class]
		print("FishAI [%s %s]: %s → %s  mem=%.0f" % [
			SPECIES_NAMES[species] as String, sz_name,
			State.keys()[state] as String,
			State.keys()[new_state] as String,
			intrusion_memory
		])
	state        = new_state
	_state_timer = 0.0
	match new_state:
		State.FEEDING:
			_target_pos = _current_feeding_target()
		State.RELOCATING:
			_target_pos = _relocation_pos
		State.HOLDING:
			_target_pos = position  # stop moving


# ---------------------------------------------------------------------------
# Angler proximity — called every frame in FEEDING / ALERT
# ---------------------------------------------------------------------------

func _check_angler(delta: float) -> void:
	if angler == null:
		return
	var spook_r := SpookCalculator.calculate(
		GameManager.difficulty,
		size_class,
		_cover_value(),
		angler.position,
		position,
		angler.is_wading,
		1.0 if angler.is_moving else 0.0,
		exposure_factor
	)
	var dist := angler.position.distance_to(position)

	if dist <= spook_r:
		_set_state(State.SPOOKED)
		return

	if dist <= spook_r * ALERT_MULT:
		_state_timer = 0.0   # reset cooldown while angler is nearby
		if state == State.FEEDING:
			_set_state(State.ALERT)
	else:
		# Angler moved away — count down from when they left
		if state == State.ALERT and _state_timer >= _alert_cooldown():
			_set_state(State.FEEDING)


# ---------------------------------------------------------------------------
# Movement
# ---------------------------------------------------------------------------

func _move_toward_target(delta: float) -> void:
	var speed := 0.0
	match state:
		State.FEEDING:  speed = FEEDING_SPEED
		State.RELOCATING: speed = FLEE_SPEED
	if speed > 0.0 and position.distance_to(_target_pos) > 2.0:
		position = position.move_toward(_target_pos, speed * delta)


func _current_feeding_target() -> Vector2:
	return _feeding_pos if TimeOfDay.is_feeding_window() else hold_pos


# ---------------------------------------------------------------------------
# Relocation — pick a hold far from angler, deeper water preferred
# ---------------------------------------------------------------------------

func _compute_relocation() -> void:
	if river_data == null:
		_relocation_pos = hold_pos
		return

	var best_pos   := hold_pos
	var best_score := -1.0

	for hold in river_data.top_holds:
		var hx: int = hold["x"]
		var hy: int = hold["y"]
		var hp := Vector2(
			_tile_to_world_x(hx),
			float(hy) * RiverConstants.TILE_SIZE + RiverConstants.TILE_SIZE * 0.5
		)
		if position.distance_to(hp) < 60.0:
			continue   # don't stay nearby

		var dist_angler := angler.position.distance_to(hp) if angler else 0.0
		var depth: float = river_data.depth_profile[hx] as float
		var score := dist_angler * 0.55 + depth * 160.0

		if score > best_score:
			best_score = score
			best_pos   = hp

	_relocation_pos = best_pos


# ---------------------------------------------------------------------------
# Feeding edge — find a faster tile nearby (seam)
# ---------------------------------------------------------------------------

func _find_feeding_edge() -> Vector2:
	if river_data == null:
		return hold_pos

	var tx := _local_tile_x(hold_pos.x)
	var ty := _local_tile_y(hold_pos.y)

	var hold_curr: float = river_data.current_map[tx][ty] as float
	var best_pos := hold_pos
	var best_curr := hold_curr

	for dx in range(-7, 8):
		for dy in range(-3, 4):
			var nx := tx + dx
			var ny := ty + dy
			if nx < 0 or nx >= river_data.width or ny < 0 or ny >= river_data.height:
				continue
			var tile: int = river_data.tile_map[nx][ny]
			if tile == RiverConstants.TILE_AIR or tile == RiverConstants.TILE_BANK:
				continue
			var curr: float = river_data.current_map[nx][ny] as float
			if curr > best_curr and curr > hold_curr + 0.15:
				best_curr = curr
				best_pos  = Vector2(
					_tile_to_world_x(nx),
					float(ny) * RiverConstants.TILE_SIZE + RiverConstants.TILE_SIZE * 0.5
				)
	return best_pos


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Convert world x to local tile column, clamped to river_data bounds.
func _local_tile_x(world_x: float) -> int:
	return clampi(int((world_x - section_start_px) / RiverConstants.TILE_SIZE),
		0, river_data.width - 1)


# Convert world y to tile row, clamped to river_data bounds.
func _local_tile_y(world_y: float) -> int:
	return clampi(int(world_y / RiverConstants.TILE_SIZE), 0, river_data.height - 1)


# Convert local tile column back to world x (tile centre).
func _tile_to_world_x(tx: int) -> float:
	return section_start_px + float(tx) * RiverConstants.TILE_SIZE + RiverConstants.TILE_SIZE * 0.5


func _cover_value() -> float:
	if river_data == null:
		return 0.0
	var tx := _local_tile_x(position.x)
	var ty := _local_tile_y(position.y)
	var tile: int = river_data.tile_map[tx][ty]
	return RiverConstants.STRUCTURE_COVER.get(tile, 0.0) as float


func _alert_cooldown() -> float:
	return ALERT_COOLDOWNS[size_class] as float


func _settle_time() -> float:
	return SETTLE_TIMES[size_class] as float


func _check_lockdown() -> void:
	var threshold: int = LOCKDOWN_THRESH[size_class] as int
	if threshold < 0:
		return
	if intrusion_memory >= float(threshold) and not _locked_down:
		_locked_down = true
		if OS.is_debug_build():
			var sz_name: String = SpookCalculator.FishSize.keys()[size_class]
			print("FishAI [%s %s]: LOCKED DOWN (mem=%.0f)" % [
				SPECIES_NAMES[species] as String, sz_name, intrusion_memory
			])


func _on_dawn() -> void:
	if _locked_down:
		_locked_down = false
		intrusion_memory = 0.0
		if OS.is_debug_build():
			var sz_name: String = SpookCalculator.FishSize.keys()[size_class]
			print("FishAI [%s %s]: dawn — lockdown cleared" % [SPECIES_NAMES[species] as String, sz_name])
	else:
		intrusion_memory = 0.0
	if state == State.HOLDING:
		_set_state(State.FEEDING)


func _on_period_changed(_period: int) -> void:
	if state == State.FEEDING:
		_target_pos = _current_feeding_target()


# ---------------------------------------------------------------------------
# Fly presentation — called by RiverWorld when a cast_result fires
# ---------------------------------------------------------------------------

func receive_hard_spook() -> void:
	# Called by HooksetController on too-early hookset; bypasses proximity check.
	if OS.is_debug_build():
		var sz_name: String = SpookCalculator.FishSize.keys()[size_class]
		print("FishAI [%s %s]: HARD SPOOK from early hookset" % [
			SPECIES_NAMES[species] as String, sz_name,
		])
	intrusion_memory += 1.0
	_check_lockdown()
	_compute_relocation()
	_set_state(State.RELOCATING)


func receive_miss_late() -> void:
	# Called by HooksetController when strike window expires; fish spits fly.
	if OS.is_debug_build():
		var sz_name: String = SpookCalculator.FishSize.keys()[size_class]
		print("FishAI [%s %s]: missed hookset — still feeding" % [
			SPECIES_NAMES[species] as String, sz_name,
		])
	if state == State.FEEDING or state == State.ALERT:
		_set_state(State.FEEDING)


func on_fly_presented(fly_name: String, fly_stage: String,
					  cast_quality: int, target_pos: Vector2) -> void:
	var dist := position.distance_to(target_pos)

	# BAD cast — line-slap disturbance regardless of fly
	if cast_quality == 2:
		if dist <= BAD_CAST_RADIUS:
			if randf() < GameManager.difficulty.bad_cast_spook_chance:
				_set_state(State.SPOOKED)
			elif state == State.FEEDING:
				_set_state(State.ALERT)
		return   # bad cast never presents a fly

	# Only feeding fish respond to fly presentations
	if state != State.FEEDING:
		return

	if dist > FLY_STRIKE_RADIUS:
		return

	var result: Dictionary = FlyMatcher.evaluate(fly_name, fly_stage, GameManager.difficulty)
	var take_prob:       float = result["take_probability"]
	var intrusion_delta: float = result["intrusion_delta"]

	# Sloppy cast reduces take probability
	if cast_quality == 1:
		take_prob *= 0.60

	if intrusion_delta > 0.0:
		intrusion_memory += intrusion_delta
		_check_lockdown()
		if OS.is_debug_build():
			var sz_name: String = SpookCalculator.FishSize.keys()[size_class]
			var kind := "stage" if intrusion_delta < 1.0 else "species"
			print("FishAI [%s %s]: fly rejected — wrong %s (Δ=%.1f mem=%.1f)" % [
				SPECIES_NAMES[species] as String, sz_name,
				kind, intrusion_delta, intrusion_memory,
			])
		_set_state(State.ALERT)
		return

	if randf() < take_prob:
		if OS.is_debug_build():
			var sz_name: String = SpookCalculator.FishSize.keys()[size_class]
			print("FishAI [%s %s]: TAKING fly '%s' (prob=%.0f%%)" % [
				SPECIES_NAMES[species] as String, sz_name,
				fly_name, take_prob * 100.0,
			])
		take_fly.emit()
