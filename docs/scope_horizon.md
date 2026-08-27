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

Last reviewed: 2026-08-26

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

- **Island transition (Blackrock → Aogashima).** All six steps of
  `docs/island_rescope_brief.md` are done. Step 5, the building generator,
  was the last one open and is closed by evidence rather than assertion:
  `tools/city_generator/` holds the four files the 2026-08-25 entry
  describes, `core/map_source/map_source.tscn` carries 151 `GBX_` markers —
  exactly the dry-run figure — and `data/world_data.tres` holds 152
  `BlockData` entries (`landmark`, `tower_001`, `cty_001`–`cty_150`), so the
  Export step ran and the runtime streams the generated city. That entry's
  own caveat ("markers actually appearing in `BLOCKS` is his first run") is
  discharged. See `CHANGELOG.md`, 2026-08-25.

- **H3. Crowd readability** and **H4. Witnesses** — closed **as concepts**,
  by decision, 2026-08-26. The archetype channels are in (five archetypes in
  `data/npc_archetypes/`, colour/gait/attention applied through
  `NPCBase._apply_archetype()`), and the witness chain of
  `docs/attribution.md` §7 runs end to end: perception → distance ceiling →
  `WitnessReport` → Votive transmit → COMMITTED / CANCELLED, with the
  developer observation panel §7 asks for. Four of the five §7 test cases
  were measured on 2026-08-26 and pass; the fifth (case C) cannot pass under
  today's tuning, recorded as a known gap in `attribution.md` §7 rather than
  fixed here. **Refinement of both is deliberately deferred well past H6** —
  closing them means they stop gating the next horizon, not that they are
  finished work.

H1's own task list had one box still unchecked when this horizon closed —
the Context/Autoload/Signal/Group rule, bundled into H1 because it was
cheap to write alongside it, was never actually written into `CLAUDE.md`.
Finished as part of closing H1 rather than left as a loose end on a
horizon marked done; see `CLAUDE.md`'s Architecture rules.

---

## Now — current horizon

### H6. Firearm chain

**Why this is Now:** H5 (`EquipmentComponent`) closed on 2026-08-23 and was
its only prerequisite. The island closed on 2026-08-26, so the reason to hold
a weapon back — "a weapon on the old vertical city is wasted effort" — is
spent. H3/H4 closed as concepts the same day and no longer gate anything.
This is the demo's TIER 2 target and the first real test of ACT.

Built as one connected slice, in this order:

1. The weapon as an inventory item
2. Pickup and persist
3. Draw / holster through `EquipmentComponent`
4. Locomotion with the weapon drawn
5. Firing at an NPC, damage through existing `HealthComponent` / `take_hit()`

Step 3 is largely met already — `draw_holster` (`B`) and the stance coupling
landed with H5 S5 — so the slice starts closer to the middle than the list
suggests. Steps 1, 2 and 5 are the real work.

**Definition of Done:** the weapon can be found on the island, picked up, kept
across a save/load and a block unload, drawn and holstered, carried while
moving, and fired at an NPC who takes damage through the existing health
path and enters the incident record the same way a punch already does.

**The weapon is a carbine, not a pistol** (2026-08-27). The chain shipped as
a pistol on 2026-08-26 and was rebuilt around a two-handed carbine the next
day: the pistol has four or five clips in this project's libraries, while
the rifle set has an idle, an aim, fires, reloads, turns and — decisively —
a full eight-direction locomotion pack, which is the only clip set that can
actually show step 4. Ammunition (a magazine, a reload key and a HUD row)
came with it and was not in the original list. **This does not close H6** —
that stays held for a clean playtest.

---

## Next — promoted when H6 closes

### H7. Persistent entity state

Doors, named NPCs, dropped items that survive block unload and save/load.
Requires classifying every world object into Ephemeral / Persistent /
Simulated / Global. Cost of deferring rises with every object added before
the registry exists.

### H3 / H4 refinement

Both closed as concepts (see Closed). What was deferred rather than done:
the SILHOUETTE observation level is unreachable under current tuning
(`attribution.md` §7), `observation_level` is still written and read by
nothing, no reaction is differentiated by it, and archetype readability is
still flat placeholder colour rather than mesh or material variants. None of
this blocks H6. Revisit after it.

---

## Out of plan

Work that happened but was never on this page. Recorded here rather than
back-dated into a horizon: this file governs a limited time budget, and a
budget that only shows planned work is fiction. An entry here is not a
demotion — it is how unplanned work stops being invisible.

### ISOMETRIC camera feel (Phases 1 → 5B)

Arrived as a separate brief while the island horizon was open, and ran
alongside it. Eight `CHANGELOG.md` entries, 2026-08-26 onward: directional
yaw replacing the four-position orbit, octant yaw and cursor bias, head
turn, critically damped output, wall safety and screen-edge framing,
look-ahead, adaptive turn character, destination reversal.

**Not finished.** Collision response and a refactoring pass remain
outstanding. It continues outside the H-series order and is tracked in its
own working session, not here — this section exists to record that it
happened and that it is still open, not to schedule it.

Two things it changed that other work must not undo: `IsometricCameraState`
now owns the ISOMETRIC yaw as well as the follow point, and the four-position
orbit (`OrbitalPosition`, Q/E stepping) plus `toggle_follow` (`P`) are left
in `OnFootCameraComponent` unreached, pending removal once the feel is
settled.

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
