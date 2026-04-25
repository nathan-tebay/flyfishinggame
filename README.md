# Fly Fishing Game

Godot 4.3 fly-fishing prototype with a procedural `RiverData` gameplay map, sprite-driven character/fish visuals, and two parallel terrain art paths:

- `assets/sprites/` is the current source-art tree for angler, fish, insects, props, and the custom river renderer inputs.
- `assets/terrain/river_atlas/` is the regenerated packed terrain atlas and TileSet for TileMap experiments and editor painting.

## Project Layout

- `assets/README.md` documents the asset layout and which folders are source art versus generated terrain packs.
- `assets/sprites/` contains the checked-in sprite sheets and metadata used by the live sprite integration work.
- `assets/terrain/river_atlas/` contains the generated `river_terrain_atlas_32.png`, `river_terrain_tileset.tres`, and supporting manifests/templates.
- `scenes/` contains the main Godot scenes, including `RiverWorld.tscn`.
- `scripts/river/` contains the live river generation and rendering code plus the atlas TileMap prototype.

## Current Terrain Status

`RiverWorld` still renders through the custom `RiverRenderer` path. The generated terrain atlas pack is kept in-repo as a normalized asset pack and comparison/prototyping path; it is not yet the production renderer source of truth.

## Validation

Headless startup check:

```bash
godot4 --headless --path /mnt/LargeNVMe/Projects/GitHub/personal/flyfishinggame --quit
```
