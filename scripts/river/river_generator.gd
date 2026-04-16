class_name RiverGenerator
extends RefCounted

# Generates a deterministic RiverData from a seed + DifficultyConfig.
# Same seed + same config always produces the same river.



func generate(seed: int, config: DifficultyConfig) -> RiverData:
	var data := RiverData.new()
	data.seed  = seed
	data.width  = RiverConstants.SECTION_W_TILES
	data.height = RiverConstants.RIVER_H_TILES

	_init_arrays(data)
	_generate_depth_profile(data)
	_apply_pool_riffle_template(data)  # bake pool/riffle cycles on top of noise
	_inject_ford_sections(data)        # carve periodic shallow crossings (overrides template)
	_classify_habitat(data)            # label columns: pool/run/riffle/ford (reads depth_profile)
	_build_tile_map(data)
	_place_islands(data)
	_generate_current_map(data)
	_place_structures(data, config)
	_apply_structure_tiles(data)
	_apply_eddy_currents(data)
	_classify_pocket_water(data)    # refine pocket-water labels from structure positions
	_calculate_hold_scores(data)
	_find_top_holds(data, config.fish_per_section)

	return data


# ---------------------------------------------------------------------------
# Array initialisation
# ---------------------------------------------------------------------------

func _init_arrays(data: RiverData) -> void:
	var w := data.width
	var h := data.height

	data.depth_profile.resize(w)
	data.depth_profile.fill(0.5)

	data.top_bank_profile.resize(w)
	data.top_bank_profile.fill(RiverConstants.BANK_H_TILES)

	data.bottom_bank_profile.resize(w)
	data.bottom_bank_profile.fill(RiverConstants.BANK_H_TILES + RiverConstants.MIN_DEPTH_TILES + 1)

	data.habitat_type.resize(w)
	data.habitat_type.fill(RiverConstants.HABITAT_RUN)

	data.exposure_factor.resize(w)
	data.exposure_factor.fill(0.5)

	data.current_map.resize(w)
	data.tile_map.resize(w)
	data.hold_scores.resize(w)

	for x in w:
		data.current_map[x] = []
		data.current_map[x].resize(h)
		data.current_map[x].fill(0.5)

		data.tile_map[x] = []
		data.tile_map[x].resize(h)
		data.tile_map[x].fill(RiverConstants.TILE_AIR)

		data.hold_scores[x] = []
		data.hold_scores[x].resize(h)
		data.hold_scores[x].fill(0.0)


# ---------------------------------------------------------------------------
# Step 1 — Depth profile  (1-D simplex noise along river length)
# ---------------------------------------------------------------------------

func _generate_depth_profile(data: RiverData) -> void:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed      = data.seed
	noise.frequency = 0.003

	for x in data.width:
		var raw        := noise.get_noise_1d(float(x))
		var normalized := (raw + 1.0) * 0.5
		# Reduced amplitude: noise contributes fine texture, pool-riffle template drives shape.
		# Centres around 0.40 (run depth) with ±0.175 variation.
		data.depth_profile[x] = clampf(normalized * 0.35 + 0.40, 0.0, 1.0)


# ---------------------------------------------------------------------------
# Step 1b — Pool-riffle-run template
# ---------------------------------------------------------------------------

# Bakes intentional pool-riffle cycles into the depth profile on top of the noise
# baseline. Pools are placed every 100–140 tiles (5–7 channel widths for a ~20-tile
# wide river), matching real river self-organisation spacing.
#
# Each pool has three zones written via cosine interpolation:
#   HEAD  — abrupt depth increase (plunge / food funnel entry), 15 tiles
#   BELLY — deep slow centre, 30 tiles
#   TAIL  — gradual shallowing toward riffle (tailout), 20 tiles
# Between pools a riffle (15–25 tiles) is injected at the midpoint.
#
# Ford sections (injected next in the pipeline) override template values
# wherever depth_profile[x] < 0.12 after ford injection, so fords are preserved.
func _apply_pool_riffle_template(data: RiverData) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(data.seed + 55555)   # distinct salt from ford RNG (22222)

	# Lengths for each pool zone
	const HEAD_LEN   := 15   # steep entry (pool head / plunge)
	const BELLY_LEN  := 30   # deep slow centre (pool belly)
	const TAIL_LEN   := 20   # gradual shallowing (tailout)
	const POOL_LEN   := HEAD_LEN + BELLY_LEN + TAIL_LEN  # 65 tiles total

	# Place pool centres spaced 100–140 tiles apart
	var pool_centres: Array = []
	var x := rng.randi_range(80, 140)
	while x < data.width - 80:
		pool_centres.append(x)
		x += rng.randi_range(100, 140)

	# Write each pool's shape into the depth profile using cosine interpolation.
	# depth_profile: 0 = deep/slow (pool), 1 = shallow/fast (riffle).
	for pc: int in pool_centres:
		var belly_depth: float = rng.randf_range(0.06, 0.14)   # deep pool target
		var run_depth:   float = rng.randf_range(0.35, 0.50)   # adjacent run depth

		# Pool head — cosine ramp from run depth down to belly depth (steep).
		# Starts HEAD_LEN tiles upstream of belly start.
		var head_start := pc - HEAD_LEN - BELLY_LEN / 2
		for i in HEAD_LEN:
			var xi := head_start + i
			if xi < 0 or xi >= data.width:
				continue
			var t := float(i) / float(HEAD_LEN)  # 0 = run, 1 = belly
			var taper := (1.0 - cos(t * PI)) * 0.5
			data.depth_profile[xi] = lerpf(run_depth, belly_depth, taper)

		# Pool belly — flat deep centre.
		var belly_start := head_start + HEAD_LEN
		for i in BELLY_LEN:
			var xi := belly_start + i
			if xi < 0 or xi >= data.width:
				continue
			# Add small noise texture so the belly isn't perfectly uniform.
			data.depth_profile[xi] = belly_depth + rng.randf_range(-0.02, 0.02)

		# Pool tail (tailout) — cosine ramp from belly back up to riffle depth.
		# Longer than the head for a gradual tailout.
		var tail_start := belly_start + BELLY_LEN
		var riffle_depth: float = rng.randf_range(0.75, 0.92)
		for i in TAIL_LEN:
			var xi := tail_start + i
			if xi < 0 or xi >= data.width:
				continue
			var t := float(i) / float(TAIL_LEN)  # 0 = belly, 1 = riffle
			var taper := (1.0 - cos(t * PI)) * 0.5
			data.depth_profile[xi] = lerpf(belly_depth, riffle_depth, taper)

		# Riffle — inject a short shallow fast section after the tailout.
		# Positioned at the midpoint between this pool's tail and the next pool head.
		var riffle_len  := rng.randi_range(15, 25)
		var riffle_start := tail_start + TAIL_LEN + rng.randi_range(5, 20)
		for i in riffle_len:
			var xi := riffle_start + i
			if xi < 0 or xi >= data.width:
				continue
			# Cosine taper on each end (4 tiles) so transition is smooth.
			var edge_fade := 1.0
			if i < 4:
				edge_fade = (1.0 - cos(float(i) / 4.0 * PI)) * 0.5
			elif i >= riffle_len - 4:
				edge_fade = (1.0 - cos(float(riffle_len - i) / 4.0 * PI)) * 0.5
			var rd: float = rng.randf_range(0.76, 0.90)
			# Blend: full riffle at centre, tapers to existing noise value at edges.
			data.depth_profile[xi] = lerpf(
				data.depth_profile[xi] as float, rd, edge_fade)


func _inject_ford_sections(data: RiverData) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(data.seed + 22222)
	const FORD_SPACING := 320   # average tiles between ford centres (reduced for more crossings)
	const FORD_WIDTH   := 60    # tiles across the ford transition (wider = easier to find)
	const FORD_DEPTH   := 0.06  # depth_val at ford centre (very shallow — no TILE_DEEP guaranteed)

	var ford_xs: Array = []
	var x := rng.randi_range(60, FORD_SPACING)
	while x < data.width - 60:
		ford_xs.append(x)
		x += FORD_SPACING + rng.randi_range(-60, 60)

	# Guarantee at least one ford per section, near the midpoint if none were placed.
	if ford_xs.is_empty():
		ford_xs.append(data.width / 2)

	for fx_centre: int in ford_xs:
		var hw := FORD_WIDTH / 2
		for dx in range(-hw, hw + 1):
			var fx := fx_centre + dx
			if fx < 0 or fx >= data.width:
				continue
			# Smooth cosine taper from normal depth at edges to FORD_DEPTH at centre
			var t := float(abs(dx)) / float(hw)  # 0 = centre, 1 = edge
			var taper := (1.0 - cos(t * PI)) * 0.5   # smooth 0→1
			var current: float = data.depth_profile[fx]
			data.depth_profile[fx] = lerpf(FORD_DEPTH, current, taper)


# ---------------------------------------------------------------------------
# Step 2 — Tile map: U-shape cross-section (deep channel, shallow banks)
# ---------------------------------------------------------------------------

func _build_tile_map(data: RiverData) -> void:
	var min_depth  := RiverConstants.MIN_DEPTH_TILES       # 4
	var max_depth  := RiverConstants.MAX_DEPTH_TILES       # 22

	# Meander noise — single source drives both banks so they curve together.
	# Controls the river centerline Y offset: when it shifts down (positive),
	# both banks shift down together, creating a coherent meander.
	var meander_noise := FastNoiseLite.new()
	meander_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	meander_noise.seed       = data.seed + 77777
	meander_noise.frequency  = 0.0018   # ~555-tile wavelength — broad river meander curves

	# Width noise — independent, higher frequency. Varies river width
	# (narrows at riffles, widens at pools) without breaking meander correlation.
	var width_noise := FastNoiseLite.new()
	width_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	width_noise.seed       = data.seed + 33333
	width_noise.frequency  = 0.004

	# 2D noise for lateral variation in tier boundaries
	var tier_noise := FastNoiseLite.new()
	tier_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	tier_noise.seed       = data.seed + 54321
	tier_noise.frequency  = 0.018

	for x in data.width:
		var depth_val: float = data.depth_profile[x]

		# Meander: shifts river center. Range -1..1 → 0..4 tile offset for near bank.
		var mn: float = meander_noise.get_noise_1d(float(x))

		# Curvature = meander derivative. Positive = river curving away from player
		# (near bank outside of curve → erosion), negative = toward player (near bank inside).
		var mn_next: float = meander_noise.get_noise_1d(float(x) + 2.0)
		var curvature: float = clampf((mn_next - mn) * 600.0, -1.0, 1.0)

		# Width variation: small modulation of total water column
		var wn: float = width_noise.get_noise_1d(float(x))

		# Near bank: meander offset + curvature bias.
		# Outside curve (curvature > 0) → thinner bank (eroded).
		# Inside curve (curvature < 0) → thicker bank (deposited).
		var near_bank_raw: float = float(RiverConstants.BANK_H_TILES) + (mn + 1.0) * 2.0 \
				- curvature * 0.8
		var top_bank_h: int = clampi(int(near_bank_raw),
				RiverConstants.BANK_H_TILES, RiverConstants.BANK_H_TILES + 4)
		data.top_bank_profile[x] = top_bank_h

		# Far bank thickness: curvature-responsive (inverse of near bank).
		# Outside curve for far bank (curvature < 0) → thinner. Inside → thicker.
		var far_bank_raw: float = float(RiverConstants.BOTTOM_BANK_H_TILES) + 1.0 \
				+ curvature * 0.8 + wn * 0.5
		var bot_bank_h: int = clampi(int(round(far_bank_raw)),
				RiverConstants.BOTTOM_BANK_H_TILES, RiverConstants.BOTTOM_BANK_H_TILES + 2)

		# Actual water column height — leave 1 tile margin; far bank fills to screen bottom.
		var cap_depth := mini(max_depth, data.height - top_bank_h - 1)
		var water_cols := min_depth + int(depth_val * float(cap_depth - min_depth))
		var riverbed_row := top_bank_h + water_cols  # row index of riverbed tile
		data.bottom_bank_profile[x] = riverbed_row + 1  # first row of far bank

		for y in data.height:
			if y < top_bank_h:
				data.tile_map[x][y] = RiverConstants.TILE_BANK
			elif y <= riverbed_row:
				# U-shaped depth: deepest in the centre of the water column.
				# frac=0 at near bank edge, frac=1 at far bank edge — both edges
				# get the same shallow treatment so both banks look symmetric.
				var frac:     float = float(y - top_bank_h) / float(water_cols)
				var centre_d: float = absf(frac - 0.5) * 2.0   # 0 = centre, 1 = edge

				# Curvature-based bank-edge depth: outside curves erode deeper,
				# inside curves deposit shallow. Affects the first/last ~40% of
				# the water column.
				# curvature > 0 → near bank inside (shallow), far bank outside (deep).
				# curvature < 0 → near bank outside (deep), far bank inside (shallow).
				var near_prox: float = maxf(0.0, 1.0 - frac * 2.5)
				var far_prox:  float = maxf(0.0, 1.0 - (1.0 - frac) * 2.5)
				# Strong shift: at max curvature, bank edge goes from SURFACE to
				# MID_DEPTH (moderate depth) or DEEP (deep pools).
				centre_d += curvature * 0.85 * near_prox
				centre_d -= curvature * 0.85 * far_prox
				centre_d = clampf(centre_d, 0.0, 1.0)

				var tn:       float = tier_noise.get_noise_2d(float(x), float(y)) * 0.10
				# Thresholds shrink as depth_val drops → ford = all SURFACE
				var deep_thr: float = lerpf(-0.2, 0.38, depth_val)
				var mid_thr:  float = lerpf(0.25, 0.70, depth_val)
				if centre_d < (deep_thr + tn):
					data.tile_map[x][y] = RiverConstants.TILE_DEEP
				elif centre_d < (mid_thr + tn):
					data.tile_map[x][y] = RiverConstants.TILE_MID_DEPTH
				else:
					data.tile_map[x][y] = RiverConstants.TILE_SURFACE
			else:
				# Far bank fills all rows below the water column to the screen bottom
				data.tile_map[x][y] = RiverConstants.TILE_BANK


# ---------------------------------------------------------------------------
# Step 2b — Islands: mid-river exposed bank strips that split current into seams.
# Placed after _build_tile_map so bank profiles are known; before _generate_current_map
# so current correctly reads TILE_BANK (0.0) for island tiles.
# Shape: sine-tapered — 1-tile tips, up to 3 tiles wide in the middle.
# Renderer handles visuals via depth-field pipeline (TILE_BANK → depth rank 0.0).
# ---------------------------------------------------------------------------

func _place_islands(data: RiverData) -> void:
	const MAX_HALF_H := 1     # island up to 3 tiles tall (center ± MAX_HALF_H)
	const MIN_CLEAR  := 3     # min water tiles each side of island
	const MIN_WATER  := MAX_HALF_H * 2 + MIN_CLEAR * 2 + 1  # = 9

	var rng := RandomNumberGenerator.new()
	rng.seed = data.seed ^ 888888

	var x := rng.randi_range(60, 180)
	while x < data.width - 40:
		var island_len := rng.randi_range(10, 22)
		var x_end      := mini(x + island_len, data.width - 4)
		var span       := x_end - x
		if span < 5:
			x += island_len + rng.randi_range(120, 320)
			continue

		# Verify all columns have enough water and compute avg center
		var center_sum := 0
		var valid      := true
		for ix in range(x, x_end):
			var top_w: int = data.top_bank_profile[ix]
			var bot_w: int = data.bottom_bank_profile[ix] - 1
			if bot_w - top_w + 1 < MIN_WATER:
				valid = false
				break
			center_sum += (top_w + bot_w) / 2

		if valid:
			var center_y: int = center_sum / span + rng.randi_range(-1, 1)
			for ix in range(x, x_end):
				var frac   := float(ix - x) / float(span)
				var half_h := int(round(float(MAX_HALF_H) * sin(frac * PI)))
				for iy in range(center_y - half_h, center_y + half_h + 1):
					if iy < 0 or iy >= data.height:
						continue
					var t: int = data.tile_map[ix][iy]
					if t != RiverConstants.TILE_BANK and t != RiverConstants.TILE_AIR:
						data.tile_map[ix][iy] = RiverConstants.TILE_BANK

		x += island_len + rng.randi_range(120, 320)


# ---------------------------------------------------------------------------
# Step 3 — Current map (shallow = fast, deep = slow)
# ---------------------------------------------------------------------------

func _generate_current_map(data: RiverData) -> void:
	for x in data.width:
		var depth_val: float = data.depth_profile[x]
		# Narrower river (fewer water_cols) = faster current; wider/deeper = slower.
		# water_cols is linear in depth_val so depth_val directly encodes width fraction.
		var min_d := RiverConstants.MIN_DEPTH_TILES
		var max_d := RiverConstants.MAX_DEPTH_TILES
		var water_cols: int = min_d + int(depth_val * float(max_d - min_d))
		var width_frac: float = float(water_cols - min_d) / float(max_d - min_d)
		# Narrow/shallow (width_frac=0): 0.95 m/s; wide/deep (width_frac=1): 0.20 m/s
		var base_speed: float = lerpf(0.95, 0.20, width_frac)

		for y in data.height:
			match data.tile_map[x][y]:
				RiverConstants.TILE_BANK, RiverConstants.TILE_AIR:
					data.current_map[x][y] = 0.0
				RiverConstants.TILE_SURFACE:
					data.current_map[x][y] = base_speed
				RiverConstants.TILE_MID_DEPTH:
					data.current_map[x][y] = base_speed * 0.85
				RiverConstants.TILE_DEEP:
					data.current_map[x][y] = base_speed * 0.60
				_:
					data.current_map[x][y] = base_speed


# ---------------------------------------------------------------------------
# Step 4 — Structure placement
# ---------------------------------------------------------------------------

func _place_structures(data: RiverData, config: DifficultyConfig) -> void:
	var density := config.structure_density_multiplier

	# Target counts per structure type, scaled by density.
	# Increased base counts for richer habitat and more fish holding spots.
	# Undercut banks removed — replaced by curvature-based depth in _build_tile_map.
	# Outside curves naturally get deeper water against the bank (erosion);
	# inside curves get shallow edges (deposition).
	var counts := {
		RiverConstants.TILE_WEED_BED:      int(14 * density),
		RiverConstants.TILE_ROCK:          int(28 * density),
		RiverConstants.TILE_BOULDER:       int(8  * density),
		RiverConstants.TILE_GRAVEL_BAR:    int(8  * density),
		RiverConstants.TILE_LOG:           int(7  * density),
	}

	for tile_type: int in counts:
		var rng := RandomNumberGenerator.new()
		# Different salt per structure type ensures independent placement
		rng.seed = hash(data.seed + tile_type * 7919)

		var target: int   = counts[tile_type]
		var placed        := 0
		var attempts: int = target * 6

		for _i in attempts:
			if placed >= target:
				break

			var x := rng.randi_range(2, data.width - 14)
			var y := rng.randi_range(0, data.height - 1)

			if not _valid_placement(data, tile_type, x, y):
				continue

			var w := _structure_w(rng, tile_type)
			var h := _structure_h(rng, tile_type)

			data.structures.append({
				"type":  tile_type,
				"x":     x,
				"y":     y,
				"w":     w,
				"h":     h,
				"cover": RiverConstants.STRUCTURE_COVER.get(tile_type, 0.5),
				"hatch": RiverConstants.STRUCTURE_HATCH.get(tile_type, 0.5),
			})
			placed += 1


func _valid_placement(data: RiverData, tile_type: int, x: int, y: int) -> bool:
	var tile: int = data.tile_map[x][y]
	match tile_type:
		RiverConstants.TILE_WEED_BED:
			return tile == RiverConstants.TILE_SURFACE or tile == RiverConstants.TILE_MID_DEPTH
		RiverConstants.TILE_ROCK:
			return tile in [RiverConstants.TILE_SURFACE, RiverConstants.TILE_MID_DEPTH, RiverConstants.TILE_DEEP]
		RiverConstants.TILE_BOULDER:
			return tile == RiverConstants.TILE_MID_DEPTH or tile == RiverConstants.TILE_DEEP
		RiverConstants.TILE_GRAVEL_BAR:
			return tile == RiverConstants.TILE_SURFACE or \
				(tile == RiverConstants.TILE_MID_DEPTH and (data.depth_profile[x] as float) < 0.35)
		RiverConstants.TILE_LOG:
			# Logs fall into near-bank or far-bank water edge only
			if tile not in [RiverConstants.TILE_SURFACE, RiverConstants.TILE_MID_DEPTH]:
				return false
			var near_edge: int = data.top_bank_profile[x]
			var far_start: int = data.bottom_bank_profile[x]
			return y <= near_edge + 2 or y >= far_start - 3
	return false


func _structure_w(rng: RandomNumberGenerator, tile_type: int) -> int:
	match tile_type:
		RiverConstants.TILE_WEED_BED:      return rng.randi_range(3, 8)
		RiverConstants.TILE_ROCK:          return rng.randi_range(1, 2)
		RiverConstants.TILE_BOULDER:       return rng.randi_range(2, 4)
		RiverConstants.TILE_GRAVEL_BAR:    return rng.randi_range(5, 12)
		RiverConstants.TILE_LOG:           return rng.randi_range(4, 9)
	return 2


func _structure_h(rng: RandomNumberGenerator, tile_type: int) -> int:
	match tile_type:
		RiverConstants.TILE_WEED_BED:      return rng.randi_range(2, 3)
		RiverConstants.TILE_ROCK:          return rng.randi_range(1, 2)
		RiverConstants.TILE_BOULDER:       return rng.randi_range(2, 3)
		RiverConstants.TILE_GRAVEL_BAR:    return rng.randi_range(2, 3)
		RiverConstants.TILE_LOG:           return 1
	return 1


# ---------------------------------------------------------------------------
# Step 5 — Bake structure tiles into tile_map
# ---------------------------------------------------------------------------

func _apply_structure_tiles(data: RiverData) -> void:
	for structure: Dictionary in data.structures:
		var sx: int = structure["x"]
		var sy: int = structure["y"]
		var sw: int = structure["w"]
		var sh: int = structure["h"]
		var tile_type: int = structure["type"]

		for dx in sw:
			for dy in sh:
				var tx := sx + dx
				var ty := sy + dy
				if tx < 0 or tx >= data.width or ty < 0 or ty >= data.height:
					continue
				var existing: int = data.tile_map[tx][ty]
				# Only place on water tiles — never overwrite bank or air
				if existing != RiverConstants.TILE_BANK and existing != RiverConstants.TILE_AIR:
					data.tile_map[tx][ty] = tile_type


# ---------------------------------------------------------------------------
# Step 6 — Eddy currents downstream of rocks and boulders
# ---------------------------------------------------------------------------

func _apply_eddy_currents(data: RiverData) -> void:
	for structure: Dictionary in data.structures:
		var tile_type: int = structure["type"]
		if tile_type != RiverConstants.TILE_ROCK and tile_type != RiverConstants.TILE_BOULDER:
			continue

		var sx: int = structure["x"]
		var sw: int = structure["w"]
		var sy: int = structure["y"]
		var sh: int = structure["h"]

		# Eddy extends downstream (right) for 3× structure width + buffer.
		# Stronger and longer eddies make downstream holds clearly preferable.
		var eddy_start := sx + sw
		var eddy_len   := sw * 3 + 4

		for dx in eddy_len:
			var ex := eddy_start + dx
			if ex >= data.width:
				break
			# Eddy strength fades linearly with distance
			var fade := 1.0 - (float(dx) / float(eddy_len))
			for dy in range(-1, sh + 2):
				var ey := sy + dy
				if ey < 0 or ey >= data.height:
					continue
				var t: int = data.tile_map[ex][ey]
				if t == RiverConstants.TILE_AIR or t == RiverConstants.TILE_BANK:
					continue
				data.current_map[ex][ey] = lerpf(
					data.current_map[ex][ey] as float, 0.08, fade * 0.85
				)


# ---------------------------------------------------------------------------
# Step 7 — Hold score evaluation
# ---------------------------------------------------------------------------

func _calculate_hold_scores(data: RiverData) -> void:
	for x in data.width:
		var habitat: int = data.habitat_type[x]

		# Habitat bonus/penalty — rewards ecologically correct holding water.
		# Tailouts and pocket water are productive; fords and riffles are not.
		var habitat_sc: float
		match habitat:
			RiverConstants.HABITAT_POOL_BELLY: habitat_sc =  0.40
			RiverConstants.HABITAT_POOL_TAIL:  habitat_sc =  0.25
			RiverConstants.HABITAT_POOL_HEAD:  habitat_sc =  0.15
			RiverConstants.HABITAT_RUN:        habitat_sc =  0.10
			RiverConstants.HABITAT_POCKET:     habitat_sc =  0.30
			RiverConstants.HABITAT_RIFFLE:     habitat_sc = -0.10
			RiverConstants.HABITAT_FORD:       habitat_sc = -0.50
			_:                                 habitat_sc =  0.0

		# Depth score multiplier varies by habitat type.
		# Deep still pools deserve extra credit for depth; shallow riffles less so.
		var depth_mult: float
		match habitat:
			RiverConstants.HABITAT_POOL_BELLY:            depth_mult = 1.20
			RiverConstants.HABITAT_RIFFLE:                depth_mult = 0.50
			RiverConstants.HABITAT_POOL_HEAD, \
			RiverConstants.HABITAT_POOL_TAIL:             depth_mult = 0.90
			_:                                            depth_mult = 0.80

		for y in data.height:
			var tile: int = data.tile_map[x][y]
			if tile == RiverConstants.TILE_BANK or tile == RiverConstants.TILE_AIR:
				continue

			var cover      := _cover_at(data, x, y)
			var depth_sc: float = (data.depth_profile[x] as float) * depth_mult

			# Bell-curve current preference peaking at 0.6 (≈ 1.5 fps comfortable wade speed).
			# Replaces the old linear "slower = always better" model.
			# Too slow (still pool) = low food delivery. Too fast (riffle) = too costly to hold.
			var current_val: float = data.current_map[x][y]
			var bell_sc: float = exp(-pow((current_val - 0.60) / 0.35, 2.0))

			var seam_sc := _seam_at(data, x, y)

			data.hold_scores[x][y] = cover + depth_sc + bell_sc + seam_sc + habitat_sc


func _cover_at(data: RiverData, x: int, y: int) -> float:
	# Maximum cover value from any structure within a 4-tile radius.
	# Rocks/boulders: tiles upstream of the structure get a heavy cover penalty
	# since the eddy (and therefore the good holding water) is downstream.
	var best := 0.0
	for structure: Dictionary in data.structures:
		var sx: int = structure["x"]
		var sy: int = structure["y"]
		var sw: int = structure["w"]
		var sh: int = structure["h"]
		var tile_type: int = structure["type"]
		var dist_x := maxi(0, maxi(sx - x, x - (sx + sw - 1)))
		var dist_y := maxi(0, maxi(sy - y, y - (sy + sh - 1)))
		if dist_x > 4 or dist_y > 4:
			continue
		var cover_val: float = float(structure["cover"])
		# Upstream of a rock/boulder: only 15% cover — not in the eddy
		if (tile_type == RiverConstants.TILE_ROCK or tile_type == RiverConstants.TILE_BOULDER) \
				and x < sx:
			cover_val *= 0.15
		best = maxf(best, cover_val)
	return best


func _seam_at(data: RiverData, x: int, y: int) -> float:
	# Reward tiles adjacent to a significant current speed change (seam)
	if x <= 0 or x >= data.width - 1:
		return 0.0
	var diff := absf((data.current_map[x + 1][y] as float) - (data.current_map[x - 1][y] as float))
	return minf(diff * 2.0, 1.0)


# ---------------------------------------------------------------------------
# Step 8 — Find top hold candidates for fish spawning (Phase 5)
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Habitat classification
# ---------------------------------------------------------------------------

# Classifies each column as pool/run/riffle/ford based on the finalised depth_profile.
# Must run after _inject_ford_sections (ford positions already written) and before
# _build_tile_map (tile builder may reference habitat in future phases).
#
# Depth profile interpretation (lower = deeper/slower = pool, higher = shallower/faster):
#   < 0.12  → FORD    (injected shallow crossings)
#   < 0.27  → pool zone — sub-classified into HEAD / BELLY / TAIL by contiguous block scan
#   0.27–0.68 → RUN
#   > 0.68  → RIFFLE
func _classify_habitat(data: RiverData) -> void:
	# --- First pass: coarse classification ---
	for x in data.width:
		var d: float = data.depth_profile[x]
		if d < 0.12:
			data.habitat_type[x]   = RiverConstants.HABITAT_FORD
			data.exposure_factor[x] = 1.00
		elif d < 0.27:
			data.habitat_type[x]   = RiverConstants.HABITAT_POOL_BELLY  # refined below
			data.exposure_factor[x] = 0.15
		elif d < 0.68:
			data.habitat_type[x]   = RiverConstants.HABITAT_RUN
			data.exposure_factor[x] = 0.45
		else:
			data.habitat_type[x]   = RiverConstants.HABITAT_RIFFLE
			data.exposure_factor[x] = 0.85

	# --- Second pass: sub-classify pool zones into HEAD / BELLY / TAIL ---
	# Scan for contiguous POOL_BELLY blocks. Re-label the leading tiles as
	# POOL_HEAD (plunge / food funnel entry) and trailing tiles as POOL_TAIL (tailout).
	const HEAD_LEN := 8   # tiles at upstream entry
	const TAIL_LEN := 10  # tiles at downstream exit (tailout is longer than head)

	var x := 0
	while x < data.width:
		if data.habitat_type[x] != RiverConstants.HABITAT_POOL_BELLY:
			x += 1
			continue

		# Found start of a pool block — find its end.
		var block_start := x
		while x < data.width and data.habitat_type[x] == RiverConstants.HABITAT_POOL_BELLY:
			x += 1
		var block_end := x   # exclusive

		var block_len := block_end - block_start
		# Only sub-classify if block is long enough to have all three zones.
		if block_len >= HEAD_LEN + TAIL_LEN + 1:
			for i in HEAD_LEN:
				var hx := block_start + i
				data.habitat_type[hx]   = RiverConstants.HABITAT_POOL_HEAD
				data.exposure_factor[hx] = 0.35
			for i in TAIL_LEN:
				var tx := block_end - TAIL_LEN + i
				data.habitat_type[tx]   = RiverConstants.HABITAT_POOL_TAIL
				data.exposure_factor[tx] = 0.70
		elif block_len >= 4:
			# Short pool: label first half HEAD, second half TAIL (no belly).
			var mid := block_start + block_len / 2
			for i in range(block_start, mid):
				data.habitat_type[i]   = RiverConstants.HABITAT_POOL_HEAD
				data.exposure_factor[i] = 0.35
			for i in range(mid, block_end):
				data.habitat_type[i]   = RiverConstants.HABITAT_POOL_TAIL
				data.exposure_factor[i] = 0.70
		# else: single/double tile pool — leave as POOL_BELLY


# Refines pocket-water habitat labels around ROCK and BOULDER structures.
# Must run after _apply_eddy_currents (structure positions are finalised).
# Labels the 4-tile downstream window of each rock/boulder as HABITAT_POCKET and
# reduces exposure (the eddy provides partial cover).
func _classify_pocket_water(data: RiverData) -> void:
	for structure: Dictionary in data.structures:
		var tile_type: int = structure["type"]
		if tile_type != RiverConstants.TILE_ROCK and tile_type != RiverConstants.TILE_BOULDER:
			continue

		var sx: int = structure["x"]
		var sw: int = structure["w"]
		var eddy_start := sx + sw          # first column downstream of structure
		var eddy_len   := sw * 2 + 4       # V-seam window: 2× width + buffer

		for dx in eddy_len:
			var ex := eddy_start + dx
			if ex < 0 or ex >= data.width:
				break
			# Don't overwrite ford — fords are passable and high-exposure by design.
			if data.habitat_type[ex] == RiverConstants.HABITAT_FORD:
				continue
			data.habitat_type[ex] = RiverConstants.HABITAT_POCKET
			# Eddy provides cover: reduce exposure proportional to distance from structure.
			var fade := 1.0 - float(dx) / float(eddy_len)
			data.exposure_factor[ex] = clampf(data.exposure_factor[ex] - fade * 0.30, 0.05, 1.0)


# ---------------------------------------------------------------------------
# Step 8 — Find top hold candidates for fish spawning (Phase 5)
# ---------------------------------------------------------------------------

func _find_top_holds(data: RiverData, fish_count: int) -> void:
	var candidates: Array = []
	var min_score  := 1.8  # Raised from 1.5 — bell curve + habitat_sc inflate scores at good spots

	for x in data.width:
		for y in data.height:
			var score: float = data.hold_scores[x][y]
			if score >= min_score:
				candidates.append({"x": x, "y": y, "score": score})

	candidates.sort_custom(func(a, b): return a["score"] > b["score"])

	# Keep 3× fish_count as candidates so Phase 5 has variety to choose from
	var top := candidates.slice(0, mini(fish_count * 3, candidates.size()))

	# Annotate each hold with spawn offset, preferred species, and exposure.
	# Consumed by river_world._spawn_section_fish().
	for hold: Dictionary in top:
		_annotate_hold(data, hold)

	data.top_holds = top


# Adds spawn_dx, spawn_dy, best_species, and exposure fields to a hold dict.
func _annotate_hold(data: RiverData, hold: Dictionary) -> void:
	var hx: int = hold["x"]
	var hy: int = hold["y"]

	# --- Spawn offset ---
	# Fish don't sit on rocks; push them into the downstream V-seam.
	# Scan for ROCK/BOULDER structures immediately upstream of this hold (within 8 tiles).
	var spawn_dx := 0
	var spawn_dy := 0
	for structure: Dictionary in data.structures:
		var tile_type: int = structure["type"]
		var sx: int = structure["x"]
		var sw: int = structure["w"]
		var sy: int = structure["y"]
		var sh: int = structure["h"]

		if tile_type == RiverConstants.TILE_ROCK or tile_type == RiverConstants.TILE_BOULDER:
			# V-seam is downstream (positive x). Only offset if the hold is
			# sitting on or directly adjacent to the structure.
			var struct_right := sx + sw
			var dist_downstream := hx - struct_right
			if dist_downstream >= 0 and dist_downstream <= 2:
				# Hold is at the structure's immediate downstream edge — push into V-seam.
				var vsm_dx := sw * 2   # 2× structure width into V-seam
				var target_x := clampi(struct_right + vsm_dx, 0, data.width - 1)
				# Verify the V-seam target is a valid water tile.
				var target_row := clampi(hy, 0, data.height - 1)
				var t: int = data.tile_map[target_x][target_row]
				if t != RiverConstants.TILE_BANK and t != RiverConstants.TILE_AIR:
					spawn_dx = target_x - hx
				break

	hold["spawn_dx"] = spawn_dx
	hold["spawn_dy"] = spawn_dy

	# --- Preferred species ---
	# Species int matches FishAI.Species enum: 0=BROWN_TROUT, 1=RAINBOW_TROUT, 2=WHITEFISH
	hold["best_species"] = _compute_species_affinity(data, hx, hy)

	# --- Exposure ---
	hold["exposure"] = data.exposure_factor[hx] if data.exposure_factor.size() > hx else 0.5


# Returns the FishAI.Species int (0/1/2) most ecologically appropriate for this hold.
# Weighs nearby structures and habitat type per species preference research.
# 0 = BROWN_TROUT, 1 = RAINBOW_TROUT, 2 = WHITEFISH
func _compute_species_affinity(data: RiverData, hx: int, hy: int) -> int:
	var scores := [0.0, 0.0, 0.0]  # brown, rainbow, whitefish

	# Habitat base weights
	var habitat: int = data.habitat_type[hx] if data.habitat_type.size() > hx \
			else RiverConstants.HABITAT_RUN
	match habitat:
		RiverConstants.HABITAT_POOL_BELLY: scores[0] += 0.60
		RiverConstants.HABITAT_POOL_HEAD:  scores[0] += 0.30; scores[1] += 0.20
		RiverConstants.HABITAT_POOL_TAIL:  scores[1] += 0.50; scores[0] += 0.30
		RiverConstants.HABITAT_RUN:        scores[0] += 0.20; scores[1] += 0.20
		RiverConstants.HABITAT_RIFFLE:     scores[1] += 0.70; scores[2] += 0.50
		RiverConstants.HABITAT_POCKET:     scores[0] += 0.40; scores[1] += 0.30
		RiverConstants.HABITAT_FORD:       scores[2] += 0.60; scores[1] += 0.20

	# Structure proximity weights (scan within 8-tile radius)
	for structure: Dictionary in data.structures:
		var sx: int = structure["x"]
		var sy: int = structure["y"]
		var sw: int = structure["w"]
		var sh: int = structure["h"]
		var tile_type: int = structure["type"]
		var dist_x := maxi(0, maxi(sx - hx, hx - (sx + sw - 1)))
		var dist_y := maxi(0, maxi(sy - hy, hy - (sy + sh - 1)))
		if dist_x > 8 or dist_y > 4:
			continue
		match tile_type:
			RiverConstants.TILE_BOULDER:       scores[0] += 0.80; scores[1] += 0.40
			RiverConstants.TILE_ROCK:          scores[0] += 0.50; scores[1] += 0.35
			RiverConstants.TILE_WEED_BED:      scores[1] += 0.60; scores[0] += 0.30
			RiverConstants.TILE_GRAVEL_BAR:    scores[2] += 1.00; scores[1] += 0.30

	# Bank-adjacent deep water bonus (replaces old undercut bank structure).
	# Brown trout favor deep water tight against the bank (natural undercuts from erosion).
	var near_bank_dist: int = (hy - data.top_bank_profile[hx]) \
			if data.top_bank_profile.size() > hx else 99
	var far_bank_dist: int = (data.bottom_bank_profile[hx] - 1 - hy) \
			if data.bottom_bank_profile.size() > hx else 99
	var bank_dist: int = mini(near_bank_dist, far_bank_dist)
	if bank_dist <= 2:
		var tile_at: int = data.tile_map[hx][hy] if hx < data.width and hy < data.height else 0
		if tile_at == RiverConstants.TILE_DEEP or tile_at == RiverConstants.TILE_MID_DEPTH:
			scores[0] += 1.00   # brown trout love deep bank-adjacent lies
			scores[1] += 0.10

	# Return species index with highest score
	var best := 0
	for i in 3:
		if scores[i] > scores[best]:
			best = i
	return best
