# Post-mortems

The third documentation genre in this repository, and the one that had nowhere
to live until 2026-09-03.

| Genre | Where | Test |
|---|---|---|
| **Invariant** — what must not break, present tense, no history | `CLAUDE.md`, `docs/architecture/*` | readable by someone who does not know the project's history |
| **Chronicle** — what changed, dated | `CHANGELOG.md`, 3–6 lines per entry | fits on a screen |
| **Post-mortem** — why it was hard, what was measured, what turned out false | **here** | one link from the invariant, nothing more |

The problem these solve is genre, not volume. `CLAUDE.md` had become a legal
record of past mistakes — "this line previously claimed…", "fourth recorded
drift", "measured 2026-09-02, six taps produced six latches and zero reads" —
and a file that is mostly the history of someone else's errors does not get
edited: agents append to the bottom or work around the middle. Both external
reviewers got the save contract wrong specifically where documentation was
densest.

**Writing one.** A post-mortem carries the measurement, the wrong belief, and
the reasoning. It does NOT carry the rule — the rule stays in `CLAUDE.md` in
present tense, with one link down here. If you find yourself stating an
invariant in a post-mortem, it belongs upstairs instead.

**Reading one.** These are archives. Nothing here describes how the project
works today; check `CLAUDE.md` and `docs/architecture/` for that. A post-mortem
that contradicts the invariant is out of date, and the invariant wins.
