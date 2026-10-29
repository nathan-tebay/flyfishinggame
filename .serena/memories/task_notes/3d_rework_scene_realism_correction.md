# 3D Rework Scene Realism Correction

2026-05-26 after user screenshot:
- Problem observed: whole scene orange, empty/flat landscape, oversized rod, repetitive foam bands.
- `scripts/river/river_world_3d.gd`: decoupled sky/fog from saturated 2D RiverConstants dawn palette; added cooler natural sky/fog, filmic tonemapping, sun color helper, meadow fill planes, distant mountain/bench hill meshes. Background visual meshes skipped in headless checks to avoid dummy-renderer warnings.
- `scripts/river/river_3d_builder.gd`: added meadow fill material support, reduced foam density/size/alpha, reduced water foam seed intensity, added meadow fill before tile surfaces.
- `assets/3d/shaders/river_water.gdshader`: darker blue/green water, lower wave height, less foam/emission, less transparent water so sky doesn't wash through.
- `assets/3d/shaders/foam_flow.gdshader`: lower alpha and smaller displacement.
- Materials tuned darker/natural: bank grass, gravel, river shallow/mid/deep. Added `meadow_grass.tres` and `distant_mountain.tres`.
- `scenes/FirstPersonAngler.tscn`: rod made much thinner, lower/right, FOV reduced to 68 to reduce distortion.
- Verified clean: `godot4 --headless --path . --scene res://scenes/RiverWorld3D.tscn --quit` and `godot4 --headless --path . --quit`.