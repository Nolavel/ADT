# NOW

Last updated: 2026-09-03 by code

## Current task

**Stan's tuning calls, applied and measured.** Witness ceilings lowered to
3 / 6 / 11 so all four rungs fit inside Clerk's 16 m vision — **`attribution.md`
§7 case C passes for the first time since it was written**. Memory lifetimes put
on a clean x3 with a floor of 12: **12 / 36 / 108 / 324** game hours. Next on the
branch: the orphan-script CI detector (3a), then typing (3b), then the
recognition proposal. Branch `claude/witness-ceilings-and-memory`.

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
  than a CI gate. All 20 untyped returns are typed now; **zero left** in game
  code. The warnings-as-errors flip is still Stan's call, unasked.
- `ShotEffectSystem.flash_light_energy` ships at 0.0 — a live `OmniLight3D` at
  the muzzle is a real cost at the FPS target and Compatibility cannot judge it.
  Unreviewed on Forward+.
- The tick is only visible in a 0.5 m band between `intent_radius` (2.5 m) and
  `prompt_distance` (2.0 m), and the knock waits 5 s. It will almost never be
  seen. Raising `intent_radius` also lengthens F's auto-approach — a gameplay
  call, unanswered since 2026-09-03.
- `target_indicator.gd`'s move-destination HALF is unused (`show_at_position()`,
  `show_invalid_click()`, `set_player_reference()`) since click-to-move went.
  **The file itself is live** — `hud_component.tscn` runs it and calls
  `hide_indicator()`. I called the whole file dead twice; it is not.
- Task 4 misses both numeric targets and both need a decision, not more
  cutting: `CLAUDE.md` is ~17 KB against 8–10 KB, and the two controllers are
  55% / 44% comment against <30%. Closing either means relocating or deleting
  present-tense invariants.
- The key-hints panel's own header called it "a working tool for showing the
  build to a reviewer, not final UI", and justified `SystemFont` on that basis.
  After this work the first is no longer true and the second is arguable — a
  bundled font is a separate decision, not made here.

## Open question for Stan

- **`core/map_source/map_data.gd` is an orphan** — a `MapData` resource schema
  with no producer and no consumer, found by the new CI detector. It sits in the
  level-design tool set `CLAUDE.md` marks do-not-refactor, so it is whitelisted
  rather than deleted. Wire it or drop it?
- **Recognition** — proposal written into `docs/architecture/npc_and_incidents.md`,
  awaiting Stan. Note before approving: **only the weapon lever is playable**;
  there is no second garment to change into, so the garment half of the
  signature is inert until one ships.
- Grain: the "Fade In Animation" is a fade-OUT — it starts at full-screen grain
  and opens the clear hole over the character in 2 s. Authored that way, left
  alone. Is that the intent?
