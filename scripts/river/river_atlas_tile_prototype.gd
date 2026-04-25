class_name RiverAtlasTilePrototype
extends TileMap

const _RiverConstants = preload("res://scripts/river/river_constants.gd")
const _SpriteCatalog = preload("res://scripts/assets/sprite_catalog.gd")

const SOURCE_ID := 0
const INVALID_ATLAS_COORD := Vector2i(-1, -1)

const _CATEGORY_BY_TILE_TYPE := {
	_RiverConstants.TILE_BANK: "grass_bank",
	_RiverConstants.TILE_UNDERCUT_BANK: "sand_bank",
	_RiverConstants.TILE_GRAVEL_BAR: "gravel_dirt",
	_RiverConstants.TILE_SURFACE: "shallow_water",
	_RiverConstants.TILE_WEED_BED: "medium_water",
	_RiverConstants.TILE_ROCK: "medium_water",
	_RiverConstants.TILE_LOG: "medium_water",
	_RiverConstants.TILE_MID_DEPTH: "medium_water",
	_RiverConstants.TILE_BOULDER: "deep_water",
	_RiverConstants.TILE_DEEP: "deep_water",
}

var _atlas_coords_by_category: Dictionary = {}


func render(data: RiverData) -> void:
	if not _ensure_tileset():
		return
	clear()

	for tx in range(data.width):
		for ty in range(data.height):
			var tile_type: int = data.tile_map[tx][ty]
			if tile_type == _RiverConstants.TILE_AIR:
				continue
			var atlas_coord := _atlas_coord_for_tile(tile_type, tx, ty, data.seed)
			if atlas_coord == INVALID_ATLAS_COORD:
				continue
			set_cell(0, Vector2i(tx, ty), SOURCE_ID, atlas_coord)


func _ensure_tileset() -> bool:
	if tile_set != null and not _atlas_coords_by_category.is_empty():
		return true

	var terrain_tileset = load(_SpriteCatalog.RIVER_TERRAIN_TILESET) as TileSet
	if terrain_tileset == null:
		push_warning("Atlas tile prototype could not load %s" % _SpriteCatalog.RIVER_TERRAIN_TILESET)
		return false
	tile_set = terrain_tileset.duplicate(true)

	_atlas_coords_by_category = _load_manifest_coords()
	if _atlas_coords_by_category.is_empty():
		push_warning("Atlas tile prototype could not read %s" % _SpriteCatalog.RIVER_TERRAIN_MANIFEST)
		return false
	return true


func _load_manifest_coords() -> Dictionary:
	var text := FileAccess.get_file_as_string(_SpriteCatalog.RIVER_TERRAIN_MANIFEST)
	if text.is_empty():
		return {}

	var parsed = JSON.parse_string(text)
	if parsed is not Array:
		return {}

	var coords_by_category := {}
	for entry_variant in parsed:
		var entry: Dictionary = entry_variant
		var category := String(entry.get("cat", ""))
		var atlas_coord_variant = entry.get("atlas_coord", [])
		if category.is_empty() or atlas_coord_variant is not Array:
			continue
		var atlas_coord: Array = atlas_coord_variant
		if atlas_coord.size() < 2:
			continue
		if not coords_by_category.has(category):
			coords_by_category[category] = []
		(coords_by_category[category] as Array).append(Vector2i(
				int(atlas_coord[0]),
				int(atlas_coord[1])))
	return coords_by_category


func _atlas_coord_for_tile(tile_type: int, tx: int, ty: int, seed: int) -> Vector2i:
	if not _CATEGORY_BY_TILE_TYPE.has(tile_type):
		return INVALID_ATLAS_COORD
	var category := String(_CATEGORY_BY_TILE_TYPE[tile_type])
	if not _atlas_coords_by_category.has(category):
		return INVALID_ATLAS_COORD
	var coords: Array = _atlas_coords_by_category[category]
	if coords.is_empty():
		return INVALID_ATLAS_COORD
	var idx := _hash(tx, ty, seed ^ tile_type) % coords.size()
	return coords[idx] as Vector2i


func _hash(x: int, y: int, seed: int) -> int:
	var h: int = (x * 1619 + y * 31337 + seed * 6971) & 0x7FFFFFFF
	h ^= h >> 16
	h = (h * 0x45d9f3b) & 0x7FFFFFFF
	h ^= h >> 16
	return h & 0x7FFFFFFF
