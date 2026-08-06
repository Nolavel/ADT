# =============================================================================
# npc_animation_component.gd — NPCAnimationComponent.
#
# NPC counterpart to PlayerAnimationComponent (player/player_components/
# animation_component/), simplified to what an NPC actually needs: no
# stances, no combat branch, just an idle<->walk crossfade by speed_ratio
# and a procedural head look. Same contract shape as that file: the
# component reads the body ONLY through _npc (get_parent()), never writes
# into it beyond animation, and has no _process/_physics_process of its
# own — update_animation_blend()/update_head_look() are called explicitly
# by npc_base.gd._physics_process(), same reason PlayerAnimationComponent
# gives for its own explicit-call convention (scene-tree processing order
# is fragile and invisible to a reader; an explicit call site isn't).
#
# Head look is a LookAtModifier3D on the skeleton, not a rotated Head node
# — npc_base.gd used to rotate a placeholder Head cube by hand; that node
# is gone along with the capsule mesh (see the npc.tscn commit). The public
# contract does NOT change: set_look_target()/clear_look_target() on
# NPCBase are still the only way in — only the implementation moved here.
# This component reads that state through NPCBase's public
# has_look_target()/get_look_target_point() getters, the same
# has_facing_target()-style pattern the debug panel already reads through.
# =============================================================================
extends Node
class_name NPCAnimationComponent

## Locomotion clips — the same peaceful (PlayerState.Stance.PEACE) clips
## player_animation_component.gd uses for its own idle/forward points.
## ANIM_WALK is the only "moving" clip this project has (no separate
## walk-pace clip; the player's own forward point reuses it too, at a
## nearer blend radius purely to read as slower) — see that file's own
## comment on why. There is no NPC equivalent of a run tier: NPCBase's
## movement intent has no speed tier past walk_speed, so a 2-point
## BlendSpace1D (idle at 0, walk at 1) is enough.
const ANIM_IDLE: StringName = &"LightIdle"
const ANIM_WALK: StringName = &"new4/sneak-walk"

## Knockdown/getup clips, ShooterLib (new4/) — "knockdown" and "ko-getup",
## not the root-prefixed "root-knockdown"/"ko-root-getup" duplicates: this
## project's established convention (see player_animation_component.gd's own
## note on MeleeLib/ShooterLib root- clips) is that the root- prefix marks an
## unused import artifact, not a distinct root-motion variant. Unverified for
## these two specifically without running the editor — confirm by eye.
const ANIM_KNOCKDOWN: StringName = &"new4/knockdown"
const ANIM_GETUP: StringName = &"new4/ko-getup"

## Head bone name for the procedural LookAt — same bone player.gd's own
## rig uses.
const HEAD_BONE_NAME: StringName = &"Head"
## Distance the look-at marker sits at when idle/looking straight ahead, in
## metres — same value as PlayerAnimationComponent's own.
const HEAD_LOOK_DISTANCE: float = 5.0
## How fast the look-at marker chases its target point — same role and
## value as PlayerAnimationComponent's HEAD_LOOK_SMOOTH.
const HEAD_LOOK_SMOOTH: float = 8.0

@export_group("Locomotion")
## Smoothing.damp_factor() rate for the idle<->walk blend position. Not
## strictly required by the spec, but a hard snap between NPCBase's
## instantaneous speed_ratio steps (an idle controller pausing/resuming
## wander) would pop visibly with no smoothing at all.
@export var speed_blend_smoothing: float = 8.0

@export_group("Head Look Limits")
## Same defaults as player_animation_component.gd's own — a feel value
## carried over, not re-derived for NPC proportions.
@export var head_look_primary_limit_deg: float = 70.0
@export var head_look_secondary_limit_deg: float = 45.0
@export var head_look_duration: float = 0.25
## Fade rate of the modifier's influence, per second — same role as
## PlayerAnimationComponent's HEAD_LOOK_FADE_SPEED.
@export var head_look_fade_speed: float = 4.0

var _anim_tree: AnimationTree
var _blend_position: float = 0.0
## The oneshot's "shot" input — a single AnimationNodeAnimation whose
## .animation is swapped between ANIM_KNOCKDOWN and ANIM_GETUP and re-fired,
## rather than two separate oneshot nodes. See play_knockdown()/play_getup().
var _action_clip: AnimationNodeAnimation

var _skeleton: Skeleton3D
var _head_lookat: LookAtModifier3D
var _head_look_node: Node3D
var _head_look_influence: float = 0.0

@onready var _npc: NPCBase = get_parent()


func _ready() -> void:
	_setup_animation_tree()
	_setup_head_look()


## Blend position comes straight from NPCBase's own speed_ratio (already
## clamped 0..1 there) — smoothed here only to avoid a visible pop between
## instantaneous controller steps, see speed_blend_smoothing's own comment.
func update_animation_blend(delta: float) -> void:
	if not _anim_tree:
		return
	_blend_position = lerp(
		_blend_position, _npc.get_move_speed_ratio(), Smoothing.damp_factor(speed_blend_smoothing, delta)
	)
	_anim_tree.set("parameters/locomotion/blend_position", _blend_position)


## Aims the LookAtModifier3D at NPCBase's current look target (whatever
## set_look_target() was last called with), or eases back to a straight-
## ahead neutral point when there is none — same influence-fade approach
## as PlayerAnimationComponent.update_head_look(), see that file's own
## comment on why influence, not target position, is what fades.
func update_head_look(delta: float) -> void:
	if _head_lookat == null or _head_look_node == null:
		return

	var want := _npc.has_look_target()
	var target_pos: Vector3

	if want:
		target_pos = _npc.get_look_target_point()
	else:
		target_pos = (
			_npc.global_position + _npc.get_facing_direction() * HEAD_LOOK_DISTANCE
			+ Vector3.UP * _npc.get_eye_height()
		)

	if want and _head_look_influence <= 0.001:
		## First frame it turns on — snap immediately, no windup from
		## wherever the marker was left last time.
		_head_look_node.global_position = target_pos
	else:
		_head_look_node.global_position = _head_look_node.global_position.lerp(
			target_pos, delta * HEAD_LOOK_SMOOTH
		)

	_head_look_influence = move_toward(
		_head_look_influence, 1.0 if want else 0.0, delta * head_look_fade_speed
	)
	_head_lookat.influence = _head_look_influence
	_head_lookat.active = _head_look_influence > 0.001


## Fires the knockdown clip via the shared action_oneshot layer — see
## _action_clip's own comment. Called by NPCBase.take_hit().
func play_knockdown() -> void:
	if not _anim_tree:
		return
	_action_clip.animation = ANIM_KNOCKDOWN
	_anim_tree.set("parameters/action_oneshot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## Fires the getup clip the same way — called by NPCBase once its knockdown
## timer elapses.
func play_getup() -> void:
	if not _anim_tree:
		return
	_action_clip.animation = ANIM_GETUP
	_anim_tree.set("parameters/action_oneshot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## True while the knockdown/getup oneshot is still playing — NPCBase polls
## this after firing getup to know when to hand the controller back, instead
## of guessing the clip's length.
func is_action_playing() -> bool:
	if not _anim_tree:
		return false
	return bool(_anim_tree.get("parameters/action_oneshot/active"))


## Locomotion (idle<->walk BlendSpace1D, see ANIM_WALK's own comment on why
## there is no third/run point) with knockdown/getup layered on top via
## AnimationNodeOneShot, same technique and reason as
## player_animation_component.gd's punch_oneshot: this project has no
## upper-body-only blending yet, so a knocked-down NPC briefly plays a
## full-body clip instead of locomotion, which is fine because NPCBase stops
## driving movement for the same duration (see its is_knocked_down()).
## Assembled in code, same convention as player_animation_component.gd's
## tree (no hand-authored .tres), easy to rebuild if clips change.
func _setup_animation_tree() -> void:
	var anim_player := _npc.get_node_or_null("player_base_mesh/AnimationPlayer") as AnimationPlayer
	if anim_player == null:
		push_warning("[NPCAnimationComponent] AnimationPlayer not found under player_base_mesh — animation disabled")
		return

	var idle := AnimationNodeAnimation.new()
	idle.animation = ANIM_IDLE
	var walk := AnimationNodeAnimation.new()
	walk.animation = ANIM_WALK

	var locomotion := AnimationNodeBlendSpace1D.new()
	locomotion.min_space = 0.0
	locomotion.max_space = 1.0
	locomotion.add_blend_point(idle, 0.0)
	locomotion.add_blend_point(walk, 1.0)

	## Placeholder clip at setup time — never played until play_knockdown()/
	## play_getup() assigns and fires it.
	_action_clip = AnimationNodeAnimation.new()
	_action_clip.animation = ANIM_KNOCKDOWN
	var action_oneshot := AnimationNodeOneShot.new()

	var tree_root := AnimationNodeBlendTree.new()
	tree_root.add_node("locomotion", locomotion)
	tree_root.add_node("action_clip", _action_clip)
	tree_root.add_node("action_oneshot", action_oneshot)
	tree_root.connect_node("action_oneshot", 0, "locomotion")
	tree_root.connect_node("action_oneshot", 1, "action_clip")
	tree_root.connect_node("output", 0, "action_oneshot")

	_anim_tree = AnimationTree.new()
	_anim_tree.tree_root = tree_root
	_anim_tree.anim_player = anim_player.get_path()
	add_child(_anim_tree)
	_anim_tree.active = true


## Same lookup convention as player_animation_component.gd's own
## _setup_head_look(): named lookup first ("LookAt", which the copied rig
## does carry — see the npc.tscn commit), then a type-scan fallback with a
## warning as the safety net if a future re-copy ever loses that name.
func _setup_head_look() -> void:
	_skeleton = _npc.get_node_or_null(
		"player_base_mesh/GeneralSkeleton/RetargetModifier3D/OriginalSkeleton"
	) as Skeleton3D
	if _skeleton == null:
		push_warning("[NPCAnimationComponent] Skeleton3D not found — head look disabled")
		return

	_head_lookat = _skeleton.get_node_or_null("LookAt") as LookAtModifier3D
	if _head_lookat == null:
		for child in _skeleton.get_children():
			if child is LookAtModifier3D:
				_head_lookat = child
				break
	if _head_lookat == null:
		push_warning("[NPCAnimationComponent] LookAtModifier3D not found under Skeleton3D — head look disabled")
		return

	_head_look_node = Node3D.new()
	_head_look_node.name = "HeadLookTarget"
	add_child(_head_look_node)
	_head_look_node.global_position = (
		_npc.global_position + _npc.get_facing_direction() * HEAD_LOOK_DISTANCE
		+ Vector3.UP * _npc.get_eye_height()
	)

	_head_lookat.bone_name = HEAD_BONE_NAME
	_head_lookat.use_angle_limitation = true
	_head_lookat.primary_limit_angle = head_look_primary_limit_deg
	_head_lookat.secondary_limit_angle = head_look_secondary_limit_deg
	_head_lookat.duration = head_look_duration
	_head_lookat.target_node = _head_lookat.get_path_to(_head_look_node)
	_head_lookat.active = false
	_head_lookat.influence = 0.0
