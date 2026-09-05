# =============================================================================
# actor_base.gd — ActorBase, the physical-body contract shared by every AI
# actor that NPCControllerBase drives and PerceptionComponent watches.
#
# NPCBase (npc/npc_base.gd) and DroneBase (world/police_drone/drone_base.gd)
# integrate movement completely differently — a capsule that walks and a
# drone that hovers — but a controller and a perception component never need
# more than this much of either: where it is, which way it faces, where its
# sensor sits, a way to hand it a movement/look intent, and an opt-in contract
# for firearm hits. Every method here is a stub meant to be overridden;
# nothing on ActorBase itself runs a body.
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
# nobody asked for. This group lets perception/debug tooling and firearm target
# discovery enumerate actors without depending on a combat-specific group.
# can_receive_shot() is the second gate, so joining this group alone never
# makes an actor damageable.
# Subclasses that want combat lock-on join "lockable" themselves, as NPCBase
# already does.
#
# actor_id is this actor's contribution to H1's save contract
# (docs/scope_horizon.md): IncidentRegistry.report()/has_recent_incident_by()
# key on this instead of a Node3D reference, since a node reference is
# meaningless after a reload and meaningless once the block this actor lived
# in has been streamed out. Deliberately an authored @export, not something
# derived from get_path() or get_instance_id() — both change across a
# streaming reload/reinstantiation, which is exactly the case this id has to
# survive. It is authored the same way BlockBase's id or LodgingRoom's
# room_id are: set once by whoever places the instance, stable regardless of
# where in the tree it ends up. The player is not an ActorBase (player.gd
# extends CharacterBody3D directly) and carries its own id the same way —
# see player.gd's ACTOR_ID constant and get_actor_id() — so IncidentRegistry
# resolves both through the same duck-typed get_actor_id() call rather than
# two different lookups.
# =============================================================================
extends CharacterBody3D
class_name ActorBase

## Physical nature is orthogonal to an NPC's role/archetype. It defines
## perception capabilities shared by every actor type.
enum Nature {
	HUMAN,
	SYNTHETIC,
	ROBOT,
}

## Shared actor-discovery group — see the file header for why this is not
## "lockable" and why firearm targeting still needs can_receive_shot().
const GROUP_PERCEIVED_ACTOR: StringName = &"perceived_actor"

## Authored per actor instance rather than inherited from NPCArchetypeData:
## role and physical nature are independent axes.
@export var nature: Nature = Nature.HUMAN

## Stable id for this actor, authored per-instance — see the file header.
## Empty by default; every ActorBase placed in a scene that might ever
## report() or be reported on needs this set explicitly, the same way a
## BlockBase marker needs its own id set.
@export var actor_id: StringName = &""


func _ready() -> void:
	add_to_group(GROUP_PERCEIVED_ACTOR)
	if actor_id == &"":
		push_warning("[%s] actor_id is unset — this instance cannot be identified as an incident perpetrator/witness" % name)


## Stable id for IncidentRegistry (and any future consumer) to key on instead
## of this Node. Duck-typed rather than requiring a cast to ActorBase: the
## player carries the same method without extending this class.
func get_actor_id() -> StringName:
	return actor_id


## Whether this actor has a mechanical sensor capable of reading an iris.
func can_read_iris() -> bool:
	return nature != Nature.HUMAN


## Whether this actor owns a Votive terminal. The device belongs to humans;
## mechanical natures can perceive an iris but cannot transmit through one.
func has_votive() -> bool:
	return nature == Nature.HUMAN


## Whether firearm target discovery may select this actor. False by default:
## perception membership alone is not consent to participate in combat.
func can_receive_shot() -> bool:
	return false


## World-space landmark used consistently by shot selection, wall occlusion
## and the tracer endpoint. Only read when can_receive_shot() is true.
func get_shot_target_point() -> Vector3:
	return global_position + Vector3(0.0, get_eye_height(), 0.0)


## Receives a firearm hit after the player has selected this actor and proved
## the path clear. Damageable subclasses own what damage and death look like.
func take_hit(_from_position: Vector3, _damage: float = 25.0) -> void:
	pass


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
