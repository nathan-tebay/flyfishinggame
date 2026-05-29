# Lower Madison Reach: Black's Ford Bend

## Selection

The first 3D environment represents the readable approach bend immediately upstream of **Black's Ford FAS** within the Warm Springs–Black's Ford Lower Madison float. Montana FWP identifies Black's Ford on the Madison River at approximately `45.64638, -111.52247`; the selected hydrography segment terminates close upstream at `45.64615, -111.52450`.

## Public source data

Retrieved on 2026-05-26:

| Purpose | Runtime/source file | Dataset / request |
| --- | --- | --- |
| River alignment | `assets/3d/geodata/lower_madison_nhd_flowline.geojson` | USGS NHD Flowline - Large Scale, permanent identifier `52394513`, reach code `10020007003886`, `GNIS_NAME=Madison River` |
| River area reference | `assets/3d/geodata/lower_madison_nhd_area.geojson` | USGS NHD Area - Large Scale, perennial river polygon |
| Landform | `assets/3d/geodata/lower_madison_3dep_128.tif` | USGS 3DEP dynamic elevation service clip, WGS84 bbox `[-111.535,45.637,-111.523,45.647]`, 128 × 128 float TIFF |
| Runtime terrain grid | `assets/3d/geodata/lower_madison_3dep_samples.json` | 33 × 33 reduction of the archived 3DEP clip |

Services:

- USGS NHD: https://hydro.nationalmap.gov/arcgis/rest/services/nhd/MapServer
- USGS 3DEP: https://elevation.nationalmap.gov/arcgis/rest/services/3DEPElevation/ImageServer
- Montana FWP Black's Ford FAS: https://myfwp.mt.gov/fishMT/fas/39753502

NHD service metadata states the data are open and non-proprietary and requests USGS acknowledgement for derived works. The source files above preserve that acknowledgement and reproducibility.

## Coordinate treatment

`LowerMadisonReach` reads the NHD flowline at runtime, projects longitude/latitude locally in meters, rotates downstream onto game X, and compresses only for playability:

- longitudinal factor: `0.40`
- cross-channel factor: `0.85`
- terrain vertical factor: `0.15`

The real bend direction and relative approach to Black's Ford remain readable while the full 1.157 km NHD reach fits a walkable scene. Fixed bank shelves, bars, hydraulic zones, boulders, weed edges, and vegetation anchors are authored over the public geometry.

## Hydraulic/gameplay zones

Reach queries expose dry land versus water, water surface, bed height/depth, current strength/vector, habitat name, and hold distance. Fixed habitat names:

- shallow riffle
- main run
- deeper seam
- bank pocket
- boulder pocket
- weed edge
- gravel shallows

Session seeds choose occupied hold silhouettes only. They never regenerate terrain, river shape, structures, bars, or vegetation.

## Imagery/legal boundary

No Google Maps/Earth imagery, elevation, traced channel geometry, or texture content is shipped or used to build the reach. Google products may be used only for informal visual inspection outside the asset pipeline. Geometry and terrain shipped here derive from public USGS data.
