# `project.godot` does not keep comments

Archive. The rule is in `CLAUDE.md` under Style conventions; this is the
evidence.

**What happened.** Work plan Task 3b added a `[debug]` section to
`project.godot` enabling two GDScript analyzer warnings, with fifteen lines of
comment above them: that they are warnings and not errors deliberately, that
flipping them is Stan's decision, and — the part that took a measurement to
establish — that they are **editor-only** and CI can never see them, so a green
run says nothing about them.

Commit `e3a2be4` (Stan, 2026-09-03) shows `project.godot` at `-16` lines. The
two settings survived intact. **Every line of comment was gone.**

**Why.** Not an edit by hand. The Godot editor rewrites `project.godot` from its
in-memory `ProjectSettings` whenever settings are saved, and that serialiser
emits key/value pairs only. Anything a human typed between them is not part of
the data model and does not survive the round trip. Opening the project and
changing any setting is enough.

**What it costs.** The measurement is the expensive half. "These warnings never
reach the CLI" was established by adding a deliberately untyped function to an
autoload and observing zero output from both `godot --headless --editor` and
`godot --headless`. That finding is what stops the next person reading a green
CI run as evidence about typing. It cannot live next to the setting it is about.

**What was NOT the lesson.** Not "do not write comments" and not "do not touch
`project.godot`". The settings themselves round-trip perfectly well; it is only
prose that evaporates.

Same family as `.import` files, which Godot also owns and rewrites — see
`docs/postmortems/import_files_and_uids.md`. The general shape: a file the
engine generates is a place to put values, never a place to put reasoning.
