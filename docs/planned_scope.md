# Planned scope — not started

Everything on this page is **not implemented**. It exists here so that it
does not exist in the file tree as an empty script or an empty directory.

An `extends Node` placeholder and an empty folder both read to a newcomer as
either committed scope or abandoned work. Neither is true. This list is the
honest version.

Nothing here is a commitment. Items are built only when an existing system
demonstrably cannot carry the weight, and only when the item serves at least
two systems that already exist.

Design specifications for things on this page, where they exist, live
beside it: the city's reaction to the player is specified in
`NPC_REACTIONS.md`.

Items promoted from this page to active work move to `scope_horizon.md`.

Last reviewed: 2026-08-24

---

## Removed from the tree on 2026-07-29

These files were `extends Node` and nothing else. Deleting them does not
delete the intent — it is recorded below.

### Transport

| Was | Intent | Prerequisite |
|---|---|---|
| `core/controllers/transport/base/lift_base.gd` | Vertical lift between levels of the island | A location where a lift is required by gameplay |
| `core/controllers/transport/base/tube_transit_base.gd` | Pneumatic tube transit; observer camera only | `TUBE_TRANSIT` mode has a destination worth travelling to |
| `core/controllers/transport/base/hover_metro_base.gd` | Levitating metro line, distinct from tubes | Hover base proven at scale first |
| `core/controllers/transport/metro_train_types/train0..3.gd` | Metro rolling stock variants | Metro base exists |
| `core/controllers/transport/hover_types/hover_bus.gd`, `hover_van.gd`, `hover_truck.gd` | Hover variants beyond the player car | A reason for a second hover type; one is enough for streaming stress-testing |
| `core/controllers/transport/ai_hover_controller.gd` | AI driver feeding the same `set_move_intent()` interface as the player controller | Traffic is needed; the interface on `HoverBase` already anticipates it |

Duplicate empty stubs of `input_hover_controller.gd` and
`ai_hover_controller.gd` also existed at
`core/controllers/transport/`. The working implementation lives at
`core/controllers/transport/base/input_hover_controller.gd`. The duplicates
were removed; they were never referenced.

### Systems

| Was | Intent | Prerequisite |
|---|---|---|
| `core/sound/sound_systems.gd` | Audio bus routing, diegetic sources, ambience per stratum | A deliberate audio design pass; this is a clean seam and a good delegation target |
| `core/world/world_environment_systems/world_environment_systems.gd` | Environment aggregation | Unclear that it is needed at all — `environment_lighting_system.gd` currently covers the ground it was created for |

### Player components

The following directories under `player/player_components/` were empty on
2026-07-29 and removed:

`attributes`, `crafting`, `health`, `hunger`, `progression`,
`save_player`, `sleep`, `wallet`.

(`equipment` was among them then; it has since been implemented as H5 and is
no longer planned scope.)

Implemented components today: `nav_component`, `stamina_component`,
`interact_component`, `inventory_component`, `equipment_component`,
`equipment_visuals_component`, `animation_component`.

| Intent | Note |
|---|---|
| Health | Needed once damage exists. Damage does not exist. |
| Hunger, sleep | Physiology. Deliberately not surfaced as permanent on-screen bars; state is shown at threshold crossings, on request, or when it blocks an action. |
| Wallet, progression | Economy is tied to identity, which is a core theme rather than a numbers system. Design not settled. |
| Save (player route) | The remaining gap. See its own section below. |

---

## Equipment — remaining open questions (H5 closed)

H5 is done (S1–S7, 2026-08-23). Layer split, slots, pockets, draw/holster,
stance symmetry, visuals and save hooks are live. What follows is only what
is still undecided or unfinished.

### Still undecided

- **The rest of the item model** — physical volume, anything beyond
  size class and observer readability. It predates this page and lives outside
  the repository.
- **Where the layout resource lives.** Direction remains: a layout `Resource`
  assigned on the player. Check existing conventions
  (`data/npc_archetypes/`, `data/comic_effects/`, `data/key_hints.tres`)
  before inventing a fourth.
- **Whether a backpack's own slots are also single sockets** or something else.
- **What the body mesh looks like** with the jumpsuit hidden.
- **The player-component route into `SaveSystem`.** `SaveSystem` still walks
  only `WORLD_SYSTEM_SCRIPTS`. Equipment already implements
  `get_save_key()` / `get_save_data()` / `load_save_data()`, but the walk
  that would call them from a player component does not exist yet. Same
  route a persisted inventory will need.

### Hard rules that remain in force

- **No belt holster. Ever.** A pistol is concealed in the jacket, and only there.
- Drawing a weapon and `Stance.COMBAT` stay one state, symmetric both ways.
- Clothing is skinned; rigid props use `BoneAttachment3D`.
- An equipment mesh must not be tagged `archetype_body_mesh`.

---

## Save

Saving is load-bearing. The contract itself exists and is proven on
`GameClockSystem`, `IncidentRegistry` and `LodgingSystem`. What is missing
is the layer that lets **player components** reach a save.

### Conventions to hold to

- **Save data, not scenes.** No `PackedScene`, no `ResourceSaver` of live
  nodes. A dictionary of primitives.
- **Version the format from the first write.**
- **Nothing durable holds a `Node` reference.**
- **Game time, not engine uptime, for anything durable.**
- **The crowd is disposable; consequences are not.**

### Open questions

- Whether story flags live in their own durable store or as a section of the
  save payload.
- Whether the durable wanted record is `IncidentRegistry` or a separate
  object (retention: current `max_incident_age` is far too short).
- Event orchestration (system) vs the flags it reads/writes (data) — keep
  them separate.

---

## Input actions defined but not implemented

Present in `project.godot`, read by nothing:

- `crouch` — bound to `C` / `Ctrl`, unread
- `weapon_reload` — bound to `R`, unread (no weapons)
- `debug_info` — bound to `Enter`, unread
- `crafting` — **no binding at all and unread**

They are documented in `input_map.md` as reserved. If still unread at the
next review, they go.

---

## Known defects

- **The punch is bound in TPS view only.** `COMBAT` stance in ISOMETRIC has
  no attack. Stance is a `PlayerState` axis and must not depend on the
  camera view. `player.gd`.

---

## Not started, not stubbed

Named here so the absence is deliberate rather than overlooked:

- **NPC and AI (remaining).** Real navigation (navmesh, not single raycast),
  memory beyond one ALERT timer, reaction that spreads beyond one drone's
  radius, full witness system. Design: `NPC_REACTIONS.md`, `core_loop.md` §7.
- **Combat.** Health, damage numbers, death, a weapon beyond the punch,
  lock-on that actually locks. Consequence system is currently ahead of the
  combat it measures.
- **Missions.**
- **Animation beyond locomotion and stances.** Layered upper-body blending;
  any attack beyond the one punch. `new5` / Weapons.res is effectively empty.
- **`RaycastService`.** Deliberately not built. Revisit when a third query
  domain appears beyond perception and camera.
- **Inter-block and vertical connections.** World data describes blocks but
  not what connects them. No level index, no elevator, no traversal link.
  Prerequisite: a mission or traversal feature that actually needs to address
  a location by level. Cheap to add while missions, navigation, NPC schedules
  and save records are still few.
