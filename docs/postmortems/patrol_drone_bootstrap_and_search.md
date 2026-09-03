# PatrolDroneController: three things that took two attempts each

**Invariant this belongs to:** the header of
`world/police_drone/controllers/patrol_drone_controller.gd`.

## 1. The registry lookup could not be a one-shot `_ready()` call

`IncidentRegistry` is a `WORLD_SYSTEM_SCRIPTS` entry created by `world.gd`, not
an autoload, and this drone is a static instance placed directly in
`world.tscn`. It never receives a `WorldContext`, so it resolves the registry by
group — the same pattern `PerceptionComponent` uses to find the player.

That lookup **originally was** a single call in `_ready()`, and that was a real
bug rather than a hypothetical. Godot calls `_ready()` bottom-up as a scene
enters the tree, so every static `PoliceDrone` under `StreamContainer` (four in
`world.tscn`) gets `_ready()` — and the lookup — before `World._ready()` even
runs, let alone before `_init_world()` creates the registry (`World._ready()`
additionally awaits a process frame first). The group is provably empty at that
point.

`_try_resolve_incident_registry()` is now retried from `_decide()` until it
succeeds: cheap once resolved, and self-healing regardless of bootstrap order.

The more thorough fix would be architectural — `world.gd` creating systems
before the static tree's `_ready()` pass, or a "world ready" signal static
instances could await. Every static instance in `world.tscn` today is documented
as temporary test scaffolding ("remove once real spawning exists"), so permanent
bootstrap-ordering infrastructure is not worth building for it yet. Worth
revisiting once these become real spawned content.

## 2. One hook was assumed to cover two gaps; it covered one

An earlier version assumed the resolve-time query alone covered both a
streamed-out-and-back-in block **and** a save/load boundary. It did not: the
resolve-time query already ran once, early, typically while the registry was
still empty, and never runs again on its own. The save/load case needs
`IncidentRegistry`'s own `incidents_restored` signal. The two hooks are not
redundant, and a third — the patrol scan — was added for the reason below.

## 3. `alert_incident_radius` went to 600 m and back to 60 m

A diagnostic detour during 2026-08-13, not a design change. The actual defect it
was covering for: the drone only ever checked the registry at fixed **moments**
(resolving it, a load) and never as it moved, so one patrolling directly over a
fresh incident noticed nothing unless the radius was inflated far past its
intended scale. `_update_patrol_scan()` closed that; the radius went back.

## 4. One timer had to become two

Losing sight of the player in ALERT was first collapsed onto `alert_memory_time`
alone (2026-08-13's first pass). That produced a "search" which gave up after
three seconds — barely long enough to reach a single wander point. Three seconds
is right for "don't twitch on a blink" and wrong for "how long to actually
look", so the two meanings were separated: `alert_memory_time` is the tolerance,
`search_duration` is the search.

## Also gone

- **A raised fist used to trigger ALERT directly.** It read as the city
  responding to a pose rather than to an event. A raised stance is now OBSERVE;
  ALERT wants a fact on record.
- **Before the `WITNESS_REPORT` channel existed**, a committed witness report had
  no observable consequence anywhere in the build.
- **`StatusLight`** — one `OmniLight3D` doing an instant colour lerp, barely
  legible in the greybox — was replaced by the spotlight (addressed: who it is
  looking at) plus the two-lamp light bar (ambient: that it is looking at all).
