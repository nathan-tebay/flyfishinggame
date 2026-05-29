# Lower Madison 3D Assets

`RiverWorld3D` renders a fixed authored reach: the bend immediately upstream of Black's Ford Fishing Access Site on the Lower Madison. Session seeds alter visible fish-hold occupancy only; they do not alter channel, bars, boulders, vegetation, or terrain.

## Geographic assets

- `geodata/lower_madison_nhd_flowline.geojson` — USGS NHD high-resolution Madison River flowline `52394513`, used at runtime for centerline geometry.
- `geodata/lower_madison_nhd_area.geojson` — USGS NHD perennial river area source retained for shoreline alignment reference.
- `geodata/lower_madison_3dep_128.tif` — clipped USGS 3DEP terrain source.
- `geodata/lower_madison_3dep_samples.json` — reduced terrain grid used by runtime mesh generation.

`scripts/river/lower_madison_reach.gd` converts WGS84 source geometry to local coordinates and applies controlled compression (`0.40` longitudinal, `0.85` cross-channel). It owns fixed water/land queries, bed depth, current vector, named habitats, structures, vegetation anchors, start bank, and fish-hold anchors.

## Imported PBR materials

Runtime PBR texture maps under `pbr/ambientcg/` are CC0 ambientCG 1K JPG downloads:

- `Gravel027` — wet cobble bed, shoreline gravel, boulders.
- `Grass001` — vegetated bank and meadow.
- `Ground027` — dry valley/bench soil.

Materials bind imported color, OpenGL normal, roughness, and ambient-occlusion maps through Godot resources. No generated albedo images or runtime `ImageTexture` loading are used.

## Rendering

- `riverbed.tres` / `riverbed.gdshader` — carved cobble channel with imported PBR maps.
- `river_water.tres` / `river_water.gdshader` — bounded moving water with depth/current vertex data.
- `bank_gravel.tres`, `bank_grass.tres`, `bank_soil.tres`, `meadow_grass.tres` — dry/wet corridor and valley surfaces.
- `foam.tres` — localized riffle streaks and boulder wakes only.
- `submerged_weeds.tres` — fixed Lower Madison weed edges.
- `fish_*` — separate materials for modeled rainbow trout, brown trout, and mountain whitefish coloration/fins/markings.
- `insect_*` — adult mayfly and adult caddis body/wing/detail materials.
- `rod_*` / `fly_line.tres` — full-length graphite rod, cork grip, reel, snake guides, and threaded line.

`scripts/river/river_3d_builder.gd` builds continuous riverbed, water, gravel shelves, exposed bars, 3DEP bench terrain, fixed structures, clustered riparian cover, seed-selected modeled fish, and centimeter-scale adult surface insects. `scripts/models/` owns reusable fish/insect constructions; `scripts/player/fly_rod_3d.gd` builds the 2.74 m tackle model. The removed 2D/tile runtime is not supported.

See `docs/LOWER_MADISON_REACH.md` and `pbr/ambientcg/LICENSE_SOURCES.md` for source and license records.
