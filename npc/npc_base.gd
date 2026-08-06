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
# Extends ActorBase (core/characters/actor_base.gd), the contract
# NPCControllerBase and PerceptionComponent actually type-check against —
# DroneBase (world/police_drone/drone_base.gd) extends the same base and
# reuses both. get_facing_direction() is inherited unmodified: NPCBase's
# root really does turn to face (_face_move_direction() below), which is
# exactly what ActorBase's default assumes.
#
# Metric and facing getters (get_eye_height/get_shoulder_height/
# get_facing_direction) share names with player.gd's own: the TPS camera's
# target/lock-on code already reads these through duck typing, so any node
# carrying them is usable wherever the player is, without the reader needing
# to know it's an NPC. get_facing_direction() exists because this project's
# rotation convention (atan2(dir.x, dir.z), +Z forward) isn't Godot's usual
# -Z-forward — see ActorBase's own comment on that getter.
#
# Perception exists now (npc_components/perception_component/), and this
# body can aim its head at a world point via set_look_target()/
# clear_look_target() — but it still never decides WHAT to look at. That
# decision lives in the controller (idle_npc_controller.gd today), same as
# movement intent.
#
# set_look_target()/clear_look_target() are state only — NPCAnimationComponent
# (npc_components/animation_component/) is what actually turns the head, via
# a LookAtModifier3D on the skeleton, read through has_look_target()/
# get_look_target_point() below. This body used to rotate a placeholder Head
# node by hand; that node is gone along with the capsule mesh once the real
# rig landed (see the npc.tscn commit) — the public contract didn't change,
# only where the turning happens.
#
# take_hit()/is_knocked_down() are a new contract, NPCBase-only rather than
# on ActorBase: DroneBase has no animation component to play a fall/getup
# clip on, and a flying body being knocked to the ground is a bigger,
# separate feature (real falling physics, a "crashed" state) this doesn't
# build. A punch that reaches a drone in flight just doesn't connect — see
# player.gd's own hit-detection comment.
#
# The knockdown sequence is three fixed-duration phases (FALLING/LYING/
# GETTING_UP, see KnockdownPhase and _update_knockdown()), not two with a
# poll on animation completion — an earlier version fired the knockdown
# clip once and then just waited out knockdown_duration before firing
# getup, which glitched: AnimationNodeOneShot goes inactive — and the
# locomotion tree underneath shows straight through, an idle pop mid-fall —
# the instant its CURRENT clip finishes playing, regardless of how long the
# controller wants to hold the pose for. A non-looping clip finishes on its
# own schedule, not the controller's. The fix is the LYING phase playing a
# looping clip (new4/ko-idle-loop, not the non-looping "ko-idle" also in the
# library — see npc_animation_component.gd's own comment on ANIM_LIE): a
# loop never finishes on its own, so it holds exactly as long as
# knockdown_hold_time says. FALLING/GETTING_UP still use non-looping clips
# and are still nominally at risk of the same gap if their own exported
# durations are tuned LONGER than the real clip lengths — tune them at or
# under, never over, and the phase transition (which always fires an
# explicit re-request, cutting the old clip off) preempts the gap entirely.
# =============================================================================
extends ActorBase
class_name NPCBase

## Total height of this character. Per-instance data, not a constant: NPCs
## will vary. Landmark heights come from BodyMetrics ratios.
@export var body_height: float = 1.8
@export var walk_speed: float = 3.0

@export_group("Turning")
## How fast this body turns to face its movement direction or a facing
## target, rad/s equivalent fed through Smoothing.damp_factor. A feel
## value, tuned by eye — exported for that reason, same as walk_speed.
@export var turn_smoothing: float = 10.0

@export_group("Gravity")
## Same value and formula as player.gd's _apply_gravity(): one physical
## world, one gravity convention — not a second source to keep in sync.
@export var gravity: float = 20.0

@export_group("Knockdown")
## Seconds the fall clip (new4/knockdown) plays before the lying phase takes
## over. Tune at or under the real clip's own length — see the file header
## on why longer reopens the gap this fix closes.
@export var knockdown_fall_time: float = 0.6
## Seconds the body holds the lying-idle loop (new4/ko-idle-loop) before
## getting up — the bulk of the sequence, and the one phase immune to being
## tuned "too long" (a looping clip never ends on its own). This is what
## reads as "down."
@export var knockdown_hold_time: float = 2.0
## Seconds the getup clip (new4/ko-getup) plays before control returns to
## the controller. Same tuning caveat as knockdown_fall_time — at or under
## the real clip length, not over.
@export var knockdown_getup_time: float = 1.0

## Movement intent for this frame, written by whatever controller drives
## this NPC. direction is expected normalised and horizontal (Y ignored);
## speed_ratio is 0..1, a fraction of walk_speed.
var _move_direction: Vector3 = Vector3.ZERO
var _move_speed_ratio: float = 0.0

## FALLING plays the knockdown clip, LYING holds the looping idle clip,
## GETTING_UP plays the getup clip — see _update_knockdown() for the
## fixed-duration timing of each and the file header for why fixed
## durations, not animation-completion polling, is what fixed the pop.
enum KnockdownPhase { FALLING, LYING, GETTING_UP }

## Knocked down by a hit — see take_hit()'s own comment. While true, this
## body ignores movement intent outright (_physics_process branches on it
## directly, not by refusing set_move_intent() calls) and the controller is
## expected to have stopped calling set_move_intent()/set_look_target() at
## all (see is_knocked_down()).
var _knocked_down: bool = false
## Which of the three phases is currently playing — see KnockdownPhase.
var _knockdown_phase: KnockdownPhase = KnockdownPhase.FALLING
## Seconds spent in the CURRENT phase — reset to 0 on every phase change,
## compared against that phase's own exported duration.
var _knockdown_phase_timer: float = 0.0


## World point the body turns toward when it isn't moving — set by
## set_facing_target()/clear_facing_target(), read only by
## _face_move_direction(). Movement always overrides this; see that
## method's comment.
var _has_facing_target: bool = false
var _facing_target_point: Vector3 = Vector3.ZERO

## Whether the head currently has somewhere to look, and where — set by
## set_look_target()/clear_look_target(), read by NPCAnimationComponent
## through the getters below (has_look_target()/get_look_target_point()).
var _has_look_target: bool = false
var _look_target_point: Vector3 = Vector3.ZERO

## Resolved once via @onready. Null (and silently skipped by
## _physics_process()) if the scene has no AnimationComponent — same
## defensive pattern the old $Head lookup used to have.
@onready var _animation: NPCAnimationComponent = get_node_or_null("AnimationComponent")


func _ready() -> void:
	super._ready()
	add_to_group("lockable")


func _physics_process(delta: float) -> void:
	if _knocked_down:
		velocity.x = 0.0
		velocity.z = 0.0
	else:
		velocity.x = _move_direction.x * walk_speed * _move_speed_ratio
		velocity.z = _move_direction.z * walk_speed * _move_speed_ratio
	if not is_on_floor():
		velocity.y -= gravity * delta
	move_and_slide()
	if _knocked_down:
		_update_knockdown(delta)
	else:
		_face_move_direction(delta)
	if _animation:
		_animation.update_animation_blend(delta)
		_animation.update_head_look(delta)


## Movement intent for this frame, written by whatever controller drives this
## NPC. The body integrates it; it never decides what the intent should be.
## direction is expected normalised and horizontal; speed_ratio is 0..1.
func set_move_intent(direction: Vector3, speed_ratio: float) -> void:
	_move_direction = direction
	_move_speed_ratio = clampf(speed_ratio, 0.0, 1.0)


## Read by NPCAnimationComponent to drive the idle<->walk blend — the same
## 0..1 fraction of walk_speed set_move_intent() was given.
func get_move_speed_ratio() -> float:
	return _move_speed_ratio


## Knocked down by a hit. Not damage — this project has no health yet. The
## fall is what makes the hit legible to the player and to anything
## watching.
##
## Ignored while already knocked down (a second hit mid-fall doesn't restart
## the timer — there is no stacking/combo concept here). Clears any facing/
## look target and zeroes movement intent outright, since a knocked-down
## body no longer has a controller deciding either — see is_knocked_down().
func take_hit(_from_position: Vector3) -> void:
	if _knocked_down:
		return
	_knocked_down = true
	_knockdown_phase = KnockdownPhase.FALLING
	_knockdown_phase_timer = 0.0
	_move_direction = Vector3.ZERO
	_move_speed_ratio = 0.0
	clear_look_target()
	clear_facing_target()
	if _animation:
		_animation.play_knockdown()


## Read by the controller (idle_npc_controller.gd's _decide()) to stop
## deciding outright while this body is down — the body itself already
## refuses to move regardless (see _physics_process()), this is what lets
## the controller stop calling set_move_intent()/set_look_target() at all
## rather than calling them into a body that's ignoring them.
func is_knocked_down() -> bool:
	return _knocked_down


## Advances the fixed-duration knockdown state machine.
##
## Every phase owns its own timer and animation:
##
## FALLING
##     Plays the non-looping fall animation.
##
## LYING
##     Holds the looping lying animation for exactly
##     knockdown_hold_time seconds.
##
## GETTING_UP
##     Plays the non-looping getup animation before
##     handing control back to the controller.
func _update_knockdown(delta: float) -> void:
	_knockdown_phase_timer += delta

	match _knockdown_phase:

		KnockdownPhase.FALLING:
			if _knockdown_phase_timer < knockdown_fall_time:
				return

			_knockdown_phase = KnockdownPhase.LYING
			_knockdown_phase_timer = 0.0

			if _animation:
				_animation.play_lying()

		KnockdownPhase.LYING:
			if _knockdown_phase_timer < knockdown_hold_time:
				return

			_knockdown_phase = KnockdownPhase.GETTING_UP
			_knockdown_phase_timer = 0.0

			if _animation:
				_animation.play_getup()

		KnockdownPhase.GETTING_UP:
			if _knockdown_phase_timer < knockdown_getup_time:
				return

			_knocked_down = false
			_knockdown_phase_timer = 0.0


## Character metric getters — same names as player.gd, so callers that duck
## type against the player (camera lock-on) work on an NPC unmodified.
func get_eye_height() -> float:
	return BodyMetrics.eye_height(body_height)


func get_shoulder_height() -> float:
	return BodyMetrics.shoulder_height(body_height)


func get_debug_type_label() -> String:
	return "NPC"


## Point this character's head turns toward, in world space. The body only
## aims the head; whether there is anything worth looking at is a decision,
## and decisions live in the controller.
func set_look_target(point: Vector3) -> void:
	_has_look_target = true
	_look_target_point = point


## Returns the head to neutral (facing the same way as the body).
func clear_look_target() -> void:
	_has_look_target = false


## Read by NPCAnimationComponent (and the perception debug panel) — same
## has_facing_target()-style pattern, a public getter instead of reaching
## into a private var across a node boundary.
func has_look_target() -> bool:
	return _has_look_target


func get_look_target_point() -> Vector3:
	return _look_target_point


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
	rotation.y = lerp_angle(rotation.y, target_angle, Smoothing.damp_factor(turn_smoothing, delta))
