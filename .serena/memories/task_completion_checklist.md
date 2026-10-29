# Task Completion Checklist — Current

When finishing a coding task in `flyfishinggame`:

1. Do **not** commit or tag unless user explicitly asks.
2. Keep changes surgical; do not revive removed 2D runtime unless user explicitly asks.
3. Run `git diff --check` after file edits.
4. For runtime/script changes, run at least one focused Godot headless check, usually:
   - `godot4 --headless --path . --scene res://scenes/RiverWorld3D.tscn --quit`
   - `godot4 --headless --path . --scene res://scenes/SessionConfig.tscn --quit` when startup/config changes.
5. For reach/mesh/water changes, also run focused validation scripts if available or recreate small `/tmp` checks for:
   - dry spawn / exposed bar classification
   - required habitat zones
   - water/bank fold checks
   - upward normals / no water under dry bars
6. For visual realism changes, headless checks are not enough. State that interactive GPU review or user screenshot is still required.
7. Wrap all release-path `print()` calls in `if OS.is_debug_build():`.
8. No inline conditionals with more than one condition; prefer guard clauses.
9. Treat third-party GDSQLite editor shutdown warning `Can't close database if connection is not open!` as known noise if no new errors appear.
10. Do not create transcript/blog planning docs for routine tasks. Create them only for major planning sessions or explicit user request.