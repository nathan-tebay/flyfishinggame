# 3D Rework Fish-Fin Shard Suppression

Follow-up on 2026-05-27 after screenshot still showed bright triangular shards across clear water.

## Diagnosis
The visible shards were not the water shader foam. They matched the `FishModel3D` fin geometry: double-sided transparent triangular fin meshes using `assets/3d/materials/fish_fin.tres`. Under clear water and screen-space sorting, those translucent fins rendered as pale/pink shards.

## Fix
- `assets/3d/materials/fish_fin.tres`: changed fin material from translucent alpha-blended to opaque matte dark green/gray (`transparency = 0`, darker albedo, roughness 0.82, disabled specular mode). Resource renamed to `FishFinMatte`.
- `scripts/models/fish_model_3d.gd`: reduced dorsal, adipose, pectoral, tail, and whitefish sail fin triangle extents so fish read as subtle underwater silhouettes, not large panels.

## Validation
- `godot4 --headless --path . --scene res://scenes/RiverWorld3D.tscn --quit`: pass.
- `godot4 --headless --path . --script /tmp/test_fish_fin_material.gd`: `fins=4 transparent=0`; dummy renderer shutdown warnings are expected after forced mesh creation.
- `git diff --check` and whitespace check on touched files: pass.

No commit was made.