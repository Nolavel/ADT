# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Chronology of changes lives in `CHANGELOG.md` — read it when you need to know *when*
something changed, or what work is currently in flight in a parallel session. For
*how the project works right now*, this file is authoritative; do not reconstruct
current state by replaying the log.

## Project

Godot 4.7 (Forward+ renderer) project. Repository `ADT`; internal build name **"Vertical Trespass"** (`config/name`); public title **"Another Digital Thriller"** — use the public title only in store-facing material, never in code or docs. Almost entirely GDScript — the only C# file is `tools/scan_folder_files/project_scanner.cs` (an editor utility). Do not introduce C# for gameplay code unless asked; the codebase convention is GDScript. Dropping C# entirely is an open backlog item.

## Documents

| File | Purpose |
|---|---|
| `docs/CONTRIBUTING.md` | What a collaborator may pick up, what is off-limits, contribution terms |
| `docs/GDSCRIPT_STYLE.md` | Code conventions; stricter than the official Godot guide in places |
| `docs/planned_scope.md` | Scope that is **not started**. Not a task list. |
| `docs/CREDITS.md` | Third-party attributions, incl. the Godot MIT notice |
| `INPUT_MAP.md` | Single source of truth for input bindings |
| `LICENSE.md` | Proprietary; all rights reserved |
+
 ## Working with the running editor

Startup scene: `res://world/world.tscn`.

## Working with the running editor

This repo has the **godot-ai MCP server** wired in (`addons/godot_ai/`, enabled in `project.godot` under `[editor_plugins]`, autoloaded as `_mcp_game_helper`). When the Godot editor is open, prefer the `mcp__godot-ai__*` tools over hand-editing `.tscn`/resource files or shelling out to the Godot CLI:
- `editor_state` — check what scene is open / whether the editor is ready before issuing other calls.
- `scene_open` / `scene_get_hierarchy` / `node_*` — inspect and mutate the live scene tree (safer than hand-editing `.tscn` text for structural changes).
- `script_create` / `script_attach` / `script_patch` — create/edit/attach GDScript.
- `project_run`, `logs_read`, `test_run` — run the game and read Godot's output instead of guessing at runtime behavior.

There is no separate unit-test framework (no GUT etc.); "testing" a change means running the project (`project_run` / F5 in editor) and watching `logs_read` for the `push_error`/`push_warning`/`print` diagnostics the systems below emit liberally.

## Style conventions

- `INPUT_MAP.md` is the **single source of truth for input bindings** (verified against `project.godot` 2026-07-29, 29 actions) — update it whenever an action is added/removed/rebound in Project Settings → Input Map (`project.godot` `[input]`).
- Full conventions live in `docs/GDSCRIPT_STYLE.md`; collaborator-facing rules in `docs/CONTRIBUTING.md`. Read the style guide before writing GDScript.
- **New comments are written in English.** Existing comments are largely Russian and are being translated header by header; do not add more Russian.
- **Standing instruction when editing an existing script:** before changing it, check it against `docs/GDSCRIPT_STYLE.md` — static typing, declaration order, naming, banner header on systems, `TODO(scope):` form. If the file deviates, say so and offer the correction as a separate step. Do not silently reformat, and do not bundle a style pass into a behaviour change.
- **Do not create placeholder scripts or empty directories** for work that has not started. Planned scope belongs in `docs/planned_scope.md`. An empty file in the tree reads as a promise.
 
## Architecture

### Autoload singletons (`project.godot` `[autoload]`)

State and cross-scene concerns live in a small set of autoloads, each with one clearly-scoped job — read the header comment in each file before touching it, they're deliberately kept separate:

- **`WorldSystems`** (`core/world/world_systems.gd`) — the single source of truth for world geometry: strata height bands (Doggerland/Manifold/Glare), the ground-tile grid, tile-coordinate math, and session state that must survive scene changes (spawn point, current strata/district/tile). Pure math only — no physics nodes.
- **`StreamingSystems`** (`core/world/streaming_systems.gd`) — the world-content streaming pipeline; the *only* owner of streamed content (`world.gd` doesn't know about individual cells). Two rings: Ring 0 = permanent-collision silhouettes for all ground tiles/blocks, spawned once; Ring 1 = actual content cells (ground tiles + blocks), state machine `UNLOADED → QUEUED → LOADING → READY → ACTIVE`, streamed in/out by XZ radius from the player, threaded-loaded with a per-frame instantiation budget. Blocks additionally materialize one "strata layer" (`InstancePlaceholder` named `Layer<StrataName>`) matching the player's current vertical strata — this naming contract (`LayerDoggerland`/`LayerManifold`/`LayerGlare`) must be respected by any new block content scene.
- **`InputSystems`** (`core/input/input_systems.gd`) — the *only* place that calls `Input.*`. Translates raw input into signals (`primary_click_pressed`, `interact_pressed`, etc.) or query methods (`is_jump_just_pressed()`, `get_move_axis()`); it has zero game logic and never decides what an input means — that's left to subscribers reacting to `PlayerState`.
- **`PlayerState`** (`core/player_state/player_state.gd`) — single source of truth for player `mode` (`ON_FOOT`, `HOVER`, `TUBE_TRANSIT`, `MENU`) and `view_mode` (`TPS`, `ISOMETRIC`). `TOPDOWN` was removed entirely (not just deferred) — do not reintroduce it. `MENU` must only be entered/exited via `open_menu()`/`close_menu()` (these also own `get_tree().paused`) — never set `mode = MENU` directly.

### Scene bootstrap (`world/world.gd`)

`World._init_world()` is the composition root and is intentionally organized as three fixed, non-growing loops rather than one flexible abstraction, because each category has a different construction method and parent node:
1. **`WORLD_SYSTEM_SCRIPTS`** — plain `Node` classes (`GameClockSystem`, `EnvironmentLightingSystem`, `ClickToMoveSystem`, `TPSMovementSystem`, `MenuSystem`, `ZoomRulerSystem`, `IncidentRegistry`) instantiated with `.new()`, parented to `World` itself.
2. **`WORLD_3D_ENTITY_SCENES`** — standalone 3D `.tscn` scenes instantiated and parented to `stream_container`.
3. **`WORLD_UI_SCENES`** — screen-space `Control` UI scenes, parented to a dedicated `CanvasLayer`.

Any node/scene in these lists can implement `on_world_ready(context: WorldContext)`, called once after player/camera/systems exist (`core/world/world_context.gd` exposes `context.get_system(SomeClass)`). Adding a new system/entity/UI scene = one line in the relevant array, not new bootstrap code. This mechanism is strictly about game-system/UI lifecycle — actual world content (tiles/blocks) is `StreamingSystems`' job, entirely separate.

### Player (`player/player.gd` + `player/player_components/`)

`player.gd` (on `CharacterBody3D`) owns physics, animation state machine, and rotation directly (not delegated to components) for both movement modes it supports:
- **Click-to-move / navigation** (`ISOMETRIC` view mode) — driven by `NavigationComponent`, path following in `_handle_navigation`. Currently a straight-line stub: `nav_component.tscn` leaves `navigation_region_path` unset, so `_initialize_navigation()` finds no `NavigationRegion3D` and forces `use_navigation` to `false` at runtime — `set_target_position()` then just emits a single-point path straight to the destination. No obstacle avoidance and no path validation yet.
- **Direct WASD movement** (`TPS` view mode) — `TPSMovementSystem` (a `WORLD_SYSTEM_SCRIPTS` entry) feeds `set_direct_move_input()` every physics frame; `player.gd` does the actual velocity/rotation/animation in `_apply_direct_movement`.

Which path runs is gated on `PlayerState.view_mode` inside `_physics_process`. `player_components/` contains three implemented components: `nav_component`, `stamina_component`, `interact_component`. Empty placeholder directories for unstarted components (health, hunger, sleep, wallet, progression, equipment, crafting, save) were removed on 2026-07-29; that scope is recorded in `docs/planned_scope.md`.

### Camera (`camera/`)

`camera_follow.gd` is the host; per-mode behavior lives in `camera_component/`: `on_foot_camera_component` (ISOMETRIC orbital + TPS, with three sub-state helpers — `TpsShoulderCameraState` for left/right shoulder offset, `TpsCombatCameraState` for Explore↔Locked lock-on, and `IsometricCameraState` for the ISOMETRIC follow point: dead zone, lead toward the click-to-move destination, a separate vertical channel, asymmetric damping; `IsometricCameraDebugOverlay` visualizes it when attached), `hover_camera_component` (renamed from `vehicle_hover_camera_component`; `HoverView` = CHASE/COCKPIT), `tube_transit_camera_component` (stub, freelook only), `camera_shake_component` (additive-only, pure getter — cannot leave a residual offset by construction). `camera_follow.gd` also owns an internal `CameraState{GAME, MENU_PAUSE}` for the menu tween, separate from `PlayerState.Mode`. Reads input exclusively through `InputSystems` query methods, not `Input.*` directly.

### Transport (`core/controllers/transport/`)

+`base/hover_base.gd` is the shared hover behaviour (CharacterBody3D pseudo-physics, inertia, yaw smoothing, semi-automatic altitude hold). Control is fed in every frame through `set_move_intent(move, vertical)` — `base/input_hover_controller.gd` (`InputHoverController`) is the player-side implementation and reads exclusively through `InputSystems`. An AI-side controller will use the same interface. Boarding is handled by `hover_entry_trigger.gd` (FSM: `IDLE → BOARDING → SEATED → EXITING`), not by `InteractComponent`.

- Metro, lifts, tube transit and additional hover types are **not implemented** — see `docs/planned_scope.md`. Their placeholder scripts were removed on 2026-07-29.

### World content data (`world/resources/`, `data/world_data.tres`)

`WorldData`/`GroundTileData`/`BlockData`/`CityZoneData` (`world/resources/*.gd`) are `Resource` subclasses defining the declarative content list `StreamingSystems` consumes at runtime (tile/block positions, content scene paths, silhouette scene paths). Editing world layout means editing `data/world_data.tres` (or the resource via the Godot inspector), not code.

### Block markers (`core/map_source/blockbase.gd`, `map_source.tscn`)

`BlockBase` (`class_name BlockBase`, extends `Node3D`) is the shared carrier for every tower/block marker placed in `map_source.tscn`: common fields (`id`, `block_name`, `district`, `scene_path`, `silhouette_scene_path`, `block_height`) plus shared logic (`_find_mesh`, `_compute_height`, a `_ready()` that is final by convention). Per-strata or per-purpose specialization is done by **subclassing** `BlockBase` (e.g. `BlockHaze` for residential towers, adding `floor_count`/`has_rooftop_garden`) and overriding the virtual hooks (`_on_marker_ready`, `get_marker_data`, `_log_extra_info`) — never by editing the base class per-use-case.

Markers are generated by `tools/block_generator/block_placer.gd` (an `EditorScript`, run manually via File → Run in the editor, not autoloaded — there is nothing to "turn off"). It clears and regenerates only nodes whose **name** starts with the `GBX_` prefix; nodes without that prefix are left untouched. **To make a generated marker authorial/hand-owned, rename it to remove the `GBX_` prefix** — otherwise the next `block_placer.gd` run will delete and regenerate it regardless of any manual edits made to its fields.

## Key gameplay conventions worth knowing before touching related code

- **Height/strata convention**: ground floor = world Y 0; strata bands (`STRATA_DOGGERLAND/MANIFOLD/GLARE`) are read directly off `pos.y`, no offset.
- **Character physical size** is per-character data (`player/player.gd`'s `body_height` export; `npc/npc_base.gd`'s own) with shared eye/shoulder/chest ratios in `core/characters/body_metrics.gd` (`BodyMetrics`), not duplicated per character. The `Player` `CharacterBody3D` origin sits at the feet. Any value that depends on the character's height (camera framing, raycast origins, attachment points) must go through the `get_eye_height()`/`get_shoulder_height()`/`get_chest_height()` getters — never hardcode a height or assume where origin sits.
- **Tile coordinates** are always `Vector2i(col, row)` — `.x` = column (world X axis), `.y` = row (world Z axis). Tile id format: `"gt_r%d_c%d" % [row, col]`.
- **Streaming distances are XZ-only**; blocks are full-height columns spanning `GAMEPLAY_HEIGHT`, so vertical filtering for blocks is meaningless — vertical detail is handled by the strata-layer mechanism instead.
- **Ground tiles have per-tile content/silhouette scenes**, same pattern as blocks: `GroundTileData.content_scene_path`/`silhouette_scene_path` are set individually, one pair per `(row, col)` — `map_source.gd` generates the paths (`gt_content_r{row}_c{col}.tscn` / `gt_silhouette_r{row}_c{col}.tscn`), not a shared scene. There is no `WorldData`-level shared silhouette anymore.
- **Player spawn** is a single `Vector3` (`WorldSystems.spawn_point`), placed via one marker in `map_source.tscn`. Its Y is currently hard-clamped to `Y_CITY_ZONE_TOP` at commit time (`_commit_spawn_point`) regardless of raycast hit height — this is why it's ground-tile-only today; placing on other strata requires removing that clamp.
- **Player stance** (`PlayerState.stance`, `Stance.PEACE`/`Stance.COMBAT`) is a declared intent, not equipment — raised fists are already a statement, a weapon only changes its volume. Mutated only through `PlayerState.set_stance()`, never assigned directly, same rule as `mode`/`view_mode`. Read by `player.gd` (movement speed, TPS body rotation, and — only in `COMBAT` — the punch action on `mouse_left_button`, see `_on_primary_click_pressed()`), `camera/tps_combat_camera_state.gd` (lock-on gating), `player_animation_component.gd` (a stance-branched AnimationTree — two direction-blended `AnimationNodeBlendSpace2D` branches with identical geometry: a centre/idle point plus seven directional points, forward split into a walk point (`walk_blend_radius`) and a run point (outer edge) since the blend vector's length carries speed; every point is the same clip on both branches except idle, MeleeLib's `LightIdle` for PEACE vs ShooterLib's `sneak-idle` for COMBAT — plus a punch, layered over whichever branch is mixed in via `AnimationNodeOneShot`, ShooterLib's `punch1`), and — as of the drone/NPC work below — the AI decision layer: `idle_npc_controller.gd`'s glance/turn gate still reads `PlayerObservation.stance` (itself sourced from `PlayerState.stance` by `PerceptionComponent`, only when the player is actually seen), but `patrol_drone_controller.gd`'s ALERT no longer does — see the `IncidentRegistry` paragraph below for what replaced it. The evidence system still doesn't read stance. Not reset by `open_menu()`/`close_menu()`.
  - **`PlayerState.is_aiming`** is a COMBAT-only modifier, not a third stance (`set_aiming()` silently clamps to `false` outside `Stance.COMBAT`/`Mode.ON_FOOT` — a held aim button crossing a stance change mid-press is ordinary input, not an error). Read by `player.gd` (`aim_speed_multiplier`, stacked on top of the COMBAT speed multiplier), `on_foot_camera_component.gd` (dollies TPS camera distance to `TPS_AIM_DISTANCE`, widens shoulder offset by `aim_shoulder_offset_multiplier` — wins even over an active lock-on), and `ui/hud/aim_reticle/` (a debug-grade screen-centre cross, visible only while aiming — confirms ADS reads on screen, not the final aiming UI).
- **NPCs and AI actors** (`npc/`, `world/police_drone/`, `core/characters/actor_base.gd`): `ActorBase` (`CharacterBody3D`) is the physical-body contract `NPCControllerBase` and `PerceptionComponent` type-check against — `set_move_intent()`/`set_look_target()`/`get_eye_height()`/`get_facing_direction()`, every method a stub meant to be overridden. `NPCBase` (a walking capsule) and `DroneBase` (a hovering, ground-following flyer, `world/police_drone/drone_base.gd`) both extend it, so `NPCControllerBase` (despite the name — kept for the controllers already built on it) and `PerceptionComponent` drive/watch either without knowing which. `PatrolDroneController` extends `NPCControllerBase` the same way `IdleNPCController` does; both read `PlayerObservation.stance` (see above) to decide when to react. `PerceptionComponent` itself is unchanged either way — only its exported `vision_range`/`vision_angle_deg` differ per scene instance (wider on the drone). NPCs carry a full copy of the player's mesh/skeleton/`AnimationPlayer` rig (`npc.tscn`'s `player_base_mesh`, copied from `player.tscn` — see that scene's own node structure; **not** an instanced shared scene, `player.tscn` bakes its mesh/skeleton as inline sub-resources, so reuse meant a literal copy, textures dropped for a grey-dummy look) driven by `NPCAnimationComponent` (`npc_components/animation_component/`) — a single `AnimationNodeBlendSpace1D` (idle to walk, no run tier) plus a `LookAtModifier3D` head look, the same technique `player_animation_component.gd` uses, replacing `NPCBase`'s old hand-rotated `Head` node. `set_look_target()`/`clear_look_target()` on `NPCBase` are unchanged as the public contract other systems call; only the turning implementation moved.
- **`take_hit()`** is a contract on `NPCBase` (`npc/npc_base.gd`), not `ActorBase` — deliberately narrower than `set_move_intent()`/`set_look_target()`. A hit knocks the body down (`is_knocked_down()`, `new4/knockdown` then `new4/ko-getup`, layered over locomotion the same `AnimationNodeOneShot` way `player_animation_component.gd` layers the punch); the controller (`idle_npc_controller.gd`'s `_decide()`) stops deciding while it's true, and the body itself refuses movement intent regardless of what's called into it. `DroneBase` has no equivalent — no animation component to play a fall/getup clip on, and a flying body being knocked from the sky is a separate, unbuilt feature — so a punch that reaches a drone simply doesn't connect (`player.gd`'s hit detection filters its target group to `NPCBase`).
- **`IncidentRegistry`** (`core/world/incident_registry/`, a `WORLD_SYSTEM_SCRIPTS` entry) is what the city has on record — **actors report; they do not remember.** This is the architectural decision that lets a reaction survive its own block being unloaded: ambient NPCs are streamed in and out with `StreamingSystems`, so nothing durable may live on one — the fact has to live in a registry that outlives any single actor, not on the actor itself. `report(perpetrator, kind, position)` and `has_recent_incident_by(perpetrator, within_seconds)` are its two consumer-facing calls; timestamps are real seconds (`Time.get_ticks_msec()`), not `GameClockSystem`'s game-hours — that clock runs at a compressed, eventually variable (`time_scale`) ratio to real time, which doesn't compose safely with a real-second recency window. The player's punch (`player.gd`'s `punch_landed` signal, `COMBAT`-only, `mouse_left_button`) is the only producer today, wired through `IncidentRegistry.on_world_ready()` rather than `player.gd` knowing the registry exists — the same `WorldContext` pattern `ClickToMoveSystem` already uses to learn about the player. `patrol_drone_controller.gd`'s ALERT is the only consumer today: it subscribes to `incident_reported` and goes ALERT when the incident falls within `alert_incident_radius`, not on a raised stance anymore (a stance is still a reason for `idle_npc_controller.gd` to look closer, just not to summon a drone). Since the drone is a static scene instance and never receives a `WorldContext`, it resolves the registry via `get_tree().get_first_node_in_group(IncidentRegistry.GROUP_INCIDENT_REGISTRY)` instead — the same lookup pattern `PerceptionComponent` already uses to find the player. Designed as a first slice of the roadmap's `WitnessSystem`: `Kind` has exactly one value (`ASSAULT`) because nothing produces a second one yet, and `perpetrator` is a plain `Node3D`, not narrowed to the player, so a future witness NPC reports through the same call.
- Global node groups actually in use: `player` (lowercase — added in code, `player.gd`'s `_ready()`), `wall`, `interactables`, `floor`, `vehicle`, `world_root` (fast lookup via `get_first_node_in_group`), `district`, `lockable` (combat camera lock-on pool, `NPCBase` only — see `tps_combat_camera_state.gd`), `perceived_actor` (`ActorBase`'s own group, both NPCs and drones — debug-tooling enumeration only, deliberately not `lockable`: a drone is not a lock-on target), `incident_registry` (`IncidentRegistry`'s own group — the lookup path for consumers that can't reach it through `WorldContext`, see above). `project.godot`'s `[global_group]` section still registers a capitalized `Player` name too, but no node carries it — the group tag on the `Player` node itself was removed as dead weight; the leftover registration wasn't touched.

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
- - **Update `CLAUDE.md` in the same commit.** When an architectural decision, a system's contract, or the *meaning* of a tunable changes, update the matching section here as part of that change — not as a later cleanup pass. This file is the compiled knowledge layer for the repo: agents and future collaborators read it instead of re-deriving state from source. It has already drifted twice (the renderer constraint contradicted itself for ten days; several `WORLD_SYSTEM_SCRIPTS` entries existed in `world.gd` but not here), and each drift cost real debugging time.
- **Append to `CHANGELOG.md` in the same commit.** Every meaningful change gets a dated entry: what changed in substance, which systems/files it touched, and — if the work came from a parallel session — a note saying so. Add to the existing day's entry if one exists, otherwise open a new one at the top. Keep entries to a few lines; English primary, with a one-line Russian gloss in italics matching the existing style. This is the only mechanism by which parallel work sessions stay aware of each other — an unrecorded change is invisible to the next session.
