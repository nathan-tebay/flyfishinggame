class_name RiverRenderer
extends TileMap  # kept for scene-tree compatibility; tile layers are unused

const _SpriteCatalog = preload("res://scripts/assets/sprite_catalog.gd")

# River rendered as a continuous depth field.
#
# Pipeline per section:
#   1. Build a float depth map from tile types (_DEPTH_RANK_F)
#   2. Blur it with 2 separable box-blur passes (~4-tile transition width)
#   3. For each 32×32 tile, bilinearly interpolate the blurred depth at its
#      4 corners → map through a multi-stop colour gradient → cache the result
#   4. blit_rect every tile from the cache — zero per-pixel GDScript at render time
#   5. Rock/boulder clusters drawn as Polygon2D + Line2D child nodes (unchanged)
#
# Transitions are 100-150 px wide, organic, and have no grid artifacts.

# Continuous depth rank per tile type — finer than the old integer ranks.
const _DEPTH_RANK_F: Dictionary = {
	RiverConstants.TILE_BANK:          0.0,
	RiverConstants.TILE_UNDERCUT_BANK: 0.7,
	RiverConstants.TILE_GRAVEL_BAR:    1.1,
	RiverConstants.TILE_SURFACE:       2.0,
	RiverConstants.TILE_WEED_BED:      2.4,
	RiverConstants.TILE_ROCK:          2.9,
	RiverConstants.TILE_LOG:           2.6,  # slightly darker than surface — shaded water under log
	RiverConstants.TILE_MID_DEPTH:     3.0,
	RiverConstants.TILE_BOULDER:       3.8,
	RiverConstants.TILE_DEEP:          4.0,
}

# Multi-stop depth→colour gradient.
# Covers: grass bank → wet mud → gravel → shallows → weeds → blue mid → deep navy.
# Contrast reduced ~25% vs initial version; gravel (1.1) and weed bed (2.4) have
# explicit stops so they read as distinct habitat rather than blending into plain water.
const _DEPTH_STOPS: Array = [
	[0.0, Color(0.24, 0.52, 0.14)],   # bank grass
	[0.5, Color(0.28, 0.46, 0.15)],   # bank edge
	[0.85,Color(0.36, 0.37, 0.18)],   # wet bank / mud
	[1.1, Color(0.66, 0.60, 0.38)],   # gravel bar — warm sandy tan
	[1.5, Color(0.44, 0.76, 0.80)],   # waterline — blue-teal (no green)
	[2.0, Color(0.40, 0.72, 0.84)],   # surface water
	[2.4, Color(0.22, 0.48, 0.60)],   # weed bed — blue-teal (distinct, no green cast)
	[2.7, Color(0.28, 0.62, 0.82)],   # transition back to water
	[3.0, Color(0.16, 0.48, 0.76)],   # mid-depth
	[3.5, Color(0.10, 0.33, 0.64)],   # mid-deep
	[4.0, Color(0.07, 0.20, 0.50)],   # deep channel
]

const _TREE_REGIONS: Array = [
	Rect2i(669, 88, 146, 331),
	Rect2i(421, 89, 178, 328),
	Rect2i(320, 495, 231, 346),
	Rect2i(608, 565, 201, 268),
	Rect2i(739, 991, 144, 260),
]

const _BOULDER_REGIONS: Array = [
	Rect2i(1336, 123, 120, 108),
	Rect2i(1494, 129, 131, 99),
	Rect2i(1666, 131, 118, 102),
	Rect2i(572, 161, 105, 95),
	Rect2i(708, 176, 73, 69),
	Rect2i(1348, 251, 117, 86),
]

const _GRASS_REGIONS: Array = [
	Rect2i(820, 1188, 151, 183),
	Rect2i(1424, 1189, 175, 210),
	Rect2i(1184, 1177, 158, 193),
	Rect2i(200, 1196, 158, 167),
]

const _WEED_REGIONS: Array = [
	Rect2i(651, 474, 237, 193),
	Rect2i(232, 480, 153, 156),
	Rect2i(426, 480, 191, 176),
]

const _LOG_REGIONS: Array = [
	Rect2i(963, 472, 299, 176),
	Rect2i(1256, 494, 252, 148),
	Rect2i(1807, 513, 189, 135),
]

var _river_data: RiverData = null

# Child nodes — freed and rebuilt on each render() call.
var _chunk_sprites: Array[Sprite2D] = []
var _rock_nodes:    Array[Node]     = []
var _debug_nodes:   Array[Node]     = []

# Blurred depth map — flat PackedFloat32Array, index = tx * height + ty.
var _depth_map:  PackedFloat32Array = PackedFloat32Array()
var _map_height: int = 0

# Depth-tile image cache — key encodes quantised corner depths.
var _depth_tile_cache: Dictionary = {}
var _tree_texture: Texture2D = null
var _boulder_texture: Texture2D = null
var _feature_texture: Texture2D = null


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func render(data: RiverData) -> void:
	_river_data = data
	_ensure_prop_textures()
	_clear_chunks()
	_clear_rock_nodes()
	_depth_tile_cache.clear()
	_build_depth_map(data)
	_apply_rock_effects(data)    # bow wave + wake written into depth map before chunk bake
	_apply_current_effects(data) # fast riffles lighter, slow pools darker
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
# Depth map — build once per section, reused across all 24 chunks
# ---------------------------------------------------------------------------

func _build_depth_map(data: RiverData) -> void:
	var w := data.width
	var h := data.height
	_map_height = h

	# Initialise from tile types
	_depth_map.resize(w * h)
	for tx in w:
		for ty in h:
			_depth_map[tx * h + ty] = _DEPTH_RANK_F.get(data.tile_map[tx][ty], 0.0)

	# Two passes of separable 3-tap box blur → effective transition width ~4 tiles (128 px).
	# A PackedFloat32Array is used so element access avoids GDScript Array overhead.
	var tmp := PackedFloat32Array()
	tmp.resize(w * h)

	for _pass in 2:
		# ── Blur in X ──
		for ty in h:
			tmp[0 * h + ty]       = _depth_map[0 * h + ty]
			tmp[(w-1) * h + ty]   = _depth_map[(w-1) * h + ty]
			for tx in range(1, w - 1):
				tmp[tx * h + ty] = (
					_depth_map[(tx-1) * h + ty] +
					_depth_map[ tx    * h + ty] +
					_depth_map[(tx+1) * h + ty]) / 3.0
		var swap := _depth_map; _depth_map = tmp; tmp = swap

		# ── Blur in Y ──
		for tx in w:
			tmp[tx * h + 0]     = _depth_map[tx * h + 0]
			tmp[tx * h + h - 1] = _depth_map[tx * h + h - 1]
			for ty in range(1, h - 1):
				tmp[tx * h + ty] = (
					_depth_map[tx * h + ty - 1] +
					_depth_map[tx * h + ty    ] +
					_depth_map[tx * h + ty + 1]) / 3.0
		swap = _depth_map; _depth_map = tmp; tmp = swap


func _depth_at(tx: int, ty: int, data: RiverData) -> float:
	return _depth_map[clampi(tx, 0, data.width - 1) * _map_height +
	                  clampi(ty, 0, _map_height - 1)]


# ---------------------------------------------------------------------------
# Rock flow effects — written into the depth map before chunks are baked
# ---------------------------------------------------------------------------
# Upstream = negative x (fish face upstream, river flows left→right).
# Bow wave: shallower water piling against the upstream face → lighter colour.
# V-wake:   deeper/darker turbulent water spreading downstream.
# Boulder scale factor is larger than rock.

func _apply_rock_effects(data: RiverData) -> void:
	var h := _map_height
	for tx in data.width:
		for ty in data.height:
			var tile: int = data.tile_map[tx][ty]
			if tile != RiverConstants.TILE_ROCK and tile != RiverConstants.TILE_BOULDER:
				continue
			var is_boulder := tile == RiverConstants.TILE_BOULDER

			# ── Bow wave upstream ────────────────────────────────────────────────
			var bow_reach := 5 if is_boulder else 3
			var bow_str   := 0.28 if is_boulder else 0.22
			for dx in range(1, bow_reach + 1):
				var ux := tx - dx
				if ux < 0: continue
				var f := 1.0 - float(dx) / float(bow_reach + 1)
				var lat := 2 if is_boulder else 1
				for dy in range(-lat, lat + 1):
					var uy := ty + dy
					if uy < 0 or uy >= h: continue
					var side_fade := 1.0 - float(abs(dy)) / float(lat + 1)
					var idx := ux * h + uy
					_depth_map[idx] = maxf(1.6, _depth_map[idx] - bow_str * f * side_fade)

			if is_boulder:
				# ── Boulder: dead-water zone + side eddies + long V-wake ─────────
				#
				# Zone 1 — Dead water (1–4 tiles directly behind): wide, dark, calm.
				# This is the prime holding lie — sheltered from current, food funnels in.
				for dx in range(1, 5):
					var wx := tx + dx
					if wx >= data.width: continue
					for dy in range(-2, 3):
						var wy := ty + dy
						if wy < 0 or wy >= h: continue
						var lateral_fade := 1.0 - float(abs(dy)) / 3.0
						var idx := wx * h + wy
						_depth_map[idx] = minf(4.0, _depth_map[idx] + 0.60 * lateral_fade)

				# Zone 2 — Side eddies (1–7 tiles, flanking the dead water):
				# The reverse-current pockets on each side of the boulder wake.
				for dx in range(1, 8):
					var wx := tx + dx
					if wx >= data.width: continue
					var eddy_f := 1.0 - float(dx) / 8.0
					for side in [-1, 1]:
						for dy_off in range(2, 5):
							var wy: int = ty + int(side) * dy_off
							if wy < 0 or wy >= h: continue
							var eddy_t := 1.0 - float(dy_off - 2) / 3.0
							var idx: int = wx * h + wy
							_depth_map[idx] = minf(4.0, _depth_map[idx] + 0.45 * eddy_f * eddy_t)

				# Zone 3 — Long V-wake (5–14 tiles): spreading turbulence line.
				for dx in range(5, 15):
					var wx := tx + dx
					if wx >= data.width: continue
					var f      := 1.0 - float(dx - 4) / 11.0
					var spread := maxf(2.0, float(dx) * 0.55)
					for dy in range(-ceili(spread) - 1, ceili(spread) + 2):
						var side_t := absf(float(dy)) / spread
						if side_t >= 1.0: continue
						var wy := ty + dy
						if wy < 0 or wy >= h: continue
						var idx := wx * h + wy
						_depth_map[idx] = minf(4.0, _depth_map[idx] + 0.28 * f * (1.0 - side_t * 0.55))
			else:
				# ── Rock: simple V-wake (1–6 tiles) ─────────────────────────────
				for dx in range(1, 7):
					var wx := tx + dx
					if wx >= data.width: continue
					var f      := 1.0 - float(dx) / 7.0
					var spread := maxf(1.0, float(dx) * 0.50)
					for dy in range(-ceili(spread) - 1, ceili(spread) + 2):
						var side_t := absf(float(dy)) / spread
						if side_t >= 1.0: continue
						var wy := ty + dy
						if wy < 0 or wy >= h: continue
						var idx := wx * h + wy
						_depth_map[idx] = minf(4.0, _depth_map[idx] + 0.38 * f * (1.0 - side_t * 0.65))


# ---------------------------------------------------------------------------
# Current effects — fast riffles raise surface reflection (lighter depth),
# slow pools stay dark.  Applied after rock effects, before chunk bake.
# ---------------------------------------------------------------------------

func _apply_current_effects(data: RiverData) -> void:
	var h := _map_height
	for tx in data.width:
		for ty in data.height:
			var tile: int = data.tile_map[tx][ty]
			# Only affect water tiles — leave bank/gravel untouched
			if tile == RiverConstants.TILE_BANK or tile == RiverConstants.TILE_UNDERCUT_BANK \
					or tile == RiverConstants.TILE_GRAVEL_BAR:
				continue
			var current: float = data.current_map[tx][ty]
			if current < 0.05:
				continue
			var idx := tx * h + ty
			# Fast water → shallower-looking (broken surface reflects more light)
			# Slow/eddy water → slightly deeper (dark glassy pool appearance)
			var delta := current * 0.22 - 0.04   # net effect: positive in fast, slight negative in slow
			_depth_map[idx] = clampf(_depth_map[idx] - delta, 1.4, 4.0)


# ---------------------------------------------------------------------------
# Chunk generation
# ---------------------------------------------------------------------------

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
			# Sample blurred depth at this tile's 4 corners
			var d00 := _depth_at(tx,     ty,     data)
			var d10 := _depth_at(tx + 1, ty,     data)
			var d01 := _depth_at(tx,     ty + 1, data)
			var d11 := _depth_at(tx + 1, ty + 1, data)

			var key := _tile_key(d00, d10, d01, d11)
			if not _depth_tile_cache.has(key):
				_depth_tile_cache[key] = _make_depth_tile(
					_q(d00), _q(d10), _q(d01), _q(d11))

			img.blit_rect(_depth_tile_cache[key],
				Rect2i(0, 0, ts, ts),
				Vector2i((tx - start_tx) * ts, ty * ts))

	return img


# Snap depth to 0.1 increments so the cache key is stable.
func _q(d: float) -> float:
	return float(clampi(int(d * 10.0 + 0.5), 0, 40)) / 10.0


# 24-bit key from four quantised depths (0-40 each, 6 bits each).
func _tile_key(d00: float, d10: float, d01: float, d11: float) -> int:
	var q0 := clampi(int(d00 * 10.0 + 0.5), 0, 40)
	var q1 := clampi(int(d10 * 10.0 + 0.5), 0, 40)
	var q2 := clampi(int(d01 * 10.0 + 0.5), 0, 40)
	var q3 := clampi(int(d11 * 10.0 + 0.5), 0, 40)
	return q0 | (q1 << 6) | (q2 << 12) | (q3 << 18)


# Generate one 32×32 tile image by bilinearly interpolating depth → colour.
# Called only on cache miss — amortised across thousands of blit_rect calls.
# Three texture layers applied in water zones:
#   1. Coarse grain noise   — breaks up solid zones
#   2. Fine shimmer noise   — adds sparkle in shallows
#   3. Horizontal flow band — subtle darker trough/lighter crest every ~8px
func _make_depth_tile(d00: float, d10: float, d01: float, d11: float) -> Image:
	var ts    := RiverConstants.TILE_SIZE
	var d_avg := (d00 + d10 + d01 + d11) * 0.25
	var img   := Image.create(ts, ts, false, Image.FORMAT_RGBA8)
	for j in ts:
		var fy := (float(j) + 0.5) / float(ts)
		# Primary flow band — wide, gently curved (period ~14px)
		var band1 := sin(float(j) * 0.46 + d_avg * 2.1) * 0.5 + 0.5
		# Secondary band — tighter, slightly diagonal (period ~9px, drifts with i)
		for i in ts:
			var fx    := (float(i) + 0.5) / float(ts)
			var depth := _bilerp(d00, d10, d01, d11, fx, fy)

			var band2 := sin(float(j) * 0.78 + float(i) * 0.10 + d_avg * 1.5) * 0.5 + 0.5

			# Coarse + fine grain noise
			var n_coarse := _hash(i, j) * 0.12 - 0.06
			var n_fine   := _hash(i * 5 + 3, j * 7 + 11) * 0.05 - 0.025

			var tex_depth := depth + n_coarse + n_fine

			# Flow ripple — stronger in shallow/mid water, fades in deep pool
			var water_t := clampf((depth - 1.4) / 1.8, 0.0, 1.0)
			var pool_t  := clampf((depth - 2.8) / 1.2, 0.0, 1.0)  # suppress in deep pool
			var ripple_str := water_t * (1.0 - pool_t * 0.7)
			var flow_offset := ((band1 - 0.5) * 0.11 + (band2 - 0.5) * 0.06) * ripple_str

			# Caustic sparkle — shallow zones only
			var caustic := 0.0
			if depth < 2.5 and _hash(i * 11 + 1, j * 13 + 7) > 0.94:
				caustic = 0.13 * (1.0 - clampf((depth - 1.5) / 1.0, 0.0, 1.0))

			tex_depth += flow_offset + caustic
			img.set_pixel(i, j, _depth_color(clampf(tex_depth, 0.0, 4.0)))
	return img


func _bilerp(v00: float, v10: float, v01: float, v11: float,
		fx: float, fy: float) -> float:
	return v00 + (v10 - v00) * fx + (v01 - v00) * fy \
		+ (v00 - v10 - v01 + v11) * fx * fy


func _hash(x: int, y: int) -> float:
	var h: int = (x * 1619 + y * 31337) & 0x7FFFFFFF
	h ^= h >> 16
	h  = (h * 0x45d9f3b) & 0x7FFFFFFF
	return float(h & 0xFF) / 255.0


func _depth_color(depth: float) -> Color:
	var stops: Array = _DEPTH_STOPS
	var last: int = stops.size() - 1
	if depth <= (stops[0][0] as float):
		return stops[0][1] as Color
	if depth >= (stops[last][0] as float):
		return stops[last][1] as Color
	for i in range(1, stops.size()):
		if depth <= (stops[i][0] as float):
			var d0: float = stops[i-1][0] as float
			var d1: float = stops[i  ][0] as float
			var c0: Color = stops[i-1][1] as Color
			var c1: Color = stops[i  ][1] as Color
			return c0.lerp(c1, (depth - d0) / (d1 - d0))
	return stops[last][1] as Color


# ---------------------------------------------------------------------------
# Rock cluster rendering — Polygon2D + Line2D child nodes
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
			const STEPS := 24
			var poly := PackedVector2Array()
			for i in STEPS:
				var angle := float(i) / float(STEPS) * TAU
				var da := cos(angle); var db := sin(angle)
				var best_r := ts * 0.44
				for c in cells:
					var cv: Vector2i = c
					var px := float(cv.x) * ts + ts * 0.5
					var py := float(cv.y) * ts + ts * 0.5
					var cdx := px - cx; var cdy := py - cy
					var dot  := cdx * da + cdy * db
					var perp := sqrt(maxf(0.0, cdx*cdx + cdy*cdy - dot*dot))
					if perp < ts * 0.72:
						var r := dot + ts * 0.54
						if r > best_r: best_r = r
				poly.append(Vector2(
					cx + da * best_r * (0.86 + rng.randf() * 0.22),
					cy + db * best_r * (0.86 + rng.randf() * 0.22)))

			if poly.size() < 3: continue

			var c_base: Color; var c_light: Color; var c_dark: Color
			var c_edge: Color; var c_spec:  Color
			if is_boulder:
				c_base  = Color(0.38, 0.34, 0.28, 0.78); c_light = Color(0.60, 0.56, 0.50)
				c_dark  = Color(0.18, 0.15, 0.11);        c_edge  = Color(0.12, 0.10, 0.07, 0.70)
				c_spec  = Color(0.78, 0.76, 0.70)
			else:
				c_base  = Color(0.54, 0.50, 0.44, 0.78); c_light = Color(0.76, 0.72, 0.66)
				c_dark  = Color(0.30, 0.26, 0.20);        c_edge  = Color(0.20, 0.17, 0.13, 0.70)
				c_spec  = Color(0.92, 0.90, 0.86)

			var min_x := poly[0].x; var max_x := poly[0].x
			var min_y := poly[0].y; var max_y := poly[0].y
			for p in poly:
				min_x = minf(min_x, p.x); max_x = maxf(max_x, p.x)
				min_y = minf(min_y, p.y); max_y = maxf(max_y, p.y)
			var rw := (max_x - min_x) * 0.5
			var rh := (max_y - min_y) * 0.5

			var shadow := PackedVector2Array()
			for p in poly: shadow.append(p + Vector2(2.0, 3.0))
			_add_poly(shadow, Color(0.0, 0.0, 0.0, 0.18))
			_add_poly(poly, c_base)
			_add_poly(_ellipse_poly(cx - rw*0.22, cy - rh*0.24, rw*0.52, rh*0.44, 14),
				Color(c_light.r, c_light.g, c_light.b, 0.60))
			_add_poly(_ellipse_poly(cx + rw*0.28, cy + rh*0.30, rw*0.50, rh*0.42, 14),
				Color(c_dark.r, c_dark.g, c_dark.b, 0.55))
			# Upstream water-pressure crescent — bright water piling on the upstream face
			_add_poly(_arc_crescent(cx - rw * 0.72, cy, rw * 0.30, rh * 0.68,
				deg_to_rad(110.0), deg_to_rad(250.0), 10),
				Color(0.55, 0.82, 0.96, 0.50))
			var spec_r := maxf(2.5, minf(rw, rh) * 0.14)
			_add_poly(_ellipse_poly(cx - rw*0.30, cy - rh*0.32, spec_r, spec_r, 8),
				Color(c_spec.r, c_spec.g, c_spec.b, 0.75))
			if is_boulder:
				var moss := Color(0.24, 0.36, 0.12, 0.55)
				_add_poly(_ellipse_poly(cx - rw*0.10, cy - rh*0.50,
					maxf(2.0, rw*0.18), maxf(2.0, rw*0.18), 8), moss)
				_add_poly(_ellipse_poly(cx + rw*0.30, cy - rh*0.40,
					maxf(1.5, rw*0.12), maxf(1.5, rw*0.12), 8), moss)

			var outline_pts := PackedVector2Array(poly)
			outline_pts.append(poly[0])
			var line := Line2D.new()
			line.points = outline_pts; line.default_color = c_edge
			line.width = 1.0; line.antialiased = true; line.z_index = 1
			add_child(line)
			_rock_nodes.append(line)

			_add_wake_seams(cx, cy, rw, ts, data, is_boulder)


func _add_poly(poly: PackedVector2Array, color: Color) -> void:
	var node := Polygon2D.new()
	node.polygon = poly; node.color = color; node.z_index = 1
	add_child(node); _rock_nodes.append(node)


func _ellipse_poly(ecx: float, ecy: float, rx: float, ry: float,
		steps: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in steps:
		var a := float(i) / float(steps) * TAU
		pts.append(Vector2(ecx + cos(a) * rx, ecy + sin(a) * ry))
	return pts


# Filled wedge arc — used for the upstream water-pressure crescent on rocks.
# start_a/end_a in radians; fan from centre outward.
func _arc_crescent(ecx: float, ecy: float, rx: float, ry: float,
		start_a: float, end_a: float, steps: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.append(Vector2(ecx, ecy))
	for i in range(steps + 1):
		var a := start_a + float(i) / float(steps) * (end_a - start_a)
		pts.append(Vector2(ecx + cos(a) * rx, ecy + sin(a) * ry))
	return pts


# ---------------------------------------------------------------------------
# Wake seam lines — teardrop shape, confined to river, rocks + boulders
# ---------------------------------------------------------------------------
# Two Line2Ds trace the edge of the dead-water bubble behind each obstruction.
# Shape: starts at rock half-width, converges to a point downstream (teardrop).
# Points clamped to water column so lines never bleed onto bank tiles.
# Boulders: longer, slightly more opaque.  Rocks: shorter, more transparent.

func _add_wake_seams(cx: float, cy: float, rw: float, ts: float,
		data: RiverData, is_boulder: bool) -> void:
	var wake_tiles := 9  if is_boulder else 5
	var max_half   := rw * 1.10 if is_boulder else rw * 0.90
	var alpha_tip  := 0.40 if is_boulder else 0.28

	var seam_upper := PackedVector2Array()
	var seam_lower := PackedVector2Array()

	for step in range(0, wake_tiles + 1):
		var t      := float(step) / float(wake_tiles)
		var wx_px  := cx + float(step + 1) * ts
		# Quadratic taper → teardrop: wide at rock, narrows to convergence point
		var half_w := max_half * (1.0 - t * t)

		# Clamp to water column at this x (keep seams in river)
		var tile_x := clampi(int(wx_px / ts), 0, data.width - 1)
		var top_px := float(data.top_bank_profile[tile_x]) * ts
		var bot_px := float(data.bottom_bank_profile[tile_x] - 1) * ts + ts

		var uy := clampf(cy - half_w, top_px, bot_px)
		var ly := clampf(cy + half_w, top_px, bot_px)
		seam_upper.append(Vector2(wx_px, uy))
		seam_lower.append(Vector2(wx_px, ly))

	var grad := Gradient.new()
	grad.remove_point(1)
	grad.set_color(0, Color(0.82, 0.94, 0.99, alpha_tip))
	grad.add_point(0.5, Color(0.82, 0.94, 0.99, alpha_tip * 0.55))
	grad.add_point(1.0, Color(0.82, 0.94, 0.99, 0.0))

	var w := 1.5 if is_boulder else 1.0
	for pts in [seam_upper, seam_lower]:
		var l := Line2D.new()
		l.points = pts; l.gradient = grad
		l.width = w; l.antialiased = true; l.z_index = 2
		add_child(l); _rock_nodes.append(l)


# ---------------------------------------------------------------------------
# Log rendering — elongated rounded brown polygons at bank-edge water tiles
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Driftwood — rotated, varied shapes (straight / tapered / forked)
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
		if _draw_log_sprite(cx, cy, length, angle, rng):
			continue

		# Shape variant: 40% straight, 35% tapered, 25% forked
		var sv := _hash(sx * 11 + 1, sy * 7 + 5)
		if sv < 0.40:
			_draw_driftwood_straight(cx, cy, length, angle, rng)
		elif sv < 0.75:
			_draw_driftwood_tapered(cx, cy, length, angle, rng)
		else:
			_draw_driftwood_forked(cx, cy, length, angle, rng)


# Rotate PackedVector2Array around (cx, cy) by angle_deg degrees.
func _rotate_pts(pts: PackedVector2Array, cx: float, cy: float,
		angle_deg: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var a   := deg_to_rad(angle_deg)
	var ca  := cos(a); var sa := sin(a)
	for p in pts:
		var dx := p.x - cx; var dy := p.y - cy
		out.append(Vector2(cx + dx * ca - dy * sa, cy + dx * sa + dy * ca))
	return out


# Weathered driftwood palette — bleached silver-grey after years in the river.
# Three tones: mid-grey base, lighter bleached highlight, darker waterlogged shadow.
func _bark_colors(rng: RandomNumberGenerator) -> Array:
	# Range: dark waterlogged (0.38) → bleached silver (0.72)
	var g := 0.38 + rng.randf() * 0.34
	# Slight warm or cool cast — driftwood ranges from cool grey to warm silver-tan
	var roff := rng.randf_range(-0.04, 0.06)
	var boff := rng.randf_range(-0.06, 0.02)
	var base := Color(g + roff, g, g + boff, 0.94)
	return [
		base,
		Color(minf(1.0, base.r + 0.18), minf(1.0, base.g + 0.16),
			  minf(1.0, base.b + 0.14), 0.65),  # bleached highlight
		Color(maxf(0.0, base.r - 0.12), maxf(0.0, base.g - 0.11),
			  maxf(0.0, base.b - 0.10), 0.84),  # waterlogged shadow
	]


# Dead branch stubs — thin Line2D spines radiating from points along the trunk axis.
# Angle is the trunk rotation in degrees; stubs spread mostly perpendicular to trunk.
func _add_branch_stubs(cx: float, cy: float, hlen: float, angle: float,
		rng: RandomNumberGenerator, cols: Array) -> void:
	var n := rng.randi_range(2, 5)
	var trunk_rad := deg_to_rad(angle)
	var base_col: Color = cols[2]
	var stub_col := Color(base_col.r * 0.82, base_col.g * 0.80, base_col.b * 0.78, 0.88)

	for _i in n:
		# Position along trunk (-hlen..hlen)
		var t_along := rng.randf_range(-hlen * 0.75, hlen * 0.75)
		var bx := cx + cos(trunk_rad) * t_along
		var by := cy + sin(trunk_rad) * t_along

		# Stub grows mostly perpendicular to trunk (±60° from normal)
		var normal_angle := angle + 90.0 + rng.randf_range(-60.0, 60.0)
		var stub_len     := hlen * (0.18 + rng.randf() * 0.32)
		var stub_rad     := deg_to_rad(normal_angle)
		var ex := bx + cos(stub_rad) * stub_len
		var ey := by + sin(stub_rad) * stub_len

		# Optional sub-branch (40% chance)
		var pts := PackedVector2Array([Vector2(bx, by), Vector2(ex, ey)])
		if rng.randf() < 0.40:
			var sub_angle := normal_angle + rng.randf_range(-50.0, 50.0)
			var sub_len   := stub_len * (0.35 + rng.randf() * 0.30)
			var sub_rad   := deg_to_rad(sub_angle)
			var split_t   := rng.randf_range(0.45, 0.75)
			var sx := bx + cos(stub_rad) * stub_len * split_t
			var sy := by + sin(stub_rad) * stub_len * split_t
			var sub_line := Line2D.new()
			sub_line.points = PackedVector2Array([
				Vector2(sx, sy),
				Vector2(sx + cos(sub_rad) * sub_len, sy + sin(sub_rad) * sub_len)
			])
			sub_line.default_color = stub_col
			sub_line.width = 1.0; sub_line.antialiased = true; sub_line.z_index = 2
			add_child(sub_line); _rock_nodes.append(sub_line)

		var line := Line2D.new()
		line.points = pts
		line.default_color = stub_col
		line.width = rng.randf_range(1.2, 2.2)
		line.antialiased = true; line.z_index = 2
		add_child(line); _rock_nodes.append(line)


func _draw_driftwood_straight(cx: float, cy: float, length: float,
		angle: float, rng: RandomNumberGenerator) -> void:
	var hr  := length * (0.055 + rng.randf() * 0.025)
	var cap := hr
	var hlen := length * 0.5
	const S := 6

	var body := PackedVector2Array()
	for i in range(S + 1):
		var a := PI * 0.5 + float(i) / float(S) * PI
		body.append(Vector2(cx - hlen + cap + cos(a) * cap, cy + sin(a) * hr))
	for i in range(S + 1):
		var a := -PI * 0.5 + float(i) / float(S) * PI
		body.append(Vector2(cx + hlen - cap + cos(a) * cap, cy + sin(a) * hr))
	body = _rotate_pts(body, cx, cy, angle)

	var cols := _bark_colors(rng)
	_add_poly(body, cols[0] as Color)
	# Highlight strip
	var hi := _rotate_pts(PackedVector2Array([
		Vector2(cx - hlen + cap, cy - hr * 0.50),
		Vector2(cx + hlen - cap, cy - hr * 0.50),
		Vector2(cx + hlen - cap, cy - hr * 0.12),
		Vector2(cx - hlen + cap, cy - hr * 0.12),
	]), cx, cy, angle)
	_add_poly(hi, cols[1] as Color)
	# Shadow strip
	var sh := _rotate_pts(PackedVector2Array([
		Vector2(cx - hlen + cap, cy + hr * 0.18),
		Vector2(cx + hlen - cap, cy + hr * 0.18),
		Vector2(cx + hlen - cap, cy + hr * 0.82),
		Vector2(cx - hlen + cap, cy + hr * 0.82),
	]), cx, cy, angle)
	_add_poly(sh, cols[2] as Color)
	# 65% chance: dead branch stubs still attached
	if rng.randf() < 0.65:
		_add_branch_stubs(cx, cy, hlen, angle, rng, cols)


func _draw_driftwood_tapered(cx: float, cy: float, length: float,
		angle: float, rng: RandomNumberGenerator) -> void:
	var hr_thick := length * (0.075 + rng.randf() * 0.030)
	var hr_thin  := length * (0.025 + rng.randf() * 0.015)
	var hlen     := length * 0.5

	var pts := PackedVector2Array([
		Vector2(cx - hlen, cy - hr_thick),
		Vector2(cx + hlen, cy - hr_thin),
		Vector2(cx + hlen, cy + hr_thin),
		Vector2(cx - hlen, cy + hr_thick),
	])
	pts = _rotate_pts(pts, cx, cy, angle)

	var cols := _bark_colors(rng)
	_add_poly(pts, cols[0] as Color)
	var hi := _rotate_pts(PackedVector2Array([
		Vector2(cx - hlen, cy - hr_thick * 0.85),
		Vector2(cx,        cy - (hr_thick + hr_thin) * 0.25),
		Vector2(cx,        cy - (hr_thick + hr_thin) * 0.05),
		Vector2(cx - hlen, cy - hr_thick * 0.10),
	]), cx, cy, angle)
	_add_poly(hi, cols[1] as Color)
	# 55% chance: stubs — tapered logs often retain some branches at the thick end
	if rng.randf() < 0.55:
		_add_branch_stubs(cx - hlen * 0.3, cy, hlen * 0.7, angle, rng, cols)


func _draw_driftwood_forked(cx: float, cy: float, length: float,
		angle: float, rng: RandomNumberGenerator) -> void:
	# Main trunk + large forked branch + optional dead stubs
	var cols := _bark_colors(rng)
	var hlen := length * 0.5

	# Draw trunk body directly so we share cols with stubs
	var hr  := length * (0.055 + rng.randf() * 0.025)
	var cap := hr
	const S := 6
	var body := PackedVector2Array()
	for i in range(S + 1):
		var a := PI * 0.5 + float(i) / float(S) * PI
		body.append(Vector2(cx - hlen + cap + cos(a) * cap, cy + sin(a) * hr))
	for i in range(S + 1):
		var a := -PI * 0.5 + float(i) / float(S) * PI
		body.append(Vector2(cx + hlen - cap + cos(a) * cap, cy + sin(a) * hr))
	_add_poly(_rotate_pts(body, cx, cy, angle), cols[0] as Color)

	# Major fork — a full-size branch breaking off near the upstream end
	var fork_angle  := angle + rng.randf_range(32.0, 60.0) * (1.0 if rng.randf() > 0.5 else -1.0)
	var fork_len    := length * (0.40 + rng.randf() * 0.30)
	var main_a      := deg_to_rad(angle)
	var offset_frac := rng.randf_range(-0.35, 0.05)
	var fork_cx := cx + cos(main_a) * length * offset_frac
	var fork_cy := cy + sin(main_a) * length * offset_frac
	_draw_driftwood_straight(fork_cx, fork_cy, fork_len, fork_angle, rng)

	# Stubs on main trunk
	if rng.randf() < 0.70:
		_add_branch_stubs(cx, cy, hlen, angle, rng, cols)


# ---------------------------------------------------------------------------
# Sprite props — selected atlas regions layered over procedural terrain
# ---------------------------------------------------------------------------

func _ensure_prop_textures() -> void:
	if _tree_texture == null:
		_tree_texture = load(_SpriteCatalog.TREES) as Texture2D
	if _boulder_texture == null:
		_boulder_texture = load(_SpriteCatalog.BOULDERS) as Texture2D
	if _feature_texture == null:
		_feature_texture = load(_SpriteCatalog.RIVER_ENVIRONMENT_FEATURES) as Texture2D


func _add_prop_sprite(texture: Texture2D, region: Rect2i, base_pos: Vector2,
		target_width: float, z: int = 2, centered: bool = false,
		rotation_deg: float = 0.0, modulate: Color = Color.WHITE) -> bool:
	if texture == null:
		return false
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.region_enabled = true
	sprite.region_rect = region
	sprite.centered = centered
	sprite.position = base_pos
	sprite.scale = Vector2.ONE * (target_width / float(region.size.x))
	sprite.rotation_degrees = rotation_deg
	sprite.modulate = modulate
	sprite.z_index = z
	add_child(sprite)
	_rock_nodes.append(sprite)
	return true


func _pick_region(regions: Array, rng: RandomNumberGenerator) -> Rect2i:
	return regions[rng.randi_range(0, regions.size() - 1)] as Rect2i


func _build_weed_feature_sprites(data: RiverData) -> void:
	if _feature_texture == null:
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
		var region := _pick_region(_WEED_REGIONS, rng)
		var cx := (float(sx) + float(sw) * 0.5) * ts
		var cy := (float(sy) + float(sh) * 0.5) * ts
		_add_prop_sprite(_feature_texture, region, Vector2(cx, cy),
				float(sw) * ts * rng.randf_range(0.75, 1.05), 1, true,
				rng.randf_range(-8.0, 8.0), Color(1.0, 1.0, 1.0, 0.78))


func _draw_log_sprite(cx: float, cy: float, length: float, angle: float,
		rng: RandomNumberGenerator) -> bool:
	if _feature_texture == null:
		return false
	var region := _pick_region(_LOG_REGIONS, rng)
	return _add_prop_sprite(_feature_texture, region, Vector2(cx, cy),
			length, 2, true, angle, Color(1.0, 1.0, 1.0, 0.92))


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
			var near_edge: int = data.top_bank_profile[tx]
			var far_start: int = data.bottom_bank_profile[tx]
			if ty < far_start:
				# Near bank — skip row immediately adjacent to water
				if ty >= near_edge - 1:
					continue
			else:
				# Far bank — skip first row (water-adjacent)
				if ty == far_start:
					continue

			var r   := rng.randf()
			var wx  := float(tx) * ts + rng.randf_range(ts * 0.1, ts * 0.9)
			var wy  := float(ty) * ts + rng.randf_range(ts * 0.1, ts * 0.9)

			# Trees: 6.25% — exclusive
			if r < 0.0625:
				_draw_bank_tree(wx, wy, ts, rng)
				continue
			# Bushes: ~70% of remaining tiles — near-continuous ground cover
			if r < 0.95:
				_draw_bank_bush(wx, wy, ts, rng)
			# Boulders: independent roll — scattered rocks throughout cover
			if _hash(tx * 17 + 11, ty * 31 + 7) < 0.30:
				_draw_bank_boulder(wx, wy, ts, rng)


func _draw_bank_tree(wx: float, wy: float, ts: float, rng: RandomNumberGenerator) -> void:
	if _tree_texture != null:
		var region := _pick_region(_TREE_REGIONS, rng)
		var width := ts * rng.randf_range(1.55, 2.35)
		var scale := width / float(region.size.x)
		var sprite_pos := Vector2(wx, wy - float(region.size.y) * scale * 0.5)
		_add_prop_sprite(_tree_texture, region, sprite_pos, width, 3, true)
		return

	var trunk_h := ts * (0.70 + rng.randf() * 0.50)
	var crown_r := ts * (0.75 + rng.randf() * 0.55)
	var lean    := rng.randf_range(-ts * 0.14, ts * 0.14)
	var tw      := ts * (0.06 + rng.randf() * 0.03)  # trunk half-width

	# Trunk — slightly tapered
	var trunk := PackedVector2Array([
		Vector2(wx - tw * 1.4, wy),
		Vector2(wx + tw * 1.4, wy),
		Vector2(wx + tw * 0.7 + lean, wy - trunk_h),
		Vector2(wx - tw * 0.7 + lean, wy - trunk_h),
	])
	_add_poly(trunk, Color(0.26 + rng.randf() * 0.06, 0.18 + rng.randf() * 0.05,
						   0.10 + rng.randf() * 0.03, 0.92))

	var crown_cx := wx + lean
	var crown_cy := wy - trunk_h - crown_r * 0.52

	# Optional second smaller crown lobe (30% chance) — multi-lobe canopy
	if rng.randf() < 0.30:
		var r2 := crown_r * (0.60 + rng.randf() * 0.25)
		var ox := rng.randf_range(-crown_r * 0.55, crown_r * 0.55)
		_add_poly(_ellipse_poly(crown_cx + ox, crown_cy + r2 * 0.10, r2, r2 * 0.82, 10),
			Color(0.14 + rng.randf() * 0.05, 0.32 + rng.randf() * 0.07,
				  0.10 + rng.randf() * 0.04, 0.82))

	# Branch spokes visible behind crown — dark thin lines radiating from trunk top
	var n_branches := rng.randi_range(3, 6)
	for i in n_branches:
		var ba  := rng.randf_range(-PI * 0.80, -PI * 0.20)  # upper hemisphere only
		var bl  := crown_r * rng.randf_range(0.55, 0.95)
		var bk  := Line2D.new()
		bk.points = PackedVector2Array([
			Vector2(crown_cx, crown_cy),
			Vector2(crown_cx + cos(ba) * bl, crown_cy + sin(ba) * bl)
		])
		bk.default_color = Color(0.18, 0.12, 0.07, 0.70)
		bk.width = rng.randf_range(1.0, 1.8); bk.antialiased = true; bk.z_index = 1
		add_child(bk); _rock_nodes.append(bk)

	# Main crown — jittered circle
	const CROWN_STEPS := 14
	var cr := Color(0.15 + rng.randf() * 0.06, 0.34 + rng.randf() * 0.09,
					0.11 + rng.randf() * 0.04, 0.90)
	var crown := PackedVector2Array()
	for i in CROWN_STEPS:
		var a   := float(i) / float(CROWN_STEPS) * TAU
		var jit := 1.0 + rng.randf_range(-0.22, 0.22)
		crown.append(Vector2(crown_cx + cos(a) * crown_r * jit,
							 crown_cy + sin(a) * crown_r * 0.82 * jit))
	_add_poly(crown, cr)

	# Inner shadow — darker mid-crown gives canopy depth
	_add_poly(_ellipse_poly(crown_cx + crown_r * 0.08, crown_cy + crown_r * 0.12,
		crown_r * 0.52, crown_r * 0.44, 10),
		Color(cr.r - 0.05, cr.g - 0.06, cr.b - 0.02, 0.48))

	# Crown highlight — bright top-left
	_add_poly(_ellipse_poly(crown_cx - crown_r * 0.22, crown_cy - crown_r * 0.26,
		crown_r * 0.46, crown_r * 0.38, 9),
		Color(0.24, 0.52, 0.16, 0.50))

	# Bark texture — 2 short vertical dark streaks on trunk
	for _i in 2:
		var bx  := wx + lean * 0.5 + rng.randf_range(-tw * 0.6, tw * 0.6)
		var by0 := wy - trunk_h * rng.randf_range(0.20, 0.50)
		var by1 := by0 - trunk_h * rng.randf_range(0.15, 0.30)
		var bkl := Line2D.new()
		bkl.points = PackedVector2Array([Vector2(bx, by0), Vector2(bx + rng.randf_range(-2.0, 2.0), by1)])
		bkl.default_color = Color(0.16, 0.10, 0.05, 0.50)
		bkl.width = 1.0; bkl.antialiased = true; bkl.z_index = 1
		add_child(bkl); _rock_nodes.append(bkl)


func _draw_bank_bush(wx: float, wy: float, ts: float, rng: RandomNumberGenerator) -> void:
	if _feature_texture != null and rng.randf() < 0.45:
		var region := _pick_region(_GRASS_REGIONS, rng)
		var width := ts * rng.randf_range(1.0, 1.65)
		_add_prop_sprite(_feature_texture, region, Vector2(wx, wy), width, 2, true,
				rng.randf_range(-4.0, 4.0), Color(1.0, 1.0, 1.0, 0.86))
		return

	# Texture-patch approach: 5-9 small overlapping blobs — no distinct object silhouette
	var n      := rng.randi_range(5, 9)
	var spread := ts * 0.57   # 1.5× (was 0.38)
	var base_g := 0.36 + rng.randf() * 0.10
	var base_r := 0.14 + rng.randf() * 0.07
	for _i in n:
		var ox  := rng.randf_range(-spread, spread)
		var oy  := rng.randf_range(-spread * 0.65, spread * 0.25)
		var pr  := ts * rng.randf_range(0.135, 0.30)  # 1.5× (was 0.09-0.20)
		var pg  := base_g + rng.randf_range(-0.06, 0.08)
		var pr2 := base_r + rng.randf_range(-0.04, 0.06)
		var pa  := rng.randf_range(0.55, 0.80)
		_add_poly(_ellipse_poly(wx + ox, wy + oy, pr, pr * rng.randf_range(0.65, 1.0), 7),
			Color(pr2, pg, 0.08 + rng.randf() * 0.06, pa))


func _draw_bank_boulder(wx: float, wy: float, ts: float, rng: RandomNumberGenerator) -> void:
	if _boulder_texture != null:
		var region := _pick_region(_BOULDER_REGIONS, rng)
		var width := ts * rng.randf_range(0.55, 1.35)
		_add_prop_sprite(_boulder_texture, region, Vector2(wx, wy), width, 2, true)
		return

	# Texture-patch approach: 3-5 small gray blobs — rocky scatter, no shading or cracks
	var n      := rng.randi_range(3, 5)
	var spread := ts * 0.42   # 1.5× (was 0.28)
	var base_g := 0.40 + rng.randf() * 0.18
	for _i in n:
		var ox  := rng.randf_range(-spread, spread)
		var oy  := rng.randf_range(-spread * 0.70, spread * 0.50)
		var pr  := ts * rng.randf_range(0.105, 0.24)  # 1.5× (was 0.07-0.16)
		var g   := base_g + rng.randf_range(-0.06, 0.08)
		var pa  := rng.randf_range(0.60, 0.82)
		_add_poly(_ellipse_poly(wx + ox, wy + oy, pr, pr * rng.randf_range(0.60, 1.0), 6),
			Color(g, g * 0.97, g * 0.92, pa))


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
