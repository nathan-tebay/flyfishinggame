class_name LowerMadisonReach
extends RefCounted

# Geometry source: selected NHD high-resolution artificial-path centerline inside
# the Madison River area polygon, immediately upstream of Black's Ford FAS.
const FLOWLINE_PATH := "res://assets/3d/geodata/lower_madison_nhd_flowline.geojson"
const TERRAIN_PATH := "res://assets/3d/geodata/lower_madison_3dep_samples.json"
const METERS_PER_LATITUDE_DEGREE := 110540.0
const LONGITUDINAL_SCALE := 0.40
const CROSS_CHANNEL_SCALE := 0.85
const TERRAIN_VERTICAL_SCALE := 0.15
const TERRAIN_BASE_ELEVATION_M := 1343.84
const WATER_HEIGHT := 0.05
const STATION_STEP := 4.0
const WADABLE_DEPTH_LIMIT := 0.82
const DEPTH_DEBUG_MAX := 1.35
# NHD artificial-path corners are valid centerline reference points, but a wide
# rendered river offset directly from their short-segment normals can fold over
# itself at bends. Smooth bank/channel frames while retaining the source path.
const FRAME_TANGENT_RADIUS := 48.0

const STRUCTURES := [
	{"kind": "boulder", "fraction": 0.20, "lateral": -1.8, "radius": 0.82},
	{"kind": "boulder", "fraction": 0.24, "lateral": 3.3, "radius": 0.60},
	{"kind": "boulder", "fraction": 0.40, "lateral": 6.4, "radius": 0.92},
	{"kind": "boulder", "fraction": 0.63, "lateral": -5.2, "radius": 0.68},
	{"kind": "boulder", "fraction": 0.68, "lateral": -1.4, "radius": 0.52},
	{"kind": "driftwood", "fraction": 0.54, "lateral": -14.4, "length": 4.7},
]
const GRAVEL_BARS := [
	{"fraction": 0.16, "lateral": 10.2, "length": 22.0, "width": 4.2},
	{"fraction": 0.76, "lateral": -10.8, "length": 31.0, "width": 5.0},
	{"fraction": 0.90, "lateral": 9.8, "length": 18.0, "width": 3.8},
]
const DEEP_POOLS := [
	{"fraction": 0.24, "lateral": 3.2, "length": 18.0, "width": 4.8, "extra_depth": 0.22, "kind": "boulder-pocket hole"},
	{"fraction": 0.38, "lateral": 5.5, "length": 34.0, "width": 6.5, "extra_depth": 0.34, "kind": "outside-bend pool"},
	{"fraction": 0.52, "lateral": 7.2, "length": 44.0, "width": 7.2, "extra_depth": 0.42, "kind": "deep seam pool"},
	{"fraction": 0.66, "lateral": -7.4, "length": 30.0, "width": 5.8, "extra_depth": 0.36, "kind": "bank-pocket hole"},
	{"fraction": 0.79, "lateral": 1.6, "length": 28.0, "width": 5.6, "extra_depth": 0.28, "kind": "main-run hole"},
]
const WEED_BEDS := [
	{"fraction": 0.45, "lateral": -4.5, "length": 34.0, "width": 4.8},
	{"fraction": 0.57, "lateral": 5.0, "length": 27.0, "width": 4.0},
]
const TREE_CLUSTERS := [
	{"fraction": 0.08, "lateral": -28.0, "scale": 2.8},
	{"fraction": 0.12, "lateral": -36.0, "scale": 3.3},
	{"fraction": 0.29, "lateral": 30.0, "scale": 2.7},
	{"fraction": 0.32, "lateral": 39.0, "scale": 3.2},
	{"fraction": 0.51, "lateral": 31.0, "scale": 3.6},
	{"fraction": 0.55, "lateral": 41.0, "scale": 2.8},
	{"fraction": 0.69, "lateral": -32.0, "scale": 3.5},
	{"fraction": 0.74, "lateral": -42.0, "scale": 2.9},
	{"fraction": 0.88, "lateral": 34.0, "scale": 3.4},
]
const WILLOW_CLUSTERS := [
	{"fraction": 0.06, "lateral": 18.5, "scale": 1.2},
	{"fraction": 0.18, "lateral": -18.2, "scale": 1.0},
	{"fraction": 0.31, "lateral": 18.0, "scale": 1.3},
	{"fraction": 0.47, "lateral": -19.2, "scale": 1.2},
	{"fraction": 0.60, "lateral": 19.0, "scale": 1.0},
	{"fraction": 0.72, "lateral": -18.0, "scale": 1.35},
	{"fraction": 0.84, "lateral": 18.5, "scale": 1.15},
]
const HOLD_ANCHORS := [
	{"fraction": 0.22, "lateral": -2.8, "habitat": "boulder pocket"},
	{"fraction": 0.25, "lateral": 4.4, "habitat": "boulder pocket"},
	{"fraction": 0.37, "lateral": 2.8, "habitat": "deeper seam"},
	{"fraction": 0.43, "lateral": 6.0, "habitat": "boulder pocket"},
	{"fraction": 0.48, "lateral": -6.2, "habitat": "weed edge"},
	{"fraction": 0.54, "lateral": 6.4, "habitat": "weed edge"},
	{"fraction": 0.62, "lateral": -8.5, "habitat": "bank pocket"},
	{"fraction": 0.68, "lateral": -2.1, "habitat": "boulder pocket"},
	{"fraction": 0.79, "lateral": 1.5, "habitat": "main run"},
	{"fraction": 0.88, "lateral": -5.0, "habitat": "gravel shallows"},
]

var source_centerline: Array = []
var stations: Array = []
var terrain_data: Dictionary = {}
var _geo_origin := Vector2.ZERO
var _downstream := Vector2.RIGHT
var _crossstream := Vector2.DOWN
var _length := 0.0


func _init() -> void:
	_load_source_centerline()
	_build_stations()
	_load_terrain_samples()


func station_count() -> int:
	return stations.size()


func station_at(index: int) -> Dictionary:
	return stations[clampi(index, 0, stations.size() - 1)] as Dictionary


func length() -> float:
	return _length


func segment_count(segment_length_m: float) -> int:
	return max(1, int(ceil(_length / maxf(segment_length_m, 1.0))))


func segment_fraction_range(segment_index: int, segment_length_m: float, overlap_m: float = 0.0) -> Vector2:
	var count := segment_count(segment_length_m)
	var clamped_index := clampi(segment_index, 0, count - 1)
	var safe_length := maxf(segment_length_m, 1.0)
	var start_distance := maxf(0.0, float(clamped_index) * safe_length - maxf(overlap_m, 0.0))
	var end_distance := minf(_length, float(clamped_index + 1) * safe_length + maxf(overlap_m, 0.0))
	if _length <= 0.0:
		return Vector2.ZERO
	return Vector2(start_distance / _length, end_distance / _length)


func segment_index_for_world_pos(world_pos: Vector3, segment_length_m: float) -> int:
	var nearest := _nearest_channel_frame(Vector2(world_pos.x, world_pos.z))
	var safe_length := maxf(segment_length_m, 1.0)
	return clampi(
		int(floor(float(nearest["fraction"]) * _length / safe_length)),
		0,
		segment_count(safe_length) - 1
	)


func world_bounds() -> Rect2:
	var bounds := Rect2(source_centerline[0] as Vector2, Vector2.ZERO)
	for point in source_centerline:
		bounds = bounds.expand(point as Vector2)
	return bounds.grow(92.0)


func structures() -> Array:
	return STRUCTURES


func gravel_bars() -> Array:
	return GRAVEL_BARS


func weed_beds() -> Array:
	return WEED_BEDS


func tree_clusters() -> Array:
	return TREE_CLUSTERS


func willow_clusters() -> Array:
	return WILLOW_CLUSTERS


func hold_points() -> Array:
	return HOLD_ANCHORS


func position_at(fraction: float, lateral: float, height: float = WATER_HEIGHT) -> Vector3:
	var frame := frame_at_fraction(fraction)
	var point: Vector2 = frame["position"] + (frame["normal"] as Vector2) * lateral
	return Vector3(point.x, height, point.y)


func frame_at_fraction(fraction: float) -> Dictionary:
	var target := clampf(fraction, 0.0, 1.0) * _length
	if target <= 0.0:
		return stations[0] as Dictionary
	for i in range(stations.size() - 1):
		var current := stations[i] as Dictionary
		var next := stations[i + 1] as Dictionary
		var next_distance: float = next["distance"]
		if target > next_distance:
			continue
		var interval: float = next_distance - float(current["distance"])
		var weight := 0.0 if interval <= 0.0 else (target - float(current["distance"])) / interval
		var tangent := ((current["tangent"] as Vector2).lerp(next["tangent"] as Vector2, weight)).normalized()
		return {
			"position": (current["position"] as Vector2).lerp(next["position"] as Vector2, weight),
			"tangent": tangent,
			"normal": Vector2(-tangent.y, tangent.x),
			"fraction": clampf(fraction, 0.0, 1.0),
			"distance": target,
			"half_width": lerpf(float(current["half_width"]), float(next["half_width"]), weight),
		}
	return stations[-1] as Dictionary


func half_width_at(fraction: float) -> float:
	var base := 15.2
	base += sin(fraction * PI) * 2.6
	base += sin(fraction * TAU * 2.3 + 0.4) * 0.8
	if fraction > 0.32 and fraction < 0.60:
		base += 1.8
	return base


func sample(world_pos: Vector3) -> Dictionary:
	var horizontal := Vector2(world_pos.x, world_pos.z)
	var nearest := _nearest_channel_frame(horizontal)
	var lateral: float = nearest["lateral"]
	var fraction: float = nearest["fraction"]
	var half_width: float = half_width_at(fraction)
	var exposed_bar := _is_exposed_bar(horizontal)
	var is_water := absf(lateral) <= half_width and not exposed_bar
	var habitat := "gravel bar" if exposed_bar else "dry bank"
	var depth := 0.0
	var strength := 0.0
	var flow := Vector3.ZERO
	var turbulence := 0.0
	var foam := 0.0
	var curvature := curvature_at_fraction(fraction)
	if is_water:
		habitat = habitat_at(fraction, lateral)
		depth = water_depth_at(fraction, lateral)
		strength = current_strength_at(fraction, lateral)
		flow = surface_flow_at(fraction, lateral)
		turbulence = visual_turbulence_at(fraction, lateral)
		foam = foam_tendency_at(fraction, lateral)
	var flow_direction := Vector3.ZERO
	if flow.length_squared() > 0.0001:
		flow_direction = flow.normalized()
	return {
		"is_water": is_water,
		"is_wadable": not is_water or depth <= WADABLE_DEPTH_LIMIT,
		"water_surface": WATER_HEIGHT,
		"bed_height": WATER_HEIGHT - depth if is_water else terrain_height_at(world_pos),
		"depth": depth,
		"depth_band": depth_band_for_depth(depth, is_water),
		"current_strength": strength,
		"current_vector": flow,
		"surface_flow_direction": flow_direction,
		"visual_turbulence": turbulence,
		"foam_tendency": foam,
		"curvature": curvature,
		"habitat": habitat,
		"fraction": fraction,
		"lateral": lateral,
		"half_width": half_width,
	}


func is_water(world_pos: Vector3) -> bool:
	return bool(sample(world_pos)["is_water"])


func is_wadable(world_pos: Vector3) -> bool:
	var query := sample(world_pos)
	if not bool(query["is_water"]):
		return true
	return bool(query["is_wadable"])


func terrain_height_at(world_pos: Vector3) -> float:
	if _is_exposed_bar(Vector2(world_pos.x, world_pos.z)):
		return WATER_HEIGHT + 0.035
	var nearest := _nearest_channel_frame(Vector2(world_pos.x, world_pos.z))
	var bank_distance := maxf(absf(float(nearest["lateral"])) - half_width_at(float(nearest["fraction"])), 0.0)
	return WATER_HEIGHT + 0.10 + minf(bank_distance * 0.038, 0.58)


func water_depth_at(fraction: float, lateral: float) -> float:
	var across := clampf(absf(lateral) / half_width_at(fraction), 0.0, 1.0)
	var center_depth := 0.64
	if fraction < 0.30:
		center_depth = 0.36
	elif fraction < 0.60:
		center_depth = 0.92
	elif fraction < 0.73:
		center_depth = 0.74
	elif fraction < 0.86:
		center_depth = 0.57
	else:
		center_depth = 0.39
	var seam_shift := smoothstep(0.26, 0.60, fraction) * (1.0 - smoothstep(0.60, 0.80, fraction))
	var outside_seam := smoothstep(0.15, 0.58, lateral / half_width_at(fraction)) * seam_shift * 0.22
	var pool_depth := _deep_pool_extra_depth(fraction, lateral)
	var boulder_scour := _boulder_influence(fraction, lateral) * 0.12
	var shoal_lift := _bar_shoal_influence(fraction, lateral) * 0.42
	var section_depth := center_depth + outside_seam + pool_depth + boulder_scour - shoal_lift
	return maxf(0.045, lerpf(0.08, section_depth, pow(1.0 - across, 0.65)))


func current_strength_at(fraction: float, lateral: float) -> float:
	var habitat := habitat_at(fraction, lateral)
	var base := 0.62
	match habitat:
		"shallow riffle":
			base = 0.90
		"deeper seam":
			base = 0.67
		"bank pocket", "boulder pocket":
			base = 0.33
		"weed edge":
			base = 0.45
		"gravel shallows":
			base = 0.52
		"deep pool":
			base = 0.38
		"deep seam pool":
			base = 0.50
	var shoal_push := _bar_shoal_influence(fraction, lateral) * 0.10
	var pool_slow := _deep_pool_influence(fraction, lateral) * 0.14
	var curvature_push := curvature_at_fraction(fraction) * 0.08
	return clampf(base + shoal_push + curvature_push - pool_slow, 0.20, 0.96)


func habitat_at(fraction: float, lateral: float) -> String:
	for structure in STRUCTURES:
		var sd := structure as Dictionary
		if sd["kind"] != "boulder":
			continue
		if absf(fraction - float(sd["fraction"])) < 0.034 and absf(lateral - float(sd["lateral"])) < float(sd["radius"]) + 2.2:
			return "boulder pocket"
	var pool_kind := _dominant_pool_kind(fraction, lateral)
	if pool_kind == "deep seam pool":
		return "deep seam pool"
	if pool_kind != "":
		return "deep pool"
	if fraction >= 0.42 and fraction <= 0.62 and lateral < -1.0:
		return "weed edge"
	if fraction >= 0.54 and fraction <= 0.72 and lateral < -half_width_at(fraction) * 0.53:
		return "bank pocket"
	if fraction < 0.30:
		return "shallow riffle"
	if fraction < 0.60 and lateral > 0.4:
		return "deeper seam"
	if fraction > 0.84 or absf(lateral) > half_width_at(fraction) * 0.72:
		return "gravel shallows"
	return "main run"


func depth_band_for_depth(depth: float, is_water: bool = true) -> String:
	if not is_water:
		return "dry"
	if depth <= 0.18:
		return "ankle"
	if depth <= 0.38:
		return "shin"
	if depth <= 0.62:
		return "knee"
	if depth <= WADABLE_DEPTH_LIMIT:
		return "thigh"
	return "non-wadable"


func visual_turbulence_at(fraction: float, lateral: float) -> float:
	var depth := water_depth_at(fraction, lateral)
	var shallow := 1.0 - clampf(depth / WADABLE_DEPTH_LIMIT, 0.0, 1.0)
	var speed := current_strength_at(fraction, lateral)
	var boulder := _boulder_influence(fraction, lateral)
	var shoal := _bar_shoal_influence(fraction, lateral)
	var pool := _deep_pool_influence(fraction, lateral)
	var bend := curvature_at_fraction(fraction)
	var turbulence := speed * 0.42 + shallow * 0.25 + boulder * 0.30 + shoal * 0.18 + bend * 0.20
	turbulence -= pool * 0.12
	return clampf(turbulence, 0.0, 1.0)


func foam_tendency_at(fraction: float, lateral: float) -> float:
	var turbulence := visual_turbulence_at(fraction, lateral)
	var boulder := _boulder_influence(fraction, lateral)
	var shoal := _bar_shoal_influence(fraction, lateral)
	var riffle_bonus := 0.20 if habitat_at(fraction, lateral) == "shallow riffle" else 0.0
	var source := turbulence + boulder * 0.24 + shoal * 0.12 + riffle_bonus
	return smoothstep(0.72, 1.05, source)


func curvature_at_fraction(fraction: float) -> float:
	var before: Vector2 = frame_at_fraction(fraction - 0.035)["tangent"]
	var after: Vector2 = frame_at_fraction(fraction + 0.035)["tangent"]
	return clampf(absf(before.cross(after)) * 4.2, 0.0, 1.0)


func surface_flow_at(fraction: float, lateral: float) -> Vector3:
	var frame := frame_at_fraction(fraction)
	var tangent: Vector2 = frame["tangent"]
	var normal: Vector2 = frame["normal"]
	var half_width := half_width_at(fraction)
	var cross_fraction := clampf(lateral / half_width, -1.0, 1.0)
	var seam_push := smoothstep(0.30, 0.58, fraction) * (1.0 - smoothstep(0.58, 0.82, fraction)) * 0.10
	var side := 0.0
	if lateral > 0.0:
		side = 1.0
	if lateral < 0.0:
		side = -1.0
	var bar_push := -side * _bar_shoal_influence(fraction, lateral) * 0.08
	var boulder_push := _boulder_deflection(fraction, lateral) * 0.16
	var bank_pull := -cross_fraction * 0.05
	var direction := (tangent + normal * (seam_push + bar_push + boulder_push + bank_pull)).normalized()
	var strength := current_strength_at(fraction, lateral)
	return Vector3(direction.x, 0.0, direction.y) * strength


func _deep_pool_extra_depth(fraction: float, lateral: float) -> float:
	var extra_depth := 0.0
	for pool in DEEP_POOLS:
		var pd := pool as Dictionary
		extra_depth += _feature_influence(fraction, lateral, pd) * float(pd["extra_depth"])
	return extra_depth


func _deep_pool_influence(fraction: float, lateral: float) -> float:
	var best := 0.0
	for pool in DEEP_POOLS:
		best = maxf(best, _feature_influence(fraction, lateral, pool as Dictionary))
	return best


func _dominant_pool_kind(fraction: float, lateral: float) -> String:
	var best := 0.0
	var kind := ""
	for pool in DEEP_POOLS:
		var pd := pool as Dictionary
		var influence := _feature_influence(fraction, lateral, pd)
		if influence <= best:
			continue
		best = influence
		kind = String(pd["kind"])
	if best < 0.42:
		return ""
	return kind


func _boulder_influence(fraction: float, lateral: float) -> float:
	var best := 0.0
	for structure in STRUCTURES:
		var sd := structure as Dictionary
		if sd["kind"] != "boulder":
			continue
		var boulder := {
			"fraction": float(sd["fraction"]),
			"lateral": float(sd["lateral"]),
			"length": float(sd["radius"]) * 9.0 + 8.0,
			"width": float(sd["radius"]) * 5.5 + 4.0,
		}
		best = maxf(best, _feature_influence(fraction, lateral, boulder))
	return best


func _boulder_deflection(fraction: float, lateral: float) -> float:
	var push := 0.0
	for structure in STRUCTURES:
		var sd := structure as Dictionary
		if sd["kind"] != "boulder":
			continue
		var boulder := {
			"fraction": float(sd["fraction"]),
			"lateral": float(sd["lateral"]),
			"length": float(sd["radius"]) * 9.0 + 8.0,
			"width": float(sd["radius"]) * 5.5 + 4.0,
		}
		var influence := _feature_influence(fraction, lateral, boulder)
		if influence <= 0.0:
			continue
		var lateral_delta := lateral - float(sd["lateral"])
		var push_side := 1.0
		if lateral_delta < 0.0:
			push_side = -1.0
		push += push_side * influence
	return clampf(push, -1.0, 1.0)


func _bar_shoal_influence(fraction: float, lateral: float) -> float:
	var best := 0.0
	for bar in GRAVEL_BARS:
		var bd := bar as Dictionary
		var length := float(bd["length"]) + 7.0
		var width := float(bd["width"]) + 4.6
		var feature := {
			"fraction": float(bd["fraction"]),
			"lateral": float(bd["lateral"]),
			"length": length,
			"width": width,
		}
		var measure := _feature_measure(fraction, lateral, feature)
		if measure <= 1.0:
			best = maxf(best, 1.0)
			continue
		if measure > 2.2:
			continue
		var falloff := clampf((2.2 - measure) / 1.2, 0.0, 1.0)
		var eased := falloff * falloff * (3.0 - 2.0 * falloff)
		best = maxf(best, eased * 0.70)
	return best


func _feature_influence(fraction: float, lateral: float, feature: Dictionary) -> float:
	var measure := _feature_measure(fraction, lateral, feature)
	if measure >= 1.0:
		return 0.0
	return pow(1.0 - measure, 1.35)


func _feature_measure(fraction: float, lateral: float, feature: Dictionary) -> float:
	var length_fraction := maxf(float(feature["length"]) / maxf(_length, 1.0), 0.001)
	var along := (fraction - float(feature["fraction"])) / (length_fraction * 0.5)
	var across := (lateral - float(feature["lateral"])) / maxf(float(feature["width"]) * 0.5, 0.001)
	return along * along + across * across


func nearest_hold_distance(world_pos: Vector3) -> float:
	var best := INF
	for hold in HOLD_ANCHORS:
		var hd := hold as Dictionary
		best = minf(best, world_pos.distance_to(position_at(float(hd["fraction"]), float(hd["lateral"]))))
	return best


func start_position() -> Vector3:
	var point := position_at(0.69, -half_width_at(0.69) - 6.2, 0.0)
	point.y = terrain_height_at(point)
	return point


func look_target_from_start() -> Vector3:
	return position_at(0.73, 2.0, WATER_HEIGHT)


func terrain_row_count() -> int:
	return (terrain_data.get("elevations_m", []) as Array).size()


func terrain_column_count() -> int:
	var rows := terrain_data.get("elevations_m", []) as Array
	return 0 if rows.is_empty() else (rows[0] as Array).size()


func terrain_grid_point(row: int, column: int) -> Vector3:
	var rows := terrain_data["sample_rows"] as Array
	var columns := terrain_data["sample_columns"] as Array
	var bbox := terrain_data["bbox_wgs84"] as Array
	var lon := lerpf(float(bbox[0]), float(bbox[2]), float(columns[column]) / 127.0)
	var lat := lerpf(float(bbox[3]), float(bbox[1]), float(rows[row]) / 127.0)
	var point := _geo_to_local(Vector2(lon, lat))
	var elevations := terrain_data["elevations_m"] as Array
	var elevation := float((elevations[row] as Array)[column])
	var height := maxf((elevation - TERRAIN_BASE_ELEVATION_M) * TERRAIN_VERTICAL_SCALE, WATER_HEIGHT + 0.16)
	return Vector3(point.x, height, point.y)


func is_channel_corridor(point: Vector2, margin: float = 0.0) -> bool:
	var nearest := _nearest_channel_frame(point)
	return absf(float(nearest["lateral"])) < half_width_at(float(nearest["fraction"])) + margin


func _is_exposed_bar(point: Vector2) -> bool:
	for bar in GRAVEL_BARS:
		var bd := bar as Dictionary
		var frame := frame_at_fraction(float(bd["fraction"]))
		var delta := point - (frame["position"] as Vector2) - (frame["normal"] as Vector2) * float(bd["lateral"])
		var along := delta.dot(frame["tangent"] as Vector2) / (float(bd["length"]) * 0.5)
		var across := delta.dot(frame["normal"] as Vector2) / (float(bd["width"]) * 0.5)
		if along * along + across * across <= 1.0:
			return true
	return false


func _load_source_centerline() -> void:
	var parsed := _read_json(FLOWLINE_PATH)
	var feature := (parsed["features"] as Array)[0] as Dictionary
	var geometry := feature["geometry"] as Dictionary
	var coordinates := geometry["coordinates"] as Array
	var origin := coordinates[0] as Array
	var endpoint := coordinates[-1] as Array
	_geo_origin = Vector2(float(origin[0]), float(origin[1]))
	var end_meters := _geo_to_meters(Vector2(float(endpoint[0]), float(endpoint[1])))
	_downstream = end_meters.normalized()
	_crossstream = Vector2(-_downstream.y, _downstream.x)
	for coordinate in coordinates:
		var item := coordinate as Array
		source_centerline.append(_geo_to_local(Vector2(float(item[0]), float(item[1]))))


func _build_stations() -> void:
	var distances: Array = [0.0]
	var total := 0.0
	for i in range(1, source_centerline.size()):
		total += (source_centerline[i] as Vector2).distance_to(source_centerline[i - 1] as Vector2)
		distances.append(total)
	_length = total
	var station_distance := 0.0
	while station_distance < _length:
		_append_station(_point_on_line(station_distance, distances), station_distance)
		station_distance += STATION_STEP
	_append_station(source_centerline[-1] as Vector2, _length)
	for i in stations.size():
		var distance: float = (stations[i] as Dictionary)["distance"]
		var before := _point_on_line(maxf(distance - FRAME_TANGENT_RADIUS, 0.0), distances)
		var after := _point_on_line(minf(distance + FRAME_TANGENT_RADIUS, _length), distances)
		var tangent := (after - before).normalized()
		(stations[i] as Dictionary)["tangent"] = tangent
		(stations[i] as Dictionary)["normal"] = Vector2(-tangent.y, tangent.x)


func _append_station(point: Vector2, distance: float) -> void:
	var fraction := 0.0 if _length <= 0.0 else distance / _length
	stations.append({
		"position": point,
		"distance": distance,
		"fraction": fraction,
		"half_width": half_width_at(fraction),
		"tangent": Vector2.RIGHT,
		"normal": Vector2.DOWN,
	})


func _point_on_line(distance: float, distances: Array) -> Vector2:
	for i in range(source_centerline.size() - 1):
		if distance > float(distances[i + 1]):
			continue
		var interval := float(distances[i + 1]) - float(distances[i])
		var weight := 0.0 if interval <= 0.0 else (distance - float(distances[i])) / interval
		return (source_centerline[i] as Vector2).lerp(source_centerline[i + 1] as Vector2, weight)
	return source_centerline[-1] as Vector2


func _nearest_channel_frame(point: Vector2) -> Dictionary:
	var best_distance := INF
	var best := stations[0].duplicate() as Dictionary
	for i in range(stations.size() - 1):
		var current := stations[i] as Dictionary
		var next := stations[i + 1] as Dictionary
		var a := current["position"] as Vector2
		var b := next["position"] as Vector2
		var delta := b - a
		var weight := clampf((point - a).dot(delta) / maxf(delta.length_squared(), 0.001), 0.0, 1.0)
		var nearest := a + delta * weight
		var distance := point.distance_squared_to(nearest)
		if distance >= best_distance:
			continue
		best_distance = distance
		var fraction := lerpf(float(current["fraction"]), float(next["fraction"]), weight)
		var channel_frame := frame_at_fraction(fraction)
		var tangent: Vector2 = channel_frame["tangent"]
		var normal: Vector2 = channel_frame["normal"]
		var center: Vector2 = channel_frame["position"]
		best = {
			"position": center,
			"tangent": tangent,
			"normal": normal,
			"fraction": fraction,
			"distance": lerpf(float(current["distance"]), float(next["distance"]), weight),
			"lateral": (point - center).dot(normal),
		}
	return best


func _load_terrain_samples() -> void:
	terrain_data = _read_json(TERRAIN_PATH)


func _geo_to_local(geo: Vector2) -> Vector2:
	var meters := _geo_to_meters(geo)
	return Vector2(meters.dot(_downstream) * LONGITUDINAL_SCALE, meters.dot(_crossstream) * CROSS_CHANNEL_SCALE)


func _geo_to_meters(geo: Vector2) -> Vector2:
	var longitude_scale := 111320.0 * cos(deg_to_rad(_geo_origin.y))
	return Vector2((geo.x - _geo_origin.x) * longitude_scale, (geo.y - _geo_origin.y) * METERS_PER_LATITUDE_DEGREE)


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Unable to open authored reach data: %s" % path)
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return parsed as Dictionary
	push_error("Unable to parse authored reach data: %s" % path)
	return {}
