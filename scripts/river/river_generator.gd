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
	_inject_ford_sections(data)     # carve periodic shallow crossings
	_build_tile_map(data)
	_generate_current_map(data)
	_place_structures(data, config)
	_apply_structure_tiles(data)
	_apply_eddy_currents(data)
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
		# Range [0.20, 1.0] — lower bound allows natural shallow riffles; fords injected separately
		data.depth_profile[x] = clampf(normalized * 0.80 + 0.20, 0.0, 1.0)


# ---------------------------------------------------------------------------
# Step 1b — Ford injection: carve periodic shallow crossings into depth profile
# ---------------------------------------------------------------------------

func _inject_ford_sections(data: RiverData) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(data.seed + 22222)
	const FORD_SPACING := 380   # average tiles between ford centres
	const FORD_WIDTH   := 50    # tiles across the ford transition
	const FORD_DEPTH   := 0.08  # depth_val at ford centre (very shallow)

	var x := rng.randi_range(80, FORD_SPACING)
	while x < data.width - 80:
		var hw := FORD_WIDTH / 2
		for dx in range(-hw, hw + 1):
			var fx := x + dx
			if fx < 0 or fx >= data.width:
				continue
			# Smooth cosine taper from normal depth at edges to FORD_DEPTH at centre
			var t := float(abs(dx)) / float(hw)  # 0 = centre, 1 = edge
			var taper := (1.0 - cos(t * PI)) * 0.5   # smooth 0→1
			var current: float = data.depth_profile[fx]
			data.depth_profile[fx] = lerpf(FORD_DEPTH, current, taper)
		x += FORD_SPACING + rng.randi_range(-60, 60)


# ---------------------------------------------------------------------------
# Step 2 — Tile map: U-shape cross-section (deep channel, shallow banks)
# ---------------------------------------------------------------------------

func _build_tile_map(data: RiverData) -> void:
	var top_bank   := RiverConstants.BANK_H_TILES          # 3
	var bot_bank_h := RiverConstants.BOTTOM_BANK_H_TILES   # 3
	var min_depth  := RiverConstants.MIN_DEPTH_TILES       # 4
	var max_depth  := RiverConstants.MAX_DEPTH_TILES       # 22

	# Water always spans from just below top bank to just above bottom bank.
	# depth_profile controls the tier distribution (all-surface ford vs deep pool).
	var water_top  := top_bank           # y=3, first water row
	var water_span := max_depth          # maximum rows of water

	# 2D noise for lateral variation in tier boundaries
	var tier_noise := FastNoiseLite.new()
	tier_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	tier_noise.seed       = data.seed + 54321
	tier_noise.frequency  = 0.018

	for x in data.width:
		var depth_val: float = data.depth_profile[x]
		# Actual water column height for this column
		var water_cols := min_depth + int(depth_val * float(max_depth - min_depth))
		var riverbed_y := water_top + water_cols  # row index of riverbed tile

		for y in data.height:
			if y < top_bank:
				data.tile_map[x][y] = RiverConstants.TILE_BANK
			elif y < water_top:
				data.tile_map[x][y] = RiverConstants.TILE_SURFACE
			elif y < riverbed_y:
				# U-shaped depth: deepest in the centre of the water column.
				# frac=0 at top edge, frac=1 at bottom edge; centre = 0.5
				var frac      := float(y - water_top) / float(water_cols)
				var centre_d  := abs(frac - 0.5) * 2.0   # 0 = centre, 1 = edge
				var tn        := tier_noise.get_noise_2d(float(x), float(y)) * 0.10
				# Thresholds shrink as depth_val drops → ford = all SURFACE
				var deep_thr  := lerpf(-0.2, 0.38, depth_val)
				var mid_thr   := lerpf(0.25, 0.70, depth_val)
				if centre_d < (deep_thr + tn):
					data.tile_map[x][y] = RiverConstants.TILE_DEEP
				elif centre_d < (mid_thr + tn):
					data.tile_map[x][y] = RiverConstants.TILE_MID_DEPTH
				else:
					data.tile_map[x][y] = RiverConstants.TILE_SURFACE
			elif y == riverbed_y:
				data.tile_map[x][y] = RiverConstants.TILE_RIVERBED
			elif y < riverbed_y + bot_bank_h + 1:
				# Far (bottom) bank — appears right after the riverbed
				data.tile_map[x][y] = RiverConstants.TILE_BANK
			# y beyond that stays TILE_AIR


# ---------------------------------------------------------------------------
# Step 3 — Current map (shallow = fast, deep = slow)
# ---------------------------------------------------------------------------

func _generate_current_map(data: RiverData) -> void:
	for x in data.width:
		var depth_val: float = data.depth_profile[x]
		# Shallow riffles run fast (0.85-1.0), deep pools slow (0.25-0.55)
		var base_speed := lerpf(0.95, 0.25, depth_val)

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
				RiverConstants.TILE_RIVERBED:
					data.current_map[x][y] = base_speed * 0.30
				_:
					data.current_map[x][y] = base_speed


# ---------------------------------------------------------------------------
# Step 4 — Structure placement
# ---------------------------------------------------------------------------

func _place_structures(data: RiverData, config: DifficultyConfig) -> void:
	var density := config.structure_density_multiplier

	# Target counts per structure type, scaled by density.
	# Increased base counts for richer habitat and more fish holding spots.
	var counts := {
		RiverConstants.TILE_WEED_BED:      int(14 * density),
		RiverConstants.TILE_ROCK:          int(28 * density),
		RiverConstants.TILE_BOULDER:       int(8  * density),
		RiverConstants.TILE_UNDERCUT_BANK: int(10 * density),
		RiverConstants.TILE_GRAVEL_BAR:    int(8  * density),
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
		RiverConstants.TILE_UNDERCUT_BANK:
			return y == RiverConstants.BANK_H_TILES
		RiverConstants.TILE_GRAVEL_BAR:
			return tile == RiverConstants.TILE_SURFACE or \
				(tile == RiverConstants.TILE_MID_DEPTH and (data.depth_profile[x] as float) < 0.35)
	return false


func _structure_w(rng: RandomNumberGenerator, tile_type: int) -> int:
	match tile_type:
		RiverConstants.TILE_WEED_BED:      return rng.randi_range(3, 8)
		RiverConstants.TILE_ROCK:          return rng.randi_range(1, 2)
		RiverConstants.TILE_BOULDER:       return rng.randi_range(2, 4)
		RiverConstants.TILE_UNDERCUT_BANK: return rng.randi_range(4, 8)
		RiverConstants.TILE_GRAVEL_BAR:    return rng.randi_range(5, 12)
	return 2


func _structure_h(rng: RandomNumberGenerator, tile_type: int) -> int:
	match tile_type:
		RiverConstants.TILE_WEED_BED:      return rng.randi_range(2, 3)
		RiverConstants.TILE_ROCK:          return rng.randi_range(1, 2)
		RiverConstants.TILE_BOULDER:       return rng.randi_range(2, 3)
		RiverConstants.TILE_UNDERCUT_BANK: return 2
		RiverConstants.TILE_GRAVEL_BAR:    return rng.randi_range(2, 3)
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
		for y in data.height:
			var tile: int = data.tile_map[x][y]
			if tile == RiverConstants.TILE_BANK or tile == RiverConstants.TILE_AIR:
				continue

			var cover             := _cover_at(data, x, y)
			var depth_sc: float    = data.depth_profile[x]
			depth_sc              *= 0.8
			var slow_sc: float     = data.current_map[x][y]
			slow_sc                = 1.0 - slow_sc
			var seam_sc           := _seam_at(data, x, y)

			data.hold_scores[x][y] = cover + depth_sc + slow_sc + seam_sc


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

func _find_top_holds(data: RiverData, fish_count: int) -> void:
	var candidates: Array = []
	var min_score  := 1.5  # Threshold — avoids spawning in poor habitat

	for x in data.width:
		for y in data.height:
			var score: float = data.hold_scores[x][y]
			if score >= min_score:
				candidates.append({"x": x, "y": y, "score": score})

	candidates.sort_custom(func(a, b): return a["score"] > b["score"])

	# Keep 3× fish_count as candidates so Phase 5 has variety to choose from
	data.top_holds = candidates.slice(0, mini(fish_count * 3, candidates.size()))
