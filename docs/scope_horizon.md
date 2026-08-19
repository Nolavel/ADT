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

Last reviewed: 2026-08-16

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

H1's own task list had one box still unchecked when this horizon closed —
the Context/Autoload/Signal/Group rule, bundled into H1 because it was
cheap to write alongside it, was never actually written into `CLAUDE.md`.
Finished as part of closing H1 rather than left as a loose end on a
horizon marked done; see `CLAUDE.md`'s Architecture rules.

---

## Now — current horizon

One horizon open at a time. It closes when its Definition of Done is met, then
the next is promoted from Next.

### H3. Crowd readability

**Why this first, ahead of the pistol chain:** `core_loop.md` §7 names OBSERVE
the only stage of the loop that is completely empty — every NPC is the same
mesh, nothing to read. §8 draws the consequence bluntly: with an unreadable
crowd there is nothing to test — not the core statement, not evidence-over-
stars, not the 1/5/10 minute test (§11 — minutes 5 and 10 have no answer yet,
both blocked on this exact gap). A pistol grafted onto an unreadable crowd
changes nothing structural: it only widens ACT, the one stage that already
half-works, while the loop stays broken exactly where it always was — a
louder fist, not a different game. A weapon earns its place once there is
someone worth aiming it at on purpose, which is what this horizon builds
toward.

Implements `npc_archetypes.md` in full: six archetypes as data (a resource
per archetype plus one field on `NPCBase`), plain-colour placeholders — the
document itself sanctions flat colour at this stage — and enough population
in one Doggerland block to actually feel like a crowd rather than a lineup
of individuals, not a spawn system (see the implementation commits for what
was used instead and why it will not need tearing out).

**Definition of Done:** walk one block and name who is who out loud, without
opening the inspector. Specifically: it must be obvious who is not worth
robbing, and who is watching.

---

## Next — promoted when H3 closes

### H4. Witnesses

**Why before the pistol, after crowd readability:** readability alone gives
OBSERVE something to look at; it does not yet give ACT's aftermath anywhere
to go. `core_loop.md` §6 lays out four different outcomes of the same punch
in an alley, told apart only by what became known and to whom: nobody saw
it; a witness saw the act but not where the player went; a camera recorded
the incident without a face; a drone recorded both. `IncidentRegistry`
today has exactly one level of knowledge — a fact is reported, tied to a
known perpetrator id, or it does not exist. The work here is mostly not
code: `report()`/`Incident` already exist and work. It is deciding the
model for "witnessed, but the witness doesn't know who" — a shape the
current registry has no room for, since every incident it accepts already
assumes an identified perpetrator.

Scope is now `docs/attribution.md` §7, the vertical slice of that page's
fuller Observation → Incident → Report → Attribution chain (§1–§6, all
deliberately unbuilt past this slice):

```
NPC perception
    ↓
incident observed?
    ↓
observation quality resolved (distance ceiling, attention modifier)
    ↓
WitnessReport created
    ↓
Votive: blue → red/off ×3 → solid red
    ↓  3 s
COMMITTED  or  CANCELLED
```

A witness (`npc_archetypes.md` §2's flag, no visual tell) that decides to
call no longer reports instantly — it resolves an observation quality
(distance ceiling from §2, attention modifier from facing) into a
`WitnessReport`, then visibly transmits for `attribution.md` §6's ~3-second
window before the report actually commits. `observation_level` is written
and read by nothing yet — a deferred output for §5 (attribution, not
scheduled), not dead code. No drone reacts differently by observation
quality; suppressing a witness mid-transmission is not a special case, it is
just another assault with its own witnesses.

**Picked up out of order relative to H3.** This horizon's own work — six
archetypes, the witness flag, the Flee/Freeze/Call reaction roll — landed in
`npc/controllers/idle_npc_controller.gd` before H3's Definition of Done was
formally exercised in play. `docs/attribution.md` §7 is what replaces that
Call roll's instant, fully-attributed report with the resolve-then-transmit
chain above. H3 stays open (see its own entry) — crowd reactions still
haven't been walked through and judged by Stan — so this entry documents
what is actually being built now without claiming H3 is done.

### H5. EquipmentComponent

What is held, what is stowed, draw/holster state. Distinct from
`InventoryComponent`, which owns what is carried — a weapon is an inventory item
that equipment can hold. The only genuinely new component in this sequence;
everything else it touches already exists.

Prerequisite for all of H6.

### H6. Pistol chain

The demo's TIER 2 target, built as one connected slice rather than four separate
features:

1. Pistol as an inventory item — same data model as any other item, no special case
2. Pickup and persist in inventory
3. Draw / holster through `EquipmentComponent`
4. Locomotion with pistol drawn — the stance-branched `AnimationTree` already runs
   its COMBAT branch on ShooterLib clips, so this extends an existing structure
   rather than adding one
5. Firing at an NPC, damage through the existing `HealthComponent` and `take_hit()`

**Sequenced last on purpose.** It is the most visible item and the one most likely
to be started first out of enthusiasm. It depends on H5, and — the newer reason,
see H3's own rationale above — it answers ACT, which was never this build's
actual gap; OBSERVE (H3) and WHAT BECAME KNOWN (H4) were.

---

 **Sequenced last on purpose.** It is the most visible item and the one most likely
 to be started first out of enthusiasm. It depends on H5, and — the newer reason,
 see H3's own rationale above — it answers ACT, which was never this build's
 actual gap; OBSERVE (H3) and WHAT BECAME KNOWN (H4) were.
 
### H7. Persistent entity state

**Why here, and why not later:** three systems implement the save contract today
(`GameClockSystem`, `IncidentRegistry`, `LodgingSystem`). Nothing else survives a
block unload — an opened door closes, a killed NPC returns, a dropped item is gone.
That is invisible while the world is empty and fatal at the first mission, which is
by definition a sentence about world state persisting between two visits.

The contract itself already exists and is proven on two payloads, one trivial and
one hard. What is missing is the layer between it and the world: something that
holds "`door_warehouse_04` is open" as a fact independent of the Node representing
that door, and reapplies it when the block streams back in.

Requires classifying every world object into one of four lifecycles, which is most
of the actual work — the registry is small once the classification exists:

| Lifecycle | Rule | Example |
|---|---|---|
| Ephemeral | recreated on load, no state kept | passer-by |
| Persistent | state outlives unload | door, container, named NPC |
| Simulated | recomputed cheaply while unloaded | hover traffic |
| Global | independent of any block | game clock, incidents |

The cost of deferring is not the registry — it is that every object added before it
has to be retrofitted one at a time.

**Definition of Done:** open a door, kill a named NPC, drop an item; walk far enough
that the block unloads; come back. All three are as you left them. Same after a
save/load cycle.

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
