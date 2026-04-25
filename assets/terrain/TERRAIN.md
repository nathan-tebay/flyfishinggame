# 32x32 River Tiles — Deduped Individual PNG Set

This is a second-pass cleanup of the river tiles.

## What changed in this pass

- Removed exact and near-duplicate tiles within the same folder/category.
- Re-exported every PNG as a clean **32x32 opaque tile**.
- Filled/remediated transparent or pale background edge pixels so the tiles do not contain visible sheet borders.
- Preserved the directory structure and directional naming.

## Directional Naming

Bank folders describe where the **land/bank side** is located:

```text
edge_n      land on north/top side
edge_s      land on south/bottom side
edge_e      land on east/right side
edge_w      land on west/left side

corner_ne   land on north + east sides
corner_nw   land on north + west sides
corner_se   land on south + east sides
corner_sw   land on south + west sides
```

Example:

```text
banks/grass/edge_n/grass_bank_edge_n_001.png
```

means the grass bank is on the top edge, and water is mostly below it.

## Recommended Procedural Use

Generate your river as data first, then assign art:

```text
deep water -> mid water -> shallow water -> bank -> terrain
```

Use folders as weighted tile pools.

For example:

```gdscript
var grass_north_bank_tiles = load_tiles_from_folder("res://river_tiles/banks/grass/edge_n")
```

Then choose one randomly when your map cell has land to the north and water to the south.

## Important Generator Considerations

### 1. Keep river logic separate from art

Store gameplay information in a separate grid:

```text
depth
current_speed
wadeable
walkable
casts_blocked
fish_holding_quality
bank_material
```

Do not infer those values from the PNG.

### 2. Smooth material transitions

Grass, sand, and gravel should form patches. Avoid changing material every tile.

Good:

```text
grass bank for 10 cells -> sandbar for 6 cells -> gravel bend
```

Bad:

```text
grass -> sand -> gravel -> grass every tile
```

### 3. Avoid hard depth jumps

Best visual order:

```text
deep -> mid -> shallow -> shoreline
```

Avoid:

```text
deep -> bank
```

### 4. Use weighted randomization

Use common variants most of the time and special/odd variants rarely.

Example:

```text
basic edge: 70%
alternate edge: 25%
special detail: 5%
```

### 5. Reserve review tiles

Anything in `unclassified/review` should be manually inspected before being used by the generator.

## Files

- `tile_manifest_deduped.csv` lists kept files and removed duplicates.
- All PNGs are individual 32x32 tiles; no atlas is required.
