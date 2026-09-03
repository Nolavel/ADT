# The verification ladder: what each rung measures, and what it cost to learn

**Invariant this belongs to:** `CLAUDE.md` — the CLI verification section.

## Why the import pass runs twice

Measured on a genuinely cold cache, 2026-08-28. Pass one takes **36 s** and
prints **17 `ERROR` lines that are all false** — four `Cannot infer the type
of X`, plus a failure to load the project font. It compiles scripts before the
autoloads they reference exist. Pass two takes **31 s** and is completely
silent.

CI reflects this exactly: the first pass is run **ungated on purpose**, the
second is the authoritative one.

## Why the gate is the log and never the exit code

**Godot exits 0 even when a script fails to parse.** A run that returns success
proves nothing. Every gate in this project — local and in
`.github/workflows/godot.yml` — greps the log for `ERROR` / `SCRIPT ERROR` at
line start.

## Why `--check-only --script` is not the shortcut it looks like

It compiles one script with no autoloads registered, so every file touching
`PlayerState`, `InputSystems` or `WorldSystems` reports `Identifier not found`.
Measured: **36 of 120 files**, all false. The import pass is the tool.

## The gap that cost the most: headless never draws

The dummy driver never compiles a shader and never calls `_draw()`. A spring in
`dynamic_cursor_ui.gd` diverged to NaN and printed **7714 warnings in one
session** — six per frame, forever — while every headless check stayed silent
and green. The report came from Stan playing the game, not from any check here.

`tools/render_probe/render_probe.sh` was written in response (2026-08-28). It
runs the game under Xvfb on software OpenGL and writes a PNG sequence with
Godot's own `--write-movie`. It is the **Compatibility** renderer and the
project ships **Forward+** — there is no software Vulkan in an agent container —
so geometry, placement, orientation, silhouette and UI layout are trustworthy
and lighting, shadows, fog and post are not.

## Why CI counts warnings instead of de-duplicating them

An earlier version of `.github/workflows/godot.yml` ended its warning summary
with `sort -u`. That meant one warning and seven thousand identical ones looked
the same on the run page — which, given the NaN spring above, is precisely the
signal it was throwing away. Warnings are now reported **with their counts**, and
a warning repeating more than 50 times fails the run: at that volume it is
per-frame code, not a notice.
