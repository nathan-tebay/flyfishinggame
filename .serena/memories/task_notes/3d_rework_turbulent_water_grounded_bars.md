# 3D Rework Turbulent Water / Grounded Bars

On 2026-05-27, user screenshot showed moving pale foam polygons. User requested replacing them with a more river-like turbulent water surface and grounding bars into the riverbed.

## Fix
- Removed runtime `LocalizedRiffleFoam` generation from `scripts/river/river_3d_builder.gd` (`_build_local_foam`, wake/ribbon helpers, and MAT_FOAM preload no longer used).
- Increased `CHANNEL_CROSS_SEGMENTS` from 18 to 36 for better water displacement geometry.
- Updated `assets/3d/shaders/river_water.gdshader` and `assets/3d/materials/river_water.tres`:
  - Added procedural fbm/noise, current-thread masks, cross ripples, broad boils, stronger vertex displacement, and restrained integrated foam/riffle brightness.
  - No separate bright rectangle foam decals.
- Lowered point bar relief and added `SubmergedPointBarBedTransitions` mesh using `MAT_RIVERBED`, sloping from wet apron down to sampled underwater bed.
- Expanded builder-side water clipping over the dry/wet visual bar footprint so water does not render beneath bar surfaces; water remains over submerged transitions.

## Validation
- `godot4 --headless --path . --scene res://scenes/RiverWorld3D.tscn --quit` passed.
- `godot4 --headless --path . --quit` passed.
- `git diff --check` passed.
- Forced mesh check: `bad_foam_node=absent`; `BoundedMovingWater dry_water_tris=0`; water, shoreline, bars, wet aprons and submerged bar-bed transitions all reported upward normals. Dummy renderer leak errors remain expected for forced mesh construction.