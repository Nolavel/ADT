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

**Time budget:** 5–12 hours per week, irregular. This is the governing constraint
on everything below. A horizon that assumes more is fiction.

**Sequencing is by dependency, not by date.** Items unlock each other. Calendar
dates appear only where an external commitment exists.

Last reviewed: 2026-08-12

---

## Now — current horizon

One horizon open at a time. It closes when its Definition of Done is met, then
the next is promoted from Next.

### H1. Dependency rules + save contract

**Why this first:** every system built without a save contract raises the cost of
adding one later. `IncidentRegistry` already holds `Node3D` references and
engine-uptime timestamps — neither survives a save/load boundary. This is debt
accruing interest, and it is the only item on this page that gets worse with
delay. Everything else merely waits.

The dependency rules are bundled in because they are cheap to write and they
constrain everything after them.

**Tasks**

- [ ] Write the Context / Autoload / Signal / Group rule into `CLAUDE.md`:
  - **`WorldContext`** — composition and runtime dependencies. Default choice.
  - **Autoload** — genuinely global state or service. Closed set: the existing
    four plus the MCP helper. Additions require explicit discussion.
  - **Signal** — event notification, one-to-many, sender does not care who listens.
  - **Group** — discovery and tagging, for nodes that never receive a
    `WorldContext` (static scene instances such as `DroneBase`).
- [x] Generalise and document `get_save_data() -> Dictionary` /
      `load_save_data(data: Dictionary)` as an optional contract on
      `WORLD_SYSTEM_SCRIPTS` entries, alongside the existing
      `on_world_ready(context)` lifecycle hook. This contract already existed —
      `GameClockSystem` implemented it before H1 started — so the task here was
      never to define it, only to write it down and give it a second
      implementer. A system opts in by implementing `get_save_key()`,
      `get_save_data()` and `load_save_data()` together; `SaveSystem`
      (`core/world/save_system/`) walks every system and checks with
      `has_method()`, exactly like the existing `on_world_ready()` opt-in.
- [x] Implement it on exactly two systems: `GameClockSystem` (trivial payload,
      proves the lifecycle) and `IncidentRegistry` (hard payload, proves the
      contract is real).
- [x] `IncidentRegistry` specifically: replace the `Node3D` perpetrator reference
      with a stable string id, and replace `Time.get_ticks_msec()` timestamps with
      game time. Both are required for the record to survive a reload, and both
      get more expensive once a second producer exists.
- [x] Version field in the payload from the first write. Not "later" — the first
      save file written without one is a migration problem forever.
- [x] Debug save/load on a keybind through `InputSystems` (`F5`/`F9`,
      `debug_save`/`debug_load`).

**Definition of Done:** punch an NPC, save, quit to desktop, relaunch, load — the
drone still knows about the incident.

**Explicitly not in scope here:** player position, inventory contents, streaming
state, NPC state. The contract is what matters, not payload coverage.

Sleeping in a room is H1's own payload, not a separate item that comes after
it — this line said otherwise until 2026-08-12 and was wrong by then; see
`CHANGELOG.md` for when and why it was corrected instead of just deleted. A
debug keybind proves `SaveSystem` is wired correctly; it cannot prove the
contract is worth having, because nothing in the fiction ever produces a
save that way. Sleep is what makes "the contract works" a claim about
something real rather than about the plumbing alone — a room, not a
keypress, is the save point this horizon exists to prove out. What stays
out of H1 is everything around the act of sleeping, not the act itself:
which rooms the player can use, any cost to sleeping, whether unstored
items can be lost, and lodging read as part of the fiction rather than as
test scaffolding for this contract.

---

## Next — promoted when H1 closes

### H2. Key hints HUD

**Why before the pistol:** a collaborator cannot evaluate a build whose controls
are undiscoverable. Valid inputs differ by mode, view mode and stance, and none of
it is on screen. This is the cheapest item here with the largest effect on anyone
who is not the author — and a game designer review on a live build is the first
collaborator milestone.

Reads `PlayerState` (`mode`, `view_mode`, `stance`, `is_aiming`) and displays the
currently valid actions. Data-driven from a resource, not a hardcoded per-state
switch — the combinations will keep changing.

**Definition of Done:** someone who has never seen the project can enter combat
stance, aim, and board a hover without being told how.

### H3. EquipmentComponent

What is held, what is stowed, draw/holster state. Distinct from
`InventoryComponent`, which owns what is carried — a weapon is an inventory item
that equipment can hold. The only genuinely new component in this sequence;
everything else it touches already exists.

Prerequisite for all of H4.

### H4. Pistol chain

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
to be started first out of enthusiasm. It depends on H3, is hard to evaluate
without H2, and without H1 would be built on a foundation that cannot be saved.

---

## A note on automated tests

Both external architecture reviews (August 2026) flagged the absence of automated
testing. The judgement here is that building test infrastructure competes directly
with combat and save on a 5–12 h/week budget, and loses.

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
