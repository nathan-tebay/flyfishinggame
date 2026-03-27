class_name RiverRenderer
extends TileMap

# Renders RiverData onto the TileMap using programmatically generated
# gradient tiles for a 32-bit SNES-era look.
# Animated ripple chevrons are drawn on top via _draw(), indicating current direction.


var _tileset_built := false
var _river_data: RiverData = null
var _time: float = 0.0

# Sparse list of ripple anchors: { wx, wy, speed, phase }
var _ripples: Array = []


# Call once before first render — idempotent.
func build_tileset() -> void:
	if _tileset_built:
		return

	var ts := TileSet.new()
	ts.tile_size = Vector2i(RiverConstants.TILE_SIZE, RiverConstants.TILE_SIZE)

	for tile_id: int in RiverConstants.TILE_COLORS:
		var source := TileSetAtlasSource.new()
		var img    := _make_tile_image(tile_id)
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
	_river_data = data
	_build_ripples(data)


func show_hold_debug(data: RiverData, top_n: int = 30) -> void:
	build_tileset()
	for i in mini(top_n, data.top_holds.size()):
		var hold: Dictionary = data.top_holds[i]
		set_cell(RiverConstants.LAYER_DEBUG,
			Vector2i(hold["x"], hold["y"]),
			RiverConstants.TILE_SURFACE,
			Vector2i.ZERO)


func hide_hold_debug() -> void:
	clear_layer(RiverConstants.LAYER_DEBUG)


func _process(delta: float) -> void:
	if _river_data != null:
		_time += delta
		queue_redraw()


# ---------------------------------------------------------------------------
# Ripple animation — drawn over tiles each frame
# ---------------------------------------------------------------------------

func _draw() -> void:
	if _river_data == null:
		return
	_draw_ripples()


func _build_ripples(data: RiverData) -> void:
	_ripples.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = data.seed ^ 0xCAFEBABE
	var ts  := float(RiverConstants.TILE_SIZE)
	const TARGET := 300

	var placed := 0
	var attempts := TARGET * 12
	for _i in attempts:
		if placed >= TARGET:
			break
		var tx := rng.randi_range(0, data.width - 1)
		var ty := rng.randi_range(RiverConstants.BANK_H_TILES, data.height - 1)
		var tile: int = data.tile_map[tx][ty]
		if tile != RiverConstants.TILE_SURFACE and \
		   tile != RiverConstants.TILE_MID_DEPTH and \
		   tile != RiverConstants.TILE_DEEP:
			continue
		var speed: float = data.current_map[tx][ty]
		if speed < 0.12:
			continue  # still eddies — no ripples
		_ripples.append({
			"wx":    float(tx) * ts + rng.randf_range(2.0, ts - 2.0),
			"wy":    float(ty) * ts + rng.randf_range(2.0, ts - 2.0),
			"speed": speed,
			"phase": rng.randf() * TAU,
		})
		placed += 1


func _draw_ripples() -> void:
	const CYCLE := 56.0   # pixels per animation cycle (downstream = +x)
	for r in _ripples:
		var rd: Dictionary = r
		var spd: float  = rd["speed"]
		var phase: float = rd["phase"]
		var base_x: float = rd["wx"]
		var wy: float     = rd["wy"]

		# Animated x offset — ripple travels rightward (downstream, +x direction)
		var offset: float = fmod(_time * spd * 55.0 + phase * (CYCLE / TAU), CYCLE)
		var wx: float = base_x + offset

		var alpha := spd * 0.45
		var sz    := lerpf(3.5, 9.0, spd)
		var col   := Color(1.0, 1.0, 1.0, alpha)

		# V-chevron pointing right (downstream)
		draw_line(Vector2(wx,        wy),          Vector2(wx + sz, wy - sz * 0.45), col, 1.2)
		draw_line(Vector2(wx,        wy),          Vector2(wx + sz, wy + sz * 0.45), col, 1.2)
		# Faint trailing arm for depth
		draw_line(Vector2(wx - sz * 0.6, wy - sz * 0.30), Vector2(wx, wy), col * Color(1,1,1,0.5), 0.8)
		draw_line(Vector2(wx - sz * 0.6, wy + sz * 0.30), Vector2(wx, wy), col * Color(1,1,1,0.5), 0.8)


# ---------------------------------------------------------------------------
# Private — tile painting
# ---------------------------------------------------------------------------

func _paint_base(data: RiverData) -> void:
	for x in data.width:
		for y in data.height:
			var tile_type: int = data.tile_map[x][y]
			if tile_type == RiverConstants.TILE_AIR:
				continue
			set_cell(RiverConstants.LAYER_BASE, Vector2i(x, y), tile_type, Vector2i.ZERO)


func _paint_structures(data: RiverData) -> void:
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


# ---------------------------------------------------------------------------
# 32-bit gradient tile generation
# ---------------------------------------------------------------------------

func _make_tile_image(tile_id: int) -> Image:
	var sz  := RiverConstants.TILE_SIZE
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var base: Color = RiverConstants.TILE_COLORS.get(tile_id, Color.MAGENTA)

	match tile_id:
		RiverConstants.TILE_BANK:
			_fill_bank(img, base, sz)
		RiverConstants.TILE_SURFACE:
			_fill_water(img, base, sz, 0.10, 0.06)
		RiverConstants.TILE_MID_DEPTH:
			_fill_water(img, base, sz, 0.14, 0.10)
		RiverConstants.TILE_DEEP:
			_fill_water(img, base, sz, 0.18, 0.12)
		RiverConstants.TILE_RIVERBED:
			_fill_riverbed(img, base, sz)
		RiverConstants.TILE_WEED_BED:
			_fill_weed(img, base, sz)
		RiverConstants.TILE_ROCK, RiverConstants.TILE_BOULDER:
			_fill_rock(img, base, sz)
		RiverConstants.TILE_UNDERCUT_BANK:
			_fill_undercut(img, base, sz)
		RiverConstants.TILE_GRAVEL_BAR:
			_fill_gravel(img, base, sz)
		_:
			img.fill(base)

	return img


# Bank: vertical gradient — lighter at top (sky-lit), darker soil below
func _fill_bank(img: Image, base: Color, sz: int) -> void:
	for py in sz:
		var t := float(py) / float(sz)
		var c := base.lightened(0.18 * (1.0 - t)).darkened(t * 0.12)
		# Subtle horizontal dither for organic texture
		for px in sz:
			var d := 0.03 if ((px + py) % 3 == 0) else 0.0
			img.set_pixel(px, py, c.lightened(d))


# Water: horizontal shimmer gradient (lighter left, subtle dark right) + depth darkening
func _fill_water(img: Image, base: Color, sz: int, vert_dark: float, horiz_var: float) -> void:
	for py in sz:
		var vy := float(py) / float(sz)
		for px in sz:
			var vx := float(px) / float(sz)
			# Horizontal shimmer band
			var shimmer := sin(vx * PI * 2.2) * horiz_var * 0.5 + horiz_var * 0.5
			var c := base.darkened(vy * vert_dark).lightened(shimmer)
			# Fine dither for 32-bit texture feel
			if (px % 4 == 1) and (py % 4 == 1):
				c = c.lightened(0.06)
			elif (px % 4 == 3) and (py % 4 == 3):
				c = c.darkened(0.04)
			img.set_pixel(px, py, c)


# Riverbed: pebble suggestion via noise-like pattern
func _fill_riverbed(img: Image, base: Color, sz: int) -> void:
	for py in sz:
		var vy := float(py) / float(sz)
		for px in sz:
			var vx := float(px) / float(sz)
			# Pebble clusters using value noise approximation
			var n := sin(vx * 7.3 + 1.1) * cos(vy * 5.9 + 0.7) * 0.5 + 0.5
			var c := base.lerp(base.lightened(0.25), n * 0.4)
			c = c.darkened(vy * 0.08)
			img.set_pixel(px, py, c)


# Weed bed: irregular dark-green pattern
func _fill_weed(img: Image, base: Color, sz: int) -> void:
	for py in sz:
		for px in sz:
			var n := sin(float(px) * 1.7) * cos(float(py) * 2.3) * 0.5 + 0.5
			var c := base.lerp(base.lightened(0.20), n)
			if (px + py * 2) % 5 == 0:
				c = c.darkened(0.15)
			img.set_pixel(px, py, c)


# Rock/boulder: gray gradient with highlight on upper-left edge
func _fill_rock(img: Image, base: Color, sz: int) -> void:
	for py in sz:
		var vy := float(py) / float(sz - 1)
		for px in sz:
			var vx := float(px) / float(sz - 1)
			# Light from upper-left
			var light := (1.0 - vx) * 0.2 + (1.0 - vy) * 0.15
			var dark  := vx * 0.12 + vy * 0.10
			var c := base.lightened(light).darkened(dark)
			img.set_pixel(px, py, c)


# Undercut bank: dark earthy tone with root-like horizontal streaks
func _fill_undercut(img: Image, base: Color, sz: int) -> void:
	for py in sz:
		var vy := float(py) / float(sz)
		for px in sz:
			var streak := 0.08 if (py % 5 < 2) else 0.0
			var c := base.darkened(vy * 0.20 + streak)
			img.set_pixel(px, py, c)


# Gravel bar: sandy texture with small-grain dither
func _fill_gravel(img: Image, base: Color, sz: int) -> void:
	for py in sz:
		for px in sz:
			var grain := 0.06 if ((px * 3 + py * 7) % 4 == 0) else 0.0
			var c := base.lightened(grain).darkened(float(py) / float(sz) * 0.06)
			img.set_pixel(px, py, c)
