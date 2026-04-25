class_name SpriteCatalog
extends RefCounted

const ASSET_ROOT := "res://assets"
const SPRITE_ROOT := ASSET_ROOT + "/sprites"
const SPRITESHEETS := SPRITE_ROOT + "/spritesheets"
const SPRITE_METADATA := SPRITE_ROOT + "/metadata"
const TERRAIN_ROOT := ASSET_ROOT + "/terrain"
const TERRAIN_TILE_ROOT := TERRAIN_ROOT + "/terrain"
const TERRAIN_BANK_ROOT := TERRAIN_ROOT + "/banks"
const TERRAIN_TRANSITION_ROOT := TERRAIN_ROOT + "/transitions"
const WATER_TILE_ROOT := TERRAIN_ROOT + "/water"
const RUNTIME_TILE_ROOT := TERRAIN_ROOT + "/runtime"
const MODULE_TILE_ROOT := TERRAIN_ROOT + "/modules"
const CURATED_RUNTIME_MANIFEST := TERRAIN_ROOT + "/curated_runtime_manifest_v1.json"
const RIVER_TERRAIN_ROOT := TERRAIN_ROOT + "/river_atlas"

const ANGLER_CAST_OVERHEAD := SPRITESHEETS + "/angler_cast_overhead_48x96_strip.png"
const ANGLER_CASTING_REFERENCE := SPRITESHEETS + "/angler_casting_reference_transparent_sheet.png"
const ANGLER_MOVING_TRANSPARENT := SPRITESHEETS + "/angler_moving_transparent.png"

const AQUATIC_INSECTS_FLIES_TOPDOWN := SPRITESHEETS + "/aquatic_insects_flies_topdown_transparent_sheet.png"
const AQUATIC_INSECTS_LIFECYCLE := SPRITESHEETS + "/aquatic_insects_lifecycle_transparent_sheet.png"

const BOULDERS := SPRITESHEETS + "/boulders_transparent_sheet.png"
const TREES := SPRITESHEETS + "/trees_transparent_sheet.png"
const RIVER_ENVIRONMENT_FEATURES := SPRITESHEETS + "/river_environment_features_transparent_sheet.png"
const WATER_DEPTHS_TRANSITIONS := SPRITESHEETS + "/water_depths_transitions_transparent_sheet.png"

const BROWN_TROUT := SPRITESHEETS + "/brown_trout_transparent_sheet.png"
const RAINBOW_TROUT := SPRITESHEETS + "/rainbow_trout_transparent_sheet.png"
const MOUNTAIN_WHITEFISH := SPRITESHEETS + "/mountain_whitefish_transparent_sheet.png"
const MONSTER_TROUT := SPRITESHEETS + "/monster_trout_transparent_sheet.png"

const ANGLER_CAST_METADATA := SPRITE_METADATA + "/angler_cast_overhead_48x96.json"
const ANGLER_MOVING_METADATA := SPRITE_METADATA + "/angler_moving.json"
const MANIFEST := SPRITE_METADATA + "/manifest.json"

const RIVER_TERRAIN_ATLAS_TEXTURE := RIVER_TERRAIN_ROOT + "/river_terrain_atlas_32.png"
const RIVER_TERRAIN_TILESET := RIVER_TERRAIN_ROOT + "/river_terrain_tileset.tres"
const RIVER_TERRAIN_MANIFEST := RIVER_TERRAIN_ROOT + "/atlas_manifest.json"
const RIVER_TERRAIN_AUTOTILE_TEMPLATES := RIVER_TERRAIN_ROOT + "/autotile_templates.json"

const ANGLER_CAST_FRAME_SIZE := Vector2i(48, 96)
const ANGLER_CAST_COLUMNS := 8
const ANGLER_CAST_FRAMES := 8

const FISH_BY_SPECIES := {
	0: BROWN_TROUT,
	1: RAINBOW_TROUT,
	2: MOUNTAIN_WHITEFISH,
}
