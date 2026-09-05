# NOW

Last updated: 2026-09-05 by Codex

## Current task

**PR #66 is integrated; its first executable seam is Actor Nature.** The merged
paper defines humans, synthetics and robots as an axis separate from archetype,
with retina reading reserved for machines. The next code change will put that
contract on `ActorBase`, mark both Clerks synthetic and police drones robotic,
and cap human witness observations at `FACE`. The changelog entries lost during
conflict resolution and the stale class name in the sound decision are repaired.

## Decided this week, not yet in CLAUDE.md

- The cursor keeps its game colours, radii and speed-reactive final arcs; the
  supplied HTML contributes the transition timing and juice, not a replacement
  visual language.
- Drones are firearm targets but not TPS lock-on or punch targets. Their crash
  is kinematic with no tumble or rigid-body handoff, and is not persisted yet.
- Key hints hold clear for 1.0 s on scene startup, then their randomised blobs
  grow from zero to 80% during the ink entrance; later reopens remain immediate.
- Readability by rig (work plan 6a, archetype distinguishability at 30/10/5 m)
  is deferred as a separate art task, probably outside September. Consequence
  recorded in the plan: OBSERVE closes only half this month.
- 6b (memory surviving an encounter) is therefore the month's main substantive
  work, not a second half of 6.
- **People remember your face, machines know your name** (Stan, 2026-09-04).
  Retina reading is exclusively mechanical; the Clerk is synthetic, which is
  what keeps `_distance_ceiling()`'s `IRIS` rung legitimate. **The ladder splits
  in two the day a HUMAN archetype gains `is_witness_caller`** — a decision to
  take, not a discrepancy to find.
- **Sound is reinforcement, not duplication** (Stan, 2026-09-04). The comic word
  survives audio; `ComicEffectDef` still grows no sound field. `SoundSystems`
  as an autoload is the remaining gate and needs an argued amendment.

## Found, not fixed

- **The hand-placed crowd never streams out** — `DoggerlandCrowdBlock` is
  authored in `world.tscn` though it sits inside `StreamContainer`, so nothing
  frees it. Will bite Task 7.
- **`queue_free()` on a live NPC mid-reaction segfaults the engine** — three
  runs, no stack. Nothing in the game does it; streaming frees whole cells.
- `StreamingSystems` is an autoload with a default `process_mode`, so its
  polling halts under menu pause. Correct today; wrong once an inventory has to
  run over a live world. Design question, not a bug — see the plan, Out of plan.
- `grain_effect.gdshader`'s look is unreviewed: cyan `grain_color` at 0.3 mix,
  and the render probe is Compatibility, where colour is not trustworthy. Needs
  Stan's eye on Forward+ before any number moves.
- Task 3b's warnings are editor-only, never CLI, so they buy a standard rather
  than a CI gate. All 20 untyped returns are typed now; **zero left** in game
  code. The warnings-as-errors flip is still Stan's call, unasked.
- `ShotEffectSystem.flash_light_energy` ships at 0.0 — a live `OmniLight3D` at
  the muzzle is a real cost at the FPS target and Compatibility cannot judge it.
  Unreviewed on Forward+.
- The tick is only visible in a 0.5 m band between `intent_radius` (2.5 m) and
  `prompt_distance` (2.0 m), and the knock waits 5 s. It will almost never be
  seen. Raising `intent_radius` also lengthens F's auto-approach — a gameplay
  call, unanswered since 2026-09-03.
- `target_indicator.gd`'s move-destination half is unused since click-to-move
  went, but **the file is live** — `hud_component.tscn` runs it.
- Task 4 misses both numeric targets and both need a decision, not more
  cutting: `CLAUDE.md` is ~17 KB against 8–10 KB, and the two controllers are
  55% / 44% comment against <30%. Closing either means relocating or deleting
  present-tense invariants.
- The key-hints panel no longer matches its own header ("a working tool, not
  final UI"), which is what justified `SystemFont`. A bundled font is a separate
  decision.

## Open question for Stan

- **`core/map_source/map_data.gd` is an orphan** — a `MapData` resource schema
  with no producer and no consumer, found by the new CI detector. It sits in the
  level-design tool set `CLAUDE.md` marks do-not-refactor, so it is whitelisted
  rather than deleted. Wire it or drop it?
- **Recognition** — proposal written into `docs/architecture/npc_and_incidents.md`,
  awaiting Stan. Note before approving: **only the weapon lever is playable**;
  there is no second garment to change into, so the garment half of the
  signature is inert until one ships.
- **Does a synthetic witness transmit identity, or only a picture?** If it
  transmits identity, BRMA stops being the only place identity is produced and
  `incident_knowledge_model.md` §2 invariant 2 needs revisiting. Left open on
  purpose — `blackrock_authorities.md` §4b.
- Grain: the "Fade In Animation" is a fade-OUT — it starts at full-screen grain
  and opens the clear hole over the character in 2 s. Authored that way, left
  alone. Is that the intent?
