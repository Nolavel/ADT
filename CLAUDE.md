# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Godot 4.7 (Mobile renderer) project, internal codename **Prok**, working title **"Vertical Trespass"**. Almost entirely GDScript — the only C# file is `tools/scan_folder_files/project_scanner.cs` (an editor utility; `Prok.csproj` targets `net8.0`, `net9.0` for Android). Do not introduce C# for gameplay code unless asked; the codebase convention is GDScript.

Startup scene: `res://world/world.tscn`.

## Working with the running editor

This repo has the **godot-ai MCP server** wired in (`addons/godot_ai/`, enabled in `project.godot` under `[editor_plugins]`, autoloaded as `_mcp_game_helper`). When the Godot editor is open, prefer the `mcp__godot-ai__*` tools over hand-editing `.tscn`/resource files or shelling out to the Godot CLI:
- `editor_state` — check what scene is open / whether the editor is ready before issuing other calls.
- `scene_open` / `scene_get_hierarchy` / `node_*` — inspect and mutate the live scene tree (safer than hand-editing `.tscn` text for structural changes).
- `script_create` / `script_attach` / `script_patch` — create/edit/attach GDScript.
- `project_run`, `logs_read`, `test_run` — run the game and read Godot's output instead of guessing at runtime behavior.

There is no separate unit-test framework (no GUT etc.); "testing" a change means running the project (`project_run` / F5 in editor) and watching `logs_read` for the `push_error`/`push_warning`/`print` diagnostics the systems below emit liberally.

## Style conventions

- `.gd` files: **tabs**, width 4 (`.editorconfig`). `.cs`: spaces, width 4.
- LF line endings, UTF-8, final newline, trailing whitespace trimmed (not for `.md`).
- Existing scripts use a large banner comment (`# ====...====`) at the top of every non-trivial autoload/system file explaining *why* the file exists and its contracts/invariants — follow this convention when adding a new system, not when adding a small helper.
- `input_map.md` is documented as the **single source of truth for input bindings** — update it whenever an action is added/removed/rebound in Project Settings → Input Map (`project.godot` `[input]`).

## Architecture

### Autoload singletons (`project.godot` `[autoload]`)

State and cross-scene concerns live in a small set of autoloads, each with one clearly-scoped job — read the header comment in each file before touching it, they're deliberately kept separate:

- **`WorldSystems`** (`core/world/world_systems.gd`) — the single source of truth for world geometry: strata height bands (Doggerland/Manifold/Glare), the ground-tile grid, tile-coordinate math, and session state that must survive scene changes (spawn point, current strata/district/tile). Pure math only — no physics nodes.
- **`StreamingSystems`** (`core/world/streaming_systems.gd`) — the world-content streaming pipeline; the *only* owner of streamed content (`world.gd` doesn't know about individual cells). Two rings: Ring 0 = permanent-collision silhouettes for all ground tiles/blocks, spawned once; Ring 1 = actual content cells (ground tiles + blocks), state machine `UNLOADED → QUEUED → LOADING → READY → ACTIVE`, streamed in/out by XZ radius from the player, threaded-loaded with a per-frame instantiation budget. Blocks additionally materialize one "strata layer" (`InstancePlaceholder` named `Layer<StrataName>`) matching the player's current vertical strata — this naming contract (`LayerDoggerland`/`LayerManifold`/`LayerGlare`) must be respected by any new block content scene.
- **`InputSystems`** (`core/input/input_systems.gd`) — the *only* place that calls `Input.*`. Translates raw input into signals (`primary_click_pressed`, `interact_pressed`, etc.) or query methods (`is_jump_just_pressed()`, `get_move_axis()`); it has zero game logic and never decides what an input means — that's left to subscribers reacting to `PlayerState`.
- **`PlayerState`** (`core/player_state/player_state.gd`) — single source of truth for player `mode` (`ON_FOOT`, `VEHICLE_HOVER`, `TUBE_TRANSIT`, `MENU`) and `view_mode` (`TPS`, `ISOMETRIC`, `TOPDOWN`). `MENU` must only be entered/exited via `open_menu()`/`close_menu()` (these also own `get_tree().paused`) — never set `mode = MENU` directly.

### Scene bootstrap (`world/world.gd`)

`World._init_world()` is the composition root and is intentionally organized as three fixed, non-growing loops rather than one flexible abstraction, because each category has a different construction method and parent node:
1. **`WORLD_SYSTEM_SCRIPTS`** — plain `Node` classes (`GameClockSystem`, `EnvironmentLightingSystem`, `ClickToMoveSystem`, `TPSMovementSystem`, `MenuSystem`, `ZoomRulerSystem`) instantiated with `.new()`, parented to `World` itself.
2. **`WORLD_3D_ENTITY_SCENES`** — standalone 3D `.tscn` scenes instantiated and parented to `stream_container`.
3. **`WORLD_UI_SCENES`** — screen-space `Control` UI scenes, parented to a dedicated `CanvasLayer`.

Any node/scene in these lists can implement `on_world_ready(context: WorldContext)`, called once after player/camera/systems exist (`core/world/world_context.gd` exposes `context.get_system(SomeClass)`). Adding a new system/entity/UI scene = one line in the relevant array, not new bootstrap code. This mechanism is strictly about game-system/UI lifecycle — actual world content (tiles/blocks) is `StreamingSystems`' job, entirely separate.

### Player (`player/player.gd` + `player/player_components/`)

`player.gd` (on `CharacterBody3D`) owns physics, animation state machine, and rotation directly (not delegated to components) for both movement modes it supports:
- **Click-to-move / navigation** (`ISOMETRIC`/`TOPDOWN` view modes) — driven by `NavigationComponent`, path following in `_handle_navigation`.
- **Direct WASD movement** (`TPS` view mode) — `TPSMovementSystem` (a `WORLD_SYSTEM_SCRIPTS` entry) feeds `set_direct_move_input()` every physics frame; `player.gd` does the actual velocity/rotation/animation in `_apply_direct_movement`.

Which path runs is gated on `PlayerState.view_mode` inside `_physics_process`. `player_components/` is a component-per-concern layout (`attributes`, `equipment`, `health`, `hunger`, `interact`, `inventory`, `movement`, `nav`, `progression`, `save_player`, `sleep`, `stamina`, `wallet`); most subdirectories are currently **empty scaffolding** — only `nav_component`, `stamina_component`, and `interact_component` have implementations. Don't assume a component directory implies working code; check for a `.gd` file.

### Camera (`camera/`)

`camera_follow.gd` is the host; per-mode behavior lives in `camera_component/` (`on_foot_camera_component`, `vehicle_hover_camera_component`, `tube_transit_camera_component`, `camera_shake_component`). Reads input exclusively through `InputSystems` query methods, not `Input.*` directly.

### Transport (`core/controllers/transport/`)

Vehicle/transit controllers split into `base/` (shared behavior: `hover_vehicle_base`, `hover_metro_base`, `lift_base`, `tube_transit_base`) and concrete `*_types/` (hover_bus/car/truck/van, metro train0-3), plus `ai_vehicle_controller.gd` / `input_vehicle_controller.gd` for AI vs. player-driven control.

### World content data (`world/resources/`, `data/world_data.tres`)

`WorldData`/`GroundTileData`/`BlockData`/`CityZoneData` (`world/resources/*.gd`) are `Resource` subclasses defining the declarative content list `StreamingSystems` consumes at runtime (tile/block positions, content scene paths, silhouette scene paths). Editing world layout means editing `data/world_data.tres` (or the resource via the Godot inspector), not code.

## Key gameplay conventions worth knowing before touching related code

- **Height/strata convention**: ground floor = world Y 0; strata bands (`STRATA_DOGGERLAND/MANIFOLD/GLARE`) are read directly off `pos.y`, no offset.
- **Tile coordinates** are always `Vector2i(col, row)` — `.x` = column (world X axis), `.y` = row (world Z axis). Tile id format: `"gt_r%d_c%d" % [row, col]`.
- **Streaming distances are XZ-only**; blocks are full-height columns spanning `GAMEPLAY_HEIGHT`, so vertical filtering for blocks is meaningless — vertical detail is handled by the strata-layer mechanism instead.
- Global node groups (`project.godot` `[global_group]`): `Player`, `wall`, `interactables`, `floor`, `vehicle`, `world_root` (fast lookup via `get_first_node_in_group`), `district`.

# Project Rules (Vertical Trespass)

## Hard constraints — do not suggest changing these
- Renderer: **Forward Mobile** — deliberate, indefinite choice. Dev/target hardware is Intel HD 620, target ~55 FPS. Never propose switching to Forward+ or features that require it (e.g. volumetric fog).
- **GDScript for all gameplay code.** The single existing C# file (`tools/scan_folder_files/project_scanner.cs`) is an editor utility; do not introduce new C#.
- Shadow atlas is tuned to 1024 in Project Settings for the FPS target — don't raise it.

## Architecture rules
- **No new autoloads.** Scene-scoped systems are plain Node instances owned by `world.gd` via the `WORLD_SYSTEM_SCRIPTS` declarative list; they are instantiated with `.new()` and initialized through `on_world_ready(context: WorldContext)`.
- Prefer **explicit reference passing** over group lookups or singleton access by class name.
- `PlayerState` (existing autoload) is the single source of truth for `Mode` and `ViewMode`. Do not create parallel state enums.
- **Only `InputSystems.gd` reads `Input` directly.** Exceptions: `map_source/` and `map_camera/` — these are intentional level-design tools using raw `KEY_*` input; do not refactor them.
- Streaming: `_packed_cache` is non-optional (`load_threaded_get()` consumes the task; shared-path cells would false-fail without it). Do not change streaming budgets/radii (`STREAM_RADIUS`, `MAX_CONCURRENT_LOADS`, `INSTANTIATION_BUDGET_PER_FRAME`, etc.) without explicit discussion first.
- Strata layers load via `InstancePlaceholder` contract nodes named `"Layer" + strata`, `replace = false`, sharing the per-frame instantiation budget with cells.

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
