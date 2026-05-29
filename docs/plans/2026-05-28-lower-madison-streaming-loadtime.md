# Lower Madison Streaming and Load-Time Improvement Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Improve startup/load time and make the Lower Madison environment scalable by splitting the USGS-derived reach into deterministic streamable segments while preserving the current fixed public-data geometry constraint.

**Architecture:** Keep `LowerMadisonReach` as the canonical full-reach data/query service for gameplay, but add a segment window layer that builds and keeps visible/render-heavy nodes only near the player. Static terrain/water/bank/prop meshes should be built per longitudinal station range, cached as scenes/resources, and loaded/unloaded as the angler moves upstream/downstream. Fish occupancy/session behavior remains seed-driven; real terrain/river shape remains fixed from public data.

**Tech Stack:** Godot 4.3, GDScript, ArrayMesh/SurfaceTool/MultiMeshInstance3D, ResourceLoader threaded loading, NHD/3DEP source files under `assets/3d/geodata/`.

---

## Current observations

- Active scene: `scenes/RiverWorld3D.tscn`.
- Main orchestration: `scripts/river/river_world_3d.gd`.
- Geometry/query source: `scripts/river/lower_madison_reach.gd`.
- Mesh builder: `scripts/river/river_3d_builder.gd`.
- Current builder constructs the whole rendered reach in one `build()` call:
  - 3DEP terrain
  - channel bed/water
  - bank corridor
  - gravel bars
  - cobbles
  - structures
  - weed beds
  - riparian cover
  - adult insects
  - seeded fish
- Headless mode currently returns before visual mesh generation, so normal `godot4 --headless --path . --scene ... --quit` does not measure real render-load cost.
- The current reach is already a compressed public-data replica: NHD flowline + 3DEP samples, with gameplay-authored bars/holds/structures over that geometry. Do not use Google imagery as a shipped terrain/texture source.

---

## Recommendation

Yes: tiled/streamed loading is the right direction, but do it as streamable longitudinal river segments, not square map tiles.

Reasoning:

- The river gameplay is naturally indexed by downstream fraction/station, not a uniform world grid.
- Current queries already expose station/fraction/lateral, so segmenting by fraction keeps hydraulic gameplay simple.
- It preserves the fixed Lower Madison replica: the full source reach still exists in `LowerMadisonReach`; only the visible meshes/props are paged.
- It scales to a longer replica later, such as additional NHD reaches upstream/downstream from Black's Ford.

Target model:

- Segment length: start with 80-120 meters real-distance equivalent or 0.08-0.12 fraction chunks for the current compressed reach.
- Active radius: current segment plus 1 segment upstream and 1 segment downstream.
- Prefetch radius: one additional segment each direction, loaded in background if possible.
- Far view: keep cheap distant terrain/banks as one low-detail background mesh or impostor, not full interactive detail.
- Gameplay authority: `LowerMadisonReach.sample()` stays valid everywhere, even where visible meshes are not loaded.

---

## Phase 1: Measure before optimizing

### Task 1: Add a load-profile probe script

**Objective:** Measure visual build time, node counts, mesh counts, and per-builder-stage time in a reproducible way.

**Files:**
- Create: `tests/river_load_profile.gd`
- Modify: none initially

**Steps:**
1. Create a script that instantiates `LowerMadisonReach` and `River3DBuilder`.
2. Set `builder.force_headless_build = true` so the visual builder path runs under headless.
3. Time `builder.build(reach, seed)` with `Time.get_ticks_msec()`.
4. Count generated children, `MeshInstance3D`, `MultiMeshInstance3D`, surfaces, and rough vertex counts where accessible.
5. Print one compact summary line.

**Validation:**

Run:

```bash
godot4 --headless --path . --script tests/river_load_profile.gd
```

Expected:

- Exit code 0.
- Output includes total build milliseconds and generated node/mesh counts.

### Task 2: Add per-stage timing inside the builder behind a debug flag

**Objective:** Identify whether load time is dominated by terrain, channel, vegetation, fish/insects, or props.

**Files:**
- Modify: `scripts/river/river_3d_builder.gd`
- Test: `tests/river_load_profile.gd`

**Steps:**
1. Add `var profile_build := false` to `River3DBuilder`.
2. Add a helper like `_profile_stage(name: String, callable: Callable) -> void` or simple start/stop logging around existing `_build_*` calls.
3. Only print timing when `profile_build` is true and `OS.is_debug_build()`.
4. Set `profile_build = true` in the probe.

**Validation:**

Run:

```bash
godot4 --headless --path . --script tests/river_load_profile.gd
```

Expected:

- Stage timings appear.
- Existing smoke checks still pass.

---

## Phase 2: Separate gameplay reach data from render chunks

### Task 3: Add segment metadata helpers to `LowerMadisonReach`

**Objective:** Make station-range segmenting first-class without changing existing sample semantics.

**Files:**
- Modify: `scripts/river/lower_madison_reach.gd`
- Create: `tests/reach_segment_bounds_check.gd`

**Add helpers:**

```gdscript
func segment_count(segment_length_m: float) -> int:
	return max(1, int(ceil(_length / maxf(segment_length_m, 1.0))))

func segment_fraction_range(segment_index: int, segment_length_m: float, overlap_m: float = 0.0) -> Vector2:
	var count := segment_count(segment_length_m)
	var start_distance := maxf(0.0, float(segment_index) * segment_length_m - overlap_m)
	var end_distance := minf(_length, float(segment_index + 1) * segment_length_m + overlap_m)
	return Vector2(start_distance / _length, end_distance / _length)

func segment_index_for_world_pos(world_pos: Vector3, segment_length_m: float) -> int:
	var sample_data := sample(world_pos)
	return clampi(int(floor(float(sample_data["fraction"]) * _length / maxf(segment_length_m, 1.0))), 0, segment_count(segment_length_m) - 1)
```

**Validation:**

Run:

```bash
godot4 --headless --path . --script tests/reach_segment_bounds_check.gd
```

Expected:

- Segment ranges cover 0.0 to 1.0.
- Adjacent ranges are ordered.
- Player start maps to a valid segment.
- `sample()` output is unchanged for representative positions.

### Task 4: Extract render-range build methods from `River3DBuilder`

**Objective:** Let the builder generate meshes for a fraction range instead of always the whole reach.

**Files:**
- Modify: `scripts/river/river_3d_builder.gd`
- Test: `tests/river_load_profile.gd`

**Steps:**
1. Add `func build_segment(authored_reach, fish_seed, segment_index, fraction_min, fraction_max) -> Node3D` or create a dedicated `RiverSegmentBuilder` if the file gets too large.
2. Refactor loops like `for i in range(reach.station_count() - 1)` to use a helper returning station index bounds for a fraction range.
3. Include a small overlap at edges so water/bank meshes do not show cracks.
4. Keep global whole-reach `build()` working by delegating to one full-range segment initially.
5. Do not change `LowerMadisonReach.sample()` or fish gameplay behavior yet.

**Validation:**

Run:

```bash
godot4 --headless --path . --script tests/river_load_profile.gd
godot4 --headless --path . --scene res://scenes/RiverWorld3D.tscn --quit
godot4 --headless --path . --quit
```

Expected:

- Full-range generated scene is visually/functionally equivalent.
- Segment-only build is faster than full build for a small fraction range.

---

## Phase 3: Runtime streaming manager

### Task 5: Create a river segment streamer node

**Objective:** Load/unload segment Node3D containers around the player's current downstream fraction.

**Files:**
- Create: `scripts/river/river_segment_streamer.gd`
- Modify: `scenes/RiverWorld3D.tscn` to add a `RiverSegmentStreamer` child, or instantiate it from `river_world_3d.gd`
- Modify: `scripts/river/river_world_3d.gd`

**Core state:**

```gdscript
const SEGMENT_LENGTH_M := 120.0
const SEGMENT_OVERLAP_M := 8.0
const ACTIVE_SEGMENT_RADIUS := 1
const PREFETCH_SEGMENT_RADIUS := 2

var reach: LowerMadisonReach = null
var builder: River3DBuilder = null
var player: Node3D = null
var loaded_segments := {}
var loading_segments := {}
var current_center_segment := -1
```

**Steps:**
1. Initialize streamer after `_generate_river()` creates the reach.
2. On a low-frequency timer, compute `reach.segment_index_for_world_pos(player.global_position, SEGMENT_LENGTH_M)`.
3. Ensure center +/- active radius are present.
4. Queue unload for segments outside active radius + 1.
5. Keep unload delayed/faded if visual popping is obvious.

**Validation:**

- Start at player position: 3 active segments loaded.
- Move a fake/test player position upstream/downstream: segment set changes deterministically.
- Existing clamp/player movement uses full world bounds and reach queries, not only loaded mesh bounds.

### Task 6: Make heavy visual systems segment-aware

**Objective:** Avoid building insects, fish models, vegetation, cobbles, weeds, and props outside active segments.

**Files:**
- Modify: `scripts/river/river_3d_builder.gd`
- Modify: `scripts/river/river_world_3d.gd` if fish AI currently scans builder-wide fish entries
- Test: new or updated streaming probe

**Steps:**
1. Filter `STRUCTURES`, `GRAVEL_BARS`, `WEED_BEDS`, tree clusters, willow clusters, insects, and fish holds by segment fraction range.
2. Keep fish gameplay data seed-stable: fish occupancy should be a deterministic function of global hold ID + session seed, not segment load order.
3. When a segment unloads, remove only visual fish nodes in that segment. If a hooked/drifting interaction is active, pin that segment until the interaction ends.
4. Cap ambient/living systems globally, not per segment, so loading more segments does not multiply updates unboundedly.

**Validation:**

Run existing gameplay probes:

```bash
godot4 --headless --path . --script tests/casting_loop_modes_check.gd
godot4 --headless --path . --script tests/casting_loop_check.gd
godot4 --headless --path . --scene res://scenes/RiverWorld3D.tscn --quit
```

Expected:

- Casting/drift/fish loops still work in loaded segments.
- No crashes when fish visual nodes unload outside the active area.

---

## Phase 4: Cache static chunks for faster startup

### Task 7: Add an editor/offline chunk bake command

**Objective:** Avoid rebuilding unchanged static geometry at runtime.

**Files:**
- Create: `tools/bake_river_segments.gd`
- Create directory: `assets/3d/generated/lower_madison_segments/`
- Modify: `.gitignore` only if generated files should not be committed

**Steps:**
1. Use the same segment builder to generate static meshes per segment.
2. Save each segment as `.tscn` or mesh resources under `assets/3d/generated/lower_madison_segments/`.
3. Include a manifest with source data hash, segment length, overlap, Godot version, and builder version.
4. Runtime loads baked segment scenes when manifest matches; otherwise falls back to procedural build with a debug warning.

**Validation:**

Run:

```bash
godot4 --headless --path . --script tools/bake_river_segments.gd
godot4 --headless --path . --script tests/river_load_profile.gd
```

Expected:

- Bake succeeds.
- Runtime load path is faster than procedural full build.
- Manifest mismatch produces a clear rebuild-needed warning.

### Task 8: Add threaded prefetch for baked segment scenes

**Objective:** Hide segment load time during walking/wading.

**Files:**
- Modify: `scripts/river/river_segment_streamer.gd`

**Steps:**
1. Use `ResourceLoader.load_threaded_request(path)` for prefetch radius segments.
2. Poll `ResourceLoader.load_threaded_get_status(path)` on the streamer's timer.
3. Instantiate when complete and segment is still wanted.
4. If threaded load is unavailable or failed, fall back to synchronous load for active-radius emergency only.

**Validation:**

- Walking across segment boundaries should not stutter noticeably on a normal machine.
- Segment count/load status can be shown in debug HUD temporarily.

---

## Phase 5: Extend the public-data replica upstream/downstream

### Task 9: Build a multi-reach source manifest

**Objective:** Prepare for a longer Lower Madison replica without changing gameplay code again.

**Files:**
- Create: `assets/3d/geodata/lower_madison_manifest.json`
- Modify: `docs/LOWER_MADISON_REACH.md`
- Later modify: `scripts/river/lower_madison_reach.gd`

**Manifest should record:**

- NHD flowline feature IDs/reach codes used.
- 3DEP bbox/clip URLs and retrieval date.
- Local projection/origin.
- Compression factors.
- Segment length/overlap.
- License/source acknowledgement.

**Important constraint:**

- Use USGS NHD/3DEP and documented public data only.
- Google imagery can guide informal comparison, but must not be traced or shipped as source geometry/texture.

### Task 10: Generalize `LowerMadisonReach` into loaded public-data reaches

**Objective:** Replace hard-coded single-bend constants gradually while preserving the current Black's Ford bend behavior.

**Files:**
- Modify: `scripts/river/lower_madison_reach.gd`, or split into:
  - `scripts/river/public_river_reach.gd`
  - `scripts/river/lower_madison_reach.gd`

**Steps:**
1. Keep the current class as compatibility wrapper.
2. Move source-data loading/projection/station building into a reusable class.
3. Move authored gameplay anchors into data tables keyed by segment or reach ID.
4. Preserve exact output for the current bend with a regression test comparing start position, bounds, station count, and sample values.

**Validation:**

- Current Black's Ford scene remains unchanged.
- New upstream/downstream reach segments can be appended from public source data.

---

## Acceptance criteria

- Startup no longer builds the entire rendered river synchronously unless debug/full-build mode is enabled.
- Player can move upstream/downstream and nearby segments appear before they are needed.
- `LowerMadisonReach.sample()` remains canonical for movement, current, depth, cast drift, fish holds, and habitat.
- Session seed changes fish occupancy/behavior only, not terrain or channel shape.
- Existing tests and smoke checks pass:

```bash
godot4 --headless --path . --script tests/casting_loop_modes_check.gd
godot4 --headless --path . --script tests/casting_loop_check.gd
godot4 --headless --path . --scene res://scenes/RiverWorld3D.tscn --quit
godot4 --headless --path . --quit
git diff --check
```

- New checks pass:

```bash
godot4 --headless --path . --script tests/river_load_profile.gd
godot4 --headless --path . --script tests/reach_segment_bounds_check.gd
```

---

## Risks and mitigations

- Mesh cracks at segment borders: use station-overlap and hide seams under water/bank overlap.
- Fish unload during interaction: pin active interaction segment until drift/take/hookset resolves.
- Pop-in: prefetch one segment beyond active radius and optionally fade vegetation/props.
- Duplicate props at overlap edges: assign each prop to exactly one owner segment by anchor fraction; only geometry strips use overlap.
- Bigger real-world replica increases source-data complexity: add a manifest and source hashes before expanding the map.
- Premature complexity: first measure and segment the current builder before introducing baked caches/threaded loading.

---

## Additional optimizations worth doing

These can be implemented before or alongside streaming. They are lower-risk than full streaming and many will still pay off after streaming exists.

### A. Reuse/cached mesh resources for repeated simple models

Current builder creates new primitive mesh resources for boulders, logs, trunks, cottonwood crowns, reeds, and similar repeated props. Cache base meshes as member variables or prebuilt `.tres` resources, then vary instances with transform/scale/material.

Priority: high.

Expected benefit: faster build, fewer duplicated mesh resources, lower memory churn.

Best targets:

- `River3DBuilder._add_boulder()`
- `River3DBuilder._add_log()`
- `River3DBuilder._add_cottonwood()`
- `River3DBuilder._add_willow()`
- reed/grass mesh creation in `_build_reeds_and_grasses()`

### B. Convert repeated tree crowns/trunks to MultiMesh where interaction is not needed

Cottonwood and willow geometry is currently made of many individual `MeshInstance3D` nodes. Replace non-interactive clusters with one or more `MultiMeshInstance3D` batches per material/LOD band.

Priority: high if node count or render-thread cost is high.

Expected benefit: fewer nodes, fewer draw calls, faster scene instantiation.

### C. Avoid rebuilding cast line meshes every frame unless inputs changed enough

`RiverWorld3D._refresh_cast_line_attachment()` can call `_rebuild_cast_line()` every frame during target lock/drift, and `_rebuild_cast_line()` creates new `ImmediateMesh` resources for fly line and leader. Add a dirty/update threshold:

- Only rebuild if rod tip moved more than a small threshold, target moved more than a small threshold, or current sample changed materially.
- Or update an existing `ArrayMesh`/ImmediateMesh at a lower frequency, such as 20-30 Hz.
- During static target lock, the target and current are stable; only rod-tip motion needs updates.

Priority: medium-high.

Expected benefit: lower per-frame allocation and smoother runtime, especially on lower-end GPUs/CPUs.

### D. Decimate/LOD the channel and terrain by distance

The channel cross-section currently uses `CHANNEL_CROSS_SEGMENTS := 36` for the whole reach. For a streamable world, use multiple LODs:

- Near segment: current 36 cross segments.
- Mid segment: 18 cross segments.
- Far/impostor: 6-10 cross segments, no detailed bed color, no tiny props.

Priority: medium.

Expected benefit: lower vertex count and faster chunk generation/load.

### E. Split static, dynamic, and gameplay update loops

`RiverWorld3D._process()` updates lighting, rises, foam, birds, fish AI, dry-fly drift, HUD, and cast line every frame. Some systems do not need frame-rate updates.

Suggested cadence:

- Every frame: player movement, active drift, active cast line if visible.
- 10-20 Hz: fish AI, surface rises, foam drift, bird flock.
- 2-5 Hz: HUD text, hatch/status strings, debug label.
- On event/time-change only: lighting if time-of-day changes slowly.

Priority: medium.

Expected benefit: less scripting overhead and fewer string allocations every frame.

### F. Replace per-frame full fish scans with spatial/segment filtering

Fish AI and cast disturbance scan all `builder.fish_hold_entries`. That is fine now, but it will not scale to a longer replica. Store fish holds by segment and only update:

- active segment +/- 1 for alert/spook checks
- nearby holds around cast target for cast disturbance
- nearby feeding-lane holds around active fly drift

Priority: medium now, high before expanding the river length.

Expected benefit: gameplay cost scales with nearby fish, not total river length.

### G. Pool short-lived visual effects

Surface rises, foam flecks, markers, and cast visual nodes should be object-pooled once counts grow. Avoid repeated `new()`/`queue_free()` during normal play.

Priority: medium.

Expected benefit: fewer hitches from allocation/free cycles.

### H. Build a near/far material strategy

Use cheaper materials for far chunks:

- Far water: simpler transparent material or opaque stylized water strip.
- Far vegetation: unshaded/alpha-scissor billboards or MultiMesh impostors.
- Far terrain: lower texture detail and no per-vertex debug color requirements.

Priority: medium after streaming exists.

Expected benefit: lower shader/material cost and fewer transparency issues.

### I. Gate or disable expensive ambience by quality setting

Add a simple environment quality config:

- low: no insects, fewer foam flecks/rise rings, low vegetation density
- medium: current-ish
- high: extra insects/foam/vegetation/far detail

Priority: medium.

Expected benefit: gives immediate performance fallback without redesigning gameplay.

### J. Cache reach computations used repeatedly in mesh building

Mesh building repeatedly calls `half_width_at`, `frame_at_fraction`, `water_depth_at`, `terrain_height_at`, and related functions. Add per-station or per-segment caches for generated frames, widths, bank heights, and depth samples.

Priority: medium-high if profiling shows build CPU dominated by reach queries.

Expected benefit: faster procedural/bake build and easier deterministic tests.

---

## Suggested implementation order

1. Load profiling.
2. Builder stage timing.
3. Quick wins: cached primitive meshes, MultiMesh tree clusters, lower-frequency HUD/fish/ambience updates.
4. Cast-line dirty updates / allocation reduction.
5. Segment helpers on `LowerMadisonReach`.
6. Segment-range build path with full-build compatibility.
7. Runtime streamer around player.
8. Segment-aware fish/props/living systems.
9. Offline static chunk baking.
10. Threaded prefetch.
11. Multi-reach public-data manifest.
12. Longer Lower Madison expansion.
