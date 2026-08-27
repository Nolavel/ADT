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
## PEACE and COMBAT share every directional point (forward/retreat/strafes/
## diagonals) verbatim — there is no sneak-strafe clip set in this project
## (only new4/strafe-l and new4/strafe-r, with no diagonal or backward
## variant at all), so both stances draw the same mixed-gait compromise from
## whatever exists in the libraries, not an oversight to "fix" later. Only
## the center (idle) point differs: PEACE holds LightIdle, a relaxed gait
## Sid never had before this stance work; COMBAT holds new4/sneak-idle, a
## collected low stance, which is exactly what it always looked like — it
## used to play unconditionally, on the wrong axis. That idle clip and the
## face-camera turn rate (see _apply_direct_movement() in player.gd) are,
## today, the only things telling the stances apart while moving.
const ANIM_PEACE_IDLE: StringName = &"LightIdle"
## Still not wired into the blend tree: no third speed tier exists past
## run_speed to justify a point beyond the outer radius — see
## _setup_animation_tree()'s comment.
const ANIM_PEACE_SPRINT: StringName = &"new4/run_067"
const ANIM_COMBAT_IDLE: StringName = &"new4/sneak-idle"
const ANIM_COMBAT_FORWARD: StringName = &"new4/sneak-walk"
const ANIM_COMBAT_RUN: StringName = &"new4/sneak-run-s"
const ANIM_COMBAT_STRAFE_LEFT: StringName = &"new4/strafe-l"
const ANIM_COMBAT_STRAFE_RIGHT: StringName = &"new4/strafe-r"
const ANIM_COMBAT_STRAFE_45L: StringName = &"LightStrafe45L"
const ANIM_COMBAT_STRAFE_45R: StringName = &"LightStrafe45R"
const ANIM_COMBAT_RETREAT: StringName = &"new3/legs_locomotion_run_backward_2"

## Punch clip, ShooterLib (new4/), not MeleeLib — MeleeLib is a sword/shield
## kit (Slash1-3, Heavy1-2, ShieldBash, Stab1, ThrowL/R) and has no unarmed
## punch clip at all. ShooterLib has three candidates (punch1, punchleft,
## punchright); punch1 is the one with a root- duplicate (root-punch1,
## unused per this file's own note on root- being an import artifact, not a
## distinct clip), matching the pattern of a primary single-strike clip in
## this rig — punchleft/punchright read as a combo pair instead. Confirm by
## eye against the actual swing the next time this runs.
const ANIM_COMBAT_PUNCH: StringName = &"new4/punch1"

## Weapon-gesture clips, all fired through the one weapon_oneshot node — see
## play_weapon_gesture() and _setup_animation_tree()'s own comment on why
## draw, holster and fire share a single node rather than getting one each.
##
## Three draw clips, not one: the gesture has to start where the item
## actually was, and EquipmentComponent decides that, not this file. A chest
## pocket reads as a hip-level grab, a thigh pocket as a reach down the leg,
## a back slot as a long gun coming off the shoulder. The caller passes the
## clip; this file only names them.
const ANIM_DRAW_CHEST: StringName = &"new4/equip-hip-fast"
const ANIM_DRAW_THIGH: StringName = &"new4/equip-thigh"
const ANIM_DRAW_SHOULDER: StringName = &"new4/equip-shoulder-r"

## Holster, bare MeleeLib (empty prefix). ShooterLib has six equip-* clips
## and nothing that puts a weapon away, so the choice is between these two
## and playing a draw backwards; a reversed clip usually reads wrong at the
## wrists. _back is the long-gun stow (the carbine lives on the back, see
## player.gd._holster_clip_for_slot()), _hip the pocket one. Confirm by eye
## — if either reads as a draw rather than a stow, the fallback is one
## constant.
const ANIM_HOLSTER: StringName = &"WeaponChange_hip"
const ANIM_HOLSTER_BACK: StringName = &"WeaponChange_back"

## Firing, ShooterLib (new4/). The light rifle clip (0.25s), not
## shoot-rifle-heavy (0.42s, and imported as LOOPING, which a one-shot
## gesture must never be) and not shoot-hip, which is fired from the waist.
const ANIM_SHOOT_RIFLE: StringName = &"new4/shoot-rifle-light"

## Magazine reload, ShooterLib (new4/). 1.62s, non-looping. ShooterLib also
## carries reload-barrelfed and reload-revolver — a different feed each,
## neither of them this weapon — and a -fps variant of every one, which is
## a first-person arms-only clip and wrong for a third-person body.
const ANIM_RELOAD_RIFLE: StringName = &"new4/reload-rifle"

## Picking something up, ShooterLib (new4/). Two clips, chosen by how high
## off the ground the thing is — see InteractComponent's own comment. A
## crouch-and-take for something lying in the dirt, a reach-out-and-press
## for something at body height.
const ANIM_PICKUP_GROUND: StringName = &"new4/pickup_item"
const ANIM_PICKUP_BODY: StringName = &"new4/interact-button"

## Locomotion while a long gun is in the hands — the rifle pack (new3/),
## used whole rather than sampled. Carrying a weapon changes how a body
## moves, and this is the only clip set in the project that can actually
## show it: eight directions, all looping, all 0.50s, which is exactly the
## geometry the peace/combat blend spaces already use.
##
## The same eight clips also exist under new2/ with identical names and
## lengths — one pack mounted twice. new3/ is the one named for it
## (rifle_locomotion_pack.res), so that is the one addressed.
##
## Two honest gaps:
##   * The pack has ONE forward clip, while the geometry splits forward into
##     a walk point (walk_blend_radius) and a run point. Both get it, so a
##     walk reads as a run with a weapon out. A playback-speed scale would
##     fix it; whether it is worth one is a judgement to make by eye.
##   * backward_left/backward_right exist in the pack and have no point to
##     go to — the existing geometry has no rear diagonals in any stance.
const ANIM_WEAPON_IDLE: StringName = &"new3/rifle_new_idle"
const ANIM_WEAPON_FORWARD: StringName = &"new3/rifle_locomotion_run_forward"
const ANIM_WEAPON_RETREAT: StringName = &"new3/rifle_locomotion_run_backward"
const ANIM_WEAPON_STRAFE_LEFT: StringName = &"new3/rifle_locomotion_run_left"
const ANIM_WEAPON_STRAFE_RIGHT: StringName = &"new3/rifle_locomotion_run_right"
const ANIM_WEAPON_STRAFE_45L: StringName = &"new3/rifle_locomotion_run_forward_left"
const ANIM_WEAPON_STRAFE_45R: StringName = &"new3/rifle_locomotion_run_forward_right"

## Death clip, ShooterLib (new4/). Non-looping — an AnimationNodeAnimation
## holds the last frame once a non-looping clip finishes, which is exactly
## the permanent collapsed pose play_death() needs.
## TODO(health): unverified without running the editor whether this
## specific import is actually flagged non-looping (see this file's own
## root- note on import quirks). If it loops, the death pose will visibly
## cycle instead of holding — confirm by eye and fix the import if so.
const ANIM_DEATH: StringName = &"new4/die2"

## Speed below which the character counts as standing still (gates the TPS
## idle head-look in update_head_look()).
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
## Radius at which the walk clip sits in the movement blend space (see
## _setup_animation_tree()'s comment on the walk/run split). The blend
## vector's length carries speed, so walk and run are separated by
## distance from the centre rather than by nesting a speed blend space
## inside the forward point. A feel value, not derived exactly from
## walk_speed/run_speed — tuned by eye, only needs to sit noticeably
## closer to the centre than run (radius 1.0).
@export var walk_blend_radius: float = 0.45

@export_group("Weapon")
## How long the crossfade into and out of the weapon locomotion blend space
## takes. Longer than stance_transition_time on purpose: the stance switch
## is a posture change, this one is a whole gait changing, and snapping
## between two full locomotion sets reads as a glitch. A feel value.
@export var weapon_transition_time: float = 0.3

@export_group("Head Look Limits")
## LookAtModifier3D's clamp angles and the smoothing time when the target
## leaves them. use_angle_limitation is on, but without explicit limits and
## duration the axis snaps the head instantly past the edge — hence these
## defaults.
@export var head_look_primary_limit_deg: float = 70.0
@export var head_look_secondary_limit_deg: float = 45.0
@export var head_look_duration: float = 0.25

@export_group("Death")
## Crossfade duration for the one-way switch to the death pose. A feel
## value, tuned by eye — same role as stance_transition_time above, just for
## a transition that only ever fires once.
@export var death_transition_time: float = 0.2

## Sprint progress 0..1 for the cursor UI — smoothed separately from the
## real speed so the icon doesn't jitter in step with stamina.
var sprint_blend: float = 0.0
var sprint_blend_speed: float = 4.0

## 0 = PEACE, 1 = COMBAT. Target is set only by _on_stance_changed(); eased
## toward every frame in update_animation_blend().
var _stance_blend_amount: float = 0.0
var _stance_blend_target: float = 0.0

## Latches true the moment play_death() fires — the switch is one-way and
## irreversible, so this also doubles as the guard against firing it twice.
var _is_dead: bool = false

var _anim_tree: AnimationTree

## The clip node the weapon one-shot plays. Held as a member because its
## `animation` is rewritten immediately before every request — one node, one
## gesture at a time, see play_weapon_gesture().
var _weapon_clip: AnimationNodeAnimation = null

## 0 = whatever the stance blend produced, 1 = the weapon locomotion blend
## space. Target is set only by set_weapon_locomotion(); eased toward every
## frame in update_animation_blend(), the same way _stance_blend_amount is.
var _weapon_blend_amount: float = 0.0
var _weapon_blend_target: float = 0.0

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

	## Both branches are now BlendSpace2D with identical geometry (see
	## _setup_animation_tree()), so the same movement vector drives whichever
	## one is currently mixed in — set both parameters unconditionally, same
	## as combat's was already set regardless of stance, so the crossfade has
	## a correct position on both sides mid-transition.
	var movement_blend_position: Vector2 = _player.get_movement_vector_relative_to_facing()
	_anim_tree.set("parameters/peace/blend_position", movement_blend_position)
	_anim_tree.set("parameters/combat/blend_position", movement_blend_position)
	_anim_tree.set("parameters/weapon/blend_position", movement_blend_position)

	_stance_blend_amount = move_toward(
		_stance_blend_amount, _stance_blend_target, delta / maxf(stance_transition_time, 0.001)
	)
	_anim_tree.set("parameters/stance_blend/blend_amount", _stance_blend_amount)

	_weapon_blend_amount = move_toward(
		_weapon_blend_amount, _weapon_blend_target, delta / maxf(weapon_transition_time, 0.001)
	)
	_anim_tree.set("parameters/weapon_blend/blend_amount", _weapon_blend_amount)


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


## Fires the punch one-shot layered over whichever stance branch is
## currently mixed in (see _setup_animation_tree()'s punch_oneshot comment).
## Re-firing while already active restarts it from the top — player.gd
## already gates this behind "not already punching", so in practice this
## only ever fires on a fresh press.
func play_punch() -> void:
	if not _anim_tree:
		return
	_anim_tree.set("parameters/punch_oneshot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## True while the punch one-shot is still playing — player.gd polls this to
## know when to hand movement back, instead of guessing the clip's length.
func is_punch_active() -> bool:
	if not _anim_tree:
		return false
	return bool(_anim_tree.get("parameters/punch_oneshot/active"))


## Fires one weapon gesture — a draw, a holster or a shot — layered over
## whichever stance branch is mixed in, the same way play_punch() is.
##
## The clip is set on the shared node immediately before the request rather
## than each gesture owning a node: the three are mutually exclusive things
## to do with the same hands, so a second one playing simultaneously would
## be a bug and not a feature. Re-firing while active restarts from the top;
## player.gd gates each caller behind its own "not already busy" check.
func play_weapon_gesture(clip: StringName) -> void:
	if not _anim_tree or _weapon_clip == null:
		return
	_weapon_clip.animation = clip
	_anim_tree.set("parameters/weapon_oneshot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## True while a weapon gesture is still playing — polled by player.gd to
## know when to hand movement back, same contract as is_punch_active().
func is_weapon_gesture_active() -> bool:
	if not _anim_tree:
		return false
	return bool(_anim_tree.get("parameters/weapon_oneshot/active"))


## Crossfades the whole locomotion into or out of the weapon blend space.
## Called from player.gd on the equipment's own drawn_changed, so the gait
## reflects what is in the hands rather than this file tracking it.
##
## Was set_drawn_idle(), which swapped one clip at the centre point and left
## the eight directional points empty-handed. The name changed with the
## behaviour on purpose: it is no longer the idle that differs.
func set_weapon_locomotion(carrying: bool) -> void:
	_weapon_blend_target = 1.0 if carrying else 0.0


## Fires the one-way, irreversible switch to the death pose. Deliberately
## NOT another AnimationNodeOneShot layered over locomotion the way the
## punch is: a OneShot's non-looping clip snaps back to whatever is
## underneath the instant it finishes — exactly the trap npc_base.gd's own
## header describes for its knockdown clips, and exactly wrong for a pose
## that has to hold forever. death_transition (AnimationNodeTransition, see
## _setup_animation_tree()) crossfades to a branch that never gets asked to
## fade back. Idempotent — a second call is a no-op, since is_dead() is
## already latched from the first.
func play_death() -> void:
	if _is_dead or not _anim_tree:
		return
	_is_dead = true
	_anim_tree.set("parameters/death_transition/transition_request", "death")


func is_dead() -> bool:
	return _is_dead


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


## Two branches, crossfaded by stance (see stance_blend below), each an
## AnimationNodeBlendSpace2D with identical geometry — a center (idle)
## point plus seven directional points, blended by movement direction
## relative to the character's own facing (player.gd's
## get_movement_vector_relative_to_facing(), not world space). The center
## point already IS idle, so each space's own geometry gives a smooth
## idle<->moving crossfade for free, no separate Blend2 idle/locomotion
## wrapper needed on either side. PEACE used to be shaped differently here
## (Blend2(idle, BlendSpace1D(walk, run)) by speed) — replaced because a 1D
## speed blend can't produce strafe: PEACE's body now always faces the
## camera while moving too (see _apply_direct_movement() in player.gd), so
## it needs the same direction-blended geometry COMBAT already has, or the
## legs would walk forward while the body strafes sideways under them.
##
## Forward is two points on the same axis rather than one: walk sits at
## walk_blend_radius (@export, Stance group), run at the outer edge (radius
## 1.0). This works because the blend vector's length already carries
## speed — get_movement_vector_relative_to_facing() divides by the
## stance's own get_current_max_speed() — so walk and run separate by
## distance from the centre. Nesting a BlendSpace1D inside the forward
## point would be the tidier structure, but it needs a nested parameter
## path that cannot be verified without running the project, and a wrong
## path fails silently (stuck at whatever default position, never actually
## blending).
##
## Retreat/strafe-left/strafe-right/two 45° diagonals stay at radius 1.0,
## i.e. run pace, even sideways: there is no walk-strafe clip in this
## project (only new4/strafe-l and new4/strafe-r, no diagonal or backward
## variant either) to put at a closer radius. Not an oversight — there is
## nothing else in the libraries to draw on.
##
## The two branches differ only in their center point (ANIM_PEACE_IDLE vs
## ANIM_COMBAT_IDLE) — every directional point, including run, is the same
## AnimationNodeAnimation clip reused on both sides; see the clip-constants
## comment above for why. ANIM_PEACE_SPRINT is still not wired to either
## space: there is no third speed tier past run_speed to justify a point
## beyond the outer radius — target_speed only ever settles on walk_speed
## or run_speed (see player.gd's _update_direct_move_target_speed()). Left
## for whoever adds one.
##
## auto_triangles (Godot's default for AnimationNodeBlendSpace2D, left on
## here) triangulates the point set automatically. idle/walk/run sit
## exactly collinear on the x=0 axis — unverified whether Godot's Delaunay
## triangulation handles three collinear points cleanly or drops/misweights
## the walk point; this project cannot run the editor from here to check.
## Watch for it (a step that visually skips straight from idle to run, or a
## triangulation warning in the output panel) the next time this runs.
##
## Both branches assembled entirely in code, no hand-authored .tres/editor
## setup — easy to rebuild when clips change.
func _setup_animation_tree() -> void:
	var tree_root := AnimationNodeBlendTree.new()

	var peace_idle := AnimationNodeAnimation.new()
	peace_idle.animation = ANIM_PEACE_IDLE
	var peace_forward := AnimationNodeAnimation.new()
	peace_forward.animation = ANIM_COMBAT_FORWARD
	var peace_run := AnimationNodeAnimation.new()
	peace_run.animation = ANIM_COMBAT_RUN
	var peace_retreat := AnimationNodeAnimation.new()
	peace_retreat.animation = ANIM_COMBAT_RETREAT
	var peace_strafe_left := AnimationNodeAnimation.new()
	peace_strafe_left.animation = ANIM_COMBAT_STRAFE_LEFT
	var peace_strafe_right := AnimationNodeAnimation.new()
	peace_strafe_right.animation = ANIM_COMBAT_STRAFE_RIGHT
	var peace_strafe_45l := AnimationNodeAnimation.new()
	peace_strafe_45l.animation = ANIM_COMBAT_STRAFE_45L
	var peace_strafe_45r := AnimationNodeAnimation.new()
	peace_strafe_45r.animation = ANIM_COMBAT_STRAFE_45R

	var peace := AnimationNodeBlendSpace2D.new()
	peace.min_space = Vector2(-1.0, -1.0)
	peace.max_space = Vector2(1.0, 1.0)
	peace.add_blend_point(peace_idle, Vector2(0.0, 0.0), -1, &"idle")
	peace.add_blend_point(peace_forward, Vector2(0.0, walk_blend_radius), -1, &"forward")
	peace.add_blend_point(peace_run, Vector2(0.0, 1.0), -1, &"run")
	peace.add_blend_point(peace_retreat, Vector2(0.0, -1.0), -1, &"retreat")
	peace.add_blend_point(peace_strafe_left, Vector2(-1.0, 0.0), -1, &"strafe_left")
	peace.add_blend_point(peace_strafe_right, Vector2(1.0, 0.0), -1, &"strafe_right")
	peace.add_blend_point(peace_strafe_45l, Vector2(-0.7071, 0.7071), -1, &"strafe_45l")
	peace.add_blend_point(peace_strafe_45r, Vector2(0.7071, 0.7071), -1, &"strafe_45r")
	tree_root.add_node("peace", peace)

	var combat_idle := AnimationNodeAnimation.new()
	combat_idle.animation = ANIM_COMBAT_IDLE
	var combat_forward := AnimationNodeAnimation.new()
	combat_forward.animation = ANIM_COMBAT_FORWARD
	var combat_run := AnimationNodeAnimation.new()
	combat_run.animation = ANIM_COMBAT_RUN
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
	combat.add_blend_point(combat_idle, Vector2(0.0, 0.0), -1, &"idle")
	combat.add_blend_point(combat_forward, Vector2(0.0, walk_blend_radius), -1, &"forward")
	combat.add_blend_point(combat_run, Vector2(0.0, 1.0), -1, &"run")
	combat.add_blend_point(combat_retreat, Vector2(0.0, -1.0), -1, &"retreat")
	combat.add_blend_point(combat_strafe_left, Vector2(-1.0, 0.0), -1, &"strafe_left")
	combat.add_blend_point(combat_strafe_right, Vector2(1.0, 0.0), -1, &"strafe_right")
	combat.add_blend_point(combat_strafe_45l, Vector2(-0.7071, 0.7071), -1, &"strafe_45l")
	combat.add_blend_point(combat_strafe_45r, Vector2(0.7071, 0.7071), -1, &"strafe_45r")
	tree_root.add_node("combat", combat)

	## Blend2 rather than AnimationNodeTransition: a plain eased blend_amount
	## is simpler than a named-state transition node for a two-way switch.
	var stance_blend := AnimationNodeBlend2.new()
	tree_root.add_node("stance_blend", stance_blend)
	tree_root.connect_node("stance_blend", 0, "peace")
	tree_root.connect_node("stance_blend", 1, "combat")

	## A THIRD blend space, same geometry as the other two, holding the
	## rifle pack — carrying a long gun changes the whole gait, not just
	## what the character does while standing still. It used to be the
	## standing-still half only: set_drawn_idle() substituted one clip into
	## the combat centre point and the eight directional points kept
	## playing empty-handed, so the character sprinted with a carbine as if
	## nothing were in its hands.
	##
	## Chained after stance_blend on a second Blend2 rather than replacing
	## the combat branch: what is in the hands and what stance the character
	## is in are two independent questions (a drawn torch is not COMBAT),
	## and this way the weapon layer sits on top of whichever the stance
	## crossfade produced instead of having to be folded into both.
	var weapon_idle := AnimationNodeAnimation.new()
	weapon_idle.animation = ANIM_WEAPON_IDLE
	var weapon_forward := AnimationNodeAnimation.new()
	weapon_forward.animation = ANIM_WEAPON_FORWARD
	## Deliberately the same clip as the walk point — the pack has one
	## forward clip, see ANIM_WEAPON_FORWARD's own comment.
	var weapon_run := AnimationNodeAnimation.new()
	weapon_run.animation = ANIM_WEAPON_FORWARD
	var weapon_retreat := AnimationNodeAnimation.new()
	weapon_retreat.animation = ANIM_WEAPON_RETREAT
	var weapon_strafe_left := AnimationNodeAnimation.new()
	weapon_strafe_left.animation = ANIM_WEAPON_STRAFE_LEFT
	var weapon_strafe_right := AnimationNodeAnimation.new()
	weapon_strafe_right.animation = ANIM_WEAPON_STRAFE_RIGHT
	var weapon_strafe_45l := AnimationNodeAnimation.new()
	weapon_strafe_45l.animation = ANIM_WEAPON_STRAFE_45L
	var weapon_strafe_45r := AnimationNodeAnimation.new()
	weapon_strafe_45r.animation = ANIM_WEAPON_STRAFE_45R

	var weapon := AnimationNodeBlendSpace2D.new()
	weapon.min_space = Vector2(-1.0, -1.0)
	weapon.max_space = Vector2(1.0, 1.0)
	weapon.add_blend_point(weapon_idle, Vector2(0.0, 0.0), -1, &"idle")
	weapon.add_blend_point(weapon_forward, Vector2(0.0, walk_blend_radius), -1, &"forward")
	weapon.add_blend_point(weapon_run, Vector2(0.0, 1.0), -1, &"run")
	weapon.add_blend_point(weapon_retreat, Vector2(0.0, -1.0), -1, &"retreat")
	weapon.add_blend_point(weapon_strafe_left, Vector2(-1.0, 0.0), -1, &"strafe_left")
	weapon.add_blend_point(weapon_strafe_right, Vector2(1.0, 0.0), -1, &"strafe_right")
	weapon.add_blend_point(weapon_strafe_45l, Vector2(-0.7071, 0.7071), -1, &"strafe_45l")
	weapon.add_blend_point(weapon_strafe_45r, Vector2(0.7071, 0.7071), -1, &"strafe_45r")
	tree_root.add_node("weapon", weapon)

	var weapon_blend := AnimationNodeBlend2.new()
	tree_root.add_node("weapon_blend", weapon_blend)
	tree_root.connect_node("weapon_blend", 0, "stance_blend")
	tree_root.connect_node("weapon_blend", 1, "weapon")

	## Punch layered on top of the stance crossfade via AnimationNodeOneShot,
	## not a second Blend2 or a state machine: layered blending (upper body
	## only) isn't built in this project yet (see the ADS report), so a punch
	## plays full-body, briefly overriding stance_blend entirely for its
	## duration — exactly what OneShot is for. player.gd locks movement for
	## the same duration (set_movement_enabled(false)), so there is no
	## locomotion for the punch to visually fight with underneath.
	var punch_clip := AnimationNodeAnimation.new()
	punch_clip.animation = ANIM_COMBAT_PUNCH
	var punch_oneshot := AnimationNodeOneShot.new()
	tree_root.add_node("punch_clip", punch_clip)
	tree_root.add_node("punch_oneshot", punch_oneshot)
	tree_root.connect_node("punch_oneshot", 0, "weapon_blend")
	tree_root.connect_node("punch_oneshot", 1, "punch_clip")

	## Weapon gestures — draw, holster, shot — on a SECOND OneShot chained
	## after the punch's rather than sharing it. Sharing would mean a shot
	## and a punch could never be told apart by is_*_active(), which is what
	## player.gd polls to know when to give movement back; two nodes keep
	## the two questions separate for one node's cost. Only one clip node
	## underneath, though: the three gestures are mutually exclusive uses of
	## the same hands, so _weapon_clip's animation is rewritten per request
	## (see play_weapon_gesture()) instead of three clip nodes idling.
	var weapon_clip := AnimationNodeAnimation.new()
	weapon_clip.animation = ANIM_DRAW_CHEST
	_weapon_clip = weapon_clip
	var weapon_oneshot := AnimationNodeOneShot.new()
	tree_root.add_node("weapon_clip", weapon_clip)
	tree_root.add_node("weapon_oneshot", weapon_oneshot)
	tree_root.connect_node("weapon_oneshot", 0, "punch_oneshot")
	tree_root.connect_node("weapon_oneshot", 1, "weapon_clip")

	## Death branch, an AnimationNodeTransition at the tree's root rather than
	## another AnimationNodeOneShot: a OneShot's non-looping clip snaps back
	## to whatever is underneath the instant it finishes playing — exactly
	## the trap npc_base.gd's own header describes for its knockdown clips,
	## and exactly wrong here, since the death pose has to hold forever, not
	## for a fixed duration. "alive" is the entire tree built above
	## (everything that used to feed output directly); "death" is a single
	## non-looping clip that holds its last frame once it finishes — see
	## ANIM_DEATH's own comment. The switch only ever runs one way: nothing
	## in this file ever requests "alive" again.
	## Inputs are set via input_count/set_input_name, NOT add_input(): that
	## method is inherited from AnimationNode but does nothing useful on an
	## AnimationNodeTransition, which sizes its inputs from input_count
	## instead — calling add_input() here builds a transition with zero real
	## inputs, connect_node() succeeds silently, and the node passes nothing
	## through to output (T-pose, no console error).
	var death_clip := AnimationNodeAnimation.new()
	death_clip.animation = ANIM_DEATH
	var death_transition := AnimationNodeTransition.new()
	death_transition.xfade_time = death_transition_time
	death_transition.input_count = 2
	death_transition.set_input_name(0, "alive")
	death_transition.set_input_name(1, "death")
	tree_root.add_node("death_clip", death_clip)
	tree_root.add_node("death_transition", death_transition)
	tree_root.connect_node("death_transition", 0, "weapon_oneshot")
	tree_root.connect_node("death_transition", 1, "death_clip")
	tree_root.connect_node("output", 0, "death_transition")

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

	## The weapon layer needs no equivalent read of live state: nothing can
	## be in the hands before EquipmentComponent has run, and when a save
	## restores a drawn item it re-emits drawn_changed, which reaches
	## set_weapon_locomotion() through player.gd like any other draw. Set
	## explicitly all the same, so a Blend2 built by hand is never left
	## relying on its own default.
	_anim_tree.set("parameters/weapon_blend/blend_amount", _weapon_blend_amount)

	## AnimationNodeTransition has no meaningful default state — without an
	## explicit request the node holds no input at all and the skeleton falls
	## back to its rest pose. stance_blend needs no equivalent: a Blend2's
	## default blend_amount of 0.0 is already a valid state.
	_anim_tree.set("parameters/death_transition/transition_request", "alive")


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
