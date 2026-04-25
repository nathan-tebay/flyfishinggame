@tool
extends EditorScript

## Run from the Godot editor: open the script, then File → Run (Ctrl+Shift+X).
## Legacy comparison tool: saves 32×32 pixel-art sprites under res://assets/terrain/legacy_tiles/.
## Rock and boulder tiles are NOT generated here — the renderer draws those as
## organic cluster shapes at runtime so adjacent rocks merge into one formation.

const SZ  := 32
const OUT := "res://assets/terrain/legacy_tiles/"


func _run() -> void:
	var abs_out := ProjectSettings.globalize_path(OUT)
	DirAccess.make_dir_recursive_absolute(abs_out)

	_save(abs_out, 0, "bank",     _make_bank())
	_save(abs_out, 1, "surface",  _make_surface())
	_save(abs_out, 2, "mid",      _make_mid_depth())
	_save(abs_out, 3, "deep",     _make_deep())
	_save(abs_out, 5, "weed",     _make_weed_bed())
	_save(abs_out, 8, "undercut", _make_undercut())
	_save(abs_out, 9, "gravel",   _make_gravel())

	print("Tile sprites written to: %s" % abs_out)
	print("Rescan the FileSystem panel to import them.")


func _save(dir: String, tile_id: int, name: String, img: Image) -> void:
	var path := dir + "tile_%d_%s.png" % [tile_id, name]
	var err  := img.save_png(path)
	if err == OK:
		print("  OK  %s" % path.get_file())
	else:
		push_error("Failed to save %s (err %d)" % [path, err])


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _img() -> Image:
	return Image.create(SZ, SZ, false, Image.FORMAT_RGBA8)


func _px(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and x < SZ and y >= 0 and y < SZ:
		img.set_pixel(x, y, c)


# Deterministic per-pixel noise in [0, 1].
func _n(x: int, y: int, s: int = 0) -> float:
	var h: int = x * 1619 + y * 31337 + s * 6791
	h ^= h >> 16
	h = (h * 0x45d9f3b) & 0x7FFFFFFF
	return float(h & 0xFF) / 255.0


# ---------------------------------------------------------------------------
# Tile 0 — Bank (pure grass, no soil)
# ---------------------------------------------------------------------------

func _make_bank() -> Image:
	var img := _img()

	# Five-value grass palette — no brown at all
	var G_TIP := Color(0.52, 0.84, 0.26)   # bright blade tip
	var G_LT  := Color(0.42, 0.72, 0.18)   # sunlit grass
	var G_MD  := Color(0.30, 0.58, 0.12)   # mid grass
	var G_DK  := Color(0.20, 0.42, 0.08)   # shadow / dense cover
	var G_SHD := Color(0.14, 0.30, 0.05)   # deep shadow at base

	# Rows 0–2: blade tips — alternating bright and dark pixels for serrated look
	for x in range(0, SZ):
		var n0 := _n(x, 0, 1)
		var n1 := _n(x, 1, 2)
		_px(img, x, 0, G_TIP if n0 > 0.48 else G_DK)
		_px(img, x, 1, G_LT  if n1 > 0.55 else G_MD)

	# Rows 3–20: main grass body with noisy light/shadow variation
	for y in range(2, 21):
		for x in range(0, SZ):
			var n := _n(x, y, 3)
			var c := G_MD
			if n > 0.72:
				c = G_LT
			elif n < 0.22:
				c = G_DK
			_px(img, x, y, c)

	# Horizontal shadow bands every ~5 rows — subtle layered texture
	for sy in ([6, 11, 16] as Array[int]):
		for x in range(0, SZ):
			if _n(x, sy, 4) > 0.52:
				_px(img, x, sy, G_DK)

	# Rows 21–31: ground-level grass — progressively darker toward tile bottom
	for y in range(21, SZ):
		var t := float(y - 21) / float(SZ - 21)   # 0 at row 21, 1 at row 31
		for x in range(0, SZ):
			var n := _n(x, y, 5)
			var base := G_MD.lerp(G_SHD, t * 0.80)
			var c := base
			if n > 0.70:
				c = G_DK.lerp(G_MD, 1.0 - t * 0.6)
			elif n < 0.18:
				c = G_SHD
			_px(img, x, y, c)

	return img


# ---------------------------------------------------------------------------
# Tile 1 — Surface / shallow water
# ---------------------------------------------------------------------------

func _make_surface() -> Image:
	var img := _img()

	var W_BRT := Color(0.55, 0.86, 0.97)   # brightest surface
	var W_MD  := Color(0.38, 0.70, 0.90)   # normal surface
	var W_DK  := Color(0.26, 0.56, 0.82)   # trough / shadow
	var W_SH  := Color(0.78, 0.93, 1.00)   # shimmer crest
	var W_SP  := Color(0.96, 0.98, 1.00)   # specular sparkle

	img.fill(W_MD)

	# Undulating horizontal bands — each band has a random y offset per column
	# giving a flowing, natural water surface look
	for x in range(0, SZ):
		var band_offset := int(_n(x, 0, 10) * 3.0)
		for y in range(0, SZ):
			var band := (y + band_offset) % 7
			var n    := _n(x, y, 11)
			if band == 0 or band == 1:
				_px(img, x, y, W_SH if n > 0.40 else W_BRT)
			elif band == 5 or band == 6:
				_px(img, x, y, W_DK if n > 0.50 else W_MD)

	# Caustic patches — small clusters of bright pixels suggesting light refraction
	for y in range(0, SZ):
		for x in range(0, SZ):
			if _n(x, y, 12) > 0.91:
				_px(img, x, y, W_SP)
			# Small dark troughs between caustics
			elif _n(x, y, 13) < 0.06:
				_px(img, x, y, W_DK)

	# Foam flecks at top edge
	for x in range(0, SZ):
		if _n(x, 0, 14) > 0.65:
			_px(img, x, 0, W_SP)

	return img


# ---------------------------------------------------------------------------
# Tile 2 — Mid-depth water
# ---------------------------------------------------------------------------

func _make_mid_depth() -> Image:
	var img := _img()

	var W_BRT := Color(0.36, 0.66, 0.92)
	var W_MD  := Color(0.24, 0.52, 0.84)
	var W_DK  := Color(0.14, 0.38, 0.72)
	var W_SH  := Color(0.48, 0.74, 0.96)

	img.fill(W_MD)

	for x in range(0, SZ):
		var band_offset := int(_n(x, 0, 20) * 4.0)
		for y in range(0, SZ):
			var band := (y + band_offset) % 9
			var n    := _n(x, y, 21)
			if band == 0:
				_px(img, x, y, W_SH if n > 0.55 else W_BRT)
			elif band >= 7:
				_px(img, x, y, W_DK if n > 0.45 else W_MD)

	# Sparse sparkle — less than surface
	for y in range(0, SZ):
		for x in range(0, SZ):
			if _n(x, y, 22) > 0.93:
				_px(img, x, y, W_SH)

	return img


# ---------------------------------------------------------------------------
# Tile 3 — Deep water / channel
# ---------------------------------------------------------------------------

func _make_deep() -> Image:
	var img := _img()

	var W_BRT := Color(0.18, 0.34, 0.76)
	var W_MD  := Color(0.10, 0.22, 0.62)
	var W_DK  := Color(0.06, 0.13, 0.48)

	img.fill(W_MD)

	for x in range(0, SZ):
		var band_offset := int(_n(x, 0, 30) * 5.0)
		for y in range(0, SZ):
			var band := (y + band_offset) % 12
			var n    := _n(x, y, 31)
			if band == 0:
				_px(img, x, y, W_BRT if n > 0.60 else W_MD)
			elif band >= 10:
				_px(img, x, y, W_DK if n > 0.50 else W_MD)

	return img


# ---------------------------------------------------------------------------
# Tile 5 — Weed bed
# ---------------------------------------------------------------------------

func _make_weed_bed() -> Image:
	var img := _img()

	var MUD  := Color(0.08, 0.14, 0.08)
	var WAT  := Color(0.10, 0.24, 0.50)
	var W1   := Color(0.22, 0.48, 0.16)
	var W2   := Color(0.15, 0.36, 0.11)
	var W3   := Color(0.09, 0.22, 0.06)
	var STEM := Color(0.32, 0.22, 0.08)

	for y in range(0, SZ):
		for x in range(0, SZ):
			_px(img, x, y, WAT if _n(x, y, 40) > 0.54 else MUD)

	var frond_cols: Array[int] = [2, 6, 10, 14, 19, 23, 27, 31]
	for fc in frond_cols:
		var h:   int = 10 + int(_n(fc, 0, 41) * 16)
		var top: int = SZ - h
		for y in range(top, SZ):
			var t:    float = float(y - top) / float(h)
			var wave: int   = int(sin(t * PI * 2.8 + fc * 1.3) * 1.6)
			var x:    int   = fc + wave
			var c: Color
			if t < 0.18:
				c = STEM
			elif t < 0.55:
				c = W2
			elif _n(x, y, 42) > 0.48:
				c = W1
			else:
				c = W3
			_px(img, x, y, c)
			if t > 0.35 and t < 0.65 and _n(x, y, 43) > 0.72:
				_px(img, x + (1 if wave >= 0 else -1), y, W2)

	return img


# ---------------------------------------------------------------------------
# Tile 8 — Undercut bank
# ---------------------------------------------------------------------------

func _make_undercut() -> Image:
	var img := _img()

	var C_MA  := Color(0.34, 0.22, 0.12)
	var C_LT  := Color(0.50, 0.35, 0.20)
	var C_MD  := Color(0.42, 0.28, 0.16)
	var C_DK  := Color(0.20, 0.12, 0.06)
	var C_RT  := Color(0.64, 0.50, 0.26)
	var C_WAT := Color(0.14, 0.30, 0.58)

	img.fill(C_MA)

	var strata: Array[int] = [3, 7, 12, 17, 22, 27]
	for sy in strata:
		for x in range(0, SZ):
			var wave := int(_n(x, sy, 70) * 1.6)
			var yw   := clampi(sy + wave, 0, SZ - 1)
			if _n(x, sy, 71) > 0.38:
				_px(img, x, yw,     C_LT)
				_px(img, x, yw + 1, C_MD)

	var root_rows: Array[int] = [5, 11, 18, 25]
	for rr in root_rows:
		var x := int(_n(rr, 0, 72) * 6)
		while x < SZ:
			var step := 2 + int(_n(x, rr, 73) * 3)
			if _n(x, rr, 74) > 0.42:
				_px(img, x, rr, C_RT)
				if _n(x, rr, 75) > 0.58:
					_px(img, x, rr + (1 if x % 4 < 2 else -1), C_RT)
			x += step

	for gap_x in ([5, 14, 23] as Array[int]):
		var gah := 5 + int(_n(gap_x, 0, 76) * 10)
		for gy in range(SZ - gah, SZ):
			_px(img, gap_x, gy, C_DK)

	for x in range(0, SZ):
		if _n(x, SZ - 1, 77) > 0.48:
			_px(img, x, SZ - 1, C_WAT)
		if _n(x, SZ - 2, 78) > 0.65:
			_px(img, x, SZ - 2, C_WAT)

	return img


# ---------------------------------------------------------------------------
# Tile 9 — Gravel bar
# ---------------------------------------------------------------------------

func _make_gravel() -> Image:
	var img := _img()

	var S_LT := Color(0.88, 0.82, 0.62)
	var S_MD := Color(0.73, 0.66, 0.48)
	var S_DK := Color(0.56, 0.50, 0.34)
	var P_LT := Color(0.82, 0.78, 0.70)
	var P_MD := Color(0.60, 0.56, 0.48)
	var P_DK := Color(0.42, 0.38, 0.30)
	var P_SH := Color(0.26, 0.23, 0.18)

	for y in range(0, SZ):
		for x in range(0, SZ):
			var n := _n(x, y, 80)
			_px(img, x, y, S_LT if n > 0.72 else (S_DK if n < 0.22 else S_MD))

	var rng := RandomNumberGenerator.new()
	rng.seed = 9876
	for _i in range(48):
		var px2 := rng.randi_range(1, SZ - 4)
		var py2 := rng.randi_range(1, SZ - 4)
		var nv  := _n(px2, py2, 81)
		var sz2 := 1 + int(nv * 2.6)
		var col := P_LT if nv > 0.65 else (P_MD if nv > 0.33 else P_DK)
		_px(img, px2, py2, col)
		if sz2 >= 2:
			_px(img, px2 + 1, py2,     col.darkened(0.18))
			_px(img, px2,     py2 + 1, col.darkened(0.22))
			_px(img, px2 + 1, py2 + 1, P_SH)
		if sz2 >= 3:
			_px(img, px2 + 2, py2,     col.darkened(0.28))
			_px(img, px2,     py2 + 2, col.darkened(0.30))
			_px(img, px2 + 2, py2 + 2, P_SH)

	for y in range(24, SZ):
		var t := float(y - 24) / float(SZ - 24)
		for x in range(0, SZ):
			_px(img, x, y, img.get_pixel(x, y).lerp(S_DK, t * 0.60))

	return img
