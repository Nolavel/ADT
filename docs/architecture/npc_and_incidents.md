# NPCs, perception and incidents

Actors and their controllers, archetypes, the witness chain, what the city has on
record, and the comic reaction layer.

Split out of `CLAUDE.md` on 2026-08-25 — it had grown to 94 KB with single
paragraphs over 4000 characters, which is a document nobody edits: agents append
to the end instead of correcting the middle, and that is where the repeated drift
came from. The text here is the same text, moved, not rewritten.

`CLAUDE.md` remains authoritative for the rules; this file is authoritative for
the contracts it describes.

---

- **NPCs and AI actors** (`npc/`, `world/police_drone/`, `core/characters/actor_base.gd`): `ActorBase` (`CharacterBody3D`) is the physical-body contract `NPCControllerBase` and `PerceptionComponent` type-check against — `set_move_intent()`/`set_look_target()`/`get_eye_height()`/`get_facing_direction()`, every method a stub meant to be overridden. It also owns the actor's orthogonal physical nature: `Nature.HUMAN` (the default), `SYNTHETIC` or `ROBOT`. `nature` is authored per concrete scene instance, never on `NPCArchetypeData`, because role and nature vary independently; `can_read_iris()` is true only for mechanical natures, while `has_votive()` is true only for humans. All four placed Clerks are `HUMAN`; `Patrolman3`/`Patrolman4` are `ROBOT`; the base `PoliceDrone.tscn` is also `ROBOT`, so all drone instances inherit that nature. `NPCBase` (a walking capsule) and `DroneBase` (a hovering, ground-following flyer, `world/police_drone/drone_base.gd`) both extend it, so `NPCControllerBase` (despite the name — kept for the controllers already built on it) and `PerceptionComponent` drive/watch either without knowing which. `PatrolDroneController` extends `NPCControllerBase` the same way `IdleNPCController` does; both read `PlayerObservation.stance` (see above) to decide when to react. `PerceptionComponent` itself is unchanged either way — only its exported `vision_range`/`vision_angle_deg` differ per scene instance (wider on the drone). NPCs carry a full copy of the player's mesh/skeleton/`AnimationPlayer` rig (`npc.tscn`'s `player_base_mesh`, copied from `player.tscn` — see that scene's own node structure; **not** an instanced shared scene, `player.tscn` bakes its mesh/skeleton as inline sub-resources, so reuse meant a literal copy, textures dropped for a grey-dummy look) driven by `NPCAnimationComponent` (`npc_components/animation_component/`) — a single, signed `AnimationNodeBlendSpace1D` (`ANIM_BACKWARD` at `-1.0`, idle at `0.0`, `ANIM_WALK` at `walk_blend_radius`, `ANIM_RUN` at `1.0`; `_target_blend_position()` signs the axis by whether `NPCBase.velocity` points with or against `get_facing_direction()`, so the two-phase flee reaction's BACKING_AWAY/RUNNING phases — `idle_npc_controller.gd` — read as genuinely different clips, not just different speeds) plus a `LookAtModifier3D` head look, the same technique `player_animation_component.gd` uses, replacing `NPCBase`'s old hand-rotated `Head` node. `set_look_target()`/`clear_look_target()` on `NPCBase` are unchanged as the public contract other systems call; only the turning implementation moved.
- **`NPCArchetypeData`** (`npc/npc_archetype_data.gd`, a `Resource`) is `docs/npc_archetypes.md` as data — one `.tres` per archetype (`data/npc_archetypes/`: `vagrant`/`thug`/`commuter`/`clerk`/`patrolman`), assigned to `NPCBase.archetype` and applied once by `NPCBase._apply_archetype()` in `_ready()`. Three readability channels (§3), applied as three independent steps on purpose — colour, gait, attention — so replacing the placeholder-colour step with a real mesh/material variant later touches only that step: `placeholder_color` becomes a flat `material_override` only across `MeshInstance3D`s explicitly tagged `archetype_body_mesh` in `npc.tscn` (§4 sanctions this explicitly as prototype scaffolding, not the design). This makes component-owned geometry safe by default: a future Votive or equipment mesh that is not tagged retains its own material; a future body part must be tagged deliberately, otherwise it visibly retains its native material. `walk_speed_multiplier` scales `NPCBase.walk_speed` (speed only — posture/animation-set variation is delegated, unbuilt), and `vision_range`/`vision_angle_deg` are written onto the sibling `PerceptionComponent`'s own exports — configuration, not a change to `PerceptionComponent.gd`. The fourth channel, density & mix, is not a field on the resource — it's expressed by scene data, how many of each archetype a block places (§5). Witness (§2) still has no visual-identity field: that remains a flag meant to land on an instance of one of these five later (H4, `docs/scope_horizon.md`). It also now carries `NPC_REACTIONS.md` §4's crowd-reaction bias — `flee_probability` (a bias, not a rule: the crowd reacts by chance), `responds_by_approaching` (Patrolman-only, since §1 puts it outside the two-axis grid; walks toward an incident instead of rolling Flee/Freeze at all), and `is_witness_caller` (`docs/attribution.md` §7, deterministic — not a bias: `Clerk` is the only archetype with this set `true`, everyone else never calls in what it witnesses, however clearly it saw the incident — replacing the population-wide `witness_density`/`call_probability` pair that used to live on `IdleNPCController`).
- **`IdleNPCController`'s incident reaction** (`npc/controllers/idle_npc_controller.gd`, `NPC_REACTIONS.md` §4) subscribes to `IncidentRegistry.incident_reported` with the exact lazy-resolve scheme `PatrolDroneController` uses (a static scene instance can exist before `IncidentRegistry` does) — deliberately without that controller's catch-up-on-resolve query, since a stale incident making an NPC flinch now would read as a bug, not memory. Within `earshot_radius` of a live report, an ordinary archetype rolls `archetype.flee_probability` to Flee or Freeze-and-stare (probabilistic, per the design's own "reacts by chance" rule — never a fixed per-archetype outcome); a `responds_by_approaching` archetype (Patrolman) instead walks to the incident, its own behaviour, not a third crowd roll. A `ReactionState` other than `NONE` pre-empts the ordinary wander/observe-player behaviour entirely for its duration — the incident is the stronger stimulus.
  - **Walking Patrolmen form authored reciprocal pairs.** `NPCBase.patrol_partner_id` names the other actor through the existing `GROUP_PERCEIVED_ACTOR`; `IdleNPCController` resolves it lazily and accepts it only when both links agree, both archetypes are Patrolman, and the natures are exactly `HUMAN + ROBOT`. The human owns the wander/response destination, the robot tracks a 1.5 m lateral slot, and the leader waits above a 4.0 m split until the gap closes to 2.5 m. Player-notice stops and incident response are shared as formation state, but each controller evaluates the incident before synchronization and retains its own observation/memory result. A missing or knocked-down partner restores the unchanged solo path; there is no re-pairing or teleport. Police drones are separate BRPD units.
  - **A missed swing is the one stimulus that does not travel through `IncidentRegistry`.** `_try_connect_player_swing()` subscribes to `player.gd`'s `punch_missed` by the same lazy group lookup this controller uses for the registry, and `_on_player_punch_missed()` is the single entry point. A punch that hit nothing is a visible act, not a fact the city holds: it creates no `Incident`, no `WitnessReport`, and — unlike witnessing an actual incident — does **not** set `_remembers_player`; nobody was assaulted. It is gated on nothing but this NPC's ordinary `PerceptionComponent.observe_player()` (range + cone + line of sight), so an NPC facing away or behind a wall reacts to nothing, and it yields exactly one of two outcomes: a roll of `archetype.flee_probability * swing_flee_probability_scale` (`0.5`, an `IdleNPCController` export — the bias itself stays on the archetype, this only says how much less a whiff is worth than the real thing) into the SAME two-phase Flee state machine, or one `npc_swing_noticed` word. Never both, and never a new reaction branch: `_start_flee()` already spawns `npc_flee`, and stacking `"?"` on top of `"RUN"` over one head in one frame is the double-word mistake `npc_transmit`'s placement exists to avoid. A knocked-down body or a live `ReactionState` wins outright — a whiff is the weakest stimulus in the file and must never interrupt a transmission, a flee or a knockdown.
  - **Incident telemetry** is an event trace, not a frame-by-frame log or an extension of `perception_debug_panel.gd`: `incident_telemetry_enabled` defaults on while the witness vertical slice is being judged. Each live incident produces one `[WitnessTelemetry]` block that records every hearing-range candidate's distance, cone angle and rejection/Call outcome, followed by a transmission count; Call start, cancellation and commit print their own event lines. Range/cone evaluation returns one typed `IncidentVision` result consumed by both the log and the Call gate, so telemetry cannot silently use a second, divergent decision calculation. A candidate that isn't a witness, isn't seen, or rolled against Call and lost still falls through to the ordinary Flee/Freeze roll — `_log_incident_outcome()` prints that roll's actual result (`FLEE`/`FROZEN`) as its own line right after the REJECT/SEES line, since that earlier line is written before the roll happens and can't be appended to after the fact; every candidate that reaches the roll always resolves to one of the two, so there is no silent "no reaction" case left unexplained in the log.
  - **`VotiveProjector`** (`core/components/votive_projector/votive_projector.gd`, `docs/attribution.md` §6) is the Votive's visible half — state (`IDLE`/`TRANSMITTING`/`DARK`) plus a visual representation of it, nothing else: no `communication_state`, no `current_call`, no identity binding, and deliberately not named `VotiveProjectorComponent` (the design names it `VotiveProjector`, kept as named rather than forced onto the `*Component` suffix convention). A shared node type, same as `HealthComponent` — one instance each in `npc.tscn`/`player.tscn`, parented under a `BoneAttachment3D` bound to `OriginalSkeleton`'s `"Head"` bone (bone index `5` in both rigs) rather than offset from the body root. Ownership is configured exactly once: `NPCBase` passes `ActorBase.has_votive()`, while the player explicitly passes `true`; an unavailable synthetic/robot projector creates no `QuadMesh` or material and all transitions stay no-op. Human visuals use a small self-lit `QuadMesh` (`projection_size`, `@export`), unshaded with `cull_mode` `DISABLED`; visibility does not depend on glow. Driven every physics frame by its owner's own `_physics_process()`; it never runs its own `_process()`. `update_projection()` is a no-op outside `TRANSMITTING`, and `IDLE`/`DARK` are applied once when entered. The human-only terminal remains separate from `EquipmentComponent`: it is not removable in this iteration.
  - **`NPCBase` carries two overhead labels.** `ActorInfoLabel` is permanent and shows `NATURE · ARCHETYPE` plus health and the active knockdown phase; it refreshes only on health/phase events. This is an explicit stress-build exception to the no-overlay readability goal, not a replacement for silhouette, clothing and gait. The separate optional `DebugActionLabel` (`debug_show_action`) remains stacked above it and shows `WALK`/`IDLE`/`LOOK`/`FLEE`/`CALL`/`DOWN` plus an optional reason, sourced through the duck-typed `get_debug_action_text() -> String` contract so `NPCBase` does not name a controller class.
  - **Witness Call is no longer instant** (`docs/attribution.md` §7), and eligibility is the conjunction of the deterministic `NPCArchetypeData.is_witness_caller` trait and `ActorBase.has_votive()`. A caller must still pass `_evaluate_incident_vision()`; only then does `_build_witness_report()` resolve the 3 / 6 / 11 m distance ceiling capped by `can_read_iris()`. The current Clerk callers are human, so their nearest result is `FACE`; mechanical actors may resolve `IRIS` but cannot Call because they do not own a Votive. The report sits `PENDING` for `call_report_duration`, drives the projector, and only commits through `_call_it_in()` after that window. Knockdown or an approaching player cancels it; `WitnessReport` remains transient and Attribution remains unbuilt.
  - **The two-phase Flee reaction** (`FleePhase.BACKING_AWAY`/`RUNNING`, `NPC_REACTIONS.md` §4 extension) is time-gated on the way in and distance-gated on the way out. `BACKING_AWAY` runs for a FIXED `backpedal_duration` (2s default) regardless of the player's distance or whether it keeps approaching — the only early exits are losing track of the player node or backing into geometry; an earlier version also broke early on a distance threshold or the player no longer approaching, both removed. `RUNNING`'s own direction (`_flee_direction`) is computed exactly once, by `_set_flee_direction_from_threat()`, the moment `_enter_flee_phase()` actually turns into `RUNNING` — away from `_flee_threat_position` (the incident's own position, or wherever the player was when a memory-triggered flee started, see below), never toward the player and never recomputed per frame the way `BACKING_AWAY`'s own tracking is. `RUNNING` ends once `flee_far_distance` (80m default, raised from 40m on 2026-08-22 — at 40m a fleeing NPC was still comfortably on screen when it stopped, which read as the panic wearing off rather than as escape) is covered from that fixed point; `flee_duration` is now a per-phase safety cap on `RUNNING` alone (geometry can trap an NPC short of that distance), not the whole reaction's timer the way it used to be.
  - **Witness memory** (`NPC_REACTIONS.md` §4 extension) is a permanent, per-NPC flag (`IdleNPCController._remembers_player`), unrelated to whether that NPC ever becomes a caller: set the moment ANY archetype's `vision.is_seen` comes back true in `_on_incident_reported()`, and — as of 2026-08-22 — also the moment `_decide()` sees `is_knocked_down()`, which is how the VICTIM comes to remember. That second site is not redundant: `_on_incident_reported()` opens with a knocked-down guard that returns before `_remembers_player` is ever reached, and the victim is on the ground in the same frame its own assault is reported, so every bystander used to remember the player while the one NPC with the best reason to run got up and stared at him. Set on the knockdown edge rather than inside the incident handler because it needs no cone maths and no incident at all, and it covers a punch from a player the NPC never saw coming — "увидел — запомнил," any witness, not only one that calls it in — and never cleared. From then on, `_decide()`'s ordinary observe-player branch skips the freeze/turn behaviour entirely and calls `_start_flee(observation.position, false)` — `allow_backpedal=false`, straight to `RUNNING` — the instant the player is seen again, with no incident involved at all. The flag lives on this controller, a child of the NPC, so it disappears with the NPC on block unload — deliberately not durable in `IncidentRegistry`, which is what the city has on record, not what one passer-by personally remembers.
- **Firearm hits are an opt-in `ActorBase` contract.** `GROUP_PERCEIVED_ACTOR` remains discovery rather than lock-on: `can_receive_shot()` defaults false, `get_shot_target_point()` gives selection/occlusion/the tracer one world-space landmark, and `take_hit()` leaves the response to the body. `NPCBase` opts in at its shoulder and preserves the existing health-plus-knockdown path, including damage while down and terminal `KnockdownPhase.DOWN`; punches and the `lockable` group remain NPC-only. `DroneBase` opts in at its centred origin while alive and carries the same `HealthComponent` at 100 HP with conditions disabled. Its `died` edge enters one terminal destroyed state: flight intent and altitude hold stop, upward velocity is cut, horizontal inertia brakes while gravity pulls the kinematic body down, and floor contact leaves the colliding wreck still. `DroneBase.destroyed` lets `PatrolDroneController` immediately disable its decision tick and hard-switch the spotlight and both light-bar lamps off; living drones ignore wrecks in separation. The wreck stays in the perceived-actor group for identity/debug discovery but `can_receive_shot()` becomes false, so it cannot intercept another shot. `shot_landed` still reports the hit as the existing `ASSAULT`; no drone-specific incident kind exists.
- **`IncidentRegistry`** (`core/world/incident_registry/`, a `WORLD_SYSTEM_SCRIPTS` entry) is what the city has on record — **actors report; they do not remember.** This is the architectural decision that lets a reaction survive its own block being unloaded: ambient NPCs are streamed in and out with `StreamingSystems`, so nothing durable may live on one — the fact has to live in a registry that outlives any single actor, not on the actor itself. `report(perpetrator_id, kind, position, source)`, `has_recent_incident_by(perpetrator_id, within_hours)` and `get_incidents_near(point, radius, max_age)` are its consumer-facing calls. **`Incident.Source` (`DIRECT`/`WITNESS_REPORT`) is the load-bearing distinction added 2026-08-22**: it says HOW the city learned of a fact, which is a different question from what happened or who did it, and it splits every consumer into two channels. `DIRECT` (the trailing default, so `player.gd`'s punch call site is unchanged) is the act itself entering the record and is answered by a unit's OWN perception radius — `PatrolDroneController.alert_incident_radius` (60m), `IdleNPCController.earshot_radius` (25m), both untouched. `WITNESS_REPORT` is a Votive transmission that committed, i.e. the city was TOLD, and reaches everyone regardless of distance: every drone is dispatched and flies to the named point, and a `responds_by_approaching` archetype bypasses `earshot_radius` entirely and runs there. An ordinary bystander never gets that bypass, so Flee/Freeze/Call stay hearing-bound. Dispatch fires only on the LIVE `incident_reported` signal — every catch-up query (`_check_existing_incidents()`'s three call sites, `incidents_restored`) stays radius-bound, since a day-old report restored from a save must not scramble the whole city on load. The save format gained `"source"` WITHOUT a `SaveVersion` bump: `load_save_data()` reads it with a `DIRECT` default, which is the correct reading of a file written before the field existed, and `SaveSystem` refuses an unrecognised version outright with no migration path — bumping would discard working saves over a field that degrades cleanly. `perpetrator_id` is a stable `StringName` (see `ActorBase.actor_id`/`get_actor_id()` below), not a `Node3D` — a node reference is meaningless after a reload or once the reporting actor's block has streamed out. Timestamps are `GameClockSystem.total_game_hours` (game hours), not real seconds — this reversed as part of H1 (`docs/scope_horizon.md`): a durable record has to be timestamped in the one clock that itself survives a save/load boundary, since `Time.get_ticks_msec()` resets on launch. `max_incident_age`/`within_hours`/`max_age` are consequently GAME hours now, not real seconds. `max_incident_age` (default `24.0`, one in-game day) is deliberately NOT the same value as `PatrolDroneController.alert_memory_time` (real seconds, a drone's own live-session reaction memory) — the two briefly shared a rough magnitude by accident of history, which caused a real bug (see `CHANGELOG.md`, 2026-08-12): a fact saved shortly before `max_incident_age` was still `0.25` got correctly pruned back out the moment it reloaded, because the elapsed game time between the punch and the save already exceeded that window — the file was never wrong, the threshold was. The player's punch (`player.gd`'s `punch_landed` signal, `COMBAT`-only, `mouse_left_button`) is the only producer today, resolving `_player.get_actor_id()` at the call site before calling `report()`, wired through `IncidentRegistry.on_world_ready()` rather than `player.gd` knowing the registry exists — the same `WorldContext` pattern `ClickToMoveSystem` already uses to learn about the player. `patrol_drone_controller.gd`'s ALERT is the only consumer today, on **four** paths, each closing a different gap the others can't — do not read any two of them as redundant (`patrol_drone_controller.gd`'s own header spells out which covers what):
  1. **Live** — `incident_reported(incident)`, connected once when a drone resolves the registry; goes ALERT when the incident falls within `alert_incident_radius` (`60.0` — see the "diagnostic detour" note below), not on a raised stance anymore (a stance is still a reason for `idle_npc_controller.gd` to look closer, just not to summon a drone).
  2. **Resolve-time catch-up** — one `get_incidents_near(point, radius, max_age)` call in `_check_existing_incidents()`, run once, the moment a drone first resolves the registry (`_try_resolve_incident_registry()`). Covers a drone appearing in a world where the registry already holds relevant facts — today that's effectively inert (drones aren't real streamed content yet, and resolution happens early in a session while the registry is reliably still empty), but is correct for when that stops being true.
  3. **Load-time catch-up** — `IncidentRegistry.incidents_restored()`, a payload-free signal emitted at the end of `load_save_data()`, after `_incidents` is fully rebuilt and pruned, deliberately NOT a replay of `incident_reported` per restored entry (a restored fact isn't "just happened", and a consumer that cares about the difference couldn't recover it from a replay). `PatrolDroneController._on_incidents_restored()` re-runs the same `_check_existing_incidents()` query. Resolve-time catch-up (path 2) runs once, early, and — per its own `if _incident_registry: return` guard — never again, so a load happening later, on a player keypress, is invisible to it. An earlier build assumed path 2 alone covered a save/load boundary; it did not (see `CHANGELOG.md`, 2026-08-1X, for the diagnosed DoD failure this caused).
  4. **Periodic scan while `PATROL`** — `_update_patrol_scan()`, every `patrol_scan_interval` (`1.0` real seconds), re-runs the same `_check_existing_incidents()` query against the drone's CURRENT position. Paths 2/3 both fire once, at a moment in time, and say nothing about a drone that moves afterward — without this, a drone could fly directly over a fresh incident and never notice, which is what actually forced `alert_incident_radius` to `600.0` briefly during diagnosis (2026-08-13) before this path existed; it is back to its intended `60.0` now that a moving drone re-checks its surroundings instead of relying on radius alone. See `CHANGELOG.md`, 2026-08-13, for that diagnosis.

  **Dispatch is a fifth path and is not one of these four.** A `Source.WITNESS_REPORT` incident arriving on path 1 skips the radius check entirely (`dispatch_on_witness_report`, default `true`), overwrites `_tracked_player_position` with the incident position even if the drone has its own newer sighting, and sets `_dispatch_target` — which `_decide_dispatch()` then actually FLIES to at `alert_speed`, ahead of `alert_memory_time`'s tolerance in `_decide_alert()`. That ordering matters: the tolerance exists so a drone doesn't lurch into searching over one dropped perception frame, and it has nothing to say about a drone that was told to be somewhere and hasn't arrived. Before this, an ALERT drone with no visible player called `_decide_hold_and_watch()`, which issues `set_move_intent(Vector3.ZERO, 0.0)` — it hovered in place, and a dispatched drone never travelled at all. On arrival (`PATROL_ARRIVAL_RADIUS`) the dispatch clears and the ordinary tolerance/search behaviour resumes, anchored on the incident. Seeing the player en route wins over the trip but does not cancel it. Paths 2–4 all funnel through `_check_existing_incidents()`, which no-ops while the drone is already `ALERT` — a catch-up finding what's already known isn't a new provocation. Path 1 (`_on_incident_reported()`) has no equivalent guard: a genuinely new live report while already `ALERT` is a real, fresh provocation and should extend the hold.
- **`PatrolDroneController.ALERT` without a visible player is a SEARCH, not a frozen hover — on TWO separate timers, not one.** `_decide_alert()` runs the existing hold-and-watch behaviour while `observation.is_seen`; once not seen, `alert_memory_time` (`3.0`s) is a TOLERANCE, not the search's own duration — a brief loss of sight (one dropped frame, a moment behind a corner) holds position via `_decide_hold_and_watch()`'s own not-seen freeze, same as before search existed, rather than immediately lurching into search. Only past that tolerance does `_decide_search()` actually take over — a `_decide_patrol()`-style wander (goal point, arrive, pick a new one, `PATROL_ARRIVAL_RADIUS` reused as the arrival threshold) around `search_radius` (`20.0`m) of `_tracked_player_position` at `search_speed` (`6.0` m/s, closer to `patrol_speed` than `alert_speed` — looking around, not chasing), timed by its own `search_duration` (`30.0`s, chosen from `search_radius`/`search_speed`: crossing a random pair of points in a 20m-radius disk averages ~3s per leg at 6 m/s, so 30s covers on the order of ten distinct points). `_tracked_player_position` is the drone's real last-known sighting if it has ever actually seen the player, or (`_has_tracked_player_position` false) seeded from the triggering incident's own position by `_trigger_alert(incident_position)` — the only estimate available before a sighting. Being seen again, in either the tolerance or the search phase, resets both `_alert_memory_timer` and `_search_timer` to `0.0` and resumes ordinary hold-and-watch. `search_duration` expiring without a sighting exits ALERT via the pre-existing `OBSERVE`-if-seen-and-`COMBAT`-else-`PATROL` rule. Conflating tolerance and search duration into `alert_memory_time` alone (2026-08-13's first pass at re-enabling this decay) meant a search that gave up after three seconds — the split exists specifically because that read as a shrug, not a search.

  All three paths funnel through one `_trigger_alert()`. Paths 2/3 additionally no-op while the drone is already `ALERT` — a catch-up finding what the drone already knows isn't a new provocation, and resetting `_alert_memory_timer` on every redundant catch-up would matter the moment ALERT's currently-disabled decay is re-enabled; path 1 has no such guard, since a genuinely new live report while already `ALERT` should extend the hold. Since the drone is a static scene instance and never receives a `WorldContext`, it resolves the registry via `get_tree().get_first_node_in_group(IncidentRegistry.GROUP_INCIDENT_REGISTRY)` instead — the same lookup pattern `PerceptionComponent` already uses to find the player. Designed as a first slice of the roadmap's `WitnessSystem`: `Kind` has exactly one value (`ASSAULT`) because nothing produces a second one yet. Implements the save contract below (`get_save_key()` → `"incident_registry"`), proving it on a hard payload.
- **`ComicEffectSystem`** (`core/ui/comic_effect/`, a `WORLD_SYSTEM_SCRIPTS` entry) is floating reaction text — a screen-space word ("THUD", "RUN", "CALL") unprojected from a world point every frame, so it orbits on screen as the camera turns rather than being pinned to a viewport position. **Pure visual, and not audio**: a future audio pass may share the same event ids, but `ComicEffectDef` must not grow a sound field. Four files: `ComicEffectDef` (a `Resource` — the random `texts` pool, `radius`, a `visual_profile` and an `emphasis`), `ComicVisualProfile` (a `Resource` — how a whole CLASS of events is drawn: colours, type, border style/thickness/jitter, padding, grid step, and the pop/hold/fade timings), `ComicEffectLabel` (a pooled `Control` that draws its own panel in `_draw()` — background, print grid, inked border, text outline, text, in that order — positioned by `Camera3D.unproject_position()`, dying early when its source goes behind the camera or the followed node is freed), and `ComicEffectSystem` itself. Three rules inside the label are load-bearing and easy to undo by accident: the **outline is drawn before the text** (reversing them hides the glyphs inside their own outline, which at small outline sizes merely looks muddy), the **corner jitter is sampled once at `setup()`** (sampling it inside `_draw()` makes a hanging panel change shape whenever anything forces a redraw), and the **print grid is one tiled `draw_texture_rect`** off a static per-step `ImageTexture` cache, not a loop of `draw_rect` — eight live panels at a 5 px grid would otherwise be thousands of draw calls a frame. `ComicEffectDef.get_font_size()` is the single place the drawn size is decided (`profile.font_size * emphasis`); the label must not recompute it. **A def with no profile still renders**: `resolve_profile()` synthesises one from the legacy `color`/`font_size`/`duration`/`rise_px` fields and caches it, so migration is per-def and optional and no event silently stops drawing halfway through one. Three things are load-bearing and should not be "simplified" away: the **distance gate** (`ComicEffectDef.radius`, measured from the player — an event further than that never spawns a word at all, so a brawl fifty metres off doesn't litter the screen), the **fixed pool** (`POOL_SIZE` 12 / `MAX_ACTIVE` 8 — labels are reused, never freed mid-session, keeping the cost flat under the ~55 FPS target), and **anti-repeat** (`_last_text_by_id`, scoped per def id, so one id doesn't show the same string twice running). Consumers resolve it through `GROUP_COMIC_EFFECT_SYSTEM` and cache the reference, exactly as `PatrolDroneController`/`IdleNPCController` resolve `IncidentRegistry` — there is **no static facade**, that pattern exists for no other `WORLD_SYSTEM_SCRIPTS` entry. Its own `CanvasLayer` (index `45`) is built in `on_world_ready()` and parented to `get_tree().root`, the same deferred pattern `world.gd` uses for `UI_CANVAS_LAYER_INDEX` (`40`), so the words sit above the HUD. The vocabulary is **data, not code**: one `.tres` per event under `data/comic_effects/` (`npc_knockdown`/`npc_hit`/`npc_death`/`npc_freeze`/`npc_flee`/`npc_call`/`npc_transmit`/`npc_swing_noticed`), gathered by a `ComicEffectCatalog`, plus four shared looks under `data/comic_effects/profiles/` (`npc`, `player`, `player_hurt`, `environment` — the last has no consumer yet and is left without one rather than having an event invented for it) — same shape as `data/key_hints.tres`, same one-file-per-item convention as `data/npc_archetypes/`. The catalog is found by PATH (`CATALOG_PATH`), deliberately: this system is `.new()`-built from `WORLD_SYSTEM_SCRIPTS` and has no inspector, so the `@export` route `KeyHintsPanel` uses to reach `KeyHintsCatalog` is unavailable, and a `DirAccess` folder scan is a trap — an exported build converts `.tres` to binary behind `.remap`, so the scan would find every def in the editor and none in a shipped build. A missing catalog or an empty `texts` pool warns and makes that id unspawnable; neither is fatal. `register_def()` remains the runtime seam for adding a def without editing the catalog. Wired at eight sites, split by ownership on purpose — the body spawns what the body knows (`NPCBase.take_hit()`, on its two mutually exclusive branches: `npc_knockdown` on the hit that starts a knockdown, `npc_hit` on a hit landing on a body already down, the early `return` between them guaranteeing one hit never produces both; `_enter_down_phase()` → `npc_death`) and the decision layer spawns what it knows (`IdleNPCController._start_flee()`/`_start_freeze()`/`_start_calling()`, plus `npc_transmit` in `_commit_witness_report()` and `npc_swing_noticed` in `_on_player_punch_missed()`), neither routing through the other. The player is a consumer too, through five defs of his own (`player_hurt`/`player_death`/`player_winded`/`player_spent`/`player_combat`) wired in `player.gd` — every one on an EDGE, never a per-frame state read: a health DECREASE seen through `health_changed` (`_last_health_seen`, since `HealthComponent` has no `damaged` signal and gaining one for a decoration would be the wrong dependency direction), `sprint_allowed_changed(false)`, `stamina_depleted()`, `died()`, and `stance_changed` entering `COMBAT` only. `player_combat` used to borrow `StanceIndicator.combat_color`'s hue so the word and the HUD badge read as the same statement; since the panel work it sits in the shared `player` register instead, and that tie is now carried by the stance badge alone. That is a deliberate trade — thirteen per-event hues were a legend the player would have to memorise (`docs/visual_language.md` §7) — and it is the one thing in this change that gave something up. `npc_transmit` deliberately marks the moment the report actually reaches `IncidentRegistry`, NOT the start of transmission: `_start_calling()` decides to call and calls `_votive.start_transmitting()` in the same frame, so a `npc_transmit` placed there would put two words over one head in one frame, next to `npc_call`'s own. Commit time is the one genuinely separate event in this chain — and it is an event, not the "transmission is under way" state, which would break the word-on-event rule.


---

## Actor identity — authored, allocated, never recycled

**Chosen 2026-09-03 (Stan), work plan Task 5: the hybrid, with the growth rule
attached.** The two rejected models and why are in
`docs/postmortems/actor_identity.md`. `CLAUDE.md` carries the one-paragraph
invariant; this is the contract in full.

### The three categories

- **EPHEMERAL** — the ambient crowd. Carries no `actor_id`, has no record and no
  memory. Nothing may file anything against an ephemeral actor; there is nothing
  to file against.
- **PERSISTENT, authored** — anything placed in a scene with its id written in
  the file: the player (`player.gd`'s `ACTOR_ID`), the four drones, the eighteen
  hand-placed NPCs in `world.tscn`. Unchanged by any of this.
- **PERSISTENT, allocated** — an actor that was ephemeral and got promoted.

Authored and allocated identities are the same thing to every consumer. The only
difference is where the id came from, and no consumer may branch on it.

### Promotion

An ephemeral actor is promoted **once**, at the moment one of these happens to
it:

1. it commits a witness report (`WitnessReport.Status.COMMITTED`),
2. it takes a hit,
3. the player interacts with it.

Promotion allocates an id and nothing else. It is not a decision about what the
actor is, and it carries no gameplay meaning of its own — an actor is promoted
because a record is about to name it, so promotion and the first record are one
event.

**Promotion is one-way.** The node returns to the pool; the identity does not.
There is no demotion, and an actor is never promoted twice.

### Allocation

Allocated ids come from a **monotonic counter and are never reused**. A released
identity's id is retired with it. This is the rule that makes a stale reference
safe: a record naming a released identity resolves to nobody, which is correct,
and can never silently resolve to a *different* person, which would be a bug no
test would catch.

### Growth — the bound, and why it is not a number of its own

An allocated identity **lives exactly as long as some record still names it**,
and is released once none does. It is not capped by count and not aged out on
its own clock.

That is deliberate. A promoted identity exists *because* a record was about to
name it, so an identity nothing names any more has nothing left to be. The size
of the persistent population therefore falls out of the bounds already on the
records themselves — `IncidentRegistry` prunes at `max_incidents = 32` and
`max_incident_age = 24.0` game hours — rather than being a second, independent
number free to disagree with them.

The obligation this puts on every future record type is the load-bearing half:
**anything that names an allocated identity carries its own age or count bound.**
A record with no bound pins its identities forever, and the population becomes
unbounded through the back door. Task 6b's memory is the first such record and
inherits this requirement.

Release is a **sweep, not reference counting**: periodically, an allocated
identity that no live record names is retired. A sweep cannot leak on a missed
decrement, and it needs no coordination between the systems that hold records —
which matters because those systems (`IncidentRegistry`, 6b's memory, later H7)
are deliberately unaware of each other.

### What this touches in code, when it is built

One line, and it is the only one: `ActorBase._ready()` currently warns when
`actor_id` is empty. Ephemeral is now a legitimate state, so that warning needs
either a condition or an explicit sentinel to distinguish "ephemeral on purpose"
from "someone forgot to author an id". Everything else in this section is a
system that does not exist yet.

### What this does not decide

Model 2 — a roster of stable residents on `BlockData` — is **compatible with
this and not rejected forever**. It is a third *source* of persistent identity
alongside authoring and allocation, and it buys recognisable residents that
promotion-on-involvement never will. Nothing here forbids adding it later.

This contract says nothing about Attribution. `WitnessReport.witness_id` is the
witness's own identity, not the suspect's, so it does not touch
`docs/incident_knowledge_model.md` §2's invariant 2 ("REPORT never contains a
resolved actor identity") — do not "fix" it in the name of that rule.


---

## Personal memory — what one actor remembers, and for how long

**Proposed 2026-09-03 for work plan Task 6b.** The registry described here is
not built yet; the behaviour it will feed already is.

### It is not new behaviour. It is behaviour with nowhere to live.

`IdleNPCController._remembers_player` already exists. It is set when the NPC
sees an incident, and again when the NPC is knocked down, is never cleared, and
already changes what the NPC does: seeing the player again sends it straight to
`_start_flee(position, false)` — recognition, so no backpedal, straight to
RUNNING. That file's own header states what it lacks: it "**dies with the
NPC**".

Task 6b gives that flag a clock, a durable home and a place in the save. The
decision path in `_decide()` does not change; only where its answer comes from.

### The record

One row: **holder `holder_id` saw subject `subject_id` at this time, having got
this good a look.**

- `holder_id` — the remembering actor's own `actor_id`.
- `subject_id` — who was seen. The player today.
- `observation_level` — from the existing `_resolve_observation_level()`.
- `timestamp` — `GameClockSystem.total_game_hours`. **Game hours, never engine
  uptime**, for the reason `IncidentRegistry` already carries: only that clock
  survives a save, and `Time.get_ticks_msec()` resets on launch.

Nothing else. Not where, not what happened — `IncidentRegistry` holds that, and
duplicating the city's record inside a passer-by's head buys nothing.

### How long — and this is also the bound Task 5 demands

A memory's lifetime is a function of how well the holder saw. This is one
mechanism satisfying two separate requirements: the identity contract's rule
that **anything naming an allocated identity carries its own age or count
bound**, and `incident_knowledge_model.md` §8's narrowed permission for a
witness to read its own observation quality.

| Seen as | Remembered for, game hours |
|---|---|
| `SILHOUETTE` | 12 |
| `EQUIPMENT` | 36 |
| `FACE` | 108 |
| `IRIS` | 324 |

**A clean x3, and the shape is the point.** The first pass was 6 / 24 / 72 / 168,
which reads as a rising progression and is not one: its ratios are x4, x3, x2.3,
so it DECELERATES and each better look bought proportionally less than the one
before. Retuned 2026-09-04 (Stan: exponential, floor 12 rather than 6). Values
tune by playing; what does not move is that a worse look must decay faster, or
`observation_level` is not doing anything and the channel is decorative. A hard
count cap sits behind them, mirroring `IncidentRegistry.max_incidents`.

The `SILHOUETTE` row was unreachable on the witness path until the same day: the
quality ceilings were retuned to 3 / 6 / 11 so every rung fits inside the 16 m
witness envelope. See `docs/attribution.md` §7.

**Being hit is its own case.** A knockdown files a memory at `FACE` strength
whatever the cone said. The reasoning is already in the controller: the victim
is on the ground in the same frame its own assault reaches the registry, so the
ordinary sighting path never reaches it — and being punched is first-hand
knowledge that needs no line of sight.

### Where it lives

`ActorMemoryRegistry` (`npc/memory/`), an entry in `WORLD_SYSTEM_SCRIPTS`
alongside `IncidentRegistry`, resolved by group — the same lazy lookup
`IdleNPCController._try_resolve_incident_registry()` already uses, and for the
same reason: a static scene instance never receives a `WorldContext`. It carries
`get_save_key()`/`get_save_data()` like every other system, so `SaveSystem`
picks it up without knowing it exists.

Named "Registry" and not "System" after `IncidentRegistry`: it is a store of
records, not an orchestrator.

### The line between this and IncidentRegistry

`IncidentRegistry` is **what the city has on record**. This is **what one actor
personally remembers**. They are different records with different lifetimes and
different consumers, and neither is derived from the other. `_remembers_player`'s
own comment already draws that line; this keeps it drawn.

### What this deliberately does not do

- **No propagation between actors.** A query is always about the caller's own
  `holder_id`. One actor remembering is the whole slice — an actor learning what
  another remembers is a later, separate decision.
- **No promotion machinery.** All 36 hand-placed NPCs carry authored ids, so
  this works on the existing diorama with no pooling. Promotion arrives with
  Task 7, and the identity contract permits the gap because authored and
  allocated identities are indistinguishable to a consumer.
- **No Attribution.** `subject_id` is resolved at the call site from the player
  node, the way `_call_it_in()` already does. Nothing is inferred from reports.

---

## Recognition — proposed, not built

**Proposed 2026-09-04 (Stan). No code yet.** Flight on memory should fire only
when the NPC actually *recognises* the player as they are now, because the
player may have changed since.

This is the gameplay surface `docs/incident_knowledge_model.md` §2 invariant 5
already names — *"change appearance, discard distinctive equipment"* — and §8's
narrowed wording permits it: a witness reading its own observation quality to
change its own behaviour and its own private memory. **The city resolves
nothing here.** No `suspect_id`, no matching of reports against each other.

### The signature

Two observable traits exist today and both come from `EquipmentComponent`:
what is **worn** (`get_equipped()` across `layout.body_slots`) and what is
**in hand** (`get_drawn()`). `ActorMemory` gains a snapshot of both, taken at
the moment of witnessing.

The player exposes it as one method, resolved the duck-typed way
`get_actor_id()` already is — the controller finds the player by group and asks.
`IdleNPCController` does not reach into another actor's components.

### What breaks recognition, by how well the holder saw

Monotone on purpose: the better the look, the fewer things can break it.

| Remembered as | Recognised when | The player's out |
|---|---|---|
| `IRIS`, `FACE` | always | none — a face is a face |
| `EQUIPMENT` | the drawn item still matches | holster or drop the weapon |
| `SILHOUETTE` | the drawn item **and** the garments match | change either |

It reads off the distance bands directly: up close they saw *you*; at 6-11 m
they read the gun; at 11-16 m all they had was an outline, so any change to it
loses you.

**This closes the caveat left in Task 6a.** `observation_level` currently
changes how LONG a reaction lasts. With this it also changes WHICH reaction
fires — recognised, and the NPC flees; not recognised, and it treats you as a
stranger.

### Honest about what is playable today

**Only one of the two levers exists.** The player owns exactly two garments
(`starter_jumpsuit`, `starter_boots`), there is no second garment to change
into and no UI to change with, so the garment half of the signature is inert.
The weapon half is real now: holstering the carbine defeats an `EQUIPMENT`
memory, and that is testable the day it is built.

The garment half is written the same way regardless and becomes live the moment
a second garment ships, with no code change. Building only the weapon half
would mean revisiting the record format later, which is the more expensive
mistake.

### What it does not change

The identity contract is untouched: a memory still names an identity, so it
still carries its own age bound, and `LIFETIME_HOURS` still governs. Recognition
decides whether a *live* memory applies to the person standing there, not how
long the memory lives.
