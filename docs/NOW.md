# NOW

Last updated: 2026-09-03 by code

## Current task

**Task 5 done — the hybrid identity model, chosen and written. Zero GDScript.**
It gates 6b, 7 and 8, so those are now unblocked; 6b is next unless Stan says
otherwise. Awaiting his eyes: the shot visual (PR #60, out of plan). In `main`:
Tasks 0, 2, 4, 3b's first half, and **only the third checkbox of 3a** — the
detector script and its CI step were never built. Task 1 stays Stan's.

## Decided this week, not yet in CLAUDE.md

- Readability by rig (work plan 6a, archetype distinguishability at 30/10/5 m)
  is deferred as a separate art task, probably outside September. Consequence
  recorded in the plan: OBSERVE closes only half this month.
- 6b (memory surviving an encounter) is therefore the month's main substantive
  work, not a second half of 6.

## Found, not fixed

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
- `observation_level` is written and read only by the perception debug panel
  and one log line. Task 6a gives it its first gameplay consumer.
- Task 4 hits neither of its two numeric targets, and both need a decision
  rather than more cutting. `CLAUDE.md` is **17 059 B** against a target of
  8–10 KB: what is left after the archaeology went is rules, so closing the gap
  means RELOCATING invariants into `docs/architecture/`. The two controllers are
  at **55%** and **44%** comment against a target of <30%: their inline comments
  are mostly present-tense rationale, not history, and hitting 30% means
  deleting ~557 and ~425 comment lines of it.
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
- **Task 6a vs `incident_knowledge_model.md` §8.** Not "one is wrong", as first
  written here: §8's ban is broader than the reason §3.3 gives it. The reason
  bites only if a reaction reads `observation_level` as *how identified the
  player is* — that is Attribution done informally in a controller. It does not
  bite if a witness reads its own look quality to change its own behaviour.
  Narrow §8, or drop 6a's checkbox?
- Grain: the "Fade In Animation" is a fade-OUT — it starts at full-screen grain
  and opens the clear hole over the character in 2 s. Authored that way, left
  alone. Is that the intent?
