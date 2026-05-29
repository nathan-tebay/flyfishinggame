# Optimized Agent Thinking-Level Plan: Lower Madison Performance + Streaming

> Source work split: `docs/plans/2026-05-28-agent-work-split-loadtime-streaming.md`

Goal: reduce cost and coordination risk by assigning each task to the cheapest capable agent tier, while reserving deep reasoning for high-risk architecture and gameplay-determinism work.

---

## Thinking tiers

### Tier S — low-thinking / execution agent

Use for docs, manifests, simple tests, localized constants, and low-risk mechanical changes.

Expected behavior:
- Follow exact instructions.
- Avoid architecture changes.
- Touch only assigned files.
- Run narrow validation.

Review level:
- Lightweight coordinator review.
- No separate deep code review unless validation fails.

Typical token budget per task: ~18k base.

### Tier M — medium-thinking / focused implementer

Use for contained code changes in one subsystem with clear tests.

Expected behavior:
- Understand local file context.
- Make small refactors safely.
- Add/adjust targeted tests.
- Avoid cross-system design changes.

Review level:
- One spec/quality review, medium depth.

Typical token budget per task: ~32k base.

### Tier H — high-thinking / senior subsystem agent

Use for cross-file performance changes, batching, update-loop changes, or runtime systems that can subtly affect gameplay.

Expected behavior:
- Inspect adjacent code before editing.
- Preserve behavior and deterministic placement.
- Add probes/guards when headless tests do not exercise visual code.
- Run broader validation.

Review level:
- Spec review + quality review can be combined into one high-thinking reviewer if context is tight.
- Re-review required after important fixes.

Typical token budget per task: ~60k base.

### Tier X — deep-thinking / architecture agent

Use for segment architecture, streamer integration, fish determinism/pinning, baking/cache validation, and public reach generalization.

Expected behavior:
- Produce a short implementation design before code.
- Identify invariants and failure modes.
- Add regression tests/probes before risky refactors.
- Preserve current Black's Ford behavior exactly unless a test-approved migration says otherwise.

Review level:
- Mandatory two-gate review:
  1. Spec/invariant review.
  2. Integration/quality review.
- Final coordinator validation before next dependent task starts.

Typical token budget per task: ~100k base.

---

## Optimized assignment table

| Task | Tier | Reason | Parallelism |
| --- | --- | --- | --- |
| A1 profiling probe/stage timing | M | contained instrumentation + test/probe | first wave |
| A2 primitive mesh/resource caching | M | local builder optimization | after A1; parallel with A4/C4/B1 |
| A3 MultiMesh vegetation/tree batching | H | batching can affect visuals/node ownership | after A1/A2 preferred |
| A4 cast-line rebuild throttling | M | contained runtime allocation optimization, existing tests | after A1; parallel with A2/C4/B1 |
| A5 lower-frequency update loops | H | can break fish/cast responsiveness subtly | after A4 preferred |
| A6 runtime quality settings | S | mostly constants/config knobs after known optimizations | late Phase A |
| A7 effect pooling | M | localized but must preserve fish-take visuals | after A5 preferred |
| B1 reach segment metadata + test | M | contained API + deterministic test | first wave, independent of A |
| B2 builder segment/range extraction | X | core architecture; high risk of seams/regressions | after B1 + A1 |
| B3 runtime river segment streamer | H | new system with clear API; lower risk before integration | after B2 |
| B4 RiverWorld3D streamer integration | X | startup/runtime architecture and canonical reach invariants | after B3 |
| B5 segment-aware visuals/fish determinism/pinning | X | highest gameplay-determinism risk | after B4 |
| C1 offline segment baking | X | generated resources + manifest/hash correctness | after B2 + C4 |
| C2 runtime manifest validation/baked loading | H | streamer load path + fallback logic | after C1 + B4 |
| C3 threaded prefetch | H | async loading race/stale-load risk | after C2 |
| C4 public-data manifest/docs | S | docs/JSON/hash task; independent | first wave |
| C5 public reach generalization/wrapper | X | behavior-preserving data architecture refactor | last, after regression baseline |

---

## Optimized execution waves

### Wave 0 — cheap setup and measurement

Run these first:

1. A1 — Tier M: profiling probe/stage timing.
2. B1 — Tier M: segment helpers/test.
3. C4 — Tier S: public-data manifest/docs.

Why:
- A1 gives measurement before optimizing.
- B1 unlocks later segment work without touching rendering.
- C4 is independent and cheap, and it supports later bake manifests.

Concurrency:
- A1, B1, and C4 can run in parallel because they mostly touch different files.
- If avoiding all conflicts, run A1 first, then B1/C4 parallel.

Validation gate after Wave 0:

```bash
godot4 --headless --path . --script tests/river_load_profile.gd
godot4 --headless --path . --script tests/reach_segment_bounds_check.gd
python3 -m json.tool assets/3d/geodata/lower_madison_manifest.json >/dev/null
godot4 --headless --path . --scene res://scenes/RiverWorld3D.tscn --quit
git diff --check
```

### Wave 1 — high ROI quick wins

Run after A1:

1. A2 — Tier M: primitive mesh/resource caching.
2. A4 — Tier M: cast-line rebuild throttling.

Concurrency:
- Safe in parallel: A2 touches `river_3d_builder.gd`; A4 touches `river_world_3d.gd`.

Validation gate after Wave 1:

```bash
godot4 --headless --path . --script tests/river_load_profile.gd
godot4 --headless --path . --script tests/casting_loop_modes_check.gd
godot4 --headless --path . --script tests/casting_loop_check.gd
godot4 --headless --path . --scene res://scenes/RiverWorld3D.tscn --quit
git diff --check
```

### Wave 2 — heavier quick wins

Run after Wave 1:

1. A3 — Tier H: MultiMesh vegetation/tree batching.
2. A5 — Tier H: lower-frequency update loops.
3. A7 — Tier M: effect pooling, after A5 or coordinated with it.
4. A6 — Tier S: quality settings, last after actual optimization knobs are known.

Concurrency:
- A3 and A5 can run in parallel if the coordinator enforces file boundaries.
- A7 should not run concurrently with A5 unless carefully scoped because both touch ambient update/effect code.
- A6 should run after A3/A5/A7 to avoid inventing knobs that do not map to implemented systems.

Validation gate after Wave 2:

```bash
godot4 --headless --path . --script tests/river_load_profile.gd
godot4 --headless --path . --script tests/casting_loop_modes_check.gd
godot4 --headless --path . --script tests/casting_loop_check.gd
godot4 --headless --path . --scene res://scenes/RiverWorld3D.tscn --quit
godot4 --headless --path . --quit
git diff --check
```

### Wave 3 — segment architecture foundation

Run mostly sequentially:

1. B2 — Tier X: builder segment/range extraction.
2. B3 — Tier H: runtime river segment streamer.
3. B4 — Tier X: RiverWorld3D streamer integration.

Concurrency:
- Do not parallelize B2/B3/B4 implementation unless B3 is initially API-only against an agreed stub.
- B2 should finish and pass profile/smoke validation before B3/B4 rely on it.

Validation gate after Wave 3:

```bash
godot4 --headless --path . --script tests/reach_segment_bounds_check.gd
godot4 --headless --path . --script tests/river_load_profile.gd
godot4 --headless --path . --scene res://scenes/RiverWorld3D.tscn --quit
godot4 --headless --path . --quit
git diff --check
```

### Wave 4 — deterministic streaming gameplay

Run after Wave 3:

1. B5 — Tier X: segment-aware visuals, fish determinism, interaction pinning.

Why single-agent:
- This task crosses builder, runtime, fish state, cast target, drift, and unload behavior.
- Splitting it prematurely risks load-order-dependent bugs.

Validation gate after Wave 4:

```bash
godot4 --headless --path . --script tests/reach_segment_bounds_check.gd
godot4 --headless --path . --script tests/river_load_profile.gd
godot4 --headless --path . --script tests/casting_loop_modes_check.gd
godot4 --headless --path . --script tests/casting_loop_check.gd
godot4 --headless --path . --scene res://scenes/RiverWorld3D.tscn --quit
godot4 --headless --path . --quit
git diff --check
```

### Wave 5 — baking/cache/prefetch

Run after B2-B4, preferably after B5 if static/dynamic ownership is still changing:

1. C1 — Tier X: offline segment baking.
2. C2 — Tier H: runtime manifest validation and baked loading.
3. C3 — Tier H: threaded prefetch.

Concurrency:
- C1 and C2 should not be parallel unless C2 starts with manifest-interface scaffolding only.
- C3 waits for C2.

Validation gate after Wave 5:

```bash
godot4 --headless --path . --script tools/bake_river_segments.gd
godot4 --headless --path . --script tests/river_load_profile.gd
godot4 --headless --path . --script tests/reach_segment_bounds_check.gd
godot4 --headless --path . --script tests/casting_loop_modes_check.gd
godot4 --headless --path . --script tests/casting_loop_check.gd
godot4 --headless --path . --scene res://scenes/RiverWorld3D.tscn --quit
godot4 --headless --path . --quit
git diff --check
```

### Wave 6 — future public-reach architecture

Run last:

1. C5 — Tier X: public reach generalization / compatibility wrapper.

Why last:
- This is not needed for immediate load-time wins.
- It is a behavior-preservation refactor with broad blast radius.
- It needs regression baselines from B/C work.

Validation gate:

```bash
godot4 --headless --path . --script tests/lower_madison_reach_regression_check.gd
godot4 --headless --path . --script tests/reach_segment_bounds_check.gd
godot4 --headless --path . --script tests/casting_loop_modes_check.gd
godot4 --headless --path . --script tests/casting_loop_check.gd
godot4 --headless --path . --scene res://scenes/RiverWorld3D.tscn --quit
git diff --check
```

---

## Review strategy by tier

### Tier S review

Use coordinator review only:
- Read diff.
- Run exact validation.
- Check no out-of-scope files.

No separate review agent unless validation fails.

### Tier M review

Use one medium reviewer:
- Verify task spec.
- Verify code quality.
- Verify tests are meaningful.

If reviewer finds issues, send fix back to a Tier M implementer and rerun only targeted validation plus baseline smoke.

### Tier H review

Use one high-thinking reviewer or two compact reviews:
- Invariant/spec review.
- Behavior/performance review.

Review must inspect adjacent systems, not just changed lines.

### Tier X review

Mandatory two-stage review:
1. Deep spec/invariant reviewer:
   - canonical reach invariant
   - deterministic seed behavior
   - no 2D/runtime regression
   - no source-data/legal regression
2. Deep integration/quality reviewer:
   - architecture boundaries
   - load/unload failure modes
   - tests/probes cover intended path
   - no hidden global state/load-order coupling

Do not proceed to dependent tasks until both pass.

---

## Token-optimized MVP

If the goal is maximum near-term performance per token, do only:

1. A1 — M: profiling.
2. A2 — M: primitive mesh caching.
3. A4 — M: cast-line throttling.
4. B1 — M: segment metadata/test.
5. C4 — S: public-data manifest/docs.

Estimated budget:
- Base: ~146k tokens.
- With 30% buffer: ~190k tokens.

Why this slice:
- Provides measurement.
- Delivers likely performance wins.
- Prepares segment/bake groundwork.
- Avoids highest-risk architecture until profiling confirms need.

---

## Token estimate for optimized full plan

Using mixed tiers and right-sized reviews:

| Tier | Count | Base per task | Subtotal |
| --- | ---: | ---: | ---: |
| S | 2 | ~18k | ~36k |
| M | 5 | ~32k | ~160k |
| H | 5 | ~60k | ~300k |
| X | 5 | ~100k | ~500k |

Base optimized total: ~996k tokens.

With buffers:
- +15%: ~1.15M
- +30%: ~1.29M
- +50%: ~1.49M

Phase estimates:
- Phase A: ~266k base, ~346k with 30% buffer.
- Phase B: ~392k base, ~510k with 30% buffer.
- Phase C: ~338k base, ~439k with 30% buffer.
- Recommended MVP slice: ~146k base, ~190k with 30% buffer.
- Next architecture slice B2+B3+B4: ~260k base, ~338k with 30% buffer.

---

## Cost/risk cuts from the original split

1. Do not use deep agents for docs/config/probes unless validation fails.
2. Combine spec + quality review for Tier M/H tasks when the diff is small.
3. Preserve mandatory two-stage review only for Tier X tasks.
4. Delay A6 quality settings until actual knobs exist.
5. Delay C5 public reach generalization until after streaming/baking and regression tests.
6. Avoid implementing C1-C3 until B2-B4 prove the segment architecture.
7. Do not parallelize same-file agents unless one is docs/tests only.
8. Always run A1 profiling before claiming performance wins.

---

## Final recommended execution order

1. Wave 0: A1(M), B1(M), C4(S)
2. Wave 1: A2(M), A4(M)
3. Wave 2: A3(H), A5(H), A7(M), A6(S)
4. Wave 3: B2(X), B3(H), B4(X)
5. Wave 4: B5(X)
6. Wave 5: C1(X), C2(H), C3(H)
7. Wave 6: C5(X)

Stop points:
- After Wave 1: good cheap performance checkpoint.
- After Wave 2: optimized current single-reach runtime.
- After Wave 4: runtime streaming architecture complete.
- After Wave 5: baked streaming chunks complete.
- After Wave 6: ready for longer public-data river expansion.
