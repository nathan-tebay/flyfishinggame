class_name RiverRenderer
extends TileMap

# Renders RiverData onto the TileMap using programmatically generated
# placeholder colour tiles. Replace with a proper TileSet asset in Phase 8.


var _tileset_built := false


# Call once before first render — idempotent.
func build_tileset() -> void:
	if _tileset_built:
		return

	var ts := TileSet.new()
	ts.tile_size = Vector2i(RiverConstants.TILE_SIZE, RiverConstants.TILE_SIZE)

	for tile_id: int in RiverConstants.TILE_COLORS:
		var source := TileSetAtlasSource.new()
		var img    := Image.create(RiverConstants.TILE_SIZE, RiverConstants.TILE_SIZE, false, Image.FORMAT_RGBA8)
		img.fill(RiverConstants.TILE_COLORS[tile_id])
		source.texture              = ImageTexture.create_from_image(img)
		source.texture_region_size  = Vector2i(RiverConstants.TILE_SIZE, RiverConstants.TILE_SIZE)
		source.create_tile(Vector2i.ZERO)
		ts.add_source(source, tile_id)

	tile_set = ts

	# Ensure three layers exist: Base | Structures | Debug
	while get_layers_count() < 3:
		add_layer(-1)
	set_layer_name(RiverConstants.LAYER_BASE,       "Base")
	set_layer_name(RiverConstants.LAYER_STRUCTURES, "Structures")
	set_layer_name(RiverConstants.LAYER_DEBUG,      "Debug")

	_tileset_built = true


func render(data: RiverData) -> void:
	build_tileset()
	clear()
	_paint_base(data)
	_paint_structures(data)


func show_hold_debug(data: RiverData, top_n: int = 30) -> void:
	# Tint the top hold positions bright green for debugging
	build_tileset()
	for i in mini(top_n, data.top_holds.size()):
		var hold: Dictionary = data.top_holds[i]
		set_cell(RiverConstants.LAYER_DEBUG,
			Vector2i(hold["x"], hold["y"]),
			RiverConstants.TILE_SURFACE,
			Vector2i.ZERO)


func hide_hold_debug() -> void:
	clear_layer(RiverConstants.LAYER_DEBUG)


# ---------------------------------------------------------------------------
# Private
# ---------------------------------------------------------------------------

func _paint_base(data: RiverData) -> void:
	for x in data.width:
		for y in data.height:
			var tile_type: int = data.tile_map[x][y]
			if tile_type == RiverConstants.TILE_AIR:
				continue
			set_cell(RiverConstants.LAYER_BASE, Vector2i(x, y), tile_type, Vector2i.ZERO)


func _paint_structures(data: RiverData) -> void:
	# Structures are already baked into tile_map.
	# Re-paint them on the STRUCTURES layer so they can be toggled independently.
	for structure: Dictionary in data.structures:
		var tile_type: int = structure["type"]
		var sx: int = structure["x"]
		var sy: int = structure["y"]
		var sw: int = structure["w"]
		var sh: int = structure["h"]

		for dx in sw:
			for dy in sh:
				var tx := sx + dx
				var ty := sy + dy
				if tx >= 0 and tx < data.width and ty >= 0 and ty < data.height:
					if data.tile_map[tx][ty] == tile_type:
						set_cell(RiverConstants.LAYER_STRUCTURES, Vector2i(tx, ty), tile_type, Vector2i.ZERO)
