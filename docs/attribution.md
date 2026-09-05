# Observation and attribution — design specification

This page is the design the witness chain is built against. It is not a task
list and most of it is not scheduled. Only §7 is currently in the horizon.

It exists for the same reason `NPC_REACTIONS.md` does: this design was settled
in discussion and would otherwise live outside the repository, where a
contributor — or a future session — could not find it. Everything below §7 is
deliberately unbuilt and must stay that way until §7 has been played and
judged.

Read `core_loop.md` (§6 in particular) and `NPC_REACTIONS.md` (§4, §4a, §5)
first. This page extends both.

Last reviewed: 2026-08-16

---

## 1. The chain

The central design decision: a witness does not know who committed a crime. A
witness knows what they saw. The city decides what follows from it.

```
NPC
 │  observes
 ▼
OBSERVATION        what the eyes and ears actually got
 │  qualifies
 ▼
INCIDENT           an objective fact: A struck B, here, then
 │  witness transmits
 ▼
REPORT             a statement, held in the registry
 │  city processes
 ▼
ATTRIBUTION        evidence matched against known identities
 │
 ▼
KNOWN or UNKNOWN ACTOR
```

Each arrow is a place where information can be lost, delayed, degraded or
contested. That is the point. The conventional alternative —

```
player commits crime → wanted += 1 → police pursue
```

— collapses all four stages into one and leaves nothing for the player to act
on between them.

The gap between REPORT and ATTRIBUTION is where this project's thesis lives.
The city registers and attributes; humans read the record lazily. A statement
can sit unprocessed. In Doggerland, for a long time. In Glare, instantly.

**Two boundaries that must not blur:**

- OBSERVATION is not CRIME. The NPC reports a physical fact, not a judgement.
- REPORT is not IDENTIFICATION. Transmitting a statement is not naming a person.

---

## 2. Observation quality

What a witness got is a single value, resolved once, at the moment of the
incident. It does not improve afterwards — a witness cannot walk closer and
retroactively recognise a face.

```
NONE  <  SILHOUETTE  <  PERSON  <  EQUIPMENT  <  FACE  <  IRIS
```

Naming note: the top level is `IRIS`, not `IDENTITY`. The NPC observes a
credential, not a person. Identity is produced later, by attribution, from
that observation. Getting this wrong in naming leads to getting it wrong in
architecture.

**The top rung needs a MECHANICAL observer.** Reading a retina is exclusively
mechanical — a human tops out at a face and photographs the rest on their
Votive. `ActorBase.can_read_iris()` now enforces that cap on the shared distance
ladder: a human inside the nearest band resolves `FACE`, while a synthetic or
robot may resolve `IRIS`. See `docs/blackrock_authorities.md` §0.

### Distance sets the ceiling

| Distance | Maximum achievable |
|---|---|
| > 11 m | SILHOUETTE |
| 6–11 m | EQUIPMENT |
| 3–6 m | FACE |
| ≤ 3 m | IRIS for mechanical observers; FACE for humans |

### Not seeing it and seeing it worse are different cases

The first pass at this page collapsed two different things into one
`REDUCED` bucket, and playtest caught it immediately: a witness with their
back turned still became a witness, just one step down the ladder. That is
wrong in kind, not in tuning. Facing away is not reduced attention — it is
not seeing the incident at all.

- **Did not see it.** Outside the vision cone, blocked, back turned. The
  result is `NONE`. This witness does not become a witness for this
  incident — nothing is reported, at any quality, because there is nothing
  to report.
- **Saw it, but worse.** Inside the cone, but occupied — talking to another
  NPC, looking into their own Votive projection. The result is one level
  below whatever distance alone would have given.

Only the first case is gated in this iteration: a witness must be within
range and within the vision cone (no line-of-sight check — that is a
separate, already-broken raycast issue in `PerceptionComponent`, not this
gate's to fix) or they never become a witness at all. **Attention itself is
not applied.** Its only two real triggers — talking, looking into one's own
Votive — have no mechanic to derive them from yet in this build; standing in
"facing away" for them was the original mistake, not a workable
approximation. Every witness who clears the vision gate gets the distance
ceiling as-is. Add the `REDUCED` step back once a real busy-trigger exists,
not as a repurposed vision check.

### Attention can only lower it

This asymmetry is a hard rule, not a tuning choice, for whenever attention
does get built: it never raises the ceiling — a witness at 20 m cannot reach
IRIS however alert they are. Without this rule the system becomes an
unpredictable product of factors and cannot be debugged by eye.

Further inputs — obstruction, lighting, hearing, orientation as a continuous
value — are deliberately deferred beyond even `REDUCED` itself. Six weighted
inputs produce a result no one can explain during playtest: *why* did this
witness fail to recognise a face? Add them only if binary attention proves
insufficient in play, one at a time.

**Being busy does not blind an NPC.** A witness talking on their Votive still
sees a man struck in front of them. They see it worse. Anything that gates
perception outright on activity reads as an engine rule rather than a person.

---

## 3. Saw versus understood

An NPC can see an event without understanding it.

What is observed is physical:

```
person A, person B, physical contact
```

What that *means* — assault, brawl, self-defence, accident, performance — is a
separate layer, and it belongs to the city, not the witness. Keeping the two
apart buys two things for free: a witness can be wrong about what happened, and
the city can read a correct statement badly.

First iteration collapses this: an incident is objectively an incident and the
witness reports it as such. The seam must exist in the data even while the
classification layer does not — the report carries what was seen, and nothing
that presumes what it meant.

---

## 4. The report

A `WitnessReport` is a statement, not a conclusion. It never contains a
suspect.

```
WitnessReport
├── witness_id
├── observation_level        SILHOUETTE … IRIS
├── observed_equipment       what the actor was wearing/carrying, if seen
├── observed_at              game time
├── observed_from            position, for later line-of-sight reasoning
└── status                   PENDING / COMMITTED / CANCELLED
```

An `Incident` accumulates reports:

```
Incident
├── event_type
├── location
├── timestamp
├── victim
└── reports[]
```

Nothing in either structure names the player. The registry holds what the city
was told, not what the city concluded.

---

## 5. Attribution — deferred, and this is the expanded form

Not scheduled. Written down so it is not re-derived from scratch later, and so
that §7 can be built without foreclosing it.

**Who does this has a name now: BRMA, the Blackrock Marshal Authority** — see
`docs/blackrock_authorities.md`, which also names its lower rung (BRPD: the
drones and the `Patrolman` archetype that already exist) and the iris
credential as a seam. Naming the actor does not schedule the system.

Attribution takes the reports on an incident and attempts to resolve an actor.
It is a separate system with a one-way dependency: it reads the registry, the
registry knows nothing about it.

What makes it worth building, in order of importance:

**It gives eye replacement a real cost model.** Changing a credential is
expensive, illegal, and wipes name, wallet, status and access. Today that is
narrative. Under attribution it becomes a calculation the player can actually
make: *how much of me is already in the system, and at what quality?*

- A report at 20 m holds `male, dark coat, weapon, height` — none of it tied to
  a credential. Changing eyes does not touch it.
- A report at 7 m holds a face. Changing eyes weakens the link but the face is
  still a face.
- A report at 3 m holds an iris. That one dies with the old credential.

**Old incidents are never deleted on credential change.** The prior identity is
archived, not erased. The new one is active. Whether the city connects them
depends on what the reports contain — which is exactly the tension the whole
design is for.

**Behavioural signature is the endgame, not the start.** Identity can be faked;
behaviour cannot. Once reports accumulate, a pattern — how the player enters, how
often they kill, what they take — can link an archived identity to an active one
without any credential at all. This is the mechanical form of the project's
central claim, and it is also the easiest thing to over-build. It is named here
and nothing more.

**Timing is stratum-dependent.** Attribution is not instant. Doggerland reports
may sit unprocessed indefinitely, or be discarded. Glare resolves in seconds.
This is the same gradient as surveillance density and Votive connection speed —
one idea expressed three times, which is why it reads as a world rather than as
three systems.

Open questions, not to be answered now:

- Does contradictory testimony exist, and can it be exploited?
- Can the player influence what gets processed, rather than only what gets
  reported?
- Does a wrongly attributed identity — someone else charged — become available
  as a move?

---

## 6. Votive as the visible layer

The Votive is a communication terminal, worn at the right temple, projecting
a hologram in front of the face. It is not a credential and must never act as
one. The eye opens; the Votive shows.

```
EyeCredential                    VotiveTerminal
    identity_id                      communication_state
    access_profile                   projection_state
    wallet                           current_call
    permissions
```

Game code must not let these two touch.

Default state is a steady blue projection on every human. That baseline is what
makes the alert state legible: if only human witnesses lit up, any light would
mean trouble and there would be nothing to read against. Synthetics and robots
do not own Votives; their projector carrier node allocates no visual resources.

Transmission reads as:

```
blue … blue … RED · off · RED · off · RED · SOLID
                └──────── ~3 s ────────┘
```

Three flashes are a countdown the player can literally count, with no UI. This
is the escalation principle of `NPC_REACTIONS.md` §3 applied to the report
chain: the city shows its attention before acting on it.

The three seconds are **time until transmission completes**, not "time to kill
the witness". The distinction matters: it leaves room for interrupting,
fleeing, breaking line of sight, or deciding the report is not worth what
stopping it would cost. If the only viable answer is always violence, the
window is a punishment rather than a decision.

Stratum gradient, same idea again: Doggerland connections are slow and some
fail outright; Glare is near-instant and cannot be interrupted. Caution in the
upper city is taught by the mechanism, not stated.

**Suppressing a witness is itself an incident.** Nothing special is needed for
this — attacking a witness is an assault, and assaults have witnesses. The
recursion should be allowed to happen rather than designed: the city keeps
functioning, and cleaning up creates more to clean up.

Whether the Votive later becomes a slot on `EquipmentComponent` (H5) is an open
question deferred on purpose — it is worn by every human and is not meant to be
removable in this first iteration, so it does not belong to the same
"what's held, what's stowed" contract equipment governs. Revisit once H5 exists
and the witness chain already works, not before.

---

## 7. What is actually being built — the vertical slice

Everything above except this section is deferred.

```
NPC perception
    ↓
incident observed?
    ↓
observation quality resolved (distance ceiling, attention modifier)
    ↓
calling archetype + human-owned Votive?
    ↓
WitnessReport created
    ↓
Votive: blue → red/off ×3 → solid red
    ↓  3 s
COMMITTED  or  CANCELLED
```

**`observation_level` is written and nothing reads it.** This is intentional
and must be stated plainly wherever it might look like an oversight: the field
is a deferred output, not dead code. The system is permitted to know more than
the game can currently show — but only because §5 exists on this page. Without
a written design behind it, a field nobody reads is speculative generality.

**No drone reaction differentiated by observation level.** Adding one now would
turn the test from "does the witness chain work" into "does mini-attribution
work", and every rule added there invites the next: what about two witnesses,
one with a face and one with a silhouette? That is §5, and §5 is not scheduled.

**Developer-only observation panel**, not a log line. During playtest it should
be possible to look at a witness and see why they got what they got:

```
WITNESS
  distance   7.4 m
  in FOV     true
  ceiling    FACE
  result     EQUIPMENT

REPORT
  observed   EQUIPMENT
  actor      UNRESOLVED
  status     PENDING (1.8 s remaining)
```

No `attention` line: this iteration doesn't apply it (§2's own correction) —
`in FOV` is the only gate that's real today. `ceiling` and `result` still
both show because they will differ again the moment a real attention
trigger lands; today they're always the same number.

The player never sees this. It is the only practical way to debug a perception
rule by eye.

### Test cases

| Case | Setup | Expected |
|---|---|---|
| A | incident 2 m from a human Clerk facing it | FACE |
| B | 7 m | EQUIPMENT |
| C | 12 m | SILHOUETTE |
| D | 2 m, witness facing away | does not become a witness — no report at any quality |
| E | interrupted at 1.5 s | CANCELLED, nothing in registry |

The dated measurements below preserve the synthetic-Clerk configuration that
was live when they were taken. Since 2026-09-05 all placed Clerks are human, so
their current nearest-band acceptance result is `FACE`; the old `IRIS` rows are
history, not the present contract.

**The distances moved on 2026-09-04 and the old ones are not a lost baseline** —
they were 3 / 15 / 35 m, chosen against ceilings of 5 / 10 / 30 that put
SILHOUETTE past 30 m while no witness can see past 16. Case C was therefore
untestable from the day it was written, which is what the two dated blocks below
record. The ceilings are now 3 / 6 / 11 and every rung has a band inside the
envelope, so these five sample the ladder that actually exists.

### Measured, 2026-08-26

Run against a Clerk (`data/npc_archetypes/clerk.tres`) in a throwaway probe
scene, driving `IdleNPCController._on_incident_reported()` directly and
reading the same debug getters the observation panel uses.

| Case | Expected | Measured | |
|---|---|---|---|
| A — 3 m, facing | IRIS | `CALLING`, ceiling IRIS, result IRIS, in FOV | pass |
| B — 15 m | EQUIPMENT | `CALLING`, ceiling EQUIPMENT, result EQUIPMENT | pass |
| C — 35 m | SILHOUETTE | no reaction at all, no report | **fails — see below** |
| D — 3 m, facing away | no report at any quality | no report; falls through to the ordinary Freeze/Flee roll | pass |
| E — interrupted at 1.5 s | CANCELLED, nothing in registry | `WitnessReport.status = CANCELLED`, reaction returns to `NONE` | pass |

Two boundary probes beyond the table: 12 m gives EQUIPMENT; **20 m gives no
report at all**.

**Case C cannot pass under current tuning, and the reason is arithmetic, not
a defect in the chain.** SILHOUETTE requires
`distance > witness_ceiling_equipment_distance` (30 m). But two earlier gates
close first:

- `IdleNPCController.earshot_radius` is 25 m — past it an ordinary NPC never
  learns an incident happened;
- the witness gate itself uses the archetype's
  `PerceptionComponent.vision_range`, which for Clerk — the only calling
  archetype — is 16 m.

So the reachable witness envelope for a Clerk is **0–16 m**: IRIS ≤ 5,
FACE 5–10, EQUIPMENT 10–16. The SILHOUETTE rung, and the top of the
EQUIPMENT band, are unreachable by construction — the ladder is taller than
the room it stands in. Closing the gap is a tuning decision (raise earshot
and archetype vision above 30 m, or lower the ceilings under 16 m), not a
code change, and it is deliberately deferred: see `scope_horizon.md`,
H3 / H4 refinement.

One observability note, not a behaviour one: `_cancel_active_witness_report()`
nulls `_current_witness_report` after setting CANCELLED, so the panel shows
`n/a` rather than the terminal status. The cancellation itself is correct —
case E was confirmed by holding a reference to the report across the
interrupt.

Case D's reaction varies between runs (FROZEN or FLEEING). That is
`NPCArchetypeData.flee_probability` doing its job, not flakiness — §4 of
`NPC_REACTIONS.md` is explicit that the crowd reacts by chance.

Case D changed from an earlier draft ("witness talking", one level below
IRIS): §2's own correction applies here too. Facing away is the one gate
this iteration actually implements, and it means not seeing the incident,
not seeing it worse — there is no report to hold a level at all. A witness
who is genuinely talking (not built) would still be tested against D's old
expectation once that trigger exists; today D is the only concrete,
reproducible test of the vision-cone gate itself.

### Re-measured, 2026-09-04 (work plan Task 6a)

Same method as the block above — a throwaway probe driving
`IdleNPCController._on_incident_reported()` directly and reading the same debug
getters — so the two are comparable rather than obtained different ways. Run
against `Clerk1`, with the player parked 300 m away so `_decide()` could not
interfere except where it is being tested.

| Case | Expected | Measured 2026-09-04 | |
|---|---|---|---|
| A — 3 m, facing | IRIS | `CALLING`, ceiling IRIS, result IRIS | pass, unchanged |
| B — 15 m | EQUIPMENT | `CALLING`, ceiling EQUIPMENT, result EQUIPMENT | pass, unchanged |
| C — 35 m | SILHOUETTE | no reaction, no report | **still fails, unchanged** |
| D — 3 m, facing away | no report at any quality | no report; `FROZEN` this run | pass, unchanged |
| E — interrupted at 1.5 s | CANCELLED, nothing in registry | held report `CANCELLED`, panel `n/a` | pass, unchanged |

Boundaries: **12 m gives EQUIPMENT**, **20 m gives no report** — both unchanged.
D and the 20 m boundary landed on different reactions across two runs of this
same probe (`FLEEING` once, `FROZEN` once), which is `flee_probability` = 0.30
doing its job and was already called out above; it is recorded here as observed
rather than assumed.

**Case C has not moved, and could not have.** Nothing since 2026-08-26 touched
`vision_range`, `earshot_radius` or the ceilings. The envelope is still 0-16 m.

**The reachable ladder, measured by sweep rather than reasoned from the
constants:**

| distance | ceiling reached |
|---|---|
| 1, 3, 5 m | IRIS |
| 7, 10 m | FACE |
| 12, 14 m | EQUIPMENT |
| 16 m and beyond | nothing at all |

So the witness path can produce **IRIS, FACE and EQUIPMENT, and never
SILHOUETTE**. That has a consequence outside this document: `ActorMemoryRegistry`
maps `observation_level` to a memory lifetime, and its `SILHOUETTE` row (6 game
hours) is **dead on the witness path** — the only way to reach it today would be
a producer other than witnessing.

**New since the last block: a memory now stops a witness from being one.**
`_on_incident_reported()` has always returned early on
`_reaction_state != ReactionState.NONE` — that gate is old and was documented.
What Task 6b changed is that an NPC now has a *durable, self-triggering* reason
to be in that state: it remembers the player and `_decide()` sends it to
`FLEEING` on sight. Demonstrated end to end rather than asserted — a memory was
filed, the player was walked into view, `_decide()` reached the memory branch on
its own (`FLEEING`), and the incident that followed produced **no report**.

Whether that is right is a design question, not a defect: a frightened witness
running away instead of phoning it in is arguably correct, and it also means
**the same NPC cannot testify about you twice**. Not decided here.

### Re-measured after the ceiling retune, 2026-09-04

Stan's call: lower the ceilings rather than raise the vision. Now
`iris <= 3`, `face <= 6`, `equipment <= 11`, against Clerk's unchanged 16 m
`vision_range` and unchanged 25 m `earshot_radius`.

**Every rung is reachable now — swept, not argued:**

| distance | rung |
|---|---|
| 1, 2, 3 m | IRIS |
| 4 m | FACE |
| 6, 7, 9 m | EQUIPMENT |
| 11, 12, 14, 15 m | **SILHOUETTE** |
| 16 m and beyond | nothing (vision gate) |

| Case | Expected | Measured | |
|---|---|---|---|
| A — 2 m, facing | IRIS | `CALLING`, IRIS | pass |
| B — 7 m | EQUIPMENT | `CALLING`, EQUIPMENT | pass |
| C — 12 m | SILHOUETTE | `CALLING`, SILHOUETTE | **pass — first time** |
| D — 2 m, facing away | no report | no report; `FROZEN` this run | pass |
| E — interrupted at 1.5 s | CANCELLED | not re-run: it tests cancellation timing, which no distance threshold touches | unchanged |

At the OLD sample distances the retune reads as: 3 m still IRIS, **15 m becomes
SILHOUETTE** where it used to be EQUIPMENT, and 35 m still produces nothing —
now because it is past the 16 m vision gate rather than because the ladder ran
out. That is why the case distances in the table above moved with it.

**Case C passes for the first time since it was written.** The gap was never in
the chain; the ladder was taller than the room it stood in.

**Consequence outside this document:** `ActorMemoryRegistry`'s `SILHOUETTE`
lifetime row is no longer dead — the witness path reaches it between 11 and
16 m. Its value moved the same day, from 6 to 12 game hours, as part of putting
that table on a clean x3 progression.

### The test that actually matters

The registry is the lesser half. The real question is behavioural, and it is
about the person holding the mouse:

1. After the first incident — did they notice the red temple?
2. After the second — did they work out that red means transmission?
3. After the third — did they start looking for *who* is transmitting?
4. After several — do they move to interrupt it without being told to?

If step 4 happens unprompted, the loop has a core. If it does not, that is
worth knowing after one alley and twenty NPCs rather than after a year of
police, identity archives and behavioural profiling.

---

### What a committed report now does

Committing is no longer a bookkeeping event. A report that reaches
`IncidentRegistry` marked as a witness transmission dispatches the city to
the place it names: every drone breaks patrol and flies there from wherever
it is, and any responding archetype (Patrolman) runs to it — neither gated
by the distance that governs what a unit notices on its own. See
`NPC_REACTIONS.md` §4.

This is the first thing in the build that makes the three seconds of
transmission cost something to the player, and therefore the first thing
that makes suppressing a witness mid-transmission a decision rather than a
curiosity.

It is deliberately *not* yet differentiated by observation quality.
`observation_level` is still resolved, carried on the `WitnessReport`, and
read by nobody — the responders come, but they come the same way for a
report that saw a face and one that saw a coat. Making the response differ
by what was actually observed is §5's work, and it is the shortest path from
this page's model to a mechanic the player can play against.

## 8. Terminology

| Term | Means |
|---|---|
| Iris Access | The city's identity system. The eye is a key to a cloud record, not a store of data. |
| credential | The eye. Opens things. Passive — you are read, not asked. |
| Votive | The temple terminal. Shows things. Active, visible, never a credential. |
| observation | What a witness got. Physical, not interpretive. |
| report | A transmitted statement. Never contains a suspect. |
| attribution | The city resolving reports into an identity. Deferred. |
