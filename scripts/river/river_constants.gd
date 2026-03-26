class_name RiverConstants

const TILE_SIZE        := 32
const SECTION_SCREENS  := 24
const SCREEN_W_TILES   := 60    # 1920 / TILE_SIZE
const SECTION_W_TILES  := 1440  # SECTION_SCREENS * SCREEN_W_TILES

# River cross-section height in tiles (below sky strip)
const RIVER_H_TILES    := 24
const BANK_H_TILES     := 3     # tiles above waterline
const MIN_DEPTH_TILES  := 4     # shallowest possible water column
const MAX_DEPTH_TILES  := 21    # deepest possible (RIVER_H_TILES - BANK_H_TILES)

# Sky strip sits above the TileMap in screen space (via CanvasLayer)
const SKY_HEIGHT_PX    := 96    # BANK_H_TILES * TILE_SIZE — kept as px for CanvasLayer sizing

# --- Tile type IDs (also used as TileSet source IDs) ---
const TILE_AIR             := -1
const TILE_BANK            := 0
const TILE_SURFACE         := 1
const TILE_MID_DEPTH       := 2
const TILE_DEEP            := 3
const TILE_RIVERBED        := 4
const TILE_WEED_BED        := 5
const TILE_ROCK            := 6
const TILE_BOULDER         := 7
const TILE_UNDERCUT_BANK   := 8
const TILE_GRAVEL_BAR      := 9

# --- TileMap layer indices ---
const LAYER_BASE       := 0
const LAYER_STRUCTURES := 1
const LAYER_DEBUG      := 2

# --- Placeholder colors per tile type ---
const TILE_COLORS: Dictionary = {
	0: Color(0.22, 0.55, 0.15),   # BANK            — green
	1: Color(0.55, 0.85, 0.98),   # SURFACE          — light blue
	2: Color(0.22, 0.55, 0.88),   # MID_DEPTH        — medium blue
	3: Color(0.10, 0.25, 0.65),   # DEEP             — dark blue
	4: Color(0.45, 0.38, 0.28),   # RIVERBED         — brown
	5: Color(0.12, 0.50, 0.20),   # WEED_BED         — dark green
	6: Color(0.52, 0.48, 0.43),   # ROCK             — gray
	7: Color(0.35, 0.30, 0.25),   # BOULDER          — dark gray
	8: Color(0.42, 0.32, 0.22),   # UNDERCUT_BANK    — dark brown
	9: Color(0.72, 0.67, 0.52),   # GRAVEL_BAR       — tan
}

# --- Structure properties: cover value and hatch indicator weight ---
const STRUCTURE_COVER: Dictionary = {
	5: 0.7,   # WEED_BED
	6: 0.5,   # ROCK
	7: 0.9,   # BOULDER
	8: 0.8,   # UNDERCUT_BANK
	9: 0.1,   # GRAVEL_BAR
}

const STRUCTURE_HATCH: Dictionary = {
	5: 1.0,   # WEED_BED — primary insect habitat
	6: 0.6,   # ROCK
	7: 0.8,   # BOULDER
	8: 0.5,   # UNDERCUT_BANK
	9: 0.2,   # GRAVEL_BAR
}

# --- Sky colors per TimeOfDay.Period index (Dawn..Night) ---
const SKY_COLORS: Array = [
	Color(0.95, 0.60, 0.35),  # DAWN      — orange
	Color(0.55, 0.75, 0.95),  # MORNING   — light blue
	Color(0.35, 0.60, 0.90),  # MIDDAY    — bright blue
	Color(0.45, 0.65, 0.85),  # AFTERNOON — medium blue
	Color(0.85, 0.40, 0.20),  # DUSK      — deep orange/red
	Color(0.05, 0.05, 0.15),  # NIGHT     — near black
]
