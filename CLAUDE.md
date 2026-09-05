# CLAUDE.md

Guidance for Claude Code (claude.ai/code) working in this repository.

**This file states invariants in the present tense: what is true now and what
must not break.** It carries no history. Why something was hard, what was
measured and what turned out false lives in `docs/postmortems/`, one link from
the rule it belongs to. When changes happened is `CHANGELOG.md` (entries before
2026-08-15: `CHANGELOG_2026-07..08.md`). Do not reconstruct current state by
replaying the log, and do not add archaeology here — see
`docs/postmortems/documentation_drift.md` for what that costs.

## Project

Godot 4.7, **Forward+**. Repository `ADT`; internal build name **"Vertical
Trespass"** (`config/name`); public title **"Another Digital Thriller"** — use
the public title only in store-facing material, never in code or docs.

**Entirely GDScript.** There is no C# here, no `.csproj`, no `.sln`, and none
should be added. The empty `[dotnet]` block in `project.godot` is what the .NET
editor writes for any project it opens; it is not a sign anyone intended C#.
→ `docs/postmortems/no_csharp_here.md`

Startup scene: `res://world/world.tscn`.

## Documents

| File | Purpose |
|---|---|
| `docs/NOW.md` | **Read first every session, update last.** The chat↔code handoff, capped at 80 lines. |
| `ARCHITECTURE.md` | Architecture and the reasoning behind the contracts, with diagrams. Read before any structural change. |
| `docs/architecture/*.md` | **The per-system contracts.** Six files; each is authoritative for its own. See the Architecture section below. |
| `docs/postmortems/*.md` | Why something was hard, what was measured, what turned out false. Archives — on any contradiction, the invariant here wins. Read `docs/postmortems/README.md` before adding one. |
| `docs/scope_horizon.md` | What is being built **now**, and in what order |
| `docs/planned_scope.md` | Scope that is **not started**. Not a task list. |
| `docs/CONTRIBUTING.md` | What a collaborator may pick up, what is off-limits, contribution terms |
| `docs/GDSCRIPT_STYLE.md` | Code conventions; stricter than the official Godot guide in places |
| `input_map.md` | Single source of truth for input bindings |
| `docs/COLLISION_LAYERS.md` | Single source of truth for 3D physics layers and the named query-mask profiles |
| `docs/blackrock_authorities.md` | BRPD / BRMA / `IrisAccess` — the two rungs of law enforcement and the credential seam. Design only; BRPD is the half that already exists. |
| `docs/attribution.md` | Observation → Incident → Report → Attribution design. Only §7 is in the horizon; the rest is deliberately unbuilt. |
| `docs/visual_language.md` | How the game looks and states things — comic/noir frame, onomatopoeia rules. Artist-facing. |
| `docs/3D_ART_BIBLE.md` | **Immutable visual style contract.** Read before any asset-creation or Blender task; `docs/blender_task_template.md` says how to apply it. |
| `docs/ITEM_FITTER.md` | How to actually use the Item Fitter dock, and the two ways it silently does nothing |
| `docs/MORPHS_INTEGRATION.md` | Morph icons — what a `MorphIcon` is, and writing the next one |
| `docs/ENTIRE_SETUP.md` | Entire CLI wiring, and how to check capture is alive |
| `docs/island_rescope_brief.md` | Island transition (Aogashima) — ordered steps, numbers, constraints |
| `docs/CREDITS.md` / `LICENSE.md` | Third-party attributions incl. the Godot MIT notice / proprietary, all rights reserved |

## Tooling

**Two addons, and the split is deliberate.** `addons/godot_ai/` is the MCP
server below; `addons/item_fitter/` is an `EditorPlugin` dock for fitting a held
item to the hand. A tool goes in `addons/` **only** when it needs what an
`EditorPlugin` alone provides — a dock, the editor's own 3D gizmo on a live
node, and surviving a scene switch. `item_fitter` needs all three; nothing else
does. Everything else lives in `tools/`: one-shot `EditorScript`s run with
File → Run (each the only reproducible path to committed content), runtime debug
panels instanced into `world.tscn`, and `render_probe/`.

**The godot-ai MCP server** is wired in (`addons/godot_ai/`, enabled under
`[editor_plugins]`, autoloaded as `_mcp_game_helper`) and is committed
intentionally — do not suggest removing it. With the editor open, prefer
`mcp__godot-ai__*` over hand-editing `.tscn` files or shelling out:
`editor_state` before anything else, `scene_open`/`scene_get_hierarchy`/`node_*`
for the live tree, `script_create`/`script_attach`/`script_patch` for GDScript,
`project_run`/`logs_read`/`test_run` to run and read output.

There is no unit-test framework (no GUT etc.). "Testing" a change means running
the project and reading the `push_error`/`push_warning`/`print` diagnostics the
systems emit liberally.

## Verification — run it, do not guess

Agent sessions get Godot from `.claude/hooks/ensure_godot.sh` at session start;
it is inert when `godot` is already on `PATH`.

- `godot --headless --editor --quit-after 2000` — import; every parse error and
  broken `res://` path in one pass. **Run it twice on a cold container:** the
  first pass compiles scripts before their autoloads exist and invents errors
  that vanish on the second.
- `godot --headless --quit-after 400` — boots `world.tscn`. No rendering, but
  autoloads, `_ready()`, physics and every print are live. This catches a spawn
  inside the terrain, a system that fails to initialize, a save that does not
  round-trip.
- A temporary `print` in a `_ready()` — run, read, revert. Never commit it.

**Godot exits 0 even when a script fails to parse. Gate the log, never the exit
code.** `--check-only --script` is a trap here — it invents `Identifier not
found` for a third of the project; use the import pass.
→ `docs/postmortems/verification_ladder.md`

**Headless cannot see drawing at all.** The dummy driver never compiles a shader
and never calls `_draw()`. "The ladder is clean" says nothing whatsoever about
anything on screen. `sh tools/render_probe/render_probe.sh [frames] [out_dir]`
closes part of that — read its header before trusting a frame: it is
**Compatibility** and the project ships **Forward+**, so geometry, placement,
orientation, silhouette and UI layout are trustworthy; lighting, shadows, fog
and post are not.

**CI runs the same ladder** (`.github/workflows/godot.yml`) on every pull
request and on a push to `main`, plus a `Render` job that uploads the last frame
on every run. It reuses `ensure_godot.sh`, so the engine version is pinned in
exactly one place. Warnings do not fail a run — two are long-standing on `main`
— but they are reported **with their counts**, and one repeating more than 50
times fails: at that volume it is per-frame code, not a notice. The push trigger
is deliberately restricted to `main`; `entire/checkpoints/v1` must never be
checked out by CI. **Do not widen it.**

**An orphan script is a machine rule now, not a habit.** A `.gd` nothing
references is never compiled, so a syntax error in it passes the import pass —
`tools/ci/find_orphan_scripts.py` runs in CI and fails on one. It matches by
path, by `uid://` and by `class_name`, and is deliberately biased toward
silence: a bare mention in a comment counts, because a check that fails on a
live file gets switched off and is then worse than none. Entry points that have
no caller by design (`EditorScript`s under `tools/`) live in that file's
`ALLOWED_ORPHANS`, one line and one reason each — never a blanket glob.
→ `docs/postmortems/orphan_scripts.md`

## Observability (Entire checkpoints)

[Entire](https://entire.io) captures each session — transcript, prompts, tool
calls, token usage — onto a separate `entire/checkpoints/v1` branch, and adds an
`Entire-Checkpoint` trailer to commits made during one. Three rules:

- **A checkpoint does not replace a `CHANGELOG.md` entry.** It is raw evidence;
  the entry is the curated record of *why* a change was accepted. Write both.
- **`entire/checkpoints/v1` is not a normal branch.** Do not check it out, merge
  it, delete/prune/force-push it, or rewrite its history. CI never touches it.
- **Auto-push is off and stays off** — `origin` is public and sessions can carry
  non-public material. Do not re-enable `push_sessions` or push that branch by
  hand without asking the author.

Everything else — the wiring, and how to check capture is actually alive —
is in `docs/ENTIRE_SETUP.md`.

## Style conventions

- Full conventions live in `docs/GDSCRIPT_STYLE.md`; collaborator-facing rules
  in `docs/CONTRIBUTING.md`. Read the style guide before writing GDScript.
- `input_map.md` is the **single source of truth for input bindings** — update
  it whenever an action is added, removed or rebound in `project.godot`
  `[input]`.
- **New comments are written in English.** Existing comments are largely Russian
  and are translated header by header; do not add more Russian.
- **Standing instruction when editing an existing script:** check it against
  `docs/GDSCRIPT_STYLE.md` first — static typing, declaration order, naming,
  banner header on systems, `TODO(scope):` form. If it deviates, say so and
  offer the correction as a separate step. Do not silently reformat, and do not
  bundle a style pass into a behaviour change.
- **Never write reasoning into `project.godot`.** The editor rewrites that file
  from `ProjectSettings` whenever settings are saved, and the serialiser emits
  key/value pairs only — comments do not survive, and the settings do. Values
  there, rationale in `docs/`.
  → `docs/postmortems/project_godot_comments.md`
- **`*.import` files are committed; `.godot/` is not.** Godot 4 stores an
  asset's UID inside its `.import` file, so ignoring them makes every clone mint
  its own while the `.tscn` files keep the committed ones.
  → `docs/postmortems/import_files_and_uids.md`
- **Do not create placeholder scripts or empty directories** for work that has
  not started. Planned scope belongs in `docs/planned_scope.md`. An empty file
  in the tree reads as a promise.
- **Collision layers and masks go through `CollisionLayers`
  (`core/physics/collision_layers.gd`), never a bare integer literal**, in code
  and scenes alike. `docs/COLLISION_LAYERS.md` is the single source of truth. A
  `.tscn` cannot reference a script constant, so a scene-level mask is
  documented in that file's table instead of converted. A new layer is named in
  `project.godot` `[layer_names]`, given a constant, and given a row in that
  document — all in the same commit, never one without the other two.

## Architecture

The contracts below are rules to follow. The reasoning, the boot sequence, the
streaming state machine and the save contract are explained with diagrams in
`ARCHITECTURE.md` — read that before a structural change, not just this summary.

**The per-system contracts live in `docs/architecture/`.** Read the one covering
what you are touching; each is authoritative for its own contracts.

| File | Covers |
|---|---|
| `docs/architecture/autoloads_and_bootstrap.md` | The four autoloads, `world.gd`'s three declarative lists, `on_world_ready()`, node groups |
| `docs/architecture/world_streaming.md` | `WorldData`/`BlockData`, `BlockBase` markers, streaming conventions, spawn |
| `docs/architecture/player_and_camera.md` | `player.gd`'s two movement modes, camera components, transport, stance and aiming, key hints |
| `docs/architecture/npc_and_incidents.md` | `ActorBase`/`NPCBase`/`DroneBase`, archetypes, reactions, the witness chain, `IncidentRegistry`, `ComicEffectSystem` |
| `docs/architecture/items_and_equipment.md` | `ItemCatalog`, `EquipmentComponent`, equipment visuals, slot data, `MorphIcon` |
| `docs/architecture/persistence.md` | The save contract, `SaveSystem`, `PlayerPersistenceSystem`, `LodgingSystem`/`LodgingRoom`, `ActorBase.actor_id` |

**When a contract changes, correct the paragraph that states it, in the same
commit as the change.** Appending a newer, contradictory paragraph below the old
one is how this file drifted four times.
→ `docs/postmortems/documentation_drift.md`

# Project Rules (Vertical Trespass)

## Hard constraints — do not suggest changing these

- **Renderer: Forward+.** No `renderer/rendering_method` override is set, so the
  Forward+ default applies. The performance target is low-end integrated
  graphics at ~55 FPS — the budget is tight and every effect is a real cost, but
  Forward+ features are not off-limits. Do not switch back without explicit
  discussion. → `docs/postmortems/renderer_forward_plus.md`
- **GDScript for all gameplay code, and for everything else.** Do not introduce
  C#.
- `lights_and_shadows/directional_shadow/size` is tuned to **1024** for the FPS
  target — don't raise it. (That is the directional shadow map, not the
  positional atlas; `shadow_atlas/size` sits at its default.) Both soft-shadow
  filter qualities are 0 for the same reason.

## Architecture rules

- **How two systems learn about each other — pick one, in this order:**
  - **`WorldContext`** — composition and runtime dependencies. Default choice.
  - **Autoload** — genuinely global state or service. Closed set: the existing
	four plus the MCP helper. Additions require explicit discussion.
  - **Signal** — event notification, one-to-many, sender does not care who
	listens.
  - **Group** — discovery and tagging, for nodes that never receive a
	`WorldContext` (static scene instances such as `DroneBase`,
	`PatrolDroneController`, `LodgingRoom`).
- **No new autoloads.** Scene-scoped systems are plain Node instances owned by
  `world.gd` through the `WORLD_SYSTEM_SCRIPTS` list, created with `.new()` and
  initialized through `on_world_ready(context: WorldContext)`.
- Prefer **explicit reference passing** over group lookups or singleton access
  by class name.
- **Firearm targets opt in through `ActorBase`.** Membership in
  `GROUP_PERCEIVED_ACTOR` supplies discovery only; `can_receive_shot()` gates
  selection, `get_shot_target_point()` supplies one landmark to selection,
  occlusion and the tracer, and `take_hit()` lets each body own its response.
  This does not imply membership in the camera's separate `lockable` group.
- `PlayerState` is the single source of truth for `Mode` and `ViewMode`. Do not
  create parallel state enums.
- **`ViewMode` is a FRAMING, and only the camera may read it.** There is one
  on-foot camera; `TPS` and `TPS_WIDE` are it at the same distance with a
  different lens shift. A new branch on `view_mode` outside
  `OnFootCameraComponent` is almost certainly a mistake — say what it is for
  before writing it.
- **Only `InputSystems.gd` reads `Input` directly, and only it WRITES
  `Input.mouse_mode`.** Exceptions: `map_source/` and `map_camera/`, intentional
  level-design tools using raw `KEY_*` input — do not refactor them. A second
  writer to `mouse_mode` pins the pointer inside the window and the camera stops
  turning at the screen edge. → `docs/postmortems/mouse_mode_two_writers.md`
- **Inside `InputSystems`: edges come from events, levels come from polls.** A
  discrete press or release is matched on the `InputEvent` (keyboard in
  `_unhandled_input()`, mouse in `_input()`); held state and axes stay as
  `Input.is_action_pressed()` / `get_vector()` in `_physics_process()`. **Do not
  add a new `Input.is_action_just_pressed()` anywhere** — polling an edge from
  the physics frame drops presses as soon as the idle and physics rates diverge.
  A query method that must stay a poll is answered from the edge latch in that
  file, never from `Input`. **That latch carries no frame arithmetic.**
  → `docs/postmortems/input_edge_latch.md`
- **A gesture's state machine may not ask "has it ended" before "has it
  started".** `AnimationTree` updates on the idle frame while `player.gd`'s
  punch/shot/reload machines run in `_physics_process`, so "not active" and "not
  started yet" are the same reading until an idle frame passes. Each machine
  latches a `*_gesture_seen` flag first and only then tests for the end, with
  `GESTURE_START_GRACE` as the backstop. A fourth gesture needs a fourth flag.
  → `docs/postmortems/gesture_start_race.md`
- **An actor's identity is authored or allocated, and is never recycled.**
  `ActorBase.actor_id` is authored per instance for anything placed in a scene —
  the player, the drones, the hand-placed crowd. A pooled ambient actor carries
  no id and no record; it is promoted **once**, when a record is about to name it
  (it commits a witness report, takes a hit, or is interacted with), and the id
  it gets comes from a monotonic counter that never reuses one. Promotion is
  one-way: the node returns to the pool, the identity does not. An allocated
  identity lives as long as some record still names it and is released by sweep
  when none does — so **anything that names one carries its own age or count
  bound**, or it pins its identities forever.
  → `docs/architecture/npc_and_incidents.md`
- **Streaming:** `_packed_cache` is non-optional (`load_threaded_get()` consumes
  the task; shared-path cells would false-fail without it). Do not change
  streaming budgets or radii (`STREAM_RADIUS`, `MAX_CONCURRENT_LOADS`,
  `INSTANTIATION_BUDGET_PER_FRAME`) without explicit discussion first.

## Naming conventions

- Files/folders `snake_case`; node/class names `PascalCase`.
- **Component** = attached to a specific owner entity (`StaminaComponent`, not
  `StaminaManager`); **Manager** = owns a collection of instances; **System** =
  single cross-cutting orchestrator.

## Language policy

- **New code and comments: English**, readable for future collaborators.
- **Existing Russian comments/strings: leave as-is** — they migrate during
  planned refactoring passes, not opportunistically. When editing a file that is
  already in Russian, do not translate untouched parts; new additions within it
  are still English.

## Workflow rules

- **`docs/NOW.md` is read first in every session and updated last.** Capped at
  80 lines.
- **Claude Code and Codex operate as peer implementation agents.** The author
  owns priorities and approvals; neither agent silently overrules the other's
  recorded work. Before overlapping a live change, read the working tree,
  `docs/NOW.md`, and the relevant `CHANGELOG.md` entries to establish a clear
  file boundary or handoff.
- **Use OODA for every non-trivial task:** **Observe** the live tree, current
  contracts, and runnable evidence; **Orient** against scope and invariants;
  **Decide** a smallest verifiable step and its acceptance criteria; **Act** by
  changing, verifying, and recording that step. New evidence restarts the loop;
  it is never rationalised away.
- **`CHANGELOG.md` entries are 3–6 lines.** Anything longer — measurements, what
  turned out false, why it was hard — belongs in `docs/postmortems/`.
- **`CLAUDE.md` carries invariants only, in the present tense.** No history, no
  measurements, no "this used to". Those go to `docs/postmortems/`, linked from
  the rule.
- **Update `CLAUDE.md` in the same commit** as the change. When an architectural
  decision, a system's contract, or the *meaning* of a tunable changes, correct
  the matching section here — not as a later cleanup pass.
- **Append to `CHANGELOG.md` in the same commit.** A dated entry: what changed in
  substance, which systems it touched, and a note if the work came from a
  parallel session. English primary, one-line Russian gloss in italics. This is
  the only mechanism by which parallel sessions stay aware of each other — an
  unrecorded change is invisible to the next one.
- Propose architectural concerns and design **before** writing code for
  significant systems.
- Ask clarifying questions when the picture is incomplete; do not brute-force or
  guess.
