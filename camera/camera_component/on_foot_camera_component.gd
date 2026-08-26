# =============================================================================
# on_foot_camera_component.gd
# Camera component for PlayerState.Mode.ON_FOOT.
#
# Originally a straight relocation of the old monolithic camera_follow.gd.
# Two of the behaviours that arrived with it are gone: the four-position
# Q/E orbit (replaced by ISOMETRIC's octant yaw, which left Q/E free for a
# bounded glance) and the P follow-rotation toggle (nothing reads it any
# more — see _handle_follow_toggle()). What remains from that era is the
# V view toggle and wheel zoom.
#
# The component isn't a Camera3D itself — it gets a reference to the real
# camera (camera) and the target (target) from its host, and writes
# directly into camera.global_position/global_rotation while active.
#
# It also drives the character's HEAD in ISOMETRIC, through player.gd's
# set_head_look_point(). That is not camera placement, but the two things
# worth looking at — the manual glance offset and the cursor ground point —
# both live here and nowhere else. See _update_iso_head_look().
# =============================================================================
extends Node
class_name OnFootCameraComponent

## The only outward signal about zoom — HUD widgets (the ruler) subscribe
## here instead of reading Input themselves. _handle_zoom_input() is the
## only legitimate place in the project where zoom_in/zoom_out is
## physically read.
signal zoom_input_received()

## Not proportional to BODY_HEIGHT on purpose — camera distance is taste, not
## anatomy. Proportional to the old 2.6 @ 2.32m body would be ~2.02; 2.2 is
## visually tighter framing for this camera family.
const TPS_DISTANCE: float = 2.2
## Vertical look is deliberately slower than horizontal — the traditional
## "mouse Y feels heavier than mouse X" convention for TPS/FPS cameras.
const TPS_PITCH_SENSITIVITY_RATIO: float = 0.7

## Position follow rate in TPS, separate from view_transition_speed (which
## owns the ISOMETRIC <-> TPS transition animation). Steady-state lag behind
## a target moving at constant speed is roughly speed / this value.
const TPS_FOLLOW_SPEED: float = 16.0

## Rotation follow rate in steady-state TPS. Deliberately much faster than
## TPS_FOLLOW_SPEED: position lag reads as a spring, rotation lag reads as
## input lag. Mouse look must feel direct.
const TPS_LOOK_SMOOTHING: float = 30.0

## Position and rotation follow rates in steady-state ISOMETRIC. High
## enough to be near-transparent, and that is the entire point of them.
##
## ISOMETRIC used to fall through to view_transition_speed (4.0) for both,
## which put a SECOND time constant behind IsometricCameraState — a state
## whose dead zone, soft zone and hard zone are all measured against the
## follow point it returns, on the assumption that the camera sits there.
## It did not. At run_speed 15.5 the two stages together trailed by about
## 8.3 m where the state's own rate accounted for 4.4 of it, the lead was
## sized for neither, and the hard zone could not clamp anything at all
## because the point it clamped was not the point being drawn. Rotation had
## the matching problem: camera_target_pos is built from current_angle (this
## frame's yaw) while camera.rotation.y came from the lagged
## camera_current_yaw, so during every turn the camera body orbited ahead of
## its own look direction and slid the character across the frame.
##
## Not removed outright, at either channel. A fast filter still eases the
## first frames after enter() instead of hard-snapping the camera in from
## wherever the previous mode left it, and still absorbs a single-frame
## spike. What it must not do is contribute a lag comparable to the state's
## own: at 30.0 the residual is around 0.5 m at full run, an order of
## magnitude under the state's, and FOLLOW_RATE_MOVING's comment accounts
## for it explicitly rather than pretending it is zero.
const ISO_FOLLOW_SPEED: float = 30.0
const ISO_ROTATION_SPEED: float = 30.0

## How steeply the cursor ray must point down before _cursor_ground_point()
## trusts its intersection with the ground plane. Below this the ray is
## near-parallel to the plane and the hit runs away toward the horizon.
const CURSOR_RAY_MIN_DOWNWARD: float = 0.05

## Furthest a cursor ground point may be from the camera before it is
## discarded. A backstop for rays that pass the slope test and still land
## absurdly far out; nothing the player can act on lives out there, and
## letting one through would pin the cursor bias at its cap permanently.
const CURSOR_RAY_MAX_DISTANCE: float = 200.0

## Manual look offset, in degrees, past which the character is considered
## to be actively glancing and turns their head to match. Small, but not
## zero: the offset springs back through a long tail of fractions of a
## degree, and a head that kept following it would never settle.
const ISO_HEAD_LOOK_PEEK_DEG: float = 5.0

## How far the cursor must be from the character before the head will look
## at it. Inside this the direction is ill-defined and the head would spin
## on tiny mouse movements.
const ISO_HEAD_LOOK_CURSOR_MIN_DISTANCE: float = 1.5

## How far in front of the character to place the peek look point. Only the
## direction matters to the head, but the distance sets how far the gaze
## converges, so it should read as looking down the street rather than at
## something an arm's length away. Deliberately a local constant and not a
## reach into PlayerAnimationComponent.HEAD_LOOK_DISTANCE: the camera
## decides where to point the head and the animation component decides how
## to get it there, and neither should have to be edited because the other
## changed its mind.
const ISO_HEAD_LOOK_DISTANCE: float = 5.0

## Extra camera distance at full run speed, on top of TPS_DISTANCE. Explicit
## and tunable — the previous pull-back was an accidental by-product of the
## follow-lag, not a setting. At run_speed, the residual TPS_FOLLOW_SPEED lag
## (~0.6m) plus this (0.4m) adds up to roughly 1.0m total, versus the ~2.5m
## the old shared-lag setup produced by accident.
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

## Vertical FOV assumed when converting screen fractions to world units
## for the isometric dead zone. Read from the camera at runtime; this is
## only the fallback if the camera is missing.
const ISO_FOV_FALLBACK: float = 75.0

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
## Set once _update_iso_head_look() has warned about a target with no
## set_head_look_point(), so the warning doesn't spam every frame.
var _warned_missing_head_look: bool = false
## Smoothed sprint pull-back distance, eased toward speed_ratio *
## TPS_SPRINT_PULLBACK at TPS_PULLBACK_SMOOTHING in TPS, and back toward 0
## at the same rate in ISOMETRIC (see _update_camera_position) — never
## frozen, so it can't leak a stale value across a mode switch either way.
var _tps_sprint_pullback: float = 0.0
## Smoothed camera-lead offset, eased toward direction * speed_ratio *
## TPS_LEAD_DISTANCE at TPS_LEAD_SMOOTHING. Same decay-in-both-modes rule as
## _tps_sprint_pullback.
var _tps_lead_offset: Vector3 = Vector3.ZERO
## Latest distance_override reported by TpsCombatCameraState.update(), read
## every frame in _handle_tps_follow(). -1.0 means "don't override" (that
## dictionary's own convention, shared by EXPLORE and any non-positive
## LOCKED/TRANSITION value).
var _tps_lock_distance_override: float = -1.0
## Smoothed camera distance. Despite the name (kept from when lock-on was
## the only override) it now eases toward whichever of three sources
## _select_tps_distance_source() picks — see that function for the
## priority — not just the lock-on one. Decayed back to TPS_DISTANCE in
## ISOMETRIC by _decay_tps_state(), same rule as every other TPS-only
## smoothed value.
var _tps_lock_distance: float = TPS_DISTANCE

@export var rotation_speed: float = 8.0

@export_group("Orbit")
@export var orbit_distance: float = 20.0
@export var orbit_height: float = 15.0
@export var camera_angle: float = -35.0

@export_group("View Transition")
@export var view_transition_speed: float = 4.0

@export_group("TPS View")
## Placeholder value — tune in place; what matters is that the
## return-to-ISOMETRIC logic is preserved.
@export var tps_angle: float = -10.0

@export_group("Look")
## Multiplier on top of InputSystems.MOUSE_SENSITIVITY. User preference —
## belongs in a settings menu later, not a hardcoded constant.
## InputSystems.MOUSE_SENSITIVITY = 0.003 rad/pixel is ~0.172 deg/pixel raw,
## high for a third-person camera; 0.65 brings that down to ~0.11 deg/pixel,
## closer to convention.
## Perceived sensitivity changed sharply once TPS switched to
## MOUSE_MODE_CAPTURED (commit 63c26fe) — before that the cursor hit the
## screen edge and stopped moving the view. Don't go looking for the cause
## of a "sensitivity feels different now" report in this file.
@export var look_sensitivity_x: float = 0.65
@export var look_sensitivity_y: float = 0.65
@export var invert_look_x: bool = false
@export var invert_look_y: bool = false
## Eye-by-feel tuning values, not implementation constants — hence @export
## rather than const. -50/20 (the old constants) capped looking up at 20°
## and gave only 50° of downward range; -70/60 gives real headroom to look
## down off a ledge/deck (Blackrock's verticality is the whole point) and to
## look up at towers, while staying well clear of the ±90° gimbal case
## global_rotation's direct Euler set would hit.
@export var tps_pitch_min_deg: float = -70.0
@export var tps_pitch_max_deg: float = 60.0


@export_group("Follow")
@export var follow_rotation_damping: float = 3.0
@export var follow_rotation_delay: float = 0.2

@export_group("Isometric Look")
## Largest temporary look offset from the character's own direction, in
## degrees, either side. The whole point of the bound is that ISOMETRIC look
## stays a glance: past roughly this much the camera stops reading as
## "leaning to see" and starts reading as a free orbit, which is the thing
## directional framing exists to replace.
##
## The ONLY clamp in the system. IsometricCameraState deliberately has no
## copy — see Frame.manual_look_yaw_deg over there.
@export var iso_look_yaw_limit_deg: float = 35.0
## Degrees per second while Q or E is held.
##
## A rate, not a sensitivity multiplier: the ISOMETRIC look is driven by
## keys, and a key has no delta to scale the way look_sensitivity_x scales
## mouse motion. At 60 deg/s the full 35 degrees takes a little under six
## tenths of a second, so a tap leans and a hold reaches the stop.
@export var iso_look_rate_deg: float = 60.0
## How fast the offset springs back to zero once neither key is held.
## Faster than iso_look_rate_deg on purpose — the look should cost effort to
## hold and none to abandon.
@export var iso_look_return_rate: float = 6.0

## Furthest the character's head may turn off their own facing in
## ISOMETRIC, either side. The backstop for every head-look branch, applied
## after whichever one won — see _update_iso_head_look().
##
## Sized to match iso_look_yaw_limit_deg so a full glance turns the head the
## whole way, and no further. It is NOT derived from that value: the two
## answer different questions (how far may the camera lean, versus how far
## may a neck turn) and a neck limit that silently followed a camera
## setting is exactly how the head ended up able to rotate 360 degrees.
## PlayerAnimationComponent's rig has limits of its own
## (head_look_primary_limit_deg, 70) — this is the tighter, deliberate one,
## and the rig's is the hard backstop underneath it.
@export var iso_head_look_limit_deg: float = 35.0

## Furthest the head will turn to follow the CURSOR. Tighter than the
## glance limit on purpose: a glance is asked for, a cursor is not.
@export var iso_head_look_cursor_limit_deg: float = 25.0

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

var follow_player_rotation: bool = false

# === ORBITAL SYSTEM ===
enum OrbitalPosition { NORTH, EAST, SOUTH, WEST }
const ORBITAL_POSITIONS = [OrbitalPosition.NORTH, OrbitalPosition.EAST, OrbitalPosition.SOUTH, OrbitalPosition.WEST]
const POSITION_ANGLES = {
	OrbitalPosition.NORTH: 0.0,
	OrbitalPosition.EAST: PI / 2,
	OrbitalPosition.SOUTH: PI,
	OrbitalPosition.WEST: 3 * PI / 2
}
var current_position: OrbitalPosition = OrbitalPosition.NORTH

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

var target_angle: float = 0.0
var current_angle: float = 0.0
var player_rotation_timer: float = 0.0
var last_player_rotation: float = 0.0

## The single source of truth for the current view is PlayerState.view_mode.
## No parallel bool/enum is kept here anymore.

var camera_target_pos: Vector3
var camera_current_pos: Vector3
var camera_target_pitch: float
var camera_current_pitch: float
var camera_target_yaw: float
var camera_current_yaw: float

# === ZOOM SYSTEM ===
# One continuous "slider" across the TPS <-> ISOMETRIC chain.
# TOPDOWN was removed (see the note in the Miro concept board) — ON_FOOT
# only has TPS and ISOMETRIC left.
# Each mode has its own distance range; switching between modes via V only
# happens once the zoom has hit the matching edge.
var current_zoom_distance: float = 0.0
var target_zoom_distance: float = 0.0
var zoom_animating: bool = false
var zoom_anim_time: float = 0.0
var zoom_start_distance: float = 0.0

const ISOMETRIC_ZOOM_MIN: float = 10.0   # near edge (zoomed all the way in) -> V -> TPS
const ISOMETRIC_ZOOM_MAX: float = 17.5   # far edge — just a zoom limit, no transition
const TPS_ZOOM_MIN: float = 3.0          # nowhere further to go, a dead end (still lets you keep zooming in)
const TPS_ZOOM_MAX: float = 6.0          # far edge -> V -> back to ISOMETRIC
const ZOOM_STEP: float = 2.5
const ZOOM_EDGE_EPSILON: float = 0.05    # tolerance for "did it hit the edge" comparisons

# === ORBITAL ROTATION (Q/E) ===
var orbit_rotation_animating: bool = false
var orbit_anim_time: float = 0.0
var orbit_start_angle: float = 0.0
var orbit_target_angle: float = 0.0

# === VIEW MODE SWITCHING (V) ===
var view_mode_animating: bool = false
var view_anim_time: float = 0.0
var view_start_distance: float = 0.0
var view_target_distance: float = 0.0
var view_start_pitch: float = 0.0
var view_target_pitch: float = 0.0
## Set when V is pressed in ISOMETRIC away from ISOMETRIC_ZOOM_MIN: drives
## the existing zoom animation to the edge first, then switches to TPS once
## it lands there. A second V press while that zoom is in flight clears this
## instead of queuing another switch (see _handle_view_toggle()).
var _pending_tps_switch: bool = false

# === FOLLOW ROTATION (P) ===
var follow_rotation_animating: bool = false
var follow_anim_time: float = 0.0
var follow_start_angle: float = 0.0
var follow_target_angle: float = 0.0


var _tps_combat := TpsCombatCameraState.new()
var _shoulder := TpsShoulderCameraState.new()

var _iso := IsometricCameraState.new()

## Reused every frame so the isometric state does not allocate a
## Frame per tick. Never handed out — the host is its only writer.
var _iso_frame := IsometricCameraState.Frame.new()

## Current temporary ISOMETRIC look offset in degrees, already clamped to
## +/- iso_look_yaw_limit_deg. Owned here rather than in
## IsometricCameraState because it is a product of input, and input policy
## belongs on this side of that boundary. Handed over each frame through
## Frame.manual_look_yaw_deg.
var _iso_manual_look_yaw_deg: float = 0.0

## Set once _target_facing_direction() has warned about a target with no
## get_facing_direction(), so the warning doesn't spam every frame.
var _warned_missing_facing_direction: bool = false

## Optional, assigned by the host like the debug labels. Null in a
## normal build; when present, draws the dead-zone rectangles.
var iso_debug_overlay: IsometricCameraDebugOverlay

## Called once by the host before first use (camera/target are already assigned).
func setup() -> void:
	current_angle = POSITION_ANGLES[current_position]
	target_angle = current_angle
	camera_target_pitch = camera_angle
	camera_current_pitch = camera_angle
	camera_target_yaw = current_angle
	camera_current_yaw = current_angle
	camera_target_pos = camera.global_position
	camera_current_pos = camera.global_position
	current_zoom_distance = orbit_distance
	target_zoom_distance = orbit_distance
	
	_tps_pitch_deg = tps_angle


## Called by the host on entering ON_FOOT (including returning from MENU).
func enter() -> void:
	camera_current_pos = camera.global_position

	# Neither the follow point nor the yaw may ease in from wherever
	# ISOMETRIC left them before the last mode switch.
	#
	# request_reset() rather than reset(), even when a target is available:
	# reset() clears IsometricCameraState._needs_reset, and that flag is
	# what update_orientation() reads to decide between snapping the yaw and
	# smoothing it. Resetting the follow point here directly would therefore
	# leave the yaw smoothing out of a stale value on the first ISOMETRIC
	# frame — the follow point placed correctly, the camera swinging into
	# place around it. Deferring both to the next frame costs nothing:
	# nothing reads the follow point between here and update().
	_iso.request_reset()
	_iso_manual_look_yaw_deg = 0.0


## Releases the head on the way out, for the same reason enter() resets the
## follow point and the look offset: nothing this component decided about
## the character may outlive it being the component in charge. Without
## this, leaving ON_FOOT mid-glance would leave the head pinned at a point
## in the world that no longer means anything, with no one left running to
## take it back.
func exit() -> void:
	_clear_iso_head_look()


func update(delta: float) -> void:
	if not target:
		return

	var view := PlayerState.view_mode

	_handle_zoom_input()
	_handle_view_toggle()

	if view == PlayerState.ViewMode.TPS:
		# In TPS the camera is always behind the player — orbit (Q/E) and
		# toggle_follow (P) don't apply here, it isn't their responsibility.
		_handle_tps_follow(delta)
		_handle_shoulder_toggle()
	else:
		# ISOMETRIC yaw is directional now — it comes from where the
		# character is going, not from a camera the player aims by hand. So
		# the two mechanisms that used to aim it are no longer called here:
		# _handle_rotation_input() (Q/E stepping OrbitalPosition) and
		# _handle_follow_toggle()/_handle_follow_rotation() (P). They stay
		# in the file until the directional feel is confirmed, so reverting
		# is one line rather than a resurrection; nothing reaches them.
		#
		# Q and E themselves are not idle: they now hold the bounded
		# temporary look below.
		_handle_isometric_look_input(delta)

	_update_zoom_animation(delta)
	_update_orbit_rotation_animation(delta)
	_update_view_mode_animation(delta)
	_update_follow_rotation_animation(delta)

	if _pending_tps_switch and not zoom_animating:
		_pending_tps_switch = false
		# Re-check the edge: a wheel zoom could have retargeted the slider
		# away from ISOMETRIC_ZOOM_MIN while this was in flight.
		if is_equal_approx_eps(target_zoom_distance, ISOMETRIC_ZOOM_MIN):
			_transition_to_view(PlayerState.ViewMode.TPS)

	# In ISOMETRIC current_angle no longer drives anything — IsometricCamera-
	# State owns the yaw, and _update_camera_position() copies it back into
	# current_angle afterwards so labels and the next view transition still
	# have a sensible value to read. Easing it toward target_angle here as
	# well would be a second yaw source racing the first, which is exactly
	# the arrangement this change removes.
	if PlayerState.view_mode != PlayerState.ViewMode.ISOMETRIC:
		if not orbit_rotation_animating and not follow_rotation_animating:
			current_angle = lerp_angle(current_angle, target_angle, Smoothing.damp_factor(rotation_speed, delta))

	_update_camera_position(delta)
	
	_update_labels()


func _handle_tps_follow(delta: float) -> void:
	# --- Free mouse look (TLOU-style) ---
	# `look` (InputSystems.get_look_delta()) is in radians — camera_target_yaw
	# is also radians, so it can be added directly. _tps_pitch_deg is stored
	# in DEGREES (clamped by tps_pitch_min_deg/tps_pitch_max_deg, fed to deg_to_rad() later), so
	# it needs an explicit rad_to_deg() conversion — this mismatch was the bug
	# that made vertical look nearly unresponsive.
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


func _update_zoom_animation(delta: float):
	if not zoom_animating:
		return

	zoom_anim_time += delta
	var t: float = 0.0

	if zoom_anim_time < 0.4:
		var phase1_progress = zoom_anim_time / 0.4
		t = phase1_progress * 0.75
	elif zoom_anim_time < 0.6:
		var phase2_progress = (zoom_anim_time - 0.4) / 0.2
		t = 0.75 + phase2_progress * 0.25
	else:
		t = 1.0
		zoom_animating = false

	var te = t * t * (3.0 - 2.0 * t)
	current_zoom_distance = lerp(zoom_start_distance, target_zoom_distance, te)

	if not zoom_animating:
		current_zoom_distance = target_zoom_distance


func _update_orbit_rotation_animation(delta: float):
	if not orbit_rotation_animating:
		return

	orbit_anim_time += delta
	var t: float = 0.0

	if orbit_anim_time < 0.4:
		var phase1_progress = orbit_anim_time / 0.4
		t = phase1_progress * 0.75
	elif orbit_anim_time < 0.6:
		var phase2_progress = (orbit_anim_time - 0.4) / 0.2
		t = 0.75 + phase2_progress * 0.25
	else:
		t = 1.0
		orbit_rotation_animating = false

	var te = t * t * (3.0 - 2.0 * t)
	current_angle = lerp_angle(orbit_start_angle, orbit_target_angle, te)

	if not orbit_rotation_animating:
		current_angle = orbit_target_angle


func _update_view_mode_animation(delta: float):
	if not view_mode_animating:
		return

	view_anim_time += delta
	var t: float = 0.0

	if view_anim_time < 0.2:
		var phase1_progress = view_anim_time / 0.2
		t = phase1_progress * 0.25
	elif view_anim_time < 0.4:
		var phase2_progress = (view_anim_time - 0.2) / 0.2
		t = 0.25 + phase2_progress * 0.5
	elif view_anim_time < 0.6:
		var phase3_progress = (view_anim_time - 0.4) / 0.2
		t = 0.75 + phase3_progress * 0.25
	else:
		t = 1.0
		view_mode_animating = false

	var te = t * t * (3.0 - 2.0 * t)
	current_zoom_distance = lerp(view_start_distance, view_target_distance, te)
	camera_current_pitch = lerp(view_start_pitch, view_target_pitch, te)

	if not view_mode_animating:
		current_zoom_distance = view_target_distance
		camera_current_pitch = view_target_pitch


func _update_follow_rotation_animation(delta: float):
	if not follow_rotation_animating:
		return

	follow_anim_time += delta
	var t: float = 0.0

	if follow_anim_time < 0.4:
		var phase1_progress = follow_anim_time / 0.4
		t = phase1_progress * 0.25
	elif follow_anim_time < 0.6:
		var phase2_progress = (follow_anim_time - 0.4) / 0.2
		t = 0.25 + phase2_progress * 0.5
	elif follow_anim_time < 1.0:
		var phase3_progress = (follow_anim_time - 0.6) / 0.4
		t = 0.75 + phase3_progress * 0.25
	else:
		t = 1.0
		follow_rotation_animating = false

	var te = t * t * (3.0 - 2.0 * t)
	current_angle = lerp_angle(follow_start_angle, follow_target_angle, te)

	if not follow_rotation_animating:
		current_angle = follow_target_angle


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


## Bounded temporary look for ISOMETRIC, on held Q/E.
##
## NOT mouse-X, despite TPS reading look that way. InputSystems captures the
## cursor only in TPS (see _apply_mouse_mode()); ISOMETRIC leaves it visible
## because click-to-move needs it. Mouse look here would therefore fire on
## every ordinary movement of the cursor toward a click target, and stop
## dead at the screen edge. RMB is already claimed by ClickToMoveSystem's
## run-hold. Q and E are free precisely because this change retired the
## orbit they used to step, which makes them the natural home for the look
## that replaces it.
##
## Direction convention: increasing yaw turns get_cam_forward() from -Z
## toward -X, and +X is screen-right, so a larger yaw pans the view LEFT —
## hence lean_left adding. Derived from the maths, not observed in the
## editor; if it reads inverted, flip the two signs here and nothing else.
func _handle_isometric_look_input(delta: float) -> void:
	var axis := 0.0
	if InputSystems.is_lean_left_pressed():
		axis += 1.0
	if InputSystems.is_lean_right_pressed():
		axis -= 1.0

	if axis != 0.0:
		_iso_manual_look_yaw_deg = clampf(
			_iso_manual_look_yaw_deg + axis * iso_look_rate_deg * delta,
			-iso_look_yaw_limit_deg,
			iso_look_yaw_limit_deg
		)
		return

	# Nothing held — spring back to the character's own direction.
	_iso_manual_look_yaw_deg = lerpf(
		_iso_manual_look_yaw_deg,
		0.0,
		Smoothing.damp_factor(iso_look_return_rate, delta)
	)


## Reads target.get_facing_direction() via duck typing, same pattern as
## _target_speed_ratio() and _target_horizontal_direction().
##
## The fallback derives facing from rotation.y using +Z as forward, NOT
## Godot's usual -Z: this project rotates characters with atan2(dir.x,
## dir.z), and player.gd's own get_facing_direction() carries the warning
## that deriving it from the basis gets the sign wrong. A -Z fallback here
## would point the ISOMETRIC camera at the character's face instead of
## following them, and would do it only on targets missing the getter —
## the kind of bug that survives a playtest because the player character
## has the getter.
func _target_facing_direction() -> Vector3:
	if target.has_method(&"get_facing_direction"):
		return target.call(&"get_facing_direction") as Vector3
	if not _warned_missing_facing_direction:
		push_warning("OnFootCameraComponent: target '%s' has no get_facing_direction() — using rotation.y" % target.name)
		_warned_missing_facing_direction = true
	return Vector3(sin(target.rotation.y), 0.0, cos(target.rotation.y))


## Camera yaw that faces the same way as the given ground direction. One
## shared conversion so the view-transition seed and
## IsometricCameraState._reset_yaw() cannot disagree about the sign — they
## used to, as a hand-written "+ PI" on one side and a formula on the other.
func _yaw_facing(forward: Vector3) -> float:
	var fwd := forward
	fwd.y = 0.0
	if fwd.length_squared() < 0.0001:
		fwd = Vector3.FORWARD
	return atan2(-fwd.x, -fwd.z)


func _select_tps_distance_source() -> TpsDistanceSource:
	if PlayerState.is_aiming:
		return TpsDistanceSource.AIM

	var combat_locking := _tps_combat.state == TpsCombatCameraState.TpsState.LOCKED \
			or _tps_combat.state == TpsCombatCameraState.TpsState.TRANSITION
	if combat_locking and _tps_lock_distance_override > 0.0:
		return TpsDistanceSource.LOCK_ON

	return TpsDistanceSource.REST


## Every piece of TPS-only smoothed state (shoulder h_offset, sprint
## pull-back, camera lead, ...) must decay to its rest value here so none of
## it survives a trip through ISOMETRIC — by construction nothing else
## guarantees that. Add a new TPS state's decay line here in the same
## commit that introduces the state.
##
## Aiming introduces no new line of its own: it only ever affects
## _tps_lock_distance (already decayed below, toward TPS_DISTANCE, the
## correct rest value regardless of source) and camera.h_offset's target
## magnitude (already decayed below too) — both channels this function
## already owned before aiming existed.
func _decay_tps_state(delta: float) -> void:
	camera.h_offset = lerp(camera.h_offset, 0.0, Smoothing.damp_factor(8.0, delta))
	_tps_sprint_pullback = lerp(_tps_sprint_pullback, 0.0, Smoothing.damp_factor(TPS_PULLBACK_SMOOTHING, delta))
	_tps_lead_offset = _tps_lead_offset.lerp(Vector3.ZERO, Smoothing.damp_factor(TPS_LEAD_SMOOTHING, delta))
	_tps_lock_distance = lerp(_tps_lock_distance, TPS_DISTANCE, Smoothing.damp_factor(TPS_LOCK_DISTANCE_SMOOTHING, delta))


## Fills the reusable Frame for IsometricCameraState.
##
## Character data is read through optional getters, the same convention
## _target_metric_height() already uses, so a target missing them
## degrades instead of erroring.
##
## world_per_pixel is derived here rather than in the state because it
## depends on the camera and the zoom slider, both of which belong to
## the host. Deriving it from the CURRENT zoom is what makes the dead
## zone keep its apparent size as the player zooms.
func _build_iso_frame() -> IsometricCameraState.Frame:
	var f := _iso_frame

	f.target_position = target.global_position
	f.speed_ratio = _target_speed_ratio()
	f.on_floor = _target_on_floor()
	f.move_target = _target_move_target()
	f.combat = PlayerState.stance == PlayerState.Stance.COMBAT

	# Which direction the camera should face. Movement direction while the
	# character is actually moving, their facing once stopped — stated as an
	# explicit branch rather than "velocity, or facing if velocity is zero",
	# because the two answer different questions. While moving, the player
	# cares where they are going; standing still, velocity says nothing at
	# all and facing is the only intent there is.
	#
	# Same threshold IsometricCameraState uses to pick between its two yaw
	# rates, referenced rather than repeated: yaw and the direction feeding
	# it must agree on when a character has stopped.
	var dir: Vector3
	if f.speed_ratio > IsometricCameraState.MOVING_SPEED_THRESHOLD:
		dir = _target_horizontal_direction()
		# Click-to-move can report speed while the velocity vector is still
		# settling; facing is the honest answer for that frame.
		if dir.length_squared() < 0.0001:
			dir = _target_facing_direction()
	else:
		dir = _target_facing_direction()
	f.target_forward = dir
	f.manual_look_yaw_deg = _iso_manual_look_yaw_deg

	# Provisional basis only. The caller overwrites both from
	# _iso.get_cam_forward()/get_cam_right() once update_orientation() has
	# run — see _update_camera_position(). Filled here anyway so a Frame is
	# never handed on with a stale basis from two frames ago if some future
	# caller forgets the second step.
	f.cam_forward = Vector3(-sin(current_angle), 0.0, -cos(current_angle))
	f.cam_right = Vector3(cos(current_angle), 0.0, -sin(current_angle))

	var viewport_size := camera.get_viewport().get_visible_rect().size
	f.viewport_size = viewport_size

	# Visible world height at the character's distance, divided by viewport
	# height. This is what lets the dead zone keep its apparent screen size
	# as the player zooms.
	#
	# The two projections need different math: a perspective camera's
	# visible height grows with distance, an orthogonal camera's is fixed
	# at camera.size. Branching here rather than assuming perspective —
	# camera_follow.tscn stores an orthogonal camera and camera_follow.gd
	# overrides it to perspective at _ready(), so the assumption is one
	# edit away from being wrong.
	var visible_height: float
	if camera and camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		visible_height = camera.size
	else:
		var fov := camera.fov if camera else ISO_FOV_FALLBACK
		visible_height = 2.0 * current_zoom_distance * tan(deg_to_rad(fov) * 0.5)
	f.world_per_pixel = visible_height / maxf(viewport_size.y, 1.0)

	# How much screen a ground metre running away from the camera covers,
	# relative to one running across it. sin of the pitch, floored so a
	# camera tilted flat cannot hand the state a divisor of zero. See
	# Frame.forward_screen_scale for what goes wrong without it.
	f.forward_screen_scale = maxf(sin(deg_to_rad(absf(camera_angle))), 0.1)

	var cursor_point: Variant = _cursor_ground_point()
	f.cursor_valid = cursor_point != null
	f.cursor_point = cursor_point if f.cursor_valid else Vector3.ZERO

	return f


## Where on the ground the player is pointing, or null when the cursor does
## not name a usable point.
##
## A PLANE intersection, not a physics raycast, and the difference matters
## for what this feeds. ClickToMoveSystem.raycast_ground_point() exists and
## does the physics version, but this camera deliberately holds no
## reference to that system (same reasoning as _target_move_target()) — and
## a physics hit would be the wrong answer here anyway. A move order wants
## the exact surface the player clicked, so a discontinuity at a rooftop
## edge is correct for it. Framing wants a value that varies smoothly with
## the cursor: a hit that jumps several metres the instant the cursor
## crosses a parapet would kick the camera, and it would do it while the
## player was merely moving the mouse. Intersecting a flat plane at the
## follow point's height is continuous by construction.
##
## The plane's height comes from the follow point as it stood at the END of
## the previous frame — this runs before _iso.update() has produced this
## frame's. Same accepted one-frame lag as world_per_pixel above and the
## debug overlay's projection, and for the same reason: far below every
## damping constant involved.
##
## Reading the cursor through the viewport rather than through InputSystems
## is not a breach of the "only InputSystems touches Input" rule — this is
## a Viewport query, not Input.*, and ClickToMoveSystem._raycast_and_move()
## already reads it exactly this way.
func _cursor_ground_point() -> Variant:
	if not camera:
		return null

	var screen_pos := camera.get_viewport().get_mouse_position()
	var origin := camera.project_ray_origin(screen_pos)
	var direction := camera.project_ray_normal(screen_pos)

	# Near the horizon the ray is almost parallel to the ground and the
	# intersection runs off toward infinity. At the ISOMETRIC pitch the top
	# edge of the frustum sits only a couple of degrees above horizontal, so
	# this is an ordinary cursor position, not an edge case.
	if direction.y > -CURSOR_RAY_MIN_DOWNWARD:
		return null

	var plane := Plane(Vector3.UP, _iso.follow_point.y)
	var hit: Variant = plane.intersects_ray(origin, direction)
	if hit == null:
		return null

	var point: Vector3 = hit
	if point.distance_squared_to(origin) > CURSOR_RAY_MAX_DISTANCE * CURSOR_RAY_MAX_DISTANCE:
		return null

	return point


## Turns the character's head toward whatever the player is attending to in
## ISOMETRIC, or lets it go.
##
## The rig for this already existed and had no caller anywhere in the
## project: PlayerAnimationComponent builds a LookAtModifier3D on the Head
## bone with its own limits, smoothing and influence fade, and exposes it
## through player.gd's set_head_look_point()/clear_head_look_point(). All
## that was missing was something to decide the point. This is that.
##
## Driven from the camera rather than from player.gd because the two things
## worth looking at — the manual look offset and the cursor ground point —
## both belong to this component. player.gd could not answer either without
## acquiring them, and get_camera_yaw() is not a route to the first: it is
## fed only by TpsMovementSystem, so in ISOMETRIC it holds whatever TPS left
## behind.
##
## Priority, and why the peek wins: a glance is something the player just
## asked for by holding a key, and the cursor is merely where the mouse
## happens to rest. Answering the deliberate one first is what keeps the
## head from being pulled off a peek by an idle cursor.
##
## [param f] The frame already built for this tick, for its cursor point and
##           speed ratio — rebuilding either here would risk disagreeing
##           with what the follow point was computed against.
func _update_iso_head_look(f: IsometricCameraState.Frame) -> void:
	if not target or not target.has_method(&"set_head_look_point"):
		if not _warned_missing_head_look:
			push_warning("OnFootCameraComponent: target '%s' has no set_head_look_point() — ISOMETRIC head look disabled" % target.name)
			_warned_missing_head_look = true
		return

	# Every branch below produces an ANGLE off the body's facing, never a
	# world point, and the single construction at the bottom turns the
	# winning angle into one. That shape is not tidiness — it is what makes
	# the clamp unbypassable.
	#
	# Handing the cursor's own world point straight to the rig let the head
	# turn a full 360 degrees, and by two separate routes. The obvious one:
	# nothing bounded the angle, so a cursor behind the character asked for
	# a look behind the character. The other is worse and is invisible from
	# here — PlayerAnimationComponent lerps the marker's WORLD POSITION
	# toward the target, so a target that jumps from front to back drags the
	# marker along a straight line THROUGH the character, and as it passes
	# the head the look direction sweeps through every angle on the way. A
	# bounded cone fixes both at once: the target stays in front at a fixed
	# radius, so the interpolation path never comes near the head.
	var offset_deg: Variant = null

	if absf(_iso_manual_look_yaw_deg) > ISO_HEAD_LOOK_PEEK_DEG:
		# The head turns by exactly the angle the camera leaned, measured
		# off the BODY's own facing — deliberately not along
		# _iso.get_cam_forward(), even though the two coincide whenever the
		# camera's base happens to be the character's heading.
		#
		# They no longer always coincide. The base is an octant now, so with
		# no peek at all the camera can sit up to a little over half an
		# octant off the direction the character is actually walking; a head
		# pointed along the camera would be looking somewhere the character
		# is not, and would drift as the octant turned. Measuring off the
		# facing means the head answers only for the glance.
		#
		# Sign is derived, not guessed: facing is (sin r, 0, cos r) and a
		# +offset rotation about UP takes it to (sin(r+o), 0, cos(r+o)),
		# which is exactly what get_cam_forward() produces for the same
		# offset. So the head and the camera lean the same way by
		# construction, and if Q turns out to read inverted in game, the
		# negation in _handle_isometric_look_input() flips both at once —
		# there is nothing to keep in sync here.
		offset_deg = _iso_manual_look_yaw_deg

	elif f.cursor_valid and f.speed_ratio < IsometricCameraState.MOVING_SPEED_THRESHOLD:
		# Only while stopped. On the move the animation clips drive the
		# head, and overriding them mid-stride reads as a broken neck rather
		# than as attention — the same gate PlayerAnimationComponent's own
		# TPS branch applies for the same reason.
		var facing := _target_facing_direction()
		var to_cursor := f.cursor_point - target.global_position
		to_cursor.y = 0.0
		if to_cursor.length() > ISO_HEAD_LOOK_CURSOR_MIN_DISTANCE:
			# Clamped TIGHTER than the glance, deliberately. A glance is
			# something the player is actively holding a key to get; the
			# cursor is merely where the mouse happens to rest, and the head
			# should acknowledge it rather than commit to it. Past the limit
			# the head stops at the edge of its cone and leans that way,
			# which reads as noticing something off to the side — the
			# character is under no obligation to be able to see whatever
			# the mouse is over.
			#
			# Both angles are taken with atan2(x, z), this project's facing
			# convention (+Z forward, see player.gd's get_facing_direction),
			# and differenced with angle_difference so the wrap at +/-PI
			# cannot produce a spurious near-360 offset for a cursor sitting
			# just behind the character.
			#
			# One seam survives and is left alone on purpose: a cursor
			# crossing the line DIRECTLY behind flips the clamped offset
			# from +limit to -limit, because which shoulder to look over is
			# genuinely undefined there. The head then sweeps across the
			# front rather than through itself — the marker's interpolation
			# path is a chord several metres out, nowhere near the head —
			# so this costs a quick glance from one side to the other and
			# nothing worse. Suppressing it would mean remembering a side,
			# which is state, for a case where the character cannot see
			# anything either way.
			offset_deg = clampf(
				rad_to_deg(angle_difference(
					atan2(facing.x, facing.z), atan2(to_cursor.x, to_cursor.z)
				)),
				-iso_head_look_cursor_limit_deg,
				iso_head_look_cursor_limit_deg
			)

	if offset_deg == null:
		target.call(&"clear_head_look_point")
		return

	# The one clamp, applied to whichever branch won. The peek branch is
	# already bounded by iso_look_yaw_limit_deg, but that is an @export a
	# later tuning pass could raise without ever thinking about necks, and
	# this is the line that has to hold regardless of what it is set to.
	var clamped := clampf(
		float(offset_deg), -iso_head_look_limit_deg, iso_head_look_limit_deg
	)
	var direction := _target_facing_direction().rotated(Vector3.UP, deg_to_rad(clamped))
	target.call(
		&"set_head_look_point",
		target.global_position + direction * ISO_HEAD_LOOK_DISTANCE
	)


## Releases the head, if the target has the rig at all. Separate from
## _update_iso_head_look()'s own null branch because the callers that need
## it — a view transition starting, the component being left — have no
## Frame to hand it and should not have to build one just to say "stop".
func _clear_iso_head_look() -> void:
	if target and target.has_method(&"clear_head_look_point"):
		target.call(&"clear_head_look_point")


## Whether the target is standing on something. Optional getter, like
## the metric getters — a target without it is treated as grounded,
## which keeps the vertical channel following instead of freezing.
func _target_on_floor() -> bool:
	if target and target.has_method(&"is_on_floor"):
		return target.is_on_floor()
	return true


## Current click-to-move destination, or ZERO when there is none.
##
## Read from the target rather than from ClickToMoveSystem: the camera
## has no reference to that system and should not acquire one just to
## know where the character is headed.
func _target_move_target() -> Vector3:
	if target and target.has_method(&"get_move_target"):
		return target.get_move_target()
	return Vector3.ZERO


## Feeds the debug overlay, if one is attached. Projection happens here
## rather than in the state so the state stays free of Camera3D.
##
## Both points are projected with the camera as it stood at the END of
## the previous frame — this runs before camera.global_position is
## written. The one-frame lag is accepted: it is far below every damping
## time constant in IsometricCameraState and cannot be seen.
func _push_iso_debug(follow_point: Vector3) -> void:
	if not iso_debug_overlay or not iso_debug_overlay.visible:
		return

	iso_debug_overlay.push(
		camera.unproject_position(follow_point),
		camera.unproject_position(target.global_position),
		_iso
	)


func _update_camera_position(delta):
	match PlayerState.view_mode:
		PlayerState.ViewMode.TPS:
			var yaw_rad = camera_target_yaw
			var pitch_rad = deg_to_rad(_tps_pitch_deg)
			var horizontal_direction = Vector3(sin(yaw_rad), 0, cos(yaw_rad))

			var speed_ratio := _target_speed_ratio()
			_tps_sprint_pullback = lerp(_tps_sprint_pullback, speed_ratio * TPS_SPRINT_PULLBACK, Smoothing.damp_factor(TPS_PULLBACK_SMOOTHING, delta))

			# Dolly: base distance is TPS_DISTANCE, unless aim or lock-on
			# wants a different one — see TpsDistanceSource's comment for
			# the priority between them. Smoothed at whichever rate goes
			# with the winning source, so a push-in never reads as a snap.
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
			_tps_lock_distance = lerp(_tps_lock_distance, base_distance, Smoothing.damp_factor(distance_smoothing, delta))

			var effective_distance := _tps_lock_distance + _tps_sprint_pullback

			var horizontal_distance = effective_distance * cos(pitch_rad)
			var vertical_distance = -effective_distance * sin(pitch_rad)
			var right := Vector3(
				cos(yaw_rad),
				0.0,
				-sin(yaw_rad)
			)

			var shoulder_offset := _shoulder.update(delta)
			var shoulder := right * (shoulder_offset * TPS_SHOULDER_TRANSLATION_RATIO)

			# Lead: pivot drifts ahead of the character's movement direction,
			# not the look direction — keeps this from fighting mouse look.
			var move_direction := _target_horizontal_direction()
			_tps_lead_offset = _tps_lead_offset.lerp(move_direction * speed_ratio * TPS_LEAD_DISTANCE, Smoothing.damp_factor(TPS_LEAD_SMOOTHING, delta))

			# Base pivot: target + pivot height (shoulder level, not ground)
			var pivot_height := _target_metric_height(&"get_shoulder_height", TPS_PIVOT_HEIGHT_FALLBACK)
			var pivot := target.global_position + Vector3(0, pivot_height, 0) + _tps_lead_offset
			var offset = horizontal_direction * horizontal_distance + Vector3(0, vertical_distance, 0) + shoulder

			camera_target_pos = pivot + offset
			camera_target_pitch = _tps_pitch_deg + _tps_pitch_offset_deg

			var aim_offset_scale := aim_shoulder_offset_multiplier if PlayerState.is_aiming else 1.0
			var target_h_offset := shoulder_offset * TPS_SHOULDER_FRUSTUM_RATIO * TPS_SHOULDER_H_OFFSET_SIGN * aim_offset_scale
			camera.h_offset = lerp(camera.h_offset, target_h_offset, Smoothing.damp_factor(8.0, delta))

			# --- Wall & floor avoidance: pull camera in when geometry blocks ---
			# CollisionLayers.CAMERA_OCCLUSION (floor + wall) — deliberately
			# wider than PerceptionComponent's own CollisionLayers.SIGHT
			# (wall only): the camera swings low behind the character and
			# would sink through the deck without floor in the mask. The two
			# used to share one undifferentiated mask; they now diverge on
			# purpose, not by accident.
			var space_state := camera.get_world_3d().direct_space_state
			var occlusion_height := _target_metric_height(&"get_eye_height", TPS_OCCLUSION_HEIGHT_FALLBACK)
			var eye_pos := target.global_position + Vector3(0, occlusion_height, 0)
			var query := PhysicsRayQueryParameters3D.create(eye_pos, camera_target_pos, CollisionLayers.CAMERA_OCCLUSION)
			query.collide_with_areas = false
			var hit := space_state.intersect_ray(query)
			if hit:
				camera_target_pos = hit.position + hit.normal * 0.25

			# Mirror of _decay_tps_state: every ISOMETRIC-only value returns
			# to rest while TPS is active, so neither view can hand a stale
			# offset to the other across a switch.
			_iso.decay(delta)

		_:  # ISOMETRIC
			# The camera orbits a follow point that lags, leads and holds
			# height on its own — not the character's position directly.
			# While the view-mode transition is animating the follow point
			# is bypassed: the transition already animates position, and a
			# dead zone fighting it reads as a stutter.
			var follow_point := target.global_position
			if view_mode_animating:
				_iso.request_reset()
				# The look is a lean on the character's direction, and the
				# character's direction is exactly what a view switch
				# reconsiders. Carrying an offset across would apply it to a
				# base the player never chose it against.
				_iso_manual_look_yaw_deg = 0.0
				# Same argument for the head: whatever it was attending to
				# belongs to a view the player is leaving.
				_clear_iso_head_look()
			else:
				# Order is load-bearing, see IsometricCameraState's header:
				# yaw first, then the basis it implies, then the follow
				# point measured against that basis. Getting this backwards
				# advances the dead zone against last frame's camera plane
				# and shows up as the follow point sliding sideways whenever
				# the camera turns.
				var f := _build_iso_frame()
				_iso.update_orientation(delta, f)
				f.cam_forward = _iso.get_cam_forward()
				f.cam_right = _iso.get_cam_right()
				follow_point = _iso.update(delta, f)
				_update_iso_head_look(f)

				# Copy the authoritative yaw back for the debug labels and
				# for whatever the next view transition reads. Neither is a
				# source any more — this is the sink.
				current_angle = _iso.get_current_yaw()
				target_angle = current_angle

			# Derived AFTER the yaw is settled, which is why this no longer
			# sits at the top of the branch the way it did when
			# current_angle was already final by this point.
			var pitch_rad = deg_to_rad(camera_angle)
			var horizontal_distance = current_zoom_distance * cos(pitch_rad)
			var vertical_distance = -current_zoom_distance * sin(pitch_rad)
			var horizontal_direction = Vector3(sin(current_angle), 0, cos(current_angle))
			var orbit_offset = horizontal_direction * horizontal_distance + Vector3(0, vertical_distance, 0)

			camera_target_pos = follow_point + orbit_offset
			camera_target_pitch = camera_angle
			camera_target_yaw = current_angle

			_decay_tps_state(delta)
			_push_iso_debug(follow_point)

	# Steady-state follow rates are per-view and decoupled from
	# view_transition_speed, so each view's feel and the ISOMETRIC <-> TPS
	# transition animation can be tuned independently.
	#
	# TPS: position at TPS_FOLLOW_SPEED, rotation much faster at
	# TPS_LOOK_SMOOTHING — if rotation lagged as much as position, the
	# target would visibly leave frame on a quick mouse turn (camera body
	# already moved, look direction hasn't caught up).
	#
	# ISOMETRIC: both near-transparent, because IsometricCameraState is the
	# thing that decides how much the camera lags there and a second time
	# constant behind it made its own zone maths untrue. See
	# ISO_FOLLOW_SPEED for the full reasoning — this line is where the bug
	# lived, as a missing branch rather than a wrong number.
	#
	# While the transition animation runs, both still ride
	# view_transition_speed in either view, or the transition itself would
	# jump.
	var position_follow_speed := view_transition_speed
	var rotation_follow_speed := view_transition_speed
	if not view_mode_animating:
		if PlayerState.view_mode == PlayerState.ViewMode.TPS:
			position_follow_speed = TPS_FOLLOW_SPEED
			rotation_follow_speed = TPS_LOOK_SMOOTHING
		else:
			position_follow_speed = ISO_FOLLOW_SPEED
			rotation_follow_speed = ISO_ROTATION_SPEED

	camera_current_pos = camera_current_pos.lerp(camera_target_pos, Smoothing.damp_factor(position_follow_speed, delta))
	if not view_mode_animating:
		camera_current_pitch = lerp(camera_current_pitch, camera_target_pitch, Smoothing.damp_factor(rotation_follow_speed, delta))
	camera_current_yaw = lerp_angle(camera_current_yaw, camera_target_yaw, Smoothing.damp_factor(rotation_follow_speed, delta))

	camera.global_position = camera_current_pos
	camera.global_rotation = Vector3(deg_to_rad(camera_current_pitch), camera_current_yaw, 0)


func _handle_follow_toggle():
	if PlayerState.view_mode == PlayerState.ViewMode.TPS:
		return  # follow isn't toggleable in TPS — it's inherently always on
	if InputSystems.is_toggle_follow_just_pressed():
		follow_player_rotation = !follow_player_rotation
		if follow_player_rotation:
			last_player_rotation = target.rotation.y
			player_rotation_timer = 0.0


func _handle_view_toggle():
	if not InputSystems.is_toggle_view_just_pressed():
		return
	if view_mode_animating:
		return  # a view-mode transition is already running; ignore V until it settles

	match PlayerState.view_mode:
		PlayerState.ViewMode.ISOMETRIC:
			if zoom_animating:
				# V pressed again while auto-zooming to the edge for a pending
				# TPS switch — cancel the intent, don't queue a second one.
				_pending_tps_switch = false
				return
			if is_equal_approx_eps(target_zoom_distance, ISOMETRIC_ZOOM_MIN):
				_transition_to_view(PlayerState.ViewMode.TPS)
			else:
				# Not at the edge yet: drive the existing zoom slider there
				# first (reusing _start_zoom, not a new animation), then
				# switch once _pending_tps_switch is consumed in update().
				# The player pressed V, not the wheel, but the zoom that
				# results is still player-initiated — the HUD ruler must
				# show this phase like any other zoom change.
				zoom_input_received.emit()
				_pending_tps_switch = true
				_start_zoom(ISOMETRIC_ZOOM_MIN - target_zoom_distance)
		PlayerState.ViewMode.TPS:
			# No zoom requirement to exit TPS — V always switches back
			# instantly, and always wins over any pending ISO->TPS intent.
			_pending_tps_switch = false
			_transition_to_view(PlayerState.ViewMode.ISOMETRIC)


func is_equal_approx_eps(a: float, b: float) -> bool:
	return abs(a - b) <= ZOOM_EDGE_EPSILON


## The single point of transition between views. The switch always fires
## right at the edge of the range (see _handle_view_toggle), so no
## ratio-mapping is needed — we just enter the new view at its boundary
## zoom value.
func _transition_to_view(new_view: PlayerState.ViewMode) -> void:
	view_start_distance = current_zoom_distance
	view_start_pitch = camera_current_pitch

	match new_view:
		PlayerState.ViewMode.TPS:
			view_target_distance = TPS_DISTANCE
			view_target_pitch = _tps_pitch_deg

		PlayerState.ViewMode.ISOMETRIC:
			# Coming from TPS — enter at ISO's near edge, already facing the
			# way the character does. Through the same conversion
			# IsometricCameraState._reset_yaw() uses, so the seed and the
			# first directional frame cannot land on different angles. This
			# replaces a hand-written "target.rotation.y + PI": the same
			# value, but derived from the facing vector rather than from a
			# constant that silently encoded this project's +Z-forward
			# convention.
			view_target_distance = ISOMETRIC_ZOOM_MIN
			target_angle = _yaw_facing(_target_facing_direction())
			current_angle = target_angle
			_iso_manual_look_yaw_deg = 0.0
			view_target_pitch = camera_angle

	target_zoom_distance = view_target_distance
	view_anim_time = 0.0
	view_mode_animating = true
	PlayerState.set_view_mode(new_view)

func _handle_shoulder_toggle() -> void:

	if InputSystems.is_switch_shoulder_just_pressed():
		_shoulder.toggle()
		
func _handle_follow_rotation(delta):
	var player_y_rotation = target.rotation.y
	var desired_angle = player_y_rotation + PI

	if abs(player_y_rotation - last_player_rotation) > 0.01:
		player_rotation_timer += delta
		if player_rotation_timer >= follow_rotation_delay:
			if not follow_rotation_animating:
				follow_start_angle = current_angle
				follow_target_angle = desired_angle
				follow_anim_time = 0.0
				follow_rotation_animating = true
				target_angle = desired_angle
		last_player_rotation = player_y_rotation
	else:
		player_rotation_timer = 0.0


func _handle_rotation_input():
	if follow_player_rotation:
		return
	if PlayerState.view_mode == PlayerState.ViewMode.TPS:
		return  # orbit doesn't apply — the camera is locked behind the player
	if InputSystems.is_lean_left_just_pressed():
		_rotate_camera_left()
	elif InputSystems.is_lean_right_just_pressed():
		_rotate_camera_right()


func _rotate_camera_left():
	var idx = ORBITAL_POSITIONS.find(current_position)
	idx = (idx - 1) % ORBITAL_POSITIONS.size()
	if idx < 0: idx = ORBITAL_POSITIONS.size() - 1
	current_position = ORBITAL_POSITIONS[idx]

	orbit_start_angle = current_angle
	orbit_target_angle = POSITION_ANGLES[current_position]
	orbit_anim_time = 0.0
	orbit_rotation_animating = true

	target_angle = orbit_target_angle


func _rotate_camera_right():
	var idx = ORBITAL_POSITIONS.find(current_position)
	idx = (idx + 1) % ORBITAL_POSITIONS.size()
	if idx >= ORBITAL_POSITIONS.size(): idx = 0
	current_position = ORBITAL_POSITIONS[idx]

	orbit_start_angle = current_angle
	orbit_target_angle = POSITION_ANGLES[current_position]
	orbit_anim_time = 0.0
	orbit_rotation_animating = true

	target_angle = orbit_target_angle


func _handle_zoom_input():
	if InputSystems.is_zoom_in_just_released():
		zoom_input_received.emit()
		_start_zoom(-ZOOM_STEP)
	elif InputSystems.is_zoom_out_just_released():
		zoom_input_received.emit()
		_start_zoom(ZOOM_STEP)
		

func _start_zoom(amount: float):
	var min_zoom: float
	var max_zoom: float

	match PlayerState.view_mode:
		PlayerState.ViewMode.TPS:
			return  # zoom disabled in TPS — distance is fixed
		_:
			min_zoom = ISOMETRIC_ZOOM_MIN
			max_zoom = ISOMETRIC_ZOOM_MAX

	var new_distance = clamp(target_zoom_distance + amount, min_zoom, max_zoom)

	if abs(new_distance - target_zoom_distance) > 0.01:
		zoom_start_distance = current_zoom_distance
		target_zoom_distance = new_distance
		zoom_anim_time = 0.0
		zoom_animating = true


func _update_labels():
	if not lbl_current_mode:
		return

	lbl_current_mode.text = "Режим: %s (нажми V для изменения)" % get_current_mode()
	# Q/E no longer step an orbit — they hold a bounded look. The old text
	# is corrected here rather than left for the orbit cleanup: this change
	# is what made it false, so it does not get to outlive this commit.
	if PlayerState.view_mode == PlayerState.ViewMode.TPS:
		lbl_orbital.visible = false
	else:
		lbl_orbital.visible = true
		lbl_orbital.text = "Осмотреться: удерживай Q или E"
	# P is unread since the ISOMETRIC camera became directional — the camera
	# follows the character's direction unconditionally now. Same reason the
	# orbital line above was corrected rather than left to the cleanup.
	lbl_follow.text = "Слежение: направление движения (P не действует)"


func get_current_mode() -> String:
	match PlayerState.view_mode:
		PlayerState.ViewMode.TPS:
			return "TPS"
		_:
			# Not get_current_direction_name(): that reads current_position,
			# which nothing steps any more now that the yaw is directional.
			# It would have kept reporting "North" forever.
			return "Isometric (directional)"


func get_current_direction_name() -> String:
	match current_position:
		OrbitalPosition.NORTH: return "North"
		OrbitalPosition.EAST: return "East"
		OrbitalPosition.SOUTH: return "South"
		OrbitalPosition.WEST: return "West"
		_: return "Unknown"


## Public getter for the lock-on debug overlay
## (ui/debug/stream_debug_panel.gd) — same one-line passthrough pattern as
## camera_follow.gd's get_on_foot_component().
func get_combat_state() -> TpsCombatCameraState:
	return _tps_combat


## Public getter for the HUD widget (zoom ruler) — which distance range
## is current for the active view_mode.
func get_current_zoom_range() -> Vector2:
	match PlayerState.view_mode:
		PlayerState.ViewMode.TPS:
			return Vector2(TPS_ZOOM_MIN, TPS_ZOOM_MAX)
		_:
			return Vector2(ISOMETRIC_ZOOM_MIN, ISOMETRIC_ZOOM_MAX)
