# 3D Rework Shoreline/Bar Grounding Correction

On 2026-05-27, a screenshot showed a hard bright near-bank shoreline transition and exposed point-bar/gravel island shapes reading like flat floating caps over moving water.

## Fix
- Updated `scripts/river/river_3d_builder.gd`:
  - Added a low `WetShorelineBlend` strip between water and dry gravel, before `GravelWaterlineShelves` and `VegetatedBankBenches`.
  - Added `assets/3d/materials/wet_gravel.tres`, using existing ambientCG `Gravel027` PBR maps with darker wet-bank coloring.
  - Changed exposed gravel bars from flat ellipses to mounded bars with dry shoulders plus `WetPointBarAprons` sloping down to waterline.
  - Clipped `BoundedMovingWater` quads/triangles wherever their midpoint/triangle centers/corners classify as dry exposed bar, so water no longer renders under dry bars.
- Appended the change to session 8 transcript and planning notes.

## Validation
- `godot4 --headless --path . --scene res://scenes/RiverWorld3D.tscn --quit` passed.
- `godot4 --headless --path . --quit` passed.
- Forced mesh validation reported `BoundedMovingWater dry_water_tris=0`; `BoundedMovingWater`, `WetShorelineBlend`, `GravelWaterlineShelves`, `ExposedPointBars`, and `WetPointBarAprons` all had upward normals. Dummy renderer leak errors are expected for forced visual mesh construction in headless mode.