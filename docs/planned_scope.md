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
`NPC_REACTIONS.md`

Items promoted from this page to active work move to `scope_horizon.md`.

Last reviewed: 2026-08-07

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
| Save | **This is the gap that matters.** See its own section below. |

---

## Save

Saving is load-bearing, not started, and cannot be delegated — it touches
every system that owns mutable state. It gets more expensive with every
system added, so the decisions below are recorded now even though the
system is not being built now.

### What the design already gives us for free

Sleep is the only save point. That is a design decision, not a technical
one, and it is worth more than any implementation detail: at the moment of
sleep the world is by definition quiet. Nobody is knocked down, no drone is
in ALERT, no incident is in flight, the player is indoors and stationary.

So transient state is **not saved at all**. Not drone states, not
`is_knocked_down()`, not streaming cell states, not the incident buffer,
not camera or animation state. All of it is either derivable from the
player's position on load or genuinely gone. This is the difference between
a save system that is hard and one that is small.

### Conventions to hold to

- **Save data, not scenes.** No `PackedScene`, no `ResourceSaver` of live
  nodes. A dictionary of primitives that the world is rebuilt from. Scene
  serialisation breaks on any structural edit and drags resource references
  along with it.
- **Version the format from the first write.** A `save_version: int` at the
  root. Adding a key later without it breaks every existing save, and that
  is the one save mistake that cannot be repaired afterwards.
- **Nothing durable holds a `Node` reference.** Node identity does not
  survive a load. Anything that must outlive sleep needs a stable id.
- **Game time, not engine uptime, for anything durable.**
  `Time.get_ticks_msec()` resets on launch, which is correct for a
  responsiveness window and wrong for a fact that ages across sessions.
  `GameClockSystem` is the source of truth for the latter.
- **The crowd is disposable; consequences are not.** Ambient NPCs and drones
  stream in and out and are never saved. What they caused is.

### Proposed contract

`WORLD_SYSTEM_SCRIPTS` entries already opt into an optional lifecycle hook,
`on_world_ready(context)`. Saving should extend the same pattern with two
more optional methods rather than introduce a new mechanism:

```
func save_state() -> Dictionary
func load_state(state: Dictionary) -> void
```

Systems implement them when they have something durable to say; `world.gd`
collects and distributes. No new autoload: `IncidentRegistry` demonstrated
that a world system does not need one.

Today this contract would be implemented by two things — `GameClockSystem`
(game time and day) and the player (position and, once they exist,
physiology and wallet). That small payload is the argument for establishing
the convention now rather than later: it is cheap to adopt while there are
two participants and expensive to retrofit when there are twenty.

### Open questions

- Whether story flags (Jay missions, irreversible world events) live in
  their own durable store or as a section of the save payload. They must
  outlive world teardown either way.
- Whether the durable wanted record is `IncidentRegistry` or a separate
  object — see `NPC_REACTIONS.md` §8. The registry today is a short-lived
  sensor buffer holding node references and engine-uptime timestamps, both
  of which are correct for what it does and wrong for a fact that survives
  sleep.
- Event orchestration — sequencing story events and injecting behaviour into
  the world — is a *system*, and belongs with the other world systems. The
  flags it reads and writes are *data*, and belong in the save. These are
  two different things and should not be one class.

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

## Known defects

Not scope — things that are wrong in what exists.

- **The punch is bound in TPS view only.** `COMBAT` stance in ISOMETRIC has
  no attack. Stance is a `PlayerState` axis and must not depend on the
  camera view. `player.gd`.

---

## Not started, not stubbed

Named here so the absence is deliberate rather than overlooked:

- **NPC and AI.** A body, decision-layer seam, perception, animation and a
  reaction to a fixed fact now exist (`npc/npc_base.gd`, `npc/controllers/`,
  `core/characters/actor_base.gd` — the shared contract the police drone
  also drives through, `world/police_drone/`). `IdleNPCController` wanders
  near its spawn point and freezes/turns toward a visible player, still
  reading a raised stance for its own glance/turn gate;
  `PatrolDroneController` goes ALERT on an `IncidentRegistry` incident
  (`core/world/incident_registry/`) reported within `alert_incident_radius`
  of it — no longer on a raised stance, which read as the city watching a
  pose rather than an event — holds for a few seconds of memory, then
  reverts. What's still missing: real navigation (both controllers
  substitute a single forward raycast for obstacle avoidance, not a
  navmesh — an obstacle just means "pick another point," not "route around
  it"), any memory beyond that one ALERT timer, and reaction that spreads
  beyond one drone's own radius (one drone noticing does not alert
  another). The design documents rest heavily on how the city reacts to the
  player; this is a fuller slice of that now — a hit is legible (NPCs fall
  and get up, `take_hit()`/`is_knocked_down()` on `NPCBase`) and recorded
  (`IncidentRegistry`) — but still not the whole reaction: nothing beyond
  one drone's radius hears about it, and there's no witness system yet
  (NPCs don't report what they see, only the player's own punch does). The
  design this is built against is `NPC_REACTIONS.md`.
- **Combat.** A punch exists (`COMBAT`-only, `mouse_left_button`,
  `player.gd`) and knocks a hit NPC down for a few seconds — see NPC and AI,
  above. What doesn't: health, damage numbers, death, a weapon to swing, and
  anything for the camera's lock-on sub-state to actually lock onto besides
  the existing `lockable` NPCs (nothing currently forces a lock-on
  encounter). This is "the player can hit something," not combat. Note that
  the consequence system is currently ahead of the combat it measures:
  incidents are recorded for a punch, while nothing worse than a punch is
  possible.
- **Stance has state and reads through to animation.** `PlayerState.Stance`
  (PEACE/COMBAT, `core/player_state/player_state.gd`) exists and is read
  by movement speed and TPS body rotation (`player.gd`), lock-on gating
  (`camera/tps_combat_camera_state.gd`), and the AnimationTree
  (`player_animation_component.gd`: MeleeLib's Light* set for PEACE,
  ShooterLib's sneak-* clips for COMBAT — previously running
  unconditionally regardless of stance — plus a punch, `new4/punch1`,
  layered over whichever branch is mixed in via `AnimationNodeOneShot`).
  One loose end left there: sprint (PEACE) is still named
  (`ANIM_PEACE_SPRINT`) but not wired into the blend tree, see that file's
  comments for why — the run clip itself (COMBAT forward, outer blend
  point) is wired and was not actually a second loose end. Not done:
  weapon-in-hand as an orthogonal volume modifier on top of the stance (the
  axis is deliberately boolean — see `PlayerState.Stance`'s own comment).
  Once it lands, a drawn weapon in COMBAT is meant to put a drone into
  OBSERVE — attention on *intent*, released when the player returns to
  PEACE, distinct from the ALERT that a reported fact causes; see
  `NPC_REACTIONS.md` §4a and `patrol_drone_controller.gd`'s own header. The
  evidence system is meant to read stance too. NPC reaction to the player's
  stance is done (the glance/turn gate); drone reaction to it is not — see
  Combat and NPC/AI, above, for what replaced it.
- **Missions.**
- **Animation beyond locomotion and stances.** `PlayerAnimationComponent`
  drives idle/walk/run per stance and a procedural head look, plus one
  attack (the COMBAT punch, layered via `AnimationNodeOneShot`); NPCs now
  have a simpler idle/walk `NPCAnimationComponent`, their own
  `LookAtModifier3D` head look, and the same `AnimationNodeOneShot`
  layering for knockdown/getup (`npc_components/animation_component/`).
  Still missing: layered upper-body blending (a punch or a knockdown
  currently plays full-body, briefly overriding locomotion entirely, rather
  than blending over just the upper body) and any attack beyond the one
  punch. `player/animations/new_libs/Weapons.res` is mounted on
  `AnimationPlayer` as `new5` but is effectively empty (407 bytes) — real
  aim-down-sights animation data lives in `player/animations/libs/
  rifle_aim.res` and `rifle_aim_1.res` instead; don't assume `new5/` has
  content because it's mounted.
