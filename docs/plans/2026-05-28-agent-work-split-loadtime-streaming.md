# Agent Work Split: Lower Madison Load-Time and Streaming Optimizations

> Source plan: `docs/plans/2026-05-28-lower-madison-streaming-loadtime.md`

Goal: split load-time, runtime optimization, river-segment streaming, baked chunks, and public-data expansion into agent-sized work packages with clear ownership boundaries.

Global constraints:
- Keep runtime 3D-only.
- Do not reintroduce `RiverWorld.tscn`, classic runtime selection, procedural 2D river tiles, or pixel-art assets.
- `LowerMadisonReach` remains canonical for movement, water/depth/current/habitat/fish/cast queries.
- Session seed may vary fish/session behavior only, not terrain/channel geometry.
- Use documented public data only for shipped terrain/geometry. No Google imagery/elevation/traced geometry/textures in the asset pipeline.
- Runtime debug `print()` calls must be guarded with `OS.is_debug_build()`.
- Do not commit unless explicitly requested.

Baseline validation gate for any code-changing agent:

```bash
cd /mnt/LargeNVMe/Projects/GitHub/personal/flyfishinggame
godot4 --headless --path . --scene res://scenes/RiverWorld3D.tscn --quit
godot4 --headless --path . --quit
git diff --check
```

Agents touching casting/drift/fish loops also run:

```bash
godot4 --headless --path . --script tests/casting_loop_modes_check.gd
godot4 --headless --path . --script tests/casting_loop_check.gd
```

---

## Phase A: Profiling and quick-win optimizations

Purpose: reduce startup/runtime cost before full streaming. These tasks are smaller, safer, and remain useful after streaming exists.

Recommended order:
1. A1 profiling probe/stage timing
2. A2 primitive mesh caching
3. A3 MultiMesh vegetation/tree batching
4. A4 cast-line rebuild throttling
5. A5 lower-frequency update loops
6. A7 effect pooling
7. A6 runtime quality settings

### Agent A1: Load/runtime profiling probe

Owns:
- `tests/river_load_profile.gd`
- `scripts/river/river_3d_builder.gd`
- optionally `scripts/river/river_world_3d.gd`

Tasks:
- Add reproducible load-profile probe that forces visual build under headless via `builder.force_headless_build = true`.
- Time total build and key builder stages.
- Add builder debug flag such as `profile_build`.
- Count generated children, `MeshInstance3D`, `MultiMeshInstance3D`, surfaces, and rough vertex counts where accessible.
- Keep logs debug-only/explicit-probe-only.

Validation:
```bash
godot4 --headless --path . --script tests/river_load_profile.gd
godot4 --headless --path . --scene res://scenes/RiverWorld3D.tscn --quit
git diff --check
```

### Agent A2: Primitive mesh/resource caching

Owns:
- `scripts/river/river_3d_builder.gd`

Tasks:
- Cache/reuse primitive meshes for boulders, driftwood/logs, cottonwood trunks/crowns, willows, reeds/grasses where compatible.
- Preserve current visual appearance and transforms.
- Avoid changing `LowerMadisonReach` or gameplay semantics.

Depends on: A1 preferred for before/after timing.

Validation:
```bash
godot4 --headless --path . --script tests/river_load_profile.gd
godot4 --headless --path . --scene res://scenes/RiverWorld3D.tscn --quit
git diff --check
```

### Agent A3: MultiMesh vegetation/tree batching

Owns:
- `scripts/river/river_3d_builder.gd`

Tasks:
- Convert non-interactive repeated vegetation/tree geometry to `MultiMeshInstance3D` batches where safe.
- Target willow clusters, cottonwood crowns/trunks, reeds/grasses, and possibly cobbles/boulders.
- Use one multimesh per compatible mesh/material group.
- Preserve deterministic placement.

Depends on: A1; coordinate with A2 shared mesh cache.

Validation:
```bash
godot4 --headless --path . --script tests/river_load_profile.gd
godot4 --headless --path . --scene res://scenes/RiverWorld3D.tscn --quit
git diff --check
```

### Agent A4: Cast-line rebuild throttling

Owns:
- `scripts/river/river_world_3d.gd`

Tasks:
- Avoid rebuilding `ImmediateMesh` line/leader every frame when origin/target/current have not changed meaningfully.
- Cache last cast-line origin/target/state.
- Rebuild only when rod tip/fly target crosses threshold, cast state changes, or visuals are invalidated.
- Preserve rod-attached fly line and leader ending at the dry fly.

Validation:
```bash
godot4 --headless --path . --script tests/casting_loop_modes_check.gd
godot4 --headless --path . --script tests/casting_loop_check.gd
godot4 --headless --path . --scene res://scenes/RiverWorld3D.tscn --quit
git diff --check
```

### Agent A5: Lower-frequency update loops

Owns:
- `scripts/river/river_world_3d.gd`

Tasks:
- Move non-critical updates off every-frame cadence.
- Suggested cadence:
  - every frame: player, active dry-fly drift, responsive hookset/take timing, active cast line if changing
  - 10-20 Hz: fish AI, foam, surface rise animation, bird flock
  - 2-5 Hz: HUD/debug string refresh
  - event/time-change: lighting if time advances slowly
- Preserve cast/drift/hookset responsiveness.

Validation:
```bash
godot4 --headless --path . --script tests/casting_loop_modes_check.gd
godot4 --headless --path . --script tests/casting_loop_check.gd
godot4 --headless --path . --scene res://scenes/RiverWorld3D.tscn --quit
git diff --check
```

### Agent A6: Runtime quality settings

Owns:
- `scripts/river/river_world_3d.gd`
- `scripts/river/river_3d_builder.gd`
- optionally `scenes/RiverWorld3D.tscn` for exported defaults

Tasks:
- Add simple quality knobs for ambience count/rates, bird/foam/rise density, vegetation density, and optional line/effect detail.
- Default should preserve current visual target or use a conservative optimized profile.
- Quality affects rendering/ambience, not canonical reach geometry.

Validation:
```bash
godot4 --headless --path . --scene res://scenes/RiverWorld3D.tscn --quit
godot4 --headless --path . --quit
git diff --check
```

### Agent A7: Effect pooling

Owns:
- `scripts/river/river_world_3d.gd`

Tasks:
- Pool reusable nodes/meshes for surface rise rings and foam flecks.
- Hide/reuse inactive effects instead of repeated `new()`/`queue_free()` during normal play.
- Keep fish-take rise cues intact.

Validation:
```bash
godot4 --headless --path . --script tests/casting_loop_modes_check.gd
godot4 --headless --path . --script tests/casting_loop_check.gd
godot4 --headless --path . --scene res://scenes/RiverWorld3D.tscn --quit
git diff --check
```

---

## Phase B: River segment architecture and runtime streaming

Purpose: stream render-heavy longitudinal river segments around the player while preserving full-reach gameplay queries.

Recommended order:
1. B1 reach segment helpers/test
2. B2 builder range extraction
3. B3 streamer node
4. B4 RiverWorld3D integration
5. B5 segment-aware visual systems/determinism

### Agent B1: Reach segment metadata and test

Owns:
- `scripts/river/lower_madison_reach.gd`
- `tests/reach_segment_bounds_check.gd`

Tasks:
- Add helpers:
  - `segment_count(segment_length_m: float) -> int`
  - `segment_fraction_range(segment_index: int, segment_length_m: float, overlap_m: float = 0.0) -> Vector2`
  - `segment_index_for_world_pos(world_pos: Vector3, segment_length_m: float) -> int`
- Ensure ranges cover `[0.0, 1.0]`, overlap clamps safely, player start maps to a valid segment.
- Verify representative `sample()` outputs are unchanged.

Validation:
```bash
godot4 --headless --path . --script tests/reach_segment_bounds_check.gd
git diff --check
```

### Agent B2: Builder segment/range extraction

Owns:
- `scripts/river/river_3d_builder.gd`
- may update `tests/river_load_profile.gd`

Tasks:
- Add segment/range build entry point, e.g. `build_segment(...)` or equivalent.
- Keep existing `build(authored_reach, fish_seed)` working via full-range path.
- Refactor station/fraction loops to respect range and overlap.
- Filter render-heavy features by range.
- Do not change gameplay query semantics.

Depends on: B1.

Validation:
```bash
godot4 --headless --path . --script tests/river_load_profile.gd
godot4 --headless --path . --scene res://scenes/RiverWorld3D.tscn --quit
git diff --check
```

### Agent B3: Runtime river segment streamer

Owns:
- `scripts/river/river_segment_streamer.gd`

Tasks:
- Create streamer with constants:
  - `SEGMENT_LENGTH_M := 120.0`
  - `SEGMENT_OVERLAP_M := 8.0`
  - `ACTIVE_SEGMENT_RADIUS := 1`
  - `PREFETCH_SEGMENT_RADIUS := 2`
- API should include configure/update/load/unload/pin/unpin helpers.
- Keep state for loaded/loading/pinned segments and current center segment.
- Load center +/- active radius; retain/prefetch farther as appropriate.
- Unload only render segment nodes; canonical reach remains global.

Depends on: B1, B2.

Validation: run after B4 integration; optionally add a focused streamer probe.

### Agent B4: RiverWorld3D streamer integration

Owns:
- `scripts/river/river_world_3d.gd`
- optionally `scenes/RiverWorld3D.tscn`

Tasks:
- `_generate_river()` still creates one canonical `LowerMadisonReach`.
- Configure `RiverSegmentStreamer` after reach/builder/player are ready.
- Startup should load initial active segments around player instead of whole visual reach, unless a debug/full-build fallback is enabled.
- Movement/clamping/wading/cast target/drift continue using full reach queries.

Depends on: B1-B3.

Validation:
```bash
godot4 --headless --path . --scene res://scenes/RiverWorld3D.tscn --quit
godot4 --headless --path . --quit
git diff --check
```

### Agent B5: Segment-aware visuals, fish determinism, pinning

Owns:
- `scripts/river/river_3d_builder.gd`
- `scripts/river/river_world_3d.gd`

Tasks:
- Ensure structures, bars, cobbles, weed beds, trees, willows, insects, and fish visuals are filtered by segment.
- Fish occupancy must be deterministic by global hold ID + session seed, independent of segment load order.
- Pin segments for selected target, active dry-fly drift, pending take, hooked/landing fish.
- Ambient/living systems remain globally capped.

Depends on: B1-B4.

Validation:
```bash
godot4 --headless --path . --script tests/casting_loop_modes_check.gd
godot4 --headless --path . --script tests/casting_loop_check.gd
godot4 --headless --path . --scene res://scenes/RiverWorld3D.tscn --quit
git diff --check
```

Phase B full validation:
```bash
godot4 --headless --path . --script tests/reach_segment_bounds_check.gd
godot4 --headless --path . --script tests/river_load_profile.gd
godot4 --headless --path . --script tests/casting_loop_modes_check.gd
godot4 --headless --path . --script tests/casting_loop_check.gd
godot4 --headless --path . --scene res://scenes/RiverWorld3D.tscn --quit
godot4 --headless --path . --quit
git diff --check
```

---

## Phase C: Offline baking, threaded prefetch, public-data expansion

Purpose: avoid runtime static rebuilds, hide baked segment load costs, and prepare for a longer public-data Lower Madison replica.

Recommended order:
1. C4 public-data manifest/docs
2. C1 offline bake command
3. C2 baked manifest validation/loading
4. C3 threaded prefetch
5. C5 public reach generalization

### Agent C1: Offline segment baking

Owns:
- `tools/bake_river_segments.gd`
- `assets/3d/generated/lower_madison_segments/`
- `assets/3d/generated/lower_madison_segments/manifest.json`
- may modify `scripts/river/river_3d_builder.gd`

Tasks:
- Generate static segment scenes/resources for each segment range.
- Exclude session/dynamic state from baked content.
- Write bake manifest containing schema version, builder version, Godot version, segment config, segment paths, ranges, source hash, builder/config hash.
- Runtime must be able to detect manifest mismatch and fall back to procedural build.

Depends on: B1/B2; C4 preferred.

Validation:
```bash
godot4 --headless --path . --script tools/bake_river_segments.gd
godot4 --headless --path . --script tests/river_load_profile.gd
godot4 --headless --path . --scene res://scenes/RiverWorld3D.tscn --quit
git diff --check
```

### Agent C2: Runtime manifest validation and baked segment loading

Owns:
- `scripts/river/river_segment_streamer.gd`
- optionally `scripts/river/river_world_3d.gd`

Tasks:
- Load and validate generated segment manifest.
- Prefer baked segment scenes when schema/config/source hashes match.
- Fall back to procedural segment build with one clear warning if missing/invalid.
- Unload only segment-owned static nodes.

Depends on: B3/B4, C1, C4.

Validation:
```bash
godot4 --headless --path . --script tools/bake_river_segments.gd
godot4 --headless --path . --script tests/reach_segment_bounds_check.gd
godot4 --headless --path . --script tests/river_load_profile.gd
godot4 --headless --path . --scene res://scenes/RiverWorld3D.tscn --quit
godot4 --headless --path . --quit
git diff --check
```

### Agent C3: Threaded prefetch

Owns:
- `scripts/river/river_segment_streamer.gd`

Tasks:
- Use `ResourceLoader.load_threaded_request(path)` for prefetch-radius baked segments.
- Poll status and instantiate only if segment is still wanted.
- Avoid stale prefetch instantiation.
- Use synchronous fallback only for active-radius emergency.
- Keep deterministic load/unload before adding fade/pop-in polish.

Depends on: C2.

Validation:
```bash
godot4 --headless --path . --script tools/bake_river_segments.gd
godot4 --headless --path . --script tests/river_load_profile.gd
godot4 --headless --path . --script tests/casting_loop_modes_check.gd
godot4 --headless --path . --script tests/casting_loop_check.gd
godot4 --headless --path . --scene res://scenes/RiverWorld3D.tscn --quit
git diff --check
```

Manual validation:
- Run scene normally.
- Walk/wade upstream and downstream across segment boundaries.
- Watch for stutter, missing terrain/water, duplicate props at overlaps, stale pop-in, and fish/cast unload crashes.

### Agent C4: Public-data manifest and docs

Owns:
- `assets/3d/geodata/lower_madison_manifest.json`
- `docs/LOWER_MADISON_REACH.md`

Tasks:
- Record NHD/3DEP source metadata, local file paths, hashes, projection/origin assumptions, compression factors, segment defaults, license/source acknowledgements.
- Explicitly document no Google imagery/elevation/traced geometry/textures in shipped asset pipeline.
- Keep docs and manifest in agreement.

Validation:
```bash
python3 -m json.tool assets/3d/geodata/lower_madison_manifest.json >/dev/null
sha256sum \
  assets/3d/geodata/lower_madison_nhd_flowline.geojson \
  assets/3d/geodata/lower_madison_nhd_area.geojson \
  assets/3d/geodata/lower_madison_3dep_128.tif \
  assets/3d/geodata/lower_madison_3dep_samples.json
git diff --check
```

### Agent C5: Public reach generalization / compatibility wrapper

Owns:
- `scripts/river/lower_madison_reach.gd`
- possibly `scripts/river/public_river_reach.gd`
- reach regression tests, e.g. `tests/lower_madison_reach_regression_check.gd`

Tasks:
- Preserve `LowerMadisonReach` as compatibility class used by game code.
- Optionally move reusable source loading/projection/station building into `PublicRiverReach`.
- Preserve current Black's Ford authored anchors and sample outputs.
- Add regression checks for start position, station count, bounds, water/land classification, depth/current/habitat, hold behavior.
- Do not actually expand upstream/downstream geometry in this task unless separately assigned.

Depends on: C4 and strong regression baseline. Best done after C1-C3.

Validation:
```bash
godot4 --headless --path . --script tests/reach_segment_bounds_check.gd
godot4 --headless --path . --script tests/lower_madison_reach_regression_check.gd
godot4 --headless --path . --script tests/casting_loop_modes_check.gd
godot4 --headless --path . --script tests/casting_loop_check.gd
godot4 --headless --path . --scene res://scenes/RiverWorld3D.tscn --quit
git diff --check
```

---

## Parallelization guidance

Safe parallel groups:

- First wave:
  - A1 alone or first.
  - C4 can run independently because it is docs/manifest only.

- Second wave after A1:
  - A2 and A4 can run in parallel.
  - A3 should coordinate with A2 if both touch mesh caching/batching in `river_3d_builder.gd`.
  - A5 should coordinate with A4 because both touch `_process()`/cast visuals in `river_world_3d.gd`.

- Phase B should mostly be sequential:
  - B1 -> B2 -> B3 -> B4 -> B5.
  - B1 can start while Phase A runs.

- Phase C depends on Phase B:
  - C4 can run early.
  - C1 waits for B2.
  - C2/C3 wait for B3/B4 and C1.
  - C5 waits for C4 and regression tests.

Avoid parallel edits to the same file unless one agent is strictly docs/tests and the other is code.

---

## Controller/review protocol

For each agent implementation task:
1. Dispatch a fresh implementer agent with the specific section above.
2. Run the task-specific validation gate.
3. Dispatch spec-compliance review against the task section.
4. Dispatch code-quality review after spec passes.
5. Only then mark task complete and proceed.

For Phase A/B/C completion:
- Run the phase full validation suite.
- Run baseline smoke tests.
- Check `git diff --check`.
- Summarize changed files and any known existing warnings separately from new failures.
