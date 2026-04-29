class_name RiverRenderer
extends TileMap  # kept for scene-tree compatibility; tile layers are unused

const _SpriteCatalog = preload("res://scripts/assets/sprite_catalog.gd")
const _RiverSpriteAtlas = preload("res://scripts/river/river_sprite_atlas.gd")

const BANK_TREE_CHANCE := 0.025
const BANK_GRASS_CHANCE := 0.18
const BANK_BOULDER_CHANCE := 0.07

# River rendered from authored multi-cell water and shoreline modules.
#
# Pipeline per section:
#   1. RiverData remains the gameplay/source map.
#   2. General land fill comes from terrain tiles under assets/terrain.
#   3. Water depth and shoreline come from authored 64x64 runtime modules.
#   3. Trees, boulders, logs, weeds, and other props remain on the sprite path.

const _TILE_POOL_DIRS := {
	"terrain_grass": _SpriteCatalog.TERRAIN_TILE_ROOT + "/grass",
	"terrain_dirt": _SpriteCatalog.TERRAIN_TILE_ROOT + "/dirt",
	"terrain_gravel": _SpriteCatalog.TERRAIN_TILE_ROOT + "/gravel",
	"terrain_sand": _SpriteCatalog.TERRAIN_TILE_ROOT + "/sand",
	"shoreline_edge": _SpriteCatalog.MODULE_TILE_ROOT + "/shoreline/edge",
	"shoreline_outer_corner": _SpriteCatalog.MODULE_TILE_ROOT + "/shoreline/outer_corner",
	"shoreline_inner_corner": _SpriteCatalog.MODULE_TILE_ROOT + "/shoreline/inner_corner",
	"water_shallow": _SpriteCatalog.MODULE_TILE_ROOT + "/water/shallow",
	"water_mid": _SpriteCatalog.MODULE_TILE_ROOT + "/water/mid",
	"water_deep": _SpriteCatalog.MODULE_TILE_ROOT + "/water/deep",
	"transition_shallow_mid": _SpriteCatalog.RUNTIME_TILE_ROOT + "/water/transitions/shallow_to_mid",
	"transition_mid_deep": _SpriteCatalog.RUNTIME_TILE_ROOT + "/water/transitions/mid_to_deep",
	"gravel_bar": _SpriteCatalog.MODULE_TILE_ROOT + "/gravel_bar",
}

const _WATER_POOL_BY_DEPTH_CLASS := {
	0: "water_shallow",
	1: "water_mid",
	2: "water_deep",
}

const _TRANSITION_POOL_BY_KIND := {
	_RiverSpriteAtlas.TRANSITION_SHALLOW_MID: "transition_shallow_mid",
	_RiverSpriteAtlas.TRANSITION_MID_DEEP: "transition_mid_deep",
	_RiverSpriteAtlas.TRANSITION_SHALLOW_DEEP: "transition_shallow_deep",
}

const _BANK_MATERIAL_SAND := 0
const _BANK_MATERIAL_GRAVEL := 1
const _BANK_MATERIAL_GRASS := 2
const _MODULE_TILE_SIZE := RiverConstants.TILE_SIZE * 2
const _CORNER_WATER_TL := 0
const _CORNER_WATER_TR := 1
const _CORNER_WATER_BL := 2
const _CORNER_WATER_BR := 3

const _SHORELINE_CORNER_INDICES_BY_WATER_QUADRANT := {
	_CORNER_WATER_TL: [6, 7],
	_CORNER_WATER_TR: [4, 5],
	_CORNER_WATER_BL: [2, 3],
	_CORNER_WATER_BR: [0, 1],
}

const _MANIFEST_CATEGORY_BY_POOL := {
	"water_shallow": "water_shallow",
	"water_mid": "water_mid",
	"water_deep": "water_deep",
	"transition_shallow_mid": "transition_shallow_mid",
	"transition_mid_deep": "transition_mid_deep",
	"transition_shallow_deep": "transition_shallow_deep",
	"shoreline_edge": "shoreline_edge",
	"shoreline_outer_corner": "shoreline_outer_corner",
	"shoreline_inner_corner": "shoreline_inner_corner",
	"gravel_bar": "gravel_bar",
	"terrain_gravel": "land_fill_secondary",
	"terrain_dirt": "land_fill_secondary",
	"terrain_grass": "land_fill_primary",
}

const _DEPTH_RANK_F: Dictionary = {
	RiverConstants.TILE_BANK:          0.0,
	RiverConstants.TILE_UNDERCUT_BANK: 0.7,
	RiverConstants.TILE_GRAVEL_BAR:    1.1,
	RiverConstants.TILE_SURFACE:       2.0,
	RiverConstants.TILE_WEED_BED:      2.4,
	RiverConstants.TILE_ROCK:          2.9,
	RiverConstants.TILE_LOG:           2.6,
	RiverConstants.TILE_MID_DEPTH:     3.0,
	RiverConstants.TILE_BOULDER:       3.8,
	RiverConstants.TILE_DEEP:          4.0,
}

const _DEPTH_STOPS: Array = [
	[0.0, Color(0.24, 0.50, 0.15)],
	[0.5, Color(0.29, 0.43, 0.17)],
	[0.85, Color(0.37, 0.37, 0.20)],
	[1.1, Color(0.60, 0.56, 0.38)],
	[1.5, Color(0.41, 0.65, 0.68)],
	[2.0, Color(0.30, 0.55, 0.69)],
	[2.4, Color(0.21, 0.43, 0.57)],
	[2.7, Color(0.17, 0.38, 0.53)],
	[3.0, Color(0.12, 0.29, 0.49)],
	[3.5, Color(0.08, 0.21, 0.40)],
	[4.0, Color(0.05, 0.14, 0.29)],
]

var _river_data: RiverData = null

# Child nodes — freed and rebuilt on each render() call.
var _chunk_sprites: Array[Sprite2D] = []
var _rock_nodes:    Array[Node]     = []
var _debug_nodes:   Array[Node]     = []

var _depth_map: PackedFloat32Array = PackedFloat32Array()
var _map_height: int = 0
var _depth_tile_cache: Dictionary = {}
var _tree_texture: Texture2D = null
var _boulder_texture: Texture2D = null
var _weed_texture: Texture2D = null
var _log_texture: Texture2D = null
var _sandbar_texture: Texture2D = null
var _bank_overlay_texture: Texture2D = null
var _bank_curve_texture: Texture2D = null
var _atlas_source_images: Dictionary = {}
var _tile_pools: Dictionary = {}
var _tile_pool_meta: Dictionary = {}
var _runtime_manifest: Dictionary = {}
var _material_module_cache: Dictionary = {}
var _blend_tile_cache: Dictionary = {}


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func render(data: RiverData) -> void:
	_river_data = data
	y_sort_enabled = true
	_ensure_prop_textures()
	_ensure_tile_pools()
	_clear_chunks()
	_clear_rock_nodes()
	_build_chunks(data)
	_build_rock_clusters(data)
	_build_log_nodes(data)
	_build_weed_feature_sprites(data)
	_build_bank_features(data)


func show_hold_debug(data: RiverData, top_n: int = 30) -> void:
	_clear_debug_nodes()
	var ts := float(RiverConstants.TILE_SIZE)
	for i in mini(top_n, data.top_holds.size()):
		var hold: Dictionary = data.top_holds[i]
		var px := float(int(hold["x"])) * ts
		var py := float(int(hold["y"])) * ts
		var sq := PackedVector2Array([
			Vector2(px,      py),      Vector2(px + ts, py),
			Vector2(px + ts, py + ts), Vector2(px,      py + ts),
		])
		var node := Polygon2D.new()
		node.polygon = sq
		node.color   = Color(1.0, 0.8, 0.0, 0.40)
		node.z_index = 2
		add_child(node)
		_debug_nodes.append(node)


func hide_hold_debug() -> void:
	_clear_debug_nodes()


# ---------------------------------------------------------------------------
# Chunk generation
# ---------------------------------------------------------------------------

func _ensure_tile_pools() -> void:
	if not _tile_pools.is_empty():
		return
	_ensure_runtime_manifest()
	for pool_key in _TILE_POOL_DIRS.keys():
		_tile_pools[pool_key] = _load_tile_pool(
				pool_key,
				_TILE_POOL_DIRS[pool_key] as String)


func _ensure_runtime_manifest() -> void:
	if not _runtime_manifest.is_empty():
		return
	if not FileAccess.file_exists(_SpriteCatalog.CURATED_RUNTIME_MANIFEST):
		return
	var file := FileAccess.open(_SpriteCatalog.CURATED_RUNTIME_MANIFEST, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		_runtime_manifest = parsed


func _load_tile_pool(pool_key: String, dir_path: String) -> Array:
	var pool: Array = []
	var abs_dir := ProjectSettings.globalize_path(dir_path)
	if not DirAccess.dir_exists_absolute(abs_dir):
		push_warning("River tile pool missing: %s" % dir_path)
		return pool
	var files: PackedStringArray = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_warning("River tile pool failed to open: %s" % dir_path)
		return pool
	dir.list_dir_begin()
	while true:
		var entry := dir.get_next()
		if entry.is_empty():
			break
		if dir.current_is_dir():
			continue
		if not entry.to_lower().ends_with(".png"):
			continue
		files.append(entry)
	dir.list_dir_end()
	files.sort()
	var category := _MANIFEST_CATEGORY_BY_POOL.get(pool_key, "") as String
	var meta := _pool_meta_for_category(category)
	var selected_files := _curated_file_list(files, meta)
	_tile_pool_meta[pool_key] = {
		"common_count": int(meta.get("target_common", selected_files.size())),
		"patch_span": _patch_span_for_pool(pool_key),
	}
	for file_name in selected_files:
		var img := Image.new()
		var load_path := dir_path.path_join(file_name)
		if img.load(ProjectSettings.globalize_path(load_path)) == OK:
			if img.get_format() != Image.FORMAT_RGBA8:
				img.convert(Image.FORMAT_RGBA8)
			if pool_key.begins_with("terrain_"):
				_seal_bright_tile_edges(img)
			pool.append(img)
	return pool


func _seal_bright_tile_edges(tile: Image) -> void:
	var w := tile.get_width()
	var h := tile.get_height()
	if w < 8 or h < 8:
		return
	var edge_width := 2
	var inset := 3
	for y in range(h):
		for x in range(edge_width):
			tile.set_pixel(x, y, tile.get_pixel(inset, y))
			tile.set_pixel(w - 1 - x, y, tile.get_pixel(w - 1 - inset, y))
	for x in range(w):
		for y in range(edge_width):
			tile.set_pixel(x, y, tile.get_pixel(x, inset))
			tile.set_pixel(x, h - 1 - y, tile.get_pixel(x, h - 1 - inset))


func _pool_meta_for_category(category: String) -> Dictionary:
	var categories := _runtime_manifest.get("categories", {}) as Dictionary
	if category.is_empty() or not categories.has(category):
		return {}
	return categories[category] as Dictionary


func _curated_file_list(files: PackedStringArray, meta: Dictionary) -> PackedStringArray:
	if files.is_empty():
		return files
	var target_common := int(meta.get("target_common", files.size()))
	var target_rare := int(meta.get("target_rare", 0))
	var max_runtime := int(meta.get("max_runtime", files.size()))
	var total := clampi(target_common + target_rare, 1, mini(max_runtime, files.size()))
	if total >= files.size():
		return files

	var chosen: PackedStringArray = []
	var used := {}
	for i in range(total):
		var idx := int(round(float(i) * float(files.size() - 1) / float(total - 1))) if total > 1 else 0
		idx = clampi(idx, 0, files.size() - 1)
		var name := files[idx]
		if used.has(name):
			continue
		used[name] = true
		chosen.append(name)

	var fill_idx := 0
	while chosen.size() < total and fill_idx < files.size():
		var fallback := files[fill_idx]
		if not used.has(fallback):
			used[fallback] = true
			chosen.append(fallback)
		fill_idx += 1
	return chosen


func _patch_span_for_pool(pool_key: String) -> Vector2i:
	if pool_key.begins_with("water_"):
		return Vector2i(12, 8)
	if pool_key.begins_with("transition_"):
		return Vector2i(10, 6)
	if pool_key.begins_with("shoreline_"):
		return Vector2i(14, 2)
	if pool_key == "gravel_bar":
		return Vector2i(6, 4)
	if pool_key.begins_with("bank_corner_"):
		return Vector2i(2, 2)
	return Vector2i(3, 3)


func _build_depth_map(data: RiverData) -> void:
	var w := data.width
	var h := data.height
	_map_height = h
	_depth_map.resize(w * h)
	for tx in range(w):
		for ty in range(h):
			_depth_map[tx * h + ty] = _DEPTH_RANK_F.get(data.tile_map[tx][ty], 0.0)

	var tmp := PackedFloat32Array()
	tmp.resize(w * h)
	for _pass in 2:
		for ty in range(h):
			tmp[ty] = _depth_map[ty]
			tmp[(w - 1) * h + ty] = _depth_map[(w - 1) * h + ty]
			for tx in range(1, w - 1):
				tmp[tx * h + ty] = (
					_depth_map[(tx - 1) * h + ty] +
					_depth_map[tx * h + ty] +
					_depth_map[(tx + 1) * h + ty]) / 3.0
		var swap := _depth_map
		_depth_map = tmp
		tmp = swap

		for tx in range(w):
			tmp[tx * h] = _depth_map[tx * h]
			tmp[tx * h + h - 1] = _depth_map[tx * h + h - 1]
			for ty in range(1, h - 1):
				tmp[tx * h + ty] = (
					_depth_map[tx * h + ty - 1] +
					_depth_map[tx * h + ty] +
					_depth_map[tx * h + ty + 1]) / 3.0
		swap = _depth_map
		_depth_map = tmp
		tmp = swap


func _depth_at(tx: int, ty: int, data: RiverData) -> float:
	return _depth_map[
			clampi(tx, 0, data.width - 1) * _map_height +
			clampi(ty, 0, _map_height - 1)]


func _apply_rock_effects(data: RiverData) -> void:
	var h := _map_height
	for tx in range(data.width):
		for ty in range(data.height):
			var tile: int = data.tile_map[tx][ty]
			if tile != RiverConstants.TILE_ROCK and tile != RiverConstants.TILE_BOULDER:
				continue
			var is_boulder := tile == RiverConstants.TILE_BOULDER

			var bow_reach := 5 if is_boulder else 3
			var bow_str := 0.28 if is_boulder else 0.22
			for dx in range(1, bow_reach + 1):
				var ux := tx - dx
				if ux < 0:
					continue
				var f := 1.0 - float(dx) / float(bow_reach + 1)
				var lat := 2 if is_boulder else 1
				for dy in range(-lat, lat + 1):
					var uy := ty + dy
					if uy < 0 or uy >= h:
						continue
					var side_fade := 1.0 - float(abs(dy)) / float(lat + 1)
					var idx := ux * h + uy
					_depth_map[idx] = maxf(1.6, _depth_map[idx] - bow_str * f * side_fade)

			if is_boulder:
				for dx in range(1, 5):
					var wx := tx + dx
					if wx >= data.width:
						continue
					for dy in range(-2, 3):
						var wy := ty + dy
						if wy < 0 or wy >= h:
							continue
						var lateral_fade := 1.0 - float(abs(dy)) / 3.0
						var idx := wx * h + wy
						_depth_map[idx] = minf(4.0, _depth_map[idx] + 0.60 * lateral_fade)

				for dx in range(1, 8):
					var wx2 := tx + dx
					if wx2 >= data.width:
						continue
					var eddy_f := 1.0 - float(dx) / 8.0
					for side in [-1, 1]:
						for dy_off in range(2, 5):
							var wy2 := ty + int(side) * dy_off
							if wy2 < 0 or wy2 >= h:
								continue
							var eddy_t := 1.0 - float(dy_off - 2) / 3.0
							var idx2 := wx2 * h + wy2
							_depth_map[idx2] = minf(4.0, _depth_map[idx2] + 0.45 * eddy_f * eddy_t)

				for dx in range(5, 15):
					var wx3 := tx + dx
					if wx3 >= data.width:
						continue
					var f2 := 1.0 - float(dx - 4) / 11.0
					var spread := maxf(2.0, float(dx) * 0.55)
					for dy2 in range(-ceili(spread) - 1, ceili(spread) + 2):
						var side_t := absf(float(dy2)) / spread
						if side_t >= 1.0:
							continue
						var wy3 := ty + dy2
						if wy3 < 0 or wy3 >= h:
							continue
						var idx3 := wx3 * h + wy3
						_depth_map[idx3] = minf(4.0, _depth_map[idx3] + 0.28 * f2 * (1.0 - side_t * 0.55))
			else:
				for dx in range(1, 7):
					var wx4 := tx + dx
					if wx4 >= data.width:
						continue
					var f3 := 1.0 - float(dx) / 7.0
					var spread2 := maxf(1.0, float(dx) * 0.50)
					for dy3 in range(-ceili(spread2) - 1, ceili(spread2) + 2):
						var side_t2 := absf(float(dy3)) / spread2
						if side_t2 >= 1.0:
							continue
						var wy4 := ty + dy3
						if wy4 < 0 or wy4 >= h:
							continue
						var idx4 := wx4 * h + wy4
						_depth_map[idx4] = minf(4.0, _depth_map[idx4] + 0.38 * f3 * (1.0 - side_t2 * 0.65))


func _apply_current_effects(data: RiverData) -> void:
	var h := _map_height
	for tx in range(data.width):
		for ty in range(data.height):
			var tile: int = data.tile_map[tx][ty]
			if tile == RiverConstants.TILE_BANK or tile == RiverConstants.TILE_UNDERCUT_BANK \
					or tile == RiverConstants.TILE_GRAVEL_BAR:
				continue
			var current: float = data.current_map[tx][ty]
			if current < 0.05:
				continue
			var idx := tx * h + ty
			var delta := current * 0.10 - 0.02
			_depth_map[idx] = clampf(_depth_map[idx] - delta, 1.45, 4.0)

func _build_chunks(data: RiverData) -> void:
	var ts       := RiverConstants.TILE_SIZE
	var sw       := RiverConstants.SCREEN_W_TILES
	var n_chunks := data.width / sw
	for ci in n_chunks:
		var start_tx := ci * sw
		var img      := _render_chunk(data, start_tx, sw)
		var sprite   := Sprite2D.new()
		sprite.centered = false
		sprite.position = Vector2(float(start_tx * ts), 0.0)
		sprite.texture  = ImageTexture.create_from_image(img)
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.z_index  = 0
		add_child(sprite)
		_chunk_sprites.append(sprite)


func _render_chunk(data: RiverData, start_tx: int, chunk_w: int) -> Image:
	var ts    := RiverConstants.TILE_SIZE
	var img_w := chunk_w * ts
	var img_h := data.height * ts
	var img   := Image.create(img_w, img_h, false, Image.FORMAT_RGBA8)

	for tx in range(start_tx, start_tx + chunk_w):
		for ty in range(data.height):
			var dst := Vector2i((tx - start_tx) * ts, ty * ts)
			_blit_base_tile(img, dst, data, tx, ty)
			if not _blit_water_transition(img, dst, data, tx, ty):
				_blit_water_depth_blend(img, dst, data, tx, ty)

	_blend_compatible_tile_seams(img, data, start_tx, chunk_w)
	_blit_shoreline_modules(img, data, start_tx, chunk_w)
	_blit_profile_shoreline_overlay(img, data, start_tx, chunk_w)

	return img


func _blit_base_tile(target: Image, dst: Vector2i, data: RiverData, tx: int, ty: int) -> void:
	var tile_type: int = data.tile_map[tx][ty]
	var depth_class := _water_depth_class_for_type(tile_type)
	if depth_class >= 0:
		_blit_module_quadrant(
				target,
				dst,
				_WATER_POOL_BY_DEPTH_CLASS[depth_class] as String,
				tx,
				ty,
				depth_class * 101)
		return

	match tile_type:
		RiverConstants.TILE_BANK:
			_blit_material_module_quadrant(
					target,
					dst,
					_bank_fill_pool_key(data, tx, ty),
					tx,
					ty,
					509)
		RiverConstants.TILE_GRAVEL_BAR:
			_blit_module_quadrant(target, dst, "gravel_bar", tx, ty, 613)
		RiverConstants.TILE_UNDERCUT_BANK:
			_blit_material_module_quadrant(target, dst, "terrain_gravel", tx, ty, 719)


func _blend_compatible_tile_seams(target: Image, data: RiverData, start_tx: int, chunk_w: int) -> void:
	var ts := RiverConstants.TILE_SIZE
	var end_tx := start_tx + chunk_w
	for tx in range(start_tx + 1, end_tx):
		var seam_x := (tx - start_tx) * ts
		for ty in range(data.height):
			if not _tiles_can_seam_blend(data, tx - 1, ty, tx, ty):
				continue
			_blend_vertical_seam_segment(target, seam_x, ty * ts, ts)

	for tx in range(start_tx, end_tx):
		var x0 := (tx - start_tx) * ts
		for ty in range(1, data.height):
			if not _tiles_can_seam_blend(data, tx, ty - 1, tx, ty):
				continue
			_blend_horizontal_seam_segment(target, x0, ty * ts, ts)


func _tiles_can_seam_blend(data: RiverData, ax: int, ay: int, bx: int, by: int) -> bool:
	if ax < 0 or bx < 0 or ax >= data.width or bx >= data.width \
			or ay < 0 or by < 0 or ay >= data.height or by >= data.height:
		return false
	var a_group := _seam_blend_group(data.tile_map[ax][ay] as int)
	var b_group := _seam_blend_group(data.tile_map[bx][by] as int)
	return a_group >= 0 and a_group == b_group


func _seam_blend_group(tile_type: int) -> int:
	if _water_depth_class_for_type(tile_type) >= 0:
		return 1
	match tile_type:
		RiverConstants.TILE_BANK, RiverConstants.TILE_UNDERCUT_BANK, RiverConstants.TILE_GRAVEL_BAR:
			return 2
	return -1


func _blend_vertical_seam_segment(target: Image, seam_x: int, y0: int, height: int) -> void:
	if seam_x <= 0 or seam_x >= target.get_width():
		return
	var blend_width := 3
	for y in range(y0, mini(y0 + height, target.get_height())):
		for d in range(blend_width):
			var lx := seam_x - 1 - d
			var rx := seam_x + d
			if lx < 0 or rx >= target.get_width():
				continue
			var left := target.get_pixel(lx, y)
			var right := target.get_pixel(rx, y)
			var mix := 0.34 - float(d) * 0.08
			target.set_pixel(lx, y, left.lerp(right, mix))
			target.set_pixel(rx, y, right.lerp(left, mix))


func _blend_horizontal_seam_segment(target: Image, x0: int, seam_y: int, width: int) -> void:
	if seam_y <= 0 or seam_y >= target.get_height():
		return
	var blend_width := 3
	for x in range(x0, mini(x0 + width, target.get_width())):
		for d in range(blend_width):
			var uy := seam_y - 1 - d
			var dy := seam_y + d
			if uy < 0 or dy >= target.get_height():
				continue
			var up := target.get_pixel(x, uy)
			var down := target.get_pixel(x, dy)
			var mix := 0.34 - float(d) * 0.08
			target.set_pixel(x, uy, up.lerp(down, mix))
			target.set_pixel(x, dy, down.lerp(up, mix))


func _blit_shoreline_modules(target: Image, data: RiverData, start_tx: int, chunk_w: int) -> void:
	var end_tx := start_tx + chunk_w
	for tx in range(start_tx, end_tx):
		for ty in range(data.height):
			if data.tile_map[tx][ty] != RiverConstants.TILE_BANK:
				continue
			var shoreline := _bank_tile_def(data, tx, ty)
			if shoreline.is_empty():
				continue
			if not _shoreline_has_water_contact(data, tx, ty, shoreline):
				continue
			var dst := Vector2i((tx - start_tx) * RiverConstants.TILE_SIZE, ty * RiverConstants.TILE_SIZE)
			_blit_oriented_module_quadrant(
					target,
					dst,
					shoreline["pool"] as String,
					tx,
					ty,
					401,
					int(shoreline.get("rotation", _RiverSpriteAtlas.ROTATE_0)),
					bool(shoreline.get("flip_h", false)),
					bool(shoreline.get("flip_v", false)),
					shoreline.get("indices", []),
					shoreline.get("quadrant", Vector2i.ZERO) as Vector2i,
					shoreline.get("water_dirs", []))


func _shoreline_module_def_for_anchor(data: RiverData, tx: int, ty: int) -> Dictionary:
	if tx < 0 or tx + 1 >= data.width or ty < 0 or ty + 1 >= data.height:
		return {}
	var tl := _depth_class_at(data, tx, ty) >= 0
	var tr := _depth_class_at(data, tx + 1, ty) >= 0
	var bl := _depth_class_at(data, tx, ty + 1) >= 0
	var br := _depth_class_at(data, tx + 1, ty + 1) >= 0
	var water_count := int(tl) + int(tr) + int(bl) + int(br)

	if water_count == 1:
		var quadrant := _CORNER_WATER_BR
		if tl:
			quadrant = _CORNER_WATER_TL
		elif tr:
			quadrant = _CORNER_WATER_TR
		elif bl:
			quadrant = _CORNER_WATER_BL
		return {
			"pool": "shoreline_outer_corner",
			"rotation": _RiverSpriteAtlas.ROTATE_0,
			"flip_h": false,
			"flip_v": false,
			"indices": _SHORELINE_CORNER_INDICES_BY_WATER_QUADRANT[quadrant],
		}

	if water_count == 2:
		if bl and br:
			return {
				"pool": "shoreline_edge",
				"rotation": _RiverSpriteAtlas.ROTATE_0,
				"flip_h": false,
				"flip_v": false,
			}
		if tl and tr:
			return {
				"pool": "shoreline_edge",
				"rotation": _RiverSpriteAtlas.ROTATE_0,
				"flip_h": false,
				"flip_v": true,
			}
		if tl and bl:
			return {
				"pool": "shoreline_edge",
				"rotation": _RiverSpriteAtlas.ROTATE_90,
				"flip_h": false,
				"flip_v": false,
			}
		if tr and br:
			return {
				"pool": "shoreline_edge",
				"rotation": _RiverSpriteAtlas.ROTATE_270,
				"flip_h": false,
				"flip_v": false,
			}

	return {}


func _shoreline_priority(pool_key: String) -> int:
	match pool_key:
		"shoreline_outer_corner":
			return 3
		"shoreline_inner_corner":
			return 2
		"shoreline_edge":
			return 1
	return 0


func _shoreline_has_water_contact(data: RiverData, tx: int, ty: int, shoreline: Dictionary) -> bool:
	var dirs: Array = shoreline.get("water_dirs", [])
	for dir_variant in dirs:
		var dir := dir_variant as Vector2i
		if _depth_class_at(data, tx + dir.x, ty + dir.y) < 0:
			return false
	return not dirs.is_empty()


func _blit_water_depth_blend(target: Image, dst: Vector2i, data: RiverData, tx: int, ty: int) -> void:
	var here := _depth_class_at(data, tx, ty)
	if here < 0:
		return
	var blend := _depth_blend_info(data, tx, ty)
	if blend.is_empty():
		return
	var from_pool := _WATER_POOL_BY_DEPTH_CLASS[here] as String
	var to_pool := _WATER_POOL_BY_DEPTH_CLASS[blend["depth"] as int] as String
	var overlay := _blended_quadrant_image(
			from_pool,
			to_pool,
			tx,
			ty,
			903,
			blend["rotation"] as int)
	if overlay == null:
		return
	target.blit_rect(overlay, Rect2i(Vector2i.ZERO, overlay.get_size()), dst)


func _blit_water_transition(target: Image, dst: Vector2i, data: RiverData, tx: int, ty: int) -> bool:
	var transition := _transition_tile_info(data, tx, ty)
	if transition.is_empty():
		return false
	var pool_key := _TRANSITION_POOL_BY_KIND.get(
			transition["kind"] as int,
			"") as String
	if pool_key.is_empty():
		return false
	var transition_tile := _pool_tile_image(pool_key, tx, ty, 911)
	if transition_tile == null:
		return false
	var rotation := transition["rotation"] as int
	if rotation != _RiverSpriteAtlas.ROTATE_0:
		transition_tile = _transformed_image(transition_tile, rotation, false, false)
	var base_tile := target.get_region(Rect2i(dst, Vector2i.ONE * RiverConstants.TILE_SIZE))
	var blended := _make_transition_overlay_tile(base_tile, transition_tile, rotation)
	target.blit_rect(blended, Rect2i(Vector2i.ZERO, blended.get_size()), dst)
	return true


func _blit_pool_tile(target: Image, dst: Vector2i, pool_key: String, tx: int, ty: int,
		salt: int, rotation: int = _RiverSpriteAtlas.ROTATE_0,
		flip_h: bool = false, flip_v: bool = false) -> bool:
	var tile := _pool_tile_image(pool_key, tx, ty, salt)
	if tile == null:
		return false
	if rotation == _RiverSpriteAtlas.ROTATE_0 and not flip_h and not flip_v:
		target.blit_rect(tile, Rect2i(Vector2i.ZERO, tile.get_size()), dst)
		return true
	var transformed := _transformed_image(tile, rotation, flip_h, flip_v)
	target.blit_rect(transformed, Rect2i(Vector2i.ZERO, transformed.get_size()), dst)
	return true


func _blit_module_image(target: Image, dst: Vector2i, pool_key: String, tx: int, ty: int,
		salt: int, rotation: int = _RiverSpriteAtlas.ROTATE_0,
		flip_h: bool = false, flip_v: bool = false) -> void:
	var module := _pool_tile_image(pool_key, tx, ty, salt)
	if module == null:
		return
	if rotation == _RiverSpriteAtlas.ROTATE_0 and not flip_h and not flip_v:
		target.blit_rect(module, Rect2i(Vector2i.ZERO, module.get_size()), dst)
		return
	var transformed := _transformed_image(module, rotation, flip_h, flip_v)
	target.blit_rect(transformed, Rect2i(Vector2i.ZERO, transformed.get_size()), dst)


func _blit_oriented_module_quadrant(target: Image, dst: Vector2i, pool_key: String,
		tx: int, ty: int, salt: int, rotation: int = _RiverSpriteAtlas.ROTATE_0,
		flip_h: bool = false, flip_v: bool = false, indices: Array = [],
		quadrant: Vector2i = Vector2i.ZERO, water_dirs: Array = []) -> void:
	var module := _pool_tile_image_from_indices(pool_key, indices, tx, ty, salt) \
			if not indices.is_empty() else _pool_tile_image(pool_key, tx, ty, salt)
	if module == null:
		return
	if rotation != _RiverSpriteAtlas.ROTATE_0 or flip_h or flip_v:
		module = _transformed_image(module, rotation, flip_h, flip_v)
	var ts := RiverConstants.TILE_SIZE
	var local := Vector2i(clampi(quadrant.x, 0, 1), clampi(quadrant.y, 0, 1))
	var region := Rect2i(local.x * ts, local.y * ts, ts, ts)
	var tile := module.get_region(region)
	_blit_shoreline_overlay_tile(target, tile, dst, water_dirs)


func _blit_shoreline_overlay_tile(target: Image, source: Image, dst: Vector2i, water_dirs: Array) -> void:
	var size := source.get_size()
	for y in range(size.y):
		var target_y := dst.y + y
		if target_y < 0 or target_y >= target.get_height():
			continue
		for x in range(size.x):
			var target_x := dst.x + x
			if target_x < 0 or target_x >= target.get_width():
				continue
			var alpha := _shoreline_overlay_alpha(x, y, size, water_dirs)
			if alpha <= 0.0:
				continue
			var src := source.get_pixel(x, y)
			target.set_pixel(
					target_x,
					target_y,
					target.get_pixel(target_x, target_y).lerp(src, alpha * src.a))


func _shoreline_overlay_alpha(x: int, y: int, size: Vector2i, water_dirs: Array) -> float:
	if water_dirs.is_empty():
		return 1.0
	var edge_alpha := 0.0
	for dir_variant in water_dirs:
		var dir := dir_variant as Vector2i
		var dist := 0
		if dir == Vector2i(0, 1):
			dist = size.y - 1 - y
		elif dir == Vector2i(0, -1):
			dist = y
		elif dir == Vector2i(1, 0):
			dist = size.x - 1 - x
		elif dir == Vector2i(-1, 0):
			dist = x
		else:
			continue
		var a := 1.0 - clampf(float(dist) / 18.0, 0.0, 1.0)
		edge_alpha = maxf(edge_alpha, a)
	edge_alpha = edge_alpha * edge_alpha * (3.0 - 2.0 * edge_alpha)
	return edge_alpha


func _blit_profile_shoreline_overlay(target: Image, data: RiverData, start_tx: int, chunk_w: int) -> void:
	var ts := RiverConstants.TILE_SIZE
	var img_w := target.get_width()
	for px in range(img_w):
		var world_x := start_tx + float(px) / float(ts)
		var top_y := _smoothed_bank_profile_y(data.top_bank_profile, world_x, data.width) * float(ts)
		var bottom_y := _smoothed_bank_profile_y(data.bottom_bank_profile, world_x, data.width) * float(ts)
		var world_tx := clampi(start_tx + px / ts, 0, data.width - 1)
		var top_hard_y := float(int(data.top_bank_profile[world_tx]) * ts)
		var bottom_hard_y := float(int(data.bottom_bank_profile[world_tx]) * ts)
		_blit_profile_mismatch_column(target, data, px, top_y, top_hard_y, true, world_tx)
		_blit_profile_mismatch_column(target, data, px, bottom_y, bottom_hard_y, false, world_tx)
		_blit_profile_shore_column(target, data, start_tx, px, top_y, true)
		_blit_profile_shore_column(target, data, start_tx, px, bottom_y, false)


func _smoothed_bank_profile_y(profile: Array, world_x: float, width: int) -> float:
	if profile.is_empty():
		return 0.0
	var x0 := floori(world_x)
	var accum := 0.0
	var weight_sum := 0.0
	for dx in range(-3, 4):
		var sx := clampi(x0 + dx, 0, width - 1)
		var dist := absf(world_x - float(sx))
		var weight := maxf(0.0, 1.0 - dist / 3.5)
		weight *= weight
		accum += float(profile[sx]) * weight
		weight_sum += weight
	if weight_sum <= 0.0:
		return float(profile[clampi(x0, 0, profile.size() - 1)])
	return accum / weight_sum


func _blit_profile_mismatch_column(target: Image, data: RiverData, px: int, shore_y: float,
		hard_y: float, top_bank: bool, world_tx: int) -> void:
	var delta := hard_y - shore_y
	if absf(delta) < 1.0:
		return
	var y0 := floori(minf(shore_y, hard_y) - 6.0)
	var y1 := ceili(maxf(shore_y, hard_y) + 6.0)
	y0 = maxi(0, y0)
	y1 = mini(target.get_height() - 1, y1)
	for py in range(y0, y1 + 1):
		var visual_water := float(py) >= shore_y if top_bank else float(py) <= shore_y
		var hard_water := float(py) >= hard_y if top_bank else float(py) <= hard_y
		if visual_water == hard_water:
			continue
		var dist_to_gap_edge := minf(absf(float(py) - shore_y), absf(float(py) - hard_y))
		var edge_fade := clampf(dist_to_gap_edge / 4.0, 0.0, 1.0)
		edge_fade = 0.35 + 0.65 * edge_fade
		var color := _profile_filler_sample_color(
				target,
				px,
				py,
				hard_y,
				top_bank,
				visual_water,
				data.seed + world_tx * 17)
		target.set_pixel(px, py, target.get_pixel(px, py).lerp(color, 0.86 * edge_fade))


func _blit_profile_shore_column(target: Image, data: RiverData, start_tx: int, px: int,
		shore_y: float, top_bank: bool) -> void:
	var ts := RiverConstants.TILE_SIZE
	var world_tx := clampi(start_tx + px / ts, 0, data.width - 1)
	var y_start := maxi(0, floori(shore_y - 18.0))
	var y_end := mini(target.get_height() - 1, ceili(shore_y + 30.0))
	for py in range(y_start, y_end + 1):
		var dist_to_water := float(py) - shore_y if top_bank else shore_y - float(py)
		var alpha := _profile_shore_alpha(dist_to_water)
		if alpha <= 0.0:
			continue
		var color := _profile_shore_color(dist_to_water, px, py, data.seed + world_tx * 17)
		target.set_pixel(px, py, target.get_pixel(px, py).lerp(color, alpha))


func _profile_shore_alpha(dist_to_water: float) -> float:
	if dist_to_water < -14.0 or dist_to_water > 28.0:
		return 0.0
	var fade_land := clampf((dist_to_water + 14.0) / 14.0, 0.0, 1.0)
	var fade_water := 1.0 - clampf((dist_to_water - 10.0) / 18.0, 0.0, 1.0)
	var edge := fade_land * fade_water
	edge = edge * edge * (3.0 - 2.0 * edge)
	return edge * 0.58


func _profile_shore_color(dist_to_water: float, px: int, py: int, salt: int) -> Color:
	var dry_bank := Color(0.43, 0.39, 0.23, 1.0)
	var wet_bank := Color(0.38, 0.43, 0.28, 1.0)
	var shallow := Color(0.10, 0.38, 0.39, 1.0)
	var deeper := Color(0.07, 0.31, 0.36, 1.0)
	var t := clampf((dist_to_water + 8.0) / 28.0, 0.0, 1.0)
	var color := dry_bank.lerp(wet_bank, clampf((dist_to_water + 12.0) / 12.0, 0.0, 1.0))
	color = color.lerp(shallow.lerp(deeper, t), t)
	var glint_t := 1.0 - clampf(absf(dist_to_water - 2.0) / 8.0, 0.0, 1.0)
	color = color.lerp(Color(0.42, 0.58, 0.52, 1.0), glint_t * 0.16)
	var noise := (_hash(px * 19 + salt, py * 23 + salt * 3) - 0.5) * 0.07
	color.r = clampf(color.r + noise, 0.0, 1.0)
	color.g = clampf(color.g + noise, 0.0, 1.0)
	color.b = clampf(color.b + noise, 0.0, 1.0)
	return color


func _profile_filler_sample_color(target: Image, px: int, py: int, hard_y: float,
		top_bank: bool, want_water: bool, salt: int) -> Color:
	var water_sample_y := floori(hard_y + 10.0) if top_bank else ceili(hard_y - 10.0)
	var bank_sample_y := ceili(hard_y - 10.0) if top_bank else floori(hard_y + 10.0)
	var sample_y := water_sample_y if want_water else bank_sample_y
	sample_y = clampi(sample_y, 0, target.get_height() - 1)
	var jitter_x := clampi(px + int(round((_hash(px * 31 + salt, py * 7 + salt) - 0.5) * 4.0)), 0, target.get_width() - 1)
	var color := target.get_pixel(jitter_x, sample_y)
	var noise := (_hash(px * 13 + salt, py * 17 + salt * 3) - 0.5) * 0.045
	color.r = clampf(color.r + noise, 0.0, 1.0)
	color.g = clampf(color.g + noise, 0.0, 1.0)
	color.b = clampf(color.b + noise, 0.0, 1.0)
	return color


func _profile_water_fill_color(px: int, py: int, salt: int) -> Color:
	var water := Color(0.08, 0.34, 0.37, 1.0)
	var shallow := Color(0.16, 0.45, 0.43, 1.0)
	var noise := _hash(px * 13 + salt, py * 17 + salt * 3)
	return water.lerp(shallow, 0.35 + noise * 0.25)


func _profile_bank_fill_color(px: int, py: int, salt: int) -> Color:
	var sand := Color(0.55, 0.48, 0.31, 1.0)
	var grass := Color(0.28, 0.40, 0.13, 1.0)
	var noise := _hash(px * 23 + salt, py * 11 + salt * 5)
	return sand.lerp(grass, noise * 0.32)


func _blit_module_image_clipped(target: Image, dst: Vector2i, pool_key: String, tx: int, ty: int,
		salt: int, rotation: int = _RiverSpriteAtlas.ROTATE_0,
		flip_h: bool = false, flip_v: bool = false) -> void:
	var module := _pool_tile_image(pool_key, tx, ty, salt)
	if module == null:
		return
	if rotation != _RiverSpriteAtlas.ROTATE_0 or flip_h or flip_v:
		module = _transformed_image(module, rotation, flip_h, flip_v)
	_blit_image_clipped(target, module, dst)


func _blit_module_image_from_indices(target: Image, dst: Vector2i, pool_key: String,
		indices: Array, tx: int, ty: int, salt: int) -> void:
	var module := _pool_tile_image_from_indices(pool_key, indices, tx, ty, salt)
	if module == null:
		return
	target.blit_rect(module, Rect2i(Vector2i.ZERO, module.get_size()), dst)


func _blit_module_image_from_indices_clipped(target: Image, dst: Vector2i, pool_key: String,
		indices: Array, tx: int, ty: int, salt: int) -> void:
	var module := _pool_tile_image_from_indices(pool_key, indices, tx, ty, salt)
	if module == null:
		return
	_blit_image_clipped(target, module, dst)


func _blit_image_clipped(target: Image, source: Image, dst: Vector2i) -> void:
	var source_pos := Vector2i.ZERO
	var target_pos := dst
	var size := source.get_size()
	if target_pos.x < 0:
		source_pos.x = -target_pos.x
		size.x -= source_pos.x
		target_pos.x = 0
	if target_pos.y < 0:
		source_pos.y = -target_pos.y
		size.y -= source_pos.y
		target_pos.y = 0
	if target_pos.x + size.x > target.get_width():
		size.x = target.get_width() - target_pos.x
	if target_pos.y + size.y > target.get_height():
		size.y = target.get_height() - target_pos.y
	if size.x <= 0 or size.y <= 0:
		return
	target.blit_rect(source, Rect2i(source_pos, size), target_pos)


func _blit_module_quadrant(target: Image, dst: Vector2i, pool_key: String, tx: int, ty: int, salt: int) -> void:
	var ts := RiverConstants.TILE_SIZE
	var anchor_tx := tx - posmod(tx, 2)
	var anchor_ty := ty - posmod(ty, 2)
	var module := _pool_tile_image(pool_key, anchor_tx, anchor_ty, salt)
	if module == null:
		return
	if module.get_width() < _MODULE_TILE_SIZE or module.get_height() < _MODULE_TILE_SIZE:
		target.blit_rect(module, Rect2i(Vector2i.ZERO, Vector2i(mini(module.get_width(), ts), mini(module.get_height(), ts))), dst)
		return
	var local_x := tx - anchor_tx
	var local_y := ty - anchor_ty
	var region := Rect2i(local_x * ts, local_y * ts, ts, ts)
	target.blit_rect(module, region, dst)


func _blit_material_module_quadrant(target: Image, dst: Vector2i, pool_key: String, tx: int, ty: int, salt: int) -> void:
	var ts := RiverConstants.TILE_SIZE
	var anchor_tx := tx - posmod(tx, 2)
	var anchor_ty := ty - posmod(ty, 2)
	var module := _material_module_image(pool_key, anchor_tx, anchor_ty, salt)
	if module == null:
		return
	var local_x := tx - anchor_tx
	var local_y := ty - anchor_ty
	var region := Rect2i(local_x * ts, local_y * ts, ts, ts)
	target.blit_rect(module, region, dst)


func _material_module_image(pool_key: String, anchor_tx: int, anchor_ty: int, salt: int) -> Image:
	var cache_key := "%s:%d:%d:%d" % [pool_key, anchor_tx, anchor_ty, salt]
	if _material_module_cache.has(cache_key):
		return _material_module_cache[cache_key] as Image
	var pool: Array = _tile_pools.get(pool_key, [])
	if pool.is_empty():
		return null
	var module := Image.create(_MODULE_TILE_SIZE, _MODULE_TILE_SIZE, false, Image.FORMAT_RGBA8)
	var ts := RiverConstants.TILE_SIZE
	for local_x in range(2):
		for local_y in range(2):
			var tile := _material_module_tile(pool, pool_key, anchor_tx, anchor_ty, local_x, local_y, salt)
			if tile == null:
				continue
			module.blit_rect(tile, Rect2i(Vector2i.ZERO, tile.get_size()), Vector2i(local_x * ts, local_y * ts))
	_material_module_cache[cache_key] = module
	return module


func _material_module_tile(pool: Array, pool_key: String, anchor_tx: int, anchor_ty: int,
		local_x: int, local_y: int, salt: int) -> Image:
	if pool.is_empty():
		return null
	var span := Vector2i(12, 8) if pool_key == "terrain_grass" else Vector2i(10, 6)
	var patch_x := anchor_tx / maxi(1, span.x)
	var patch_y := anchor_ty / maxi(1, span.y)
	var module_seed := clampi(
			int(floor(_hash(patch_x * 79 + salt, patch_y * 41 + salt * 5) * float(pool.size()))),
			0,
			pool.size() - 1)
	var accent_seed := clampi(
			int(floor(_hash(patch_x * 131 + local_x * 17 + salt, patch_y * 97 + local_y * 23 + salt) * float(pool.size()))),
			0,
			pool.size() - 1)
	var idx := posmod(module_seed + local_x + local_y, pool.size())
	if _hash(anchor_tx + local_x * 13 + salt, anchor_ty + local_y * 29 + salt) > 0.74:
		idx = accent_seed
	return pool[idx] as Image


func _transformed_image(source: Image, rotation: int, flip_h: bool, flip_v: bool) -> Image:
	var transformed := source.get_region(Rect2i(Vector2i.ZERO, source.get_size()))
	if flip_h:
		transformed.flip_x()
	if flip_v:
		transformed.flip_y()
	for _step in range(rotation):
		transformed.rotate_90(0)
	return transformed


func _blended_quadrant_image(from_pool: String, to_pool: String, tx: int, ty: int,
		salt: int, rotation: int) -> Image:
	var cache_key := "%s:%s:%d:%d:%d:%d" % [from_pool, to_pool, tx, ty, salt, rotation]
	if _blend_tile_cache.has(cache_key):
		return _blend_tile_cache[cache_key] as Image
	var from_img := _module_quadrant_image(from_pool, tx, ty, salt)
	var to_img := _module_quadrant_image(to_pool, tx, ty, salt + 17)
	if from_img == null or to_img == null:
		return null
	var blended := _make_directional_blend_tile(from_img, to_img, rotation)
	_blend_tile_cache[cache_key] = blended
	return blended


func _module_quadrant_image(pool_key: String, tx: int, ty: int, salt: int) -> Image:
	var ts := RiverConstants.TILE_SIZE
	var anchor_tx := tx - posmod(tx, 2)
	var anchor_ty := ty - posmod(ty, 2)
	var module := _pool_tile_image(pool_key, anchor_tx, anchor_ty, salt)
	if module == null:
		return null
	if module.get_width() < _MODULE_TILE_SIZE or module.get_height() < _MODULE_TILE_SIZE:
		return module
	var local_x := tx - anchor_tx
	var local_y := ty - anchor_ty
	return module.get_region(Rect2i(local_x * ts, local_y * ts, ts, ts))


func _make_directional_blend_tile(base_img: Image, over_img: Image, rotation: int) -> Image:
	var size := base_img.get_size()
	var out := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var axis_x := rotation == _RiverSpriteAtlas.ROTATE_0 or rotation == _RiverSpriteAtlas.ROTATE_180
	var invert := rotation == _RiverSpriteAtlas.ROTATE_180 or rotation == _RiverSpriteAtlas.ROTATE_270
	for y in range(size.y):
		for x in range(size.x):
			var t := float(x) / float(maxi(1, size.x - 1)) if axis_x else float(y) / float(maxi(1, size.y - 1))
			if invert:
				t = 1.0 - t
			var edge0 := 0.18
			var edge1 := 0.82
			var alpha := clampf((t - edge0) / (edge1 - edge0), 0.0, 1.0)
			alpha = alpha * alpha * (3.0 - 2.0 * alpha)
			var noise := (_hash(x * 11 + 7, y * 13 + 5) - 0.5) * 0.10
			alpha = clampf(alpha + noise, 0.0, 1.0) * 0.58
			out.set_pixel(x, y, base_img.get_pixel(x, y).lerp(over_img.get_pixel(x, y), alpha))
	return out


func _make_transition_overlay_tile(base_img: Image, transition_img: Image, rotation: int) -> Image:
	var size := base_img.get_size()
	var out := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var axis_x := rotation == _RiverSpriteAtlas.ROTATE_0 or rotation == _RiverSpriteAtlas.ROTATE_180
	var invert := rotation == _RiverSpriteAtlas.ROTATE_180 or rotation == _RiverSpriteAtlas.ROTATE_270
	for y in range(size.y):
		for x in range(size.x):
			var t := float(x) / float(maxi(1, size.x - 1)) if axis_x else float(y) / float(maxi(1, size.y - 1))
			if invert:
				t = 1.0 - t
			var edge_alpha := clampf((t - 0.20) / 0.62, 0.0, 1.0)
			edge_alpha = edge_alpha * edge_alpha * (3.0 - 2.0 * edge_alpha)
			var source := transition_img.get_pixel(x, y)
			var alpha := minf(source.a, edge_alpha * 0.72)
			out.set_pixel(x, y, base_img.get_pixel(x, y).lerp(source, alpha))
	return out


func _depth_blend_info(data: RiverData, tx: int, ty: int) -> Dictionary:
	var here := _depth_class_at(data, tx, ty)
	if here < 0:
		return {}

	var right := _depth_class_at(data, tx + 1, ty)
	if right >= 0 and right != here:
		return {"depth": right, "rotation": _RiverSpriteAtlas.ROTATE_0}

	var below := _depth_class_at(data, tx, ty + 1)
	if below >= 0 and below != here:
		return {"depth": below, "rotation": _RiverSpriteAtlas.ROTATE_90}

	var left := _depth_class_at(data, tx - 1, ty)
	if left >= 0 and left != here:
		return {"depth": left, "rotation": _RiverSpriteAtlas.ROTATE_180}

	var above := _depth_class_at(data, tx, ty - 1)
	if above >= 0 and above != here:
		return {"depth": above, "rotation": _RiverSpriteAtlas.ROTATE_270}

	return {}


func _pool_tile_image(pool_key: String, tx: int, ty: int, salt: int) -> Image:
	var pool: Array = _tile_pools.get(pool_key, [])
	if pool.is_empty():
		return null
	var meta := _tile_pool_meta.get(pool_key, {}) as Dictionary
	var patch_span := meta.get("patch_span", Vector2i.ONE) as Vector2i
	var patch_x := tx / maxi(1, patch_span.x)
	var patch_y := ty / maxi(1, patch_span.y)
	var common_count := clampi(int(meta.get("common_count", pool.size())), 1, pool.size())
	var has_rare := pool.size() > common_count
	var use_rare := has_rare and _hash(patch_x * 43 + salt, patch_y * 29 + salt * 3) > 0.88
	var offset := common_count if use_rare else 0
	var count := pool.size() - common_count if use_rare else common_count
	count = maxi(1, count)
	var idx := offset + clampi(
			int(floor(_hash(patch_x * 97 + salt, patch_y * 53 + salt * 7) * float(count))),
			0,
			count - 1)
	return pool[idx] as Image


func _pool_tile_image_from_indices(pool_key: String, indices: Array, tx: int, ty: int, salt: int) -> Image:
	var pool: Array = _tile_pools.get(pool_key, [])
	if pool.is_empty() or indices.is_empty():
		return null
	var valid_indices: Array = []
	for idx_variant in indices:
		var idx := int(idx_variant)
		if idx >= 0 and idx < pool.size():
			valid_indices.append(idx)
	if valid_indices.is_empty():
		return null
	var choice := clampi(
			int(floor(_hash(tx * 97 + salt, ty * 53 + salt * 7) * float(valid_indices.size()))),
			0,
			valid_indices.size() - 1)
	return pool[int(valid_indices[choice])] as Image


func _bank_fill_pool_key(data: RiverData, tx: int, ty: int) -> String:
	match _bank_material_at(data, tx, ty):
		_BANK_MATERIAL_SAND:
			return "terrain_sand"
		_BANK_MATERIAL_GRAVEL:
			return "terrain_gravel"
		_BANK_MATERIAL_GRASS:
			return "terrain_grass"
	return "terrain_grass"


func _gravel_bar_pool_key(tx: int, ty: int) -> String:
	var patch_x := tx / 4
	var patch_y := ty / 2
	return "terrain_sand" if _hash(patch_x * 31 + 7, patch_y * 19 + 13) < 0.28 else "terrain_gravel"


func _bank_material_at(data: RiverData, tx: int, ty: int) -> int:
	var band := _bank_band(data, tx, ty)
	if band <= 0:
		return _BANK_MATERIAL_SAND

	var top_bank := ty <= int(data.top_bank_profile[tx]) - 1
	var patch_x := tx / (8 if top_bank else 10)
	var patch_y := 0 if top_bank else 1
	var roll := _hash(patch_x * 37 + 11, patch_y * 73 + 17)

	if band == 1:
		return _BANK_MATERIAL_GRAVEL if roll < 0.34 else _BANK_MATERIAL_SAND

	if band == 2:
		if roll < 0.12:
			return _BANK_MATERIAL_GRAVEL
		return _BANK_MATERIAL_GRASS

	if roll < 0.08:
		return _BANK_MATERIAL_GRAVEL
	return _BANK_MATERIAL_GRASS


func _bank_tile_def(data: RiverData, tx: int, ty: int) -> Dictionary:
	var water_n := _depth_class_at(data, tx, ty - 1) >= 0
	var water_s := _depth_class_at(data, tx, ty + 1) >= 0
	var water_e := _depth_class_at(data, tx + 1, ty) >= 0
	var water_w := _depth_class_at(data, tx - 1, ty) >= 0
	var water_count := int(water_n) + int(water_s) + int(water_e) + int(water_w)

	if water_count == 1:
		if water_s:
			return {
				"pool": "shoreline_edge",
				"rotation": _RiverSpriteAtlas.ROTATE_0,
				"flip_h": false,
				"flip_v": false,
				"water_dirs": [Vector2i(0, 1)],
				"quadrant": Vector2i(posmod(tx, 2), 0),
			}
		if water_n:
			return {
				"pool": "shoreline_edge",
				"rotation": _RiverSpriteAtlas.ROTATE_0,
				"flip_h": false,
				"flip_v": true,
				"water_dirs": [Vector2i(0, -1)],
				"quadrant": Vector2i(posmod(tx, 2), 1),
			}
		if water_w:
			return {
				"pool": "shoreline_edge",
				"rotation": _RiverSpriteAtlas.ROTATE_90,
				"flip_h": false,
				"flip_v": false,
				"water_dirs": [Vector2i(-1, 0)],
				"quadrant": Vector2i(1, posmod(ty, 2)),
			}
		if water_e:
			return {
				"pool": "shoreline_edge",
				"rotation": _RiverSpriteAtlas.ROTATE_270,
				"flip_h": false,
				"flip_v": false,
				"water_dirs": [Vector2i(1, 0)],
				"quadrant": Vector2i(0, posmod(ty, 2)),
			}

	if water_count == 2:
		if water_s and water_e:
			return {
				"pool": "shoreline_outer_corner",
				"rotation": _RiverSpriteAtlas.ROTATE_0,
				"flip_h": false,
				"flip_v": false,
				"water_dirs": [Vector2i(0, 1), Vector2i(1, 0)],
				"indices": [0, 1],
				"quadrant": Vector2i(0, 0),
			}
		if water_s and water_w:
			return {
				"pool": "shoreline_outer_corner",
				"rotation": _RiverSpriteAtlas.ROTATE_0,
				"flip_h": true,
				"flip_v": false,
				"water_dirs": [Vector2i(0, 1), Vector2i(-1, 0)],
				"indices": [0, 1],
				"quadrant": Vector2i(1, 0),
			}
		if water_n and water_e:
			return {
				"pool": "shoreline_outer_corner",
				"rotation": _RiverSpriteAtlas.ROTATE_0,
				"flip_h": false,
				"flip_v": true,
				"water_dirs": [Vector2i(0, -1), Vector2i(1, 0)],
				"indices": [0, 1],
				"quadrant": Vector2i(0, 1),
			}
		if water_n and water_w:
			return {
				"pool": "shoreline_outer_corner",
				"rotation": _RiverSpriteAtlas.ROTATE_0,
				"flip_h": true,
				"flip_v": true,
				"water_dirs": [Vector2i(0, -1), Vector2i(-1, 0)],
				"indices": [0, 1],
				"quadrant": Vector2i(1, 1),
			}

	if water_count == 3:
		if not water_n:
			return {
				"pool": "shoreline_edge",
				"rotation": _RiverSpriteAtlas.ROTATE_0,
				"flip_h": false,
				"flip_v": false,
				"water_dirs": [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)],
				"quadrant": Vector2i(posmod(tx, 2), 0),
			}
		if not water_e:
			return {
				"pool": "shoreline_edge",
				"rotation": _RiverSpriteAtlas.ROTATE_90,
				"flip_h": false,
				"flip_v": false,
				"water_dirs": [Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)],
				"quadrant": Vector2i(1, posmod(ty, 2)),
			}
		if not water_s:
			return {
				"pool": "shoreline_edge",
				"rotation": _RiverSpriteAtlas.ROTATE_0,
				"flip_h": false,
				"flip_v": true,
				"water_dirs": [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1)],
				"quadrant": Vector2i(posmod(tx, 2), 1),
			}
		if not water_w:
			return {
				"pool": "shoreline_edge",
				"rotation": _RiverSpriteAtlas.ROTATE_270,
				"flip_h": false,
				"flip_v": false,
				"water_dirs": [Vector2i(1, 0), Vector2i(0, 1), Vector2i(0, -1)],
				"quadrant": Vector2i(0, posmod(ty, 2)),
			}

	return {}


func _visual_tile_def(data: RiverData, tx: int, ty: int, material: Dictionary) -> Array:
	var tile_type: int = material["tile_type"] as int
	var depth_class := material["depth_class"] as int
	var current := material["current"] as float
	var rotation := _RiverSpriteAtlas.ROTATE_0
	var transition := _transition_tile_info(data, tx, ty)
	var transition_kind := _RiverSpriteAtlas.TRANSITION_NONE
	if tile_type == RiverConstants.TILE_BANK and material["bank_edge"] as bool:
		rotation = _bank_edge_rotation(data, tx, ty)
	if not transition.is_empty():
		rotation = transition["rotation"] as int
		transition_kind = transition["kind"] as int
	var def := _RiverSpriteAtlas.base_def(
			tile_type,
			tx,
			ty,
			data.seed,
			depth_class,
			material["bank_edge"] as bool,
			current,
			transition_kind,
			Vector2i.ONE * RiverConstants.TILE_SIZE,
			material["bank_band"] as int,
			rotation)
	if def.is_empty():
		return []
	return [
		def[_RiverSpriteAtlas.SOURCE_PATH] as String,
		def[_RiverSpriteAtlas.SOURCE_REGION] as Rect2i,
		def[_RiverSpriteAtlas.SOURCE_ROTATION] as int,
	]


func _blit_visual_def(target: Image, dst: Vector2i, def: Array) -> void:
	var source := _source_image(def[0] as String)
	if source == null:
		return
	var region := def[1] as Rect2i
	var rotation := def[2] as int
	if rotation == _RiverSpriteAtlas.ROTATE_0:
		target.blit_rect(source, region, dst)
		return
	var tile := source.get_region(region)
	for _step in range(rotation):
		tile.rotate_90(0)
	target.blit_rect(tile, Rect2i(Vector2i.ZERO, tile.get_size()), dst)


func _blit_depth_base(target: Image, dst: Vector2i, data: RiverData, tx: int, ty: int) -> void:
	var ts := RiverConstants.TILE_SIZE
	var d00 := _depth_at(tx, ty, data)
	var d10 := _depth_at(tx + 1, ty, data)
	var d01 := _depth_at(tx, ty + 1, data)
	var d11 := _depth_at(tx + 1, ty + 1, data)
	var variant := _tile_variant(tx, ty, data.seed)
	var key := _tile_key(d00, d10, d01, d11, variant)
	if not _depth_tile_cache.has(key):
		_depth_tile_cache[key] = _make_depth_tile(_q(d00), _q(d10), _q(d01), _q(d11), variant)
	target.blit_rect(
			_depth_tile_cache[key],
			Rect2i(Vector2i.ZERO, Vector2i.ONE * ts),
			dst)


func _q(d: float) -> float:
	return float(clampi(int(d * 10.0 + 0.5), 0, 40)) / 10.0


func _tile_key(d00: float, d10: float, d01: float, d11: float, variant: int = 0) -> int:
	var q0 := clampi(int(d00 * 10.0 + 0.5), 0, 40)
	var q1 := clampi(int(d10 * 10.0 + 0.5), 0, 40)
	var q2 := clampi(int(d01 * 10.0 + 0.5), 0, 40)
	var q3 := clampi(int(d11 * 10.0 + 0.5), 0, 40)
	return q0 | (q1 << 6) | (q2 << 12) | (q3 << 18) | (clampi(variant, 0, 7) << 24)


func _tile_variant(tx: int, ty: int, seed: int) -> int:
	return mini(3, maxi(0, int(floor(_hash(tx * 17 + seed, ty * 29 + seed * 3) * 4.0))))


func _make_depth_tile(d00: float, d10: float, d01: float, d11: float, variant: int = 0) -> Image:
	var ts := RiverConstants.TILE_SIZE
	var vx := variant * 19 + 7
	var vy := variant * 31 + 11
	var img := Image.create(ts, ts, false, Image.FORMAT_RGBA8)
	for j in range(ts):
		var fy := (float(j) + 0.5) / float(ts)
		for i in range(ts):
			var fx := (float(i) + 0.5) / float(ts)
			var depth := _bilerp(d00, d10, d01, d11, fx, fy)
			var n_coarse := _hash(i + vx, j + vy) * 0.08 - 0.04
			var n_fine := _hash(i * 5 + 3 + vx, j * 7 + 11 + vy) * 0.03 - 0.015
			var diagonal := _hash(i * 3 + j * 2 + 17 + vx, j * 5 + i + 29 + vy) * 0.04 - 0.02
			var tex_depth := depth + n_coarse + n_fine + diagonal
			var caustic := 0.0
			if depth < 2.35 and _hash(i * 11 + 1 + vx, j * 13 + 7 + vy) > 0.975:
				caustic = 0.05 * (1.0 - clampf((depth - 1.45) / 0.85, 0.0, 1.0))

			tex_depth += caustic
			img.set_pixel(i, j, _depth_color(clampf(tex_depth, 0.0, 4.0)))
	return img


func _bilerp(v00: float, v10: float, v01: float, v11: float,
		fx: float, fy: float) -> float:
	return v00 + (v10 - v00) * fx + (v01 - v00) * fy \
		+ (v00 - v10 - v01 + v11) * fx * fy


func _base_material_info(data: RiverData, tx: int, ty: int) -> Dictionary:
	var tile_type: int = data.tile_map[tx][ty]
	var depth_class := _water_depth_class_for_type(tile_type)
	if depth_class >= 0:
		var water_tile := RiverConstants.TILE_SURFACE
		if depth_class == 1:
			water_tile = RiverConstants.TILE_MID_DEPTH
		elif depth_class == 2:
			water_tile = RiverConstants.TILE_DEEP
		return {
			"tile_type": water_tile,
			"depth_class": depth_class,
			"bank_edge": false,
			"bank_band": -1,
			"current": _current_at(data, tx, ty),
		}
	if tile_type == RiverConstants.TILE_BANK:
		return {
			"tile_type": RiverConstants.TILE_BANK,
			"depth_class": -1,
			"bank_edge": _is_bank_edge(data, tx, ty),
			"bank_band": _bank_band(data, tx, ty),
			"current": 0.0,
		}
	if tile_type == RiverConstants.TILE_UNDERCUT_BANK or tile_type == RiverConstants.TILE_GRAVEL_BAR:
		return {
			"tile_type": tile_type,
			"depth_class": -1,
			"bank_edge": false,
			"bank_band": -1,
			"current": 0.0,
		}
	return {}


func _current_at(data: RiverData, tx: int, ty: int) -> float:
	if tx < 0 or tx >= data.current_map.size():
		return 0.0
	var column: Array = data.current_map[tx]
	if ty < 0 or ty >= column.size():
		return 0.0
	return column[ty] as float


func _is_bank_edge(data: RiverData, tx: int, ty: int) -> bool:
	if data.tile_map[tx][ty] != RiverConstants.TILE_BANK:
		return false
	for n in [
		Vector2i(tx - 1, ty),
		Vector2i(tx + 1, ty),
		Vector2i(tx, ty - 1),
		Vector2i(tx, ty + 1),
	]:
		if n.x < 0 or n.x >= data.width or n.y < 0 or n.y >= data.height:
			continue
		if _water_depth_class_for_type(data.tile_map[n.x][n.y]) >= 0:
			return true
	return false


func _bank_band(data: RiverData, tx: int, ty: int) -> int:
	if data.tile_map[tx][ty] != RiverConstants.TILE_BANK:
		return -1
	var near_edge_row: int = int(data.top_bank_profile[tx]) - 1
	if ty <= near_edge_row:
		return mini(2, maxi(0, near_edge_row - ty))
	var far_edge_row: int = int(data.bottom_bank_profile[tx])
	if ty >= far_edge_row:
		return mini(2, maxi(0, ty - far_edge_row))
	return 0


func _bank_edge_rotation(data: RiverData, tx: int, ty: int) -> int:
	if _depth_class_at(data, tx, ty + 1) >= 0:
		return _RiverSpriteAtlas.ROTATE_0
	if _depth_class_at(data, tx - 1, ty) >= 0:
		return _RiverSpriteAtlas.ROTATE_90
	if _depth_class_at(data, tx, ty - 1) >= 0:
		return _RiverSpriteAtlas.ROTATE_180
	if _depth_class_at(data, tx + 1, ty) >= 0:
		return _RiverSpriteAtlas.ROTATE_270
	return _RiverSpriteAtlas.ROTATE_0


func _transition_tile_info(data: RiverData, tx: int, ty: int) -> Dictionary:
	var here := _depth_class_at(data, tx, ty)
	if here < 0:
		return {}

	var right := _depth_class_at(data, tx + 1, ty)
	if right > here:
		var kind := _transition_between_depths(here, right)
		if kind != _RiverSpriteAtlas.TRANSITION_NONE:
			return {
				"kind": kind,
				"rotation": _RiverSpriteAtlas.ROTATE_0,
			}

	var below := _depth_class_at(data, tx, ty + 1)
	if below > here:
		var below_kind := _transition_between_depths(here, below)
		if below_kind != _RiverSpriteAtlas.TRANSITION_NONE:
			return {
				"kind": below_kind,
				"rotation": _RiverSpriteAtlas.ROTATE_90,
			}

	var left := _depth_class_at(data, tx - 1, ty)
	if left > here:
		var left_kind := _transition_between_depths(here, left)
		if left_kind != _RiverSpriteAtlas.TRANSITION_NONE:
			return {
				"kind": left_kind,
				"rotation": _RiverSpriteAtlas.ROTATE_180,
			}

	var above := _depth_class_at(data, tx, ty - 1)
	if above > here:
		var above_kind := _transition_between_depths(here, above)
		if above_kind != _RiverSpriteAtlas.TRANSITION_NONE:
			return {
				"kind": above_kind,
				"rotation": _RiverSpriteAtlas.ROTATE_270,
			}

	return {}


func _transition_between_depths(a: int, b: int) -> int:
	if a < 0 or b < 0 or a == b:
		return _RiverSpriteAtlas.TRANSITION_NONE
	var low := mini(a, b)
	var high := maxi(a, b)
	if low == 0 and high == 1:
		return _RiverSpriteAtlas.TRANSITION_SHALLOW_MID
	if low == 1 and high == 2:
		return _RiverSpriteAtlas.TRANSITION_MID_DEEP
	if low == 0 and high == 2:
		return _RiverSpriteAtlas.TRANSITION_SHALLOW_DEEP
	return _RiverSpriteAtlas.TRANSITION_NONE


func _depth_class_at(data: RiverData, tx: int, ty: int) -> int:
	if tx < 0 or tx >= data.width or ty < 0 or ty >= data.height:
		return -1
	return _water_depth_class_for_type(data.tile_map[tx][ty])


func _water_depth_class_for_type(tile_type: int) -> int:
	match tile_type:
		RiverConstants.TILE_SURFACE:
			return 0
		RiverConstants.TILE_MID_DEPTH, RiverConstants.TILE_WEED_BED, \
				RiverConstants.TILE_ROCK, RiverConstants.TILE_LOG:
			return 1
		RiverConstants.TILE_DEEP, RiverConstants.TILE_BOULDER:
			return 2
	return -1


func _source_image(path: String) -> Image:
	if _atlas_source_images.has(path):
		return _atlas_source_images[path] as Image
	var img := Image.new()
	var err := img.load(ProjectSettings.globalize_path(path))
	if err != OK:
		push_warning("River atlas source could not load %s" % path)
		return null
	_atlas_source_images[path] = img
	return img


func _hash(x: int, y: int) -> float:
	var h: int = (x * 1619 + y * 31337) & 0x7FFFFFFF
	h ^= h >> 16
	h  = (h * 0x45d9f3b) & 0x7FFFFFFF
	return float(h & 0xFF) / 255.0


func _depth_color(depth: float) -> Color:
	var stops: Array = _DEPTH_STOPS
	var last := stops.size() - 1
	if depth <= (stops[0][0] as float):
		return stops[0][1] as Color
	if depth >= (stops[last][0] as float):
		return stops[last][1] as Color
	for i in range(1, stops.size()):
		if depth <= (stops[i][0] as float):
			var d0 := stops[i - 1][0] as float
			var d1 := stops[i][0] as float
			var c0 := stops[i - 1][1] as Color
			var c1 := stops[i][1] as Color
			return c0.lerp(c1, (depth - d0) / (d1 - d0))
	return stops[last][1] as Color


# ---------------------------------------------------------------------------
# Rock cluster rendering — sprite-only overlays
# ---------------------------------------------------------------------------

func _build_rock_clusters(data: RiverData) -> void:
	var ts      := float(RiverConstants.TILE_SIZE)
	var visited := {}

	for tx in range(0, data.width):
		for ty in range(0, data.height):
			var tile: int = data.tile_map[tx][ty]
			if tile != RiverConstants.TILE_ROCK and tile != RiverConstants.TILE_BOULDER:
				continue
			var key := Vector2i(tx, ty)
			if visited.has(key):
				continue

			var cells:     Array = []
			var is_boulder := false
			var queue:     Array = [key]
			while not queue.is_empty():
				var c: Vector2i = queue.pop_back()
				if visited.has(c): continue
				if c.x < 0 or c.x >= data.width or c.y < 0 or c.y >= data.height: continue
				var ct: int = data.tile_map[c.x][c.y]
				if ct != RiverConstants.TILE_ROCK and ct != RiverConstants.TILE_BOULDER: continue
				visited[c] = true
				cells.append(c)
				if ct == RiverConstants.TILE_BOULDER: is_boulder = true
				queue.append(Vector2i(c.x + 1, c.y))
				queue.append(Vector2i(c.x - 1, c.y))
				queue.append(Vector2i(c.x, c.y + 1))
				queue.append(Vector2i(c.x, c.y - 1))

			if cells.is_empty(): continue

			var cx := 0.0; var cy := 0.0
			for c in cells:
				var cv: Vector2i = c
				cx += float(cv.x) * ts + ts * 0.5
				cy += float(cv.y) * ts + ts * 0.5
			cx /= float(cells.size()); cy /= float(cells.size())

			var rng := RandomNumberGenerator.new()
			rng.seed = data.seed ^ (int(cx) * 1619) ^ (int(cy) * 31337)
			_draw_rock_cluster_sprite(cx, cy, cells, is_boulder, ts, rng)


# ---------------------------------------------------------------------------
# Log rendering — sprite-only overlays
# ---------------------------------------------------------------------------

func _build_log_nodes(data: RiverData) -> void:
	var ts := float(RiverConstants.TILE_SIZE)
	for structure: Dictionary in data.structures:
		if (structure["type"] as int) != RiverConstants.TILE_LOG:
			continue
		var sx: int = structure["x"]
		var sy: int = structure["y"]
		var sw: int = structure["w"]

		var rng := RandomNumberGenerator.new()
		rng.seed = data.seed ^ sx ^ (sy * 997)

		# Visual center of the structure footprint
		var cx := (float(sx) + float(sw) * 0.5) * ts
		var cy := (float(sy) + 0.5) * ts

		# Angle: 30% near-horizontal, 30% diagonal, 40% near-perpendicular
		var ah  := _hash(sx * 5 + 3, sy * 17 + 7)
		var angle: float
		if ah < 0.30:
			angle = rng.randf_range(-14.0, 14.0)
		elif ah < 0.60:
			angle = rng.randf_range(22.0, 52.0) * (1.0 if rng.randf() > 0.5 else -1.0)
		else:
			angle = rng.randf_range(62.0, 86.0) * (1.0 if rng.randf() > 0.5 else -1.0)

		var length := float(sw) * ts * (0.80 + rng.randf() * 0.30)
		_draw_log_sprite(cx, cy, length, angle, rng)


# ---------------------------------------------------------------------------
# Sprite props — selected atlas regions layered over the sprite-atlas river base
# ---------------------------------------------------------------------------

func _ensure_prop_textures() -> void:
	if _tree_texture == null:
		_tree_texture = _load_external_texture(_RiverSpriteAtlas.atlas_path(_RiverSpriteAtlas.TREES_KEY))
	if _boulder_texture == null:
		_boulder_texture = _load_external_texture(_RiverSpriteAtlas.atlas_path(_RiverSpriteAtlas.BOULDERS_KEY))
	if _weed_texture == null:
		_weed_texture = _load_external_texture(_RiverSpriteAtlas.atlas_path(_RiverSpriteAtlas.WEED_BEDS_KEY))
	if _log_texture == null:
		_log_texture = _load_external_texture(_RiverSpriteAtlas.atlas_path(_RiverSpriteAtlas.LOGS_KEY))


func _load_external_texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	var img := Image.new()
	if img.load(ProjectSettings.globalize_path(path)) != OK:
		push_warning("River renderer could not load texture %s" % path)
		return null
	return ImageTexture.create_from_image(img)


func _add_prop_sprite(texture: Texture2D, region: Rect2i, base_pos: Vector2,
		target_width: float, z: int = 2, centered: bool = false,
		rotation_deg: float = 0.0, modulate: Color = Color.WHITE,
		filter_linear: bool = false, flip_h: bool = false, flip_v: bool = false) -> bool:
	if texture == null:
		return false
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.region_enabled = true
	sprite.region_rect = region
	sprite.centered = centered
	sprite.flip_h = flip_h
	sprite.flip_v = flip_v
	if filter_linear:
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	else:
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.position = base_pos
	sprite.scale = Vector2.ONE * (target_width / float(region.size.x))
	sprite.rotation_degrees = rotation_deg
	sprite.modulate = modulate
	sprite.z_index = z
	sprite.z_as_relative = false
	add_child(sprite)
	_rock_nodes.append(sprite)
	return true


func _pick_region(regions: Array, rng: RandomNumberGenerator) -> Rect2i:
	return regions[rng.randi_range(0, regions.size() - 1)] as Rect2i


func _pick_best_region(regions: Array, target_size: Vector2, rng: RandomNumberGenerator) -> Rect2i:
	if regions.is_empty():
		return Rect2i(Vector2i.ZERO, Vector2i(RiverConstants.TILE_SIZE, RiverConstants.TILE_SIZE))
	var best := regions[0] as Rect2i
	var best_score := INF
	for region_variant in regions:
		var region: Rect2i = region_variant
		var score := absf(float(region.size.x) - target_size.x) + absf(float(region.size.y) - target_size.y) * 0.7
		if score < best_score:
			best = region
			best_score = score
		elif is_equal_approx(score, best_score) and rng.randf() < 0.5:
			best = region
	return best


func _build_bank_edge_overlays(data: RiverData) -> void:
	if _bank_overlay_texture == null:
		return
	var ts := float(RiverConstants.TILE_SIZE)
	var rng := RandomNumberGenerator.new()
	rng.seed = data.seed ^ 0xE11D6E
	var strip_regions := _RiverSpriteAtlas.side_strip_regions()
	var curve_regions := _RiverSpriteAtlas.bank_curve_regions()
	var top_curve_covered := {}
	var bottom_curve_covered := {}
	var top_strip_covered := {}
	var bottom_strip_covered := {}

	if _bank_curve_texture != null:
		_build_bank_curve_overlays(data, true, curve_regions, rng, ts, top_curve_covered)
		_build_bank_curve_overlays(data, false, curve_regions, rng, ts, bottom_curve_covered)

	for tx in range(data.width):
		var top_y := int(data.top_bank_profile[tx]) - 1
		if top_y >= 0 and top_y < data.height \
				and data.tile_map[tx][top_y] == RiverConstants.TILE_BANK \
				and not top_curve_covered.has(tx) \
				and not top_strip_covered.has(tx):
			var top_region := _pick_region(strip_regions, rng)
			var top_cover_tiles := maxi(1, ceili(float(top_region.size.x) / ts))
			var top_pos := Vector2(float(tx) * ts + float(top_region.size.x) * 0.5, float(top_y) * ts + float(top_region.size.y) * 0.5)
			_add_prop_sprite(_bank_overlay_texture, top_region, top_pos, float(top_region.size.x) * 1.01,
					1, true, 0.0, Color(1.0, 1.0, 1.0, 0.82), false, rng.randf() < 0.5)
			for cover_tx in range(tx, mini(data.width, tx + top_cover_tiles)):
				top_strip_covered[cover_tx] = true

		var bottom_y := int(data.bottom_bank_profile[tx])
		if bottom_y >= 0 and bottom_y < data.height \
				and data.tile_map[tx][bottom_y] == RiverConstants.TILE_BANK \
				and not bottom_curve_covered.has(tx) \
				and not bottom_strip_covered.has(tx):
			var bottom_region := _pick_region(strip_regions, rng)
			var bottom_cover_tiles := maxi(1, ceili(float(bottom_region.size.x) / ts))
			var bottom_pos := Vector2(float(tx) * ts + float(bottom_region.size.x) * 0.5, float(bottom_y) * ts + float(bottom_region.size.y) * 0.5)
			_add_prop_sprite(_bank_overlay_texture, bottom_region, bottom_pos, float(bottom_region.size.x) * 1.01,
					1, true, 0.0, Color(1.0, 1.0, 1.0, 0.82), false, rng.randf() < 0.5, true)
			for cover_tx in range(tx, mini(data.width, tx + bottom_cover_tiles)):
				bottom_strip_covered[cover_tx] = true


func _build_bank_curve_overlays(data: RiverData, is_top_bank: bool, regions: Array,
		rng: RandomNumberGenerator, ts: float, covered: Dictionary) -> void:
	if _bank_curve_texture == null or regions.is_empty():
		return
	if data.width < 3:
		return

	for tx in range(1, data.width - 1):
		var prev_y := _bank_edge_y(data, tx - 1, is_top_bank)
		var here_y := _bank_edge_y(data, tx, is_top_bank)
		var next_y := _bank_edge_y(data, tx + 1, is_top_bank)
		if here_y < 0:
			continue

		var left_delta: int = here_y - prev_y
		var right_delta: int = next_y - here_y
		var bend_score: int = abs(left_delta) + abs(right_delta)
		if bend_score == 0:
			continue
		if abs(left_delta) > 1 or abs(right_delta) > 1:
			continue

		var target_size := Vector2(ts * 2.0, ts * (2.0 if bend_score > 1 else 1.0))
		var region := _pick_best_region(regions, target_size, rng)
		var cover_tiles := clampi(ceili(float(region.size.x) / ts), 2, 3)
		var start_tx := tx
		if abs(left_delta) > abs(right_delta):
			start_tx = tx - (cover_tiles - 1)
		elif abs(left_delta) == abs(right_delta):
			start_tx = tx - int(floor(float(cover_tiles - 1) * 0.5))
		start_tx = clampi(start_tx, 0, maxi(0, data.width - cover_tiles))
		var edge_y := _curve_bank_edge_y(data, start_tx, cover_tiles, is_top_bank)
		if edge_y < 0:
			continue

		var base_pos := Vector2(
				float(start_tx) * ts + float(region.size.x) * 0.5,
				float(edge_y) * ts + float(region.size.y) * 0.5)
		var trend: int = next_y - prev_y
		var flip_h := trend < 0
		var flip_v := not is_top_bank
		_add_prop_sprite(_bank_curve_texture, region, base_pos, float(region.size.x),
				2, true, 0.0, Color(1.0, 1.0, 1.0, 0.98), false, flip_h, flip_v)

		for cover_tx in range(start_tx, mini(data.width, start_tx + cover_tiles)):
			covered[cover_tx] = true


func _bank_edge_y(data: RiverData, tx: int, is_top_bank: bool) -> int:
	if tx < 0 or tx >= data.width:
		return -1
	return int(data.top_bank_profile[tx]) - 1 if is_top_bank else int(data.bottom_bank_profile[tx])


func _average_bank_edge_y(data: RiverData, start_tx: int, width_tiles: int, is_top_bank: bool) -> int:
	var total := 0
	var count := 0
	for tx in range(start_tx, mini(data.width, start_tx + width_tiles)):
		var edge_y := _bank_edge_y(data, tx, is_top_bank)
		if edge_y < 0:
			continue
		total += edge_y
		count += 1
	if count == 0:
		return -1
	return int(round(float(total) / float(count)))


func _curve_bank_edge_y(data: RiverData, start_tx: int, width_tiles: int, is_top_bank: bool) -> int:
	var edge_value := -1
	for tx in range(start_tx, mini(data.width, start_tx + width_tiles)):
		var edge_y := _bank_edge_y(data, tx, is_top_bank)
		if edge_y < 0:
			continue
		if edge_value < 0:
			edge_value = edge_y
		elif is_top_bank:
			edge_value = mini(edge_value, edge_y)
		else:
			edge_value = maxi(edge_value, edge_y)
	return edge_value


func _build_weed_feature_sprites(data: RiverData) -> void:
	if _weed_texture == null:
		return
	var ts := float(RiverConstants.TILE_SIZE)
	for structure: Dictionary in data.structures:
		if (structure["type"] as int) != RiverConstants.TILE_WEED_BED:
			continue
		var sx: int = structure["x"]
		var sy: int = structure["y"]
		var sw: int = structure["w"]
		var sh: int = structure["h"]
		var rng := RandomNumberGenerator.new()
		rng.seed = data.seed ^ (sx * 3811) ^ (sy * 9437)
		var region := _pick_region(_RiverSpriteAtlas.weed_regions(), rng)
		var cx := (float(sx) + float(sw) * 0.5) * ts
		var cy := (float(sy) + float(sh) * 0.5) * ts
		_add_prop_sprite(_weed_texture, region, Vector2(cx, cy),
				float(sw) * ts * rng.randf_range(0.42, 0.58), 1, true,
				rng.randf_range(-8.0, 8.0), Color(1.0, 1.0, 1.0, 0.74), true)


func _draw_log_sprite(cx: float, cy: float, length: float, angle: float,
		rng: RandomNumberGenerator) -> bool:
	if _log_texture == null:
		return false
	var region := _pick_region(_RiverSpriteAtlas.log_regions(), rng)
	return _add_prop_sprite(_log_texture, region, Vector2(cx, cy),
			length * 0.68, 2, true, angle, Color(1.0, 1.0, 1.0, 0.90), true)


func _draw_rock_cluster_sprite(cx: float, cy: float, cells: Array, is_boulder: bool,
		ts: float, rng: RandomNumberGenerator) -> bool:
	if _boulder_texture == null:
		return false

	var min_tx := 999999
	var max_tx := 0
	var min_ty := 999999
	var max_ty := 0
	for c in cells:
		var cv: Vector2i = c
		min_tx = mini(min_tx, cv.x)
		max_tx = maxi(max_tx, cv.x)
		min_ty = mini(min_ty, cv.y)
		max_ty = maxi(max_ty, cv.y)

	var footprint_w := float(max_tx - min_tx + 1) * ts
	var footprint_h := float(max_ty - min_ty + 1) * ts
	var regions := _RiverSpriteAtlas.in_river_boulder_regions() \
			if is_boulder or cells.size() > 2 else _RiverSpriteAtlas.in_river_rock_regions()
	var region := _pick_region(regions, rng)
	var target_w := maxf(footprint_w * rng.randf_range(0.85, 1.10), ts * (1.05 if is_boulder else 0.70))
	var sprite_y := cy + footprint_h * 0.08

	return _add_prop_sprite(_boulder_texture, region, Vector2(cx, sprite_y),
			target_w, 2, true, rng.randf_range(-4.0, 4.0), Color(1.0, 1.0, 1.0, 0.96), true)


func _build_sandbar_sprites(data: RiverData) -> void:
	if _sandbar_texture == null:
		return
	var ts := float(RiverConstants.TILE_SIZE)
	for structure: Dictionary in data.structures:
		if (structure["type"] as int) != RiverConstants.TILE_GRAVEL_BAR:
			continue
		var sx: int = structure["x"]
		var sy: int = structure["y"]
		var sw: int = structure["w"]
		var sh: int = structure["h"]
		var rng := RandomNumberGenerator.new()
		rng.seed = data.seed ^ (sx * 6983) ^ (sy * 1237)
		var target_size := Vector2(float(sw) * ts * 0.9, float(sh) * ts * 1.6)
		var region := _pick_best_region(_RiverSpriteAtlas.sandbar_regions(), target_size, rng)
		var cx := (float(sx) + float(sw) * 0.5) * ts
		var cy := (float(sy) + float(sh) * 0.5) * ts
		var target_width := minf(float(region.size.x), maxf(float(sw) * ts * rng.randf_range(0.78, 0.98), ts * 1.8))
		_add_prop_sprite(_sandbar_texture, region, Vector2(cx, cy),
				target_width, 1, true, rng.randf_range(-6.0, 6.0), Color(1.0, 1.0, 1.0, 0.86), false)


# ---------------------------------------------------------------------------
# Bank features — scattered trees, bushes, boulders on bank tiles
# ---------------------------------------------------------------------------

func _build_bank_features(data: RiverData) -> void:
	var ts  := float(RiverConstants.TILE_SIZE)
	var rng := RandomNumberGenerator.new()
	rng.seed = data.seed ^ 0xBADF00D

	# Every column — continuous ground cover
	for tx in range(data.width):
		for ty in range(data.height):
			if data.tile_map[tx][ty] != RiverConstants.TILE_BANK:
				continue
			var bank_band := _bank_band(data, tx, ty)
			if bank_band <= 0:
				continue

			var wx  := float(tx) * ts + rng.randf_range(ts * 0.1, ts * 0.9)
			var wy  := float(ty) * ts + rng.randf_range(ts * 0.1, ts * 0.9)
			var roll := _hash(tx * 43 + 17, ty * 89 + 23)
			var tree_chance := BANK_TREE_CHANCE * (1.9 if bank_band >= 2 else 0.55)
			var grass_chance := BANK_GRASS_CHANCE * (1.15 if bank_band == 1 else 0.80)
			var boulder_chance := BANK_BOULDER_CHANCE * (0.45 if bank_band == 1 else 0.90)

			if roll < tree_chance:
				_draw_bank_tree(wx, wy, ts, rng)
				continue
			if roll < tree_chance + grass_chance:
				_draw_bank_bush(wx, wy, ts, rng)
			if _hash(tx * 17 + 11, ty * 31 + 7) < boulder_chance:
				_draw_bank_boulder(wx, wy, ts, rng)


func _draw_bank_tree(wx: float, wy: float, ts: float, rng: RandomNumberGenerator) -> void:
	if _tree_texture == null:
		return
	var region := _pick_region(_RiverSpriteAtlas.tree_regions(), rng)
	var width := ts * rng.randf_range(1.25, 1.85)
	var scale := width / float(region.size.x)
	var sprite_pos := Vector2(wx, wy - float(region.size.y) * scale * 0.5)
	_add_prop_sprite(_tree_texture, region, sprite_pos, width, 3, true)


func _draw_bank_bush(wx: float, wy: float, ts: float, rng: RandomNumberGenerator) -> void:
	if _tree_texture == null:
		return
	var region := _pick_region(_RiverSpriteAtlas.shrub_regions(), rng)
	var width := ts * rng.randf_range(0.85, 1.35)
	_add_prop_sprite(_tree_texture, region, Vector2(wx, wy), width, 1, true,
			rng.randf_range(-4.0, 4.0), Color(1.0, 1.0, 1.0, 0.86))


func _draw_bank_boulder(wx: float, wy: float, ts: float, rng: RandomNumberGenerator) -> void:
	if _boulder_texture == null:
		return
	var region := _pick_region(_RiverSpriteAtlas.bank_boulder_regions(), rng)
	var width := ts * rng.randf_range(0.45, 0.95)
	_add_prop_sprite(_boulder_texture, region, Vector2(wx, wy), width, 2, true)


# ---------------------------------------------------------------------------
# Node cleanup
# ---------------------------------------------------------------------------

func _clear_chunks() -> void:
	for s in _chunk_sprites:
		if is_instance_valid(s): s.queue_free()
	_chunk_sprites.clear()


func _clear_rock_nodes() -> void:
	for n in _rock_nodes:
		if is_instance_valid(n): n.queue_free()
	_rock_nodes.clear()


func _clear_debug_nodes() -> void:
	for n in _debug_nodes:
		if is_instance_valid(n): n.queue_free()
	_debug_nodes.clear()
