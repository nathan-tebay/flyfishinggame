# Fly Fishing Sprite Pack — Godot Implementation Notes

This pack turns the supplied reference images into Godot-ready PNG sheets. The reference sheets were labeled, so I kept the complete art intact and made transparent-background versions rather than destroying any sprites during slicing. `angler moving.png` is included as both the original and a checkerboard-removed transparent copy.

## Contents

- `spritesheets/angler_cast_overhead_48x96_strip.png` — production uniform strip, 8 frames, 48x96 each.
- `spritesheets/angler_moving_transparent.png` — checked-in moving/wading sheet with the checkerboard removed.
- `spritesheets/*_transparent_sheet.png` — transparent versions of the supplied reference sheets for trees, boulders, fish, insects, water, terrain, and river features.
- `metadata/manifest.json` — list of every generated sheet.
- `metadata/angler_cast_overhead_48x96.json` — frame metadata for the casting strip.

## Godot import settings

For every PNG, select the file in Godot and set:

- **Filter:** Off / Nearest
- **Mipmaps:** Off
- **Repeat:** Disabled for sprites; Enabled only for repeating terrain or water textures
- **Compression Mode:** Lossless

Then click **Reimport**.

## Angler casting setup

Use `spritesheets/angler_cast_overhead_48x96_strip.png`.

Frame size: **48x96**  
Columns: **8**  
Rows: **1**

Animation order:

1. Ready
2. Lift
3. Back accel
4. Back stop
5. Unload / near vertical
6. Forward accel
7. Forward stop
8. Presentation

Create an `AnimatedSprite2D`, add a `SpriteFrames` resource, create the animation `cast_overhead`, and choose **Add frames from a sprite sheet**. Set the grid to **8 horizontal x 1 vertical**.

Example:

```gdscript
@onready var angler_sprite: AnimatedSprite2D = $AnimatedSprite2D

func play_cast() -> void:
    angler_sprite.play("cast_overhead")
```

Suggested FPS: **10–14 FPS**, one-shot or brief non-looping animation.

## Angler moving setup

Use `spritesheets/angler_moving_transparent.png` for movement/wading animation setup.

Suggested animation groups:

- `walk_land_north/south/east/west`
- `wade_shallow_north/south/east/west`
- `wade_mid_north/south/east/west`

The moving sheet is visually arranged rather than exported as one strict 48x96 strip, so select the frame regions in Godot’s sprite sheet picker and verify each row.

## Fish and rise sprites

Use these sheets:

- `rainbow_trout_transparent_sheet.png`
- `brown_trout_transparent_sheet.png`
- `mountain_whitefish_transparent_sheet.png`
- `monster_trout_transparent_sheet.png`

Suggested animations:

- `idle_swim`: 6–8 FPS, loop
- `slow_glide`: 4–6 FPS, loop
- `subtle_rise`: 8–12 FPS, one-shot or short loop
- `splashy_rise`: 10–14 FPS, one-shot

Place rise animations above water as separate `AnimatedSprite2D` nodes so the fish can remain hidden or partially visible underneath.

## Water, terrain, and river props

Use these as TileSet/Atlas sources:

- `water_depths_transitions_transparent_sheet.png`
- `river_environment_features_transparent_sheet.png`
- `boulders_transparent_sheet.png`
- `trees_transparent_sheet.png`

Recommended TileMap layers:

1. Base ground: sand, fine gravel, gravel, grass, bank soil
2. Water base: shallow / mid / deep
3. Water transition overlays
4. In-water features: submerged rocks, logs, weed beds
5. Above-water props: boulders, bushes, trees
6. Fish/rise effects
7. Player/angler

Enable Y-sort for the world parent when using top-down props:

```gdscript
func _ready() -> void:
    $World.y_sort_enabled = true
```

For trees, put collision only on the trunk/base, not the canopy.

## Insects and flies

Use:

- `aquatic_insects_lifecycle_transparent_sheet.png`
- `aquatic_insects_flies_topdown_transparent_sheet.png`

Implementation ideas:

- Drift nymphs and larvae just under the water surface.
- Float duns/spinners/adults on the surface with subtle bobbing.
- Use fishing fly sprites as lure icons, hatch-matching UI, or actual drift objects.

## Notes

The large category sheets are cleaned full-reference atlases. They remain useful in Godot by choosing atlas regions manually. This avoids accidental loss of small sprites, legs, antennae, white splash pixels, and tiny rise rings that automated slicing often removes.
