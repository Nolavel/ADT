# AGENTS.md

This file exists only because Codex looks for `AGENTS.md` specifically —
it is a pointer, not a second copy.

**Read `CLAUDE.md` in full before making any change in this repository.**
It is the single source of truth for this project: hard constraints
(GDScript-only, Forward+ renderer, tuned shadow settings), architecture and
autoload contracts, naming conventions, and workflow rules (update `CLAUDE.md`
and `CHANGELOG.md` in the same commit as any change they describe).
`CLAUDE.md` also indexes the rest of `docs/` (architecture, style guide,
contribution rules, scope) — follow those links from there rather than from
here.

Do not duplicate `CLAUDE.md`'s project content into this file. The operational
boundary below is intentionally Codex-only and therefore does not belong in
the shared Claude instructions.

## Codex-only verification boundary

- Rendering, in-editor inspection, and Godot runtime verification belong to
  Stan. Report what needs visual checking and leave that check to him.
- Do not download, install, or launch Godot or another rendering/runtime tool.
  Do not start the project or a render probe unless Stan explicitly requests
  that exact action in the current conversation.
- An unavailable MCP/editor endpoint proves only that Codex cannot reach the
  endpoint. Never infer or state that the editor itself is closed.
- Static analysis and repository-only checks remain Codex responsibilities.
