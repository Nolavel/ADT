# NOW

Last updated: 2026-09-03 by code

## Current task

Task 2 (physics interpolation) and the `fade_by_distance` half of Task 3a, in
two commits, in one session — Stan asked for them together, overriding his own
"one task per session" rule. Both are done and pushed. Task 1 is Stan's (H6
needs eyes); the rest of Task 3 is not started.

## Decided this week, not yet in CLAUDE.md

- Readability by rig (work plan 6a, archetype distinguishability at 30/10/5 m)
  is deferred as a separate art task, probably outside September. Consequence
  recorded in the plan: OBSERVE closes only half this month.
- 6b (memory surviving an encounter) is therefore the month's main substantive
  work, not a second half of 6.
- Three documentation genres — invariant / chronicle / post-mortem — with
  `docs/postmortems/` as the third destination. Only Task 4 acts on it; until
  then `CLAUDE.md` still carries archaeology that belongs elsewhere.

## Found, not fixed

- The plan's original MENU-pause item was based on a false premise from the
  chat side (`get_tree().paused` "set nowhere"); corrected before the file
  landed. Recorded because this is the first working example of feedback
  travelling code → chat, which is what this file exists for.
- `StreamingSystems` is an autoload with a default `process_mode`, so its
  polling halts under menu pause. Correct today; wrong once an inventory has to
  run over a live world. Design question, not a bug — see the plan, Out of plan.
- The two `reset_physics_interpolation()` calls in `StreamingSystems` and the
  player's `teleport_to()` are correct by construction but changed 0.02% of the
  render probe's pixels — insurance, not a measured fix. The camera's
  interpolation override is the whole of the visible change (15% of frame 1).
- `grain_effect.gdshader`'s look is unreviewed: cyan `grain_color` at 0.3 mix,
  and the render probe is Compatibility, where colour is not trustworthy. Needs
  Stan's eye on Forward+ before any number moves.
- 38 functions outside `tools/` have no return type, 15 of them in
  `core/ui/target_indicator/target_indicator.gd`. Task 3b.
- `core/ui/target_indicator/target_indicator.gd` still carries the whole
  move-destination API (`show_at_position()`, `show_invalid_click()`,
  `set_player_reference()`, the ring and the arrow) with no caller since
  click-to-move was removed. Left intact on purpose; whether a destination
  marker returns is a design question.
- `observation_level` is written and read only by the perception debug panel
  and one log line. Task 6a gives it its first gameplay consumer.

## Open question for Stan

- `common/max_physics_steps_per_frame=9` (engine default is 8). On the Intel HD
  620 target a higher ceiling makes a hitch longer, not shorter — why 9?
  **Not changed, not to be changed until answered.** Explained in chat
  2026-09-03: it caps how many physics ticks the engine will simulate inside one
  rendered frame before it gives up catching up and lets game time dilate.
- Grain: the "Fade In Animation" is a fade-OUT — it starts at full-screen grain
  and opens the clear hole over the character in 2 s. Authored that way, left
  alone. Is that the intent?
