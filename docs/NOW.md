# NOW

Last updated: 2026-09-03 by code

## Current task

**Task 6a closed — OBSERVE's half is done.** Its second checkbox turned out to
be closed already by 6b (`observation_level` drives memory lifetime), and the
five `attribution.md` §7 cases were re-measured: A/B/D/E unchanged, **C still
fails and has not moved**. Two findings beyond the table: the witness path can
never reach SILHOUETTE (envelope 0-16 m), so `LIFETIME_HOURS[SILHOUETTE]` is
dead; and **an NPC that remembers you refuses to witness** — memory sends it to
FLEEING and the "already reacting" gate closes. Branch
`claude/observe-6a-retest`.

## Decided this week, not yet in CLAUDE.md

- Readability by rig (work plan 6a, archetype distinguishability at 30/10/5 m)
  is deferred as a separate art task, probably outside September. Consequence
  recorded in the plan: OBSERVE closes only half this month.
- 6b (memory surviving an encounter) is therefore the month's main substantive
  work, not a second half of 6.

## Found, not fixed

- **`queue_free()` on a live NPC mid-reaction crashes the engine.** Segfault
  every time, three runs, no stack. Found while probing 6b; nothing in the game
  does it (streaming frees whole cells), so it is not on the path of any task.
- **The hand-placed crowd never streams out.** `DoggerlandCrowdBlock` sits
  inside `StreamContainer` but is authored in `world.tscn`, so `StreamingSystems`
  never frees it. "Survives a block unload" cannot be demonstrated on it — 6b
  proves the equivalent instead: a memory is addressed by id and holds for an
  actor with no node in the tree at all.
- `StreamingSystems` is an autoload with a default `process_mode`, so its
  polling halts under menu pause. Correct today; wrong once an inventory has to
  run over a live world. Design question, not a bug — see the plan, Out of plan.
- `grain_effect.gdshader`'s look is unreviewed: cyan `grain_color` at 0.3 mix,
  and the render probe is Compatibility, where colour is not trustworthy. Needs
  Stan's eye on Forward+ before any number moves.
- Task 3b's warnings are editor-only, never CLI, so they buy a standard rather
  than a CI gate. **20** untyped returns left — `target_indicator.gd` 15,
  `camera_follow.gd` 4, `navigation_component.gd` 1.
- `ShotEffectSystem.flash_light_energy` ships at 0.0 — a live `OmniLight3D` at
  the muzzle is a real cost at the FPS target and Compatibility cannot judge it.
  Unreviewed on Forward+.
- The tick is only visible in a 0.5 m band between `intent_radius` (2.5 m) and
  `prompt_distance` (2.0 m), and the knock waits 5 s. It will almost never be
  seen. Raising `intent_radius` also lengthens F's auto-approach — a gameplay
  call, unanswered since 2026-09-03.
- `core/ui/target_indicator/target_indicator.gd` still carries the whole
  move-destination API (`show_at_position()`, `show_invalid_click()`,
  `set_player_reference()`, the ring and the arrow) with no caller since
  click-to-move was removed. Left intact on purpose; whether a destination
  marker returns is a design question.
- Task 4 misses both numeric targets and both need a decision, not more
  cutting: `CLAUDE.md` is ~17 KB against 8–10 KB, and the two controllers are
  55% / 44% comment against <30%. Closing either means relocating or deleting
  present-tense invariants.
- The key-hints panel's own header called it "a working tool for showing the
  build to a reviewer, not final UI", and justified `SystemFont` on that basis.
  After this work the first is no longer true and the second is arguable — a
  bundled font is a separate decision, not made here.

## Open question for Stan

- **Witness envelope versus the quality ladder.** A Clerk's `vision_range` is
  16 m but SILHOUETTE needs >30 m, so the top rung is unreachable and case C
  cannot pass. Raise `earshot_radius`/`vision_range` above 30, or lower the
  ceilings under 16? Deferred in H3/H4 since August; now it also leaves a dead
  row in `ActorMemoryRegistry.LIFETIME_HOURS`.
- **A remembering NPC refuses to witness** (measured 2026-09-04). Right, or
  should memory-flight yield to a fresh incident? It means the same NPC cannot
  testify about you twice.
- Grain: the "Fade In Animation" is a fade-OUT — it starts at full-screen grain
  and opens the clear hole over the character in 2 s. Authored that way, left
  alone. Is that the intent?
