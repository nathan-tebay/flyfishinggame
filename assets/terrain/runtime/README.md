# SNES Runtime Tiles

These are the curated runtime tiles cropped from:

- `assets/terrain/reference/snes_river_tiles_target_v2.png`

They replace the larger temporary extraction pools for the active tile-based
river renderer.

Regenerate with:

```bash
godot4 --headless --path /mnt/LargeNVMe/Projects/GitHub/personal/flyfishinggame --script res://scripts/tools/extract_snes_runtime_tiles.gd
```

Folders:

- `water/shallow`
- `water/mid`
- `water/deep`
- `water/transitions/shallow_to_mid`
- `water/transitions/mid_to_deep`
- `shoreline/edge`
- `shoreline/outer_corner`
- `shoreline/inner_corner`
- `gravel_bar`
