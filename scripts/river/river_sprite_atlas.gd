class_name RiverSpriteAtlas
extends RefCounted

const _SpriteCatalog = preload("res://scripts/assets/sprite_catalog.gd")

const TILE_SIZE := Vector2i(32, 32)

const SOURCE_PATH := "path"
const SOURCE_REGION := "region"
const SOURCE_ROTATION := "rotation"

const ROTATE_0 := 0
const ROTATE_90 := 1
const ROTATE_180 := 2
const ROTATE_270 := 3

const TRANSITION_NONE := 0
const TRANSITION_SHALLOW_MID := 1
const TRANSITION_MID_DEEP := 2
const TRANSITION_SHALLOW_DEEP := 3

const BANK_CURVES_KEY := "bank_curves"
const BOULDERS_KEY := "boulders"
const LOGS_KEY := "logs"
const SANDBARS_KEY := "sandbars"
const TERRAIN_A_KEY := "terrain_a"
const TERRAIN_B_KEY := "terrain_b"
const TERRAIN_COMBINED_KEY := "terrain_combined"
const TERRAIN_SIDE_STRIPS_KEY := "terrain_side_strips"
const TREES_KEY := "trees"
const WEED_BEDS_KEY := "weed_beds"

const TERRAIN_CAT_GRASS_BANK := "grass_bank"
const TERRAIN_CAT_GRAVEL_DIRT := "gravel_dirt"
const TERRAIN_CAT_SAND_BANK := "sand_bank"

const TREE_REGIONS: Array = [
	Rect2i(669, 88, 146, 331),
	Rect2i(421, 89, 178, 328),
	Rect2i(320, 495, 231, 346),
	Rect2i(608, 565, 201, 268),
	Rect2i(739, 991, 144, 260),
]

const SHRUB_REGIONS: Array = [
	Rect2i(820, 1188, 151, 177),
	Rect2i(1424, 1189, 175, 176),
	Rect2i(1184, 1177, 158, 188),
	Rect2i(200, 1196, 158, 169),
]

const BANK_BOULDER_REGIONS: Array = [
	Rect2i(572, 161, 105, 95),
	Rect2i(708, 176, 73, 69),
	Rect2i(1348, 251, 117, 86),
]

const IN_RIVER_ROCK_REGIONS: Array = [
	Rect2i(572, 161, 105, 95),
	Rect2i(708, 176, 73, 69),
	Rect2i(1348, 251, 117, 86),
]

const IN_RIVER_BOULDER_REGIONS: Array = [
	Rect2i(1336, 123, 120, 108),
	Rect2i(1494, 129, 131, 99),
	Rect2i(1666, 131, 118, 102),
	Rect2i(572, 161, 105, 95),
	Rect2i(708, 176, 73, 69),
	Rect2i(1348, 251, 117, 86),
]

const WEED_REGIONS: Array = [
	Rect2i(651, 474, 237, 193),
	Rect2i(232, 480, 153, 156),
	Rect2i(426, 480, 191, 176),
]

const LOG_REGIONS: Array = [
	Rect2i(963, 472, 299, 176),
	Rect2i(1256, 494, 252, 148),
	Rect2i(1807, 513, 189, 135),
]

const SHALLOW_WATER_BLOCKS: Array = [
	Rect2i(48, 140, 231, 166),
	Rect2i(48, 327, 231, 165),
	Rect2i(48, 512, 231, 166),
	Rect2i(59, 768, 238, 171),
]

const MID_WATER_BLOCKS: Array = [
	Rect2i(305, 140, 230, 166),
	Rect2i(304, 327, 231, 165),
	Rect2i(304, 512, 231, 166),
	Rect2i(331, 768, 236, 171),
	Rect2i(920, 768, 236, 171),
]

const DEEP_WATER_BLOCKS: Array = [
	Rect2i(562, 139, 228, 166),
	Rect2i(561, 327, 229, 164),
	Rect2i(561, 511, 229, 166),
	Rect2i(600, 768, 240, 170),
	Rect2i(1455, 768, 234, 170),
	Rect2i(1721, 768, 231, 172),
]

const HIGH_CURRENT_BLOCKS: Array = [
	Rect2i(1761, 1056, 224, 103),
	Rect2i(1760, 1172, 225, 122),
	Rect2i(1761, 1307, 224, 122),
	Rect2i(1760, 1441, 226, 121),
]

const SHALLOW_MID_TRANSITION_BLOCKS: Array = [
	Rect2i(859, 137, 370, 168),
	Rect2i(859, 327, 370, 165),
	Rect2i(859, 512, 370, 167),
]

const MID_DEEP_TRANSITION_BLOCKS: Array = [
	Rect2i(1251, 137, 373, 167),
	Rect2i(1250, 327, 374, 165),
	Rect2i(1250, 512, 374, 166),
]

const SHALLOW_DEEP_TRANSITION_BLOCKS: Array = [
	Rect2i(1646, 137, 371, 168),
	Rect2i(1646, 327, 371, 165),
	Rect2i(1646, 512, 371, 167),
]

static var _terrain_manifest_regions_cache: Dictionary = {}


static func base_def(tile_type: int, tx: int = 0, ty: int = 0, seed: int = 0,
		depth_class: int = -1, bank_edge: bool = false, current: float = 0.0,
		transition: int = TRANSITION_NONE, sample_size: Vector2i = TILE_SIZE,
		bank_band: int = 2, rotation_steps: int = ROTATE_0) -> Dictionary:
	var depth := _depth_for_tile(tile_type, depth_class)

	if transition != TRANSITION_NONE:
		return _def(
				_SpriteCatalog.WATER_DEPTHS_TRANSITIONS,
				_sample_block(_transition_blocks(transition), tx, ty, seed, tile_type + 1000, sample_size),
				rotation_steps)

	match tile_type:
		RiverConstants.TILE_BANK:
			return _def(
					_SpriteCatalog.RIVER_TERRAIN_ATLAS_TEXTURE,
					_pick_region(_bank_regions(bank_band, bank_edge), tx, ty, seed, tile_type),
					rotation_steps)
		RiverConstants.TILE_UNDERCUT_BANK:
			return _def(
					_SpriteCatalog.RIVER_TERRAIN_ATLAS_TEXTURE,
					_pick_region(_undercut_regions(), tx, ty, seed, tile_type),
					rotation_steps)
		RiverConstants.TILE_GRAVEL_BAR:
			return _def(
					_SpriteCatalog.RIVER_TERRAIN_ATLAS_TEXTURE,
					_pick_region(_gravel_bar_regions(), tx, ty, seed, tile_type),
					rotation_steps)
		RiverConstants.TILE_WEED_BED, RiverConstants.TILE_LOG, \
				RiverConstants.TILE_ROCK, RiverConstants.TILE_BOULDER, \
				RiverConstants.TILE_SURFACE, RiverConstants.TILE_MID_DEPTH, RiverConstants.TILE_DEEP:
			var water_blocks := HIGH_CURRENT_BLOCKS if current >= 0.72 and depth > 0 else _water_blocks(depth)
			return _def(
					_SpriteCatalog.WATER_DEPTHS_TRANSITIONS,
					_sample_block(water_blocks, tx, ty, seed, tile_type, sample_size),
					rotation_steps)

	return {}


static func atlas_path(key: String) -> String:
	match key:
		TREES_KEY:
			return _SpriteCatalog.TREES
		BOULDERS_KEY:
			return _SpriteCatalog.BOULDERS
		LOGS_KEY, WEED_BEDS_KEY:
			return _SpriteCatalog.RIVER_ENVIRONMENT_FEATURES
		SANDBARS_KEY, TERRAIN_SIDE_STRIPS_KEY, BANK_CURVES_KEY:
			return _SpriteCatalog.RIVER_TERRAIN_ATLAS_TEXTURE
	return ""


static func tree_regions() -> Array:
	return TREE_REGIONS


static func shrub_regions() -> Array:
	return SHRUB_REGIONS


static func weed_regions() -> Array:
	return WEED_REGIONS


static func log_regions() -> Array:
	return LOG_REGIONS


static func sandbar_regions() -> Array:
	return _terrain_regions(TERRAIN_CAT_SAND_BANK)


static func side_strip_regions() -> Array:
	return [
		Rect2i(1280, 832, 64, 64),
		Rect2i(1344, 832, 64, 64),
		Rect2i(1408, 832, 64, 64),
		Rect2i(1472, 832, 64, 64),
		Rect2i(1536, 832, 64, 64),
		Rect2i(1600, 832, 64, 64),
		Rect2i(1664, 832, 64, 64),
		Rect2i(1728, 840, 64, 55),
		Rect2i(1792, 840, 64, 55),
		Rect2i(1856, 840, 64, 55),
		Rect2i(1920, 840, 64, 55),
		Rect2i(1984, 840, 64, 55),
	]


static func bank_curve_regions() -> Array:
	return [
		Rect2i(1088, 910, 64, 50),
		Rect2i(1154, 897, 60, 63),
		Rect2i(1218, 897, 59, 62),
		Rect2i(1283, 897, 58, 63),
		Rect2i(1728, 924, 64, 36),
		Rect2i(1792, 900, 64, 28),
		Rect2i(1984, 923, 64, 37),
	]


static func bank_boulder_regions() -> Array:
	return BANK_BOULDER_REGIONS


static func in_river_rock_regions() -> Array:
	return IN_RIVER_ROCK_REGIONS


static func in_river_boulder_regions() -> Array:
	return IN_RIVER_BOULDER_REGIONS


static func all_base_defs() -> Array:
	var defs: Array = []
	for tile_type in [
		RiverConstants.TILE_BANK,
		RiverConstants.TILE_SURFACE,
		RiverConstants.TILE_MID_DEPTH,
		RiverConstants.TILE_DEEP,
		RiverConstants.TILE_GRAVEL_BAR,
	]:
		var def := base_def(tile_type)
		if def.is_empty():
			continue
		defs.append({
			"tile_type": tile_type,
			SOURCE_PATH: def[SOURCE_PATH],
			SOURCE_REGION: def[SOURCE_REGION],
		})
	return defs


static func _def(path: String, region: Rect2i, rotation_steps: int = ROTATE_0) -> Dictionary:
	return {
		SOURCE_PATH: path,
		SOURCE_REGION: region,
		SOURCE_ROTATION: rotation_steps,
	}


static func _bank_regions(bank_band: int, bank_edge: bool) -> Array:
	if bank_edge or bank_band <= 0:
		return _concat_regions([
			_terrain_regions(TERRAIN_CAT_SAND_BANK),
			_terrain_regions(TERRAIN_CAT_GRAVEL_DIRT),
		])
	if bank_band == 1:
		return _concat_regions([
			_terrain_regions(TERRAIN_CAT_GRASS_BANK),
			_terrain_regions(TERRAIN_CAT_GRAVEL_DIRT),
		])
	return _terrain_regions(TERRAIN_CAT_GRASS_BANK)


static func _undercut_regions() -> Array:
	return _concat_regions([
		_terrain_regions(TERRAIN_CAT_SAND_BANK),
		_terrain_regions(TERRAIN_CAT_GRAVEL_DIRT),
	])


static func _gravel_bar_regions() -> Array:
	return _concat_regions([
		_terrain_regions(TERRAIN_CAT_GRAVEL_DIRT),
		_terrain_regions(TERRAIN_CAT_SAND_BANK),
	])


static func _concat_regions(region_sets: Array) -> Array:
	var combined: Array = []
	for region_set in region_sets:
		combined.append_array(region_set as Array)
	return combined


static func _terrain_regions(category: String) -> Array:
	if _terrain_manifest_regions_cache.has(category):
		return _terrain_manifest_regions_cache[category] as Array

	var text := FileAccess.get_file_as_string(_SpriteCatalog.RIVER_TERRAIN_MANIFEST)
	if text.is_empty():
		_terrain_manifest_regions_cache[category] = []
		return []
	var parsed = JSON.parse_string(text)
	if parsed is not Array:
		_terrain_manifest_regions_cache[category] = []
		return []

	var regions: Array = []
	for entry_variant in parsed:
		var entry: Dictionary = entry_variant
		if String(entry.get("cat", "")) != category:
			continue
		var atlas_coord_variant = entry.get("atlas_coord", [])
		if atlas_coord_variant is not Array:
			continue
		var atlas_coord: Array = atlas_coord_variant
		if atlas_coord.size() < 2:
			continue
		regions.append(Rect2i(
				Vector2i(int(atlas_coord[0]) * TILE_SIZE.x, int(atlas_coord[1]) * TILE_SIZE.y),
				TILE_SIZE))

	_terrain_manifest_regions_cache[category] = regions
	return regions


static func _depth_for_tile(tile_type: int, depth_class: int) -> int:
	if depth_class >= 0:
		return clampi(depth_class, 0, 2)
	match tile_type:
		RiverConstants.TILE_SURFACE:
			return 0
		RiverConstants.TILE_DEEP, RiverConstants.TILE_BOULDER:
			return 2
	return 1


static func _water_blocks(depth_class: int) -> Array:
	match clampi(depth_class, 0, 2):
		0:
			return SHALLOW_WATER_BLOCKS
		2:
			return DEEP_WATER_BLOCKS
	return MID_WATER_BLOCKS


static func _transition_blocks(transition: int) -> Array:
	match transition:
		TRANSITION_SHALLOW_MID:
			return SHALLOW_MID_TRANSITION_BLOCKS
		TRANSITION_MID_DEEP:
			return MID_DEEP_TRANSITION_BLOCKS
		TRANSITION_SHALLOW_DEEP:
			return SHALLOW_DEEP_TRANSITION_BLOCKS
	return MID_WATER_BLOCKS


static func _sample_block(blocks: Array, tx: int, ty: int, seed: int, salt: int,
		sample_size: Vector2i = TILE_SIZE) -> Rect2i:
	var block := _pick_region(blocks, tx, ty, seed, salt)
	var sample_w := maxi(TILE_SIZE.x, sample_size.x)
	var sample_h := maxi(TILE_SIZE.y, sample_size.y)
	var cols := maxi(1, block.size.x / sample_w)
	var rows := maxi(1, block.size.y / sample_h)
	var patch_x := floori(float(tx) / 9.0)
	var patch_y := floori(float(ty) / 6.0)
	var h := _hash_int(patch_x, patch_y, seed ^ salt)
	var ox := (h % cols) * sample_w
	var oy := ((h / cols) % rows) * sample_h
	return Rect2i(block.position + Vector2i(ox, oy), Vector2i(sample_w, sample_h))


static func _pick_region(regions: Array, tx: int, ty: int, seed: int, salt: int) -> Rect2i:
	if regions.is_empty():
		return Rect2i(Vector2i.ZERO, TILE_SIZE)
	var idx := _hash_int(tx / 3, ty / 2, seed ^ salt) % regions.size()
	return regions[idx] as Rect2i


static func _hash_int(x: int, y: int, seed: int) -> int:
	var h: int = (x * 1619 + y * 31337 + seed * 6971) & 0x7FFFFFFF
	h ^= h >> 16
	h = (h * 0x45d9f3b) & 0x7FFFFFFF
	h ^= h >> 16
	return h & 0x7FFFFFFF
