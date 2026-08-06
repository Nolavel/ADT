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
# States are PATROL and ALERT, not PATROL/CHASE. The old police_drone.gd's
# local-square patrol pattern (a random point inside a square centred on the
# drone's start position, rotated to its start yaw) is unchanged, ported
# onto DroneBase/PerceptionComponent.
#
# The drone does not react to a raised stance anymore — a fist in the air on
# an empty street used to be enough to summon a patrol, which reads as the
# city watching a pose rather than an event. The hierarchy now has two
# rungs: a raised stance (PlayerObservation.stance == COMBAT) is a reason to
# look closer, nothing this controller currently acts on beyond what
# idle_npc_controller.gd's own glance/turn gate already does elsewhere —
# ALERT is reserved for a fixed fact on record. It triggers on
# IncidentRegistry.incident_reported (core/world/incident_registry/), when
# the incident happened within alert_incident_radius of the drone — the
# same registry player.gd's punch reports to. It does not un-trigger the
# instant the incident ages past the registry's own window — alert_memory_
# time holds the state for a few seconds on its own clock, so the drone
# doesn't look like it forgot mid-blink.
#
# IncidentRegistry is a WORLD_SYSTEM_SCRIPTS entry (world.gd), not an
# autoload, and this drone is a static test instance placed directly in
# world.tscn — it never receives a WorldContext the way ClickToMoveSystem
# does (on_world_ready()). Resolved instead via get_tree().get_first_node_
# in_group(), the exact pattern PerceptionComponent already uses to find the
# player from anywhere in the tree, not a new lookup convention.
#
# Planned: a drawn weapon in COMBAT is itself a statement of intent — a
# blade or a firearm in hand should draw the drone's attention on its own,
# without an incident having happened yet. Not built: the player has no
# weapon to hold. When equipment lands, this belongs next to the incident
# check, as a weaker trigger.
# =============================================================================
extends NPCControllerBase
class_name PatrolDroneController

## Distance the drone must arrive within before picking a new patrol point.
## Matches the old police_drone.gd's hand-tuned value.
const PATROL_ARRIVAL_RADIUS: float = 2.5

enum State { PATROL, ALERT }

@export_group("Patrol")
## Half-width of the local patrol square, metres — same "±100m, 200x200
## total" shape as the old police_drone.gd.
@export var patrol_radius: float = 100.0
## Desired patrol speed, m/s — converted to DroneBase's speed_ratio against
## its own max_speed every frame, so this stays meaningful if max_speed is
## retuned on the body independently.
@export var patrol_speed: float = 5.0

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
## before lapsing back to PATROL. Not zero: a drone that forgets the instant
## the fact is old reads as glitching, not calming down. A feel value, tuned
## by eye — start at 3s per spec.
@export var alert_memory_time: float = 3.0

@export_group("Alert Signal")
## Status light this drone flashes red in ALERT. Relative to this
## controller node (a child of DroneBase, sibling of the light) — default
## matches the node PoliceDrone.tscn adds.
@export var light_path: NodePath = ^"../StatusLight"
@export var patrol_light_color: Color = Color(0.4, 0.7, 1.0)
@export var alert_light_color: Color = Color(1.0, 0.05, 0.05)
## Smoothing.damp_factor() rate for the color transition. Not instant —
## see the file header on why ALERT reads as an escalation, not a switch
## flip; the light follows the same logic as the state itself.
@export var light_color_smoothing: float = 3.0

## Resolved once in _ready() — NPCControllerBase's _actor narrowed to the
## drone-specific type this controller actually drives.
var _drone: DroneBase = null
## Sibling PerceptionComponent, same resolution pattern as
## IdleNPCController's own _perception.
var _perception: PerceptionComponent = null
## Resolved once in _ready() via light_path. Null (and silently skipped by
## _update_light()) if the scene has no status light yet.
var _light: OmniLight3D = null
## Resolved once in _ready() via a group lookup — see the file header on why
## this drone can't reach it through WorldContext. Null (and ALERT then
## never triggers, silently — same defensive shape as _light) if no
## IncidentRegistry exists in the scene, which should only happen in an
## isolated test scene, not the real game.
var _incident_registry: IncidentRegistry = null

var _state: State = State.PATROL
## Seconds since the last incident that put this drone into ALERT — reset to
## 0 by _on_incident_reported() on every provoking report, only ever counted
## up while in ALERT. Compared against alert_memory_time to decide when
## ALERT lapses.
var _alert_memory_timer: float = 0.0
var _current_light_color: Color = Color(0.4, 0.7, 1.0)

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

	if light_path != NodePath():
		_light = get_node_or_null(light_path) as OmniLight3D
	_current_light_color = patrol_light_color

	_incident_registry = get_tree().get_first_node_in_group(
		IncidentRegistry.GROUP_INCIDENT_REGISTRY
	) as IncidentRegistry
	if _incident_registry:
		_incident_registry.incident_reported.connect(_on_incident_reported)


func _decide(delta: float) -> void:
	if not _drone:
		return

	var observation: PlayerObservation = null
	if _perception:
		observation = _perception.observe_player()

	_update_alert_memory(delta)

	match _state:
		State.PATROL:
			_decide_patrol(delta)
		State.ALERT:
			_decide_alert(observation)

	_update_light(delta)


## Human-readable state for debug tooling (perception_debug_panel.gd), same
## convention as IdleNPCController.get_visible_time().
func get_state_name() -> String:
	return State.keys()[_state]


## Seconds left before ALERT lapses back to PATROL from memory alone, or
## -1.0 outside ALERT ("n/a") — read by the perception debug panel.
func get_alert_memory_remaining() -> float:
	if _state != State.ALERT:
		return -1.0
	return maxf(0.0, alert_memory_time - _alert_memory_timer)


## The drone does not care that someone is there — the city is full of
## people. It cares that a fact is on record. See the file header on why
## this is IncidentRegistry.incident_reported now, not a raised stance.
func _on_incident_reported(incident: Incident) -> void:
	if not _drone:
		return
	if incident.position.distance_to(_drone.global_position) > alert_incident_radius:
		return
	_alert_memory_timer = 0.0
	_state = State.ALERT


## Counts ALERT down toward PATROL on its own clock — the trigger itself is
## _on_incident_reported() now, event-driven, not polled here.
func _update_alert_memory(delta: float) -> void:
	if _state != State.ALERT:
		return

	_alert_memory_timer += delta
	if _alert_memory_timer >= alert_memory_time:
		_state = State.PATROL
		_pick_new_patrol_point()


## Observation, not pursuit: closes to alert_hover_distance and holds,
## never all the way to the player. Vertical separation is not computed
## here — it comes free from DroneBase's own ground-following altitude
## hold (see that file's header): hovering near the player, who stands on
## the same local ground, already puts the drone hover_height above them.
func _decide_alert(observation: PlayerObservation) -> void:
	if observation == null or not observation.is_seen:
		## Out of sight but still inside the memory window — hold position
		## rather than steer at a stale sighting. The next observation, or
		## the memory timeout in _update_alert_memory(), decides what's next.
		_drone.set_move_intent(Vector3.ZERO, 0.0)
		return

	var player_pos := observation.position
	var drone_pos := _drone.global_position
	var to_player := Vector3(player_pos.x - drone_pos.x, 0.0, player_pos.z - drone_pos.z)
	var dist := to_player.length()

	if dist > alert_hover_distance:
		_drone.set_move_intent(to_player.normalized(), _speed_ratio(alert_speed))
	else:
		_drone.set_move_intent(Vector3.ZERO, 0.0)

	_drone.set_look_target(player_pos)


func _update_light(delta: float) -> void:
	if not _light:
		return
	var target := alert_light_color if _state == State.ALERT else patrol_light_color
	_current_light_color = _current_light_color.lerp(target, Smoothing.damp_factor(light_color_smoothing, delta))
	_light.light_color = _current_light_color


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
