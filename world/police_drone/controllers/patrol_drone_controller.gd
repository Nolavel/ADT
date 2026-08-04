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
# States are PATROL and ALERT, not PATROL/CHASE: what ALERT means and how it
# is triggered lands in the next commit — this one only ports the old
# police_drone.gd's local-square patrol pattern (unchanged: a random point
# inside a square centred on the drone's start position, rotated to its
# start yaw) onto the new DroneBase/PerceptionComponent split.
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

## Resolved once in _ready() — NPCControllerBase's _actor narrowed to the
## drone-specific type this controller actually drives.
var _drone: DroneBase = null
## Sibling PerceptionComponent, same resolution pattern as
## IdleNPCController's own _perception.
var _perception: PerceptionComponent = null

var _state: State = State.PATROL

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


func _decide(delta: float) -> void:
	if not _drone:
		return

	match _state:
		State.PATROL:
			_decide_patrol(delta)
		# State.ALERT is wired in the next commit — unreachable until then.


## Human-readable state for debug tooling (perception_debug_panel.gd), same
## convention as IdleNPCController.get_visible_time().
func get_state_name() -> String:
	return State.keys()[_state]


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
