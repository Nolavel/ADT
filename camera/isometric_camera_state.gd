# =============================================================================
# isometric_camera_state.gd
#
# Sub-state of the ON_FOOT camera. Owns the ISOMETRIC follow point and the
# ISOMETRIC yaw, and nothing else.
#
# Responsibilities
# - Dead zone: the follow point does not move while the character stays
#   inside a screen-space rectangle around it
# - Lead: the follow point drifts toward the click destination
# - Vertical channel: follows ground height, not body height
# - Asymmetric damping: eases out of rest slowly, settles quickly
# - Directional yaw: the camera faces where the character is going, or
#   where they are facing once stopped, plus a bounded manual look
#
# TWO CALLS PER FRAME, IN ORDER. update_orientation() first, then the host
# reads get_cam_forward()/get_cam_right() into the Frame, then update().
# The order is not a style preference: the dead zone is measured in the
# camera plane, so a follow point advanced against last frame's basis while
# yaw moved this frame would drift sideways for no reason the player can
# see. One yaw, one basis, one frame.
#
# _current_yaw is the authoritative ISOMETRIC yaw. The host keeps its own
# current_angle in sync afterwards for labels and the view transition, but
# that value never drives orientation again once this state has run for the
# frame — before this existed it was the only source, and two sources is
# what this change removes.
#
# Architecture
# Camera
#
# Dependencies
# - Smoothing
#
# Used By
# - OnFootCameraComponent
#
# Notes
# Does not know about Input, PlayerState or Camera3D. The host fills a
# reusable Frame with everything this needs and reads back a world-space
# follow point. Zoom and view switching stay in the host — they are not
# follow behaviour. So does the manual look INPUT: the host reads the keys
# and clamps the offset, and hands the result over as a number of degrees.
# This file holds no input policy, which is why there is no look limit
# here — see Frame.manual_look_yaw_deg.
#
# Screen-space work is done through values the host derives from the camera
# as it stood at the END of the previous frame, because the camera for this
# frame is not placed until after this runs. The resulting one-frame lag is
# accepted and deliberate: at any plausible frame rate it is far below the
# damping time constants below, so it cannot be seen.
#
# Every value here decays back to rest while TPS is active (see decay()),
# mirroring OnFootCameraComponent._decay_tps_state(). Neither view can leak
# a stale offset into the other by construction.
# =============================================================================

extends RefCounted
class_name IsometricCameraState


# =============================================================================
# FRAME INPUT
# =============================================================================

## Per-frame input, filled by the host. A single instance is reused so this
## does not allocate every frame.
class Frame extends RefCounted:

	## World position of the character.
	var target_position: Vector3 = Vector3.ZERO

	## Horizontal speed as a 0..1 fraction of the current maximum.
	## Read from the target's get_speed_ratio() by the host.
	var speed_ratio: float = 0.0

	## World destination the character is currently moving toward, or ZERO
	## when there is none. With click-to-move the destination is known the
	## moment the player clicks, so the lead aims at it directly instead of
	## extrapolating from velocity.
	var move_target: Vector3 = Vector3.ZERO

	## True while the character is standing on something.
	var on_floor: bool = true

	## True while the character is in the COMBAT stance. Tightens the dead
	## zone and shortens the lead — in combat the player needs to see what
	## is around the character, not where the character is heading.
	var combat: bool = false

	## Horizontal camera-plane basis. Used to express the dead zone in the
	## plane the player actually sees. Filled by the host from
	## get_cam_forward()/get_cam_right() AFTER update_orientation() has run,
	## so the zone and the yaw always agree within one frame — see the file
	## header on why that ordering is load-bearing.
	var cam_right: Vector3 = Vector3.RIGHT
	var cam_forward: Vector3 = Vector3.FORWARD

	## Normalised horizontal direction the camera should face. The host
	## decides what that means — movement direction while moving, character
	## facing once stopped — and this state never asks why. Keeping the
	## choice out here is what lets a future mount, vehicle or cutscene feed
	## a direction of its own without touching the yaw maths below.
	##
	## Expressed as a VECTOR, not an angle, deliberately: this project
	## rotates characters with atan2(dir.x, dir.z), which makes +Z the
	## visual forward rather than Godot's usual -Z (see
	## player.gd's get_facing_direction()). A raw rotation.y crossing this
	## boundary would carry that convention silently; a direction vector
	## cannot be misread.
	var target_forward: Vector3 = Vector3.FORWARD

	## Temporary manual look offset in degrees, ALREADY CLAMPED by the host.
	## There is deliberately no limit constant in this file to clamp it
	## against: the limit belongs where the input is read, and a second copy
	## here would either duplicate the policy or sit unused and lie about
	## being enforced.
	var manual_look_yaw_deg: float = 0.0

	## How many world units one screen pixel covers at the character's
	## distance. Derived by the host from FOV, zoom distance and viewport
	## height, which is what makes the dead zone scale with zoom without
	## any zoom-specific code in here.
	var world_per_pixel: float = 0.01

	## Viewport size in pixels, for converting zone fractions to pixels.
	var viewport_size: Vector2 = Vector2(1920, 1080)


# =============================================================================
# DEAD ZONE
# =============================================================================

## Dead zone half-extents as a fraction of viewport size. The character can
## drift this far from the follow point before the camera reacts at all.
## Wider than tall on purpose: horizontal drift reads as headroom, vertical
## drift reads as the camera losing the character.
##
## @export rather than const — this is an eye-by-feel framing value, not an
## implementation detail (same reasoning as TpsCombatCameraState's spring
## constants). Was 0.12/0.08; shrunk to roughly half. At the old size the
## character could cross nearly a quarter of the screen width before the
## follow point reacted at all, which read as the camera being unhooked
## from the character rather than deliberately lagging it — the lag IS the
## point (see FOLLOW_RATE_MOVING's own comment), but a dead zone this size
## hid the lag behind a flat non-reaction instead.
@export var dead_zone_x: float = 0.07
@export var dead_zone_y: float = 0.045

## Dead zone in COMBAT. Tighter, so the character stays near the centre of
## the frame while the player is watching for threats.
const DEAD_ZONE_COMBAT_X: float = 0.05
const DEAD_ZONE_COMBAT_Y: float = 0.04

## Outer edge of the soft zone, again as a fraction of viewport size.
## Between the dead zone and this, the camera catches up under damping.
const SOFT_ZONE_X: float = 0.30
const SOFT_ZONE_Y: float = 0.22

## Hard limit. The character is never allowed past this — the follow point
## is snapped, not damped. Exists for teleports, spawns and long falls,
## where damping alone would let the character leave the screen for
## several seconds.
const HARD_ZONE_X: float = 0.42
const HARD_ZONE_Y: float = 0.34

## How fast the dead-zone rectangle itself resizes when the stance changes.
## Slow enough to read as the camera reconsidering, fast enough not to lag
## behind the stance switch.
const ZONE_RESIZE_RATE: float = 6.0


# =============================================================================
# DAMPING
# =============================================================================

## Catch-up rate while the character is moving away from the follow point.
## Deliberately slow: the lag is the point. The camera should read as being
## dragged along rather than bolted to the character.
const FOLLOW_RATE_MOVING: float = 3.5

## Catch-up rate once the character has stopped. Faster, and applied to a
## shrinking error, so the camera settles instead of coasting past and
## drifting back. The asymmetry between this and FOLLOW_RATE_MOVING is what
## makes starts feel heavy and stops feel clean.
const FOLLOW_RATE_SETTLING: float = 9.0

## Speed ratio below which the character counts as stopped for the purpose
## of choosing between the two rates above.
const SETTLING_SPEED_THRESHOLD: float = 0.05


# =============================================================================
# LEAD
# =============================================================================

## Maximum world-space lead toward the move destination at full speed.
## Not proportional to anything — this is framing, tuned by eye.
const LEAD_DISTANCE: float = 3.2

## Lead in COMBAT. Shorter: leaning ahead is the wrong instinct in a fight.
const LEAD_DISTANCE_COMBAT: float = 1.0

## How far along the path to the destination the lead is allowed to reach.
## Without this, a click two metres away would produce the same lead as a
## click fifty metres away, and short moves would overshoot their own
## destination.
const LEAD_DESTINATION_FRACTION: float = 0.35

## Lead easing rate. Much slower than the follow rate on purpose: the lead
## should drift in over about a second, not snap the moment a click lands.
## Slow easing is also what keeps a rapid change of destination from
## throwing the camera side to side.
const LEAD_RATE: float = 1.8


# =============================================================================
# VERTICAL CHANNEL
# =============================================================================

## Rate at which the tracked ground height follows the character while they
## are on the floor. Much slower than horizontal follow, so stairs and
## kerbs do not pump the camera up and down in step with the character.
const GROUND_RATE: float = 2.5

## Rate used once a fall has been going on long enough to count as a real
## fall rather than a jump (see FALL_GRACE). Fast, so the camera does not
## let the character drop off the bottom of the screen.
const GROUND_RATE_FALLING: float = 8.0

## How long the character may be airborne before the vertical channel stops
## holding still and starts chasing. Below this, a jump reads as a jump:
## the character rises in frame and the world stays put. Above it, the
## character is falling down the terrain and the camera has to follow.
const FALL_GRACE: float = 0.55


# =============================================================================
# DIRECTIONAL ORIENTATION
# =============================================================================

## How fast the camera yaw chases the character's direction while they are
## moving. Slow enough that a change of direction reads as the camera
## swinging round to follow, not as the world snapping — the same "the lag
## is the point" reasoning as FOLLOW_RATE_MOVING, applied to rotation.
##
## @export rather than const, like dead_zone_x/y and for the same reason:
## this is a framing value tuned by eye, not an implementation detail.
@export var follow_yaw_rate: float = 4.0

## How fast the yaw returns to the character's facing once they have
## stopped. Slower than follow_yaw_rate on purpose. While moving, the
## direction the camera is chasing is the one the player chose a moment ago,
## so catching up is welcome; standing still, the only thing left to chase
## is the character turning on the spot, and matching that quickly would
## make every idle fidget swing the whole view.
@export var recenter_yaw_rate: float = 2.2

## Speed ratio above which the character counts as moving for the purpose of
## choosing between the two rates above. Deliberately the same threshold
## SETTLING_SPEED_THRESHOLD uses for the follow point: yaw and position
## should agree on when a character has stopped, and two nearly-equal
## constants would drift apart the first time either was retuned.
const MOVING_SPEED_THRESHOLD: float = SETTLING_SPEED_THRESHOLD


# =============================================================================
# DECAY
# =============================================================================

## Rate at which every ISOMETRIC-only value returns to rest while TPS is
## active. Mirrors the decay of the TPS-only values while ISOMETRIC is
## active. Values decay rather than freeze so that neither view can hand a
## stale offset to the other across a switch.
const DECAY_RATE: float = 4.0


# =============================================================================
# STATE
# =============================================================================

## Follow point in world space — the value the host reads back. Not the
## character's position: it lags, leads and holds height independently.
var follow_point: Vector3 = Vector3.ZERO

## Smoothed lead offset, horizontal only.
var _lead_offset: Vector3 = Vector3.ZERO

## Tracked ground height. Updated while the character is on the floor, held
## while airborne, chased once a fall passes FALL_GRACE.
var _ground_height: float = 0.0

## Seconds the character has been continuously airborne.
var _air_time: float = 0.0

## Current dead-zone half-extents in viewport fractions, eased toward the
## stance-appropriate constants so a stance change does not resize the
## rectangle instantly.
var _zone_x: float = dead_zone_x
var _zone_y: float = dead_zone_y

## True until the first update() after a reset was requested, so the follow
## point can be placed on the character instead of easing in from wherever
## it was left. Cleared by reset().
var _needs_reset: bool = true

## The same, for the yaw channel, and deliberately a SECOND flag rather than
## a second reader of the one above.
##
## The two resets are cleared by different methods — reset() from update(),
## _reset_yaw() from update_orientation() — so one shared flag would make
## each channel's reset depend on the OTHER channel's call also happening.
## Today they are always called as a pair, so a shared flag would work and
## would keep working right up until some caller ran orientation alone: the
## flag would never clear, update_orientation() would take the reset path
## every frame, and the yaw would silently pin to the character's direction
## with the manual look doing nothing at all. Found exactly that way, by a
## harness that drove update_orientation() without update().
##
## Each channel clearing its own flag costs one bool and removes the
## coupling outright.
var _needs_yaw_reset: bool = true

## Yaw the character's own direction asks for, before the manual look.
var _base_yaw: float = 0.0

## _base_yaw plus the host's clamped manual offset — where the camera is
## heading this frame.
var _target_yaw: float = 0.0

## The smoothed, authoritative ISOMETRIC yaw. Everything the host derives
## for ISOMETRIC — camera placement, camera_target_yaw, the dead-zone basis
## — comes from this value and nothing else.
var _current_yaw: float = 0.0

## Last computed screen-space error, in pixels, kept only so the debug
## overlay can draw what the state actually decided rather than
## recomputing it and possibly disagreeing.
var debug_error_px: Vector2 = Vector2.ZERO
var debug_zone_px: Vector2 = Vector2.ZERO
var debug_soft_px: Vector2 = Vector2.ZERO
var debug_hard_px: Vector2 = Vector2.ZERO
var debug_settling: bool = false
var debug_hard_clamped: bool = false


# =============================================================================
# PUBLIC API
# =============================================================================

## Places the follow point on the character without easing. Called by the
## host when ISOMETRIC becomes active, so the camera does not sweep in from
## a stale position left over from TPS.
## Yaw is deliberately NOT touched here. reset() answers "where is the
## follow point", and orientation is reset on its own path
## (update_orientation() -> _reset_yaw()) because only that path has a Frame
## to read a direction out of. Keeping the two apart is what lets this stay
## a position-only call that a host can make with nothing but a Vector3.
func reset(target_position: Vector3) -> void:
	follow_point = target_position
	_ground_height = target_position.y
	_lead_offset = Vector3.ZERO
	_air_time = 0.0
	_needs_reset = false


## Marks the state as needing a reset on the next update. Used when the
## host does not have a target position to hand yet — and, since this is the
## only route that also reaches _reset_yaw(), the way a host should ALWAYS
## ask for a reset when a Frame is about to be built anyway. See
## _needs_reset's own comment.
func request_reset() -> void:
	_needs_reset = true
	_needs_yaw_reset = true


## Advances the directional yaw one frame. Must be called BEFORE the host
## fills Frame.cam_forward/cam_right and before update() — see the file
## header for why the order matters.
##
## [param delta] Frame delta.
## [param f] Frame input; reads target_forward, manual_look_yaw_deg and
##           speed_ratio only.
func update_orientation(delta: float, f: Frame) -> void:
	if _needs_yaw_reset:
		_reset_yaw(f)
	else:
		_update_yaw(delta, f)


## The authoritative ISOMETRIC yaw for this frame.
func get_current_yaw() -> float:
	return _current_yaw


## Horizontal direction the camera looks along the ground, from the current
## yaw. Matches the host's own camera placement by construction: it puts the
## camera at follow_point + (sin y, 0, cos y) * distance and sets its
## rotation.y to the same y, so the way it faces is the negation of that
## offset.
func get_cam_forward() -> Vector3:
	return Vector3(-sin(_current_yaw), 0.0, -cos(_current_yaw))


## Ninety degrees clockwise from get_cam_forward(), in the ground plane.
func get_cam_right() -> Vector3:
	return Vector3(cos(_current_yaw), 0.0, -sin(_current_yaw))


## Advances one frame and returns the world-space follow point.
##
## [param delta] Frame delta.
## [param f] Frame input, filled by the host.
## [return] Point the camera should orbit around this frame.
func update(delta: float, f: Frame) -> Vector3:

	if _needs_reset:
		reset(f.target_position)
		# Deliberately no early return. The reset frame runs the same zone,
		# lead and ground code every other frame runs — with a zero error,
		# so it changes nothing — rather than being a special case that has
		# to be kept in step with the ordinary path by hand.

	_update_zone_size(delta, f.combat)
	_update_lead(delta, f)
	_update_ground(delta, f)

	var desired := _desired_point(f)
	_apply_zones(delta, f, desired)

	return follow_point


## Returns every ISOMETRIC-only value toward rest. Called by the host every
## frame while TPS is active, so nothing here can survive a round trip
## through the other view.
##
## [param delta] Frame delta.
func decay(delta: float) -> void:
	var k := Smoothing.damp_factor(DECAY_RATE, delta)
	_lead_offset = _lead_offset.lerp(Vector3.ZERO, k)
	_zone_x = lerp(_zone_x, dead_zone_x, k)
	_zone_y = lerp(_zone_y, dead_zone_y, k)
	_air_time = 0.0
	# Yaw is not eased back here the way the offsets above are. There is
	# nothing to ease toward: the yaw a returning ISOMETRIC frame wants
	# depends on where the character is facing at that moment, which is not
	# knowable from a TPS frame. Setting _needs_reset instead makes the
	# first ISOMETRIC frame snap it to the real direction through
	# update_orientation() -> _reset_yaw(), which is also what stops a stale
	# TPS-era yaw from leaking back in.
	_needs_reset = true
	_needs_yaw_reset = true


# =============================================================================
# INTERNAL
# =============================================================================

## Snaps the yaw straight onto the character's direction, with no easing.
## Used on the first frame of a fresh ISOMETRIC stretch (entering ON_FOOT,
## coming back from TPS, finishing a view transition), where there is no
## previous yaw worth easing from — whatever _current_yaw holds is left over
## from a view the player is no longer in.
func _reset_yaw(f: Frame) -> void:
	_base_yaw = _yaw_from_forward(f.target_forward)
	_target_yaw = _base_yaw
	_current_yaw = _base_yaw
	_needs_yaw_reset = false


## Eases the yaw toward the character's direction plus the manual look.
##
## The manual offset is added to the BASE rather than held as a separate
## smoothed channel: it is a temporary lean on top of wherever the character
## is heading, so when they turn while the player is looking aside, the look
## turns with them instead of staying pinned to a compass bearing.
func _update_yaw(delta: float, f: Frame) -> void:
	_base_yaw = _yaw_from_forward(f.target_forward)
	_target_yaw = _base_yaw + deg_to_rad(f.manual_look_yaw_deg)

	var rate := follow_yaw_rate if f.speed_ratio > MOVING_SPEED_THRESHOLD else recenter_yaw_rate
	_current_yaw = lerp_angle(_current_yaw, _target_yaw, Smoothing.damp_factor(rate, delta))


## Camera yaw that makes get_cam_forward() equal the given direction.
##
## Inverse of get_cam_forward()'s own (-sin, -cos) form, which is why the
## arguments are negated. A degenerate direction falls back to FORWARD
## rather than producing a NaN yaw that would poison every later frame —
## atan2(0, 0) is defined, but the direction it implies is not.
func _yaw_from_forward(forward: Vector3) -> float:
	var fwd := forward
	fwd.y = 0.0
	if fwd.length_squared() < 0.0001:
		fwd = Vector3.FORWARD
	return atan2(-fwd.x, -fwd.z)


## Eases the dead-zone rectangle toward the size the current stance asks
## for. Resizing rather than switching keeps a stance change from snapping
## the camera when the character happens to be off-centre at the time.
func _update_zone_size(delta: float, combat: bool) -> void:
	var want_x := DEAD_ZONE_COMBAT_X if combat else dead_zone_x
	var want_y := DEAD_ZONE_COMBAT_Y if combat else dead_zone_y
	var k := Smoothing.damp_factor(ZONE_RESIZE_RATE, delta)
	_zone_x = lerp(_zone_x, want_x, k)
	_zone_y = lerp(_zone_y, want_y, k)


## Eases the lead offset toward a point ahead of the character on the way
## to its destination.
##
## The lead aims at the known destination rather than at the velocity
## vector. With click-to-move the destination is known before the character
## has taken a step, so leading by velocity would waste the first moment of
## every move — exactly the moment the lead exists to cover.
func _update_lead(delta: float, f: Frame) -> void:
	var want := Vector3.ZERO

	if f.move_target != Vector3.ZERO and f.speed_ratio > 0.0:
		var to_target := f.move_target - f.target_position
		to_target.y = 0.0
		var distance := to_target.length()

		if distance > 0.01:
			var max_lead := LEAD_DISTANCE_COMBAT if f.combat else LEAD_DISTANCE
			# Never lead further than a fraction of the way there, so a
			# short move does not push the follow point past its own
			# destination.
			var reach: float = min(max_lead * f.speed_ratio, distance * LEAD_DESTINATION_FRACTION)
			want = to_target.normalized() * reach

	_lead_offset = _lead_offset.lerp(want, Smoothing.damp_factor(LEAD_RATE, delta))


## Updates the tracked ground height.
##
## While the character is on the floor this follows their height slowly.
## While airborne it holds still, so a jump reads as the character leaving
## the ground rather than the world sinking. Once a fall outlasts
## FALL_GRACE it is no longer a jump, and the height chases quickly so the
## character cannot drop off the bottom of the screen — the case that
## matters when falling down a slope.
func _update_ground(delta: float, f: Frame) -> void:
	if f.on_floor:
		_air_time = 0.0
		_ground_height = lerp(_ground_height, f.target_position.y, Smoothing.damp_factor(GROUND_RATE, delta))
		return

	_air_time += delta

	if _air_time > FALL_GRACE:
		_ground_height = lerp(_ground_height, f.target_position.y, Smoothing.damp_factor(GROUND_RATE_FALLING, delta))


## The point the follow point would sit on if there were no dead zone:
## the character, plus the lead, at tracked ground height rather than body
## height.
func _desired_point(f: Frame) -> Vector3:
	var p := f.target_position + _lead_offset
	p.y = _ground_height
	return p


## Applies the three zones to the horizontal follow point.
##
## Inside the dead zone nothing happens at all — this is the whole point of
## the mechanism, and damping toward the target "just a little" would
## defeat it. Between the dead zone and the soft edge the follow point
## catches up under damping, and only by the amount that exceeds the dead
## zone, so the character stays parked at the zone boundary instead of
## being pulled back to centre. Past the hard limit the excess is removed
## outright.
func _apply_zones(delta: float, f: Frame, desired: Vector3) -> void:

	# Vertical channel is not subject to the zones — it has its own damping
	# in _update_ground, and letting the dead zone hold it as well would
	# make the camera lag a fall twice over.
	follow_point.y = desired.y

	var error := desired - follow_point
	error.y = 0.0

	# Express the error in the plane the player sees, then in pixels, so
	# the zones mean the same thing at any zoom and any orbit angle.
	var error_right := error.dot(f.cam_right)
	var error_forward := error.dot(f.cam_forward)

	var px_per_world := 1.0 / maxf(f.world_per_pixel, 0.00001)
	var error_px := Vector2(error_right, error_forward) * px_per_world

	var zone_px := Vector2(_zone_x, _zone_y) * f.viewport_size
	var hard_px := Vector2(HARD_ZONE_X, HARD_ZONE_Y) * f.viewport_size

	debug_error_px = error_px
	debug_zone_px = zone_px
	debug_soft_px = Vector2(SOFT_ZONE_X, SOFT_ZONE_Y) * f.viewport_size
	debug_hard_px = hard_px

	# Only the part of the error that sticks out of the dead zone is worth
	# reacting to.
	var excess_px := Vector2(
		_excess(error_px.x, zone_px.x),
		_excess(error_px.y, zone_px.y)
	)

	debug_settling = f.speed_ratio < SETTLING_SPEED_THRESHOLD
	debug_hard_clamped = false

	if excess_px == Vector2.ZERO:
		return

	var rate := FOLLOW_RATE_SETTLING if debug_settling else FOLLOW_RATE_MOVING
	var k := Smoothing.damp_factor(rate, delta)

	var move_px := excess_px * k

	# Hard limit: whatever damping did not cover, take outright. Without
	# this a teleport or a long fall would leave the character off screen
	# for as long as the damping takes to catch up.
	var hard_excess_px := Vector2(
		_excess(error_px.x, hard_px.x),
		_excess(error_px.y, hard_px.y)
	)
	if hard_excess_px != Vector2.ZERO:
		debug_hard_clamped = true
		move_px.x = _max_abs(move_px.x, hard_excess_px.x)
		move_px.y = _max_abs(move_px.y, hard_excess_px.y)

	var move_world := move_px * f.world_per_pixel
	follow_point += f.cam_right * move_world.x + f.cam_forward * move_world.y


## How far a value sticks out past a symmetric limit, keeping its sign.
## Zero while inside.
func _excess(value: float, limit: float) -> float:
	if value > limit:
		return value - limit
	if value < -limit:
		return value + limit
	return 0.0


## Whichever of two same-signed values has the larger magnitude.
func _max_abs(a: float, b: float) -> float:
	return a if absf(a) > absf(b) else b
