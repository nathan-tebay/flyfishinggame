# SNES River Tileset Plan

Target reference:

- [snes_river_tiles_target_v1.png](/mnt/LargeNVMe/Projects/GitHub/personal/flyfishinggame/assets/terrain/reference/snes_river_tiles_target_v1.png)

## Style target

- SNES-era 16-bit top-down fishing game
- cohesive limited palette
- restrained highlight treatment
- readable depth separation
- shoreline and water painted in the same visual language
- no bright cyan shoreline glow
- no painterly or photographic patchwork sampling

## Current issues

- `assets/terrain/water/*` is too large and too literal a crop of the reference sheet.
- Water tiles are not authored as a small reusable set, so the river reads as noisy mosaic instead of a game surface.
- `assets/terrain/banks/sand/*` is the only complete directional shoreline set.
- Terrain fills are adequate, but they need patch-level placement and fewer competing materials on screen.

## Runtime minimum set

Only these categories are required for a cohesive first pass:

- shallow water: 6 common, 2 rare
- mid-depth water: 6 common, 2 rare
- deep water: 6 common, 2 rare
- shallow-to-mid transition: 4 common, 2 rare
- mid-to-deep transition: 4 common, 2 rare
- shoreline straight edge: 4 common, 2 rare
- shoreline outer corner: 4 common, 2 rare
- shoreline inner corner: 2 common, 2 rare
- gravel bar: 4 common, 2 rare
- land fill primary: 6 common, 2 rare
- land fill secondary: 4 common, 2 rare

## Not needed for v1

These can be deferred until the base river reads cleanly:

- full grass/gravel directional bank families
- all terrain-to-terrain transition folders
- huge water variation pools
- special-case ripple tiles
- feature-specific water variants for every object class

## Regeneration order

1. Regenerate shoreline bank set in SNES target style.
2. Regenerate shallow, mid, and deep water tiles as seamless 32x32 tiles.
3. Regenerate only two water transition families:
   - shallow to mid
   - mid to deep
4. Build `shallow_to_deep` only if the generator truly produces hard jumps.
5. Regenerate gravel bar tiles to match the shoreline palette.
6. Re-tune renderer weighting after the smaller set is in place.
