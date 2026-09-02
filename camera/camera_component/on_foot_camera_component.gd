# =============================================================================
# on_foot_camera_component.gd
# Camera component for PlayerState.Mode.ON_FOOT.
#
# ONE CAMERA. The isometric orbit is gone (2026-09-02) — the class, its
# debug overlay, the zoom slider that chained the two views together,
# click-to-move and the whole Q/E-orbit / P-follow layer that had already
# been dead for weeks. `docs/tps_camera_single_mode_audit.md` is the survey
# that made the removal safe; read it before reviving any of it from git.
#
# WHAT `PlayerState.ViewMode` MEANS NOW. Both values are third person and
# differ only in FRAMING — where the character sits in the picture, not
# where the camera sits in the world:
#
#   TPS       the character centred behind the shoulder, as before
#   TPS_WIDE  the same camera at the same distance, with the character
#             pushed toward the lower-left of frame
#
# That is a lens shift (Camera3D.h_offset/v_offset), not a move: distance,
# pitch, yaw, occlusion and every follow rate are identical between them.
# Nothing outside this file needs to branch on the view any more, and the
# systems that used to (movement, mouse capture, head-look, the cursor) had
# their branches removed in the same commit rather than left keyed on a
# distinction that no longer exists.
#
# The component isn't a Camera3D itself — it gets a reference to the real
# camera (camera) and the target (target) from its host, and writes
# directly into camera.global_position/global_rotation while active.
# =============================================================================
extends Node
class_name OnFootCameraComponent

## Not proportional to BODY_HEIGHT on purpose — camera distance is taste, not
## anatomy. Proportional to the old 2.6 @ 2.32m body would be ~2.02; 2.2 is
## visually tighter framing for this camera family.
const TPS_DISTANCE: float = 2.2
## Vertical look is deliberately slower than horizontal — the traditional
## "mouse Y feels heavier than mouse X" convention for TPS/FPS cameras.
const TPS_PITCH_SENSITIVITY_RATIO: float = 0.7

## Position follow rate. Steady-state lag behind a target moving at constant
## speed is roughly speed / this value.
const TPS_FOLLOW_SPEED: float = 16.0

## Rotation follow rate. Deliberately much faster than TPS_FOLLOW_SPEED:
## position lag reads as a spring, rotation lag reads as input lag. Mouse
## look must feel direct.
const TPS_LOOK_SMOOTHING: float = 30.0

## Extra camera distance at full run speed, on top of TPS_DISTANCE. Explicit
## and tunable — the previous pull-back was an accidental by-product of the
## follow-lag, not a setting.
const TPS_SPRINT_PULLBACK: float = 0.4
## How fast the pull-back follows a change of speed. Lower than the follow
## rate on purpose, so it eases in instead of snapping when the run starts.
const TPS_PULLBACK_SMOOTHING: float = 3.0

## How far ahead of the character the camera pivot leads at full run speed.
## Reads as "I see where I'm going" instead of "I see my own back".
const TPS_LEAD_DISTANCE: float = 0.6
## Lead easing rate. Slower than the look rate on purpose — the lead should
## drift in, not snap when the character starts moving.
const TPS_LEAD_SMOOTHING: float = 2.5

## How fast the camera dollies to (and back from) a lock-on distance
## override. A first guess, not tuned by ear/eye yet — the dolly needs a
## running lock-on target to actually see.
const TPS_LOCK_DISTANCE_SMOOTHING: float = 4.0

## Camera distance while aiming. Closer than TPS_DISTANCE — the shot needs a
## tighter frame than movement does.
const TPS_AIM_DISTANCE: float = 1.5
## How fast the camera dollies in and out of the aim distance.
const TPS_AIM_DISTANCE_SMOOTHING: float = 8.0

## Used only if `target` doesn't expose character-metric getters (see
## _target_metric_height()) — a safe non-zero default instead of silently
## pivoting/casting at ground level.
const TPS_PIVOT_HEIGHT_FALLBACK: float = 1.45
const TPS_OCCLUSION_HEIGHT_FALLBACK: float = 1.5

## Frustum-vs-translation split for the shoulder offset — picked visually, not
## derived. Frustum offset keeps the look axis centered on screen (needed for
## aiming); translation keeps some camera-plane parallax.
const TPS_SHOULDER_FRUSTUM_RATIO: float = 0.6
const TPS_SHOULDER_TRANSLATION_RATIO: float = 0.4
## Sign depends on which way `right` points on screen — verify by running the game.
const TPS_SHOULDER_H_OFFSET_SIGN: float = 1.0

## How fast camera.h_offset / v_offset chase their target. Shared by the
## shoulder swap and the framing blend so the two cannot ease at different
## rates and read as two separate moves.
const LENS_OFFSET_SMOOTHING: float = 8.0

## Q/E lean. A rate rather than a sensitivity multiplier — a key has no
## delta to scale the way look_sensitivity_x scales mouse motion. At 5.0 the
## lean reaches full in a fifth of a second, so a tap leans and a hold holds.
const LEAN_RATE: float = 5.0
## How fast the lean springs back with neither key held. Faster than
## LEAN_RATE on purpose — the lean should cost effort to hold and none to
## abandon. Inherited from the isometric glance this replaces, which used
## exactly that asymmetry for exactly that reason.
const LEAN_RETURN_RATE: float = 8.0

## How fast the TPS <-> TPS_WIDE framing blend crosses. A lens shift has no
## geometry to animate, so this replaces the old view-transition machinery
## (zoom slider, pitch retarget, a `view_mode_animating` gate the whole
## position pass had to be aware of) with one scalar.
const FRAMING_BLEND_SPEED: float = 6.0


# =============================================================================
# WALL AND FLOOR SAFETY
# =============================================================================
#
# The shape is a SPHERE cast, not a ray, and that is inherited deliberately
# rather than by accident. This camera used to use intersect_ray() while the
# isometric one used a sphere cast_motion(); CHANGELOG records that the
# sphere replaced a ray precisely BECAUSE a ray asks whether the camera's
# mathematical centre has crossed the wall — answered late and
# discontinuously, with the near face of the frustum already inside the wall
# — while a sphere reports the surface a whole radius early and its reported
# distance then varies continuously as the player walks. Carrying the ray
# into the single remaining camera would have been an unrecorded rollback of
# a decision the project already made once; the audit says so in §17 and
# this is that instruction carried out.
#
# THE METHOD TRANSFERS, THE MAGNITUDES DO NOT, and that is the one thing
# that had to be re-derived rather than copied. The isometric numbers were
# sized for a 10-17.5 m orbit: a 3.0 m minimum distance and a 0.45 m probe.
# Applied unchanged to a 2.2 m boom the minimum alone would have disabled
# occlusion outright — the probe's own early-out returns the desired
# distance whenever it is already at or under the minimum, and 2.2 is under
# 3.0. The two lengths below are therefore stated in terms of THIS camera's
# scale, and they are the part of this migration most in need of a look with
# eyes on a real corridor.

## Radius of the probe. Smaller than the orbit camera's 0.45: this boom is
## an order of magnitude shorter and lives indoors, where a fat probe would
## report a retraction in every doorway the character can walk through.
const CAMERA_COLLISION_RADIUS: float = 0.30

## Closest the camera may be pulled to the pivot. The character may be
## occluded; the camera may not be inside their head. Under a 1.5-2.6 m
## working range this leaves the boom room to retract meaningfully instead
## of being clamped away at the first wall.
const CAMERA_COLLISION_MIN_DISTANCE: float = 0.70

## How fast the camera returns to its full distance once the obstruction is
## gone. Deliberately slow, and deliberately NOT symmetric with the retract
## (see _update_collision_distance): coming out is a luxury, going in is a
## correctness requirement, and a fast return reads as the camera being
## shoved outward by a wall it has just cleared. A rate rather than a
## length, so this one does carry over from the orbit unchanged.
const CAMERA_COLLISION_RESTORE_RATE: float = 2.5

## Extra clearance kept between the camera and the surface the probe hit, so
## the camera sits in front of the wall rather than touching it. The same
## 0.25 the old ray back-off used.
const CAMERA_COLLISION_SURFACE_MARGIN: float = 0.25


## Runtime pitch accumulated from mouse look. Base tps_angle is the starting offset.
var _tps_pitch_deg: float = -10.0
## Pitch offset from TpsCombatCameraState (explore sway / lock-on), added on top of _tps_pitch_deg.
var _tps_pitch_offset_deg: float = 0.0
## Set once _target_metric_height() has warned about a target with no
## character-metric getters, so the warning doesn't spam every frame.
var _warned_missing_target_metrics: bool = false
## Set once _target_speed_ratio() has warned about a target with no
## get_speed_ratio(), so the warning doesn't spam every frame.
var _warned_missing_speed_ratio: bool = false
## Set once _target_horizontal_direction() has warned about a target with no
## get_horizontal_direction(), so the warning doesn't spam every frame.
var _warned_missing_horizontal_direction: bool = false

## Smoothed sprint pull-back distance, eased toward speed_ratio *
## TPS_SPRINT_PULLBACK at TPS_PULLBACK_SMOOTHING.
var _tps_sprint_pullback: float = 0.0
## Smoothed camera-lead offset, eased toward direction * speed_ratio *
## TPS_LEAD_DISTANCE at TPS_LEAD_SMOOTHING.
var _tps_lead_offset: Vector3 = Vector3.ZERO
## Latest distance_override reported by TpsCombatCameraState.update(), read
## every frame in _handle_tps_follow(). -1.0 means "don't override" (that
## dictionary's own convention, shared by EXPLORE and any non-positive
## LOCKED/TRANSITION value).
var _tps_lock_distance_override: float = -1.0
## Smoothed camera distance. Despite the name (kept from when lock-on was
## the only override) it now eases toward whichever of three sources
## _select_tps_distance_source() picks — see that function for the priority.
var _tps_lock_distance: float = TPS_DISTANCE

## 0 in TPS, 1 in TPS_WIDE, eased between. The single quantity that makes
## the two framings different.
var _framing_blend: float = 0.0

## How much of the lean POSE is applied on top of the camera lean, 0 to 1,
## eased. See _handle_lean() for why it is not simply 1.
var _lean_pose: float = 0.0

## -1 fully left to +1 fully right. The camera owns this, not the player:
## Q/E move the CAMERA out from behind cover and the body follows, which is
## the order every third-person lean works in. The pose is pushed to the
## character through player.set_lean() — the same "camera decides, animation
## component applies" split the old isometric head-look used.
var _lean: float = 0.0

## Smoothed camera distance after wall retraction. Negative means "no value
## yet", so the first frame adopts the real distance instead of easing out
## from zero with the camera sitting on the character's head.
var _collision_distance: float = -1.0
## Reusable query and shape for the wall probe. Held rather than built per
## frame — this runs every frame and both objects are pure configuration.
var _collision_shape := SphereShape3D.new()
var _collision_query := PhysicsShapeQueryParameters3D.new()
## Pivot the probe casts from, written by the position pass and read by the
## clamp that runs after it. Stashed rather than recomputed so the probe and
## the framing cannot disagree about where the character is this frame.
var _probe_pivot: Vector3 = Vector3.ZERO

@export_group("View")
## Base pitch the camera starts at.
@export var tps_angle: float = -10.0

@export_group("Lean")
## How far the camera slides sideways at full lean, metres. Applied along the
## camera's own right vector, so it is a strafe of the eye and not a roll —
## global_rotation's z is written as 0 every frame and a roll here would be
## silently discarded.
@export var lean_camera_offset: float = 0.45

@export_group("Wide framing")
## Lens shift applied at full TPS_WIDE, in the same units Camera3D's own
## h_offset/v_offset use. Positive h pushes the rendered subject toward one
## side and positive v toward the bottom — which side and which way is a
## sign that has to be confirmed on screen, not derived, so both are
## exported and the render probe is how they were set.
##
## The character ends up low and to one side, the framing most third-person
## games use for their "wide" or "exploration" camera, and the reason there
## is a second view mode at all after the orbit was removed.
@export var wide_h_offset: float = 0.55
## Set by looking at a render, not by taste in the abstract: at 0.35 the
## character's feet were cropped by the bottom of the frame. 0.22 keeps the
## whole figure in shot while still reading as a low corner placement.
@export var wide_v_offset: float = 0.22

@export_group("Look")
## Multiplier on top of InputSystems.MOUSE_SENSITIVITY. User preference —
## belongs in a settings menu later, not a hardcoded constant.
## InputSystems.MOUSE_SENSITIVITY = 0.003 rad/pixel is ~0.172 deg/pixel raw,
## high for a third-person camera; 0.65 brings that down to ~0.11 deg/pixel,
## closer to convention.
@export var look_sensitivity_x: float = 0.65
@export var look_sensitivity_y: float = 0.65
@export var invert_look_x: bool = false
@export var invert_look_y: bool = false
## Eye-by-feel tuning values, not implementation constants — hence @export
## rather than const. -70/60 gives real headroom to look down off a
## ledge/deck (Blackrock's verticality is the whole point) and to look up at
## towers, while staying well clear of the +/-90 gimbal case
## global_rotation's direct Euler set would hit.
@export var tps_pitch_min_deg: float = -70.0
@export var tps_pitch_max_deg: float = 60.0

@export_group("Aim")
## Multiplier on the shoulder h_offset while aiming. Grown, not shrunk: the
## sight needs to clear the character's silhouette, not sit centered on it,
## so the shot reads against open frame instead of against Sid's own back.
@export var aim_shoulder_offset_multiplier: float = 1.4

## --- References, assigned by the host before enter() ---
var camera: Camera3D
var target: Node3D

## --- Optional debug labels (assigned by the host, may be null) ---
var lbl_current_mode: Label
var lbl_orbital: Label
var lbl_follow: Label

## Which of three sources _tps_lock_distance should ease toward this frame,
## picked by _select_tps_distance_source(). A single decision point instead
## of three independent conditions, so the priority between them can't
## drift out of sync with whichever smoothing rate the caller applies for
## the winner:
##   1. AIM — PlayerState.is_aiming. Wins even over an active lock: aiming
##      AT a locked target should still pull the camera in tight for the
##      shot, not stay at lock-on's wider situational-awareness framing.
##   2. LOCK_ON — _tps_combat reports a positive distance_override while
##      LOCKED/TRANSITION. An ambient framing aid, not a deliberate choice
##      at this instant, so it yields to aim.
##   3. REST — TPS_DISTANCE, neither aiming nor locked.
enum TpsDistanceSource { REST, LOCK_ON, AIM }

var camera_target_pos: Vector3
var camera_current_pos: Vector3
var camera_target_pitch: float
var camera_current_pitch: float
var camera_target_yaw: float
var camera_current_yaw: float

var _tps_combat := TpsCombatCameraState.new()
var _shoulder := TpsShoulderCameraState.new()


## Called once by the host before first use (camera/target are already assigned).
func setup() -> void:
	camera_target_pitch = tps_angle
	camera_current_pitch = tps_angle
	camera_target_pos = camera.global_position
	camera_current_pos = camera.global_position
	_tps_pitch_deg = tps_angle
	_framing_blend = _framing_target()


## Called by the host on entering ON_FOOT (including returning from MENU).
func enter() -> void:
	camera_current_pos = camera.global_position
	# "Not yet known", so the first frame adopts the real distance rather
	# than easing out to it from whatever the previous stretch ended on —
	# the camera would otherwise start inside the character and swing out.
	_collision_distance = -1.0
	_framing_blend = _framing_target()


func exit() -> void:
	pass


func update(delta: float) -> void:
	if not target:
		return

	_handle_view_toggle()
	_handle_tps_follow(delta)
	_handle_shoulder_toggle()
	_handle_lean(delta)
	_framing_blend = lerpf(
		_framing_blend, _framing_target(), Smoothing.damp_factor(FRAMING_BLEND_SPEED, delta)
	)
	_update_camera_position(delta)
	_update_labels()


func _handle_tps_follow(delta: float) -> void:
	# --- Free mouse look (TLOU-style) ---
	# `look` (InputSystems.get_look_delta()) is in radians — camera_target_yaw
	# is also radians, so it can be added directly. _tps_pitch_deg is stored
	# in DEGREES (clamped by tps_pitch_min_deg/tps_pitch_max_deg, fed to
	# deg_to_rad() later), so it needs an explicit rad_to_deg() conversion —
	# this mismatch was the bug that made vertical look nearly unresponsive.
	var look := InputSystems.get_look_delta()
	# Mouse right -> relative.x > 0. Positive rotation.y in Godot turns the
	# view LEFT (forward sweeps toward -X), so adding here inverted the
	# horizontal look. Subtract so mouse right turns the camera right.
	var x_sign := -1.0 if invert_look_x else 1.0
	camera_target_yaw -= look.x * look_sensitivity_x * x_sign
	camera_target_yaw = wrapf(camera_target_yaw, -PI, PI)
	# TPS_PITCH_SENSITIVITY_RATIO is an anatomical proportion (vertical feels
	# heavier than horizontal), not a user setting — applied on top of
	# look_sensitivity_y rather than folded into it.
	var y_sign := -1.0 if invert_look_y else 1.0
	_tps_pitch_deg -= rad_to_deg(look.y) * look_sensitivity_y * TPS_PITCH_SENSITIVITY_RATIO * y_sign
	_tps_pitch_deg = clamp(_tps_pitch_deg, tps_pitch_min_deg, tps_pitch_max_deg)

	# --- Lock-on (combat state overrides yaw only when locked) ---
	if InputSystems.is_lock_on_just_pressed():
		_tps_combat.try_toggle_lock(target)

	var result := _tps_combat.update(delta, target, camera_target_yaw)
	_tps_pitch_offset_deg = result.pitch_offset_deg
	if _tps_combat.state == TpsCombatCameraState.TpsState.LOCKED:
		camera_target_yaw = result.yaw
	_tps_lock_distance_override = result.distance_override


## Reads a character-metric getter off `target` via duck typing — target is
## a generic Node3D, not necessarily the Player. Falls back to a fixed,
## non-zero height (with a one-time warning) if target doesn't expose it.
func _target_metric_height(method: StringName, fallback: float) -> float:
	if target.has_method(method):
		return float(target.call(method))
	if not _warned_missing_target_metrics:
		push_warning("OnFootCameraComponent: target '%s' has no %s() — using fallback height %.2f" % [target.name, method, fallback])
		_warned_missing_target_metrics = true
	return fallback


## Reads target.get_speed_ratio() via duck typing, same pattern as
## _target_metric_height(). Falls back to 0 (no pull-back) with a one-time
## warning if target doesn't expose it.
func _target_speed_ratio() -> float:
	if target.has_method(&"get_speed_ratio"):
		return float(target.call(&"get_speed_ratio"))
	if not _warned_missing_speed_ratio:
		push_warning("OnFootCameraComponent: target '%s' has no get_speed_ratio() — sprint pull-back disabled" % target.name)
		_warned_missing_speed_ratio = true
	return 0.0


## Reads target.get_horizontal_direction() via duck typing, same pattern as
## _target_speed_ratio(). Falls back to ZERO (no lead) with a one-time
## warning if target doesn't expose it.
func _target_horizontal_direction() -> Vector3:
	if target.has_method(&"get_horizontal_direction"):
		return target.call(&"get_horizontal_direction") as Vector3
	if not _warned_missing_horizontal_direction:
		push_warning("OnFootCameraComponent: target '%s' has no get_horizontal_direction() — camera lead disabled" % target.name)
		_warned_missing_horizontal_direction = true
	return Vector3.ZERO


func _select_tps_distance_source() -> TpsDistanceSource:
	if PlayerState.is_aiming:
		return TpsDistanceSource.AIM

	var combat_locking := _tps_combat.state == TpsCombatCameraState.TpsState.LOCKED \
			or _tps_combat.state == TpsCombatCameraState.TpsState.TRANSITION
	if combat_locking and _tps_lock_distance_override > 0.0:
		return TpsDistanceSource.LOCK_ON

	return TpsDistanceSource.REST


## Q/E, held. The clips behind the pose are static held poses (measured —
## see PlayerAnimationComponent.ANIM_LEAN_LEFT), so the amount below IS the
## lean and nothing has to be seeked or frozen.
##
## THE CAMERA ALWAYS LEANS; THE BODY ONLY LEANS IN COMBAT. The two clips are
## named aim-lean-l/r and they are exactly that — a full aiming posture,
## hands up at the shoulder as if a long gun were in them. Rendered and
## looked at on 2026-09-02 with empty hands in PEACE, they read as the
## character miming a rifle, which is a worse picture than no pose at all.
## Applying them where they belong keeps what Stan asked for (use the clips
## if the clips exist) without shipping a pose that contradicts what is in
## the hands. Out of COMBAT the lean is the camera sliding sideways, which
## is what a peek is for anyway.
func _handle_lean(delta: float) -> void:
	var axis := 0.0
	if InputSystems.is_lean_left_pressed():
		axis -= 1.0
	if InputSystems.is_lean_right_pressed():
		axis += 1.0

	if axis != 0.0:
		_lean = clampf(_lean + axis * LEAN_RATE * delta, -1.0, 1.0)
	else:
		_lean = lerpf(_lean, 0.0, Smoothing.damp_factor(LEAN_RETURN_RATE, delta))

	var pose_wanted := 1.0 if PlayerState.stance == PlayerState.Stance.COMBAT else 0.0
	_lean_pose = lerpf(_lean_pose, pose_wanted, Smoothing.damp_factor(LEAN_RETURN_RATE, delta))

	if target.has_method(&"set_lean"):
		target.call(&"set_lean", _lean * _lean_pose)


func _framing_target() -> float:
	return 1.0 if PlayerState.view_mode == PlayerState.ViewMode.TPS_WIDE else 0.0


func _update_camera_position(delta: float) -> void:
	var yaw_rad := camera_target_yaw
	var pitch_rad := deg_to_rad(_tps_pitch_deg)
	var horizontal_direction := Vector3(sin(yaw_rad), 0.0, cos(yaw_rad))

	var speed_ratio := _target_speed_ratio()
	_tps_sprint_pullback = lerp(
		_tps_sprint_pullback, speed_ratio * TPS_SPRINT_PULLBACK,
		Smoothing.damp_factor(TPS_PULLBACK_SMOOTHING, delta)
	)

	# Dolly: base distance is TPS_DISTANCE, unless aim or lock-on wants a
	# different one — see TpsDistanceSource's comment for the priority
	# between them. Smoothed at whichever rate goes with the winning source,
	# so a push-in never reads as a snap.
	var base_distance := TPS_DISTANCE
	var distance_smoothing := TPS_LOCK_DISTANCE_SMOOTHING
	match _select_tps_distance_source():
		TpsDistanceSource.AIM:
			base_distance = TPS_AIM_DISTANCE
			distance_smoothing = TPS_AIM_DISTANCE_SMOOTHING
		TpsDistanceSource.LOCK_ON:
			base_distance = _tps_lock_distance_override
		TpsDistanceSource.REST:
			pass
	_tps_lock_distance = lerp(
		_tps_lock_distance, base_distance, Smoothing.damp_factor(distance_smoothing, delta)
	)

	# TPS_WIDE is the SAME distance, deliberately — Stan, 2026-09-02: "только
	# смещение, дистанция та же". Pulling back as well would make the two
	# views two cameras again, which is what this migration removes.
	var effective_distance: float = _tps_lock_distance + _tps_sprint_pullback

	var horizontal_distance := effective_distance * cos(pitch_rad)
	var vertical_distance := -effective_distance * sin(pitch_rad)
	var right := Vector3(cos(yaw_rad), 0.0, -sin(yaw_rad))

	var shoulder_offset := _shoulder.update(delta)
	# The lean rides the same right vector as the shoulder offset and is
	# added to it: leaning while switched to the left shoulder should move
	# further left, not fight it.
	var shoulder := right * (
		shoulder_offset * TPS_SHOULDER_TRANSLATION_RATIO + _lean * lean_camera_offset
	)

	# Lead: pivot drifts ahead of the character's movement direction, not the
	# look direction — keeps this from fighting mouse look.
	var move_direction := _target_horizontal_direction()
	_tps_lead_offset = _tps_lead_offset.lerp(
		move_direction * speed_ratio * TPS_LEAD_DISTANCE,
		Smoothing.damp_factor(TPS_LEAD_SMOOTHING, delta)
	)

	# Base pivot: target + pivot height (shoulder level, not ground)
	var pivot_height := _target_metric_height(&"get_shoulder_height", TPS_PIVOT_HEIGHT_FALLBACK)
	var pivot := target.global_position + Vector3(0.0, pivot_height, 0.0) + _tps_lead_offset
	var offset := horizontal_direction * horizontal_distance \
			+ Vector3(0.0, vertical_distance, 0.0) + shoulder

	camera_target_pos = pivot + offset
	camera_target_pitch = _tps_pitch_deg + _tps_pitch_offset_deg

	# Lens shift: the shoulder's own frustum share plus the wide framing.
	# ADDED, not replaced — the wide view keeps the shoulder swap working,
	# it only moves where the whole picture sits.
	var aim_offset_scale := aim_shoulder_offset_multiplier if PlayerState.is_aiming else 1.0
	var target_h_offset := shoulder_offset * TPS_SHOULDER_FRUSTUM_RATIO \
			* TPS_SHOULDER_H_OFFSET_SIGN * aim_offset_scale \
			+ wide_h_offset * _framing_blend
	var target_v_offset := wide_v_offset * _framing_blend
	var lens_damp := Smoothing.damp_factor(LENS_OFFSET_SMOOTHING, delta)
	camera.h_offset = lerp(camera.h_offset, target_h_offset, lens_damp)
	camera.v_offset = lerp(camera.v_offset, target_v_offset, lens_damp)

	# Pivot for the wall probe. Eye height rather than the follow point: a
	# probe from the feet would begin flush with the floor and report a hit
	# on the ground the character is standing on.
	_probe_pivot = target.global_position + Vector3(
		0.0,
		_target_metric_height(&"get_eye_height", TPS_OCCLUSION_HEIGHT_FALLBACK),
		0.0
	)

	camera_current_pos = camera_current_pos.lerp(
		camera_target_pos, Smoothing.damp_factor(TPS_FOLLOW_SPEED, delta)
	)
	# Wall safety is the LAST layer, after the follow filter rather than
	# before it. Applied to the target instead, an "immediate" retract is
	# immediate only for the target — the filter then takes its own time to
	# carry the camera there. Clamping the settled position is what makes
	# the retract actually immediate, and clamping camera_current_pos rather
	# than only the camera keeps the filter from holding a position inside
	# the wall to snap back out to when the obstruction clears.
	camera_current_pos = _apply_wall_clamp(delta, camera_current_pos)

	camera_current_pitch = lerp(
		camera_current_pitch, camera_target_pitch,
		Smoothing.damp_factor(TPS_LOOK_SMOOTHING, delta)
	)
	camera_current_yaw = lerp_angle(
		camera_current_yaw, camera_target_yaw,
		Smoothing.damp_factor(TPS_LOOK_SMOOTHING, delta)
	)

	camera.global_position = camera_current_pos
	camera.global_rotation = Vector3(deg_to_rad(camera_current_pitch), camera_current_yaw, 0.0)


func _apply_wall_clamp(delta: float, position: Vector3) -> Vector3:
	var to_camera := position - _probe_pivot
	var desired := to_camera.length()
	if desired < 0.001:
		return position

	var direction := to_camera / desired
	var safe := _update_collision_distance(delta, _probe_pivot, direction, desired)
	if safe >= desired:
		return position
	return _probe_pivot + direction * safe


## Largest distance the camera may sit from the pivot this frame without
## ending up inside geometry, smoothed, and asymmetrically.
##
## RETRACT IS IMMEDIATE, RESTORE IS SLOW, and the asymmetry is not a feel
## preference dressed up as one — the two directions are different kinds of
## thing. Being inside a wall is a correctness failure the player sees as
## the world disappearing; being further out than strictly necessary costs
## nothing at all. So the shrinking direction is taken outright and only the
## growing direction is eased.
##
## Taking the retraction outright would be a snap if the probe's answer were
## itself a step, and against a flat wall it is not: the sphere reports the
## surface a radius early and the reported distance then falls continuously
## as the player walks in. What IS a step is a silhouette edge — rounding a
## pillar, a doorway going out of line — and there the sphere radius plus
## CAMERA_COLLISION_SURFACE_MARGIN mean the step happens while the camera
## still has clearance.
func _update_collision_distance(
	delta: float, pivot: Vector3, direction: Vector3, desired: float
) -> float:
	var safe := _probe_camera_distance(pivot, direction, desired)

	if _collision_distance < 0.0:
		# First frame — adopt, do not ease in.
		_collision_distance = safe
		return safe

	if safe < _collision_distance:
		_collision_distance = safe
	else:
		_collision_distance = lerp(
			_collision_distance, safe,
			Smoothing.damp_factor(CAMERA_COLLISION_RESTORE_RATE, delta)
		)

	return _collision_distance


## Sphere-casts from the pivot toward the camera and returns how far the
## camera may go.
##
## cast_motion() rather than intersect_ray(): it answers "how far can this
## VOLUME travel before it touches something", which is the question a
## camera actually has. Its return is a pair of fractions — the last safe one
## and the first unsafe one — and only the first is wanted here.
##
## CollisionLayers.CAMERA_OCCLUSION (floor + wall) is deliberately wider than
## PerceptionComponent's CollisionLayers.SIGHT (wall only): the camera swings
## low behind the character and would sink through the deck without floor in
## the mask.
##
## A pivot already buried in geometry (spawned inside a wall, terrain
## streamed in on top of the character) makes cast_motion() report zero
## before it has moved at all. That is not a reason to put the camera on the
## character's face, so the minimum wins: the character may be occluded, the
## camera may not be inside them.
func _probe_camera_distance(pivot: Vector3, direction: Vector3, desired: float) -> float:
	if not camera or desired <= CAMERA_COLLISION_MIN_DISTANCE:
		return desired

	var space_state := camera.get_world_3d().direct_space_state
	if space_state == null:
		return desired

	_collision_shape.radius = CAMERA_COLLISION_RADIUS
	_collision_query.shape = _collision_shape
	_collision_query.transform = Transform3D(Basis.IDENTITY, pivot)
	_collision_query.motion = direction * desired
	_collision_query.collision_mask = CollisionLayers.CAMERA_OCCLUSION
	_collision_query.collide_with_areas = false
	_collision_query.exclude = [target.get_rid()] if target is CollisionObject3D else []

	var result := space_state.cast_motion(_collision_query)
	if result.is_empty():
		return desired

	var safe_fraction: float = result[0]
	if safe_fraction >= 1.0:
		return desired

	return maxf(
		desired * safe_fraction - CAMERA_COLLISION_SURFACE_MARGIN,
		CAMERA_COLLISION_MIN_DISTANCE
	)


## V swaps the framing. There is no zoom edge to reach first any more — the
## old toggle had to drive a slider to ISOMETRIC_ZOOM_MIN and queue a
## pending switch, because the two views were two positions on one continuum.
## Two lens shifts have no continuum between them.
func _handle_view_toggle() -> void:
	if not InputSystems.is_toggle_view_just_pressed():
		return
	PlayerState.set_view_mode(
		PlayerState.ViewMode.TPS
		if PlayerState.view_mode == PlayerState.ViewMode.TPS_WIDE
		else PlayerState.ViewMode.TPS_WIDE
	)


func _handle_shoulder_toggle() -> void:
	if InputSystems.is_switch_shoulder_just_pressed():
		_shoulder.toggle()


func _update_labels() -> void:
	if not lbl_current_mode:
		return
	lbl_current_mode.text = "Кадр: %s (V — переключить)" % get_current_mode()
	if lbl_orbital:
		lbl_orbital.visible = false
	if lbl_follow:
		lbl_follow.visible = false


func get_current_mode() -> String:
	return "TPS wide" if PlayerState.view_mode == PlayerState.ViewMode.TPS_WIDE else "TPS"


## Public getter for the lock-on debug overlay
## (ui/debug/stream_debug_panel.gd) — same one-line passthrough pattern as
## camera_follow.gd's get_on_foot_component().
func get_combat_state() -> TpsCombatCameraState:
	return _tps_combat
