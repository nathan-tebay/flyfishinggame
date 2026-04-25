extends SceneTree

const _SpriteCatalog = preload("res://scripts/assets/sprite_catalog.gd")

const _TILE_SIZE := 32
const _DEPTH_TILE_COLS := 7
const _DEPTH_TILE_ROWS := 5
const _TRANSITION_TILE_COLS := 11
const _TRANSITION_TILE_ROWS := 5

const _DEPTH_BLOCKS := {
	"shallow": [
		Rect2i(48, 140, 231, 166),
		Rect2i(48, 327, 231, 165),
		Rect2i(48, 512, 231, 166),
	],
	"mid": [
		Rect2i(305, 140, 230, 166),
		Rect2i(305, 327, 230, 165),
		Rect2i(304, 512, 231, 166),
	],
	"deep": [
		Rect2i(562, 139, 228, 166),
		Rect2i(561, 327, 229, 164),
		Rect2i(561, 511, 229, 166),
	],
}

const _TRANSITION_BLOCKS := {
	"shallow_to_mid": [
		Rect2i(859, 137, 370, 167),
		Rect2i(859, 327, 370, 165),
		Rect2i(859, 512, 370, 166),
	],
	"mid_to_deep": [
		Rect2i(1251, 137, 373, 167),
		Rect2i(1250, 327, 374, 165),
		Rect2i(1250, 512, 374, 166),
	],
	"shallow_to_deep": [
		Rect2i(1646, 137, 371, 167),
		Rect2i(1646, 327, 371, 165),
		Rect2i(1646, 512, 371, 166),
	],
}


func _initialize() -> void:
	var source := Image.new()
	var err := source.load(ProjectSettings.globalize_path(_SpriteCatalog.WATER_DEPTHS_TRANSITIONS))
	if err != OK:
		push_error("Failed to load %s" % _SpriteCatalog.WATER_DEPTHS_TRANSITIONS)
		quit(1)
		return

	var out_root := "res://assets/terrain/water"
	_make_dir(out_root)
	_make_dir(out_root.path_join("transitions"))

	var manifest := {
		"source": _SpriteCatalog.WATER_DEPTHS_TRANSITIONS,
		"tile_size": _TILE_SIZE,
		"categories": {},
	}

	for category in _DEPTH_BLOCKS.keys():
		var category_path := out_root.path_join(category)
		_make_dir(category_path)
		var count := _export_block_group(
				source,
				_DEPTH_BLOCKS[category],
				category_path,
				category,
				_DEPTH_TILE_COLS,
				_DEPTH_TILE_ROWS)
		manifest["categories"][category] = {
			"kind": "depth",
			"count": count,
			"blocks": _DEPTH_BLOCKS[category],
		}

	for category in _TRANSITION_BLOCKS.keys():
		var category_path := out_root.path_join("transitions").path_join(category)
		_make_dir(category_path)
		var count := _export_block_group(
				source,
				_TRANSITION_BLOCKS[category],
				category_path,
				category,
				_TRANSITION_TILE_COLS,
				_TRANSITION_TILE_ROWS)
		manifest["categories"][category] = {
			"kind": "transition",
			"count": count,
			"blocks": _TRANSITION_BLOCKS[category],
		}

	var manifest_file := FileAccess.open(
			ProjectSettings.globalize_path(out_root.path_join("manifest.json")),
			FileAccess.WRITE)
	if manifest_file == null:
		push_error("Failed to write water tile manifest")
		quit(1)
		return
	manifest_file.store_string(JSON.stringify(manifest, "\t"))
	print("Water tiles exported to %s" % out_root)
	quit()


func _export_block_group(source: Image, blocks: Array, out_dir: String, prefix: String,
		cols: int, rows: int) -> int:
	var count := 0
	for block_index in range(blocks.size()):
		var block: Rect2i = blocks[block_index]
		var crop := _centered_crop(block, cols * _TILE_SIZE, rows * _TILE_SIZE)
		for row in range(rows):
			for col in range(cols):
				var tile_rect := Rect2i(
						crop.position + Vector2i(col * _TILE_SIZE, row * _TILE_SIZE),
						Vector2i(_TILE_SIZE, _TILE_SIZE))
				var tile := source.get_region(tile_rect)
				var file_name := "%s_%03d.png" % [prefix, count + 1]
				tile.save_png(ProjectSettings.globalize_path(out_dir.path_join(file_name)))
				count += 1
	return count


func _centered_crop(block: Rect2i, width: int, height: int) -> Rect2i:
	var offset_x := maxi(0, int(floor(float(block.size.x - width) * 0.5)))
	var offset_y := maxi(0, int(floor(float(block.size.y - height) * 0.5)))
	return Rect2i(block.position + Vector2i(offset_x, offset_y), Vector2i(width, height))


func _make_dir(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))
