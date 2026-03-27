# Game Design Document — Fly Fishing Game
*Working Title: TBD*

---

## Overview

A 16-bit style 2D fly fishing game set on the Madison River, Montana. Grounded in realistic fly fishing principles — hatch-driven fish behavior, edge feeding philosophy, and skill-based casting. Targets casual players through simulation-level anglers via configurable difficulty.

**Engine:** Godot 4 (GDScript)
**Target Platforms:** Linux, Windows (initial), Android/iOS (future)
**Resolution:** Up to 1440p
**PoC Scope:** Mother's Day Caddis hatch, single river section

---

## Visual Style

- 16-bit pixel art, referencing Super Black Bass (SNES)
- Side-scrolling cross-section view of the river showing depth layers
- Angler visible on bank or wading in river
- Time-of-day lighting affects shadow projection and atmosphere

### Display Layout

```
┌────────────────────────────────────────────────┐
│  [Sky / Time of Day lighting strip]            │
│────────────────────────────────────────────────│
│  [Bank / Angler]                               │
│  [Water surface — dry flies, rises, insects]   │
│  [Mid-depth — emergers, nymphs drifting]       │
│  [Bottom — deep pockets, holding fish]         │
│────────────────────────────────────────────────│
│  [Rod arc + fly line display] [Cast Meter] [Fly Selector] │
└────────────────────────────────────────────────┘
```

---

## Core Systems

### 1. Camera & Scouting

- Side-scrolling view, free pan up to **3 screen widths** from angler position
- Player scouts for feeding fish before committing to an approach
- Camera only pans freely during scouting — follows angler during movement
- Fish visible at depth-appropriate opacity (see Fish Visibility)

### 2. Angler Movement

Player moves along river bank or wades into the river. Each mode has distinct spook implications.

| Mode | Primary Spook Risk | Notes |
|---|---|---|
| Bank fishing | Shadow projection | Directional — sun angle matters |
| Wading | Vibration/water displacement | Increases with movement speed; standing still reduces it significantly |

- Moving into water eliminates shadow risk but introduces vibration
- Wading upstream = approaching fish from behind (blind spot) = lower spook risk
- Wading downstream = approaching fish head-on = higher spook risk
- Standing still in water drops vibration to near zero — also enables net sampling

### 3. Fish Vision & Approach

Fish have a directional vision cone. Approach angle relative to the fish's facing direction (always upstream) determines spook distance.

```
				←←← upstream (fish facing direction)
   [BLIND SPOT] 🐟 [WIDE VISION CONE ~120° each side]
				←←← current flow
```

| Approach Direction | Vision Exposure | Spook Distance |
|---|---|---|
| Directly upstream (behind fish) | Blind spot | Minimum |
| Quartering upstream | Partial cone edge | Reduced |
| Broadside | Full cone | Standard radius |
| Quartering downstream | Full cone + movement | Increased |
| Directly downstream (head-on) | Full cone center | Maximum |

- Cone angle and blind spot size configurable per difficulty (Sim = narrower blind spot)
- Fast water fish have narrower focus cone — concentrating on food lane
- Larger fish have wider peripheral vision
- Wading vibration partially counteracts blind spot advantage — vibration is omnidirectional and does not respect the vision cone. Net effect still favors upstream approach but not as strongly as static bank approach from behind

### 4. Fish Visibility

Fish visibility scales with depth and lighting conditions.

| Water Type | Bright Lighting (Midday) | Low Lighting (Dawn/Dusk) | Night |
|---|---|---|---|
| Shallow | Clear ripple + silhouette | Ripple only | None |
| Deep | Strong silhouette | Faint silhouette | None |

- Deep water fish rendered at reduced opacity + desaturated, scaling with `depth × inverse(light_level)`
- Ripple particle effect triggers on fish movement in shallow water
- Midday = easy to spot fish, but fish less active at feeding edges
- Dawn/dusk = fish actively feeding but harder to locate — core scouting tension

### 5. Casting Mechanic

**Flow:**
1. Player scouts and selects target spot on river
2. Player feeds line out (right trigger / key) to desired length
3. Player initiates cast — false cast rhythm begins
4. Rod arc animates the line in the air — when line fully straightens = cue to change direction
5. Tight loops = good timing; wide or collapsed loops = poor timing
6. Player presses complete cast when happy with distance — shoots line, final presentation
7. Fly lands — accuracy and presentation quality determined by loop quality

**Rod arc as unified HUD — no separate line meter:**

| Rod arc state | Meaning |
|---|---|
| Line straightens fully | Change direction — backcast to forward or vice versa |
| Tight loop shape | Good timing — accurate presentation |
| Wide loop | Sloppy timing — reduced accuracy |
| Collapsed loop | Bad timing — line slap risk |
| Arc angle / depth | Indicates line length currently in air |

**Line management controls:**

| Input | Gamepad | Keyboard | Action |
|---|---|---|---|
| Feed line | Right trigger (hold) | Mapped key | Increases castable distance |
| Strip line | Left trigger (hold) | Mapped key | Reduces line — used during drift/retrieve |
| Complete cast | Face button (A/Cross) | Mapped key | Shoots line, final presentation |
| False cast direction | Right joystick rhythm | Mapped keys | Backcast / forward cast cycle |
| Mend upstream | Rod move upstream | Mouse move upstream | Corrects downstream drag during drift |
| Mend downstream | Rod move downstream | Mouse move downstream | Corrects upstream drag in slack water |

All controls fully remappable.

**Timing — distance-driven:**
- More line in air = slower rhythm (rod loads heavier) = more beats required
- Short cast = fast tight windows, fewer beats
- Overly ambitious line length = windows become punishing
- Rhythm scales continuously with line length

**Line drag & mending:**
- Current creates belly in line during drift → unnatural drag on fly → reduced take probability
- Mending upstream resets drag accumulation, extends natural drift window
- Mending downstream speeds fly in slack water pockets
- Mending costs rod position — cannot mend and be ready to strike simultaneously

**Cast quality → spook:**
- Perfect cast = no additional spook risk
- Sloppy loop = reduced accuracy, minor spook risk
- Collapsed loop / line slap = guaranteed Alert or Spooked on nearby fish

### 6. Fly Selection & Matching the Hatch

Fly inventory is unlimited. Available selections are filtered to species appropriate for the current season and active hatches.

**Fly matching — sliding scale:**

```
Exact Match → Close Match → Generic Attractor → Wrong Stage → Wrong Species
	↓               ↓               ↓                ↓              ↓
Highest take    Good take       Low take          Inspect +      Ignore or
probability     probability     probability        refuse         flee (Sim)
```

**Closeness scoring — weighted comparison of fly profile vs active insect profile:**

| Factor | Weight |
|---|---|
| Species match | High |
| Life stage (nymph/emerger/adult/spinner) | High |
| Size match | Medium |
| Color/profile match | Low |

**Rejection → intrusion memory:**

| Closeness | Fish Response | Intrusion Memory |
|---|---|---|
| Exact | Takes fly | None |
| Close | Takes or ignores | None |
| Generic attractor | Inspects, usually ignores | None |
| Wrong stage | Inspects, rejects, returns to hold | +0.5 (partial) |
| Wrong species | Ignores or flees (Sim) | +1 on Sim, none on Casual |

Two wrong-stage presentations = one full spook count. Large fish can be burned out by sloppy fly selection without a bad cast.

**PoC flies:**
- Elk Hair Caddis (dry fly) — surface presentation
- Caddis Pupa (wet/emerger) — subsurface drift

### 7. Hookset Mechanic

**Strike signals by fly type:**

| Fly Type | Visual Cue | Audio Cue |
|---|---|---|
| Dry fly | Fish rises, fly disappears, splash | Splash sound |
| Nymph/emerger | Floating ball strike indicator pauses or dips | Subtle tick |

- Strike indicator is a floating ball visible on the line during nymph drift
- Indicator position tracks current and mending — moves naturally with the drift

**Player action:** Pull rod back (button or stick pull) within the strike window.

**Hookset timing — asymmetric consequences:**

| Timing | Result | Notes |
|---|---|---|
| Too early | Fish gone, won't return | Punishes trigger-happy response |
| Perfect | Hook set — catch sequence begins | — |
| Too late | Fish spits fly, returns to feeding | Forgives slow reactions — try again |

- "Too early" threshold is tighter on Sim, more forgiving on Casual
- Fish that was too-early spooked counts as a hard spook (+1 intrusion memory)
- Fish that returned after too-late miss continues feeding normally

**Catch sequence (post hookset — full mechanic TBD post-PoC):**
- PoC: successful hookset = catch confirmed, triggers fish photo and log entry

### 8. Hatch System

#### Hatch States

```
No Hatch → Pre-Hatch → Emerger → Peak Hatch → Spinner Fall → No Hatch
```

| State | Surface | Subsurface | Best Fly |
|---|---|---|---|
| No Hatch | None | Nymphs only | Attractor nymph |
| Pre-Hatch | None | Nymphs + rising pupae | Pupa/emerger |
| Emerger | Few adults, many emergers | Pupae in film | Soft hackle, emerger |
| Peak Hatch | Dense adults | Sparse | Dry fly |
| Spinner Fall | Spent adults in film | None | Spinner pattern |

- Insects visible as animated sprites at appropriate depth layer during each state
- Hatch density reflects intensity (sparse = early/late, dense = peak)
- Species have distinct movement patterns: caddis skitter, mayflies drift upright, midges cluster
- Fish feeding behavior shifts based on hatch state (subsurface vs surface takes)

#### Net Sampling

Player can sample the water to identify subsurface insects when no visible hatch is active.

| Sample Type | Trigger | Reveals |
|---|---|---|
| Surface net | Net swing at surface | Adults, spent spinners, emerging duns |
| Subsurface net | Net dipped mid-depth | Emergers, caddis pupae, rising nymphs |
| Bottom sample | Net swept along bottom | Nymphs, larvae, case caddis, stoneflies |

- Player must stand still for 3–5 seconds — interrupted by movement, must restart
- Standing still also drops wading vibration to near zero
- Sample results weighted by proximity to structures (weed bed = more nymphs than open riffle)

**Sample result UI:**
```
┌─────────────────────────┐
│  NET SAMPLE             │
│  ● Caddis Pupa  ████░   │  ← relative abundance
│  ● BWO Nymph    ██░░░   │
│  ● Midge Larva  █░░░░   │
│                         │
│  [Match the Hatch →]    │
└─────────────────────────┘
```
- Abundance bars shown on Casual/Normal — Sim shows insect names only

### 8. Fish AI

#### Feeding Philosophy (Gierach / Edge Feeding)
- Fish hold in slow/deep water adjacent to fast water seams
- Insects funneled through fast water trigger feeding movement
- Fish make short bursts into seam to feed, return to hold
- Travel distance for fly inversely proportional to current speed:
  - Slow water fish = will chase fly further
  - Fast water fish = fly must drift directly into feeding lane
- Prime lies: boulder eddies, pool tail-outs, deep bank beside riffle, undercut banks

#### Fish Species (Madison River natives)
- Brown Trout
- Rainbow Trout
- Mountain Whitefish

#### Spook State Machine

```
FEEDING → ALERT → SPOOKED → RELOCATING → HOLDING → FEEDING
```

| State | Trigger | Behavior |
|---|---|---|
| Feeding | Conditions met | Active, rising, will take appropriate fly |
| Alert | Marginal intrusion or wrong-stage fly rejection | Stops feeding, holds position, won't take fly |
| Spooked | Hard intrusion — shadow, line slap, inside radius, bad cast | Flees to new hold or deeper water |
| Relocating | Post-spook during cooldown | Moving to new position |
| Holding | Settled post-spook | Resumes feeding after additional settling delay |

**Cooldown timers:**
- Small fish: 10s Alert → Feeding; 10s Spooked → Relocating + settle
- Large fish: 30s Alert → Feeding; 30s Spooked → Relocating + settle

**Relocation logic:**
- Spooked toward angler → flees downstream to deeper water
- Spooked by shadow → moves to opposite bank or undercut
- Repeated spooks → increasingly moves to deeper, less accessible holds

#### Spook Radius Calculation

Always routed through `SpookCalculator` — never hardcoded.

```
spook_radius = base_radius
			 × size_multiplier
			 × cover_reduction
			 × time_of_day_modifier
			 × approach_angle_modifier   ← vision cone
			 × difficulty_modifier
```

| Factor | Effect |
|---|---|
| Fish size | Larger fish = wider base radius |
| Cover depth | Deep pocket reduces radius significantly |
| Time of day | Dawn/dusk feeding focus reduces wariness slightly |
| Wading vibration | Adds omnidirectional component, scales with movement speed |
| Shadow cone | Directional, sun-angle dependent, bank only |
| Approach angle | Blind spot = minimum; head-on = maximum |

#### Intrusion Memory

| Fish Size | Memory Duration | Uncatchable Threshold |
|---|---|---|
| Small | Resets after cooldown | Never |
| Medium | Full session | 5 spooks |
| Large | Full session | 3 spooks |

- Wrong-stage fly rejection counts as +0.5 spook
- Large fish approaching threshold: twitchy idle animation, tighter spook radius (visual tell)
- At threshold: lockdown — drops to deepest hold, stops feeding for session
- Lockdown resets at dawn — rewards returning at the right time

### 9. Procedural River Generation

#### Generation Pipeline

```
Seed → Depth Profile → Current Map → Structure Placement → Hold Evaluator → Fish Spawn → Hatch Layer
```

- Section seed = `hash(base_seed + section_index)` — deterministic and shareable
- River flows left-to-right (downstream); fish always face upstream (right-to-left)
- Section length: **24 screen widths**
- Sections generate seamlessly — next section pre-generates offscreen, previous despawns behind player

#### Depth Profile
- Generated via simplex noise
- Parameters: river width, min/max depth, bank slope steepness
- Produces natural shallow runs, deep pools, mid-depth riffles

#### Structures

| Structure | Placement Rule | Cover Value | Hatch Indicator | Notes |
|---|---|---|---|---|
| Weed beds | Shallow/mid, slow current | High | Highest | Primary insect habitat; best cover |
| Large boulders | Mid/deep, infrequent | High | High | Strong eddy/seam creation |
| Rocks (small) | Any depth, faster current | Medium | Medium | Secondary seam creators |
| Undercut banks | Bank edge | High | Medium | Prime large fish holds |
| Gravel bars | Shallow, low current | Low | Low | Spawning areas |

All structures contribute to hatch indicator weighting — denser structure = higher insect activity in area.

#### Hold Evaluation

After structure placement, every tile scored:
```
hold_score = cover_value + seam_proximity + depth_score + current_speed_score
```
Top-scoring locations become fish holding spots — no hardcoded positions.

#### Structure Density by Difficulty

| Parameter | Arcade | Standard | Sim |
|---|---|---|---|
| Structure density | High | Medium | Low |
| Boulder frequency | Common | Moderate | Rare |
| Weed bed coverage | Dense | Moderate | Sparse |
| Undercut bank frequency | Frequent | Moderate | Rare |
| Deep pool frequency | High | Medium | Low |
| Fish per section | Many | Moderate | Few |
| Hold quality distribution | Many prime holds | Balanced | Few prime, mostly marginal |

---

## Difficulty Settings

| Factor | Casual | Normal | Sim |
|---|---|---|---|
| Base spook radius | Small | Medium | Large |
| Large fish radius multiplier | 1.2× | 1.5× | 2.0× |
| Deep cover reduction | 50% | 35% | 20% |
| Dawn/dusk wariness reduction | 30% | 20% | 10% |
| Bad cast spook chance | Low | Medium | High |
| Shadow cone visibility | Always shown | Shown when close | Hidden |
| Fish behavior telegraph | Strong color shift early | Subtle | None |
| Wading vibration radius | Small | Medium | Large |
| Vision cone blind spot | Wide | Standard | Narrow |
| Net sample abundance bars | Shown | Shown | Hidden |
| Wrong species intrusion memory | None | None | +1 |

---

## Time of Day

- Cycle: Dawn → Morning → Midday → Afternoon → Dusk → Night
- Affects: fish feeding edge activity, spook wariness modifiers, shadow direction/length, hatch windows, fish visibility/silhouette contrast
- Sky lighting strip reflects current time
- Large fish lockdown resets at dawn

**Time scale (player configurable):**

| Setting | Real time per in-game hour | Full day duration |
|---|---|---|
| Default | 1 minute | ~24 minutes |
| Slow | Up to 60 minutes | Up to 24 hours (real-time) |

- Player sets session start time (e.g. start at dawn to hit the morning hatch)
- Real-time mode intended for immersive/sim play

---

## Session Structure & Catch Log

Sessions are freeform — no objectives, no time limits. The player explores, reads the water, matches the hatch, and fishes at their own pace.

**On catch:**
- Successful hookset triggers catch sequence (full fight mechanic TBD post-PoC)
- Each fish has procedurally generated visual attributes assigned at spawn — photo captures the specific fish

**Procedural fish variation per species:**

| Species | Varied Attributes |
|---|---|
| Brown trout | Spot density, spot size, body color (golden → silver), kype size on large males |
| Rainbow trout | Lateral stripe intensity (spawning pink → chrome), spot density, body depth |
| Mountain whitefish | Scale pattern variation, body proportions |

- Variation seeded from fish instance — same fish always looks the same if revisited
- Photo snapshot renders the fish's specific generated attributes in 16-bit pixel art style

**Catch log entry records:**
- Fish species
- Size (inches/cm)
- Fly used
- Hatch state at time of catch
- Time of day
- River section seed + approximate location in section

**Logbook UI:**
- Accessible from pause menu
- Photo gallery of all caught fish
- Sortable by species, size, fly, time of day
- Foundation for future multiplayer sharing (seed already stored per catch)

---

## UI / HUD

| Element | Location | Purpose |
|---|---|---|
| Rod arc + fly line | Bottom left | Casting rhythm reference |
| Cast timing meter | Bottom center | Timing window visualization |
| Fly selector | Bottom right | Active fly, quick swap |
| Net sample panel | Context popup | Insect abundance results |
| Time of day indicator | Top strip | Sky lighting + time label |
| Difficulty indicator | Pause/settings | Current difficulty tier |

---

## PoC Milestone Scope

- [ ] Single procedurally generated river section (seeded), 24 screens wide
- [ ] 3-4 depth layers with current simulation
- [ ] Structures: weed beds, rocks, large boulders, undercut banks
- [ ] Hold evaluation and fish spawn from hold scores
- [ ] Bank and wading movement with distinct spook profiles
- [ ] Fish vision cone — approach angle affects spook distance
- [ ] Fish visibility — depth + lighting opacity scaling, shallow ripple
- [ ] Casting mechanic — line feed/strip, false cast rhythm, rod arc HUD (direction cue + loop quality + line length), complete cast button
- [ ] Line drag accumulation during drift
- [ ] Mending — upstream and downstream rod movement corrects drag
- [ ] Elk Hair Caddis + Caddis Pupa fly selection
- [ ] Fly matching sliding scale with partial intrusion memory
- [ ] Brown trout and rainbow trout
- [ ] Mother's Day Caddis hatch — full state cycle (Pre-Hatch → Spinner Fall)
- [ ] Net sampling mechanic with 3-5s stand-still requirement
- [ ] Spook state machine with intrusion memory
- [ ] Large fish lockdown at 3 spooks, resets at dawn
- [ ] 3 difficulty tiers (Arcade / Standard / Sim)
- [ ] Seamless section generation
- [ ] Time of day cycle with configurable time scale and session start time
- [ ] Hookset mechanic — strike indicator (nymph) / rise splash (dry), asymmetric too-early/too-late consequences
- [ ] Procedurally varied fish visuals (per-instance at spawn)
- [ ] Catch log — pixel art fish photo snapshot with procedural variation, logbook UI
- [ ] Placeholder pixel art assets
- [ ] Keyboard + gamepad input mapping (fully remappable)

---

## Open Questions / Future Scope

- Multi-stage false casting for distance control
- Full Madison River hatch chart across seasons
- Multiplayer (seed sharing already designed for this)
- Fish steering / line mending during drift
- Drag mechanic — unnatural fly movement reduces take probability
- Weather effects (wind affecting cast, overcast reducing shadow risk)
- Sound design (river ambience, cast whoosh, rise splash)
- Mobile touch controls for casting rhythm
- Generic/attractor pattern profiles
- Upstream approach vibration counteracting blind spot advantage
