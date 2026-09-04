# Blackrock authorities — BRPD, BRMA, and the iris

**Design specification. Not built.** Named here so the shape is decided before
anything is written against it, the same way `docs/attribution.md` §5 records
Attribution without scheduling it. Where this describes something that already
exists, it says so and names the file.

`CLAUDE.md` and `docs/architecture/*` stay authoritative for what is built.
This document is authoritative for nothing yet.

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
- **The `Patrolman` archetype** — `docs/npc_archetypes.md` calls it "the human
  counterpart to the drone… a moving no-go zone", and it is the only archetype
  with `responds_by_approaching`, which is exactly BRPD behaviour: it runs to
  the place, it does not work out who.

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

## 5. What is decided and what is not

**Decided:** the two rungs and what separates them; that BRPD already exists in
part and is dispatched to places; that BRMA is §5's Attribution with a name;
that `IrisAccess` is a seam that both grants access and records an observation
at `IRIS` quality.

**Not decided, deliberately:** whether cameras are `ActorBase` or something
lighter; where an authority's own record lives, or whether it needs one beyond
`IncidentRegistry`; what a Marshal does when it resolves a person; whether the
player can hold a forged or borrowed credential; how an authority's reaction is
funded against the FPS target. None of these are answerable before there is a
reason to answer them, and guessing now is how a system gets built twice.

**Prerequisite before any of it is code:** the identity contract in
`docs/architecture/npc_and_incidents.md` already governs, and an authority that
names an actor is a record that names an identity — so it inherits that
contract's obligation to carry its own age or count bound.
