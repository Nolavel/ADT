# =============================================================================
# patrol_drone_controller.gd — PatrolDroneController: flies a random local
# patrol pattern and watches for a reason to stop.
#
# Extends NPCControllerBase (npc/controllers/npc_controller_base.gd) rather
# than a second drone-specific controller base — it already resolves its
# ActorBase parent and calls _decide(delta) every physics frame, which is
# all a drone controller needs too; see that file's own header for why it
# is no longer NPC-only. Perception is the exact same PerceptionComponent
# every NPC uses (npc/npc_components/perception_component/) — only its
# exported vision_range/vision_angle_deg differ per-instance in the scene,
# not a second component.
#
# States are PATROL, OBSERVE and ALERT, not PATROL/CHASE. The old
# police_drone.gd's local-square patrol pattern (a random point inside a
# square centred on the drone's start position, rotated to its start yaw) is
# unchanged, ported onto DroneBase/PerceptionComponent.
#
# Two rungs of reaction, not one switch: a raised stance
# (PlayerObservation.stance == COMBAT, player actually seen) is a reason to
# look closer — OBSERVE holds distance and follows with its gaze, lights
# off, the same declared-intent read idle_npc_controller.gd's own glance/
# turn gate uses. A fist in the air on an empty street is not, on its own,
# a reason to summon a patrol — that used to be ALERT's own trigger, and it
# read as the city watching a pose rather than an event. ALERT is reserved
# for a fixed fact on record: it triggers on IncidentRegistry.
# incident_reported (core/world/incident_registry/) — the same registry
# player.gd's punch reports to — and always wins over OBSERVE regardless of
# what the live stance/visibility read says that frame.
#
# HOW that fact arrives splits into TWO CHANNELS, and they are not the same
# provocation (Incident.Source):
#
#   DIRECT          — the act itself entered the record. Gated on
#                     alert_incident_radius: this drone noticed something
#                     happen near it. Local, and unchanged.
#   WITNESS_REPORT  — a Votive transmission committed, i.e. the CITY was
#                     told. Not gated on distance at all: every drone is
#                     dispatched and flies to the named place from wherever
#                     it is (dispatch_on_witness_report, _decide_dispatch()).
#
# That split is what makes a witness worth having. A punch nobody calls in
# stays a local matter that one nearby drone might notice; a punch a witness
# transmits brings the city. Before it existed, a committed report had no
# observable consequence anywhere in the build.
#
# A dispatched drone actually TRAVELS — _decide_dispatch() runs ahead of
# alert_memory_time's tolerance in _decide_alert(), because that tolerance
# is about not twitching over a dropped perception frame and has nothing to
# say about a drone that was told to be somewhere and has not arrived. On
# arrival the dispatch clears and the ordinary tolerance/search behaviour
# takes over, anchored on the incident.
#
# incident_reported alone only covers facts reported WHILE this drone is
# already listening — it says nothing about facts already on record from
# before this drone existed in the world, or from before its own most
# recent state replacement. That gap is real, not theoretical, and it is
# TWO gaps, not one, closed by two different hooks — see
# _check_existing_incidents()'s own comment for exactly which case each
# covers, and do not read the two as redundant:
#
#   - a streamed-out-and-back-in block, closed by a one-shot query the
#     moment this drone resolves the registry
#     (_try_resolve_incident_registry() -> _check_existing_incidents());
#
#   - a save/load boundary, closed by IncidentRegistry's own
#     incidents_restored signal (_on_incidents_restored() ->
#     _check_existing_incidents()) — NOT by the resolve-time query above,
#     which already ran once, early, typically while the registry was
#     still empty, and will never run again on its own (see
#     _try_resolve_incident_registry()'s early return). An earlier version
#     of this file assumed the resolve-time query alone covered both cases;
#     it did not — see CHANGELOG.md, 2026-08-1X, for the diagnosis.
#
# IncidentRegistry surviving both a reload and a streaming cycle is the
# whole point of H1 (docs/scope_horizon.md) — a fact durable enough to
# outlive either is wasted if the one consumer that should act on it can
# only ever hear about it live. Neither hook polls — a one-time sync per
# event, same distinction has_recent_incident_by() vs. a hypothetical
# polling API would draw.
#
# Both rungs share alert_memory_time as a tolerance against a single dropped
# frame, not an instant un-trigger: ALERT doesn't un-trigger the instant the
# incident ages past the registry's own window, and OBSERVE doesn't
# un-trigger the instant the player lowers their stance or looks away — a
# drone that forgets mid-blink reads as glitching, not calming down. Past
# that shared tolerance the two diverge: OBSERVE un-triggers directly
# (falls back to PATROL, nothing left to search for — a raised stance was
# never a fact on record); ALERT instead enters its own search phase, timed
# separately by search_duration, and only THAT expiring — not
# alert_memory_time — falls back to OBSERVE-if-seen-and-COMBAT-else-PATROL,
# the same live read OBSERVE's own entry uses, not a separate "was I
# provoked recently" flag. See search_duration's own comment for why one
# shared shape stopped being enough once ALERT's un-triggering also had to
# cover a whole search, not a single moment.
#
# IncidentRegistry is a WORLD_SYSTEM_SCRIPTS entry (world.gd), not an
# autoload, and this drone is a static test instance placed directly in
# world.tscn — it never receives a WorldContext the way TPSMovementSystem
# does (on_world_ready()). Resolved instead via get_tree().get_first_node_
# in_group(), the exact pattern PerceptionComponent already uses to find the
# player from anywhere in the tree, not a new lookup convention.
#
# That lookup CANNOT be a one-shot call in _ready(), and originally was one
# — a real bug, not a hypothetical: Godot calls _ready() bottom-up as a
# scene enters the tree, so every static PoliceDrone under StreamContainer
# (four of them in world.tscn today) gets _ready() — and this lookup —
# called before World's own _ready() even runs, let alone before
# _init_world() creates IncidentRegistry (World._ready() additionally
# awaits a process frame first). The group is provably empty at that point.
# _try_resolve_incident_registry() is called again every _decide() until it
# succeeds — cheap once resolved (an early-out), and self-healing regardless
# of bootstrap order. A single push_warning fires if incident_registry_
# search_timeout passes with nothing found, once per instance, not every
# frame — silence here would mean a drone that never reacts to anything,
# with nothing in the log to explain why.
#
# The more thorough fix would be architectural — world.gd creating systems
# before the static scene tree's own _ready() pass, or a "world ready"
# signal static instances could await — but every static instance in
# world.tscn today (npc.tscn's own too) is explicitly documented as
# temporary test scaffolding ("remove once real spawning exists"), so
# building permanent bootstrap-ordering infrastructure for it isn't worth it
# yet. Worth revisiting once these become real spawned content.
#
# Planned: a drawn weapon in COMBAT is itself a statement of intent — a
# blade or a firearm in hand should draw the drone's attention on its own,
# without an incident having happened yet. Not built: the player has no
# weapon to hold. When equipment lands, this belongs next to the stance
# check as a second way into OBSERVE, not a second way into ALERT — a drawn
# weapon is still not a fact on record, only a stronger reason to look
# closer.
#
# ALERT is now also readable, not just tracked in state: a SpotLight3D
# (Spotlight, child of DroneMesh) opens onto the player while ALERT and they
# are actually seen, addressed at them specifically — see
# _update_spotlight()'s own comment on why this replaces StatusLight's
# OmniLight3D color swap (unaddressed, barely legible in the greybox) as the
# thing a player actually notices, and why it opens/closes rather than
# switching instantly.
#
# StatusLight is gone — replaced by two small OmniLight3Ds (LightBarBlue/
# LightBarRed) blinking in antiphase while ALERT, the ambient "there is a
# drone in ALERT nearby" signal StatusLight used to carry with an instant
# colour lerp. The spotlight is the addressed signal (who it's looking at);
# the light bar is the ambient one (that it's looking at all).
#
# ALERT without a visible player is a SEARCH (_decide_search()), not a
# frozen hover — a motionless drone waiting for the player to walk up to it
# read as broken, not as a city responding to a fact on record. Search
# wanders search_radius of _tracked_player_position: the real last-known
# sighting if this drone has ever actually seen the player, otherwise the
# triggering incident's own position (seeded once, in _trigger_alert()).
# search_speed is deliberately closer to patrol_speed than to alert_speed —
# this is looking around an area, not a pursuit.
#
# Losing sight of the player in ALERT is now TWO phases, not one, on two
# DIFFERENT timers — collapsing them into one (alert_memory_time alone,
# 2026-08-13's first pass at this) meant a "search" that gave up after three
# seconds, barely long enough to reach a single wander point:
#
#   - alert_memory_time (unchanged in value, narrowed in meaning) is a
#     TOLERANCE: a brief loss of sight — a frame of occlusion, a corner
#     briefly blocking the line — holds position rather than immediately
#     lurching into search, the same way OBSERVE's own entry doesn't un-
#     trigger on a single dropped frame. Three seconds is right for "don't
#     twitch on a blink," wrong for "how long to actually look."
#
#   - search_duration is how long the search phase itself runs once the
#     tolerance is spent — see that export's own comment for the value and
#     why. Resets to 0 the moment the player is seen again (mid-search or
#     mid-tolerance both fall back to ordinary hold-and-watch on a
#     sighting); expiring without a sighting exits ALERT via the existing
#     OBSERVE-or-PATROL rule, same formula this file already used before
#     search existed.
#
# alert_incident_radius went to 600m and back to 60m during this work
# (2026-08-13) — a diagnostic detour, not a design change. The actual
# defect it was covering for: this drone only ever checked IncidentRegistry
# at fixed MOMENTS (resolving the registry, a load) and never as it moved,
# so a drone patrolling directly over a fresh incident noticed nothing
# unless the radius was inflated far past its intended scale to compensate.
# _update_patrol_scan() (patrol_scan_interval, PATROL only) closes that —
# see _check_existing_incidents()'s own header for all three hooks into
# that query and which covers what.
# =============================================================================
extends NPCControllerBase
class_name PatrolDroneController

## Distance the drone must arrive within before picking a new patrol point.
## Matches the old police_drone.gd's hand-tuned value.
const PATROL_ARRIVAL_RADIUS: float = 2.5
## Spotlight aim target height when the player node has no get_chest_height()
## — see _target_chest_height(). Same order-of-magnitude reasoning as
## PerceptionComponent's own RAY_TARGET_HEIGHT_FALLBACK, kept as this
## controller's own constant rather than reached into that unrelated file's,
## so the two don't have to be retuned together by coincidence.
const SPOTLIGHT_TARGET_HEIGHT_FALLBACK: float = 1.3

enum State { PATROL, OBSERVE, ALERT }

@export_group("Patrol")
## Half-width of the local patrol square, metres — same "±100m, 200x200
## total" shape as the old police_drone.gd.
@export var patrol_radius: float = 100.0
## Desired patrol speed, m/s — converted to DroneBase's speed_ratio against
## its own max_speed every frame, so this stays meaningful if max_speed is
## retuned on the body independently.
@export var patrol_speed: float = 5.0
## How often, seconds (real time — a perception cadence, like alert_memory_
## time, not a game-time value), a PATROL drone asks IncidentRegistry
## whether anything landed within alert_incident_radius of its CURRENT
## position — see _check_existing_incidents()'s own header for why this is
## a third, distinct hook into that query, not a fourth path into ALERT.
## Not every frame: this is a poll, and checking every frame would be pure
## waste against a registry that changes rarely. Not zero either — a drone
## that never re-checks its surroundings while patrolling is exactly the
## "flew right over the incident and noticed nothing" gap this closes. A
## feel value, tuned by eye like every other cadence in this file.
@export var patrol_scan_interval: float = 1.0

@export_group("Observe")
## Horizontal distance from the player this drone holds while OBSERVE —
## deliberately further than alert_hover_distance: watching from a
## respectful distance, not closing in the way an actual response does.
@export var observe_hover_distance: float = 10.0
## Desired speed while closing to observe_hover_distance, m/s — unhurried,
## closer to patrol_speed than to alert_speed: OBSERVE isn't urgency.
@export var observe_speed: float = 5.0

@export_group("Alert")
## Desired speed while closing in to observation distance in ALERT, m/s —
## same conversion as patrol_speed. Matches the old police_drone.gd's
## chase_speed value, repurposed: this is how fast it closes the gap, not a
## pursuit top speed.
@export var alert_speed: float = 12.0
## Horizontal distance from the player the drone holds once in ALERT —
## closes to this and stops, never all the way to the player. Vertical
## separation is not a separate parameter; see _decide_alert()'s comment.
@export var alert_hover_distance: float = 6.0
## Radius, metres, an incident must fall within (measured from the drone's
## current position, not its patrol origin) to trigger ALERT — see the file
## header on why an incident is the trigger now, not a raised stance. A
## feel/scale value: wide enough that a drone patrolling nearby plausibly
## notices, not so wide every drone in the district converges on one punch.
@export var alert_incident_radius: float = 60.0
## Whether a committed WITNESS REPORT dispatches this drone regardless of
## distance. alert_incident_radius above is unchanged and stays this
## drone's OWN noticing range — the two are separate channels, and this one
## is what makes reporting worth anything: a punch nobody calls in stays a
## local matter, a punch a witness transmits brings the city. See
## Incident.Source and NPC_REACTIONS.md §4.
##
## Only the LIVE incident_reported signal dispatches. The catch-up queries
## (_check_existing_incidents(), all three of its call sites) deliberately
## stay radius-bound — a day-old report restored from a save must not
## scramble every drone in the city the moment the player presses load.
@export var dispatch_on_witness_report: bool = true
## Seconds ALERT and OBSERVE tolerate the player being out of sight/lowered
## before reacting — NOT how long the resulting reaction lasts, see the file
## header on why those used to be the same number and stopped being one.
## For OBSERVE this is the whole story: past this tolerance it un-triggers
## straight to PATROL. For ALERT this only gates entry into the SEARCH
## phase (_decide_search()) — search_duration, a separate export, is what
## actually times that phase. A drone that reacts to a single dropped frame
## of perception reads as glitching, not calming down; three seconds is
## right for that purpose specifically. A feel value, tuned by eye — start
## at 3s per spec.
@export var alert_memory_time: float = 3.0
## Radius, metres, this drone wanders within while searching (ALERT, player
## not currently seen — see _decide_search()) — around _tracked_player_
## position, the same "last known point" _decide_hold_and_watch() already
## reads, seeded from the triggering incident's own position if this drone
## has never actually seen the player (see _trigger_alert()). A feel/scale
## value: wide enough that circling reads as looking around an area, not
## orbiting one exact point.
@export var search_radius: float = 20.0
## Desired speed while searching, m/s — deliberately closer to patrol_speed
## than to alert_speed: this is a drone looking around an area it already
## has a reason to suspect, not chasing a live sighting. Converted to
## DroneBase's speed_ratio the same way patrol_speed/alert_speed are.
@export var search_speed: float = 6.0
## Seconds the search phase itself runs (see _update_state()'s ALERT
## branch) before giving up and exiting ALERT via the existing OBSERVE-or-
## PATROL rule — starts counting only once alert_memory_time's own
## tolerance has already elapsed, and resets to 0 the instant the player is
## seen again. Deliberately NOT alert_memory_time: reusing that single
## value for search duration too (2026-08-13's first pass at this) meant a
## search that gave up after three seconds — barely enough to reach one
## wander point before quitting, which read as a shrug, not a search.
## 30.0 is derived from search_radius/search_speed, not picked blind: the
## expected distance between two random points inside a disk of radius R is
## ≈0.9·R, so at search_radius 20m and search_speed 6 m/s each leg between
## wander points takes roughly 3s — 30s covers on the order of ten distinct
## points, enough to read as an actual search. A feel value regardless,
## tuned by eye like every other cadence in this file.
@export var search_duration: float = 30.0

@export_group("Hold And Watch")
## Distance, metres, over which the drone brakes its closing speed to zero
## as it nears its current goal point (see _decide_hold_and_watch()'s own
## header) — a hard instant-stop boundary reads as flickering, especially
## once separation is nudging that goal point around frame to frame. A feel
## value; wide enough the brake is visible, not so wide the drone looks
## sluggish well short of arriving.
@export var hover_approach_margin: float = 2.0
## Distance, metres, inside which the drone counts itself as having arrived
## at its goal point and holds still rather than keep nudging toward it —
## without this the drone never actually rests, always crawling the last
## few centimetres. See _decide_hold_and_watch()'s own header for why a
## dead zone (not just braking) is what makes rest reachable at all now
## that separation offsets the goal point instead of blending into a
## velocity that never quite reaches zero.
@export var hold_deadband: float = 0.5

@export_group("Tracking")
## How quickly the drone's internally tracked player position catches up to
## the player's actual live position, a Smoothing.damp_factor() rate.
## mesh_turn_smoothing and spotlight_aim_smoothing already add some implicit
## lag turning the mesh/beam onto a target — this is a second, deliberately
## more visible lag on the target itself, on top of that: the drone's
## awareness of where the player currently is trails their actual motion,
## not just its own limbs catching up. Low enough to be seen: a player who
## changes direction quickly can make the spotlight swing past and curve
## back to find them again — that's the intended cinematic effect, not a
## bug. Well below mesh_turn_smoothing/spotlight_aim_smoothing on purpose,
## so this lag is the dominant, visible one rather than being swamped by
## those faster downstream dampers.
@export var player_tracking_lag: float = 2.0

@export_group("Spotlight")
## Relative to this controller node, same convention as the light bar paths
## below. Default matches the Spotlight node PoliceDrone.tscn adds under
## DroneMesh.
@export var spotlight_path: NodePath = ^"../DroneMesh/Spotlight"
## Full beam width, degrees (SpotLight3D.spot_angle) once fully open. A feel
## value, tuned by eye.
@export var spotlight_angle_deg: float = 20.0
## Beam reach, metres (SpotLight3D.spot_range) once fully open.
@export var spotlight_range: float = 25.0
@export var spotlight_energy: float = 8.0
## Spotlight geometry at the moment it comes on: a point, not a pool. The
## beam opening up onto the target is what reads as being found — a light
## that simply appears at full width reads as a switch being flipped.
@export var spotlight_angle_closed_deg: float = 1.5
@export var spotlight_range_closed: float = 4.0
## How fast the beam opens and closes. Opening slightly faster than closing
## is deliberate: being caught is abrupt, losing you is reluctant.
@export var spotlight_open_speed: float = 4.0
@export var spotlight_close_speed: float = 2.0
## How fast the beam settles onto the player, a Smoothing.damp_factor() rate
## — same idiom as DroneBase's own mesh_turn_smoothing. Deliberately not
## instant: a beam that lands exactly on the target every frame reads as
## glued to a rail, not as a drone tracking a moving person.
@export var spotlight_aim_smoothing: float = 6.0

@export_group("Light Bar")
## Relative to this controller node, same convention as spotlight_path
## above. Defaults match the LightBarBlue/LightBarRed nodes PoliceDrone.tscn
## adds — StatusLight's replacement, see the file header.
@export var light_bar_blue_path: NodePath = ^"../LightBarBlue"
@export var light_bar_red_path: NodePath = ^"../LightBarRed"
@export var light_bar_energy: float = 4.0
@export var light_bar_range: float = 5.0
## Full blink cycle, seconds — blue for the first half, red for the second.
## One shared phase accumulator drives both lights in antiphase (see
## _update_light_bar()), not two independent timers, so they can never both
## land on the same phase by drift. A feel value, tuned by eye.
@export var light_bar_period: float = 0.5

@export_group("Separation")
## Distance within which two drones start pushing apart from each other,
## metres. Only matters in OBSERVE/ALERT today — that is where multiple
## drones converge on the same player and, without this, stack on the same
## hover point.
@export var separation_radius: float = 12.0
## Metres of goal-point displacement per unit of _separation_offset (which
## is itself already normalised-ish by how close/many neighbours are, see
## _raw_separation_offset()) — NOT a blend weight against a direction
## anymore. It used to mix into the movement direction alongside the
## approach direction, which is exactly what produced a stable limit cycle
## (see _decide_hold_and_watch()'s own header): a drone at rest on the ring
## still had a nonzero separation-direction velocity, so it overshot past
## hover_approach_margin, regained a full-speed "return to the ring" pull,
## and flew straight back in — dithering forever with two or more drones.
## Offsetting the GOAL POINT instead means a pushed-apart drone has
## somewhere concrete to actually stop, not just a direction to keep
## drifting in.
@export var separation_weight: float = 1.5
## How fast the combined separation push itself settles toward its current
## raw value, a Smoothing.damp_factor() rate. _raw_separation_offset() is
## recomputed from scratch every frame from every other drone's live
## position — with several drones converging on one player that's an
## unsmoothed multi-agent feedback loop with no damping of its own. This
## smooths the one derived push vector, same "smooth the result once, not
## each ingredient independently" idiom _update_spotlight() already uses
## for _spotlight_open. Comparable to acceleration/braking on purpose: the
## push feeds straight into movement, so it shouldn't settle slower than
## the body itself does.
@export var separation_smoothing: float = 4.0

@export_group("Incident Registry")
## Seconds to keep retrying the group lookup before giving up and warning
## once — see the file header on why this can't be a single _ready() call.
## world.gd's IncidentRegistry should exist within the first couple of
## frames after startup; a wait this long past that means something is
## actually wrong (no IncidentRegistry in the scene at all), not a startup
## race.
@export var incident_registry_search_timeout: float = 5.0

## Resolved once in _ready() — NPCControllerBase's _actor narrowed to the
## drone-specific type this controller actually drives.
var _drone: DroneBase = null
## Sibling PerceptionComponent, same resolution pattern as
## IdleNPCController's own _perception.
var _perception: PerceptionComponent = null
## Resolved once in _ready() via spotlight_path. Null (and silently skipped
## by _update_spotlight()) if the scene has no spotlight yet.
var _spotlight: SpotLight3D = null
## Reveal factor, 0 (closed: a point, no light) .. 1 (fully open) — the one
## value _update_spotlight() eases toward its target and then derives
## spot_angle/spot_range/light_energy from, instead of easing those three
## independently. See that method's own comment for why one value, not
## three.
var _spotlight_open: float = 0.0
## Set once _target_chest_height() has warned about a player with no
## get_chest_height(), so the warning doesn't spam every call.
var _warned_missing_chest_height: bool = false
## Resolved once in _ready() via their paths above. Null (and silently
## skipped by _update_light_bar()) if the scene has no light bar yet.
var _light_bar_blue: OmniLight3D = null
var _light_bar_red: OmniLight3D = null
## Seconds into the current blink cycle, 0..light_bar_period — the one
## accumulator both lights read; see light_bar_period's own comment.
var _light_bar_phase: float = 0.0
## Resolved lazily via a group lookup, retried from _decide() until it
## succeeds — see the file header on why this can't be a single _ready()
## call. Null until then.
var _incident_registry: IncidentRegistry = null
## Seconds spent so far retrying the lookup — compared against
## incident_registry_search_timeout to decide when to warn.
var _incident_registry_search_time: float = 0.0
## Set once the timeout warning has fired, so it fires exactly once per
## instance instead of every frame the registry stays unresolved.
var _warned_missing_incident_registry: bool = false

## Smoothed stand-in for _raw_separation_offset() — see separation_smoothing's
## own comment. Updated once per frame by _update_separation_offset(), read
## everywhere else _decide_hold_and_watch() used to read the raw value.
var _separation_offset: Vector3 = Vector3.ZERO
## Stable per-drone escape direction, used only when another drone is within
## 0.001m of this one — see _raw_separation_offset()'s own comment. Computed
## once in _ready() from this drone's own instance ID, not re-rolled every
## frame: world.tscn spawns four PoliceDrone instances at the exact same
## transform, and a random per-frame direction here would just be a
## different flavour of the jitter this whole mechanism exists to remove.
## Distinct per instance so exactly-stacked drones scatter along different
## bearings instead of cancelling out.
var _fallback_separation_dir: Vector3 = Vector3.RIGHT

## Lagged stand-in for the player's live position — see player_tracking_lag's
## own comment. Both DroneMesh's look (set_look_target(), in
## _decide_hold_and_watch()) and the spotlight's aim (_aim_spotlight()) read
## this instead of observation.position directly, so the two stop chasing
## the live position independently at their own separate rates
## (mesh_turn_smoothing vs spotlight_aim_smoothing) — one lagged point, with
## each of those two dampers still turning toward it at its own rate on top.
var _tracked_player_position: Vector3 = Vector3.ZERO
## True once _tracked_player_position has been initialized from a real
## sighting. Guards the very first sighting so tracking starts exactly on
## the player instead of lerping in from Vector3.ZERO (the var's default)
## across the map.
var _has_tracked_player_position: bool = false

var _state: State = State.PATROL
## Seconds since the player was last actually seen while in ALERT — reset to
## 0 by _trigger_alert() on entry and by _update_state() every frame the
## player is seen again, only ever counted up while in ALERT and not seen.
## Gates entry into the search phase (compared against alert_memory_time,
## the tolerance) — NOT how long ALERT itself lasts, see _search_timer for
## that. Renamed in role, not in name, 2026-08-13 — see the file header.
var _alert_memory_timer: float = 0.0
## Seconds since the player last provoked OBSERVE (seen and in COMBAT) —
## reset to 0 by _update_state() every frame that's still true, only ever
## counted up while in OBSERVE. Compared against alert_memory_time, same
## tolerance _alert_memory_timer uses for ALERT's own entry into search —
## see that export's own comment.
var _observe_memory_timer: float = 0.0
## Seconds since the last periodic registry scan while PATROL — see
## patrol_scan_interval's own comment. Only ever counted up while PATROL
## (_update_patrol_scan() is only called from that branch of _decide()).
var _patrol_scan_timer: float = 0.0
## Seconds spent actively searching (ALERT, player not seen, past
## alert_memory_time's own tolerance) — compared against search_duration to
## decide when ALERT actually lapses. Only ever counted up during the
## search phase itself (see _update_state()'s ALERT branch); reset to 0 by
## _trigger_alert() on entry and by _update_state() the instant the player
## is seen again, same reset points as _alert_memory_timer.
var _search_timer: float = 0.0

## Current wander goal while searching (ALERT, player not seen) — same
## "goal point, arrive, pick a new one" idiom _patrol_target uses for
## PATROL, around _tracked_player_position instead of _start_position. See
## _decide_search()/_pick_new_search_target().
var _search_target: Vector3 = Vector3.ZERO
## False until the first search target is picked after entering ALERT —
## reset by _enter_state() on every ALERT entry, so a stale target from an
## earlier, unrelated ALERT episode is never reused.
var _has_search_target: bool = false

## Where a dispatch is sending this drone, and whether one is in flight.
## Distinct from _search_target: a dispatch is a single fixed destination
## the drone commits to crossing the map for, while a search target is one
## of many random points sampled around an anchor once it has arrived.
## Cleared on arrival (PATROL_ARRIVAL_RADIUS), after which the ordinary
## tolerance/search behaviour takes over anchored on the incident.
var _dispatch_target: Vector3 = Vector3.ZERO
var _has_dispatch_target: bool = false

## Captured once in _ready() — the patrol square's centre and rotation, same
## convention as the old police_drone.gd (a local square anchored to where
## the drone started, not world axes).
var _start_position: Vector3 = Vector3.ZERO
var _start_yaw: float = 0.0
var _patrol_target: Vector3 = Vector3.ZERO


func _ready() -> void:
	super._ready()
	_drone = _actor as DroneBase
	if not _drone:
		return
	for child in _drone.get_children():
		if child is PerceptionComponent:
			_perception = child
			break

	_start_position = _drone.global_position
	_start_yaw = _drone.global_rotation.y
	_pick_new_patrol_point()

	## See _fallback_separation_dir's own comment — a stable, per-instance
	## bearing rather than a per-frame random one.
	var fallback_angle := float(_drone.get_instance_id() % 3600) * (TAU / 3600.0)
	_fallback_separation_dir = Vector3(cos(fallback_angle), 0.0, sin(fallback_angle))

	if light_bar_blue_path != NodePath():
		_light_bar_blue = get_node_or_null(light_bar_blue_path) as OmniLight3D
	if light_bar_red_path != NodePath():
		_light_bar_red = get_node_or_null(light_bar_red_path) as OmniLight3D
	for bar_light in [_light_bar_blue, _light_bar_red]:
		if bar_light:
			bar_light.light_energy = light_bar_energy
			bar_light.omni_range = light_bar_range
			bar_light.visible = false

	if spotlight_path != NodePath():
		_spotlight = get_node_or_null(spotlight_path) as SpotLight3D
	if _spotlight:
		## Starts fully closed — _update_spotlight() drives it open from here,
		## it does not just apply the open values once.
		_spotlight.spot_angle = spotlight_angle_closed_deg
		_spotlight.spot_range = spotlight_range_closed
		_spotlight.light_energy = 0.0
		_spotlight.visible = false

	## Very likely to fail here (see the file header) — kept anyway, harmless,
	## and resolves immediately in the rare case ordering ever does favour
	## this instance. _decide() is what actually guarantees resolution.
	_try_resolve_incident_registry()


func _decide(delta: float) -> void:
	if not _drone:
		return

	if not _incident_registry:
		_try_resolve_incident_registry()
	if not _incident_registry:
		_incident_registry_search_time += delta
		if not _warned_missing_incident_registry \
				and _incident_registry_search_time >= incident_registry_search_timeout:
			_warned_missing_incident_registry = true
			push_warning(
				"[PatrolDroneController] %s: IncidentRegistry not found after %.1fs — "
				% [_drone.name, _incident_registry_search_time]
				+ "this drone's ALERT will never trigger on an incident"
			)

	var observation: PlayerObservation = null
	if _perception:
		observation = _perception.observe_player()

	_update_state(observation, delta)

	match _state:
		State.PATROL:
			_decide_patrol(delta)
			_update_patrol_scan(delta)
		State.OBSERVE:
			_decide_observe(observation, delta)
		State.ALERT:
			_decide_alert(observation, delta)

	_update_light_bar(delta)
	_update_spotlight(observation, delta)


## Human-readable state for debug tooling (perception_debug_panel.gd), same
## convention as IdleNPCController.get_visible_time().
func get_state_name() -> String:
	return State.keys()[_state]


## Seconds left before ALERT actually lapses back to OBSERVE-or-PATROL, or
## -1.0 outside ALERT ("n/a") — read by the perception debug panel. Spans
## BOTH phases behind one number, same contract this getter had before
## search existed, so the debug panel's existing "held by incident memory"
## line stays meaningful without that file needing to know search exists:
## still in the tolerance (haven't started searching yet) reports the rest
## of that tolerance PLUS the full search_duration still ahead; already
## searching reports what's left of search_duration alone.
func get_alert_memory_remaining() -> float:
	if _state != State.ALERT:
		return -1.0
	if _alert_memory_timer < alert_memory_time:
		return maxf(0.0, (alert_memory_time - _alert_memory_timer) + search_duration)
	return maxf(0.0, search_duration - _search_timer)


## Read by the perception debug panel — a getter instead of exposing
## _spotlight directly, same encapsulation as get_alert_memory_remaining().
## Reports whether a beam is actually rendered right now (_spotlight_open >
## 0), not the instantaneous ALERT+is_seen targeting condition
## _update_spotlight() checks each frame: that condition can flip false a
## full spotlight_close_speed's worth of seconds before the beam visually
## finishes collapsing, and this exists to tell a human what they'd actually
## see, not the logic behind it.
func is_spotlight_active() -> bool:
	return _spotlight != null and _spotlight.visible


## Read by the perception debug panel — whether ALERT is even reachable for
## this drone right now. False here (past the first frame or two) is exactly
## the silent-failure state this file's header describes; the panel is
## where a human actually notices it without waiting for the timeout
## warning.
func is_incident_registry_resolved() -> bool:
	return _incident_registry != null


## Retried from _decide() until it succeeds — see the file header on why a
## single _ready() call isn't enough. Idempotent past the first success: an
## already-resolved _incident_registry is left alone, and the signal is only
## ever connected once (on the call that finds it). The moment resolution
## succeeds is also the one and only time _check_existing_incidents() runs
## — see that method's own comment for why a one-time catch-up belongs here.
func _try_resolve_incident_registry() -> void:
	if _incident_registry:
		return
	var found := get_tree().get_first_node_in_group(
		IncidentRegistry.GROUP_INCIDENT_REGISTRY
	) as IncidentRegistry
	if not found:
		return
	_incident_registry = found
	_incident_registry.incident_reported.connect(_on_incident_reported)
	_incident_registry.incidents_restored.connect(_on_incidents_restored)
	_check_existing_incidents()


## The drone does not care that someone is there — the city is full of
## people. It cares that a fact is on record. See the file header on why
## this is IncidentRegistry.incident_reported now, not a raised stance.
## Always wins over whatever _update_state() left _state at — set directly,
## not gated on current state, since ALERT outranks both PATROL and OBSERVE
## unconditionally.
func _on_incident_reported(incident: Incident) -> void:
	if not _drone:
		return
	## Two channels, deliberately not one radius (Incident.Source):
	## DIRECT is this drone noticing something within its own
	## alert_incident_radius, WITNESS_REPORT is the city being told and
	## dispatching everyone, from anywhere. Only the live signal dispatches
	## — see dispatch_on_witness_report's own comment on why the catch-up
	## queries must not.
	var dispatched: bool = dispatch_on_witness_report \
			and incident.source == Incident.Source.WITNESS_REPORT
	if not dispatched \
			and incident.position.distance_to(_drone.global_position) > alert_incident_radius:
		return
	_trigger_alert(incident.position, dispatched)


## Catch-up query shared by THREE distinct hooks — see each call site below
## for which covers what. All three stay RADIUS-BOUND and never dispatch,
## whatever Source the records they find carry: dispatch is a response to
## being told something NOW, and replaying it from a restored save would
## scramble every drone in the city over a day-old report the moment the
## player presses load. Only the live incident_reported signal dispatches.
## for which covers what, and read all three before touching any one of
## them; none is redundant with either of the others:
##
## 1. _try_resolve_incident_registry() calls this once, the moment this
##    drone first resolves the registry — covers a drone that appears in a
##    world where the registry ALREADY holds relevant facts, i.e. this
##    drone's own block streaming back in after being unloaded. In today's
##    build this path is effectively inert (drones are static instances in
##    world.tscn, not yet real streamed content, and resolution happens in
##    the first few frames of a fresh session when the registry is reliably
##    still empty) but the hook is correct for when that stops being true.
##
## 2. _on_incidents_restored() calls this every time IncidentRegistry's
##    state is replaced wholesale by a load — covers the case that
##    resolving once at startup CANNOT: a load happens later, on a player
##    keypress, long after this drone already resolved the registry (and
##    _try_resolve_incident_registry() will never run again — see its own
##    early return). See incident_registry.gd's incidents_restored signal
##    for the full reasoning, and CHANGELOG.md (2026-08-1X) for the bug this
##    replaced — an earlier version of this file assumed resolving once was
##    enough for both this case and case 1, and it demonstrably was not.
##
## 3. _update_patrol_scan() calls this periodically (patrol_scan_interval),
##    only while PATROL — covers a drone that is simply flying near a
##    record that predates it noticing, which cases 1/2 cannot: both fire
##    once, at a moment in time, and say nothing about the drone's position
##    changing afterward. Without this, alert_incident_radius had to be
##    inflated far past its intended scale (60m -> 600m, briefly, during
##    diagnosis) to compensate for a drone that only ever checked its
##    surroundings at two fixed instants rather than as it moved — see
##    CHANGELOG.md (2026-08-13) for that diagnosis. 60m is the correct
##    value again now that a moving drone actually re-checks its
##    surroundings.
##
## None of the three poll every frame; each fires on its own distinct
## cadence or event. Reuses IncidentRegistry's own max_incident_age as the
## recency bound rather than inventing a second threshold: anything the
## registry still holds is by definition not stale by its own rule.
## Guarded against firing while already ALERT: a catch-up finding what this
## drone already knows about is not a new provocation, and letting it reset
## _alert_memory_timer would prevent ALERT's own decay (_update_state()'s
## ALERT branch) from ever completing — not a hypothetical anymore now that
## decay is live, see that method's own comment. _on_incident_reported()
## deliberately has no equivalent guard: a genuinely NEW live report while
## already ALERT is a real, fresh provocation, and should extend the hold.
func _check_existing_incidents() -> void:
	if _state == State.ALERT:
		return
	var nearby := _incident_registry.get_incidents_near(
		_drone.global_position, alert_incident_radius, _incident_registry.max_incident_age
	)
	if nearby.is_empty():
		return

	## Closest, not first/last — with more than one match, the nearest is
	## the most plausible reason THIS drone specifically noticed something,
	## and the most useful anchor to search around if the player isn't
	## seen yet (see _trigger_alert()).
	var closest := nearby[0]
	var closest_dist := closest.position.distance_to(_drone.global_position)
	for incident in nearby:
		var dist := incident.position.distance_to(_drone.global_position)
		if dist < closest_dist:
			closest = incident
			closest_dist = dist
	_trigger_alert(closest.position)


## Periodic scan while PATROL only — see patrol_scan_interval's own comment
## and _check_existing_incidents()'s header (case 3) for why this drone
## needs a THIRD hook into that query, not a fourth way into ALERT. Only
## ever called from _decide()'s PATROL branch, so OBSERVE/ALERT never pay
## for it, not even on the frame a state transition happens (that frame's
## match already reads the post-transition state).
func _update_patrol_scan(delta: float) -> void:
	if not _incident_registry:
		return
	_patrol_scan_timer += delta
	if _patrol_scan_timer < patrol_scan_interval:
		return
	_patrol_scan_timer = 0.0
	_check_existing_incidents()


## incidents_restored fires with no payload — see that signal's own comment
## for why — so this just re-runs the same catch-up query
## _try_resolve_incident_registry() already uses, rather than a parallel
## code path. See _check_existing_incidents()'s own comment for why all
## three hooks into it are needed and what each one covers.
func _on_incidents_restored() -> void:
	_check_existing_incidents()


## Single place ALERT is actually entered from, whichever of the four paths
## triggered it (live report, resolve-time catch-up, load-time catch-up,
## periodic scan) — one entry path, so none of them drift into slightly
## different "what does ALERT reset" behaviour. incident_position is the
## reporting incident's own location — used only to seed
## _tracked_player_position if this drone has never actually seen the
## player yet (_has_tracked_player_position false): _decide_search() needs
## SOME point to search around, and "where the triggering fact happened" is
## the only estimate available before an actual sighting. If the player has
## already been seen at least once, their real last-known position is used
## instead and incident_position is ignored — a live sighting is always a
## better anchor than the incident that merely provoked the escalation.
func _trigger_alert(incident_position: Vector3, is_dispatch: bool = false) -> void:
	if is_dispatch:
		## A dispatch names the place. It must overwrite any stale sighting
		## outright, unlike the local case below: the guard there exists so
		## a drone that HAS seen the player keeps searching where it last
		## saw them rather than at a second-hand coordinate, which is right
		## for something it noticed itself and wrong for being told where
		## to go.
		_tracked_player_position = incident_position
		_has_tracked_player_position = true
		_dispatch_target = incident_position
		_has_dispatch_target = true
	elif not _has_tracked_player_position:
		_tracked_player_position = incident_position
		_has_tracked_player_position = true
	_alert_memory_timer = 0.0
	_search_timer = 0.0
	_enter_state(State.ALERT)


## Resolves PATROL/OBSERVE every frame from the live stance/visibility read,
## and counts ALERT's own memory down when that's the current state — one
## method, not two, because falling out of ALERT needs the same "is the
## player still provoking OBSERVE right now" read OBSERVE's own entry uses.
## ALERT's own entry is _trigger_alert(), event-driven, and always wins
## regardless of what this method would otherwise resolve to that frame —
## this method never sets ALERT itself.
func _update_state(observation: PlayerObservation, delta: float) -> void:
	var provoking_observe := observation != null and observation.is_seen \
			and observation.stance == PlayerState.Stance.COMBAT

	if _state == State.ALERT:
		var seen := observation != null and observation.is_seen
		if seen:
			## Found (again) — ordinary hold-and-watch resumes in
			## _decide_alert(). Both timers reset: a sighting means
			## nothing is currently being tolerated or searched for.
			_alert_memory_timer = 0.0
			_search_timer = 0.0
			return

		## Not seen this frame. First tick toward alert_memory_time's own
		## tolerance — a brief loss of sight (a dropped frame, a moment
		## behind a corner) holds position rather than immediately
		## treating the player as actually lost; _decide_alert() mirrors
		## this same threshold for what it does with the body.
		_alert_memory_timer += delta
		if _alert_memory_timer < alert_memory_time:
			return

		## Tolerance spent — actively searching. Ticks search_duration
		## instead of alert_memory_time now; see search_duration's own
		## comment for why conflating the two (2026-08-13's first pass at
		## this) meant a search that gave up after three seconds.
		_search_timer += delta
		if _search_timer < search_duration:
			return

		## Search exhausted, still not found — exits via the same formula
		## this file used before search existed. provoking_observe needs
		## observation.is_seen, which this branch only reaches when false,
		## so OBSERVE is reachable here only in the edge case of a
		## sighting landing on the exact frame the search timer expires;
		## PATROL is the practical outcome otherwise.
		_enter_state(State.OBSERVE if provoking_observe else State.PATROL)
		return

	if provoking_observe:
		_observe_memory_timer = 0.0
		if _state != State.OBSERVE:
			_enter_state(State.OBSERVE)
		return

	if _state == State.OBSERVE:
		_observe_memory_timer += delta
		if _observe_memory_timer >= alert_memory_time:
			_enter_state(State.PATROL)


## Single place _state is actually assigned — PATROL needs a fresh patrol
## point on entry (the old one may be stale after however long OBSERVE/
## ALERT held); OBSERVE/ALERT need no equivalent setup, both read the
## current observation fresh every frame instead of capturing anything at
## entry.
func _enter_state(new_state: State) -> void:
	_state = new_state
	if new_state == State.PATROL:
		_pick_new_patrol_point()
	elif new_state == State.ALERT:
		## Discard any search target left over from an earlier, unrelated
		## ALERT episode — _decide_search() picks a fresh one, anchored to
		## wherever _tracked_player_position is NOW, on its first call.
		## _has_dispatch_target is deliberately NOT cleared here:
		## _trigger_alert() sets it immediately before calling this, and a
		## dispatch outlives the state entry that carried it.
		_has_search_target = false
	if new_state != State.ALERT:
		## Leaving ALERT abandons any trip still in flight — whatever ended
		## the alert (found the player, search expired) is a better reason
		## to be somewhere than a coordinate from a report.
		_has_dispatch_target = false


## OBSERVE: watches from observe_hover_distance, unhurried. See the shared
## _decide_hold_and_watch() below for what "watches" means mechanically.
func _decide_observe(observation: PlayerObservation, delta: float) -> void:
	_decide_hold_and_watch(observation, observe_hover_distance, observe_speed, delta)


## ALERT: hold-and-watch (same as OBSERVE, closer and faster) while the
## player is actually seen, and — mirroring _update_state()'s own
## alert_memory_time threshold — for a brief loss of sight too, still
## within tolerance: a drone that immediately lurches into searching over
## one dropped frame of perception reads as twitchy, not attentive. Only
## past that tolerance (_alert_memory_timer >= alert_memory_time) does
## _decide_search() actually take over. See the file header on why ALERT
## without a visible player used to just hover motionless waiting
## indefinitely — that read as broken, or as "waiting for the player to
## walk up to it," neither of which is what a drone escalated by a fact on
## record should look like.
func _decide_alert(observation: PlayerObservation, delta: float) -> void:
	if observation != null and observation.is_seen:
		## Seeing the player outranks everything, including a trip in
		## progress — arriving at a coordinate matters less than the person
		## who is right there. The dispatch flag survives, so losing sight
		## again resumes the trip rather than restarting the whole alert.
		_decide_hold_and_watch(observation, alert_hover_distance, alert_speed, delta)
		return
	if _has_dispatch_target:
		## En route. Deliberately ahead of the alert_memory_time tolerance
		## below: that tolerance exists to keep a drone from lurching into
		## a search over one dropped frame of perception, and it has
		## nothing to say about a drone that was told to be somewhere and
		## has not got there yet. Without this branch the drone would hover
		## through its own tolerance and then "search" from wherever it
		## happened to be standing, which is what made a dispatched drone
		## look like it was ignoring the report.
		_decide_dispatch()
		return
	if _alert_memory_timer < alert_memory_time:
		## Within tolerance — hold position rather than start searching
		## over a single perception blink. _decide_hold_and_watch()'s own
		## not-seen branch already just freezes in place, which is exactly
		## the behaviour wanted here too — reused, not duplicated.
		_decide_hold_and_watch(observation, alert_hover_distance, alert_speed, delta)
		return
	_decide_search(delta)


## Shared movement for OBSERVE and ALERT: closes to hover_distance and
## holds, never all the way to the player, aiming the mesh at them
## throughout (the spotlight, in ALERT, aims independently — see
## _aim_spotlight()). Vertical separation is not computed here — it comes
## free from DroneBase's own ground-following altitude hold (see that
## file's header): hovering
## near the player, who stands on the same local ground, already puts the
## drone hover_height above them.
##
## Flies toward a GOAL POINT and brakes to a stop on arrival — not a goal
## DIRECTION blended with a separation direction, the previous approach,
## which could never actually stop: at rest exactly on the ring, that blend
## degenerated to pure separation drift at nonzero speed, so a drone pushed
## off the ring by a neighbour immediately regained a nonzero "return to
## the ring" component the instant it crossed hover_approach_margin, and
## flew back in at speed — a stable limit cycle, not a resting state, read
## as dithering/circling with two or more drones. A point target has no
## such trap: separation offsets WHERE the drone is trying to go (in
## metres, added to the goal point) rather than blending into a velocity
## that's never actually zero, so arriving and braking (see hold_deadband
## below) is reachable regardless of how close a neighbour is.
##
## The goal point itself is the nearest spot on the hover ring to the
## drone's OWN current bearing from the tracked player (not, say, a fixed
## compass angle), so drones that start on different sides of the player
## stay on different sides rather than racing for one preferred point.
func _decide_hold_and_watch(observation: PlayerObservation, hover_distance: float, speed: float, delta: float) -> void:
	if observation == null or not observation.is_seen:
		## Out of sight but still inside the memory window — hold position
		## rather than steer at a stale sighting. The next observation, or
		## the memory timeout in _update_state(), decides what's next.
		_drone.set_move_intent(Vector3.ZERO, 0.0)
		return

	_update_tracked_player_position(observation.position, delta)
	_update_separation_offset(delta)

	## Tracked, laggy position drives movement, not observation.position —
	## this is what actually makes player_tracking_lag visible in how the
	## drone flies, not just in where it looks. Before this fix the goal
	## math read the live position directly, so the lag only ever showed up
	## in set_look_target() below, never in the flight path itself.
	var tracked_pos := _tracked_player_position
	var drone_pos := _drone.global_position

	var bearing := Vector3(drone_pos.x - tracked_pos.x, 0.0, drone_pos.z - tracked_pos.z)
	if bearing.length() < 0.001:
		## Degenerate only when the drone sits exactly above the tracked
		## point — no horizontal bearing to hold onto. Same stable
		## per-instance fallback _raw_separation_offset() uses for the same
		## reason, rather than a direction that would itself flicker.
		bearing = _fallback_separation_dir
	else:
		bearing = bearing.normalized()

	var ring_point := tracked_pos + bearing * hover_distance
	var goal_point := ring_point + _separation_offset * separation_weight

	var to_goal := Vector3(goal_point.x - drone_pos.x, 0.0, goal_point.z - drone_pos.z)
	var error := to_goal.length()

	if error < hold_deadband:
		## Actually at rest — the state the old direction-blend could never
		## reach. See this method's own header for why that mattered.
		_drone.set_move_intent(Vector3.ZERO, 0.0)
	else:
		var move_speed_ratio := _speed_ratio(speed) \
				* clampf(error / maxf(hover_approach_margin, 0.001), 0.0, 1.0)
		_drone.set_move_intent(to_goal.normalized(), move_speed_ratio)

	_drone.set_look_target(_tracked_player_position)


## Advances _tracked_player_position toward the player's live position at
## player_tracking_lag — called once per frame from _decide_hold_and_watch(),
## the one place both OBSERVE and ALERT read a live sighting from. Not
## advanced (frozen at its last value) while the player isn't currently
## seen — same "nothing fresh to chase" reasoning _aim_spotlight() and the
## movement hold above already use.
func _update_tracked_player_position(player_pos: Vector3, delta: float) -> void:
	if not _has_tracked_player_position:
		## First sighting ever — snap straight there instead of lerping in
		## from Vector3.ZERO across the map.
		_tracked_player_position = player_pos
		_has_tracked_player_position = true
		return
	_tracked_player_position = _tracked_player_position.lerp(
		player_pos, Smoothing.damp_factor(player_tracking_lag, delta)
	)


## Eases the combined separation push toward _raw_separation_offset()'s
## current value — see separation_smoothing's own comment for why the raw
## value can't be used directly.
func _update_separation_offset(delta: float) -> void:
	_separation_offset = _separation_offset.lerp(
		_raw_separation_offset(), Smoothing.damp_factor(separation_smoothing, delta)
	)


## Simple boids-style separation: a vector pointing away from every other
## DroneBase within separation_radius, stronger the closer they are. Zero
## when no other drone is close. Drones don't have a dedicated group of
## their own — ActorBase.GROUP_PERCEIVED_ACTOR already lists every NPC and
## drone, filtered here to DroneBase, same lookup pattern
## _target_chest_height() already uses for the player. Raw and unsmoothed by
## design — _update_separation_offset() is what turns this into something
## safe to feed into movement every frame; nothing else should call this
## directly.
func _raw_separation_offset() -> Vector3:
	var offset := Vector3.ZERO
	for candidate in get_tree().get_nodes_in_group(ActorBase.GROUP_PERCEIVED_ACTOR):
		if candidate == _drone or not (candidate is DroneBase):
			continue
		var other: DroneBase = candidate
		var away := _drone.global_position - other.global_position
		away.y = 0.0
		var dist := away.length()
		if dist < 0.001:
			## Exactly (or almost exactly) stacked — world.tscn spawns
			## several PoliceDrone instances at the identical transform, and
			## away.normalized() is undefined at zero length. Push along a
			## stable per-instance bearing instead of leaving this pair with
			## zero separation force between them.
			offset += _fallback_separation_dir
			continue
		if dist > separation_radius:
			continue
		offset += away.normalized() * (1.0 - dist / separation_radius)
	return offset


## Targeted only in ALERT while the player is actually seen — loses sight,
## loses the beam, rather than pinning a stale sighting. _spotlight_open is
## a single 0..1 reveal factor, eased toward 1 (targeted) or 0 (not) via
## Smoothing.damp_factor() at spotlight_open_speed/spotlight_close_speed —
## opening faster than it closes, same asymmetric-rate idea DroneBase's own
## acceleration/braking uses. spot_angle/spot_range/light_energy are all
## derived from that one value rather than eased independently: three
## separate smooths at the same nominal rate still drift apart frame to
## frame, and the beam opening up would stop reading as one motion — it is
## the growing cone, not any one property alone, that reads as the drone
## finding you. visible tracks _spotlight_open > 0 rather than the raw
## targeted condition, so a fully-closed beam (a point, zero energy) is not
## still counted by the engine as an active light. Aiming (_aim_spotlight())
## runs whenever there is any beam to aim, not only while targeted, so a
## still-collapsing beam keeps whatever direction it last had rather than
## snapping to rest.
func _update_spotlight(observation: PlayerObservation, delta: float) -> void:
	if not _spotlight:
		return

	var targeted := _state == State.ALERT and observation != null and observation.is_seen
	var open_rate := spotlight_open_speed if targeted else spotlight_close_speed
	_spotlight_open = lerpf(_spotlight_open, 1.0 if targeted else 0.0, Smoothing.damp_factor(open_rate, delta))

	_spotlight.spot_angle = lerpf(spotlight_angle_closed_deg, spotlight_angle_deg, _spotlight_open)
	_spotlight.spot_range = lerpf(spotlight_range_closed, spotlight_range, _spotlight_open)
	_spotlight.light_energy = spotlight_energy * _spotlight_open
	_spotlight.visible = _spotlight_open > 0.0

	if _spotlight_open > 0.0:
		_aim_spotlight(observation, delta)


## DroneMesh's own turn (drone_base.gd's _update_mesh_look()) is yaw-only by
## design — it flattens its look target to the mesh's own height before
## calling looking_at(), so the mesh, and by inheritance Spotlight (its
## plain identity-transform child), only ever faces the player's compass
## direction and never pitches down at them. From hover_height above the
## ground that leaves a beam that just tracked DroneMesh's rotation level,
## sailing over the player's head rather than landing on them — so this sets
## Spotlight's own global rotation directly instead, independent of
## DroneMesh's, the same Transform3D.looking_at() + interpolate_with() +
## Smoothing.damp_factor() idiom _update_mesh_look() itself uses. SpotLight3D
## shines along its local -Z — the node's own convention, unrelated to this
## project's +Z character-facing convention (see player.gd's
## get_facing_direction()) — so looking_at() needs no correction for it.
## Holds the last aim rather than steering at a stale sighting when the
## player isn't currently seen, same reasoning _decide_hold_and_watch() uses
## for movement — there is nothing fresh to aim at once sight is lost, even
## while the beam is still visibly collapsing.
func _aim_spotlight(observation: PlayerObservation, delta: float) -> void:
	if observation == null or not observation.is_seen:
		return

	## _tracked_player_position, not observation.position: see that var's own
	## comment — this keeps the spotlight chasing the same lagged point
	## DroneMesh's own look does, rather than two independently-damped
	## layers each reacting to the live position at their own rate.
	var target_point := _tracked_player_position + Vector3(0.0, _target_chest_height(), 0.0)
	if _spotlight.global_position.distance_to(target_point) < 0.05:
		return

	var target_transform := _spotlight.global_transform.looking_at(target_point, Vector3.UP)
	var t := Smoothing.damp_factor(spotlight_aim_smoothing, delta)
	_spotlight.global_transform = _spotlight.global_transform.interpolate_with(target_transform, t)


## Reads player.get_chest_height() via duck typing, same one-time-warning
## pattern PerceptionComponent._target_chest_height() and
## OnFootCameraComponent._target_metric_height() already use elsewhere in
## this project. The player node isn't threaded through PlayerObservation
## (a plain fact record with no node reference, by design — see that file's
## header), so this does its own group lookup, the same one
## PerceptionComponent.observe_player() already does to find the player.
func _target_chest_height() -> float:
	var player_node := get_tree().get_first_node_in_group("player")
	if player_node and player_node.has_method(&"get_chest_height"):
		return float(player_node.call(&"get_chest_height"))
	if not _warned_missing_chest_height:
		push_warning(
			"[PatrolDroneController] player has no get_chest_height() — "
			+ "spotlight aims at fallback height %.2f" % SPOTLIGHT_TARGET_HEIGHT_FALLBACK
		)
		_warned_missing_chest_height = true
	return SPOTLIGHT_TARGET_HEIGHT_FALLBACK


## Off outside ALERT (and the phase resets, so the next ALERT always starts
## on blue rather than wherever the phase happened to be left). In ALERT,
## one accumulator (_light_bar_phase) drives both lights in antiphase —
## blue for the first half of light_bar_period, red for the second — rather
## than two independent timers that could drift into both being on, or both
## off, at once.
func _update_light_bar(delta: float) -> void:
	if not _light_bar_blue or not _light_bar_red:
		return

	if _state != State.ALERT:
		_light_bar_phase = 0.0
		_light_bar_blue.visible = false
		_light_bar_red.visible = false
		return

	_light_bar_phase = fmod(_light_bar_phase + delta, light_bar_period)
	var blue_on := _light_bar_phase < light_bar_period * 0.5
	_light_bar_blue.visible = blue_on
	_light_bar_red.visible = not blue_on


func _decide_patrol(_delta: float) -> void:
	var dest_horizontal := Vector3(_patrol_target.x, _drone.global_position.y, _patrol_target.z)
	var dist := _drone.global_position.distance_to(dest_horizontal)

	if dist < PATROL_ARRIVAL_RADIUS:
		_pick_new_patrol_point()

	var direction := Vector3.ZERO
	if dist > 0.5:
		direction = (dest_horizontal - _drone.global_position).normalized()

	_drone.set_move_intent(direction, _speed_ratio(patrol_speed))
	_drone.set_look_target(_patrol_target)


## Ported as-is from the old police_drone.gd's pick_new_patrol_point() — a
## random point inside the local square, rotated to the drone's start yaw.
func _pick_new_patrol_point() -> void:
	var local_x := randf_range(-patrol_radius, patrol_radius)
	var local_z := randf_range(-patrol_radius, patrol_radius)
	var local_offset := Vector3(local_x, 0.0, local_z).rotated(Vector3.UP, _start_yaw)
	_patrol_target = _start_position + local_offset


## ALERT, player not currently seen: wanders the neighbourhood of
## _tracked_player_position (the real last-known sighting, or the
## triggering incident's own position if there was never a sighting — see
## _trigger_alert()) instead of holding still and waiting. Same "goal
## point, arrive, pick a new one" idiom _decide_patrol() uses for its own
## square — reuses PATROL_ARRIVAL_RADIUS as the arrival threshold rather
## than a second near-identical constant, since both mean the same thing
## ("close enough to this wander goal to pick another one"). Spotlight and
## light bar are untouched here — _update_spotlight()/_update_light_bar()
## already key off _state == State.ALERT and observation.is_seen
## independently of this movement, so search only changes where the drone
## flies, not what its lights do.
## Flies a straight line to the place a report named, at alert_speed, and
## clears the dispatch on arrival — after which _decide_alert() falls
## through to the ordinary tolerance/search behaviour, now anchored on the
## incident because _trigger_alert() seeded _tracked_player_position with
## it. Same fly-to-a-point shape as _decide_search() below, against a fixed
## destination instead of a resampled one; PATROL_ARRIVAL_RADIUS is reused
## as the arrival threshold rather than inventing a third one.
func _decide_dispatch() -> void:
	var to_target := _dispatch_target - _drone.global_position
	to_target.y = 0.0
	if to_target.length() < PATROL_ARRIVAL_RADIUS:
		_has_dispatch_target = false
		_drone.set_move_intent(Vector3.ZERO, 0.0)
		return

	_drone.set_move_intent(to_target.normalized(), _speed_ratio(alert_speed))
	_drone.set_look_target(_dispatch_target)


func _decide_search(_delta: float) -> void:
	if not _has_search_target \
			or _drone.global_position.distance_to(_search_target) < PATROL_ARRIVAL_RADIUS:
		_pick_new_search_target()

	var dist := _drone.global_position.distance_to(_search_target)
	var direction := Vector3.ZERO
	if dist > 0.5:
		direction = (_search_target - _drone.global_position).normalized()

	_drone.set_move_intent(direction, _speed_ratio(search_speed))
	_drone.set_look_target(_search_target)


## A random point inside search_radius of _tracked_player_position — same
## shape as _pick_new_patrol_point(), around the search anchor instead of
## the patrol square's centre.
func _pick_new_search_target() -> void:
	var local_x := randf_range(-search_radius, search_radius)
	var local_z := randf_range(-search_radius, search_radius)
	_search_target = _tracked_player_position + Vector3(local_x, 0.0, local_z)
	_has_search_target = true


## Converts an absolute m/s speed to DroneBase's 0..1 speed_ratio against its
## own current max_speed.
func _speed_ratio(desired_speed: float) -> float:
	return clampf(desired_speed / maxf(_drone.max_speed, 0.001), 0.0, 1.0)
