# NPC reactions — design specification

This page is the design the crowd and the city's responders are built
against. It is not a task list and nothing here is scheduled.

The design was settled in discussion and lived outside the repository, which
meant a contributor could not find it. Sections 2, 3, 5, 6 and 7 are still
unbuilt; section 4 is partly built. See Status below for the split.

Read `CONTRIBUTING.md` before picking any of it up.

Last reviewed: 2026-08-10

---

## Status

Built:

- `IncidentRegistry` (`core/world/incident_registry/`) — a bounded, aging log
  of reported facts. Deliberately not player-specific: `report()` takes any
  perpetrator, so a future witness reports through the same call. Today the
  only caller is the player's own `punch_landed`.
- `PatrolDroneController` — goes ALERT on an incident within
  `alert_incident_radius`, with OBSERVE a rung below, spotlights the player
  while alerted, and reverts after a memory timer.
- NPCs — the player's rig, idle/walk animation, head turn via
  `LookAtModifier3D`, a wander around the spawn point, and `take_hit()`:
  they fall and get up.
- The player's punch (`COMBAT` stance, `mouse_left_button`).

Not built: navigation (both controllers substitute a single forward raycast
for a navmesh), memory beyond one ALERT timer, reaction spreading past one
drone's radius, the witness flag, and everything in sections 2, 3, 5, 6, 7.

Design rule: `mouse_left_button` splits by `PlayerState.Stance`, not by
camera view. In `COMBAT` it throws the punch, in both `TPS` and `ISOMETRIC`;
in `PEACE` it is click-to-move's stop/cancel button in `ISOMETRIC` (unclaimed
in TPS). Raising fists is the same statement regardless of which camera the
player happens to be using, so the stance axis — not the view — is what
gates the action. `ClickToMoveSystem` self-gates off for the duration of
`COMBAT` so the two subscribers of the shared click signal never race each
other for the same click.

---

## 1. Why the crowd is load-bearing

The core minute of play is: move with the crowd → read people and space →
either avoid a threat or strike and rob → keep moving. Every verb in that
loop takes the crowd as its object. A crowd that only walks past turns the
core loop into scenery.

This has a direct consequence for implementation order: **readability comes
before intelligence.** An NPC that is easy to classify at a glance is worth
more here than an NPC that plans well.

---

## 2. Readability — the crowd must be legible without UI

There is no profiler overlay, no scan mode, no highlight. The player learns
to read the crowd by looking at it. Four channels carry that information:

| Channel | Reads as | Carried by |
|---|---|---|
| Clothing | Wealth — is this worth robbing | Mesh / material variant |
| Gait | Vulnerability — is this an easy target | Locomotion speed, posture, animation set |
| Attention | Threat — is this one looking at me | Head/eye direction, stance |
| Stratum | Which rules apply here | Population mix per stratum |

Design rule: an archetype must be identifiable from behind and at distance.
If two archetypes need a front-facing close-up to be told apart, they are
the same archetype.

Player skill in this game is street literacy. It has to be learnable by
observation alone, which means the channels above must be consistent across
the whole population, not decorated per NPC.

---

## 3. The city telegraphs before it punishes

Any hostile crowd response escalates through visible stages:

```
glance  →  shove  →  shout  →  hit
```

The player must be able to read stage one and withdraw. A response that
skips to the last stage reads as an engine defect, not as a rule of the
world — the player concludes the city is unfair rather than that they were
careless.

Worked examples:

- Standing in an NPC's path: glance, then a shove, then a slap.
- Blocking a queue (a pneumatic tube boarding point, for instance): the
  crowd escalates collectively and beats the player out of the way.

This is also the tutorial. The city explains nothing verbally; it explains
itself by reacting in a legible order.

---

## 4. Incident response — the crowd reacts by chance

Violence in the city is a local incident, not a norm. The crowd is shocked
every time. Within earshot of an incident, an NPC picks a response:

| Response | Effect |
|---|---|
| Flee | Leaves the area, no report |
| Freeze and stare | Stays, no report, blocks flow |
| Call | Reports the incident |

**Only NPCs carrying a witness flag can produce the Call response.** The
flag is assigned to a minority of the population. The rest are shocked but
useless to the authorities.

The reason for the flag is design, not performance: if every bystander could
report, the player would optimise by clearing lines of sight, and the crowd
would become a puzzle. With a minority, the player cannot know which
bystander is dangerous, so the correct play is prudence rather than
calculation.

The flag is also cheap. Deep behaviour is needed on few agents; the rest is
a small reaction state machine. This matters at the population densities the
city implies.

Open: how witness density scales per stratum, and whether the flag is
static per NPC or rolled per incident.

### 4a. Intent, before anything has happened

A responder reacts to two different things, and they are not the same rung.

**A reported fact** — an incident in the registry — is grounds for ALERT.
Something happened; the drone addresses the player.

**Intent** — a drawn weapon while the player is in `COMBAT` stance — is
grounds for attention only. The drone moves to OBSERVE: it turns, it
follows, it makes clear it is watching, and it does not escalate. The
attention is released when the player returns to `PEACE` and holsters.
Nothing is recorded, because nothing was done.

This gives the player a way to be read as dangerous without being guilty,
and a way to defuse it that costs only a stance change. It is the same
telegraph principle as section 3, applied to responders rather than the
crowd: the city shows its attention before it acts on it.

Prerequisite: weapon-in-hand does not exist yet as a state. `PlayerState.
Stance` is deliberately boolean (PEACE/COMBAT); the weapon axis is meant to
sit on top of it as an orthogonal modifier. Until it lands, a drone cannot
distinguish a raised stance from a drawn weapon, which is why stance alone
was removed as an ALERT trigger — the city was reacting to a pose.

---

## 5. Consequences are evidence, not stars

There is no wanted meter. What is punished is the *recorded* deed. A job is
clean when all three hold:

1. No drone or camera fixation.
2. The victim is not linked to law enforcement.
3. No witness flag triggered.

If all three hold, the city never learns of it. Thug-on-thug violence is
additionally invisible by class: the bottom does not call the police.

If the deed *is* recorded, the response is not a chase. The city broadcasts
the face and prices the head, and collection is left to whoever is nearby —
which at the bottom means people materially identical to the player. The
loop inverts: the crowd starts reading the player the way the player reads
the crowd.

Open: how fixation is telegraphed. The player must be able to tell that a
drone or camera recorded them; the escalation rule of section 3 applies
here too, and no mechanism has been chosen.

---

## 6. Surveillance is a gradient, not a switch

| Stratum | Coverage | Reason |
|---|---|---|
| Doggerland | Sparse — few drones, dark, tight geometry | The city does not count this population, so it does not watch it |
| Manifold | Moderate | — |
| Glare | Dense — CCTV, open sightlines, narrow approved routes | Everything of value is here |

Height equals visibility. This is the same axis as wealth, light and
transport cost; it is not a separate difficulty curve and should not be
tuned as one.

The inversion is deliberate and should survive implementation: the safest
place to commit a crime is the place with the least protection for its
residents.

---

## 7. Advertising reads the player

Advertising stands are the diegetic HUD. They respond to the player's
current state — food when hungry, flophouses when sleep is due, security
services after an incident. This replaces status bars, and it is the primary
way the city demonstrates that it registers the player without addressing
them.

Some ad content is deliberately non-actionable: it carries no address, no
lead, and no interaction. That is a narrative rule, not an oversight. Do not
"fix" it by wiring it to a destination.

---

## 8. Not designed yet

Named so the absence is deliberate:

- Retribution inside the bottom. There is no police response to
  thug-on-thug violence; what replaces it — street revenge, standing among
  peers — is undecided.
- Spawn composition — which archetypes appear together, in what proportion,
  per stratum and time of day.
- Whether a durable wanted record is the same object as `IncidentRegistry`
  or a separate one. The registry today is a short-lived sensor buffer
  (`max_incident_age` defaults to 30s) holding node references and
  engine-uptime timestamps; a record that outlives sleep needs stable
  identity and game-time stamps instead. Decide before a second consumer
  arrives.

---

## 9. Delegation boundaries

Open to a contributor, against this page:

- Archetype meshes and materials that satisfy section 2, to written spec.
- Locomotion and reaction animation sets, against the existing rig.
- Ambient crowd audio per stratum, and incident reaction audio (see
  `planned_scope.md` — no audio system exists, the seam is clean).

Needs a spec from the owner first:

- Witness flag assignment and the incident response state machine.
- Anything touching `PerceptionComponent`, `IncidentRegistry` or
  `PlayerState`.

Not open: the evidence and wanted rules of sections 5 and 6. They are tied
to systems and story beats that are not public.
