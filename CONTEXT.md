# CONTEXT — Domain & Architecture Glossary

Shared vocabulary for the Lower Madison 3D fly-fishing runtime. Architecture
reviews use these names so seams and modules don't get re-litigated each pass.

## Architecture vocabulary (how we talk about structure)

- **Module** — anything with an interface and an implementation.
- **Interface** — everything a caller must know to use a module: types, invariants,
  ordering, error modes. Not just the function signature.
- **Seam** — where an interface lives; a place behaviour can be swapped without
  editing in place.
- **Deep / shallow** — deep = a lot of behaviour behind a small interface; shallow =
  interface nearly as wide as the implementation.
- **`river_world_3d.gd` is the orchestrator, not a dumping ground.** It owns
  world/reach coupling, applies outcomes, and wires nodes. Gameplay rules that can
  be decided from inputs alone belong in their own deep, headless-testable module.
  The guiding principle from the 2026-06-02 review: **pure modules decide; the
  world owns the coupling and applies the result.**

## Casting

- **CastingStateManager** — the single seam for a cast. Owns cast phase, line load,
  stroke quality, false-cast count, and the *decision* to deliver. Drives
  `LoopPhysicsEngine` for loop geometry. Does **not** touch `reach` or `builder`.
- **CastInput** — the per-frame input the casting seam consumes: rod elevation,
  lateral, mouse dy, current line length, whether the fly is already on water.
- **CastOutcome** — what the seam emits on delivery: `{style, line_load,
  loop_quality}`. The world resolves landing/drift/spook/slack from it (pending
  slack is derived world-side from line load + target distance, not by the module).
- **LoopPhysicsEngine** — pure loop-geometry model (bend, speed, width, position);
  visual feed only, already unit-tested headless.
- **Line load** — proportion of target distance the stroke has loaded (0–1.2);
  gates delivery and drives where the fly lands.
- **Loop quality** — `tight / adequate / tailing / wide`, scored from how close a
  stroke reversal was to the loop straightening.

## Drift & fish

- **DriftSimulation** — pure stepper for the dry fly on the water.
  `step(dt, flow_at_fly) -> DriftSample`. The world supplies flow (`reach.sample`),
  owns the fly marker and HUD readout.
- **DriftSample** — `{position, drag, flow, finished, quality}` emitted each tick;
  consumed by `TroutBehaviour`.
- **TroutBehaviour** — pure, stateless evaluator of fish reaction.
  `evaluate_take(fish, drift_sample, affinity) -> Verdict`, plus `on_disturbance`
  and `tick`. The world owns the fish state and applies verdicts.
- **Verdict** — the take/spook/ignore decision (with timing) a fish evaluator
  returns. The world mutates fish state from it.
- **Affinity** — fly-vs-fish match score, computed by the world from
  `HatchManager` + selected fly, passed into `TroutBehaviour` as a number.

## World & player

- **AmbientEffects** — one module behind `update(dt, time_of_day, density)` that
  owns surface rises, foam flecks, the bird flock, living light, and their pools.
  No gameplay coupling.
- **WaterQuery** — the (currently informal) seam the angler uses to ask the world
  about water: `speed_at`, `clamp`, `surface_h`. Today these are `has_method`
  duck-calls; formalise into a typed interface only once a second adapter (e.g. a
  flat-water test stub for headless angler-movement tests) is real.
