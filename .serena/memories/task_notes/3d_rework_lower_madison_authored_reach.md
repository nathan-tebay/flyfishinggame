# Authored Lower Madison Black's Ford Bend Pass — Historical

Implemented on branch `3d-rework` on 2026-05-26. This note records the authored-reach pass but is superseded by later 3D-only removal/current-state memories where they conflict.

## What this pass added
- Added `scripts/river/lower_madison_reach.gd`: fixed reach interface based on public USGS source files. Loads NHD high-resolution Madison River artificial-path centerline feature `52394513` / reachcode `10020007003886`, converts to local downstream coordinates, and exposes water/land classification, water surface/bed depth, current vector/strength, named habitats, fixed props, gravel bars, vegetation anchors, fish holds and dry start position.
- Archived geodata in `assets/3d/geodata/`: NHD flowline GeoJSON, NHD perennial area reference GeoJSON, USGS 3DEP TIFF clip, and terrain sample JSON used at runtime.
- Replaced visible 3D from seeded `RiverData`/tile maps with continuous carved bed/water, gravel shelves and dry bars, 3DEP valley relief, fixed boulders/log/weed edges/riparian clusters and seed-selected fish silhouettes. Exposed bars are classified dry land.
- Downloaded/imported CC0 ambientCG 1K PBR maps under `assets/3d/pbr/ambientcg/` and added source/license records plus `docs/LOWER_MADISON_REACH.md`.

## Superseded detail
- This pass temporarily kept classic `RiverWorld.tscn` selectable. That was superseded on 2026-05-27 when user explicitly requested removing 2D support.
- Current runtime is 3D-only; do not restore selectable classic mode unless user explicitly asks.

## Historical validation
Initial validation checked reach queries, 3D scene, then-still-existing classic 2D scene, startup, diff whitespace, and forced visual mesh smoke. Later current-state validation should be preferred.