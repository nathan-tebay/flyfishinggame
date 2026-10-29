# Authored Reach Water-Surface Correction

On 2026-05-27 the user supplied a screenshot showing the 3D river still rendering as broad pale/sky-colored triangles with missing readable water.

## Diagnosis
- `River3DBuilder` generated `CarvedCobbleRiverbed`, `BoundedMovingWater`, and `LocalizedRiffleFoam` with downward-facing normals; backface culling hid the playable water/bed surface from above.
- `GravelWaterlineShelves` and `VegetatedBankBenches` had one of two bank sides downward-facing.
- Raw short-segment NHD/artificial-path tangents rotated sharply enough at bends for wide channel/bank offset strips to fold through themselves.
- The transparent water shader used `depth_prepass_alpha`, defeating the intended visible cobble bed beneath shallow water.

## Fix
- Added reversed quad helpers in `scripts/river/river_3d_builder.gd`; used them for water, bed, foam, and only the downward bank side. Terrain and gravel bars already had upward winding.
- Added `FRAME_TANGENT_RADIUS := 48.0` in `scripts/river/lower_madison_reach.gd`, smoothing cross-channel render/sample frames over the unchanged authored centerline so wide offset strips do not fold at public-data bends.
- Made nearest sampling use the same smoothed channel frame as visual geometry.
- Removed water and foam transparent depth prepasses; reduced water opacity while darkening water tint, and reduced foam alpha/emission.
- Recorded correction in session 8 transcript/planning notes.

## Validation
- Forced generated mesh normal scan: `CarvedCobbleRiverbed`, `BoundedMovingWater`, `GravelWaterlineShelves`, `VegetatedBankBenches`, `ExposedPointBars`, `USGS3DEPValleyTerrain`, and `LocalizedRiffleFoam` all report upward normals only.
- Corridor fold test: `folded_water=0 folded_bank=0 water_min_area=38.673 bank_min_area=21.844`.
- Reach query test passes with fixed reach length 509.31, dry start, dry exposed bar and all seven water habitats.
- `godot4 --headless --path . --scene res://scenes/RiverWorld3D.tscn --quit` passes.
- `git diff --check` passes.