# CI cannot see an orphan script

**Invariant this belongs to:** `CLAUDE.md` — "a new file wired to nothing is the
case to check by hand."

A `.gd` file that no scene, autoload or other script references is never
compiled by the import pass, so a syntax error in it passes CI green.

Measured 2026-08-28 with a deliberate break, both directions:

| Where the break was | Import pass | Boot |
|---|---|---|
| `core/input/input_systems.gd` (an autoload) | 14 gated lines | 18 gated lines |
| an unreferenced file | 0 | 0 |

`--check-only --script` is not the fix — see `verification_ladder.md` for why it
invents `Identifier not found` for a third of the project.

There is no cheap automatic answer to this. A file added and wired to nothing is
checked by hand, and that is the whole mitigation.
