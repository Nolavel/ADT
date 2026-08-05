# =============================================================================
# perception_component.gd — PerceptionComponent: what this actor can sense
# about the player right now.
#
# Child of the actor node (same shape as npc/controllers/*: resolves its
# ActorBase parent once in _ready(), loudly disables itself on a mismatch —
# not NPC-only, DroneBase (world/police_drone/) hosts one too, same
# component, wider vision_range/vision_angle_deg exports).
# observe_player() reports a plain PlayerObservation — see that file's
# banner for why this component never decides what the fact means, only
# measures it. Vision only; hearing is out of scope for this pass.
# =============================================================================
extends Node3D
class_name PerceptionComponent

@export var vision_range: float = 90.0
@export var vision_angle_deg: float = 180.0

## Layers this component's line-of-sight raycast collides with: floor (2)
## and wall (3) — the exact same mask the camera's own occlusion raycast
## uses (on_foot_camera_component.gd, _update_camera_position()). Reusing
## it, not inventing a second wall/floor mask convention.
const LINE_OF_SIGHT_MASK: int = (1 << 1) | (1 << 2)

## Used only if the player node has no get_chest_height() — a safe non-zero
## ray-target height instead of aiming at the player's feet. Matches the
## order of magnitude of player.gd's own get_chest_height() (~1.3 at
## BODY_HEIGHT 1.8), it just isn't computed from a live character.
const RAY_TARGET_HEIGHT_FALLBACK: float = 1.3

var _npc: ActorBase = null
## Set once _target_chest_height() has warned about a player with no
## get_chest_height(), so the warning doesn't spam every call.
var _warned_missing_chest_height: bool = false


func _ready() -> void:
	var parent := get_parent()
	if not (parent is ActorBase):
		push_error("PerceptionComponent: parent '%s' is not an ActorBase — component disabled" % parent.name)
		return
	_npc = parent


## What this actor can sense about the player right now. Returns a plain
## observation — never an interpretation of it.
func observe_player() -> PlayerObservation:
	var observation := PlayerObservation.new()
	if not _npc:
		return observation

	var player_node := get_tree().get_first_node_in_group("player")
	if player_node == null or not (player_node is Node3D):
		return observation
	var player: Node3D = player_node

	observation.position = player.global_position

	var eye_pos := _npc.global_position + Vector3(0, _npc.get_eye_height(), 0)
	observation.distance = eye_pos.distance_to(player.global_position)

	# Facing comes from get_facing_direction(), never the basis — deriving
	# it from the basis is exactly the bug that broke lock-on's cone check.
	var facing := _npc.get_facing_direction()
	var to_player := player.global_position - eye_pos
	var horizontal_to_player := Vector3(to_player.x, 0.0, to_player.z)
	observation.angle_deg = rad_to_deg(facing.angle_to(horizontal_to_player.normalized())) \
			if horizontal_to_player.length() > 0.001 else 0.0

	if observation.distance > vision_range:
		return observation
	if observation.angle_deg > vision_angle_deg * 0.5:
		return observation

	var target_pos := player.global_position + Vector3(0, _target_chest_height(player), 0)
	var space_state := _npc.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(eye_pos, target_pos, LINE_OF_SIGHT_MASK)
	query.collide_with_areas = false
	query.exclude = [_npc.get_rid()]
	var hit := space_state.intersect_ray(query)
	if hit:
		return observation   # floor/wall geometry blocks the view

	observation.is_seen = true
	# Stance is a visual read (raised fists / weapon), same as the sight
	# check just passed — set it here, not earlier, so an occluded or
	# out-of-range player leaves stance at its PEACE default rather than
	# reporting something the NPC couldn't actually have seen.
	observation.stance = PlayerState.stance
	return observation


## Reads player.get_chest_height() via duck typing, same one-time-warning
## pattern OnFootCameraComponent uses for its own target-metric getters —
## the player node is found through a group lookup, not a static type, so
## its schema isn't guaranteed at compile time.
func _target_chest_height(player: Node3D) -> float:
	if player.has_method(&"get_chest_height"):
		return float(player.call(&"get_chest_height"))
	if not _warned_missing_chest_height:
		push_warning("PerceptionComponent: player '%s' has no get_chest_height() — using fallback ray-target height %.2f" % [player.name, RAY_TARGET_HEIGHT_FALLBACK])
		_warned_missing_chest_height = true
	return RAY_TARGET_HEIGHT_FALLBACK
