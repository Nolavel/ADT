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

Last reviewed: 2026-08-28

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

### H6. Carbine chain

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

**The weapon is the carbine.** It shipped as a pistol on 2026-08-26 and was
rebuilt around a two-handed carbine the next day, and the horizon is named
for the carbine from 2026-08-29 because that is what it is: the pistol has
four or five clips in this project's libraries, while the rifle set has an
idle, an aim, fires, reloads, turns and — decisively — a full eight-direction
locomotion pack, which is the only clip set that can actually show step 4.
Ammunition (a magazine, a reload key and a HUD row) came with it and was not
in the original list.

**Measured against the Definition of Done, 2026-08-29.** Six of the seven
clauses were driven in a throwaway probe rather than judged by eye, and all
six pass:

| Clause | Result |
|---|---|
| found on the island | `world.tscn` carries the placed `carbine.tscn` instance |
| picked up | `stow_anywhere()` accepts it onto `back_pack` |
| kept across save/load | the slot AND the spent magazine both survive a `get_save_data()` / `load_save_data()` round trip (6 rounds in, 6 rounds out) |
| drawn and holstered | `draw()` accepted, `get_drawn()` reads `carbine`, `holster()` returns it, hands empty after |
| fired at an NPC, damage through the health path | `_resolve_shot()` → `take_hit()` → `HealthComponent`, 100 → 0 |
| enters the incident record | `IncidentRegistry.get_latest_incident()` is non-null after the shot; `shot_landed` is wired to the same handler `punch_landed` uses |

The seventh — **carried while moving** — is the one clause a headless probe
cannot answer, because it is entirely about how the eight-direction rifle
locomotion reads on screen. **That, and only that, is what H6 is still held
for.** Everything mechanical in the Definition of Done is now evidenced.

Also outstanding and visual, not mechanical: the carbine's `HeldFit` puts
the weapon along the forearm but has not been seated in the palm with the
Item Fitter dock (`docs/ITEM_FITTER.md`).

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

### TPS-only camera migration — DONE 2026-09-02

Audited 2026-08-30 (`docs/tps_camera_single_mode_audit.md`), decided and
carried out on 2026-09-02. The audit's finding held: there was no technical
blocker, and the risk was entirely in the periphery.

**What was removed.** `IsometricCameraState`, `isometric_camera_debug_overlay.gd`
and the `IsoCameraDebug` node, every ISO branch inside `OnFootCameraComponent`
(which went from 2023 lines to ~640) along with the orbit and follow-rotation
code the audit had already found unreachable, `ClickToMoveSystem`,
`ZoomRulerSystem` and `vfx/hud_component/zoom_ruler/`, the `zoom_in`,
`zoom_out` and `toggle_follow` actions, and the move-destination indicator.

**What was deliberately NOT removed.** `NavigationComponent` and
`player.move_to_position()` — `InteractComponent`'s auto-approach uses them,
exactly as the audit warned. Only the click handler died. The candidate decal
(`CandidateIndicator`) also stays: it is about interaction, not about clicks.

**The three open product decisions, answered by Stan:**

1. **Zoom is gone**, with `ZoomRulerSystem` and `zoom_ruler_hud` — no TPS
   consumer existed and none was invented.
2. **Q/E become a TPS lean**, using the animation clips if they existed. They
   did: `new4/aim-lean-l` / `new4/aim-lean-r`, measured to be static held
   poses, wired as two chained `AnimationNodeBlend2`. The camera leans always,
   the body only in `COMBAT` — the clips are aiming poses and read as miming
   a rifle with empty hands.
3. **CONFLICT-1 is not touched**, carried over unchanged as a separately
   tracked bug, per the audit's explicit instruction that the migration must
   neither silently fix nor silently lose it. See "Carried over" below.

**Inherited as the audit required:** the sphere-cast occlusion contract
(`cast_motion`) is now the single camera's, not the old TPS raycast. Its two
LENGTHS could not come with it — sized for a 10–17.5 m orbit, the 3.0 m
minimum would have disabled occlusion outright on a 2.2 m boom — so radius
and minimum distance were re-derived and are the part most in need of eyes.

**The second view mode survives as a FRAMING.** `PlayerState.ViewMode` is
`TPS` / `TPS_WIDE`: one camera, with a lens shift putting the character low
and to one side and a shorter boom (1.30 m against 2.2). The constraint began
as *"только смещение, дистанция та же"* and was built that way; it moved when
the reference frame was measured against a render — the character sits 6.8%
in from the left at ~29% of frame width there, against 20% and ~14% from a
lens shift alone, and a lens shift cannot make a subject bigger. `wide_distance`
set back to `TPS_DISTANCE` restores the original behaviour exactly.

### Carried over from the camera migration

- **CONFLICT-1** — `TpsCombatCameraState` computes a blended yaw during
  `TRANSITION` but the caller applies it only while `LOCKED`, so the blend is
  discarded. Untouched by the migration on purpose. Not scheduled.
- **`TargetIndicator`'s move-destination API** (`show_at_position()`,
  `show_invalid_click()`, `set_player_reference()`, and the ring and arrow
  they drive) is now unreached — the decal_only candidate role is the only
  one instanced. Left intact rather than stripped: whether a destination
  marker comes back is a design question, not a cleanup.
- **The wide framing's three numbers** (`wide_h_offset` 0.40 / `wide_v_offset`
  0.20 / `wide_distance` 1.30) were chosen from rendered candidates against
  the reference frame, on Compatibility, not by playing. Deliberately held
  back from the reference's exact scale: at 1.1–1.2 m the figure fills a
  quarter of the frame permanently and the near plane starts clipping the
  shoulder on turns. They are exports; expect to move them.

### Comic panels (the word gets a frame)

The floating comic word became a drawn panel — plate, faint print grid, inked
border — with four shared visual registers instead of thirteen per-event
colours, and pop → hold → fade timing instead of a fade that started on the
first frame. `docs/visual_language.md` §7 is the art-direction record;
`CHANGELOG.md` 2026-08-28 is the dated one.

**This was never on this page, and it is not a horizon.** It came out of an
idea worth trying and was built the same week it was had. The trade is stated
plainly rather than dressed up: development here is one person with a limited
budget and no external plan to answer to, so experimenting with what the
interface feels like is part of the work rather than a distraction from it —
but it spends time H6 was holding. The intent is to keep such work in the
form of targeted follow-up edits, not reverted merges.

**What it did not touch, on purpose:** the vocabulary, the distance gate, and
`MAX_ACTIVE` — `docs/visual_language.md` §4 makes those art direction, and
this change had no art-direction argument for moving them.

**Open:** the `environment` register exists with no consumer, waiting for a
first world event rather than for an event invented to justify it. And the
look itself is unverified — headless proves the geometry, the phases and the
absence of leaks, not whether the panel reads as a comic panel rather than a
UI tooltip. That needs eyes.

---

### CI for the verification ladder

`.github/workflows/godot.yml` — the import-twice-then-boot ladder, run by the
repository on every PR and on a push to `main`, reusing
`.claude/hooks/ensure_godot.sh` so the engine version stays pinned in one
place. There was no `.github/` directory in this repo at all before this.

**Not a horizon and not on the H-series.** It came out of a question about
what such a folder would even be for, and was built the same hour. It costs
close to nothing to run (the repo is public, so Actions minutes are free) and
about an hour to build, which is an hour H6 was holding.

**What it deliberately does not do:** no test suite (see the note below —
that trade is unchanged), no `CHANGELOG`/contract gate (considered, dropped
as likely to be worked around rather than obeyed), no PR template. Those can
be added later without touching what is here.

**Open:** an orphan script — a `.gd` nothing references — is never compiled by
the import pass, so a syntax error in it still passes green. Measured, not
assumed. There is no cheap fix and the case is documented in `CLAUDE.md`
rather than papered over.

---

## A note on automated tests

Both external architecture reviews (August 2026) flagged the absence of automated
testing. The judgement here is that building test infrastructure competes directly
with combat and save under limited development time, and loses.

This is recorded as an accepted trade, not an oversight, so that it stops being
re-raised as a finding. Revisit when a second person is working in the repo —
at that point the cost of a regression is paid by someone who did not write the
change, which is when tests start earning their keep.

**CI, added 2026-08-28, does not reverse that trade — it is a different thing.**
`.github/workflows/godot.yml` runs the existing verification ladder from
`CLAUDE.md` (import twice, boot `world.tscn`) and asserts nothing about
behaviour: it catches a script that does not parse, a `res://` path that does
not resolve, and a world that does not come up. No test suite, no GUT, no
assertions about what the code *does*. The trade above still stands; what
changed is only that the ladder now runs by itself instead of depending on
whoever remembers it.

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
