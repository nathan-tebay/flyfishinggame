# River Anatomy Implementation Plan

Implements real river anatomy (pool-riffle-run cycles, fish holding science, species-specific
behavior) into procedural generation and fish AI. Ordered for minimal file re-touching and
maximum early gameplay value.

**Status: All six phases implemented** (Session 4, 2026-03-27).

---

## Dependency Graph

```
Phase A  (RiverData fields + habitat classification)
    |-- Phase B  (bell curve + habitat hold scoring)
            |-- Phase C  (pool-riffle-run depth cycle)
                    |-- Phase D  (V-seam spawn offsets + species affinity)
                            |-- Phase E  (exposure-based spook sensitivity)

Phase F  (foam line visual) -- independent, additive-only
```

---

## Phase A -- Foundation: RiverData Fields + Habitat Classification

**Files:** `river_constants.gd`, `river_data.gd`, `river_generator.gd`
**Status:** Complete

### Implementation

**`river_constants.gd`** -- Habitat type constants:
```gdscript
const HABITAT_POOL_HEAD  := 0
const HABITAT_POOL_BELLY := 1
const HABITAT_POOL_TAIL  := 2
const HABITAT_RUN        := 3
const HABITAT_RIFFLE     := 4
const HABITAT_FORD       := 5
const HABITAT_POCKET     := 6
```

**`river_data.gd`** -- Two new arrays:
```gdscript
var habitat_type: Array = []      # RiverConstants.HABITAT_* per column
var exposure_factor: Array = []   # 0.0 (sheltered) .. 1.0 (fully exposed)
```

**`river_generator.gd`** -- Four additions:

1. `_init_arrays()`: fills both new arrays (default: HABITAT_RUN, exposure 0.5).

2. `_classify_habitat(data)` called after `_inject_ford_sections`, before `_build_tile_map`.
   Depth thresholds (as implemented):
   - `depth_profile < 0.12` -> HABITAT_FORD, exposure 1.0
   - `< 0.27` -> pool zone; two-pass sub-classification:
     - First 8 tiles entering a pool -> POOL_HEAD, exposure 0.35
     - Middle tiles -> POOL_BELLY, exposure 0.15
     - Last 10 tiles (depth rising) -> POOL_TAIL, exposure 0.70
     - Short pools (4-18 tiles): split into HEAD/TAIL only (no belly)
   - `0.27-0.68` -> HABITAT_RUN, exposure 0.45
   - `> 0.68` -> HABITAT_RIFFLE, exposure 0.85

3. `_classify_pocket_water(data)` called after `_apply_eddy_currents`. Labels
   the `sw * 2 + 4` tile window downstream of each ROCK/BOULDER structure as
   HABITAT_POCKET; reduces exposure by `fade * 0.30` (distance-proportional,
   fading over the window length). Skips ford columns.

4. Both calls wired into `generate()` at the correct positions.

---

## Phase B -- Hold Scoring Overhaul: Bell Curve + Habitat Weighting

**Files:** `river_generator.gd` only
**Status:** Complete

### Implementation

Replaced `_calculate_hold_scores()` internals.

**Gaussian bell curve** replacing linear `slow_sc`, peaking at current=0.6:
```gdscript
var bell_sc: float = exp(-pow((current_val - 0.60) / 0.35, 2.0))
```

**Habitat-adjusted depth multiplier** (hoisted before inner y-loop):
- POOL_BELLY -> x1.2
- RIFFLE -> x0.5
- POOL_HEAD/TAIL -> x0.9
- else -> x0.8

**Additive `habitat_sc` term:**
- POOL_BELLY: +0.40
- POOL_TAIL:  +0.25
- POOL_HEAD:  +0.15
- RUN:        +0.10
- RIFFLE:     -0.10
- POCKET:     +0.30
- FORD:       -0.50

**Final formula:** `cover + depth_sc + bell_sc + seam_sc + habitat_sc`

min_score threshold raised from 1.5 to 1.8.

---

## Phase C -- Pool-Riffle-Run Cycle in Depth Profile

**Files:** `river_generator.gd` only
**Status:** Complete

### Implementation

**Noise amplitude reduced** to texture-only contribution:
```gdscript
data.depth_profile[x] = clampf(normalized * 0.35 + 0.40, 0.0, 1.0)
```

**`_apply_pool_riffle_template(data)`** runs after noise, before ford injection.
Uses `RandomNumberGenerator` seeded `hash(data.seed + 55555)`.

Pool placement: 100-140 tiles apart (inherent variation in spacing range).
- First pool centre: random x in [80, 140]
- Subsequent pools: +100-140 tiles
- Stop when x > width - 80

Per pool, fixed zone lengths with cosine interpolation:
- Pool head (HEAD_LEN=15 tiles): cosine ramp from run depth (0.35-0.50) -> belly depth
- Pool belly (BELLY_LEN=30 tiles): target depth 0.06-0.14 (deep), +/- 0.02 noise texture
- Tailout (TAIL_LEN=20 tiles): cosine ramp from belly -> riffle depth (0.75-0.92)

Between pools, riffle injected after the tailout:
- 15-25 tiles forced to depth 0.76-0.90 (shallow/fast)
- 4-tile cosine taper on each end blends into existing noise values

**Ford protection:** Not needed -- pipeline order (`template -> fords`) means ford
injection runs after the template and overwrites any template values at ford positions.
`_classify_habitat` then reads the final profile including fords.

**Call order in `generate()`:**
```
_generate_depth_profile()       # noise baseline
_apply_pool_riffle_template()   # bake pool/riffle shape
_inject_ford_sections()         # fords override template
_classify_habitat()             # classify from final profile
_build_tile_map()               # build tiles
```

---

## Phase D -- V-Seam Spawn Offsets + Species Structure Affinity

**Files:** `river_generator.gd`, `river_world.gd`
**Status:** Complete

### Implementation

**`river_generator.gd`** -- `_find_top_holds()` calls `_annotate_hold()` per candidate.

Each hold dict receives four new fields:
- `"spawn_dx": int` -- tile offset downstream into V-seam (default 0)
- `"spawn_dy": int` -- tile offset vertically for bank-edge snapping (default 0)
- `"best_species": int` -- FishAI.Species (0/1/2) most appropriate for this lie
- `"exposure": float` -- copied from `data.exposure_factor[x]`

**`_annotate_hold(data, hold)`** (single helper, combines offset + annotation):
- If BOULDER/ROCK with hold within 2 tiles of structure's downstream edge ->
  `spawn_dx = sw * 2` (into V-seam). Clamps and verifies target is water.
- If UNDERCUT_BANK within 2x/3y tiles -> `spawn_dy` snaps to `top_bank_profile[hx]`.

**`_compute_species_affinity(data, hx, hy)`** -- per-species scoring:

Structure proximity weights (8-tile x radius, 4-tile y radius):
```
BOULDER nearby:          brown +0.80, rainbow +0.40
ROCK nearby:             brown +0.50, rainbow +0.35
UNDERCUT_BANK nearby:    brown +1.20, rainbow +0.10
WEED_BED nearby:         rainbow +0.60, brown +0.30
GRAVEL_BAR nearby:       whitefish +1.00, rainbow +0.30
```

Habitat base weights:
```
POOL_BELLY:   brown +0.60
POOL_HEAD:    brown +0.30, rainbow +0.20
POOL_TAIL:    rainbow +0.50, brown +0.30
RUN:          brown +0.20, rainbow +0.20
RIFFLE:       rainbow +0.70, whitefish +0.50
POCKET:       brown +0.40, rainbow +0.30
FORD:         whitefish +0.60, rainbow +0.20
```
Returns species index with highest score.

**`river_world.gd` -- `_spawn_section_fish()`:**
- Applies `spawn_dx` / `spawn_dy` when computing world position, with clamping.
- 65% `best_species` / 35% random baseline species assignment.
- Sets `fish.exposure_factor = hold.get("exposure", 0.5)`.
- MIN_FISH_DIST remains 48.0 (no reduction needed -- V-seam offsets did not
  cause significant dedup rejection).

---

## Phase E -- Exposure-Based Spook Sensitivity

**Files:** `spook_calculator.gd`, `fish_ai.gd`
**Status:** Complete

### Implementation

**`spook_calculator.gd`** -- `exposure_factor: float = 0.5` parameter added as the
last argument to `calculate()` and `is_within_radius()` (default preserves all
existing call sites). Incorporated as:
```gdscript
var exposure_mod := lerpf(0.70, 1.25, clampf(exposure_factor, 0.0, 1.0))
# Multiplied into directional_r:
var directional_r := base * size_mult * cover_mod * time_mod * approach * exposure_mod
```
- Pool belly fish (exposure ~0.15): radius x0.82 -- harder to spook
- Tailout fish (exposure ~0.70): radius x1.08 -- easier to spook
- Riffle fish (exposure ~0.85): radius x1.17

**`fish_ai.gd`** -- `var exposure_factor: float = 0.5` public property.
Passed to `SpookCalculator.calculate()` in `_check_angler()`.

---

## Phase F -- Foam Line Visual

**Files:** `river_renderer.gd` only
**Status:** Complete

### Implementation

`_foam_lines: Array` member (same pattern as `_ripples`).

**`_build_foam_lines(data)`** called from `render()` after `_build_arrows()`:
- Every 2nd column, every water row: seam strength =
  `abs(current_map[x+1][y] - current_map[x-1][y])`
- If `seam_strength > 0.25`, creates foam anchor dict:
  `{ wx, wy, drift_speed, phase, seam_width }`
- Subsampled to max 150 anchors via Fisher-Yates shuffle (seeded RNG).

**`_draw_foam_lines()`** called from `_draw()` after `_draw_arrows()`:
- Animated x offset: `fmod(_time * drift_speed * 40.0 + phase * 16.0, 24.0)`
- Primary dot: `draw_circle()` radius `lerpf(1.5, 3.5, seam_width)`,
  color `Color(1,1,1, seam_width * 0.55)`
- Two secondary dots +/-4px y at 65% radius and 50% alpha (foam line suggestion)

---

## Quick Reference

| Phase | Files | Primary Value |
|-------|-------|---------------|
| A | river_constants, river_data, river_generator | Foundation for B-E |
| B | river_generator | Fish in ecologically correct spots |
| C | river_generator | River looks and feels like a real river |
| D | river_generator, river_world | Species placement becomes meaningful |
| E | spook_calculator, fish_ai | Tailout tension; pool depth reward |
| F | river_renderer | Seam visibility; foam-is-home visual |

## Implementation Notes

- **Phase A** thresholds (0.27 pool, 0.68 riffle) were tuned during implementation
  from the original plan values (0.22, 0.72) to better match the pool-riffle template
  depth ranges from Phase C.
- **Phase C** uses fixed zone lengths (HEAD=15, BELLY=30, TAIL=20) rather than the
  originally planned random ranges. This gives more predictable pool structure.
  The tailout ramps to the actual adjacent riffle depth rather than a fixed 0.70.
- **Phase D** differentiates ROCK (brown +0.50) from BOULDER (brown +0.80) in
  species affinity -- the original plan lumped them together. V-seam proximity check
  uses a 2-tile downstream-edge threshold rather than the originally planned 6-tile
  upstream scan -- tighter and more correct since holds near structures are already
  close by definition.
- **Phase E** places `exposure_factor` as the last parameter with a default value,
  preserving backwards compatibility for any callers that don't need it.
- **Phase F** uses Fisher-Yates shuffle for fair subsampling of foam anchors.
