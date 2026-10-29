# 3D Rework White-Shard Suppression

On 2026-05-27, after removing the foam ribbon node, a follow-up screenshot still showed bright triangular shards across the current.

## Diagnosis
- `LocalizedRiffleFoam` was absent, so remaining shards were from overly contrasty water shader foam/specular/fresnel masks, with adult insect wing triangles a possible secondary light-catching source.

## Fix
- Retuned `assets/3d/shaders/river_water.gdshader` and `assets/3d/materials/river_water.tres`:
  - Foam color changed from white to muted blue-gray.
  - Foam masks made softer/lower strength; max foam greatly reduced.
  - Foam emission removed; roughness increased; specular and fresnel reduced.
  - Kept turbulence through broad current threads/ripples/boils and moderate vertex displacement.
- Adjusted `scripts/river/river_3d_builder.gd`:
  - Shoreline and bar lift constants lowered so wet gravel/bar aprons sit into the water rather than creating hard pale seams.
  - Ambient adult insects scaled down from ~0.18-0.22 to ~0.08-0.10.
- Adjusted `scripts/river/river_world_3d.gd`: cast dry-fly marker scale reduced from 0.22 to 0.10.
- Adjusted `assets/3d/materials/insect_wing.tres`: wings darker, more transparent, and rougher.

## Validation
- `godot4 --headless --path . --scene res://scenes/RiverWorld3D.tscn --quit` passed.
- `godot4 --headless --path . --quit` passed.
- `git diff --check` passed.
- Forced mesh check: `bad_foam_node=absent`; `BoundedMovingWater dry_water_tris=0`; upward normals on water, shoreline, bars, wet aprons, and submerged bar-bed transitions. Dummy renderer leak errors expected for forced visual mesh construction.