extends SceneTree

const _SOURCE_PATH := "res://assets/terrain/reference/snes_river_tiles_target_v2.png"
const _OUT_ROOT := "res://assets/terrain/modules"
const _MODULE_SIZE := 64

const _COLS := [
	Rect2i(36, 0, 105, 0),
	Rect2i(153, 0, 104, 0),
	Rect2i(269, 0, 103, 0),
	Rect2i(384, 0, 104, 0),
	Rect2i(539, 0, 105, 0),
	Rect2i(656, 0, 104, 0),
	Rect2i(772, 0, 104, 0),
	Rect2i(888, 0, 104, 0),
	Rect2i(1047, 0, 104, 0),
	Rect2i(1163, 0, 103, 0),
	Rect2i(1278, 0, 104, 0),
	Rect2i(1394, 0, 104, 0),
]

const _ROWS := [
	Rect2i(0, 56, 0, 104),
	Rect2i(0, 172, 0, 104),
	Rect2i(0, 346, 0, 103),
	Rect2i(0, 461, 0, 104),
	Rect2i(0, 634, 0, 104),
	Rect2i(0, 750, 0, 104),
]

const _CATEGORY_SPECS := [
	{
		"name": "water_shallow",
		"dir": _OUT_ROOT + "/water/shallow",
		"prefix": "shallow",
		"cells": [
			Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0),
			Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1),
		],
	},
	{
		"name": "water_mid",
		"dir": _OUT_ROOT + "/water/mid",
		"prefix": "mid",
		"cells": [
			Vector2i(4, 0), Vector2i(5, 0), Vector2i(6, 0), Vector2i(7, 0),
			Vector2i(4, 1), Vector2i(5, 1), Vector2i(6, 1), Vector2i(7, 1),
		],
	},
	{
		"name": "water_deep",
		"dir": _OUT_ROOT + "/water/deep",
		"prefix": "deep",
		"cells": [
			Vector2i(8, 0), Vector2i(9, 0), Vector2i(10, 0), Vector2i(11, 0),
			Vector2i(8, 1), Vector2i(9, 1), Vector2i(10, 1), Vector2i(11, 1),
		],
	},
	{
		"name": "shoreline_edge",
		"dir": _OUT_ROOT + "/shoreline/edge",
		"prefix": "shoreline_edge",
		"cells": [
			Vector2i(8, 2), Vector2i(9, 2), Vector2i(10, 2), Vector2i(11, 2),
			Vector2i(8, 3), Vector2i(9, 3), Vector2i(10, 3), Vector2i(11, 3),
		],
	},
	{
		"name": "shoreline_outer_corner",
		"dir": _OUT_ROOT + "/shoreline/outer_corner",
		"prefix": "shoreline_outer_corner",
		"cells": [
			Vector2i(0, 4), Vector2i(1, 4), Vector2i(2, 4), Vector2i(3, 4),
			Vector2i(0, 5), Vector2i(1, 5), Vector2i(2, 5), Vector2i(3, 5),
		],
	},
	{
		"name": "shoreline_inner_corner",
		"dir": _OUT_ROOT + "/shoreline/inner_corner",
		"prefix": "shoreline_inner_corner",
		"cells": [
			Vector2i(4, 4), Vector2i(5, 4), Vector2i(6, 4), Vector2i(7, 4),
			Vector2i(4, 5), Vector2i(5, 5), Vector2i(6, 5), Vector2i(7, 5),
		],
	},
	{
		"name": "gravel_bar",
		"dir": _OUT_ROOT + "/gravel_bar",
		"prefix": "gravel_bar",
		"cells": [
			Vector2i(8, 4), Vector2i(9, 4), Vector2i(10, 4), Vector2i(11, 4),
			Vector2i(8, 5), Vector2i(9, 5), Vector2i(10, 5), Vector2i(11, 5),
		],
	},
]


func _initialize() -> void:
	var source := Image.new()
	var err := source.load(ProjectSettings.globalize_path(_SOURCE_PATH))
	if err != OK:
		push_error("Failed to load SNES module reference sheet")
		quit(1)
		return

	var manifest := {
		"source": _SOURCE_PATH,
		"module_size": _MODULE_SIZE,
		"categories": {},
	}

	for spec_variant in _CATEGORY_SPECS:
		var spec: Dictionary = spec_variant
		var out_dir := spec["dir"] as String
		_reset_dir(out_dir)
		var exported := []
		var cells: Array = spec["cells"] as Array
		for output_index in range(cells.size()):
			var cell: Vector2i = cells[output_index]
			var rect := Rect2i(
					_COLS[cell.x].position.x,
					_ROWS[cell.y].position.y,
					_COLS[cell.x].size.x,
					_ROWS[cell.y].size.y)
			var tile := source.get_region(rect)
			tile.resize(_MODULE_SIZE, _MODULE_SIZE, Image.INTERPOLATE_BILINEAR)
			_seal_module_edges(tile)
			var file_name := "%s_%03d.png" % [spec["prefix"], output_index + 1]
			var out_path := out_dir.path_join(file_name)
			tile.save_png(ProjectSettings.globalize_path(out_path))
			exported.append({
				"file": out_path,
				"source_rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y],
				"source_cell": [cell.x, cell.y],
			})
		manifest["categories"][spec["name"]] = {
			"dir": out_dir,
			"count": exported.size(),
			"tiles": exported,
		}

	var manifest_path := _OUT_ROOT.path_join("manifest.json")
	var file := FileAccess.open(ProjectSettings.globalize_path(manifest_path), FileAccess.WRITE)
	if file == null:
		push_error("Failed to write module manifest")
		quit(1)
		return
	file.store_string(JSON.stringify(manifest, "\t"))
	print("SNES runtime modules exported to %s" % _OUT_ROOT)
	quit()


func _seal_module_edges(tile: Image) -> void:
	var w := tile.get_width()
	var h := tile.get_height()
	if w < 8 or h < 8:
		return

	for y in range(h):
		var left_src := tile.get_pixel(3, y)
		var right_src := tile.get_pixel(w - 4, y)
		tile.set_pixel(0, y, left_src)
		tile.set_pixel(1, y, left_src)
		tile.set_pixel(w - 2, y, right_src)
		tile.set_pixel(w - 1, y, right_src)

	for x in range(w):
		var top_src := tile.get_pixel(x, 3)
		var bottom_src := tile.get_pixel(x, h - 4)
		tile.set_pixel(x, 0, top_src)
		tile.set_pixel(x, 1, top_src)
		tile.set_pixel(x, h - 2, bottom_src)
		tile.set_pixel(x, h - 1, bottom_src)


func _reset_dir(path: String) -> void:
	var abs_path := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(abs_path)
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	while true:
		var entry := dir.get_next()
		if entry.is_empty():
			break
		if dir.current_is_dir():
			continue
		if entry.to_lower().ends_with(".png"):
			DirAccess.remove_absolute(abs_path.path_join(entry))
	dir.list_dir_end()
