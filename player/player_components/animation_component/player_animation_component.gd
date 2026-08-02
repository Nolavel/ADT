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

## 0 = idle, 1 = locomotion; smoothed separately from locomotion's own
## blend_position so idle<->moving doesn't snap.
var _moving_blend_amount: float = 0.0

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
	_anim_tree.set("parameters/locomotion/blend_position", locomotion_pos)

	var target_moving: float = 1.0 if _player.speed > IDLE_ENTER_SPEED else 0.0
	_moving_blend_amount = move_toward(_moving_blend_amount, target_moving, delta * MOVE_BLEND_SPEED)
	_anim_tree.set("parameters/moving_blend/blend_amount", _moving_blend_amount)


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


## Assembled entirely in code: Blend2(idle <-> locomotion), where locomotion
## is a BlendSpace1D(walk@0 .. run@1). Needs no hand-authored .tres/editor
## setup, easy to rebuild when clips change.
func _setup_animation_tree() -> void:
	var idle_node := AnimationNodeAnimation.new()
	idle_node.animation = "new4/idle"

	var walk_node := AnimationNodeAnimation.new()
	walk_node.animation = "new4/root-sneak-walk"

	var run_node := AnimationNodeAnimation.new()
	run_node.animation = "new4/root-sneak-run-s"

	var locomotion := AnimationNodeBlendSpace1D.new()
	locomotion.min_space = 0.0
	locomotion.max_space = 1.0
	locomotion.add_blend_point(walk_node, 0.0)
	locomotion.add_blend_point(run_node, 1.0)

	var moving_blend := AnimationNodeBlend2.new()

	var tree_root := AnimationNodeBlendTree.new()
	tree_root.add_node("idle", idle_node)
	tree_root.add_node("locomotion", locomotion)
	tree_root.add_node("moving_blend", moving_blend)
	tree_root.connect_node("moving_blend", 0, "idle")
	tree_root.connect_node("moving_blend", 1, "locomotion")
	tree_root.connect_node("output", 0, "moving_blend")

	_anim_tree = AnimationTree.new()
	_anim_tree.tree_root = tree_root
	_anim_tree.anim_player = _player.player_animation_player.get_path()
	add_child(_anim_tree)
	_anim_tree.active = true


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
