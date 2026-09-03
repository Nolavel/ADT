# ADT — work plan, September 2026

Claude Code: create this file at `docs/work_plan_2026-09.md` verbatim, commit it
as its own commit, then start at Task 0. Tick the checkboxes in this file as you
go, in the same commit as the work they describe.

**Read before touching anything:** `docs/NOW.md` (after Task 0 creates it),
`CLAUDE.md`, `docs/scope_horizon.md`, and the `docs/architecture/*.md` file
covering the system you are about to change.

**Rules for every task here:**
- One task per commit. Do not bundle. Do not start the next task in the same session.
- `CHANGELOG.md` entry in the same commit: **3–6 lines. Hard limit.**
- No new `InputMap` actions and no new debug keybindings without asking Stan.
- Do not fix anything the task does not name. Write one line under "Found, not
  fixed" in `docs/NOW.md` and move on.
- **Nothing goes into `CLAUDE.md` except an invariant stated in the present
  tense.** No history, no measurements, no "this used to say", no drift counters.
  If you want to write any of those, the destination is `docs/postmortems/`.
- If the picture is incomplete, stop and ask. Do not guess and do not brute-force.

> **Three corrections applied before this file landed.** Claude Code checked the
> plan's measured claims against the repository; eleven of fourteen confirmed
> exactly, three did not. All three are marked **[corrected 2026-09-03]** at the
> point they occur. A plan carrying a knowingly false premise is worse than an
> edited one — leaving the wrong paragraph in and filing the discrepancy under
> "Found, not fixed" is the documentation drift Task 4 exists to stop.

---

## Task 0 — Session handoff file

**Why.** Chat sessions and Claude Code sessions do not see each other.
`CHANGELOG.md` was meant to be the sync point but is 402 KB across 106 entries
with a 2.6 KB median entry, so nobody reads it at session start. It became an
archive and stopped being sync. Symptom: two external reviewers both reported
`PlayerPersistenceSystem` as missing when it has been wired in `world.gd:64` for
weeks.

- [x] Create `docs/NOW.md` with exactly these four sections and a **hard ceiling
      of 80 lines**. Over 80 lines means something in it is stale and gets
      deleted, never appended around.

```markdown
# NOW

Last updated: <date> by <chat | code>

## Current task
One paragraph. What is being built and which task in docs/work_plan_2026-09.md.

## Decided this week, not yet in CLAUDE.md
Decisions made in chat the code does not reflect yet. Each line ends up either
in CLAUDE.md or deleted. Nothing lives here longer than two weeks.

## Found, not fixed
Noticed while doing something else. One line each. Not a backlog — if it
survives three weeks it goes to docs/planned_scope.md or gets deleted.

## Open question for Stan
At most three. Delete once answered.
```

- [x] Add to `CLAUDE.md`, Workflow rules, **two lines and no more**:
      `docs/NOW.md` is read first in every session and updated last;
      `CHANGELOG.md` entries are 3–6 lines, longer belongs in `docs/postmortems/`.

**Done when:** `docs/NOW.md` exists, is under 80 lines, `CLAUDE.md` points at it,
nothing else changed.

---

## Task 1 — Close H6 (carbine, the visual clause)

Six of seven Definition-of-Done clauses were driven headless on 2026-08-29 and
pass. Two things remain and both need eyes, not code: the eight-direction rifle
locomotion read on screen with the carbine drawn, and the carbine's `HeldFit`
seated in the palm via the Item Fitter dock (`docs/ITEM_FITTER.md`).

**This is Stan's task.** Claude Code's role is limited to running
`sh tools/render_probe/render_probe.sh` on request and applying offsets Stan
reports back. Do not tune `HeldFit` from a Compatibility render — the probe
answers "is the rifle across the hands", never "does it look right".

- [ ] Stan confirms H6 closed
- [ ] `docs/scope_horizon.md`: H6 moved to Closed, one paragraph, pointing at the
      CHANGELOG date

---

## Task 2 — Physics interpolation, one commit

**Measured, not suspected.** `project.godot` sets `common/physics_interpolation=true`.
`reset_physics_interpolation()` is called **nowhere**. `physics_interpolation_mode`
is overridden on exactly one node — `HoverTest`, `world.tscn:25` — a symptom
patched on a single object. `camera_follow.gd` writes `global_transform` in
`_process` (lines 107, 205) and adds shake with `global_position +=` in `_process`
on top of a transform computed in `_physics_process`.

Expect three consequences: streamed cells added via `add_child()`
(`streaming_systems.gd:269`, `:402`) interpolate from the origin on their first
frame; player teleports (spawn, `hover_entry_trigger`, `LodgingRoom`) smear for a
frame; camera shake is eaten or jittered non-deterministically by frame rate.

- [ ] `physics_interpolation_mode = PHYSICS_INTERPOLATION_MODE_OFF` explicitly on
      the camera node, with a two-line comment: the camera does its own
      exponential smoothing in `_physics_process` and writes itself in `_process`,
      so engine interpolation on top is a second smoother fighting the first.
- [ ] `reset_physics_interpolation()` in exactly two places: `StreamingSystems`
      immediately after a newly added node's transform is set (silhouette path and
      content path), and the player teleport path. **Find every discontinuous
      assignment to the player's `global_position` first, list them in the commit
      message, route them through one private helper.** Do not sprinkle calls.
- [ ] Remove the `physics_interpolation_mode` override from `HoverTest`. If it
      turns out to still be needed, stop and report — that means the diagnosis is
      wrong.
- [ ] One line in `docs/NOW.md` → "Open question for Stan":
      `common/max_physics_steps_per_frame=9` (engine default 8) makes a hitch on
      the Intel HD 620 target longer, not shorter — why is it 9?
      **Do not change it.**

**Done when:** the two calls exist, the camera override exists, the `HoverTest`
override is gone, CI green, Stan has watched a boot and confirms nothing slides in
from the origin.

---

## Task 3 — Turn two written rules into machine rules

### 3a. Orphan script detection

`CLAUDE.md` already documents this gap: a `.gd` no scene, autoload or script
references is never compiled by the import pass, so a syntax error in it passes
CI. Confirmed instance right now: `ui/hud/fade_by_distance/fade_by_distance.gd`,
210 lines, referenced by nothing.

- [ ] `tools/ci/find_orphan_scripts.py` (~20–30 lines): collect every `.gd`
      outside `addons/`, subtract everything referenced by `.tscn`, `.tres`,
      `project.godot` and other `.gd` — by path, by `uid://`, and by `class_name`
      — fail on a non-empty remainder. Whitelist `tools/**` EditorScripts as an
      **explicit list with a comment per entry**, not a blanket glob.
- [ ] Wire it into `.github/workflows/godot.yml` as a third step
- [ ] Ask Stan whether `fade_by_distance.gd` gets wired to something or deleted.
      Do not decide.

### 3b. Warnings

`project.godot` has no `[debug]` GDScript warning configuration at all, so engine
defaults apply while the project's stated standard is strict typing. Actual drift:
**38 of 1087 functions outside `tools/` lack a return type (3.5%); 71 project-wide
once `tools/` is counted** — 15 of them in
`core/ui/target_indicator/target_indicator.gd`, which `docs/scope_horizon.md`
already records as unreached code.

> **[corrected 2026-09-03]** The plan originally said "68 of 1181 … fix the 68
> sites outside `tools/`", which merged two different numbers into one: 68–71 is
> the project-wide count, and only 38 of those are outside `tools/`. Measured on
> `main` at `e72903c`.

- [ ] Enable `untyped_declaration` and `unsafe_method_access` as **warnings** in
      `project.godot`. Do **not** enable warnings-as-errors.
- [ ] Separate commit: fix the 38 sites outside `tools/`
- [ ] Then propose the warnings-as-errors flip to Stan as its own decision

**Done when:** CI fails on a deliberately orphaned test file and passes on `main`.

---

## Task 4 — Documentation split by genre; `CLAUDE.md` diet

**The problem is genre, not volume.** Measured: 28 927 lines of GDScript of which
**35.1% are comment lines**; 837 KB of Markdown. `patrol_drone_controller.gd` is
60% comment (773 of 1279 lines), `idle_npc_controller.gd` 49%, `player.gd` 42%.
`CLAUDE.md` and the file headers have become a legal record of past mistakes
("this line previously claimed…", "fourth recorded drift", "measured 2026-09-02,
six taps produced six latches"). An agent opening a file that is 60% history of
someone else's errors appends to the bottom or works around it. Both external
reviewers got the save contract wrong specifically where documentation is densest.

Three genres, three places, no overlap:

| Genre | Where | Test |
|---|---|---|
| Invariant — what must not break, present tense, no history | `CLAUDE.md`, `docs/architecture/*` | readable by someone who does not know the project's history |
| Chronicle — what changed, dated | `CHANGELOG.md`, 3–6 lines | fits on a screen |
| Post-mortem — why it was hard, what was measured, what turned out false | **new `docs/postmortems/`** | one link from the invariant, nothing more |

One commit each:

- [ ] `git mv docs/tps_camera_single_mode_audit.md docs/postmortems/` — 74 KB
      about a migration completed 2026-09-02. A record of a decision, not
      documentation of a current system. No content edits.
- [ ] Split `CHANGELOG.md`: everything before 2026-08-15 into
      `CHANGELOG_2026-07..08.md` (that range holds the 25 KB, 24 KB, 20 KB and
      15 KB entries). Main file keeps ~six weeks plus a link.
- [ ] Strip archaeology from `CLAUDE.md`, each removed passage moving to a named
      file under `docs/postmortems/`: the `.mono` status-bar story, the input-latch
      measurements, the renderer drift history, every "Nth recorded drift"
      sentence. What stays is the invariant in present tense — e.g. "edges come
      from events, levels come from polls; do not add a new
      `Input.is_action_just_pressed()`" plus one link to
      `docs/postmortems/input_edge_latch.md`. **Target: 27 KB → 8–10 KB.**
- [ ] File headers, `patrol_drone_controller.gd` first, then
      `idle_npc_controller.gd`: purpose and invariants only, ceiling ~25 lines.
      Anything starting "this used to" or carrying a measurement date moves to a
      post-mortem. **Comment-only commit — verify with `git diff --stat` that no
      logic line was touched.**

**Done when:** `docs/postmortems/` holds at least four files, `CLAUDE.md` is under
10 KB, both controllers are under 30% comment, no behaviour changed.

---

## Task 5 — Actor identity contract — **PAPER ONLY, NO CODE**

**Why this exists and why it is here.** Stan's own judgement: reusing pooled
agents can break NPC memory retroactively. Correct. The conclusion is not that
memory is risky, it is that the identity contract must be decided **before**
memory is built, so memory is built against the right one and spawn later only
fills it in.

`IncidentRegistry` stores incidents against stable `actor_id`s — that is its
foundation, it gave up holding `Node3D` references specifically to get them. But a
pooled agent is a different person every time it is re-targeted: one node is a
passer-by at the market now and a vagrant in another district a minute later.

Three candidate models, to be argued and chosen **in chat with Stan**:

1. **Identity in the pool.** The agent gets a fresh `actor_id` on activation, the
   old one is dead forever. Consequence: the witness you punched ceases to exist
   when the block unloads, and the incident loses its carrier of memory.
2. **Identity in the block.** `BlockData` holds a list of stable resident ids; a
   pooled agent wears one. Consequence: the same passer-by returns to the same
   place and the city becomes recognisable, but every district must store a
   population.
3. **Hybrid.** Ambient crowd is anonymous and gets no id at all; named and
   "involved" characters are promoted into a separate persistent category.

Model 3 is exactly the Ephemeral / Persistent / Simulated / Global classification
H7 exists for — which is why H7 is not derivable today and comes after this.

- [x] Write the three models, their consequences and the recommendation into
      `docs/architecture/npc_and_incidents.md` as a new section
- [x] Stan chooses one; the chosen one is stated in `CLAUDE.md` as **one
      invariant paragraph**, present tense, no argument text
- [x] The two rejected models go to `docs/postmortems/actor_identity.md`

**Done when:** the contract is written and chosen. **Zero lines of GDScript in
this task.**

---

## Task 6 — OBSERVE and ADAPT: make the existing eighteen NPCs into gameplay

**This is the horizon, ahead of spawn.** The reasoning, so it is not
re-litigated: the project's largest risk is a knowledge model without a loop under
it. Growing the crowd does not close the loop — twenty-four unreadable placeholders
carry exactly as much information as eighteen, which is none, and twenty-four NPCs
who forget everything on a timer adapt exactly as much as eighteen, which is
nothing. Both can be built and measured on the existing hand-placed diorama, where
the witness chain is already tuned. Spawn then scales something that works instead
of something empty.

Do **not** design this as one block. Bring a proposal per sub-item.

### 6a. Readability — OBSERVE

Today an archetype is colour, speed and a flee bias. `observation_level` is
written, and read **only** by the perception debug panel and one log line — no
reaction is differentiated by it.

> **[corrected 2026-09-03]** The plan originally said `observation_level` is
> "written and read by nothing". It is written by
> `IdleNPCController._resolve_observation_level()` and read by
> `perception_debug_panel.gd` and one log line. The actionable half of the claim
> stands unchanged: nothing in gameplay is differentiated by it.

- [ ] ~~Proposal: what makes two archetypes distinguishable at 30 m, at 10 m and
      at 5 m~~ — **deferred (Stan, 2026-09-03): readability by rig is a separate
      art task and probably falls outside September.** `docs/3D_ART_BIBLE.md`
      silhouette → primary → secondary hierarchy remains the constraint when it
      is picked up.
- [ ] Make `observation_level` change at least one reaction. One is enough — the
      point is the channel existing, not its breadth.

> **[unblocked 2026-09-03]** This collided with `incident_knowledge_model.md`
> §8 ("must stay unread until Attribution exists"). Not a contradiction to
> pick a winner from: §8 banned more than its own reason in §3.3 supports.
> The reason bites when a reaction reads `observation_level` as a proxy for
> how identified the PLAYER is — Attribution done informally in a controller —
> and not when a witness reads its own look quality to change its own
> behaviour. §8 is narrowed to that; Stan, 2026-09-03. Task 6b's memory
> duration is the first consumer.
- [ ] Retest the five `attribution.md` §7 cases; case C is a known gap, say
      whether it moved.

**Consequence, stated so it is not forgotten in a month: OBSERVE closes only half
in September.** The channel starts working; archetype distinguishability does not
appear. Do not record OBSERVE as done on the strength of this task.

### 6b. Memory that survives an encounter — ADAPT

Today ALERT dies on a timer and nothing outlives the encounter. With 6a halved,
**this is the main substantive work of September** — it is what produces the one
measurable result: punch someone, walk away, come back, the world is different.

- [ ] Proposal: what a single NPC remembers, for how long, and in what unit
      (game-hours, per `GameClockSystem` — not engine uptime, per the
      `IncidentRegistry` precedent). Keyed on the identity model chosen in Task 5.
- [ ] One consequence that survives a block unload and a save/load round trip
- [ ] No propagation between NPCs in this task. One NPC remembering is the slice.

**Done when:** Stan can punch someone, walk away, come back, and the world is
different in one readable way.

---

## Task 7 — NPC spawn on the streaming conveyor

**State.** No streamed block contains an NPC. All 18 live NPCs are hand-placed in
`world.tscn` under `DoggerlandCrowdBlock`, whose own `editor_description` says to
remove it once a spawn system exists. The island is 3500×2500 m; the crowd exists
within about forty metres of one point.

Shape to propose, from established practice, not invention:

- Fixed live-agent budget (start at 24), pre-created pool, **re-target rather than
  `instantiate()`**. `NPCBase` is mesh + skeleton + `AnimationTree` +
  `PerceptionComponent` + collision; instantiating that at runtime competes with
  `StreamingSystems`' `INSTANTIATION_BUDGET_PER_FRAME`, which already queues cells
  one per frame. This is where the object pool earns its place: a named pain, not
  a speculative utility.
- Density and mix read from `data/npc_archetypes/` and `docs/npc_archetypes.md` §5,
  keyed off `BlockData`, not off a district name in dialogue.
- Spawn/despawn on distance and view frustum; standard despawn-out-of-view-beyond-
  minimum-distance rule.
- Rides the existing Ring 0 / Ring 1 conveyor. No parallel mechanism. **No autoload.**
- `actor_id` follows whatever Task 5 decided. If it does not fit, Task 5 was wrong
  and gets reopened — do not improvise around it.
- `DoggerlandCrowdBlock` stays untouched until this works, then is deleted. Do not
  migrate it; it is a test diorama, not content.

- [ ] Written proposal
- [ ] Stan approves
- [ ] Build

---

## Task 8 — H7 persistent entity state

Now derivable, because Task 5 chose the identity model and Task 7 produced real
ephemeral objects to classify against. Doors, named NPCs, dropped items surviving
block unload and save/load.

---

## Out of plan

Recorded here so they have somewhere to be, and so nobody mistakes them for
scheduled work.

**Sound.** Extra-scope, taken up in free time, not sequenced. Two conditions when
it happens: (1) `docs/visual_language.md` first records which onomatopoeia survive
the arrival of audio — `ComicEffectSystem` currently stands in for sound, and after
audio each word is either duplication or reinforcement, which is a decision, not a
consequence; (2) `SoundSystems` as an autoload is an **explicit, argued amendment**
to the closed set in `CLAUDE.md`, not a quiet exception — audio is needed before
`world.tscn` exists (main menu) and cannot reach the menu through `WorldContext`.
Do not start either without Stan.

**`WorldState` / `EventOrchestra`.** Not started. Goes to `docs/planned_scope.md`
with its prerequisite named: **name three concrete couplings that `WorldContext`,
a signal and a group cannot express.** There is no such case today, and a global
event bus was already considered and rejected. `PlayerState` is already the single
source of truth for modes; a second state object risks the parallel enum set
`CLAUDE.md` forbids. If three cases can be named after Task 7 ships, the design
conversation starts then.

**MENU pause — no longer a defect, one open design question.** `get_tree().paused`
**is** set, in `player_state.gd:77` / `:86`, and the exemptions around it are
deliberate: `GameClockSystem` stays on `PROCESS_MODE_INHERIT` on purpose so game
time does not run behind the menu, `InputSystems` and the menu tree are
`PROCESS_MODE_ALWAYS`. Nothing to fix. What stays open is a design question for
later: `StreamingSystems` is an autoload with a default `process_mode`, so its
polling halts under pause. That is correct today and becomes wrong the day an
inventory has to run over a live world. Not scheduled, no code, revisit when
inventory UI is on the horizon.

> **[corrected 2026-09-03]** This item originally read "`get_tree().paused` is set
> **nowhere** … so the world keeps simulating behind the menu", and was written up
> as a defect. The premise was false — it is set in `player_state.gd:77`/`:86` —
> so the whole paragraph was replaced rather than footnoted.

---

## Sequence

```
0. NOW.md handoff              30 min, first
1. Close H6                    Stan, eyes required
2. Physics interpolation       independent, may run alongside 1
3. CI checks                   independent, may run alongside 1
4. Docs by genre               BEFORE 6, so the next big system is written new-genre
5. Actor identity contract     paper only, no code
6. OBSERVE + ADAPT             the horizon
7. NPC spawn                   scales what 6 made work
8. H7 persistent entities      now derivable
```
