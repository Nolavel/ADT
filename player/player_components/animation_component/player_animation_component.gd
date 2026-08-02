# =============================================================================
# player_animation_component.gd — PlayerAnimationComponent.
#
# Extracted out of player.gd (was 637 lines): everything animation-side —
# the AnimationNodeBlendTree assembly, walk/run blending, sprint blend for
# the cursor UI, and the procedural Head LookAt — has nothing to do with
# physics/rotation, but used to live tangled up with them in one file.
# Contract: the component reads player state ONLY through the _player
# reference (get_parent(), same pattern as InteractComponent/
# StaminaComponent) and never writes into it. The only way out is getters
# (get_sprint_blend(), get_head_yaw_relative_deg(), ...), which player.gd
# re-exports as thin wrappers for outside callers (dynamic_cursor_ui.gd and
# similar).
# The component deliberately has no _process/_physics_process of its own:
# update_sprint_blend()/update_animation_blend()/update_head_look() are
# called explicitly by player.gd._physics_process(), in a specific order
# (sprint blend before the stamina check; animation blend and head look
# after _update_speed() has settled this frame's real speed). Relying on
# scene-tree processing order instead of an explicit call would make that
# ordering fragile and invisible to a collaborator reading either file.
# =============================================================================
extends Node
class_name PlayerAnimationComponent

## Animation clip names. MeleeLib is mounted with an empty prefix
## (player.tscn: libraries/ = ExtResource("5_ftrmt")), so its clips are
## addressed bare; ShooterLib is mounted as new4/. The root- prefixed
## duplicates that exist for almost every MeleeLib clip (and for
## ShooterLib's sneak-* clips) are not used: verified in the editor that
## their content matches the unprefixed versions — root- is an import
## artifact, not a distinct root-motion variant.
##
## PEACE gets MeleeLib's Light* set: a relaxed gait Sid never had before
## this, since the AnimationTree used to run these three sneak-* clips
## unconditionally regardless of stance. COMBAT gets those sneak-* clips
## instead — a collected, low stance, which is exactly what they always
## looked like; they just used to be playing on the wrong axis. COMBAT's
## strafes and diagonals are drawn from Light* rather than a crouched
## equivalent because no sneak-strafe clips exist in this project (only
## new4/strafe-l and new4/strafe-r, with no diagonal or backward variant at
## all) — mixing gait manners in the strafe is a deliberate compromise
## given what's actually in the libraries, not an oversight to "fix" later.
const ANIM_PEACE_IDLE: StringName = &"LightIdle"
const ANIM_PEACE_WALK: StringName = &"LightWalking"
const ANIM_PEACE_RUN: StringName = &"LightRunning"
## Not currently wired into the blend tree — see _setup_animation_tree()'s
## comment on why sprint doesn't fit the existing speed-blend cleanly.
const ANIM_PEACE_SPRINT: StringName = &"Sprint"
const ANIM_COMBAT_IDLE: StringName = &"new4/sneak-idle"
const ANIM_COMBAT_FORWARD: StringName = &"new4/sneak-walk"
## Not currently wired into the blend tree — see _setup_animation_tree()'s
## comment on why COMBAT's forward point doesn't speed-blend to a run clip.
const ANIM_COMBAT_RUN: StringName = &"new4/sneak-run-s"
const ANIM_COMBAT_STRAFE_LEFT: StringName = &"LightStrafeLwalk"
const ANIM_COMBAT_STRAFE_RIGHT: StringName = &"LightStrafeRwalk"
const ANIM_COMBAT_STRAFE_45L: StringName = &"LightStrafe45L"
const ANIM_COMBAT_STRAFE_45R: StringName = &"LightStrafe45R"
const ANIM_COMBAT_RETREAT: StringName = &"Retreat"

## How fast the walk<->run blend space chases the real speed, and the speed
## below which the character counts as standing still.
const MOVE_BLEND_SPEED: float = 6.0
const IDLE_ENTER_SPEED: float = 0.15

## Head bone name and smoothing parameters for the procedural LookAt.
const HEAD_BONE_NAME: StringName = &"Head"
## How fast the look-at marker chases its target point.
const HEAD_LOOK_SMOOTH: float = 8.0
## Distance the look-at point is held at, in meters.
const HEAD_LOOK_DISTANCE: float = 5.0
## Fade rate of the modifier's influence, per second.
const HEAD_LOOK_FADE_SPEED: float = 4.0

@export_group("Stance")
## How long the crossfade between the PEACE and COMBAT branches takes. A
## feel value, tuned by eye — start at 0.2s.
@export var stance_transition_time: float = 0.2

@export_group("Head Look Limits")
## LookAtModifier3D's clamp angles and the smoothing time when the target
## leaves them. use_angle_limitation is on, but without explicit limits and
## duration the axis snaps the head instantly past the edge — hence these
## defaults.
@export var head_look_primary_limit_deg: float = 70.0
@export var head_look_secondary_limit_deg: float = 45.0
@export var head_look_duration: float = 0.25

## Sprint progress 0..1 for the cursor UI — smoothed separately from the
## real speed so the icon doesn't jitter in step with stamina.
var sprint_blend: float = 0.0
var sprint_blend_speed: float = 4.0

## 0 = idle, 1 = locomotion, within the PEACE branch only; smoothed
## separately from peace_locomotion's own blend_position so idle<->moving
## doesn't snap. COMBAT has no equivalent — its blend space's own center
## point already crossfades idle<->moving through blend_position magnitude.
var _peace_moving_blend_amount: float = 0.0

## 0 = PEACE, 1 = COMBAT. Target is set only by _on_stance_changed(); eased
## toward every frame in update_animation_blend(), same shape as
## _peace_moving_blend_amount above.
var _stance_blend_amount: float = 0.0
var _stance_blend_target: float = 0.0

var _anim_tree: AnimationTree

var _skeleton: Skeleton3D
var _head_lookat: LookAtModifier3D
var _head_look_node: Node3D
## Current modifier influence, 0..1. Fading happens through influence, not
## by dragging the target back to neutral: influence doesn't depend on
## distance to the target, whereas the earlier approach took longer to
## settle the further the character had been looking.
var _head_look_influence: float = 0.0

## World-space look point for ISOMETRIC. Written from outside via
## set_head_look_point(); the component itself knows nothing about the
## camera and casts no rays.
var _look_point: Vector3 = Vector3.ZERO
var _look_point_valid: bool = false

@onready var _player: CharacterBody3D = get_parent()


func _ready() -> void:
	_setup_animation_tree()
	_setup_head_look()
	PlayerState.stance_changed.connect(_on_stance_changed)


## The blend space position comes from the REAL speed (already smoothed
## through move_toward/accel_time in player.gd._update_speed()), not from
## is_running_mode — so the animation can never physically outrun the
## character's actual speed, and stamina running out "settles" visually
## without a clip jump.
func update_animation_blend(delta: float) -> void:
	if not _anim_tree:
		return

	var locomotion_pos: float = 0.0
	if _player.run_speed > _player.walk_speed:
		locomotion_pos = clamp(
			(_player.speed - _player.walk_speed) / (_player.run_speed - _player.walk_speed),
			0.0,
			1.0
		)
	_anim_tree.set("parameters/peace_locomotion/blend_position", locomotion_pos)

	var target_moving: float = 1.0 if _player.speed > IDLE_ENTER_SPEED else 0.0
	_peace_moving_blend_amount = move_toward(
		_peace_moving_blend_amount, target_moving, delta * MOVE_BLEND_SPEED
	)
	_anim_tree.set("parameters/peace_moving_blend/blend_amount", _peace_moving_blend_amount)

	_anim_tree.set(
		"parameters/combat/blend_position", _player.get_movement_vector_relative_to_facing()
	)

	_stance_blend_amount = move_toward(
		_stance_blend_amount, _stance_blend_target, delta / maxf(stance_transition_time, 0.001)
	)
	_anim_tree.set("parameters/stance_blend/blend_amount", _stance_blend_amount)


func update_sprint_blend(delta: float) -> void:
	var target_blend: float = 1.0 if _player.is_running_mode else 0.0
	sprint_blend = lerp(sprint_blend, target_blend, sprint_blend_speed * delta)


## In TPS idle the head smoothly follows the camera direction. Disabled
## while moving — animation clips drive the head then. Disabled in
## ISO/MENU/Hover so it doesn't fight click-to-move or cutscenes.
func update_head_look(delta: float) -> void:
	if _head_lookat == null or _head_look_node == null:
		return

	var want: bool = false
	var target_pos: Vector3 = Vector3.ZERO

	if PlayerState.mode == PlayerState.Mode.ON_FOOT:
		match PlayerState.view_mode:
			PlayerState.ViewMode.TPS:
				if _player.speed < IDLE_ENTER_SPEED:
					## +PI is required. The camera looks down −Z, while this
					## project's visual "forward" is +Z (see
					## get_facing_direction's comment in player.gd). Without
					## +PI the head looks INTO the lens instead of where the
					## player is looking.
					var cam_angle: float = _player.get_camera_yaw() + PI
					var cam_dir := Vector3(sin(cam_angle), 0.0, cos(cam_angle))
					target_pos = (
						_player.global_position + cam_dir * HEAD_LOOK_DISTANCE
						+ Vector3.UP * _player.get_eye_height()
					)
					want = true
			_:
				if _look_point_valid:
					## The point comes in at floor level — raise it to chest
					## height, or the character stares at its own feet.
					target_pos = _look_point + Vector3.UP * _player.get_chest_height()
					want = true

	if not want:
		target_pos = (
			_player.global_position + _player.get_facing_direction() * HEAD_LOOK_DISTANCE
			+ Vector3.UP * _player.get_eye_height()
		)

	if want and _head_look_influence <= 0.001:
		## First frame it turns on — snap the marker immediately, no windup
		## from wherever it was left last time.
		_head_look_node.global_position = target_pos
	else:
		_head_look_node.global_position = _head_look_node.global_position.lerp(
			target_pos, delta * HEAD_LOOK_SMOOTH
		)

	_head_look_influence = move_toward(
		_head_look_influence, 1.0 if want else 0.0, delta * HEAD_LOOK_FADE_SPEED
	)
	_head_lookat.influence = _head_look_influence
	_head_lookat.active = _head_look_influence > 0.001


func get_sprint_blend() -> float:
	return sprint_blend


func set_head_look_point(world_pos: Vector3) -> void:
	_look_point = world_pos
	_look_point_valid = true


func clear_head_look_point() -> void:
	_look_point_valid = false


## Head yaw relative to the body, in degrees. Derived from the direction to
## the current look-at target (_head_look_node), not from the bone's actual
## post-clamp pose from LookAtModifier3D — cheaper and needs no skeleton
## pose read, at the cost of slight inaccuracy right at the limit. That's
## precise enough for a "should the body turn now" decision. Returns 0
## while head look is inactive (influence ~0) — the angle is meaningless then.
func get_head_yaw_relative_deg() -> float:
	if _head_lookat == null or _head_look_node == null or _head_look_influence <= 0.001:
		return 0.0

	var to_target: Vector3 = _head_look_node.global_position - _player.global_position
	to_target.y = 0.0
	if to_target.length() < 0.001:
		return 0.0

	var look_yaw: float = atan2(to_target.x, to_target.z)
	var relative_yaw: float = wrapf(look_yaw - _player.rotation.y, -PI, PI)
	return rad_to_deg(relative_yaw)


## Sets the crossfade target only — update_animation_blend() eases toward
## it every frame. This is the one place PlayerState.stance is read at all:
## on change, via the signal, not polled every frame.
func _on_stance_changed(_old_stance: PlayerState.Stance, new_stance: PlayerState.Stance) -> void:
	_stance_blend_target = 1.0 if new_stance == PlayerState.Stance.COMBAT else 0.0


## Two branches, crossfaded by stance (see stance_blend below), each with
## its own locomotion:
##
## PEACE: unchanged in shape from before this stance work — Blend2(idle <->
## locomotion), locomotion a BlendSpace1D(walk@0 .. run@1) by speed. Sprint
## (ANIM_PEACE_SPRINT) is defined but not mixed in: this project's movement
## model has no third speed tier to drive a genuine sprint blend point with
## — target_speed only ever settles on walk_speed or run_speed (see
## player.gd's _update_direct_move_target_speed()) — so there is nothing to
## blend on past run_speed short of inventing a speed tier that doesn't
## otherwise exist. Left for whoever adds one.
##
## COMBAT: a single AnimationNodeBlendSpace2D, blended by movement direction
## relative to the character's own facing (player.gd's get_movement_vector_
## relative_to_facing(), not world space) instead of an idle/moving
## wrapper — the center point below already IS idle, so the space's own
## geometry gives a smooth idle<->moving crossfade for free, the same job
## PEACE's moving_blend does by hand. ANIM_COMBAT_RUN is defined but not
## used as a separate point: nothing in this feature's spec said how a
## speed-blended run should compose with a direction-blended 2D space (only
## "forward: new4/sneak-walk"), and Godot's parameter path for a blend
## space nested inside another one isn't something verifiable without
## running the project — guessed wrong, it fails silently (stuck at
## whatever default position, never actually blending). Forward plays
## ANIM_COMBAT_FORWARD at any speed until this is resolved on purpose.
##
## Both branches assembled entirely in code, no hand-authored .tres/editor
## setup — easy to rebuild when clips change.
func _setup_animation_tree() -> void:
	var tree_root := AnimationNodeBlendTree.new()

	var peace_idle := AnimationNodeAnimation.new()
	peace_idle.animation = ANIM_PEACE_IDLE
	var peace_walk := AnimationNodeAnimation.new()
	peace_walk.animation = ANIM_PEACE_WALK
	var peace_run := AnimationNodeAnimation.new()
	peace_run.animation = ANIM_PEACE_RUN

	var peace_locomotion := AnimationNodeBlendSpace1D.new()
	peace_locomotion.min_space = 0.0
	peace_locomotion.max_space = 1.0
	peace_locomotion.add_blend_point(peace_walk, 0.0)
	peace_locomotion.add_blend_point(peace_run, 1.0)

	var peace_moving_blend := AnimationNodeBlend2.new()

	tree_root.add_node("peace_idle", peace_idle)
	tree_root.add_node("peace_locomotion", peace_locomotion)
	tree_root.add_node("peace_moving_blend", peace_moving_blend)
	tree_root.connect_node("peace_moving_blend", 0, "peace_idle")
	tree_root.connect_node("peace_moving_blend", 1, "peace_locomotion")

	var combat_idle := AnimationNodeAnimation.new()
	combat_idle.animation = ANIM_COMBAT_IDLE
	var combat_forward := AnimationNodeAnimation.new()
	combat_forward.animation = ANIM_COMBAT_FORWARD
	var combat_retreat := AnimationNodeAnimation.new()
	combat_retreat.animation = ANIM_COMBAT_RETREAT
	var combat_strafe_left := AnimationNodeAnimation.new()
	combat_strafe_left.animation = ANIM_COMBAT_STRAFE_LEFT
	var combat_strafe_right := AnimationNodeAnimation.new()
	combat_strafe_right.animation = ANIM_COMBAT_STRAFE_RIGHT
	var combat_strafe_45l := AnimationNodeAnimation.new()
	combat_strafe_45l.animation = ANIM_COMBAT_STRAFE_45L
	var combat_strafe_45r := AnimationNodeAnimation.new()
	combat_strafe_45r.animation = ANIM_COMBAT_STRAFE_45R

	var combat := AnimationNodeBlendSpace2D.new()
	combat.min_space = Vector2(-1.0, -1.0)
	combat.max_space = Vector2(1.0, 1.0)
	combat.add_blend_point(combat_idle, Vector2(0.0, 0.0))
	combat.add_blend_point(combat_forward, Vector2(0.0, 1.0))
	combat.add_blend_point(combat_retreat, Vector2(0.0, -1.0))
	combat.add_blend_point(combat_strafe_left, Vector2(-1.0, 0.0))
	combat.add_blend_point(combat_strafe_right, Vector2(1.0, 0.0))
	combat.add_blend_point(combat_strafe_45l, Vector2(-0.7071, 0.7071))
	combat.add_blend_point(combat_strafe_45r, Vector2(0.7071, 0.7071))
	tree_root.add_node("combat", combat)

	## Blend2 rather than AnimationNodeTransition: a plain eased
	## blend_amount is simpler than a named-state transition node for a
	## two-way switch, and keeps this file to one blending idiom instead of
	## two (peace_moving_blend above is the same shape).
	var stance_blend := AnimationNodeBlend2.new()
	tree_root.add_node("stance_blend", stance_blend)
	tree_root.connect_node("stance_blend", 0, "peace_moving_blend")
	tree_root.connect_node("stance_blend", 1, "combat")
	tree_root.connect_node("output", 0, "stance_blend")

	_anim_tree = AnimationTree.new()
	_anim_tree.tree_root = tree_root
	_anim_tree.anim_player = _player.player_animation_player.get_path()
	add_child(_anim_tree)
	_anim_tree.active = true

	## Start the crossfade already settled on the current stance instead of
	## always at PEACE=0 and letting the first frame's ease reveal it — the
	## component can be set up after PlayerState already left its default.
	_stance_blend_amount = 1.0 if PlayerState.stance == PlayerState.Stance.COMBAT else 0.0
	_stance_blend_target = _stance_blend_amount
	_anim_tree.set("parameters/stance_blend/blend_amount", _stance_blend_amount)


func _setup_head_look() -> void:
	_skeleton = _player.get_node_or_null(
		"player_base_mesh/GeneralSkeleton/RetargetModifier3D/OriginalSkeleton"
	) as Skeleton3D
	if _skeleton == null:
		push_warning("[PlayerAnimationComponent] Skeleton3D не найден — head look отключён")
		return

	## Named lookup first, then a type-scan fallback with a warning — the
	## node in the current player.tscn isn't actually named "LookAt" (it
	## kept its default "LookAtModifier3D" name), so in practice it's the
	## fallback that fires today. Both paths are kept on purpose: the name
	## is the fast path for later (rename the node and it works with no
	## code change), the scan is the safety net that must not fail silently.
	_head_lookat = _skeleton.get_node_or_null("LookAt") as LookAtModifier3D
	if _head_lookat == null:
		push_warning(
			"[PlayerAnimationComponent] LookAtModifier3D не найден по имени \"LookAt\" "
			+ "под Skeleton3D — ищем по типу среди детей"
		)
		for child in _skeleton.get_children():
			if child is LookAtModifier3D:
				_head_lookat = child
				break
	if _head_lookat == null:
		push_warning(
			"[PlayerAnimationComponent] LookAtModifier3D не найден под Skeleton3D — head look отключён"
		)
		return

	## Target marker. Created before handing its path to the modifier.
	_head_look_node = Node3D.new()
	_head_look_node.name = "HeadLookTarget"
	add_child(_head_look_node)
	_head_look_node.global_position = (
		_player.global_position + _player.get_facing_direction() * HEAD_LOOK_DISTANCE
		+ Vector3.UP * _player.get_eye_height()
	)

	_head_lookat.bone_name = HEAD_BONE_NAME
	## The property is spelled use_angle_limitation. use_angle_limits does
	## not exist; assigning to it is a runtime error.
	_head_lookat.use_angle_limitation = true
	## Limits and duration must be set explicitly: use_angle_limitation
	## alone turns clamping on, but with no limits it clamps to 0, and with
	## no duration (defaults to 0) leaving the limit instantly snaps the
	## axis instead of easing it.
	_head_lookat.primary_limit_angle = head_look_primary_limit_deg
	_head_lookat.secondary_limit_angle = head_look_secondary_limit_deg
	_head_lookat.duration = head_look_duration
	_head_lookat.target_node = _head_lookat.get_path_to(_head_look_node)
	## active, not enabled. SkeletonModifier3D has no enabled property.
	_head_lookat.active = false
	_head_lookat.influence = 0.0

	## If the head looks sideways or down with a correct target, the cause
	## isn't the math but forward_axis: it defaults to +Z, while imported
	## rigs often have the head's "forward" along −Z or +Y. Fix it in the
	## inspector.
