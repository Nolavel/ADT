# Vertical Trespass

Noir open-world action prototype set in the vertical city of Blackrock.
Solo project, in active development. Not a shipping game — a prototype.

**Engine:** Godot 4.7 · Forward+ renderer · GDScript
**Status:** prototype. World streaming, player movement, camera and hover
transport are implemented. Combat, AI, missions and saving are not.

> Нуарный опенворлд-прототип в вертикальном городе Блэкрок.
> Соло-проект в активной разработке.

## A note on names

This project carries two names, deliberately.

**Vertical Trespass** is the internal working title. It is formal — it names
the build, the window title and `config/name`, and it is the name used
throughout the code and documentation. It is not a marketing name and is not
intended to be one.

**ADT — Another Digital Thriller** is the public name. It is what the
repository is called, what appears on itch.io and store pages, and the name
the project will carry if it goes commercial.

Use the internal name in code, commits, documentation and issues. Use the
public name in anything a player or a storefront will see. Do not mix them.

---

## Run

Main scene: **`world/world.tscn`** — player, camera, game systems and the
city streaming pipeline are brought up automatically by `world/world.gd`.

There is no test framework. Verifying a change means running the project
(F5) and reading Godot's output — the systems log their state transitions
deliberately.

## Controls

**`input_map.md` is the single source of truth for bindings.** Summary:

**On foot** (`ISOMETRIC` ⇄ `TPS` — `V`)

| Key | Action |
|---|---|
| RMB | move to point; hold — run |
| `F` | interact: items, buttons, boarding a hover |
| `Q` / `E` | orbital camera step |
| `P` | toggle camera follow |
| Wheel | zoom |
| `W A S D` | direct movement (TPS only) |

**Hover**

| Key | Action |
|---|---|
| `W A S D` | thrust / strafe |
| `Space` / `Ctrl` | ascend / descend; release — altitude hold |
| `V` | camera CHASE ⇄ COCKPIT |
| `F` | exit (near-zero speed only) |

**Global:** `Esc` — pause menu. `\` — streaming debug panel.

## Layout

| Path | Purpose |
|---|---|
| `core/` | Autoloads and systems: `PlayerState`, `InputSystems`, streaming, transport |
| `player/` | Player scene and components (interact, inventory, stamina, nav) |
| `camera/` | Camera host + per-mode components (on foot / hover / transit) |
| `world/` | `world.tscn`, block and ground-tile content and silhouettes |
| `tools/` | Editor tooling, incl. the greybox block generator |
| `data/` | Data resources: `world_data.tres`, items |
| `docs/` | Style guide, planned scope, current horizon |

## World editing

World data comes from **`map_source.tscn`** (block markers, spawn point).
Running that scene re-exports `data/world_data.tres`. Mass greybox
generation lives in `tools/block_generator/` (step A — block library,
step B — marker placement).

Markers named with the `GBX_` prefix are regenerated and **will be deleted**
on the next generator run. Rename a marker to drop the prefix to make it
hand-owned.

## For collaborators

Start with **`ARCHITECTURE.md`** — how the project is put together and
why, with diagrams. Then `docs/CONTRIBUTING.md` (what you can pick up, what
is off-limits) and `docs/GDSCRIPT_STYLE.md` (code conventions).

`CLAUDE.md` in the root is a working brief for Claude Code, the AI tool used
in the editor. It states the same contracts as rules to obey rather than
explaining them, and it is not an introduction to the project.

Most code comments are currently in Russian. Translation of the load-bearing
system headers to English is in progress; see `CONTRIBUTING.md` for which
files are already readable in English.

## Credits and licences

Third-party fonts, meshes and textures are credited in `docs/CREDITS.md`.
Anything borrowed is attributed there — please keep that file current when
adding assets.
