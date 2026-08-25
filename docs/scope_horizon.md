# Scope horizon

What is being worked on now, what is next, and why in that order.

**Audience:** collaborators joining mid-project, and agent sessions (Claude Code)
that need to know what "next" means without being told. Read this after
`CLAUDE.md`.

**Where this sits among the other documents.** Three files, three tenses, no
overlap — if a fact belongs in two of them, it is in the wrong one:

| File | Answers |
|---|---|
| `planned_scope.md` | What does **not** exist, and what would have to be true before it did |
| `scope_horizon.md` (this file) | What is being built **now**, and in what order |
| `CHANGELOG.md` | What was **done**, dated |

Anything not on this page is not scheduled, however good an idea it is. Ideas go
to `planned_scope.md` with their prerequisite named; they do not go here until
that prerequisite is met.

The same no-overlap rule applies to design weak points: they are named once, in
`core_loop.md` §9, not restated here. If a weak point becomes relevant to
sequencing, link it from the item that depends on it.

**Time budget:** development time is limited and irregular. This is the governing
constraint on everything below. A horizon that assumes more is fiction.

**Sequencing is by dependency, not by date.** Items unlock each other. Calendar
dates appear only where an external commitment exists.

Last reviewed: 2026-08-25

---

## Closed

Horizons that met their Definition of Done. Their substance lives in
`CHANGELOG.md`, dated — not restated here; this section exists so a closed
horizon has somewhere to go instead of just disappearing from the page.

- **H1. Dependency rules + save contract.** `SaveSystem` walks
  `WORLD_SYSTEM_SCRIPTS` on the `get_save_key()`/`get_save_data()`/
  `load_save_data()` contract, implemented by `GameClockSystem` and
  `IncidentRegistry` (stable `StringName` perpetrator ids, game-hour
  timestamps, versioned payload); sleeping in `LodgingRoom` is the
  in-fiction save point the contract exists to prove out. See
  `CHANGELOG.md`, entries dated 2026-08-11 through 2026-08-13.

- **H2. Key hints HUD.** `KeyHintsPanel` reads `PlayerState`
  (`mode`/`view_mode`/`stance`/`is_aiming`) and shows the currently valid
  actions, data-driven from `data/key_hints.tres`, three columns
  (Movement/Action/System). See `CHANGELOG.md`'s "H2" entries.

- **H5. EquipmentComponent.** What is held, what is stowed, draw/holster
  state. Distinct from `InventoryComponent`. Full vertical slice delivered
  2026-08-23 (S1–S7): slot data, component rules + persistence, Interact no
  longer decides storage, draw/holster coupled to stance, equipment
  authoritative over authored mesh visibility. See `CHANGELOG.md` entries
  dated 2026-08-23. Prerequisite for H6 is now met.

H1's own task list had one box still unchecked when this horizon closed —
the Context/Autoload/Signal/Group rule, bundled into H1 because it was
cheap to write alongside it, was never actually written into `CLAUDE.md`.
Finished as part of closing H1 rather than left as a loose end on a
horizon marked done; see `CLAUDE.md`'s Architecture rules.

---

## Now — current horizon

One horizon open at a time. It closes when its Definition of Done is met, then
the next is promoted from Next.

### Island transition (Blackrock → Aogashima)

**Why this is Now:** the vertical 3200 m city is replaced by a single volcanic
island (ceiling 1000 m) per `docs/island_rescope_brief.md`. This is a
load-bearing world change. Continuing to build content or systems against the
old strata model produces work that must be torn out. The brief is the single
source of truth for order and numbers.

Order is fixed (see the brief). State as of 2026-08-25:

1. **Done** — strata removed as a technical entity, from the runtime and from
   the editor tools. The 3×3 ground-tile grid went with them: nine 2200 m slabs
   were a walkable seabed under the whole ocean, and the terrain is the ground
   now.
2. **Done** — `BLOCK_STREAM_RADIUS` 400, `BLOCK_UNLOAD_RADIUS` 500, with the
   pipeline's changed purpose recorded next to them.
3. **Done differently, by decision.** The heightmap is procedural
   (`tools/island_generator/aogashima_generator.gd`), not real Aogashima DEM;
   the `CREDITS.md` requirement lapses with it. See the brief's amendments.
4. **Done** — terrain mesh, vertex-displacement shader, `HeightMapShape3D`
   collision and the water plane, all in `world/aogashima/`.
5. **Open. This is what "now" means.** No building generator exists. The 33
   greybox blocks currently on the island were replanted from the old city
   layout by scaling it — provisional scenery, not generated placement.
6. **Done** — `CLAUDE.md` split into `docs/architecture/`, world descriptions
   corrected across the documents.

**Definition of Done:** island is the only world geometry; strata code and data
are gone; streaming radii updated; heightmap-driven terrain visible and
collidable; building markers generated from the heightmap; documents no longer
describe the old vertical city. **Only the generator is outstanding.**

H3 (Crowd readability) remains open in parallel only for the residual
play-test judgement of existing archetype reactions. It does not block the
island work and does not receive new features until the island is in.

---

## Next — promoted when the island transition closes

### H3 residual / H4. Witnesses

Crowd readability Definition of Done has not yet been formally exercised in
play. The witness vertical slice (`docs/attribution.md` §7) was partially
landed out of order. After the island is stable, finish the observation →
WitnessReport → Votive transmit chain and close the readability judgement.

### H6. Pistol chain

The demo's TIER 2 target. Now unblocked by closed H5. Built as one connected
slice:

1. Pistol as an inventory item
2. Pickup and persist
3. Draw / holster through `EquipmentComponent`
4. Locomotion with pistol drawn
5. Firing at an NPC, damage through existing `HealthComponent` / `take_hit()`

Sequenced after the island because a weapon on the old vertical city is
wasted effort; a weapon on the readable island crowd is the first real test
of ACT.

### H7. Persistent entity state

Doors, named NPCs, dropped items that survive block unload and save/load.
Requires classifying every world object into Ephemeral / Persistent /
Simulated / Global. Cost of deferring rises with every object added before
the registry exists.

---

## A note on automated tests

Both external architecture reviews (August 2026) flagged the absence of automated
testing. The judgement here is that building test infrastructure competes directly
with combat and save under limited development time, and loses.

This is recorded as an accepted trade, not an oversight, so that it stops being
re-raised as a finding. Revisit when a second person is working in the repo —
at that point the cost of a regression is paid by someone who did not write the
change, which is when tests start earning their keep.

---

## Working rules for this file

- One horizon open at a time. Finishing beats starting.
- An item enters **Now** only when everything it depends on is done.
- New ideas go to `planned_scope.md` with their prerequisite named. They do not
  go to **Now**.
- Update this file in the same commit that closes a horizon — same rule as
  `CLAUDE.md` and `CHANGELOG.md`.
- If an item has been in **Now** for more than three weeks, it was too big. Split
  it rather than extending it.
