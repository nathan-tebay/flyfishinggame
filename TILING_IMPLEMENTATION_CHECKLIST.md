# Tiling Implementation Checklist

This checklist reflects the current project state after reviewing `tiling.md`,
`scripts/river/river_renderer.gd`, `scripts/river/river_world.gd`, and the
terrain asset folders.

## Goal

Make the SNES-style river renderer use the available authored tile assets more
completely, reduce visible seams, and keep procedural section streaming visually
coherent.

## Current Facts

- `RiverRenderer` is the production renderer path.
- Active water, shoreline, and gravel bar modules are loaded from
  `assets/terrain/modules`.
- Curated runtime tiles also exist under `assets/terrain/runtime`, including
  water transition folders.
- `_blit_water_transition()` and `_transition_tile_info()` are wired into
  `_render_chunk()`, with directional blending kept as the fallback.
- Shoreline module placement now evaluates 2x2 footprints so opaque corner
  modules are only placed where the water quadrant matches the authored asset.
- Material transition assets already exist under `assets/terrain/transitions`,
  but bank material rendering does not use them.
- Section streaming exists in `RiverWorld`, with later sections rendered by new
  `RiverRenderer` instances and seeded from `GameManager.session_seed`.

## Phase 1: Wire Water Transition Tiles

- [x] Decide whether active renderer pools should use `assets/terrain/modules`
  or `assets/terrain/runtime` as the source of truth.
- [x] Add transition pool entries to `_TILE_POOL_DIRS`:
  - [x] `transition_shallow_mid`
  - [x] `transition_mid_deep`
  - [ ] `transition_shallow_deep`, if usable assets exist
- [x] Ensure `_MANIFEST_CATEGORY_BY_POOL` has matching entries for every loaded
  transition pool.
- [x] Update `_render_chunk()` so water transition rendering is part of the
  active pass.
- [x] Define transition priority explicitly:
  - [x] base water module
  - [x] authored transition tile, where available
  - [x] directional blend fallback, where no authored tile applies
- [x] Verify missing transition pools fail gracefully without blank tiles.
- [ ] Run a visual smoke test on shallow-to-mid and mid-to-deep boundaries.

## Phase 2: Fix Shoreline Corner Coverage

- [x] Review existing `shoreline_inner_corner` assets for orientation and alpha
  expectations.
- [x] Remove or replace the skip in `_blit_shoreline_modules()` for
  `shoreline_inner_corner`.
- [x] Add priority rules for overlapping shoreline anchors:
  - [x] outer corners
  - [x] inner corners
  - [x] straight edges
- [ ] Validate rotations and flips for all four corner cases.
- [x] Add a lightweight validation guard so shoreline modules are only placed
  when their water-facing side actually borders water.
- [ ] Test narrow bends, islands, gravel bars, and concave bank shapes.

## Phase 3: Bank Material Transitions

- [ ] Catalog usable transition folders under `assets/terrain/transitions`:
  - [ ] grass-to-gravel
  - [ ] grass-to-sand
  - [ ] sand-to-gravel
  - [ ] three-way variants, if useful
- [ ] Decide whether transition tiles should be loaded as 32x32 tiles,
  composed into 64x64 modules, or drawn as overlays.
- [ ] Add transition pool constants and load paths.
- [ ] Detect adjacent bank material changes around `_bank_material_at()`.
- [ ] Place material transition tiles at material boundaries.
- [ ] Keep plain material fill as the fallback for missing or ambiguous cases.
- [ ] Verify bank bands still read correctly:
  - [ ] shore sand/gravel
  - [ ] mid-bank gravel/sand mix
  - [ ] inland grass

## Phase 4: Edge Coherence And Seam Reduction

- [ ] Capture before screenshots of common seams:
  - [ ] water module boundaries
  - [ ] shoreline module boundaries
  - [ ] bank material boundaries
  - [ ] chunk boundaries inside a section
- [ ] Prefer deterministic module selection improvements before pixel blending.
- [ ] Evaluate `_pool_tile_image()` patch spans for visible repetition or abrupt
  changes.
- [ ] Add edge-aware selection only if visual seams remain after transition work.
- [ ] If needed, add a small seam blend pass with:
  - [ ] same-material boundaries only
  - [ ] configurable color-difference threshold
  - [ ] 1-3 pixel blend width
  - [ ] no blending across gameplay tile-type boundaries unless intentional
- [ ] Cache blend outputs without unbounded growth.

## Phase 5: Section Boundary Continuity

- [ ] Capture boundary screenshots between section `N` and `N + 1`.
- [ ] Determine whether seams come from:
  - [ ] river profile discontinuity
  - [ ] tile/module variant discontinuity
  - [ ] prop placement discontinuity
  - [ ] chunk sprite alignment
- [ ] Add generator-side continuity first if profiles do not match.
- [ ] Consider passing prior section boundary data into the next generation.
- [ ] Add a visual overlap/blend zone only if generation continuity is not
  sufficient.
- [ ] Verify section despawn and renderer positioning still behave correctly.

## Phase 6: Optional Water Motion

- [ ] Defer until the static renderer is clean.
- [ ] Decide whether animation should be:
  - [ ] tile variant cycling
  - [ ] overlay particles
  - [ ] shader/color modulation
- [ ] Use `current_map` to vary animation speed and direction.
- [ ] Keep animation deterministic by section seed and tile position.
- [ ] Verify it does not require regenerating whole chunk textures every frame.

## Verification

- [ ] Run Godot headless compile/smoke check.
- [ ] Launch the project and inspect at least one generated session.
- [ ] Verify no warnings for missing tile pools.
- [ ] Verify transition tiles appear at depth boundaries.
- [ ] Verify inner corners appear without wrong rotations.
- [ ] Verify bank transitions do not obscure water readability.
- [ ] Verify section streaming still loads and despawns sections correctly.
- [ ] Update `tiling.md` or project docs if the chosen asset source of truth
  changes.

## Suggested First Patch

Start with Phase 1. It is the smallest high-value change because most helper
logic already exists. The first patch should only wire transition pools, call the
transition path from `_render_chunk()`, and keep `_blit_water_depth_blend()` as a
fallback.
