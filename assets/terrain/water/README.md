# Water Tiles

These 32x32 river water tiles are extracted from:

- `assets/sprites/spritesheets/water_depths_transitions_transparent_sheet.png`

Generated folders:

- `shallow/`
- `mid/`
- `deep/`
- `transitions/shallow_to_mid/`
- `transitions/mid_to_deep/`
- `transitions/shallow_to_deep/`

Regenerate with:

```bash
godot4 --headless --path /mnt/LargeNVMe/Projects/GitHub/personal/flyfishinggame --script res://scripts/tools/extract_water_tiles.gd
```

The extractor uses centered crops from the labeled reference panels and writes a
`manifest.json` alongside the exported PNGs.

## Status

This folder is currently a temporary extraction source, not the intended final
runtime set.

The extracted pools are useful for renderer wiring and iteration, but they are
too large and too showcase-oriented for a cohesive SNES-style game scene.

See:

- `assets/terrain/SNES_TILESET_PLAN.md`
- `assets/terrain/curated_runtime_manifest_v1.json`
