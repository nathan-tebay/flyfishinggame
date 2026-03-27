class_name RiverData
extends RefCounted

var seed: int = 0
var width: int = RiverConstants.SECTION_W_TILES
var height: int = RiverConstants.RIVER_H_TILES

# depth_profile[x] = 0.0 (shallow/riffle) .. 1.0 (deep/pool)
var depth_profile: Array = []

# top_bank_profile[x] = row index where water begins (>= BANK_H_TILES).
# Varies per column via low-freq noise to produce curved/undulating near bank.
var top_bank_profile: Array = []

# bottom_bank_profile[x] = row index where the far bank begins (riverbed_row + 1).
# Varies per column via independent noise to produce a curved far bank.
var bottom_bank_profile: Array = []

# current_map[x][y] = 0.0 (still/eddy) .. 1.0 (fast)
var current_map: Array = []

# tile_map[x][y] = RiverConstants.TILE_* int  (-1 = air/empty)
var tile_map: Array = []

# hold_scores[x][y] = float  (higher = better fish holding spot)
var hold_scores: Array = []

# structures: Array of Dictionaries
#   { type:int, x:int, y:int, w:int, h:int, cover:float, hatch:float }
var structures: Array = []

# top_holds: Array of Dictionaries  { x:int, y:int, score:float }
# Sorted descending by score; length = fish_per_section * 3 (candidates for Phase 5)
var top_holds: Array = []
