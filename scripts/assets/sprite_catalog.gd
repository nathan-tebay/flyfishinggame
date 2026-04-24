class_name SpriteCatalog
extends RefCounted

const ROOT := "res://assets/sprites"
const SPRITESHEETS := ROOT + "/spritesheets"
const METADATA := ROOT + "/metadata"

const ANGLER_CAST_OVERHEAD := SPRITESHEETS + "/angler_cast_overhead_48x96_strip.png"
const ANGLER_CASTING_REFERENCE := SPRITESHEETS + "/angler_casting_reference_transparent_sheet.png"
const ANGLER_MOVING_ORIGINAL := SPRITESHEETS + "/angler_moving_original.png"
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

const ANGLER_CAST_METADATA := METADATA + "/angler_cast_overhead_48x96.json"
const ANGLER_MOVING_METADATA := METADATA + "/angler_moving.json"
const MANIFEST := METADATA + "/manifest.json"

const ANGLER_CAST_FRAME_SIZE := Vector2i(48, 96)
const ANGLER_CAST_COLUMNS := 8
const ANGLER_CAST_FRAMES := 8

const FISH_BY_SPECIES := {
	0: BROWN_TROUT,
	1: RAINBOW_TROUT,
	2: MOUNTAIN_WHITEFISH,
}
