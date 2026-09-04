# Actor identity — the two models that were not chosen

Archive. The rule this replaced them with is in `CLAUDE.md` under Architecture
rules, and the contract in full is in `docs/architecture/npc_and_incidents.md`.
Nothing here describes how the project works — if this contradicts the
invariant, the invariant wins.

**The question.** Work plan Task 5, September 2026. A pooled agent is a
different person every time it is re-targeted: one node is a passer-by at the
market now and a vagrant in another district a minute later. Task 6b files a
memory somewhere, Task 7 hands a pooled node an identity, Task 8 classifies
every world object — all three need the same answer, and getting it wrong later
means rewriting the record rather than the code. Three models were written up on
2026-09-03; Stan chose the third the same day.

## What reading the code first changed about the question

The plan framed this as an identity problem in general. It is narrower than
that, and the narrowing is what made the chosen model cheap.

`IncidentRegistry`'s only producer is `_on_punch_landed()`, which resolves
`player.get_actor_id()`. The player's `ACTOR_ID` is a constant. **So the
perpetrator is always the player and is stable by construction — pooling does
not break the perpetrator, it breaks the WITNESS.** The question is who
*remembers*, not who is *remembered*.

`WitnessReport.witness_id` was already being populated from
`_npc.get_actor_id()` before any of this was decided. The field existed and was
filled; what it lacked was anywhere to survive to.

## Model 1 — identity in the pool. Rejected.

A pooled agent gets a fresh `actor_id` on activation; the previous one is dead
forever.

Rejected because it makes Task 6b impossible by construction, not merely
awkward: any memory dies when the block unloads, `WitnessReport.witness_id`
becomes a throwaway token, and H7's "named NPCs" category has nothing to attach
to. It also contradicts `core/characters/actor_base.gd`'s own header, which
states the id is an authored `@export` rather than something derived from
`get_path()` or `get_instance_id()` **precisely** so it stays meaningful once
the block the actor lived in has been streamed out. Choosing Model 1 would have
meant deleting that paragraph.

It was the cheapest to build. That was its only argument.

## Model 2 — identity in the block. Rejected, but not wrong.

`BlockData` gains a roster of stable resident ids; a pooled agent wears one
while it stands in for that resident.

This one works. The mechanism is already proven once in this project —
`LodgingSystem` keyed on an authored `room_id`, surviving its block unloading
and reaching the save file through `get_save_key()`/`get_save_data()`. And it
buys something the chosen model does not: the same passer-by returns to the same
place, and the city becomes recognisable in a way promotion-on-involvement never
makes it.

Rejected on cost and on ordering. Every district must carry a population
**before a single memory works**: the island is 3500 × 2500 m, and `BlockData`
(`id`, `position`, `height`, `district`, two scene paths) has no field for one,
so the roster would have to be generated rather than authored. That is a system
to build before the thing it exists to enable can be tested at all — which is
the sequencing mistake the whole September plan is arranged to avoid.

**It is not off the table.** Model 2 and the chosen model are compatible: a
block roster is a second *source* of persistent identity, alongside authoring
and allocation, and it can be added the day recognisable residents are worth
their cost. Nothing in the chosen contract forbids it.
