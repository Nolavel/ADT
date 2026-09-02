# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Chronology of changes lives in `CHANGELOG.md` — read it when you need to know *when*
something changed, or what work is currently in flight in a parallel session. For
*how the project works right now*, this file is authoritative; do not reconstruct
current state by replaying the log.

## Project

Godot 4.7 (Forward+ renderer) project. Repository `ADT`; internal build name **"Vertical Trespass"** (`config/name`); public title **"Another Digital Thriller"** — use the public title only in store-facing material, never in code or docs. **Entirely GDScript.** Do not introduce C#; the codebase convention is GDScript. This line used to name `tools/scan_folder_files/project_scanner.cs` as "the only C# file" and called dropping C# an open backlog item — that file has never existed (`git log --all --diff-filter=AD -- '*.cs'` finds nothing; the path holds `project_scanner.gd`), so the backlog item was closed by never having started. `project.godot` carries an empty `[dotnet] assembly_name="ADT"`, and the earlier claim here that this came from "someone opening the project once in the .NET editor" was wrong: a screenshot of Stan's editor on 2026-08-28 shows `4.7.stable.mono` in the status bar — **the .NET build is the editor he works in every day**. What still holds is the substance: there is no C# in this repository, no `.csproj` and no `.sln`, and none should be added. The `[dotnet]` block is what the .NET editor writes for any project it opens, not a sign that anyone intended C#. Corrected 2026-08-27 — fourth recorded drift in this file.

## Working with the running editor
Startup scene: `res://world/world.tscn`.

## Documents

| File | Purpose |
|---|---|
| `docs/ARCHITECTURE.md` | **Architecture and the reasoning behind the contracts, with diagrams.** Human-facing counterpart to this file — read it before any structural change. |
| `docs/architecture/*.md` | **The per-system contracts**, split out of this file on 2026-08-25. Six files: autoloads/bootstrap, world streaming, player/camera, NPCs/incidents, items/equipment, persistence. See the Architecture section below for which covers what. |
| `docs/CONTRIBUTING.md` | What a collaborator may pick up, what is off-limits, contribution terms |
| `docs/GDSCRIPT_STYLE.md` | Code conventions; stricter than the official Godot guide in places |
| `docs/planned_scope.md` | Scope that is **not started**. Not a task list. |
| `docs/attribution.md` | Observation → Incident → Report → Attribution design. Only §7 (the witness vertical slice) is in the horizon; the rest is deliberately unbuilt. |
| `docs/CREDITS.md` | Third-party attributions, incl. the Godot MIT notice |
| `input_map.md` | Single source of truth for input bindings |
| `LICENSE.md` | Proprietary; all rights reserved |
| `docs/scope_horizon.md` | What is being built **now**, and in what order |
| `docs/ENTIRE_SETUP.md` | Entire CLI binary location, PATH dependency, git-hook vs Claude-Code-hook wiring, how to check capture is alive |
| `docs/COLLISION_LAYERS.md` | Single source of truth for 3D physics layers and the named query-mask profiles built from them |
| `docs/ITEM_FITTER.md` | **How to actually use the Item Fitter dock** — which scene must be open, the fit-against-an-animation step, what it writes, and the two ways it silently does nothing |
| `docs/MORPHS_INTEGRATION.md` | Morph icons — what a `MorphIcon` is, attaching one to a widget in the editor, and writing the next one |
| `docs/visual_language.md` | **How the game looks and states things** — the comic/noir frame, the onomatopoeia rules, and how the comic layer relates to archetype readability, BlackRock and the Votive. Artist- and animator-facing. |
| `docs/island_rescope_brief.md` | Island transition (Aogashima) — ordered steps, numbers, hard constraints |
| `docs/3D_ART_BIBLE.md` | **Immutable visual style contract.** Form-language hierarchy (silhouette → primary → secondary → accent → surface), character/vehicle/prop/environment rules, the AI-prompt formula in §12. Read before any asset-creation or Blender-generation task — see `docs/blender_task_template.md` for how to apply it. |
| `docs/blender_task_template.md` | Two working paths for Blender MCP tasks (direct bpy geometry vs Hyper3D generation) and which `3D_ART_BIBLE.md` sections apply to each. Use its prompt skeletons rather than freestyling a style description. |

**Two addons, and the split is deliberate.** `addons/godot_ai/` is the MCP server below; `addons/item_fitter/` is an `EditorPlugin` dock for fitting a held item to the hand (see `docs/architecture/items_and_equipment.md`). Everything else that could be called tooling lives in `tools/`, which holds three kinds of thing: one-shot `EditorScript`s run with File → Run (the island heightmap, the terrain build, the city and block generators — each the only reproducible path to committed content), runtime debug panels instanced into `world.tscn` (`input_debugger`, `stats_display`, `scan_folder_files`), and — since 2026-08-28 — `render_probe/`, a shell script that runs the game on software OpenGL under Xvfb and leaves PNG frames on disk. That third kind exists because the other verification here is blind to drawing; see the verification section below. A tool goes in `addons/` only when it needs what an `EditorPlugin` alone provides — a dock, the editor's own 3D gizmo on a live node, and surviving a scene switch. `item_fitter` needs all three; nothing else in the project does.

This repo has the **godot-ai MCP server** wired in (`addons/godot_ai/`, enabled in `project.godot` under `[editor_plugins]`, autoloaded as `_mcp_game_helper`). When the Godot editor is open, prefer the `mcp__godot-ai__*` tools over hand-editing `.tscn`/resource files or shelling out to the Godot CLI:
- `editor_state` — check what scene is open / whether the editor is ready before issuing other calls.
- `scene_open` / `scene_get_hierarchy` / `node_*` — inspect and mutate the live scene tree (safer than hand-editing `.tscn` text for structural changes).
- `script_create` / `script_attach` / `script_patch` — create/edit/attach GDScript.
- `project_run`, `logs_read`, `test_run` — run the game and read Godot's output instead of guessing at runtime behavior.

There is no separate unit-test framework (no GUT etc.); "testing" a change means running the project (`project_run` / F5 in editor) and watching `logs_read` for the `push_error`/`push_warning`/`print` diagnostics the systems below emit liberally.

**In an agent session, use the Godot CLI instead of guessing.** Sessions on claude.ai/code run in a throwaway container with no Godot; `.claude/hooks/ensure_godot.sh` installs it at session start (4 s from cold — the proxy caches the download) and does nothing when `godot` is already on `PATH`, so it is inert on a developer machine. Three commands cover nearly everything an agent used to hand back unverified:

- `godot --headless --editor --quit-after 2000` — imports the project and reports every script parse error and broken resource path in one pass. **Run it twice on a cold container:** the first pass compiles scripts before the autoloads they reference exist and invents `Cannot infer the type of X` errors that vanish on the second. Measured on a genuinely cold cache 2026-08-28: pass one takes 36 s and prints **17 `ERROR` lines that are all false** (four `Cannot infer the type of X`, plus a failure to load the project font); pass two takes 31 s and is completely silent. Neither pass is judged by its exit code — **Godot exits 0 even when a script fails to parse**, so what is read is the log.
- `godot --headless --quit-after 400` — actually boots `world.tscn`. No rendering (dummy driver), but autoloads, `_ready()`, physics and every `print`/`push_warning` are live. This is what catches a spawn landing inside the terrain, a system that silently fails to initialize, or a save payload that does not round-trip.
- A temporary `print` in a `_ready()` — run, read, revert — answers what no existing log line covers: where the player actually ended up, whether `is_on_floor()` is true. Never commit the probe.

**`--check-only --script` is a trap here.** It compiles one script with no autoloads registered, so every file touching `PlayerState`, `InputSystems` or `WorldSystems` reports `Identifier not found` — 36 of 120 files, all false. Use the import pass instead.

What the CLI still cannot tell you is anything visual. The terrain is drawn by a vertex-displacement shader the dummy driver never runs, so headless proves the player stands on the ground but not that the ground looks like ground. Held-item offsets, clipping, terracing and silhouette all still need eyes.

**Headless cannot see drawing at all, and that gap has cost real time.** The dummy driver never compiles a shader and never calls `_draw()`. A spring in `dynamic_cursor_ui.gd` diverged to NaN and printed **7714 warnings in one session** — six per frame, forever — while every headless check stayed silent and green, and the report came from Stan playing the game, not from any check here. Treat "the ladder is clean" as saying nothing whatsoever about anything on screen.

`sh tools/render_probe/render_probe.sh [frames] [out_dir]` closes part of that. It runs the game under Xvfb on software OpenGL and writes a PNG sequence with Godot's own `--write-movie`, so a change can be looked at. Read its header before trusting a frame: it is the **Compatibility** renderer and the project ships **Forward+** (there is no software Vulkan in an agent container), so geometry, placement, orientation, silhouette and UI layout are trustworthy and lighting, shadows, fog and post are not. A screenshot answers "is the rifle across the hands", never "does the noir look right".

**Since 2026-08-28 the ladder also runs in CI**, so it no longer depends on whoever remembers it. `.github/workflows/godot.yml` runs on every pull request and on a push to `main`: it reuses `.claude/hooks/ensure_godot.sh` (so the engine version is pinned in exactly one place, and bumping it there busts the CI cache automatically), runs the import twice with **only the second pass gated** for the reason above, then boots `world.tscn`. The gate is a grep for `ERROR` / `SCRIPT ERROR` at line start, never the exit code. Warnings do **not** fail a run — two are long-standing on `main` (`NavigationRegion3D not found`, `non-equal opposite anchors`) — but every unique warning is printed into the run summary so a new one is visible without turning the known pair permanently red. Logs are uploaded as an artifact on failure. Warnings are reported **with their counts** — an earlier version of this workflow de-duplicated them with `sort -u`, which meant one warning and seven thousand identical ones looked the same; a warning repeating more than 50 times now fails the run, because at that volume it is per-frame code and not a notice. A second job, `Render`, runs `render_probe.sh`, gates the render log the same way, and uploads the last frame on **every** run so the build can be looked at without checking it out.

Two things that green check does **not** mean. It says nothing about how anything looks, per the paragraph above. And it does not cover an **orphan script**: a `.gd` file that no scene, autoload or other script references is never compiled by the import pass, so a syntax error in it passes CI (measured — a deliberate break in `core/input/input_systems.gd` produced 14 gated lines on the import pass and 18 on the boot, while the same break in an unreferenced file produced none). `--check-only --script` is not the fix for that; see the trap above. A new file wired to nothing is the case to check by hand.

The workflow is deliberately **not** triggered on `**` — `entire/checkpoints/v1` is Entire's own branch and nothing in CI should ever check it out. Do not widen the push trigger.

## Observability (Entire checkpoints)

This repo has [Entire](https://entire.io) (`entireio/cli`, preview/pre-release
software) enabled for Claude Code and, as of 2026-08-17, Codex —
`.claude/settings.json`, `.codex/hooks.json`, and `.entire/settings.json` are
its config (`entire agent list` shows which agents are currently wired;
`entire agent add <name>` / `entire agent remove <name>` install/uninstall
one). On a commit made during a captured session, Entire's Git hooks add an
`Entire-Checkpoint` trailer to the commit message and store the session
transcript, prompts, tool calls, and token usage for that commit on a
separate `entire/checkpoints/v1` branch — *why* a change was made, next to
Git's own record of *what* changed. Review locally with `entire checkpoint
list` / `entire checkpoint explain`, or at [entire.io](https://entire.io)
once pushed.

A checkpoint is raw session evidence, not a decision — it does **not**
replace a `CHANGELOG.md` entry, which stays a deliberately curated record of
*why a change was accepted*, written in the same commit per this file's own
rule above. Keep writing both; a checkpoint existing is not a reason to skip
or shorten the changelog entry.

`entire/checkpoints/v1` is Entire's own branch, not a normal feature branch:
do not check it out to work on it, do not merge it into `main`, do not
delete/prune/force-push it, and do not run history-rewriting cleanup against
it.

**Checkpoints stay local — auto-push is off.** `origin` (`github.com/Nolavel/ADT`)
is public, and captured sessions can contain non-public material (narrative
canon, unresolved design questions, discussion content) that the author
considers confidential. `.entire/settings.json` sets
`strategy_options.push_sessions: false` (`entire configure --project
--skip-push-sessions`), which disables only the pre-push hook's automatic
push of `entire/checkpoints/v1` — capture itself (recording sessions,
writing checkpoints, the commit trailer) is unaffected; that's a separate
`enabled` setting, left `true`. This is a **project** setting, not a local
one, specifically so a fresh clone (there are two contributors) doesn't
silently re-enable the leak. Don't re-enable `push_sessions`, and don't push
`entire/checkpoints/v1` manually, without confirming with the author first.
Note: `entire status`'s "Checkpoints sync to: origin" line does **not**
reflect this setting — it names where a push would go if one happened, not
whether one will; see `docs/ENTIRE_SETUP.md` for how to actually check.

## Style conventions

- `INPUT_MAP.md` is the **single source of truth for input bindings** (verified against `project.godot` 2026-07-29, 29 actions) — update it whenever an action is added/removed/rebound in Project Settings → Input Map (`project.godot` `[input]`).
- Full conventions live in `docs/GDSCRIPT_STYLE.md`; collaborator-facing rules in `docs/CONTRIBUTING.md`. Read the style guide before writing GDScript.
- **New comments are written in English.** Existing comments are largely Russian and are being translated header by header; do not add more Russian.
- **Standing instruction when editing an existing script:** before changing it, check it against `docs/GDSCRIPT_STYLE.md` — static typing, declaration order, naming, banner header on systems, `TODO(scope):` form. If the file deviates, say so and offer the correction as a separate step. Do not silently reformat, and do not bundle a style pass into a behaviour change.
- **`*.import` files are committed; `.godot/` is not.** Godot 4 stores an imported asset's UID inside its `.import` file, so ignoring them makes every clone mint its own UIDs while the `.tscn` files that reference those assets keep whoever-committed-them's — which is exactly why a fresh clone used to open with 28 `invalid UID` warnings and a project font that failed to load. This is Godot's own recommended layout; `.gitignore` says so at the line where it used to ignore them.
- **Do not create placeholder scripts or empty directories** for work that has not started. Planned scope belongs in `docs/planned_scope.md`. An empty file in the tree reads as a promise.
- **Collision layers and masks are set through `core/physics/collision_layers.gd` (`CollisionLayers`), never as a bare integer literal**, in both code and scenes. `docs/COLLISION_LAYERS.md` is the single source of truth for the layer table and the reasoning behind each named query profile (`SIGHT`, `CAMERA_OCCLUSION`, `OBSTACLE`, `GROUND`, `INTERACTION`, `CURSOR_UI`). A `.tscn` can't reference a script constant, so a scene-level mask is documented in that file's table instead of converted. A new layer is named in `project.godot`'s `[layer_names]`, given a constant in `CollisionLayers`, and given a row in `docs/COLLISION_LAYERS.md`, all in the same commit — never one without the other two.
 
## Architecture

The contracts below are stated here as rules to follow. The reasoning behind
them, the boot sequence, the streaming state machine and the save contract are
explained with diagrams in `docs/ARCHITECTURE.md` — read that before making a
structural change, not just this summary.

**The per-system contracts live in `docs/architecture/`.** They were split out
of this file on 2026-08-25: it had reached 94 KB with single paragraphs over
4000 characters, and a document that dense does not get edited — agents append
to the end rather than correct the middle, which is where the drift this file
keeps suffering actually comes from. Read the one that covers what you are
touching; each is authoritative for its own contracts.

| File | Covers |
|---|---|
| `docs/architecture/autoloads_and_bootstrap.md` | The four autoloads, `world.gd`'s three declarative lists, `on_world_ready()`, node groups |
| `docs/architecture/world_streaming.md` | `WorldData`/`BlockData`, `BlockBase` markers, streaming conventions, spawn |
| `docs/architecture/player_and_camera.md` | `player.gd`'s two movement modes, camera components, transport, stance and aiming, key hints |
| `docs/architecture/npc_and_incidents.md` | `ActorBase`/`NPCBase`/`DroneBase`, archetypes, reactions, the witness chain, `IncidentRegistry`, `ComicEffectSystem` |
| `docs/architecture/items_and_equipment.md` | `ItemCatalog`, `EquipmentComponent`, equipment visuals, slot data, `MorphIcon` |
| `docs/architecture/persistence.md` | The save contract, `SaveSystem`, `PlayerPersistenceSystem`, `LodgingSystem`/`LodgingRoom`, `ActorBase.actor_id` |

**The rule that made the split necessary applies to these files too:** when a
contract changes, correct the paragraph that states it, in the same commit as
the change. Appending a newer, contradictory paragraph below the old one is how
this went wrong the first time.

# Project Rules (Vertical Trespass)

## Hard constraints — do not suggest changing these
- Renderer: **Forward+** — this is what `project.godot` actually runs (no `renderer/rendering_method` override is set, so the Forward+ default applies). Switched from Forward Mobile on 2026-07-21, accepting a ~20–25% FPS cost on the development machine in exchange for access to the full lighting and post stack (volumetric fog, SSIL, SSR, `AreaLight3D`), which the game's noir look depends on. The performance target is low-end integrated graphics at ~55 FPS — the budget is tight and every effect added is a real cost, but Forward+ features are not off-limits. Do not switch back without explicit discussion.
  - This line previously claimed Forward Mobile and forbade Forward+ features outright, contradicting both `project.godot` and the header of this file for roughly three weeks. Third recorded drift of this kind; see the `CLAUDE.md` update rule under Workflow.
- **GDScript for all gameplay code, and for everything else.** There is no C# in this repository and there never has been — see the correction in the Project section above. Do not introduce any.
- `lights_and_shadows/directional_shadow/size` is tuned to 1024 for the FPS target — don't raise it. (This is the directional shadow map, not the positional shadow atlas; `shadow_atlas/size` is not overridden and sits at its default.) Both soft-shadow filter qualities are set to 0 for the same reason.

## Architecture rules
- **How two systems learn about each other — pick one, in this order:**
  - **`WorldContext`** — composition and runtime dependencies. Default choice.
  - **Autoload** — genuinely global state or service. Closed set: the existing four plus the MCP helper. Additions require explicit discussion.
  - **Signal** — event notification, one-to-many, sender does not care who listens.
  - **Group** — discovery and tagging, for nodes that never receive a `WorldContext` (static scene instances such as `DroneBase`, `PatrolDroneController`, `LodgingRoom`).
- **No new autoloads.** Scene-scoped systems are plain Node instances owned by `world.gd` via the `WORLD_SYSTEM_SCRIPTS` declarative list; they are instantiated with `.new()` and initialized through `on_world_ready(context: WorldContext)`.
- Prefer **explicit reference passing** over group lookups or singleton access by class name.
- `PlayerState` (existing autoload) is the single source of truth for `Mode` and `ViewMode`. Do not create parallel state enums.
- **Only `InputSystems.gd` reads `Input` directly.** Exceptions: `map_source/` and `map_camera/` — these are intentional level-design tools using raw `KEY_*` input; do not refactor them.
- **Inside `InputSystems`: edges come from events, levels come from polls.** A discrete press or release is matched on the `InputEvent` (keyboard in `_unhandled_input()`, mouse in `_input()` — see `docs/architecture/autoloads_and_bootstrap.md` for why they differ); held state and axes stay as `Input.is_action_pressed()` / `get_vector()` in `_physics_process()`. Do not add a new `Input.is_action_just_pressed()` anywhere: polling an edge from the physics frame drops presses as soon as the idle and physics rates diverge (measured 2026-09-02 — 120 taps arrive as 42 at 5 Hz physics, and as 120 through the event path at every rate tested). A query method that has to stay a poll is answered from the edge latch in that file, never from `Input` directly.
- Streaming: `_packed_cache` is non-optional (`load_threaded_get()` consumes the task; shared-path cells would false-fail without it). Do not change streaming budgets/radii (`STREAM_RADIUS`, `MAX_CONCURRENT_LOADS`, `INSTANTIATION_BUDGET_PER_FRAME`, etc.) without explicit discussion first.

## Naming conventions
- Files/folders: `snake_case`. Node/class names: `PascalCase`.
- Semantics: **Component** = attached to a specific owner entity (e.g. `StaminaComponent`, not `StaminaManager`); **Manager** = owns a collection of instances; **System** = single cross-cutting orchestrator.

## Language policy
- **New code and comments: English**, readable for future collaborators, following Godot community standards.
- **Existing Russian comments/strings: leave as-is** — they will be migrated during planned refactoring passes, not opportunistically. When editing a file that is already in Russian, do not translate untouched parts; new additions within it are still written in English.

## Workflow rules
- Propose architectural concerns and design **before** writing code for significant systems.
- Ask clarifying questions when the picture is incomplete; do not brute-force solutions or guess.
- `addons/godot_ai/` and its `project.godot` entries are committed intentionally (local AI tooling, MIT) — do not suggest removing them.
- - **Update `CLAUDE.md` in the same commit.** When an architectural decision, a system's contract, or the *meaning* of a tunable changes, update the matching section here as part of that change — not as a later cleanup pass. This file is the compiled knowledge layer for the repo: agents and future collaborators read it instead of re-deriving state from source. It has already drifted twice (the renderer constraint contradicted itself for ten days; several `WORLD_SYSTEM_SCRIPTS` entries existed in `world.gd` but not here), and each drift cost real debugging time.
- **Append to `CHANGELOG.md` in the same commit.** Every meaningful change gets a dated entry: what changed in substance, which systems/files it touched, and — if the work came from a parallel session — a note saying so. Add to the existing day's entry if one exists, otherwise open a new one at the top. Keep entries to a few lines; English primary, with a one-line Russian gloss in italics matching the existing style. This is the only mechanism by which parallel work sessions stay aware of each other — an unrecorded change is invisible to the next session.
