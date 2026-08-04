# =============================================================================
# actor_base.gd — ActorBase, the physical-body contract shared by every AI
# actor that NPCControllerBase drives and PerceptionComponent watches.
#
# NPCBase (npc/npc_base.gd) and DroneBase (world/police_drone/drone_base.gd)
# integrate movement completely differently — a capsule that walks and a
# drone that hovers — but a controller and a perception component never need
# more than this much of either: where it is, which way it faces, where its
# sensor sits, and a way to hand it a movement/look intent. Every method here
# is a stub meant to be overridden; nothing on ActorBase itself runs a body.
#
# Introduced instead of widening NPCControllerBase/PerceptionComponent's
# "parent is NPCBase" checks to a hand-enumerated type union, so a future
# third actor type is a new subclass, not another check to update in two
# places.
#
# add_to_group(GROUP_PERCEIVED_ACTOR) in _ready() is deliberately NOT the
# same group as NPCBase's own "lockable" — "lockable" is the TPS combat
# camera's lock-on target pool (camera/tps_combat_camera_state.gd); making
# every ActorBase a combat target would hand the drone lock-on-able status
# nobody asked for. This group exists only so debug tooling can enumerate
# every perceived actor without depending on a combat-specific group.
# Subclasses that want combat lock-on join "lockable" themselves, as NPCBase
# already does.
# =============================================================================
extends CharacterBody3D
class_name ActorBase

## Debug-tooling enumeration group — see the file header for why this is not
## "lockable".
const GROUP_PERCEIVED_ACTOR: StringName = &"perceived_actor"


func _ready() -> void:
	add_to_group(GROUP_PERCEIVED_ACTOR)


## Movement intent for this frame, written by whatever controller drives
## this actor. The body integrates it; it never decides where to go.
func set_move_intent(_direction: Vector3, _speed_ratio: float) -> void:
	pass


## World point this actor orients toward. What "orienting" means is the
## body's own business — aiming a head, aiming a mesh, or something else.
func set_look_target(_point: Vector3) -> void:
	pass


## Returns to whatever this body treats as neutral orientation.
func clear_look_target() -> void:
	pass


## Height of this actor's sensor/eye point above its own origin. Perception
## raycasts and debug tooling read this instead of assuming where origin
## sits.
func get_eye_height() -> float:
	return 0.0


## Direction this actor visually faces, horizontal and normalised. Default
## assumes this project's rotation convention — atan2(dir.x, dir.z), +Z
## forward, not Godot's usual -Z — applied straight to the body's own
## rotation.y. Correct for any actor whose root actually turns to face
## (NPCBase). An actor whose root never rotates (DroneBase turns only its
## mesh) must override this instead of inheriting a constant answer.
func get_facing_direction() -> Vector3:
	return Vector3(sin(rotation.y), 0.0, cos(rotation.y))


## Short label for debug tooling ("NPC", "Drone", ...), so panels don't have
## to type-sniff (is NPCBase / is DroneBase) to say what a row is.
func get_debug_type_label() -> String:
	return "Actor"
