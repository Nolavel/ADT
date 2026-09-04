# NOW

Last updated: 2026-09-03 by code

## Current task

**Aiming, stage 1 — done and measured.** `get_aim_point()` from the camera, the
shot and its target cone from the muzzle in full 3D, `_has_clear_shot()` moved to
the same origin. **The gameplay shot is correct now; the weapon pose is not.**
Re-measured in two states, because the first pass conflated them: at the FIRING
frame it is **5.96 deg level, 30.61 up, 32.94 down**, and `dot(barrel, facing)`
stays ~0.997 throughout — the pose locks the weapon to the body's horizontal
axis, so the error at the shot is very nearly the camera pitch. Stage 2 is
therefore **pitch only**. Branch `claude/aim-from-camera`, PR #63.

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
- The two `reset_physics_interpolation()` calls in `StreamingSystems` and the
  player's `teleport_to()` are correct by construction but changed 0.02% of the
  render probe's pixels — insurance, not a measured fix. The camera's
  interpolation override is the whole of the visible change (15% of frame 1).
- `grain_effect.gdshader`'s look is unreviewed: cyan `grain_color` at 0.3 mix,
  and the render probe is Compatibility, where colour is not trustworthy. Needs
  Stan's eye on Forward+ before any number moves.
- The tick is only visible between `intent_radius` (2.5 m, where detection
  starts) and `prompt_distance` (2.0 m, where F replaces it) — a 0.5 m band,
  and the knock cycle waits 5 s before shaking. In practice the knock will
  almost never be seen. `intent_radius` is the knob; raising it also lengthens
  F's auto-approach, so it is a gameplay call, not mine.
- GDScript analyzer warnings never reach the CLI — editor Script panel only,
  proven with a deliberately untyped function in an autoload. So Task 3b buys a
  standard for whoever has the project open, not a CI gate. **20** untyped
  returns in game code — `target_indicator.gd` 15, `camera_follow.gd` 4,
  `navigation_component.gd` 1. An earlier count of 35 here was wrong: the grep
  read only the first line of each signature and missed `-> Type:` on the
  closing line of a multi-line one.
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

- The carbine's `muzzle_offset` is measured here, not Stan's — his is not in the
  repository. If he has numbers, they replace it.
- `ShotEffectSystem.flash_light_energy` ships at 0.0 — a live `OmniLight3D` at
  the muzzle is a real cost at the FPS target, and Compatibility cannot show
  what it would look like. Needs Stan's eye on Forward+ before it moves.
- Grain: the "Fade In Animation" is a fade-OUT — it starts at full-screen grain
  and opens the clear hole over the character in 2 s. Authored that way, left
  alone. Is that the intent?
