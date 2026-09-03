# NOW

Last updated: 2026-09-03 by code

## Current task

Task 0 of `docs/work_plan_2026-09.md` — this file, plus the two lines in
`CLAUDE.md` that point at it. The plan file itself landed in the commit before
this one. Nothing else is in flight from the code side. Next up per the
sequence: Task 1 is Stan's (H6 needs eyes), Tasks 2 and 3 are independent and
may run alongside it — but one task per session, so neither is started yet.

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
- `ui/hud/fade_by_distance/fade_by_distance.gd`, 210 lines, referenced by
  nothing. Task 3a decides its fate; do not delete it before Stan answers.
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
  **Not changed, not to be changed until answered.**
- Task 3a: does `fade_by_distance.gd` get wired to something, or deleted?
