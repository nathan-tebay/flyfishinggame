class_name TileLegend
extends CanvasLayer

# Toggleable on-screen reference showing each tile type, its color, and
# what it means for movement, fish habitat, and current. Toggle with F1.

var visible_flag: bool = false

const _ENTRIES: Array = [
	# [ tile_id, label, description ]
	[ RiverConstants.TILE_BANK,          "Bank",          "Dry land — angler walks here, no current" ],
	[ RiverConstants.TILE_SURFACE,       "Shallow water", "Safe to wade; fast riffles in narrow sections" ],
	[ RiverConstants.TILE_MID_DEPTH,     "Mid depth",     "Wadable; some resistance from current" ],
	[ RiverConstants.TILE_DEEP,          "Deep channel",  "Impassable — too deep to wade (dark blue)" ],
	[ RiverConstants.TILE_WEED_BED,      "Weed bed",      "Insect habitat; shallow hold; wadable" ],
	[ RiverConstants.TILE_ROCK,          "Rock",          "Creates eddy & seam downstream; fish holding" ],
	[ RiverConstants.TILE_BOULDER,       "Boulder",       "Large rock; strong eddy; prime holding water" ],
	[ RiverConstants.TILE_GRAVEL_BAR,    "Gravel bar",    "Riffle habitat; nymph zone; low cover" ],
]

const _SWATCH   := 18     # colour square size px
const _PAD      := 10     # panel padding
const _ROW_H    := 22     # height per row
const _COL_GAP  := 8      # gap between swatch and label
const _DESC_X   := 170    # x offset for description column

var _node: Node2D = null


func _ready() -> void:
	layer = 20   # above all other HUD layers
	_node = Node2D.new()
	add_child(_node)
	_node.draw.connect(_on_draw)
	_node.visible = false


func toggle() -> void:
	visible_flag = not visible_flag
	_node.visible = visible_flag
	if visible_flag:
		_node.queue_redraw()


func _on_draw() -> void:
	var rows   := _ENTRIES.size()
	var w      := 480
	var h      := _PAD * 2 + rows * _ROW_H + 24   # 24 for title row
	var sx     := 20.0
	var sy     := 20.0

	# Panel background
	_node.draw_rect(Rect2(sx, sy, w, h), Color(0.0, 0.0, 0.0, 0.72))
	_node.draw_rect(Rect2(sx, sy, w, h), Color(1.0, 1.0, 1.0, 0.25), false, 1.2)

	# Title
	_node.draw_string(ThemeDB.fallback_font,
		Vector2(sx + _PAD, sy + _PAD + 14),
		"Tile Legend  (F1 to close)",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1, 13, Color(1, 1, 0.6, 1))

	# Rows
	for i in _ENTRIES.size():
		var entry: Array = _ENTRIES[i]
		var tile_id: int = entry[0]
		var label:   String = entry[1]
		var desc:    String = entry[2]

		var ry := sy + _PAD + 24 + i * _ROW_H
		var base_col: Color = RiverConstants.TILE_COLORS.get(tile_id, Color.MAGENTA)

		# Colour swatch
		_node.draw_rect(Rect2(sx + _PAD, ry, _SWATCH, _SWATCH), base_col)
		_node.draw_rect(Rect2(sx + _PAD, ry, _SWATCH, _SWATCH),
			Color(1, 1, 1, 0.30), false, 0.8)

		# Label
		_node.draw_string(ThemeDB.fallback_font,
			Vector2(sx + _PAD + _SWATCH + _COL_GAP, ry + 14),
			label,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1, 12, Color.WHITE)

		# Description (dimmed)
		_node.draw_string(ThemeDB.fallback_font,
			Vector2(sx + _PAD + _DESC_X, ry + 14),
			desc,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1, 11, Color(0.80, 0.80, 0.80, 0.90))
