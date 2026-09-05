# Blackrock authorities — BRPD, BRMA, and the iris

**Design specification with implemented nature, Votive and walking-pair seams.**
Actor nature, the perception ceiling and the two walking BRPD pairs described
below are built; BRMA / `IrisAccess` remain design. Named here so the larger shape is decided before anything is
written against it, the same way `docs/attribution.md` §5 records Attribution
without scheduling it. Where this describes something that already exists, it
says so and names the file.

`CLAUDE.md` and `docs/architecture/*` stay authoritative for what is built.
This document remains authoritative for the unbuilt authority design.

---

## 0. Not everyone here is human

Blackrock has **humans, synthetics and robots**, and that is not flavour — it
decides **what an actor can perceive**, which is the currency this whole design
trades in.

**Reading a retina is exclusively mechanical.** A terminal can. A camera can. A
drone can, up close. A police robot can. A synthetic clerk can. **A human
cannot** — a human can only look at a face, and photograph the scene on their
Votive.

For the player that is one sentence: **people remember your face, machines know
your name.**

### Nature is a field, not a sixth archetype

`NPCArchetypeData` describes a ROLE — vagrant, thug, commuter, clerk,
patrolman. **Nature is orthogonal to it**: a clerk can be human or synthetic
and behaves the same either way; what changes is the ceiling of what it can
observe. Folding nature into the archetype list would double that table for
every nature added, which is the signature of the wrong axis.

Built contract: `ActorBase.Nature` contains `HUMAN`, `SYNTHETIC` and `ROBOT`;
its exported `nature` defaults to `HUMAN`, and `can_read_iris()` is true for
the two mechanical natures. The field is authored on the concrete actor scene
or instance, not on `NPCArchetypeData`.

| archetype | nature | why |
|---|---|---|
| Clerk1–Clerk4 | **human** | current callers; Votive-equipped and capped at FACE |
| Patrolman1 / Patrolman2 | human | leaders of the two walking BRPD pairs |
| Patrolman3 / Patrolman4 | robot | mechanical followers in those pairs |
| police drone | robot | mechanical by construction already |
| Vagrant, Thug, Commuter | human | crowd background; ceiling FACE |

### This is why `IRIS` is legitimate today

`IdleNPCController._distance_ceiling()` returns **`IRIS`** inside 3 m only when
the observing actor's `can_read_iris()` is true. A human at the same distance
is capped at `FACE`. `NPCArchetypeData.is_witness_caller` is true for Clerk and
nothing else, while `ActorBase.has_votive()` is true only for humans. A Call
requires both contracts, so the four human Clerks report at no better than
`FACE`; robot Patrolmen may observe `IRIS` but cannot transmit it themselves.

The executable rule is therefore asymmetric: **people report what they saw;
machines can know more, but have no Votive channel.** Attribution still decides
whether a human report can eventually be tied to a person.

One appearance for every character is a prototype convenience and does not
collide with any of this: nature is a field in data, not a silhouette.

---

## 1. Two rungs, and the difference is what they know

**BRPD — Blackrock Police Department.** Rank and file, drones, cameras. The
lower rung. **It responds to a PLACE.**

**BRMA — Blackrock Marshal Authority.** Marshals, working as detectives. The
upper rung. **It resolves a PERSON.**

That is the whole distinction and everything else follows from it:

| | BRPD | BRMA |
|---|---|---|
| answers | *where did it happen* | *who did it* |
| input | an incident's position | the reports about it |
| speed | immediate | slow, and stratum-dependent |
| bound by | a radius | an archive |
| exists today | **half of it** | no |

Neither writes into the other's record. Both read `IncidentRegistry`, which is
already the city's own memory and already keys on a stable `actor_id`.

## 2. BRPD is half-built and was never named

These are BRPD already, they simply have no word for the organisation:

- **`PoliceDrone.tscn` / `PatrolDroneController`** — patrol, ALERT, the four
  paths by which a drone learns of an incident, and the dispatch that breaks
  patrol and flies to the point a committed witness report names.
  → `docs/architecture/npc_and_incidents.md`
- **The `Patrolman` archetype** — the walking half of BRPD and a moving no-go
  zone. It is the only archetype
  with `responds_by_approaching`, which is exactly BRPD behaviour: it runs to
  the place, it does not work out who.

### BRPD walks in pairs, and the pair is two different sensors

**Always two: one human and one robot.** That is a fiction rule with a
mechanical consequence, which is why it is worth holding rather than decorating
with.

**A BRPD pair is one witness who can see your face and one who can read your
iris.** Being seen by the human half and being seen by the pair are therefore
different events at different prices. A patrol stops being a moving no-go zone
and becomes **two sensors that can be separated** — which is a far more
interesting thing to route around.

The robotic half is a walking Patrolman, not a drone. `patrol_partner_id`
authors the reciprocal pairs `1 ↔ 3` and `2 ↔ 4`: the human selects the route,
the robot holds the side slot, and either member falls back to solo behaviour
while the other is missing or down. Police drones patrol independently as
separate BRPD units.

What is missing from BRPD is **cameras** — static sensors with no patrol and no
reaction, whose only output is that they saw. A camera is the cheapest possible
BRPD unit and the one that makes surveillance density a real gradient rather
than a word.

**The defining constraint, and it is already true in code:**
`attribution.md` records that a committed report "dispatches the city to the
place it names… neither gated by the distance that governs what a unit notices
on its own". BRPD is dispatched to coordinates. It never receives a suspect.

## 3. BRMA is the face of the Attribution that §5 already deferred

`docs/attribution.md` §5 describes, in full and without scheduling it: reading
the registry to resolve an actor, the cost model for changing a credential,
archived versus active identity, behavioural signature as the endgame, and
processing time that varies by stratum. **BRMA is who does that.** Naming the
actor does not schedule the system; it stops the system being re-derived from
scratch when it is scheduled.

Two properties worth carrying over verbatim, because they are what make BRMA
feel like an institution rather than a timer:

- **Old incidents are never deleted on credential change.** The prior identity
  is archived, not erased.
- **Timing is stratum-dependent.** Doggerland reports may sit unprocessed
  indefinitely; Glare resolves in seconds. The same gradient as surveillance
  density and Votive speed — one idea said three times, which is what makes it
  read as a world rather than three systems.

## 4. IrisAccess — a credential, not a key

The iris is already in the fiction as **the credential the city reads**.
`attribution.md` §5: changing one "wipes name, wallet, status and access", and
"a report at 3 m holds an iris — that one dies with the old credential".

### Two sides, and they must not be confused

- **The reader** — `IrisAccess`, the seam that says "I can read a credential".
  **Mechanical only**, per §0. Mounted anywhere in the world: a camera, a
  terminal, a door, a vending machine, a hover door, a bus, the metro, a
  pneumatic tube. The project already has a precedent for a thing-in-the-world
  you deal with — `InteractableObject` — and this is the same shape with a
  different question.
- **The credential** — the eyes. **Every character carries one**, human and
  synthetic alike. It is what gets read.

A robot has **both**. A human has only the credential. A door has only the
reader. Neither derives from the other and neither collapses into the other —
writing that down because a single "IrisThing" is the obvious wrong turn.

`IrisAccess` is therefore the **seam where something demands that credential**:
a door, a terminal, a transit gate, a Marshal with a scanner. Abstract because
those have nothing else in common.

### What it must not become

**A boolean.** "Opened / refused" throws away the thing this project is built
on — `incident_knowledge_model.md` §2 invariant 5 puts the gameplay in the
*quality* of what is known. A check that only gates a door is a lock; a check
that also records is a system.

### The reading that makes it worth having

**Every check is also an observation, at the top rung of a ladder that already
exists.** A scanner reads an iris — which is `WitnessReport.ObservationLevel`'s
`IRIS`, the same value a witness gets at three metres and never gets further
out.

So **a door is a perfect witness**: it sees you at maximum quality, every time,
without a cone, without a distance falloff and without forgetting. That makes
`IrisAccess` a second *producer* for records that are already built, rather
than a system of its own — and it gives the player a reason to care which doors
they use, which is the same currency the witness chain already trades in.

### Why this does not break invariant 2

`incident_knowledge_model.md` §2 invariant 2 says a report never contains a
resolved actor identity — identity is produced later, by Attribution, from the
contents of reports.

**A scanner does not attribute. It reads.** Nothing is inferred, nothing is
matched across reports, no confidence is involved: the credential is presented
and the credential is what it is. That is a different act from Attribution, and
the invariant is about the other one. Written down here because the two look
similar from a distance and someone will otherwise "fix" it.

## 4b. The Votive is the human's channel

`VotiveProjector` (`core/components/votive_projector/`) is today the **visible
half** and says so itself: state (`IDLE`/`TRANSMITTING`/`DARK`) plus a
representation of it, "no `communication_state`, no `current_call`, **no
identity binding**". Both `npc.tscn` and `player.tscn` contain the carrier node,
but only a human owner activates it. Synthetic and robot
owners allocate no projection mesh or material, and its state calls are no-ops.

Under §0 it acquires a meaning it did not have: **the Votive is what a human
uses INSTEAD of reading a retina.** It carries a picture of the incident, not an
identity. Two capabilities, two seams — a machine reads the credential, a person
photographs the scene. Mechanical actors do not transmit iris data through a
Votive because they do not own one; identity resolution remains BRMA's deferred
job rather than leaking into the terminal.

---

## 5. What is decided and what is not

**Decided:** the two rungs and what separates them; that BRPD already exists in
part and is dispatched to places; that BRMA is §5's Attribution with a name;
that `IrisAccess` is a seam that both grants access and records an observation
at `IRIS` quality. **Built from this document:** actor nature, human-only Votive
ownership, the human `FACE` / mechanical `IRIS` observation ceiling, and the two
walking `HUMAN + ROBOT` Patrolman pairs described in §0/§2.

**Not decided, deliberately:** how many synthetics are in a crowd; what a device looks like (that is
`docs/3D_ART_BIBLE.md`, not this); whether a credential can be borrowed or
forged; whether passing a door reads you and whether that reaches a record;
whether cameras are `ActorBase` or something lighter; where an authority's own record lives, or whether it needs one beyond
`IncidentRegistry`; what a Marshal does when it resolves a person; whether the
player can hold a forged or borrowed credential; how an authority's reaction is
funded against the FPS target. None of these are answerable before there is a
reason to answer them, and guessing now is how a system gets built twice.

**Prerequisite before any of it is code:** the identity contract in
`docs/architecture/npc_and_incidents.md` already governs, and an authority that
names an actor is a record that names an identity — so it inherits that
contract's obligation to carry its own age or count bound.
