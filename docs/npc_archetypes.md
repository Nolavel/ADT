# NPC archetypes — readability spec

The core loop is: need → move → **observe** → decide → act → what became
known → adapt. OBSERVE currently returns nothing: every NPC is the same mesh
on the player's rig. Until the crowd carries information, the loop reads as
"walk, then hit whoever is nearest."

This page defines the smallest set of archetypes that makes the crowd
readable, and the channels that carry it. Written to be built against
without further explanation — see §6 for what is delegable.

Companion pages: `core_loop.md` (why the player is out here at all),
`NPC_REACTIONS.md` (what the crowd *does*). This page is only about what the
crowd *looks like*.

None of this is implemented. Last reviewed: 2026-08-13

---

## 1. Two axes

Everything the player needs from a passer-by answers two questions:

- **Worth taking?** — does this person carry anything.
- **Watching me?** — will they notice, and does it matter if they do.

The second axis is not an animation state; head-turning already exists via
`LookAtModifier3D`. It is a property of the archetype: some people are
habitually alert, some are absorbed in themselves.

|  | Absorbed | Alert |
|---|---|---|
| **Nothing to take** | Vagrant | Thug |
| **Something to take** | Commuter | Clerk |

Plus two that sit outside the grid, because they change the rules of the
space rather than offer a choice within it:

- **Patrolman** — presence alone suppresses action.
- **Witness** — indistinguishable from whichever archetype it wears; see §2.

Six total. Deliberately small: the whole vocabulary has to be learnable in
the first ten minutes.

---

## 2. The archetypes

**Vagrant.** Bottom of Doggerland. Nothing on them, absorbed, will not
report. Robbing one costs time and returns nothing — the archetype exists so
that "worth taking" is a real judgement rather than a formality.

**Thug.** Materially identical to the player. Alert, fights back, will not
call the police — the bottom does not report the bottom. A risk with no
legal consequence, which makes it the cleanest demonstration of how evidence
works.

**Commuter.** Moving with purpose, absorbed in getting somewhere. Something
to take, low resistance. The default target, and therefore the first
archetype whose density needs tuning.

**Clerk.** Better dressed, unhurried, alert to their surroundings, in the
strata where they belong. Worth more, likelier to notice an approach in
time.

**Patrolman.** Human counterpart to the drone. Does not need to see anything
to matter — the archetype is a moving no-go zone. Must be identifiable at
maximum distance: the player has to be able to route around one before
committing to anything.

**Witness.** Not a visual archetype. A flag on any of the above, held by a
minority, enabling the Call response. It carries **no** visual tell by
design (`NPC_REACTIONS.md` §4): if witnesses were identifiable, the player
would clear sightlines and the crowd would become a puzzle.

---

## 3. Channels

No profiler overlay, no scan mode, no highlight. Four channels:

| Channel | Carries | Implementation |
|---|---|---|
| Silhouette & clothing | Wealth, role | Mesh / material variant |
| Gait | Vulnerability, hurry, state | Locomotion speed, posture, animation set |
| Attention | Alert vs absorbed | Head direction, turn frequency, stance |
| Density & mix | Which stratum's rules apply | Spawn composition |

**Rule: an archetype must be identifiable from behind, at distance, in
motion.** If two archetypes need a front-facing close-up to be told apart,
they are the same archetype. The player reads the crowd while moving through
it, never while standing and inspecting it.

**Rule: channels are consistent across the whole population.** They are a
vocabulary, not decoration on individual NPCs.

---

## 4. Placeholder colours — prototype stage only

Until meshes exist, archetypes are distinguished by flat material colour so
the loop can be tested now:

| Archetype | Colour |
|---|---|
| Thug | Black |
| Patrolman | Red |
| Clerk | Blue |
| Commuter | Grey |
| Vagrant | Brown |

**This is scaffolding, not the design.** Flat colour coding is a legend the
player memorises — functionally an overlay drawn on the world, which is the
thing §3 exists to avoid. It is correct for a greybox where the question is
"does the loop work once OBSERVE returns information," and it must be
replaced by silhouette, clothing and gait before the crowd is shown to
anyone as finished work.

The replacement is not a repaint. Real readability comes from the
combination of channels: a clerk is legible through cut, pace and alertness
together, not because they are blue.

Note for the eventual art pass: Doggerland's readability cannot depend on
colour at all — the stratum is dark and tight, and its crowd must separate
by silhouette and motion under low light.

---

## 5. Composition per stratum

Same archetypes, different proportions. This is what makes the strata feel
different without new content.

| Stratum | Dominant | Rare | Absent |
|---|---|---|---|
| Doggerland | Vagrant, Thug | Clerk | — |
| Manifold | Commuter | Vagrant | — |
| Glare | Clerk | Commuter | Vagrant, Thug |

Consequence, and the reason this table matters more than it looks: the
player's read shifts as they climb. At the bottom the danger is people, and
the player reads faces and posture. At the top the danger is
infrastructure — cameras, approved routes, sightlines — and the crowd stops
being the thing worth watching. Same verb, a different grammar per stratum.

Open: witness flag density per stratum, and whether the flag is static per
NPC or rolled per incident.

---

## 6. Delegation

Open to a contributor against this page:

- Mesh and material variants for the five visual archetypes, satisfying the
  identifiability rule in §3.
- Locomotion variants — walk cycles and posture that read as hurried,
  absorbed, alert — against the existing rig.

Needs a spec from the owner first: spawn composition tuning, witness flag
assignment, anything touching `PerceptionComponent` or `IncidentRegistry`.

---

## 7. The test this page has to pass

Walking one street, before any UI exists, the player should be able to
think:

> That one has something worth taking.
> That one is watching me too closely.
> Those two saw what happened.
> Nobody here noticed.

If a build cannot produce those four thoughts, the archetypes are not
distinct enough, and no amount of behaviour work will compensate.
