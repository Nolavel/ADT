# Four drifts, and what was done about them

**Invariant this belongs to:** `CLAUDE.md`, Workflow rules — "Update `CLAUDE.md`
in the same commit", and the three-genre split in this directory's `README.md`.

`CLAUDE.md` is the compiled knowledge layer for this repository: agents read it
instead of re-deriving state from source. Four times, what it said stopped
matching what the repository contained, and each time it cost real debugging.

| # | Drift | Lived for | Fixed |
|---|---|---|---|
| 1 | Several `WORLD_SYSTEM_SCRIPTS` entries existed in `world.gd` but not here | — | — |
| 2 | The renderer constraint said Forward Mobile while the project ran Forward+ | ~3 weeks | 2026-08-12, see `renderer_forward_plus.md` |
| 3 | (same paragraph, counted separately at the time) | | |
| 4 | The C# claims — a file that never existed, a `[dotnet]` block explained wrongly | | 2026-08-27, see `no_csharp_here.md` |

**The mechanism, which matters more than the count.** On 2026-08-25 this file
had reached **94 KB with single paragraphs over 4000 characters**. A document
that dense does not get edited: an agent opening it appends to the end rather
than correcting the middle, and a newer paragraph contradicting an older one is
exactly how every drift above happened. That is what forced the split into
`docs/architecture/` — six per-system contract files, each authoritative for its
own contracts.

**And the same mechanism recurred at a different scale.** By 2026-09-03
`CLAUDE.md` had grown back to 27 KB, this time not with contradictions but with
archaeology: "this line previously claimed…", "fourth recorded drift",
"measured 2026-09-02, six taps produced six latches and zero reads". Both
external reviewers got the save contract wrong specifically where documentation
was densest. The answer was the three-genre split this directory implements —
the rule stays upstairs in present tense, the story comes down here.
