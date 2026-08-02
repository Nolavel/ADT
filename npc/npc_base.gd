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
# Perception exists now (npc_components/perception_component/), and this
# body can aim its Head at a world point via set_look_target()/
# clear_look_target() — but it still never decides WHAT to look at. That
# decision lives in the controller (idle_npc_controller.gd today), same as
# movement intent. No navigation, reactions or animation yet.
# =============================================================================
extends CharacterBody3D
class_name NPCBase

## How fast this body turns to face its movement direction, rad/s equivalent
## fed through Smoothing.damp_factor. Not exported — visual turn rate isn't
## a tuning knob yet, unlike walk_speed.
const TURN_SMOOTHING: float = 10.0
## How fast the head turns toward its look target (and back to neutral).
## Faster than TURN_SMOOTHING on purpose — heads snap to attention quicker
## than the body reorients. This is a damp_factor() decay rate in "times per
## second," not degrees or radians per second — see Smoothing.damp_factor().
const HEAD_TURN_SMOOTHING: float = 15.0
## Head rotation limits relative to the body. Past these the head stops,
## rather than turning past what a neck can do.
const HEAD_YAW_LIMIT_DEG: float = 70.0
const HEAD_PITCH_LIMIT_DEG: float = 30.0

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

## World point the body turns toward when it isn't moving — set by
## set_facing_target()/clear_facing_target(), read only by
## _face_move_direction(). Movement always overrides this; see that
## method's comment.
var _has_facing_target: bool = false
var _facing_target_point: Vector3 = Vector3.ZERO

## Whether the head currently has somewhere to look, and where — set by
## set_look_target()/clear_look_target(), read only by _update_head_look().
var _has_look_target: bool = false
var _look_target_point: Vector3 = Vector3.ZERO
## Smoothed head yaw/pitch relative to the body, in degrees. Yaw follows
## this project's atan2(x, z) convention, same as body rotation; pitch is
## positive when the head tilts to look up.
var _head_yaw_deg: float = 0.0
var _head_pitch_deg: float = 0.0

@onready var _head: Node3D = $Head


func _ready() -> void:
	add_to_group("lockable")


func _physics_process(delta: float) -> void:
	velocity.x = _move_direction.x * walk_speed * _move_speed_ratio
	velocity.z = _move_direction.z * walk_speed * _move_speed_ratio
	if not is_on_floor():
		velocity.y -= gravity * delta
	move_and_slide()
	_face_move_direction(delta)
	_update_head_look(delta)


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


## Point this character's head turns toward, in world space. The body only
## aims the head; whether there is anything worth looking at is a decision,
## and decisions live in the controller.
func set_look_target(point: Vector3) -> void:
	_has_look_target = true
	_look_target_point = point


## Returns the head to neutral (facing the same way as the body).
func clear_look_target() -> void:
	_has_look_target = false


## World point this character turns its body toward. Overrides
## face-move-direction while set. The body only turns; whether anything is
## worth turning toward is a decision, and decisions live in the controller.
func set_facing_target(point: Vector3) -> void:
	_has_facing_target = true
	_facing_target_point = point


## Returns to move-direction-only facing (the previous, only behaviour).
func clear_facing_target() -> void:
	_has_facing_target = false


## Whether the body currently has a facing target — read by the perception
## debug panel so "the body didn't turn" is distinguishable from "nothing
## asked it to."
func has_facing_target() -> bool:
	return _has_facing_target


## Turns the body to face _move_direction while moving; otherwise turns
## toward _facing_target_point if one is set (see set_facing_target()).
## Movement always wins: an NPC that is walking somewhere faces where it's
## walking, never a facing target — otherwise it would visibly walk
## sideways or backwards while "looking" elsewhere. Not exercised yet
## (nothing sets a facing target while _move_direction is nonzero), but the
## priority is worth having in place before it is.
func _face_move_direction(delta: float) -> void:
	var target_angle: float
	if _move_direction.length() > 0.01:
		target_angle = atan2(_move_direction.x, _move_direction.z)
	elif _has_facing_target:
		var to_target := _facing_target_point - global_position
		var horizontal_to_target := Vector3(to_target.x, 0.0, to_target.z)
		if horizontal_to_target.length() < 0.01:
			return
		target_angle = atan2(horizontal_to_target.x, horizontal_to_target.z)
	else:
		return
	rotation.y = lerp_angle(rotation.y, target_angle, Smoothing.damp_factor(TURN_SMOOTHING, delta))


## Aims _head at _look_target_point, clamped to HEAD_YAW_LIMIT_DEG/
## HEAD_PITCH_LIMIT_DEG relative to the body, or eases back to neutral
## (0, 0) when there is no look target. Head.rotation.y follows this
## project's atan2(x, z) yaw convention, composed with the body's own
## rotation.y (Head is a child of this node, so its world yaw is the sum of
## the two). Head.rotation.x is written assuming the head's own local +Z is
## its "forward", matching the body's convention rather than Godot's usual
## -Z, so a future asymmetric head asset stays consistent with the rest of
## the rig — unverifiable against today's symmetric placeholder cube.
func _update_head_look(delta: float) -> void:
	if not _head:
		return

	var target_yaw_deg := 0.0
	var target_pitch_deg := 0.0

	if _has_look_target:
		var eye_pos := global_position + Vector3(0, get_eye_height(), 0)
		var to_target := _look_target_point - eye_pos
		var horizontal_to_target := Vector3(to_target.x, 0.0, to_target.z)
		var horizontal_dist := horizontal_to_target.length()

		if horizontal_dist > 0.01:
			var facing := get_facing_direction()
			var body_yaw := atan2(facing.x, facing.z)
			var target_world_yaw := atan2(horizontal_to_target.x, horizontal_to_target.z)
			target_yaw_deg = rad_to_deg(wrapf(target_world_yaw - body_yaw, -PI, PI))
			target_pitch_deg = -rad_to_deg(atan2(to_target.y, horizontal_dist))

	target_yaw_deg = clampf(target_yaw_deg, -HEAD_YAW_LIMIT_DEG, HEAD_YAW_LIMIT_DEG)
	target_pitch_deg = clampf(target_pitch_deg, -HEAD_PITCH_LIMIT_DEG, HEAD_PITCH_LIMIT_DEG)

	var t := Smoothing.damp_factor(HEAD_TURN_SMOOTHING, delta)
	_head_yaw_deg = lerp(_head_yaw_deg, target_yaw_deg, t)
	_head_pitch_deg = lerp(_head_pitch_deg, target_pitch_deg, t)

	_head.rotation = Vector3(deg_to_rad(_head_pitch_deg), deg_to_rad(_head_yaw_deg), 0.0)
