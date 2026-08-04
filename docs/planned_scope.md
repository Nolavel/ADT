# Planned scope — not started

Everything on this page is **not implemented**. It exists here so that it
does not exist in the file tree as an empty script or an empty directory.

An `extends Node` placeholder and an empty folder both read to a newcomer as
either committed scope or abandoned work. Neither is true. This list is the
honest version.

Nothing here is a commitment. Items are built only when an existing system
demonstrably cannot carry the weight, and only when the item serves at least
two systems that already exist.

Last reviewed: 2026-08-04

---

## Removed from the tree on 2026-07-29

These files were `extends Node` and nothing else. Deleting them does not
delete the intent — it is recorded below.

### Transport

| Was | Intent | Prerequisite |
|---|---|---|
| `core/controllers/transport/base/lift_base.gd` | Vertical lift between strata | A location where a lift is required by gameplay |
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

The following directories under `player/player_components/` were empty:
`attributes`, `crafting`, `equipment`, `health`, `hunger`, `progression`,
`save_player`, `sleep`, `wallet`.

Implemented components — `nav_component`, `stamina_component`,
`interact_component` — are unaffected.

| Intent | Note |
|---|---|
| Health | Needed once damage exists. Damage does not exist. |
| Hunger, sleep | Physiology. Deliberately not surfaced as permanent on-screen bars; state is shown at threshold crossings, on request, or when it blocks an action. |
| Wallet, progression | Economy is tied to identity, which is a core theme rather than a numbers system. Design not settled. |
| Equipment, crafting | Not designed. The `crafting` input action exists but is unbound and unread — see below. |
| Save | **This is the gap that matters.** Saving is a load-bearing system and the only one not started. It cannot be delegated (it touches everything) and gets more expensive with every system added. |

---

## Input actions defined but not implemented

Present in `project.godot`, read by nothing:

- `crouch` — bound to `C` / `Ctrl`, unread
- `weapon_reload` — bound to `R`, unread (no weapons)
- `debug_info` — bound to `Enter`, unread
- `crafting` — **no binding at all and unread**

They are documented in `input_map.md` as reserved. They are kept because
removing and re-adding an action churns `project.godot`; if they are still
unread at the next review, they go.

---

## Not started, not stubbed

Named here so the absence is deliberate rather than overlooked:

- **NPC and AI.** A body, decision-layer seam, perception, animation and a
  stance-triggered reaction now exist (`npc/npc_base.gd`, `npc/controllers/`,
  `core/characters/actor_base.gd` — the shared contract the police drone
  also drives through, `world/police_drone/`). `IdleNPCController` wanders
  near its spawn point and freezes/turns toward a visible player;
  `PatrolDroneController` goes ALERT on a player seen in COMBAT stance,
  holds for a few seconds of memory, then reverts. What's still missing:
  real navigation (both controllers substitute a single forward raycast for
  obstacle avoidance, not a navmesh — an obstacle just means "pick another
  point," not "route around it"), any memory beyond that one ALERT timer,
  and reaction that spreads (one NPC or drone noticing does not alert
  anything else). The design documents rest heavily on how the city reacts
  to the player; this is a first slice of that, not the reaction.
- **Combat.** The camera has a lock-on sub-state; there is nothing to lock
  onto and nothing to fight.
- **Stance has state and reads through to animation.** `PlayerState.Stance`
  (PEACE/COMBAT, `core/player_state/player_state.gd`) exists and is read
  by movement speed and TPS body rotation (`player.gd`), lock-on gating
  (`camera/tps_combat_camera_state.gd`), and the AnimationTree
  (`player_animation_component.gd`: MeleeLib's Light* set for PEACE,
  ShooterLib's sneak-* clips for COMBAT — previously running
  unconditionally regardless of stance). Two loose ends left there:
  sprint (PEACE) and a speed-blended run clip (COMBAT forward) are both
  named but not wired into the blend tree, see that file's comments for
  why. Not done: weapon-in-hand as an orthogonal volume modifier on top
  of the stance (the axis is deliberately boolean — see
  `PlayerState.Stance`'s own comment); and the evidence system that's
  meant to read it too. NPC/drone reaction to the player's stance is
  done — see NPC and AI, above.
- **Missions.**
- **Animation beyond locomotion and stances.** `PlayerAnimationComponent`
  drives idle/walk/run per stance and a procedural head look; NPCs now have
  a simpler idle/walk `NPCAnimationComponent` and their own
  `LookAtModifier3D` head look (`npc_components/animation_component/`).
  Still missing: layered upper-body blending, hit reactions, and attack
  animations wired for the player. `player/animations/new_libs/Weapons.res`
  is mounted on `AnimationPlayer` as `new5` but is effectively empty (407
  bytes) — real aim-down-sights animation data lives in
  `player/animations/libs/rifle_aim.res` and `rifle_aim_1.res` instead;
  don't assume `new5/` has content because it's mounted.
