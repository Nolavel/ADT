```markdown
# Incident knowledge model

This page defines what knowledge exists at each stage of the witness chain, and what must never be collapsed into a single field.

It extends `attribution.md`. Read that page first (§1–§4 and §7). This document does not replace it; it answers the question that §4 and §5 leave open: **what exactly became known**.

Most of what follows is deliberately unbuilt. Only the vertical slice in `attribution.md` §7 is in the current horizon. Everything else exists so that future work on Equipment (H5) and Attribution does not re-derive the model from scratch or accidentally introduce identity into a report.

Last reviewed: 2026-08-23

---

## 1. Purpose

The current registry and report structures answer “an incident was reported.” They do not yet answer:

> What information did the city actually receive, and how strongly does it identify anyone?

Without that distinction the player has no meaningful decisions after a crime. The only questions become “did anyone see it?” and “can I kill the witness in time?” Both are too coarse for the loop described in `core_loop.md` §6.

This model separates three different kinds of knowledge and keeps them from collapsing into one another.

---

## 2. Central invariants

These are hard rules, not tuning choices.

1. **A witness transmits an observed version of events, not the truth.**  
   The report can be incomplete, degraded, or (later) wrong. The registry stores what was told, not what happened.

2. **REPORT never contains a resolved actor identity.**  
   No `suspect_id`, no player reference, no “this was Sid.” Identity is produced later, by Attribution, from the contents of one or more reports.

3. **OBSERVATION ≠ CRIME.**  
   The NPC records physical facts (contact, injury, presence of a weapon). Classification into assault / self-defence / accident belongs to the city, not the witness.

4. **`IncidentRegistry` holds messages, not conclusions.**  
   An incident entry means “the city received a statement with this set of observed facts.” It does not mean “Sid committed an assault.”

5. **Quality of knowledge is the gameplay surface.**  
   The player can act on what was seen: prevent the event from being observed, prevent the face from being seen, change appearance, discard distinctive equipment, interrupt transmission, or leave a situation in which the crime is known but the actor is not.

Breaking any of these turns the system back into a wanted meter with extra steps.

---

## 3. Three distinct kinds of knowledge

These must stay separate in data and in reasoning.

### 3.1 Event knowledge

What happened, independent of who did it.

- kind (assault, theft, …)
- victim (known / unknown / none)
- injury / death / theft flags
- location
- time (game clock)
- source (direct perception vs committed report)

This is enough for the city to dispatch units to a location even when no suspect description exists.

### 3.2 Actor observation

What a witness physically registered about a person present at the event.

- was a person observed at all
- silhouette / body
- clothing
- equipment / weapon
- face (seen or not)
- distinctive traits
- observation_level (existing scale: SILHOUETTE < PERSON < EQUIPMENT < FACE < IRIS)

This is still not identity. “A man in a dark jacket with a pistol” is not “Sid.”

### 3.3 Attribution / identification

How strongly the observed data can be matched to a known identity.

- face seen
- face recognized (prior encounter)
- face recorded (image or Votive capture)
- identity established (city systems can resolve the credential)
- confidence / partial match

These are different stages. Seeing a face is not the same as being able to recognize the person later, and neither is the same as the city having a usable record.

Collapsing any of these into a single `suspect_id` or a single `observation_level` destroys the decisions the player is supposed to make.

---

## 4. Data shapes (conceptual)

These are the shapes the systems will eventually carry. They are not current code.

### Witness observation (what the eyes got)

```
observation
├── observation_level          # existing SILHOUETTE … IRIS
├── face                       # seen / not
├── clothing / silhouette      # traits if resolved
├── equipment                  # weapons or distinctive gear if resolved
├── distinctive_traits         # optional
├── recognition                # prior encounter with this actor?
├── recording                  # image / Votive capture obtained?
└── uncertainty                # flags for later contradiction / degradation
```

### WitnessReport (what was transmitted)

```
WitnessReport
├── witness_id
├── observation                # subset of the above that was actually sent
├── observed_at                # game time
├── observed_from              # position
└── status                     # PENDING → COMMITTED / CANCELLED
```

A report never carries a resolved actor. `observation_level` is already written by the current vertical slice and is intentionally unread; the richer fields above are future.

### Incident (accumulated city knowledge)

```
Incident
├── event_type / kind
├── location
├── timestamp
├── victim
├── source                     # direct / reported
└── reports[]                  # zero or more WitnessReports
```

Downstream systems read the reports and decide what is actionable. The registry itself does not perform attribution.

---

## 5. Relation to systems that already exist

| System | Role relative to this model |
|--------|-----------------------------|
| `PerceptionComponent` | Resolves observation quality (distance ceiling + FOV). Attention modifier is still deferred. |
| Current `WitnessReport` | Writes `observation_level` and status. Richer observation fields are not yet present. |
| `IncidentRegistry` | Stores incidents and reports. Remains identity-free. Save contract already supports versioned payloads. |
| Votive transmission | Visible 3-second window before COMMIT. Interrupting it is ordinary assault, not a special case. |
| Equipment (H5) | Will become the source of `observed_equipment`. Changing or discarding gear changes the quality of the link between crime and actor. |
| Future Attribution | One-way reader of the registry. Produces known / partial / unknown actor from report contents. |

No new autoload is required. No report is allowed to hold a `Node` reference.

---

## 6. Worked scenarios (same assault, different knowledge)

These are the minimum set that the model must be able to distinguish.

**Scenario A — distant witness**  
Saw the blow and a silhouette, direction of flight.  
Did not see face, clothing detail, or weapon.  
Result: city knows an assault occurred at location X. No usable suspect profile. Dispatch can search the area; it cannot pursue a named or described person.

**Scenario B — close witness**  
Saw the assault, face, jacket, and pistol.  
Result: city has a concrete description. Units can search for matching appearance and equipment. Identity is still not established.

**Scenario C — prior recognition**  
Same as B, but the witness has seen the actor before.  
Result: recognition fires. The new report links to a previously observed person. This can be more dangerous than a fresh high-quality sighting, because the city now has a continuity of observation rather than a single snapshot.

A single high-quality face observation can be more dangerous than ten distant witnesses who only saw a fight. The model must make that difference expressible.

---

## 7. Player agency over knowledge

After an act the player’s questions become:

- Did anyone see the event at all?
- Did anyone see my face?
- Did anyone see distinctive clothing or equipment?
- Can I change appearance or discard gear before the description propagates?
- Can I interrupt the transmission?
- Is the fact of the crime known while my identity remains unknown?

All of these are legitimate moves. The system must not collapse them into a binary “witnessed / not witnessed.”

Suppressing a witness is itself an incident and can generate further reports. The recursion is allowed; it is not a special case that needs its own rules.

---

## 8. Explicitly deferred

The following are named so they are not treated as omissions:

- Full Attribution system (matching reports to identities, confidence, partial matches).
- Behavioural signature across multiple incidents.
- Contradictory testimony and player exploitation of it.
- Stratum-dependent processing speed and reliability (already sketched in `attribution.md`).
- Attention modifiers beyond the current FOV gate.
- Any field that is written but never read by a live system.

`observation_level` is the one intentional deferred output already present in the vertical slice. It must stay unread until Attribution exists.

---

## 9. Relation to other documents

- `attribution.md` — chain definition, observation quality scale, report shape, Votive transmission, current vertical slice (§7).
- `core_loop.md` §6 — “what exactly became known” and the four outcomes of the same punch.
- `NPC_REACTIONS.md` §4 / §5 — witness flag, Call response, evidence-not-stars.
- Future H5 (EquipmentComponent) — source of observable gear.
- Future Attribution horizon — consumer of this model.

---

## 10. Status

This document is design specification only.  
Nothing in §§3–7 is scheduled until the current witness vertical slice (`attribution.md` §7) has been played and judged, and until Equipment exists as a real observable.

An empty or speculative implementation of the richer observation fields is not permitted. The model is written down so the next system that needs it does not have to invent it under time pressure.
```
