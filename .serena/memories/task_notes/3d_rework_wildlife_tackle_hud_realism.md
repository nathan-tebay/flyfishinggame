# Modeled Wildlife, Adult Insects, Rod, and Tackle HUD

On 2026-05-27 user requested more realism: rainbow trout, brown trout, whitefish models; adult mayflies/caddis; HUD for selected fly/casting; full-length fly rod with guides and line.

## Implementation
- Added `scripts/models/fish_model_3d.gd`: articulated procedural 3D fish with tapered hull, paired/vertical/tail fins, eyes and species-specific details: Rainbow Trout rose flank stripe; Brown Trout dark/red spots; Mountain Whitefish silver body and higher dorsal profile.
- `scripts/river/river_3d_builder.gd` now creates realistic-size seeded fish at authored holds instead of generic fish shadows and places six centimeter-scale adult surface insects.
- Added `scripts/models/adult_insect_3d.gd`: adult mayfly (upright wings + three tails) and adult caddis (tent wings + antennae), with small hovering/wing motion; selected cast landing uses matching adult imitation model.
- Added fish/insect materials under `assets/3d/materials/fish_*` and `insect_*`; removed use of `fish_shadow.tres` placeholder.
- Expanded `scripts/autoloads/hatch_manager.gd` profiles to include adult mayfly and adult caddis surface activity, with mayfly adult spinner-fall semantics instead of caddis spinner stage.
- Added `scripts/player/fly_rod_3d.gd`: 2.74 m rod model with cork grip, tapered graphite blank, fly reel/backing, nine guides, threaded visible line, tip-origin casting, and cast flex. New materials: `rod_cork.tres`, `rod_metal.tres`, `rod_reel_line.tres`.
- Updated `FirstPersonAngler` to originate casts from modeled rod tip, play rod cast motion, and emit fly-change action; `InputSetup` binds `Q` / right shoulder to `cycle_fly`.
- Added tackle HUD panel in `RiverWorld3D.tscn` and world state: shows selected pattern and adult phase, active/sparse adult surface life, and `READY TO CAST` / `CASTING • LOOP OUT` / `DRIFTING • SURFACE`; patterns are Blue-Winged Olive Dun (adult mayfly) and Elk Hair Caddis (adult caddis).
- Updated current README/CLAUDE/assets documentation and Session 8 transcript/planning notes.

## Validation
- `godot4 --headless --path . --scene res://scenes/RiverWorld3D.tscn --quit` passes cleanly.
- Reach query passes: fixed length 509.31, dry spawn/bar, seven habitats.
- River no-fold test passes: `folded_water=0 folded_bank=0 water_min_area=38.673 bank_min_area=21.844`.
- Forced visual model construction outputs: `fish=[HoldingMountainWhitefish, HoldingBrownTrout, HoldingRainbowTrout] adult_insects=6 rod_parts=19 rod_length=2.74`; forced dummy rendering is inspected only for construction and may have normal dummy teardown noise.
- HUD interaction test: starts BWO adult mayfly, cycles to Elk Hair Caddis adult, cast state becomes `CASTING • LOOP OUT` with `AdultCaddis` landing model.
- `godot4 --headless --editor --path . --quit-after 5` has only previously known third-party GDSQLite shutdown warning (`Can't close database if connection is not open!`).
- `git diff --check` passes.