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
# incident_reported (core/world/incident_registry/), when the incident
# happened within alert_incident_radius of the drone — the same registry
# player.gd's punch reports to — and always wins over OBSERVE regardless of
# what the live stance/visibility read says that frame.
#
# Both rungs hold on the same memory shape (alert_memory_time), not two
# independent timers: ALERT doesn't un-trigger the instant the incident
# ages past the registry's own window, and OBSERVE doesn't un-trigger the
# instant the player lowers their stance or looks away — a drone that
# forgets mid-blink reads as glitching, not calming down. Losing ALERT's
# memory falls back to OBSERVE if the player is still seen and in COMBAT
# that frame, otherwise PATROL — the same live read OBSERVE's own entry
# uses, not a separate "was I provoked recently" flag.
#
# IncidentRegistry is a WORLD_SYSTEM_SCRIPTS entry (world.gd), not an
# autoload, and this drone is a static test instance placed directly in
# world.tscn — it never receives a WorldContext the way ClickToMoveSystem
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
# (Spotlight, child of DroneMesh) switches on while ALERT and the player is
# actually seen, addressed at them specifically — see _update_spotlight()'s
# own comment on why this replaces StatusLight's OmniLight3D color swap
# (unaddressed, barely legible in the greybox) as the thing a player
# actually notices.
#
# StatusLight is gone — replaced by two small OmniLight3Ds (LightBarBlue/
# LightBarRed) blinking in antiphase while ALERT, the ambient "there is a
# drone in ALERT nearby" signal StatusLight used to carry with an instant
# colour lerp. The spotlight is the addressed signal (who it's looking at);
# the light bar is the ambient one (that it's looking at all).
# =============================================================================
extends NPCControllerBase
class_name PatrolDroneController

## Distance the drone must arrive within before picking a new patrol point.
## Matches the old police_drone.gd's hand-tuned value.
const PATROL_ARRIVAL_RADIUS: float = 2.5

enum State { PATROL, OBSERVE, ALERT }

@export_group("Patrol")
## Half-width of the local patrol square, metres — same "±100m, 200x200
## total" shape as the old police_drone.gd.
@export var patrol_radius: float = 100.0
## Desired patrol speed, m/s — converted to DroneBase's speed_ratio against
## its own max_speed every frame, so this stays meaningful if max_speed is
## retuned on the body independently.
@export var patrol_speed: float = 5.0

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
## Seconds ALERT persists after the triggering incident ages out of memory,
## before lapsing back to OBSERVE-or-PATROL — and, reused (see the file
## header on why it's one shared shape, not two timers), seconds OBSERVE
## persists after the player lowers their stance or is lost from sight.
## Not zero either way: a drone that forgets the instant the fact is old,
## or the instant a fist is lowered, reads as glitching, not calming down.
## A feel value, tuned by eye — start at 3s per spec.
@export var alert_memory_time: float = 3.0

@export_group("Spotlight")
## Relative to this controller node, same convention as the light bar paths
## below. Default matches the Spotlight node PoliceDrone.tscn adds under
## DroneMesh.
@export var spotlight_path: NodePath = ^"../DroneMesh/Spotlight"
## Full beam width, degrees (SpotLight3D.spot_angle). A feel value, tuned by
## eye — applied once in _ready(), not tweened.
@export var spotlight_angle_deg: float = 20.0
## Beam reach, metres (SpotLight3D.spot_range).
@export var spotlight_range: float = 25.0
@export var spotlight_energy: float = 8.0

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

var _state: State = State.PATROL
## Seconds since the last incident that put this drone into ALERT — reset to
## 0 by _on_incident_reported() on every provoking report, only ever counted
## up while in ALERT. Compared against alert_memory_time to decide when
## ALERT lapses.
var _alert_memory_timer: float = 0.0
## Seconds since the player last provoked OBSERVE (seen and in COMBAT) —
## reset to 0 by _update_state() every frame that's still true, only ever
## counted up while in OBSERVE. Compared against alert_memory_time, same
## shared shape as _alert_memory_timer — see that export's own comment.
var _observe_memory_timer: float = 0.0

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
		_spotlight.spot_angle = spotlight_angle_deg
		_spotlight.spot_range = spotlight_range
		_spotlight.light_energy = spotlight_energy

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
		State.OBSERVE:
			_decide_observe(observation)
		State.ALERT:
			_decide_alert(observation)

	_update_light_bar(delta)
	_update_spotlight(observation)


## Human-readable state for debug tooling (perception_debug_panel.gd), same
## convention as IdleNPCController.get_visible_time().
func get_state_name() -> String:
	return State.keys()[_state]


## Seconds left before ALERT lapses back to OBSERVE-or-PATROL from memory
## alone, or -1.0 outside ALERT ("n/a") — read by the perception debug
## panel.
func get_alert_memory_remaining() -> float:
	if _state != State.ALERT:
		return -1.0
	return maxf(0.0, alert_memory_time - _alert_memory_timer)


## Read by the perception debug panel — a getter instead of exposing
## _spotlight directly, same encapsulation as get_alert_memory_remaining().
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
## ever connected once (on the call that finds it).
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


## The drone does not care that someone is there — the city is full of
## people. It cares that a fact is on record. See the file header on why
## this is IncidentRegistry.incident_reported now, not a raised stance.
## Always wins over whatever _update_state() left _state at — set directly,
## not gated on current state, since ALERT outranks both PATROL and OBSERVE
## unconditionally.
func _on_incident_reported(incident: Incident) -> void:
	if not _drone:
		return
	if incident.position.distance_to(_drone.global_position) > alert_incident_radius:
		return
	_alert_memory_timer = 0.0
	_enter_state(State.ALERT)


## Resolves PATROL/OBSERVE every frame from the live stance/visibility read,
## and counts ALERT's own memory down when that's the current state — one
## method, not two, because falling out of ALERT needs the same "is the
## player still provoking OBSERVE right now" read OBSERVE's own entry uses.
## ALERT's own entry is _on_incident_reported(), event-driven, and always
## wins regardless of what this method would otherwise resolve to that
## frame — this method never sets ALERT itself.
func _update_state(observation: PlayerObservation, delta: float) -> void:
	var provoking_observe := observation != null and observation.is_seen \
			and observation.stance == PlayerState.Stance.COMBAT

	if _state == State.ALERT:
		#_alert_memory_timer += delta
		#if _alert_memory_timer < alert_memory_time:
			#return
		#_enter_state(State.OBSERVE if provoking_observe else State.PATROL)
		## Temporary behaviour.
		##
		## Once an incident has escalated to ALERT, stay there indefinitely until
		## a proper resolution/de-escalation system exists. This keeps the
		## spotlight and light bar active instead of dropping back to PATROL after
		## alert_memory_time expires.
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


## OBSERVE: watches from observe_hover_distance, unhurried. See the shared
## _decide_hold_and_watch() below for what "watches" means mechanically.
func _decide_observe(observation: PlayerObservation) -> void:
	_decide_hold_and_watch(observation, observe_hover_distance, observe_speed)


## ALERT: the same watching behaviour, closer and faster to close the gap.
func _decide_alert(observation: PlayerObservation) -> void:
	_decide_hold_and_watch(observation, alert_hover_distance, alert_speed)


## Shared movement for OBSERVE and ALERT: closes to hover_distance and
## holds, never all the way to the player, aiming the mesh (and therefore
## the spotlight, in ALERT — see _update_spotlight()) at them throughout.
## Vertical separation is not computed here — it comes free from DroneBase's
## own ground-following altitude hold (see that file's header): hovering
## near the player, who stands on the same local ground, already puts the
## drone hover_height above them.
func _decide_hold_and_watch(observation: PlayerObservation, hover_distance: float, speed: float) -> void:
	if observation == null or not observation.is_seen:
		## Out of sight but still inside the memory window — hold position
		## rather than steer at a stale sighting. The next observation, or
		## the memory timeout in _update_state(), decides what's next.
		_drone.set_move_intent(Vector3.ZERO, 0.0)
		return

	var player_pos := observation.position
	var drone_pos := _drone.global_position
	var to_player := Vector3(player_pos.x - drone_pos.x, 0.0, player_pos.z - drone_pos.z)
	var dist := to_player.length()

	if dist > hover_distance:
		_drone.set_move_intent(to_player.normalized(), _speed_ratio(speed))
	else:
		_drone.set_move_intent(Vector3.ZERO, 0.0)

	_drone.set_look_target(player_pos)


## On only in ALERT while the player is actually seen — loses sight, loses
## the beam, rather than pinning a stale sighting. Aiming is not a separate
## mechanism: Spotlight is a plain child of DroneMesh (identity local
## transform, shining down its own -Z, same convention DroneMesh's own
## looking_at() turn already produces), so it tracks wherever
## _decide_alert()'s set_look_target() already points the mesh, at
## DroneBase's own mesh_turn_smoothing rate — no second "aim speed" export
## to keep in sync with that one.
func _update_spotlight(observation: PlayerObservation) -> void:
	if not _spotlight:
		return
	_spotlight.visible = _state == State.ALERT and observation != null and observation.is_seen


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


## Converts an absolute m/s speed to DroneBase's 0..1 speed_ratio against its
## own current max_speed.
func _speed_ratio(desired_speed: float) -> float:
	return clampf(desired_speed / maxf(_drone.max_speed, 0.001), 0.0, 1.0)
