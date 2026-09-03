# Entire CLI — local binary setup

This documents the machine-level half of Entire checkpoint capture: where the
binary lives and why the wiring to it is silent when it breaks. The
project-level half (what checkpoints are, the commit trailer, the branch
convention) is documented in `CLAUDE.md` under "Observability (Entire
checkpoints)" — read that first. This file is the recovery note for when
capture quietly stops working.

## Where the binary is

`Prok\entire-cli\` — a sibling of this repository inside the working folder
(`Prok\`), **outside** the git working tree (`Prok\Prok\`). Confirmed with
`git status --ignored` / `git check-ignore` run against that path from inside
the repo: git refuses both, reporting the path as outside the repository
entirely. It is not tracked, not ignored, not visible to git in any way — it
cannot end up in this repo's history by accident, and `.gitignore` plays no
role either way.

- Binary: `entire.exe`, currently **v0.10.0** (`entire --version` /
  `entire version`) — Go 1.26.5, windows/amd64. Also present:
  `git-remote-entire.exe` and the release archive/checksums it was extracted
  from (`entire_windows_amd64.zip`, `checksums.txt`).
- Do not move this folder. It is not referenced by any path baked into the
  repo — nothing in `.claude/` or `.entire/` names it directly except the
  git hooks below.

## Two different wiring mechanisms — this is the part that isn't in the docs

Entire hooks into two separate systems, and they resolve the binary two
different ways:

**Git hooks** (`.git/hooks/{pre-push,commit-msg,post-commit,post-rewrite,
prepare-commit-msg}`) — installed with an **absolute path** baked in, e.g.:

```sh
if [ -f 'C:\Users\USER\Desktop\Prok\entire-cli\entire.exe' ]; then '...\entire.exe' hooks git pre-push "$1"; else :; fi
```

This is `.entire/settings.local.json`'s `"absolute_git_hook_path": true`
doing its job (equivalently `entire configure --absolute-git-hook-path`) —
documented, and exists specifically so GUI git clients (GitHub Desktop, which
this project's developer pushes from) that don't source a shell profile can
still find the binary. These hooks work regardless of PATH.

**Claude Code hooks** (`.claude/settings.json`, the `PreToolUse` /
`PostToolUse` / `SessionStart` / `SessionEnd` / `Stop` /
`UserPromptSubmit` entries) — every single one is a `sh -c` script that
starts with `command -v entire >/dev/null 2>&1 || exit 0`. **This is a PATH
lookup, and `--absolute-git-hook-path` does not touch it** — that flag's name
and its own `--help` text ("Embed full binary path in **git hooks**") only
ever promise to cover the git-hook side. There is no equivalent flag for the
agent-hook side found in `entire configure --help` or the README's option
table. This split isn't called out anywhere in the README — it was found by
reading the generated hook files directly, not from documentation. If capture
stops working, this is the first thing to suspect, and re-running
`entire configure --absolute-git-hook-path` will **not** fix it.

**Codex hooks** (`.codex/hooks.json`, added 2026-08-17 via `entire agent add
codex`) — the same shape and the same PATH-lookup caveat as the Claude Code
hooks above (`SessionStart` / `PostToolUse` / `Stop` / `UserPromptSubmit`,
each a `command -v entire` guard). `entire agent list` shows which agents are
currently wired (`✓ claude-code`, `✓ codex`); `entire agent add <name>` /
`entire agent remove <name>` install or uninstall a given agent's hook file.
`.entire/settings.json`'s `enabled` / `strategy_options.push_sessions` are
project-level, not per-agent — Codex checkpoints are subject to the same
"stays local, doesn't auto-push" rule as Claude Code's, with no separate
setting to check.

Practically: Claude Code (and, as of 2026-08-17, Codex) session capture
(transcripts, checkpoints) depends entirely on `Prok\entire-cli` being
present in **PATH at the time the agent process itself was launched**.
Renaming/moving the folder, or removing it from PATH, breaks capture with no
error — the `SessionStart` hook does print a warning (`entire CLI is enabled
but not installed or not on PATH`), but only in that agent's own session
transcript, which is exactly the thing that then fails to get captured. It is
easy to not notice.

One more sharp edge found while setting this up: a Windows user-PATH change
(via System Properties, `setx`, etc.) only lands in the registry — it is not
retroactively visible to already-running processes, including whatever
parent shell/launcher started Claude Code. A stale Claude Code process (or a
terminal opened before the PATH edit) will keep failing `command -v entire`
even though `echo $PATH` in a *freshly opened* window shows the folder is
there. If capture isn't working, check that the current process was actually
started after the PATH change, not just that the PATH change was made.

## What Entire is, and the three rules around it

Moved out of `CLAUDE.md` on 2026-09-03 (work plan Task 4): this is the named
home for it, and the invariant file keeps only the rules plus a link here.

[Entire](https://entire.io) (`entireio/cli`, preview software) is enabled for
Claude Code and, since 2026-08-17, Codex. Its config is `.claude/settings.json`,
`.codex/hooks.json` and `.entire/settings.json`; `entire agent list` shows which
agents are wired, `entire agent add <name>` / `remove <name>` install and
uninstall one.

On a commit made during a captured session, Entire's Git hooks add an
`Entire-Checkpoint` trailer to the commit message and store that session's
transcript, prompts, tool calls and token usage on a separate
`entire/checkpoints/v1` branch — *why* a change was made, next to Git's own
record of *what* changed. Review locally with `entire checkpoint list` /
`entire checkpoint explain`, or at entire.io once pushed.

**A checkpoint is raw session evidence, not a decision.** It does not replace a
`CHANGELOG.md` entry, which stays a curated record of *why a change was
accepted*. A checkpoint existing is not a reason to skip or shorten the entry.

**`entire/checkpoints/v1` is Entire's own branch, not a feature branch.** Do not
check it out to work on it, do not merge it into `main`, do not
delete/prune/force-push it, and do not run history-rewriting cleanup against it.
CI is deliberately not triggered on it either.

**Auto-push is off, and stays off.** `origin` (`github.com/Nolavel/ADT`) is
public, and captured sessions can contain non-public material — narrative canon,
unresolved design questions, discussion content — that the author considers
confidential. `.entire/settings.json` sets
`strategy_options.push_sessions: false` (`entire configure --project
--skip-push-sessions`), which disables only the pre-push hook's automatic push
of that branch; capture itself is a separate `enabled` setting, left `true`.
This is a **project** setting, not a local one, specifically so a fresh clone
(there are two contributors) cannot silently re-enable the leak. Do not
re-enable `push_sessions` and do not push that branch by hand without
confirming with the author first.

Note: `entire status`'s "Checkpoints sync to: origin" line does **not** reflect
this setting — it names where a push *would* go if one happened, not whether one
will. See the section below for how to actually check.

## How to check capture is alive

```sh
command -v entire            # must resolve inside the Claude Code session's own shell, not just a fresh terminal
entire --version              # expect: Entire CLI 0.10.0
entire session list           # expect: at least the current session listed, once one has run
entire status --detailed      # expect: "● Enabled" and "Agents · Claude Code"
```

If `command -v entire` fails inside a Claude Code tool-shell but succeeds in
a normal freshly-opened terminal, the Claude Code process itself is running
with a stale PATH — restart Claude Code (a full process restart, launched
from a shell/shortcut opened after the PATH change), not just start a new
session inside the same running instance.

`entire status --detailed` and `entire status --json`'s
`checkpoint_sync_remote` field describe where a checkpoint push *would* go
(default: same remote as `origin`, until `checkpoint_remote` is set) — they
do **not** reflect whether auto-push is enabled at all. Do not use "does the
sync-target line still say origin" as a signal for whether push is
happening; see `CLAUDE.md`'s Entire section for the setting that actually
controls that (`strategy_options.push_sessions`).
