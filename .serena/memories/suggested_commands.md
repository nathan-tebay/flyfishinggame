# Suggested Commands

All commands go through `run.sh`:

```bash
./run.sh setup            # Download godot-sqlite plugin (first-time setup)
./run.sh run              # Run the game (native Godot, needs GPU)
./run.sh editor           # Open Godot editor (native)
./run.sh export linux     # Export Linux build via Podman container
./run.sh export windows   # Export Windows build via Podman container
./run.sh export all       # Export all platforms
./run.sh shell            # Interactive shell in export container
./run.sh clean            # Remove builds/
```

**Native (run/editor):** requires Godot 4.3 on PATH (`godot4`, `godot`, or `Godot`).
**Container (export/shell):** requires Podman. Uses `barichello/godot-ci:4.3`.

## No linting/formatting/testing commands
GDScript has no standard linter/formatter in use. No automated test suite.
Testing is done by running the game and observing behavior.

## Key versions
- `GODOT_VERSION` = 4.3
- `GODOT_SQLITE_VERSION` = 4.3
