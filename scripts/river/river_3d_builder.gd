class_name River3DBuilder
extends Node3D

const LowerMadisonReachScript = preload("res://scripts/river/lower_madison_reach.gd")
const FishModelScript = preload("res://scripts/models/fish_model_3d.gd")
const AdultInsectScript = preload("res://scripts/models/adult_insect_3d.gd")
const MAT_WATER = preload("res://assets/3d/materials/river_water.tres")
const MAT_GRAVEL = preload("res://assets/3d/materials/bank_gravel.tres")
const MAT_WET_GRAVEL = preload("res://assets/3d/materials/wet_gravel.tres")
const MAT_BANK = preload("res://assets/3d/materials/bank_grass.tres")
const MAT_SOIL = preload("res://assets/3d/materials/bank_soil.tres")
const MAT_MEADOW = preload("res://assets/3d/materials/meadow_grass.tres")
const MAT_RIVERBED = preload("res://assets/3d/materials/riverbed.tres")
const MAT_COBBLE = preload("res://assets/3d/materials/river_cobble.tres")
const MAT_ROCK = preload("res://assets/3d/materials/river_rock.tres")
const MAT_LOG = preload("res://assets/3d/materials/driftwood.tres")
const MAT_REEDS = preload("res://assets/3d/materials/reeds.tres")
const MAT_WILLOW = preload("res://assets/3d/materials/willow_leaf.tres")
const MAT_COTTONWOOD = preload("res://assets/3d/materials/cottonwood_leaf.tres")
const MAT_WEEDS = preload("res://assets/3d/materials/submerged_weeds.tres")

const CHANNEL_CROSS_SEGMENTS := 36
const GRAVEL_SHELF := 4.1
const VEGETATED_BANK := 25.0
const SHORE_WET_SHELF := 1.35
const SHORE_EDGE_LIFT := -0.012
const SHORE_WET_LIFT := 0.006
const BAR_RING_SEGMENTS := 24
const BAR_WET_APRON := 1.35
const BAR_BED_TRANSITION := 2.25
const BAR_CENTER_LIFT := 0.026
const BAR_SHOULDER_LIFT := 0.016
const BAR_EDGE_LIFT := 0.002
const BAR_APRON_LIFT := -0.008
const FISH_SPECIES := [0, 1, 2]

var reach: LowerMadisonReachScript = null
var session_seed := 0
var force_headless_build := false
var cobble_density := 1.0
var vegetation_density := 1.0
var insect_density := 1.0
var fish_visual_density := 1.0
var fish_hold_entries: Array[Dictionary] = []
var build_profile: Dictionary = {}
var _primitive_mesh_cache: Dictionary = {}
var _half_width_cache: Dictionary = {}
var _water_depth_cache: Dictionary = {}
var _position_cache: Dictionary = {}
var _bank_height_cache: Dictionary = {}
var _bar_frame_cache: Dictionary = {}


func build(authored_reach: LowerMadisonReachScript, fish_seed: int) -> void:
	reach = authored_reach
	session_seed = fish_seed
	_clear()
	var build_start_usec := Time.get_ticks_usec()
	_run_build_stage("fish_holds", Callable(self, "_build_fish_hold_entries"))
	if _is_headless_rendering():
		build_profile["total_usec"] = Time.get_ticks_usec() - build_start_usec
		return
	_run_build_stage("terrain", Callable(self, "_build_3dep_terrain"))
	_run_build_stage("channel", Callable(self, "_build_channel"))
	_run_build_stage("bank_corridor", Callable(self, "_build_bank_corridor"))
	_run_build_stage("gravel_bars", Callable(self, "_build_gravel_bars"))
	_run_build_stage("cobbles", Callable(self, "_build_cobbles"))
	_run_build_stage("structures", Callable(self, "_build_structures"))
	_run_build_stage("weed_beds", Callable(self, "_build_weed_beds"))
	_run_build_stage("riparian_cover", Callable(self, "_build_riparian_cover"))
	_run_build_stage("adult_surface_insects", Callable(self, "_build_adult_surface_insects"))
	_run_build_stage("seeded_fish", Callable(self, "_build_seeded_fish"))
	build_profile["total_usec"] = Time.get_ticks_usec() - build_start_usec
	build_profile["child_count"] = get_child_count()
	build_profile["primitive_mesh_cache"] = _primitive_mesh_cache.size()


func _run_build_stage(stage_name: String, stage_callable: Callable) -> void:
	var stage_start_usec := Time.get_ticks_usec()
	stage_callable.call()
	build_profile[stage_name + "_usec"] = Time.get_ticks_usec() - stage_start_usec


func world_bounds() -> Rect2:
	return reach.world_bounds()


func sample_at(world_pos: Vector3) -> Dictionary:
	return reach.sample(world_pos)


func start_position() -> Vector3:
	return reach.start_position()


func look_target_from_start() -> Vector3:
	return reach.look_target_from_start()


func _is_headless_rendering() -> bool:
	return DisplayServer.get_name() == "headless" and not force_headless_build


func _clear() -> void:
	for child in get_children():
		child.queue_free()
	build_profile.clear()
	_half_width_cache.clear()
	_water_depth_cache.clear()
	_position_cache.clear()
	_bank_height_cache.clear()
	_bar_frame_cache.clear()


func _cache_key_1(a: float) -> String:
	return "%.5f" % a


func _cache_key_2(a: float, b: float) -> String:
	return "%.5f:%.5f" % [a, b]


func _cache_key_3(a: float, b: float, c: float) -> String:
	return "%.5f:%.5f:%.5f" % [a, b, c]


func _density_allows(index: int, density: float) -> bool:
	if density >= 0.999:
		return true
	if density <= 0.0:
		return false
	var bucket := maxi(1, int(round(1.0 / clampf(density, 0.01, 1.0))))
	return posmod(index, bucket) == 0


func _half_width_at(fraction: float) -> float:
	var key := _cache_key_1(fraction)
	if _half_width_cache.has(key):
		return float(_half_width_cache[key])
	var value := reach.half_width_at(fraction)
	_half_width_cache[key] = value
	return value


func _water_depth_at(fraction: float, lateral: float) -> float:
	var key := _cache_key_2(fraction, lateral)
	if _water_depth_cache.has(key):
		return float(_water_depth_cache[key])
	var value := reach.water_depth_at(fraction, lateral)
	_water_depth_cache[key] = value
	return value


func _position_at(fraction: float, lateral: float, height: float = INF) -> Vector3:
	var key := _cache_key_3(fraction, lateral, height)
	if _position_cache.has(key):
		return _position_cache[key]
	var value := reach.position_at(fraction, lateral) if height == INF else reach.position_at(fraction, lateral, height)
	_position_cache[key] = value
	return value


func _build_3dep_terrain() -> void:
	var ground := SurfaceTool.new()
	ground.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in range(reach.terrain_row_count() - 1):
		for column in range(reach.terrain_column_count() - 1):
			var a := reach.terrain_grid_point(row, column)
			var b := reach.terrain_grid_point(row + 1, column + 1)
			var c := reach.terrain_grid_point(row, column + 1)
			var d := reach.terrain_grid_point(row + 1, column)
			var midpoint := (a + b + c + d) * 0.25
			if reach.is_channel_corridor(Vector2(midpoint.x, midpoint.z), VEGETATED_BANK):
				continue
			_add_quad(ground, a, b, c, d, Color.WHITE)
	_commit("USGS3DEPValleyTerrain", ground, MAT_SOIL)


func _build_channel() -> void:
	var bed := SurfaceTool.new()
	var water := SurfaceTool.new()
	bed.begin(Mesh.PRIMITIVE_TRIANGLES)
	water.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(reach.station_count() - 1):
		var current := reach.station_at(i)
		var next := reach.station_at(i + 1)
		var f0: float = current["fraction"]
		var f1: float = next["fraction"]
		var width0 := _half_width_at(f0)
		var width1 := _half_width_at(f1)
		for section in CHANNEL_CROSS_SEGMENTS:
			var across0 := lerpf(-1.0, 1.0, float(section) / float(CHANNEL_CROSS_SEGMENTS))
			var across1 := lerpf(-1.0, 1.0, float(section + 1) / float(CHANNEL_CROSS_SEGMENTS))
			var lateral00 := across0 * width0
			var lateral01 := across1 * width0
			var lateral10 := across0 * width1
			var lateral11 := across1 * width1
			var bed_a := _bed_vertex(f0, lateral00)
			var bed_b := _bed_vertex(f1, lateral11)
			var bed_c := _bed_vertex(f1, lateral10)
			var bed_d := _bed_vertex(f0, lateral01)
			_add_quad_reversed(bed, bed_a, bed_b, bed_c, bed_d, _bed_color(f0, lateral00))
			var water_a := _position_at(f0, lateral00)
			var water_b := _position_at(f1, lateral11)
			var water_c := _position_at(f1, lateral10)
			var water_d := _position_at(f0, lateral01)
			if _water_quad_is_clear(water_a, water_b, water_c, water_d):
				_add_quad_reversed_colors(water, water_a, water_b, water_c, water_d,
						_water_color(f0, lateral00), _water_color(f1, lateral11),
						_water_color(f1, lateral10), _water_color(f0, lateral01))
	_commit("CarvedCobbleRiverbed", bed, MAT_RIVERBED)
	_commit("BoundedMovingWater", water, MAT_WATER)


func _build_bank_corridor() -> void:
	var wet_gravel := SurfaceTool.new()
	var gravel := SurfaceTool.new()
	var meadow := SurfaceTool.new()
	wet_gravel.begin(Mesh.PRIMITIVE_TRIANGLES)
	gravel.begin(Mesh.PRIMITIVE_TRIANGLES)
	meadow.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(reach.station_count() - 1):
		var current := reach.station_at(i)
		var next := reach.station_at(i + 1)
		var f0: float = current["fraction"]
		var f1: float = next["fraction"]
		for side_variant in [-1.0, 1.0]:
			var side := float(side_variant)
			var water0: float = side * _half_width_at(f0)
			var water1: float = side * _half_width_at(f1)
			var wet0: float = side * (_half_width_at(f0) + SHORE_WET_SHELF)
			var wet1: float = side * (_half_width_at(f1) + SHORE_WET_SHELF)
			var gravel0: float = side * (_half_width_at(f0) + GRAVEL_SHELF)
			var gravel1: float = side * (_half_width_at(f1) + GRAVEL_SHELF)
			var meadow0: float = side * (_half_width_at(f0) + VEGETATED_BANK)
			var meadow1: float = side * (_half_width_at(f1) + VEGETATED_BANK)
			var water_current := _position_at(f0, water0, LowerMadisonReachScript.WATER_HEIGHT + SHORE_EDGE_LIFT)
			var water_next := _position_at(f1, water1, LowerMadisonReachScript.WATER_HEIGHT + SHORE_EDGE_LIFT)
			var wet_current := _position_at(f0, wet0, LowerMadisonReachScript.WATER_HEIGHT + SHORE_WET_LIFT)
			var wet_next := _position_at(f1, wet1, LowerMadisonReachScript.WATER_HEIGHT + SHORE_WET_LIFT)
			var gravel_current := _position_at(f0, gravel0, _bank_height(f0, gravel0))
			var gravel_next := _position_at(f1, gravel1, _bank_height(f1, gravel1))
			var meadow_current := _position_at(f0, meadow0, _bank_height(f0, meadow0))
			var meadow_next := _position_at(f1, meadow1, _bank_height(f1, meadow1))
			_add_bank_quad(wet_gravel, side, water_current, wet_next, water_next, wet_current)
			_add_bank_quad(gravel, side, wet_current, gravel_next, wet_next, gravel_current)
			_add_bank_quad(meadow, side, gravel_current, meadow_next, gravel_next, meadow_current)
	_commit("WetShorelineBlend", wet_gravel, MAT_WET_GRAVEL)
	_commit("GravelWaterlineShelves", gravel, MAT_GRAVEL)
	_commit("VegetatedBankBenches", meadow, MAT_BANK)


func _build_gravel_bars() -> void:
	var bars := SurfaceTool.new()
	var wet_aprons := SurfaceTool.new()
	var bed_transitions := SurfaceTool.new()
	bars.begin(Mesh.PRIMITIVE_TRIANGLES)
	wet_aprons.begin(Mesh.PRIMITIVE_TRIANGLES)
	bed_transitions.begin(Mesh.PRIMITIVE_TRIANGLES)
	for bar in reach.gravel_bars():
		var bd := bar as Dictionary
		_add_gravel_bar(bars, wet_aprons, bed_transitions, float(bd["fraction"]), float(bd["lateral"]),
				float(bd["length"]), float(bd["width"]))
	_commit("SubmergedPointBarBedTransitions", bed_transitions, MAT_RIVERBED)
	_commit("ExposedPointBars", bars, MAT_GRAVEL)
	_commit("WetPointBarAprons", wet_aprons, MAT_WET_GRAVEL)


func _build_cobbles() -> void:
	var transforms: Array[Transform3D] = []
	var cobble_index := 0
	for i in range(8, reach.station_count() - 4, 5):
		var fraction: float = reach.station_at(i)["fraction"]
		for cross in [-0.64, -0.28, 0.18, 0.54]:
			cobble_index += 1
			if not _density_allows(cobble_index, cobble_density):
				continue
			var lateral := _half_width_at(fraction) * float(cross)
			if _water_depth_at(fraction, lateral) > 0.82:
				continue
			var scale := 0.16 + float((i + int(float(cross) * 20.0)) % 5) * 0.045
			var point := _bed_vertex(fraction, lateral)
			var basis := Basis().rotated(Vector3.UP, fraction * 21.0 + float(cross)).scaled(Vector3(scale * 1.35, scale * 0.34, scale))
			transforms.append(Transform3D(basis, point + Vector3(0.0, scale * 0.15, 0.0)))
	var mesh := _cached_unit_sphere_mesh("cobble", 8, 4)
	_add_multimesh("VisibleSubmergedCobble", mesh, transforms, MAT_COBBLE)


func _build_structures() -> void:
	var boulders: Array[Transform3D] = []
	var logs: Array[Transform3D] = []
	for structure in reach.structures():
		var sd := structure as Dictionary
		var fraction := float(sd["fraction"])
		var lateral := float(sd["lateral"])
		var base := _bed_vertex(fraction, lateral)
		if sd["kind"] == "boulder":
			boulders.append(_boulder_transform(base, float(sd["radius"])))
		else:
			logs.append(_log_transform(base, float(sd["length"]), fraction * TAU))
	_add_multimesh("FixedBoulderPockets", _cached_unit_sphere_mesh("boulder", 12, 7), boulders, MAT_ROCK)
	_add_multimesh("FixedDriftwood", _cached_cylinder_mesh("driftwood", 0.08, 0.14, 1.0, 10), logs, MAT_LOG)


func _build_weed_beds() -> void:
	var patches := SurfaceTool.new()
	patches.begin(Mesh.PRIMITIVE_TRIANGLES)
	for bed in reach.weed_beds():
		var wd := bed as Dictionary
		var center_fraction := float(wd["fraction"])
		var center_lateral := float(wd["lateral"])
		var length_fraction := float(wd["length"]) / reach.length()
		var half_width := float(wd["width"]) * 0.5
		for along in range(6):
			var f0 := center_fraction - length_fraction * 0.5 + length_fraction * float(along) / 6.0
			var f1 := center_fraction - length_fraction * 0.5 + length_fraction * float(along + 1) / 6.0
			for band in range(2):
				var l0 := center_lateral - half_width + float(band) * half_width
				var l1 := center_lateral - half_width + float(band + 1) * half_width
				_add_weed_patch_quad(patches, f0, f1, l0, l1)
	_commit("FixedWeedEdges", patches, MAT_WEEDS)


func _build_riparian_cover() -> void:
	_build_reeds_and_grasses()
	var willows: Array[Transform3D] = []
	var cottonwood_trunks: Array[Transform3D] = []
	var cottonwood_crowns: Array[Transform3D] = []
	for i in reach.willow_clusters().size():
		if not _density_allows(i, vegetation_density):
			continue
		var wd := reach.willow_clusters()[i] as Dictionary
		_add_willow_transforms(willows, _position_at(float(wd["fraction"]), float(wd["lateral"]),
				_bank_height(float(wd["fraction"]), float(wd["lateral"]))), float(wd["scale"]))
	for i in reach.tree_clusters().size():
		if not _density_allows(i, vegetation_density):
			continue
		var td := reach.tree_clusters()[i] as Dictionary
		_add_cottonwood_transforms(cottonwood_trunks, cottonwood_crowns,
				_position_at(float(td["fraction"]), float(td["lateral"]),
				_bank_height(float(td["fraction"]), float(td["lateral"]))), float(td["scale"]))
	_add_multimesh("WillowClusters", _cached_unit_sphere_mesh("willow", 7, 4), willows, MAT_WILLOW)
	_add_multimesh("CottonwoodTrunks", _cached_cylinder_mesh("cottonwood_trunk", 0.11, 0.17, 2.8, 9), cottonwood_trunks, MAT_LOG)
	_add_multimesh("CottonwoodCrowns", _cached_unit_sphere_mesh("cottonwood_crown", 8, 5), cottonwood_crowns, MAT_COTTONWOOD)


func _build_reeds_and_grasses() -> void:
	var reeds: Array[Transform3D] = []
	var grass: Array[Transform3D] = []
	for i in range(5, reach.station_count() - 5, 7):
		if not _density_allows(i, vegetation_density):
			continue
		var fraction: float = reach.station_at(i)["fraction"]
		for side_variant in [-1.0, 1.0]:
			var side := float(side_variant)
			var edge: float = side * (_half_width_at(fraction) + 1.5)
			for sprig in 3:
				var lateral: float = edge + side * float(sprig) * 0.34
				var height := 0.42 + float((i + sprig) % 4) * 0.13
				var base := _position_at(fraction, lateral, _bank_height(fraction, lateral))
				var basis := Basis().rotated(Vector3.UP, fraction * 11.0 + sprig).scaled(Vector3(1.0, height, 1.0))
				reeds.append(Transform3D(basis, base + Vector3(0.0, height * 0.5, 0.0)))
			for tuft in 2:
				var lateral: float = side * (_half_width_at(fraction) + GRAVEL_SHELF + 2.0 + tuft * 1.2)
				var height := 0.25 + float((i + tuft) % 3) * 0.12
				var base := _position_at(fraction, lateral, _bank_height(fraction, lateral))
				grass.append(Transform3D(Basis().scaled(Vector3(1.0, height, 1.0)), base + Vector3(0.0, height * 0.5, 0.0)))
	var reed_mesh := _cached_cylinder_mesh("reed", 0.012, 0.025, 1.0, 5)
	_add_multimesh("AuthoredReedClusters", reed_mesh, reeds, MAT_REEDS)
	_add_multimesh("AuthoredGrassTufts", reed_mesh, grass, MAT_REEDS)


func _build_fish_hold_entries() -> void:
	fish_hold_entries.clear()
	var holds := reach.hold_points()
	if holds.is_empty():
		return
	var first := posmod(session_seed, holds.size())
	for step in range(0, mini(holds.size(), 8), 2):
		var hold := holds[(first + step) % holds.size()] as Dictionary
		var fraction := float(hold["fraction"])
		var lateral := float(hold["lateral"])
		var depth := _water_depth_at(fraction, lateral)
		if depth < 0.24:
			continue
		var species: int = FISH_SPECIES[(first + step) % FISH_SPECIES.size()]
		var length := 0.52 + float((first + step) % 4) * 0.09
		var wariness := clampf(0.42 + length * 0.28 + depth * 0.18, 0.35, 0.82)
		fish_hold_entries.append({
			"fraction": fraction,
			"lateral": lateral,
			"depth": depth,
			"species": species,
			"length": length,
			"name": ["Rainbow Trout", "Brown Trout", "Mountain Whitefish"][species],
			"position": _position_at(fraction, lateral, LowerMadisonReachScript.WATER_HEIGHT),
			"available": true,
			"state": "feeding",
			"alert": 0.0,
			"wariness": wariness,
			"spook_radius": 4.8 + wariness * 3.2,
			"feeding_lane_radius": 1.65 + clampf(depth, 0.0, 1.0) * 1.4,
		})


func _build_seeded_fish() -> void:
	for i in fish_hold_entries.size():
		if not _density_allows(i, fish_visual_density):
			continue
		var fish_entry := fish_hold_entries[i] as Dictionary
		var species := int(fish_entry["species"])
		var fraction := float(fish_entry["fraction"])
		var lateral := float(fish_entry["lateral"])
		var depth := float(fish_entry["depth"])
		var fish := FishModelScript.new()
		fish.configure(species, float(fish_entry["length"]), fraction * 21.0)
		fish.name = "Holding%s" % ["RainbowTrout", "BrownTrout", "MountainWhitefish"][species]
		fish.position = _position_at(fraction, lateral,
				LowerMadisonReachScript.WATER_HEIGHT - clampf(depth * 0.42, 0.11, 0.30))
		var tangent: Vector2 = reach.frame_at_fraction(fraction)["tangent"]
		fish.rotation.y = atan2(tangent.x, tangent.y)
		add_child(fish)


func _build_adult_surface_insects() -> void:
	var flight_sites := [
		{"kind": 0, "fraction": 0.16, "lateral": -4.0, "height": 0.48},
		{"kind": 0, "fraction": 0.20, "lateral": 2.8, "height": 0.38},
		{"kind": 0, "fraction": 0.25, "lateral": -1.4, "height": 0.56},
		{"kind": 1, "fraction": 0.30, "lateral": 11.8, "height": 0.18},
		{"kind": 1, "fraction": 0.34, "lateral": 5.2, "height": 0.16},
		{"kind": 0, "fraction": 0.39, "lateral": 8.8, "height": 0.24},
		{"kind": 1, "fraction": 0.46, "lateral": -13.2, "height": 0.31},
		{"kind": 0, "fraction": 0.49, "lateral": -5.4, "height": 0.22},
		{"kind": 1, "fraction": 0.52, "lateral": 3.6, "height": 0.14},
		{"kind": 1, "fraction": 0.55, "lateral": 13.8, "height": 0.42},
		{"kind": 0, "fraction": 0.59, "lateral": 7.6, "height": 0.20},
		{"kind": 0, "fraction": 0.63, "lateral": -2.4, "height": 0.20},
		{"kind": 1, "fraction": 0.67, "lateral": -10.4, "height": 0.15},
		{"kind": 1, "fraction": 0.71, "lateral": -12.0, "height": 0.34},
		{"kind": 0, "fraction": 0.78, "lateral": 4.8, "height": 0.18},
		{"kind": 1, "fraction": 0.84, "lateral": -8.2, "height": 0.28},
	]
	for i in flight_sites.size():
		if not _density_allows(i, insect_density):
			continue
		var site := flight_sites[i] as Dictionary
		var insect := AdultInsectScript.new()
		insect.configure(int(site["kind"]), 0.08 + float(i % 3) * 0.01, true, float(i) * 0.73)
		insect.position = _position_at(float(site["fraction"]), float(site["lateral"]),
				LowerMadisonReachScript.WATER_HEIGHT + float(site["height"]))
		add_child(insect)


func _bed_vertex(fraction: float, lateral: float) -> Vector3:
	return _position_at(fraction, lateral,
			LowerMadisonReachScript.WATER_HEIGHT - _water_depth_at(fraction, lateral))


func _bank_height(fraction: float, lateral: float) -> float:
	var key := _cache_key_2(fraction, lateral)
	if _bank_height_cache.has(key):
		return float(_bank_height_cache[key])
	var point := _position_at(fraction, lateral)
	var value := reach.terrain_height_at(point)
	_bank_height_cache[key] = value
	return value


func _bed_color(fraction: float, lateral: float) -> Color:
	var depth := _water_depth_at(fraction, lateral)
	var edge := clampf(absf(lateral) / _half_width_at(fraction), 0.0, 1.0)
	return Color(clampf(depth / LowerMadisonReachScript.DEPTH_DEBUG_MAX, 0.0, 1.0), edge, 0.0, 1.0)


func _water_color(fraction: float, lateral: float) -> Color:
	var speed := reach.current_strength_at(fraction, lateral)
	var depth := _water_depth_at(fraction, lateral)
	var depth_norm := clampf(depth / LowerMadisonReachScript.DEPTH_DEBUG_MAX, 0.0, 1.0)
	var turbulence := reach.visual_turbulence_at(fraction, lateral)
	var curvature := reach.curvature_at_fraction(fraction)
	return Color(speed, depth_norm, turbulence, curvature)


func _water_quad_is_clear(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> bool:
	var midpoint := (a + b + c + d) * 0.25
	if not reach.is_water(midpoint):
		return false
	if _is_visual_bar_surface(midpoint):
		return false
	if not reach.is_water((a + c + b) / 3.0):
		return false
	if _is_visual_bar_surface((a + c + b) / 3.0):
		return false
	if not reach.is_water((a + b + d) / 3.0):
		return false
	if _is_visual_bar_surface((a + b + d) / 3.0):
		return false
	var dry_corners := 0
	for point in [a, b, c, d]:
		if not reach.is_water(point) or _is_visual_bar_surface(point):
			dry_corners += 1
	return dry_corners < 2


func _is_visual_bar_surface(point: Vector3) -> bool:
	var horizontal := Vector2(point.x, point.z)
	for bar in reach.gravel_bars():
		var bd := bar as Dictionary
		if _bar_ellipse_measure(horizontal, bd, BAR_WET_APRON) <= 1.0:
			return true
	return false


func _bar_ellipse_measure(point: Vector2, bar: Dictionary, margin: float) -> float:
	var cache_key := _cache_key_2(float(bar["fraction"]), float(bar["lateral"]))
	var cached_frame: Dictionary
	if _bar_frame_cache.has(cache_key):
		cached_frame = _bar_frame_cache[cache_key]
	else:
		var frame := reach.frame_at_fraction(float(bar["fraction"]))
		cached_frame = {
			"center": (frame["position"] as Vector2) + (frame["normal"] as Vector2) * float(bar["lateral"]),
			"tangent": frame["tangent"],
			"normal": frame["normal"],
		}
		_bar_frame_cache[cache_key] = cached_frame
	var center: Vector2 = cached_frame["center"]
	var delta := point - center
	var along := delta.dot(cached_frame["tangent"] as Vector2) / ((float(bar["length"]) + margin * 2.0) * 0.5)
	var across := delta.dot(cached_frame["normal"] as Vector2) / ((float(bar["width"]) + margin * 2.0) * 0.5)
	return along * along + across * across


func _boulder_transform(base: Vector3, radius: float) -> Transform3D:
	var basis := Basis().scaled(Vector3(radius * 1.32, radius * 0.75, radius * 0.96))
	return Transform3D(basis, base + Vector3(0.0, radius * 0.37, 0.0))


func _log_transform(base: Vector3, length: float, yaw: float) -> Transform3D:
	var basis := Basis.from_euler(Vector3(0.08, yaw, PI * 0.5)).scaled(Vector3(1.0, length, 1.0))
	return Transform3D(basis, base + Vector3(0.0, 0.12, 0.0))


func _add_cottonwood_transforms(trunks: Array[Transform3D], crowns: Array[Transform3D],
		base: Vector3, scale_value: float) -> void:
	var trunk_basis := Basis().scaled(Vector3(scale_value, scale_value, scale_value))
	trunks.append(Transform3D(trunk_basis, base + Vector3(0.0, scale_value * 2.8 * 0.5, 0.0)))
	for i in 5:
		var radius := scale_value * (0.72 + float(i % 2) * 0.12)
		var height := scale_value * (1.32 + float((i + 1) % 2) * 0.20)
		var yaw := float(i) * 1.3
		var canopy_position := base + Vector3(cos(yaw) * scale_value * 0.52,
				scale_value * (2.35 + float(i % 3) * 0.22), sin(yaw) * scale_value * 0.40)
		var canopy_basis := Basis().scaled(Vector3(radius * 1.25, height * 0.5, radius * 1.05))
		crowns.append(Transform3D(canopy_basis, canopy_position))


func _add_willow_transforms(willows: Array[Transform3D], base: Vector3, scale_value: float) -> void:
	for i in 3:
		var position := base + Vector3(float(i - 1) * scale_value * 0.66,
				scale_value * (0.55 + float(i % 2) * 0.15), 0.0)
		var basis := Basis().scaled(Vector3(scale_value * 0.72, scale_value * 1.22 * 0.5, scale_value * 0.72))
		willows.append(Transform3D(basis, position))


func _cached_unit_sphere_mesh(cache_key: String, radial_segments: int, rings: int) -> SphereMesh:
	var key := "sphere:%s:%d:%d" % [cache_key, radial_segments, rings]
	if _primitive_mesh_cache.has(key):
		return _primitive_mesh_cache[key]
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = radial_segments
	mesh.rings = rings
	_primitive_mesh_cache[key] = mesh
	return mesh


func _cached_cylinder_mesh(cache_key: String, top_radius: float, bottom_radius: float,
		height: float, radial_segments: int) -> CylinderMesh:
	var key := "cylinder:%s:%.4f:%.4f:%.4f:%d" % [cache_key, top_radius, bottom_radius, height, radial_segments]
	if _primitive_mesh_cache.has(key):
		return _primitive_mesh_cache[key]
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	mesh.radial_segments = radial_segments
	_primitive_mesh_cache[key] = mesh
	return mesh


func _add_gravel_bar(top_tool: SurfaceTool, apron_tool: SurfaceTool, transition_tool: SurfaceTool,
		fraction: float, lateral: float, length: float, width: float) -> void:
	var frame := reach.frame_at_fraction(fraction)
	var tangent: Vector2 = frame["tangent"]
	var normal: Vector2 = frame["normal"]
	var center := _position_at(fraction, lateral,
			LowerMadisonReachScript.WATER_HEIGHT + BAR_CENTER_LIFT)
	for i in BAR_RING_SEGMENTS:
		var a_angle := TAU * float(i) / float(BAR_RING_SEGMENTS)
		var b_angle := TAU * float(i + 1) / float(BAR_RING_SEGMENTS)
		var shoulder_a := _bar_ring_point(center, tangent, normal, a_angle, length, width,
				0.43, LowerMadisonReachScript.WATER_HEIGHT + BAR_SHOULDER_LIFT)
		var shoulder_b := _bar_ring_point(center, tangent, normal, b_angle, length, width,
				0.43, LowerMadisonReachScript.WATER_HEIGHT + BAR_SHOULDER_LIFT)
		var edge_a := _bar_ring_point(center, tangent, normal, a_angle, length, width,
				1.0, LowerMadisonReachScript.WATER_HEIGHT + BAR_EDGE_LIFT)
		var edge_b := _bar_ring_point(center, tangent, normal, b_angle, length, width,
				1.0, LowerMadisonReachScript.WATER_HEIGHT + BAR_EDGE_LIFT)
		var apron_a := _bar_ring_point(center, tangent, normal, a_angle,
				length + BAR_WET_APRON * 2.0, width + BAR_WET_APRON * 2.0,
				1.0, LowerMadisonReachScript.WATER_HEIGHT + BAR_APRON_LIFT)
		var apron_b := _bar_ring_point(center, tangent, normal, b_angle,
				length + BAR_WET_APRON * 2.0, width + BAR_WET_APRON * 2.0,
				1.0, LowerMadisonReachScript.WATER_HEIGHT + BAR_APRON_LIFT)
		var bed_a := _bar_bed_ring_point(center, tangent, normal, a_angle,
				length + (BAR_WET_APRON + BAR_BED_TRANSITION) * 2.0,
				width + (BAR_WET_APRON + BAR_BED_TRANSITION) * 2.0)
		var bed_b := _bar_bed_ring_point(center, tangent, normal, b_angle,
				length + (BAR_WET_APRON + BAR_BED_TRANSITION) * 2.0,
				width + (BAR_WET_APRON + BAR_BED_TRANSITION) * 2.0)
		_add_triangle(top_tool, center, shoulder_a, shoulder_b, Color.WHITE)
		_add_ring_segment(top_tool, shoulder_a, shoulder_b, edge_a, edge_b, Color.WHITE)
		_add_ring_segment(apron_tool, edge_a, edge_b, apron_a, apron_b, Color.WHITE)
		_add_ring_segment_colors(transition_tool, apron_a, apron_b, bed_a, bed_b,
				Color(0.0, 1.0, 0.0, 1.0), _bed_color_for_point(bed_a), _bed_color_for_point(bed_b))


func _bar_ring_point(center: Vector3, tangent: Vector2, normal: Vector2, angle: float,
		length: float, width: float, scale_value: float, height: float) -> Vector3:
	var offset := tangent * cos(angle) * length * 0.5 * scale_value
	offset += normal * sin(angle) * width * 0.5 * scale_value
	return Vector3(center.x + offset.x, height, center.z + offset.y)


func _bar_bed_ring_point(center: Vector3, tangent: Vector2, normal: Vector2,
		angle: float, length: float, width: float) -> Vector3:
	var point := _bar_ring_point(center, tangent, normal, angle, length, width, 1.0,
			LowerMadisonReachScript.WATER_HEIGHT)
	var sample := reach.sample(point)
	if bool(sample["is_water"]):
		point.y = float(sample["bed_height"]) + 0.012
	else:
		point.y = minf(reach.terrain_height_at(point), LowerMadisonReachScript.WATER_HEIGHT - 0.04)
	return point


func _bed_color_for_point(point: Vector3) -> Color:
	var depth := maxf(LowerMadisonReachScript.WATER_HEIGHT - point.y, 0.0)
	return Color(clampf(depth / LowerMadisonReachScript.DEPTH_DEBUG_MAX, 0.0, 1.0), 1.0, 0.0, 1.0)


func _add_weed_patch_quad(tool: SurfaceTool, f0: float, f1: float, lateral0: float, lateral1: float) -> void:
	var a := _weed_patch_point(f0, lateral0)
	var b := _weed_patch_point(f1, lateral1)
	var c := _weed_patch_point(f1, lateral0)
	var d := _weed_patch_point(f0, lateral1)
	_add_quad_reversed(tool, a, b, c, d, Color.WHITE)


func _weed_patch_point(fraction: float, lateral: float) -> Vector3:
	var clamped_fraction := clampf(fraction, 0.0, 1.0)
	var clamped_lateral := clampf(lateral, -_half_width_at(clamped_fraction) * 0.85,
			_half_width_at(clamped_fraction) * 0.85)
	var point := _bed_vertex(clamped_fraction, clamped_lateral)
	point.y += 0.010
	return point


func _add_ring_segment(tool: SurfaceTool, inner_a: Vector3, inner_b: Vector3,
		outer_a: Vector3, outer_b: Vector3, color: Color) -> void:
	_add_triangle(tool, inner_a, outer_a, outer_b, color)
	_add_triangle(tool, inner_a, outer_b, inner_b, color)


func _add_ring_segment_colors(tool: SurfaceTool, inner_a: Vector3, inner_b: Vector3,
		outer_a: Vector3, outer_b: Vector3, inner_color: Color,
		outer_a_color: Color, outer_b_color: Color) -> void:
	_add_triangle_colors(tool, inner_a, outer_a, outer_b,
			inner_color, outer_a_color, outer_b_color)
	_add_triangle_colors(tool, inner_a, outer_b, inner_b,
			inner_color, outer_b_color, inner_color)


func _add_blade(tool: SurfaceTool, base: Vector3, height: float, half_width: float) -> void:
	var tip := base + Vector3(0.15, height, 0.0)
	var base_left := base - Vector3(0.0, 0.0, half_width)
	var tip_right := tip + Vector3(0.0, 0.0, half_width * 0.38)
	var base_right := base + Vector3(0.0, 0.0, half_width)
	var tip_left := tip - Vector3(0.0, 0.0, half_width * 0.38)
	_add_blade_vertex(tool, base_left, Vector2(0.0, 0.0))
	_add_blade_vertex(tool, tip_right, Vector2(1.0, 1.0))
	_add_blade_vertex(tool, base_right, Vector2(1.0, 0.0))
	_add_blade_vertex(tool, base_left, Vector2(0.0, 0.0))
	_add_blade_vertex(tool, tip_left, Vector2(0.0, 1.0))
	_add_blade_vertex(tool, tip_right, Vector2(1.0, 1.0))


func _add_blade_vertex(tool: SurfaceTool, point: Vector3, uv: Vector2) -> void:
	tool.set_color(Color.WHITE)
	tool.set_uv(uv)
	tool.add_vertex(point)


func _add_multimesh(node_name: String, mesh: Mesh, transforms: Array[Transform3D], material: Material) -> void:
	if transforms.is_empty():
		return
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for i in transforms.size():
		multimesh.set_instance_transform(i, transforms[i])
	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multimesh
	instance.material_override = material
	add_child(instance)


func _commit(node_name: String, tool: SurfaceTool, material: Material) -> void:
	tool.generate_normals()
	var mesh := tool.commit()
	if mesh == null:
		return
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = material
	add_child(instance)


func _add_quad(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	_add_quad_colors(tool, a, b, c, d, color, color, color, color)


func _add_quad_reversed(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	_add_quad_reversed_colors(tool, a, b, c, d, color, color, color, color)


func _add_bank_quad(tool: SurfaceTool, side: float, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	if side > 0.0:
		_add_quad_reversed(tool, a, b, c, d, Color.WHITE)
	else:
		_add_quad(tool, a, b, c, d, Color.WHITE)


func _add_quad_colors(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		color_a: Color, color_b: Color, color_c: Color, color_d: Color) -> void:
	_add_vertex(tool, a, color_a)
	_add_vertex(tool, b, color_b)
	_add_vertex(tool, c, color_c)
	_add_vertex(tool, a, color_a)
	_add_vertex(tool, d, color_d)
	_add_vertex(tool, b, color_b)


func _add_quad_reversed_colors(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		color_a: Color, color_b: Color, color_c: Color, color_d: Color) -> void:
	_add_vertex(tool, a, color_a)
	_add_vertex(tool, c, color_c)
	_add_vertex(tool, b, color_b)
	_add_vertex(tool, a, color_a)
	_add_vertex(tool, b, color_b)
	_add_vertex(tool, d, color_d)


func _add_triangle(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	_add_vertex(tool, a, color)
	_add_vertex(tool, b, color)
	_add_vertex(tool, c, color)


func _add_triangle_colors(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		color_a: Color, color_b: Color, color_c: Color) -> void:
	_add_vertex(tool, a, color_a)
	_add_vertex(tool, b, color_b)
	_add_vertex(tool, c, color_c)


func _add_vertex(tool: SurfaceTool, point: Vector3, color: Color) -> void:
	tool.set_color(color)
	tool.set_uv(Vector2(point.x, point.z) * 0.14)
	tool.add_vertex(point)
