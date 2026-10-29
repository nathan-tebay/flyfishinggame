# Code Style & Conventions — Current

## Language / Engine
- GDScript for Godot 4.3.
- Current runtime is 3D-only first-person Lower Madison reach.

## Naming
- `snake_case` for variables, functions, signals, file names.
- `PascalCase` for class names and node names.
- `UPPER_SNAKE_CASE` for constants.
- Private members prefixed with `_`.

## Structure
- No docstrings; prefer clear names.
- Comments only for non-obvious WHY: constraints, source-data quirks, renderer workarounds.
- Guard clauses over deep nesting.
- Avoid inline conditionals with more than one condition.
- Follow DRY/SOLID, but keep changes surgical and avoid speculative abstractions.

## Debug Prints
- Wrap release-path `print()` calls:
  `if OS.is_debug_build():`

## Current 3D Design Constraints
- `LowerMadisonReach` owns authored reach geometry, water/land classification, habitats, current vectors/strength, holds, fixed props, and dry spawn logic.
- `River3DBuilder` builds visible 3D geometry/models from `LowerMadisonReach`; do not reintroduce seeded 2D tile/RiverData runtime as visible scene source.
- `RiverWorld3D` owns world orchestration, environment, HUD, casting/drift state, and reach queries.
- `FirstPersonAngler` + `FlyRod3D` own movement/camera/rod-tip cast origin/rod animation.
- Water realism should come from the `river_water` shader and bounded water mesh, not separate bright rectangular foam decal meshes.
- Exposed bars/shorelines must be grounded into bed/wet aprons; no water rendering under dry bar footprints.
- Fish/insects should use procedural 3D models, not placeholder flat shadows, unless making an explicit debug visualization.