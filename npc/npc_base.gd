# =============================================================================
# npc_base.gd — NPCBase, physical body and metrics shared by every NPC.
#
# Same separation as HoverBase (core/controllers/transport/base/hover_base.gd):
# the body integrates a movement intent, it never decides what that intent
# should be. set_move_intent() is the only way in; a controller node
# (npc/controllers/*, a child of this node) is the only thing that calls it.
# Of everything that makes up an NPC, the decision layer is the one part
# expected to change (hand-written state machine now, behaviour tree later)
# — body, movement and perception are meant to outlive that switch, so
# nothing here knows or cares which controller is driving it.
#
# Metric and facing getters (get_eye_height/get_shoulder_height/
# get_facing_direction) share names with player.gd's own: the TPS camera's
# target/lock-on code already reads these through duck typing, so any node
# carrying them is usable wherever the player is, without the reader needing
# to know it's an NPC. get_facing_direction() exists because this project's
# rotation convention (atan2(dir.x, dir.z), +Z forward) isn't Godot's usual
# -Z-forward — see that getter's own comment.
#
# No perception, navigation, reactions or animation yet — see
# npc/controllers/idle_npc_controller.gd, which drives this body with a
# permanently-zero intent until those land in later commits.
# =============================================================================
extends CharacterBody3D
class_name NPCBase

## How fast this body turns to face its movement direction, rad/s equivalent
## fed through Smoothing.damp_factor. Not exported — visual turn rate isn't
## a tuning knob yet, unlike walk_speed.
const TURN_SMOOTHING: float = 10.0

## Total height of this character. Per-instance data, not a constant: NPCs
## will vary. Landmark heights come from BodyMetrics ratios.
@export var body_height: float = 1.8
@export var walk_speed: float = 3.0

@export_group("Gravity")
## Same value and formula as player.gd's _apply_gravity(): one physical
## world, one gravity convention — not a second source to keep in sync.
@export var gravity: float = 20.0

## Movement intent for this frame, written by whatever controller drives
## this NPC. direction is expected normalised and horizontal (Y ignored);
## speed_ratio is 0..1, a fraction of walk_speed.
var _move_direction: Vector3 = Vector3.ZERO
var _move_speed_ratio: float = 0.0


func _ready() -> void:
	add_to_group("lockable")


func _physics_process(delta: float) -> void:
	velocity.x = _move_direction.x * walk_speed * _move_speed_ratio
	velocity.z = _move_direction.z * walk_speed * _move_speed_ratio
	if not is_on_floor():
		velocity.y -= gravity * delta
	move_and_slide()
	_face_move_direction(delta)


## Movement intent for this frame, written by whatever controller drives this
## NPC. The body integrates it; it never decides what the intent should be.
## direction is expected normalised and horizontal; speed_ratio is 0..1.
func set_move_intent(direction: Vector3, speed_ratio: float) -> void:
	_move_direction = direction
	_move_speed_ratio = clampf(speed_ratio, 0.0, 1.0)


## Character metric getters — same names as player.gd, so callers that duck
## type against the player (camera lock-on) work on an NPC unmodified.
func get_eye_height() -> float:
	return BodyMetrics.eye_height(body_height)


func get_shoulder_height() -> float:
	return BodyMetrics.shoulder_height(body_height)


## Direction this character visually faces, horizontal and normalised.
## NOTE: this project rotates characters with atan2(dir.x, dir.z), which makes
## +Z the visual forward, not Godot's usual -Z. Read facing through this getter
## instead of deriving it from the basis, or the sign will be wrong.
func get_facing_direction() -> Vector3:
	return Vector3(sin(rotation.y), 0.0, cos(rotation.y))


func _face_move_direction(delta: float) -> void:
	if _move_direction.length() < 0.01:
		return
	var target_angle := atan2(_move_direction.x, _move_direction.z)
	rotation.y = lerp_angle(rotation.y, target_angle, Smoothing.damp_factor(TURN_SMOOTHING, delta))
