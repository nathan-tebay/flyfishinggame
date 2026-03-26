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
	noise.frequency = 0.003   # Low frequency = large pool/riffle features

	for x in data.width:
		var raw        := noise.get_noise_1d(float(x))
		var normalized := (raw + 1.0) * 0.5          # remap [-1,1] → [0,1]
		# Bias toward mid-depth so extremes (pure pool / pure riffle) are rarer
		data.depth_profile[x] = clampf(normalized * 0.8 + 0.1, 0.0, 1.0)


# ---------------------------------------------------------------------------
# Step 2 — Base tile map from depth profile
# ---------------------------------------------------------------------------

func _build_tile_map(data: RiverData) -> void:
	var bank_h     := RiverConstants.BANK_H_TILES
	var min_depth  := RiverConstants.MIN_DEPTH_TILES
	var depth_span := RiverConstants.MAX_DEPTH_TILES - min_depth

	for x in data.width:
		var depth_val: float  = data.depth_profile[x]
		var water_cols := min_depth + int(depth_val * float(depth_span))
		var bottom_y   := bank_h + water_cols - 1  # y of riverbed tile

		for y in data.height:
			if y < bank_h:
				data.tile_map[x][y] = RiverConstants.TILE_BANK
			elif y == bank_h:
				data.tile_map[x][y] = RiverConstants.TILE_SURFACE
			elif y < bottom_y:
				# Split water column: upper 50% = MID_DEPTH, lower 50% = DEEP
				var frac := float(y - bank_h) / float(water_cols)
				if frac < 0.5:
					data.tile_map[x][y] = RiverConstants.TILE_MID_DEPTH
				else:
					data.tile_map[x][y] = RiverConstants.TILE_DEEP
			elif y == bottom_y:
				data.tile_map[x][y] = RiverConstants.TILE_RIVERBED
			# y > bottom_y stays TILE_AIR


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

	# Target counts per structure type, scaled by density
	var counts := {
		RiverConstants.TILE_WEED_BED:      int(8  * density),
		RiverConstants.TILE_ROCK:          int(15 * density),
		RiverConstants.TILE_BOULDER:       int(4  * density),
		RiverConstants.TILE_UNDERCUT_BANK: int(6  * density),
		RiverConstants.TILE_GRAVEL_BAR:    int(5  * density),
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

		# Eddy extends downstream (right) for 2× structure width
		var eddy_start := sx + sw
		var eddy_len   := sw * 2 + 2

		for dx in eddy_len:
			var ex := eddy_start + dx
			if ex >= data.width:
				break
			# Eddy strength fades linearly with distance
			var fade := 1.0 - (float(dx) / float(eddy_len))
			for dy in range(-1, sh + 1):
				var ey := sy + dy
				if ey < 0 or ey >= data.height:
					continue
				var t: int = data.tile_map[ex][ey]
				if t == RiverConstants.TILE_AIR or t == RiverConstants.TILE_BANK:
					continue
				data.current_map[ex][ey] = lerpf(
					data.current_map[ex][ey] as float, 0.12, fade * 0.75
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
	# Maximum cover value from any structure within a 4-tile radius
	var best := 0.0
	for structure: Dictionary in data.structures:
		var sx: int = structure["x"]
		var sy: int = structure["y"]
		var sw: int = structure["w"]
		var sh: int = structure["h"]
		var dist_x := maxi(0, maxi(sx - x, x - (sx + sw - 1)))
		var dist_y := maxi(0, maxi(sy - y, y - (sy + sh - 1)))
		if dist_x <= 4 and dist_y <= 4:
			best = maxf(best, float(structure["cover"]))
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
