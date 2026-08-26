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
# - Cursor bias: the follow point leans a bounded amount toward the point
#   the player is pointing at
# - Vertical channel: follows ground height, not body height
# - Asymmetric damping: eases out of rest slowly, settles quickly
# - Octant yaw: the camera faces one of eight fixed compass headings,
#   chosen by where the character is going, plus a bounded manual look
#
# THE CAMERA IS THE ONLY THING THAT LAGS. Everything here is measured
# against follow_point, so follow_point must be where the camera actually
# is. The host used to run a SECOND smoothing pass over the value this
# returns, which made every zone and every rate in this file mean something
# other than what it says — the hard zone in particular could not clamp
# anything, because the point it clamped was not the point the camera sat
# on. OnFootCameraComponent now runs its own pass fast enough to be a
# pass-through in ISOMETRIC. Do not reintroduce a second time constant on
# this path.
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
# WHY OCTANTS AND NOT A CONTINUOUS FOLLOW. The first directional version
# chased the character's heading with exponential damping, and it read as
# the world rotating around the player rather than the camera turning to
# look. Two properties of that shape cause it, and both are structural
# rather than a matter of picking better rates:
#
# - Exponential damping never arrives. Its tail is small but never zero, so
#   there is always some rotation on screen, and a scene that is always
#   rotating slightly is a scene the player cannot use as a frame of
#   reference.
# - Every heading change produced some rotation, so walking a zigzag street
#   swung the view continuously in both directions.
#
# The octant model inverts both. The yaw is one of eight fixed headings and
# is therefore STILL by default; a change of heading produces a turn only
# once it is unambiguous (see the hysteresis and dwell below), and that
# turn is a fixed-duration eased move that finishes and stops. Between
# turns the world is a rigid backdrop, which is the property that makes
# streets and buildings usable as landmarks.
#
# Standing still never turns the camera at all — see _update_octant().
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

	## How much of a metre a metre is, on screen, when it points away from
	## the camera along the ground.
	##
	## sin(|camera pitch|). The camera looks down at the world, so ground
	## distance running away from it is foreshortened, while ground distance
	## running across it is not. At the host's -35 degrees the factor is
	## about 0.57: the same metre covers only 57% as much screen going up
	## the frame as it does going across it.
	##
	## Without this, _apply_zones() converted both axes with the same
	## world_per_pixel and dead_zone_y silently behaved as though it were
	## 1.75x its stated value — which is exactly the "I click near the top
	## of the screen and the camera will not follow" complaint. The host
	## supplies it because the pitch belongs to the host; this state has
	## never known which way the camera is tilted and does not need to
	## start.
	var forward_screen_scale: float = 1.0

	## Ground point the player is pointing at, valid only while
	## cursor_valid. World space, at roughly the follow point's height —
	## the host derives it by intersecting the cursor ray with a horizontal
	## plane, NOT by a physics raycast, so it cannot jump discontinuously
	## when the cursor crosses a rooftop edge. See the host's own comment
	## for why a jump there would be visible.
	var cursor_point: Vector3 = Vector3.ZERO

	## False when the cursor ray does not produce a usable ground point —
	## near the horizon it is almost parallel to the ground plane and the
	## intersection runs away to infinity. A separate flag rather than a
	## sentinel Vector3 for the same reason ClickToMoveSystem.raycast_
	## ground_point() returns null: Vector3 has no "no point" value.
	var cursor_valid: bool = false

	## How strongly the cursor's position ON SCREEN is asking for room, 0
	## to 1, derived by the host from distance to the screen edge. Zero
	## through the neutral middle of the screen, ramping to 1 at the very
	## edge.
	##
	## Separated from cursor_point so the two carry one thing each: the
	## point says WHERE the player is pointing, this says HOW MUCH they are
	## asking. Before this existed the bias was proportional to plain
	## distance from the character, which meant the frame drifted whenever
	## the mouse rested anywhere off to one side — including while the
	## player was simply reading the screen. A cursor in the middle now
	## moves nothing at all.
	var cursor_edge_weight: float = 0.0


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
## constants). Was 0.12/0.08, then 0.07/0.045, now 0.05/0.03. At the first
## size the character could cross nearly a quarter of the screen width
## before the follow point reacted at all, which read as the camera being
## unhooked from the character rather than deliberately lagging it — the lag
## IS the point (see FOLLOW_RATE_MOVING's own comment), but a dead zone
## that size hid the lag behind a flat non-reaction instead.
##
## The second shrink went most of the way and was still not felt, because
## the vertical number was not doing what it said: _apply_zones() measured
## the forward axis in the wrong plane, so 0.045 behaved as roughly 0.079.
## Frame.forward_screen_scale fixes the measurement, and these values are
## sized against the corrected one — do not read them as another blind
## halving of the same number.
@export var dead_zone_x: float = 0.05
@export var dead_zone_y: float = 0.03

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
##
## Raised from 3.5 when the host's second smoothing pass was opened up. That
## pass added a time constant of its own, so the real lag was never this
## rate alone — at run_speed 15.5 the two together trailed by about 8.3 m,
## against a LEAD_DISTANCE of 3.2 m sized as though for one of them. The
## host's pass is now fast enough to be near-transparent
## (OnFootCameraComponent.ISO_FOLLOW_SPEED), so at 6.0 the two together
## trail by roughly 3.1 m — which the 3.2 m lead genuinely cancels, leaving
## the character near the middle of the frame during a run instead of
## riding the top of it.
const FOLLOW_RATE_MOVING: float = 6.0

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
# CURSOR BIAS
# =============================================================================
#
# The frame leans toward whatever the player is pointing at. Borrowed from
# the twin-stick and click-to-move cameras that get praised for
# responsiveness (Hades is the clearest example): the camera answers "show
# me what I am about to act on" by TRANSLATING, which costs nothing in
# orientation, instead of by rotating, which costs the player their frame of
# reference.
#
# In this project the cursor is free information. ISOMETRIC leaves it
# visible because click-to-move needs it (see InputSystems._apply_mouse_
# mode()), so the player's intent is on screen at all times and a full
# second before the click lands. Reading it here is what makes the camera
# respond to aiming rather than only to having already moved.
#
# GATED ON THE SCREEN EDGE, not on plain distance from the character. The
# mouse is not only a pointing device here — it is also where the player's
# hand rests while they read the screen — so a bias that grew with mere
# distance from the character made the frame drift for no expressed reason.
# Asking how close the cursor is to leaving the screen asks something the
# player actually means: they are looking at the boundary of what they can
# see, so they want more of that side. Through the middle of the screen
# this channel now contributes exactly nothing. See Frame.cursor_edge_weight
# and the host's _cursor_edge_weight().

## Largest cursor-driven offset, in world units. Small on purpose: this is
## a lean, and past a couple of metres it stops reading as the frame
## accommodating the player and starts reading as the camera wandering off
## on its own.
##
## 2.5 -> 2.9 -> 3.4, both times deliberately short of the 50% that would
## make the reading obvious. The line this must stay on the right side of is
## "the camera took some interest in where I pointed" versus "the camera is
## trying to look at my cursor", and in Blackrock's dense streets the second
## one costs the player the character's own surroundings. Only the cap has
## ever moved; CURSOR_BIAS_FRACTION is untouched, so a cursor near the
## character still produces almost nothing and the change is felt only at
## range.
const CURSOR_BIAS_DISTANCE: float = 3.4

## Fraction of the distance to the cursor to actually lean by, before the
## cap above. Keeps a cursor resting just off the character from producing
## the same offset as one across the street — near the character the bias
## should be near zero, or every small mouse movement nudges the frame.
const CURSOR_BIAS_FRACTION: float = 0.25

## Easing rate for the bias. Slower than the follow rate and close to
## LEAD_RATE, and for the same reason: a cursor can cross the screen in a
## single frame, and anything that tracked it quickly would make the frame
## twitch every time the player moved the mouse to click.
const CURSOR_BIAS_RATE: float = 3.0


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

## How many fixed headings the yaw is allowed to take. Eight, 45 degrees
## apart, aligned so index 0 is the yaw a FORWARD-facing character asks for.
##
## Eight rather than four because four leaves a diagonal run permanently
## framed off-axis, and rather than sixteen because at 22.5 degrees apart
## the turns stop being individually legible and the model degenerates back
## into the continuous follow it replaced.
const SNAP_COUNT: int = 8

## Angular width of one octant. Derived, never typed twice.
const SNAP_STEP: float = TAU / float(SNAP_COUNT)

## How far past the boundary between two octants the character's heading
## must go before the far one is even considered.
##
## The boundary sits at SNAP_STEP/2 (22.5 degrees) from the current octant's
## centre, so this adds to that: at 12 degrees the heading has to reach
## about 34.5 degrees off centre, three quarters of the way to the next
## octant's own centre. That band is what makes a zigzag street hold still
## — without it, a heading wobbling either side of a boundary would flip the
## camera back and forth, which is worse than the continuous rotation this
## model exists to remove.
##
## @export rather than const, like dead_zone_x/y and for the same reason:
## a framing value tuned by eye, not an implementation detail. Raise it if
## turns feel trigger-happy.
@export var snap_hysteresis_deg: float = 12.0

## How long the new octant must stay the answer before the turn commits.
##
## Second gate, and it catches what the hysteresis cannot: a heading that
## sweeps cleanly through a wide arc — rounding a corner, or the first
## moment of a click-to-move path while the velocity vector is still
## settling — passes any angular threshold instantly. Requiring the answer
## to be STABLE for a moment is what distinguishes "the player has changed
## direction" from "the player is passing through this direction".
@export var snap_dwell: float = 0.3

## How long a ONE-OCTANT turn takes, in seconds. Larger turns take longer —
## see _turn_duration_for().
##
## A fixed duration with an ease, deliberately NOT exponential damping like
## every other channel in this file. Exponential damping has an infinite
## tail: it is always still turning a little, and a view that is always
## turning a little is the exact sensation this model was written to
## remove. A turn has to arrive and stop, so that the time between turns is
## genuinely still.
@export var snap_turn_duration: float = 0.25

## How much of a turn is spent accelerating and decelerating, either end,
## for the SMALLEST turn and for a full reversal. The turn's character, as
## opposed to its length, which snap_turn_duration owns.
##
## The velocity profile is a trapezoid with smootherstep corners: it ramps
## up over this fraction of the duration, holds, and ramps down over the
## same fraction at the far end. Because the area under it is fixed — the
## turn covers its angle in its duration whatever shape it takes — the
## plateau height is 1/(1-ramp), so a SMALLER ramp means a flatter, slower
## peak and a LARGER one means a taller, more pointed one.
##
## That fixed area is the whole reason this parameter exists rather than a
## gentler curve. At a fixed duration and angle the average angular speed is
## already decided, and every curve's peak is at least the average, so
## "less aggressive" can only mean "lower peak" — which means flatter, not
## rounder. A higher-order ease has softer ends and a HIGHER peak, the
## opposite of what a small turn wants.
##
## TURN_RAMP_LARGE is the value at which the profile matches the plain
## smootherstep this replaced (peak 1.875x average), so a reversal keeps
## exactly the decisive character it had. Small turns flatten from there.
## Measured peak angular speed, against the previous curve at the same
## durations: 45 deg 265 deg/s (was 337), 90 deg 403 (was 476), 135 deg 536
## (was 585), 180 deg 675 (was 675).
const TURN_RAMP_SMALL: float = 0.32
const TURN_RAMP_LARGE: float = 0.467

## Speed ratio above which the character counts as moving for the purpose of
## reconsidering the octant. Deliberately the same threshold
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

## Smoothed cursor bias offset, horizontal only. Kept apart from
## _lead_offset rather than summed into it because the two answer different
## questions — where the character is going versus where the player is
## looking — and are eased at different rates. They are added together only
## at the point of use, in _desired_point().
var _cursor_offset: Vector3 = Vector3.ZERO

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

## Which of the SNAP_COUNT headings the camera is committed to. The whole
## point of the model: this is an integer, so between turns there is nothing
## for the yaw to drift toward.
var _snap_index: int = 0

## Octant the heading currently argues for while it differs from
## _snap_index, and how long it has argued for it. -1 means no argument in
## progress. Cleared the moment the heading agrees with _snap_index again,
## so a wobble that crosses the threshold and comes back does not bank
## progress toward a turn it no longer wants.
var _candidate_index: int = -1
var _candidate_time: float = 0.0

## The committed turn in flight: where it started, where it ends, how long
## this particular turn was given (see _turn_duration_for(), which scales it
## with the size of the step), and how far through that it is. _turn_t >=
## 1.0 means no turn is running and _base_yaw simply holds _turn_to.
var _turn_from: float = 0.0
var _turn_to: float = 0.0
var _turn_duration: float = 0.25
var _turn_ramp: float = TURN_RAMP_SMALL
var _turn_t: float = 1.0

## Yaw of the committed octant, mid-turn included, before the manual look.
var _base_yaw: float = 0.0

## _base_yaw plus the host's clamped manual offset — where the camera is
## heading this frame.
var _target_yaw: float = 0.0

## The authoritative ISOMETRIC yaw. Everything the host derives for
## ISOMETRIC — camera placement, camera_target_yaw, the dead-zone basis —
## comes from this value and nothing else.
##
## Equal to _target_yaw exactly: the two smoothed channels feeding it (the
## eased turn, and the host's own spring on the manual look) have already
## done their smoothing by the time it is assembled, and running a third
## filter over the sum would put the infinite tail back that the fixed-
## duration turn exists to avoid.
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
	_cursor_offset = Vector3.ZERO
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
		return

	_update_octant(delta, f)
	_advance_turn(delta)

	# The manual look is added to the OCTANT rather than held as a separate
	# smoothed channel, and the octant is the reason it now works properly:
	# a lean is only readable against something that holds still, and before
	# this the base it leaned on was itself rotating.
	_target_yaw = _base_yaw + deg_to_rad(f.manual_look_yaw_deg)
	_current_yaw = _target_yaw


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
	_update_cursor_bias(delta, f)
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
	_cursor_offset = _cursor_offset.lerp(Vector3.ZERO, k)
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
	_snap_index = _octant_of(_yaw_from_forward(f.target_forward))
	_candidate_index = -1
	_candidate_time = 0.0
	_base_yaw = _yaw_of_octant(_snap_index)
	_turn_from = _base_yaw
	_turn_to = _base_yaw
	_turn_duration = snap_turn_duration
	_turn_ramp = TURN_RAMP_SMALL
	_turn_t = 1.0
	_target_yaw = _base_yaw
	_current_yaw = _base_yaw
	_needs_yaw_reset = false


## Decides whether the committed octant should change, and starts a turn if
## it should.
##
## Three gates, in order, and each removes a case the previous one cannot:
##
## 1. The character must be MOVING. Standing still, the only thing a
##    heading can report is the character turning on the spot, and turning
##    on the spot is precisely what must not rotate the world — it is the
##    single most common thing a player does while reading their
##    surroundings. This gate is why the old recenter_yaw_rate has no
##    successor: there is nothing left to recentre toward.
## 2. The heading must be far enough past the octant boundary
##    (snap_hysteresis_deg). Stops a heading sitting on a boundary from
##    flipping the camera back and forth.
## 3. The new answer must be STABLE for snap_dwell. Stops a heading that
##    merely sweeps through an octant on the way somewhere else from
##    committing a turn nobody asked for.
##
## Between them these cover the two ways the model could visibly misbehave,
## and it is worth being explicit about which gate covers which, because
## they are not interchangeable:
##
## - A heading WOBBLING either side of a boundary (N/NE/N/NE...) is stopped
##   by gate 2 alone. Having committed to NE, going back to N needs the
##   heading to reach 34.5 degrees off NE's centre, which is most of the way
##   into N — a few degrees of jitter at the boundary cannot reach it. The
##   camera cannot ping-pong.
## - A heading SWEEPING steadily, which is what running a circle around
##   something produces, is handled by gate 3 ONLY WHILE THE SWEEP IS FAST.
##   _candidate_time resets whenever the wanted octant changes, so a heading
##   advancing faster than roughly one octant per snap_dwell never banks the
##   dwell and the camera does not turn at all. Measured over a full circle:
##   180 deg/s produces zero turns, 90 deg/s five, and anything at or below
##   60 deg/s the full eight.
##
##   Eight is not a failure of the gates, and raising snap_dwell will not
##   meaningfully change it (0.5 was measured at seven). It is geometry: a
##   camera that follows heading at all must rotate a full 360 degrees over
##   a full circle, so the only thing any gate can trade is the NUMBER of
##   turns against their SIZE. Fewer turns on a circle means bigger ones,
##   which is more jarring per turn, not less. Eight 45-degree steps is the
##   gentlest way to spend a rotation that has to happen.
##
##   If circling still reads badly in play, the lever is therefore not these
##   gates. It is the prior question of whether a sustained circle should
##   move the octant at all — which would be a new gate on distance
##   travelled, not a bigger number here.
##
## A turn already in flight is not interrupted; the gates are only consulted
## once it has landed. Retargeting mid-turn would reintroduce exactly the
## continuous rotation this model removes, and a 0.25 s turn is short enough
## that the wait is not felt.
func _update_octant(delta: float, f: Frame) -> void:
	if _turn_t < 1.0:
		return

	if f.speed_ratio <= MOVING_SPEED_THRESHOLD:
		_candidate_index = -1
		_candidate_time = 0.0
		return

	var desired := _yaw_from_forward(f.target_forward)
	var wanted := _octant_of(desired)

	if wanted == _snap_index:
		_candidate_index = -1
		_candidate_time = 0.0
		return

	# How far the heading has left the committed octant's centre. The
	# boundary is half an octant away, so the threshold is that plus the
	# hysteresis band.
	var off_centre := absf(angle_difference(_yaw_of_octant(_snap_index), desired))
	if off_centre < SNAP_STEP * 0.5 + deg_to_rad(snap_hysteresis_deg):
		_candidate_index = -1
		_candidate_time = 0.0
		return

	if wanted != _candidate_index:
		_candidate_index = wanted
		_candidate_time = 0.0

	_candidate_time += delta
	if _candidate_time < snap_dwell:
		return

	_start_turn(wanted)


## Commits to a new octant and begins the eased turn toward it.
##
## _turn_to is built by ADDING the shortest signed step to the current base
## rather than by taking the new octant's absolute yaw, so the turn always
## goes the short way round and _base_yaw stays continuous across the
## wrap at +/-PI. Handing an absolute value to a plain lerp would make a
## turn across that seam sweep the long way — seven octants of rotation for
## a single step.
func _start_turn(index: int) -> void:
	_snap_index = index
	_candidate_index = -1
	_candidate_time = 0.0
	_turn_from = _base_yaw
	_turn_to = _base_yaw + angle_difference(_base_yaw, _yaw_of_octant(index))
	var step := absf(_turn_to - _turn_from)
	_turn_duration = _turn_duration_for(step)
	_turn_ramp = _turn_ramp_for(step)
	_turn_t = 0.0


## Advances a turn in flight. Ease-out cubic: the turn leaves quickly enough
## to read as deliberate and arrives slowly enough not to jolt, and — unlike
## the exponential damping used everywhere else in this file — it genuinely
## arrives.
func _advance_turn(delta: float) -> void:
	if _turn_t >= 1.0:
		_base_yaw = _turn_to
		return

	_turn_t = minf(_turn_t + delta / maxf(_turn_duration, 0.0001), 1.0)
	_base_yaw = lerp(_turn_from, _turn_to, _turn_ease(_turn_t, _turn_ramp))


## Quintic smootherstep, 6t^5 - 15t^4 + 10t^3. Used as the CORNER of the
## turn profile below, not as the profile itself any more.
##
## It replaced an ease-out cubic, and the reason was the VELOCITY curve
## rather than the position curve — the two look nearly identical plotted as
## position and behave completely differently to watch. Ease-out cubic has
## derivative 3(1-t)^2, which is 3x the average speed at t = 0 and zero at
## t = 1, so a turn began by snapping the angular velocity from nothing to
## three times its own average in one frame and only the ARRIVAL was smooth.
## Smootherstep's derivative is 30t^2(1-t)^2: zero at both ends, C2 at both
## ends, peaking at 1.875x average in the middle.
func _smootherstep(t: float) -> float:
	return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)


## Definite integral of _smootherstep from 0 to x, for x in [0, 1].
##
## x^6 - 3x^5 + 2.5x^4, which is 0.5 at x = 1 — a smootherstep ramp covers
## exactly half the ground a constant would over the same span, which is
## what makes the plateau height below work out to 1/(1-ramp).
func _smootherstep_integral(x: float) -> float:
	return x * x * x * x * (x * x - 3.0 * x + 2.5)


## The turn profile: a trapezoid in angular VELOCITY with smootherstep
## corners, given as position over normalised time.
##
## Velocity ramps from zero to a plateau over the first [param ramp] of the
## duration, holds, then ramps back to zero over the last [param ramp]. The
## plateau is 1/(1-ramp) times the average so the turn still covers exactly
## its angle in exactly its duration whatever ramp is chosen — the shape is
## free, the area is not.
##
## ramp = 0.5 leaves no plateau and gives a pure bump; smaller values flatten
## it toward a constant-speed move with rounded ends. Both ends stay C2, as
## smootherstep's do, so a turn still starts and finishes without a step in
## either velocity or acceleration; what changes is how much of the turn is
## spent at the peak rather than climbing to it.
##
## This is the whole of Phase 5A. Durations are untouched — the same turn
## takes the same time as before and only its shape has changed.
func _turn_ease(t: float, ramp: float) -> float:
	var r := clampf(ramp, 0.01, 0.5)
	var plateau := 1.0 / (1.0 - r)

	if t <= r:
		return plateau * r * _smootherstep_integral(t / r)
	if t >= 1.0 - r:
		return 1.0 - plateau * r * _smootherstep_integral((1.0 - t) / r)
	return plateau * (r * 0.5 + t - r)


## Ramp fraction for a turn of the given size, in radians.
##
## Interpolates from TURN_RAMP_SMALL at one octant to TURN_RAMP_LARGE at a
## full reversal, so responsiveness is a curve rather than a switch: an
## almost-invisible correction flows, a quarter turn is smooth but decisive,
## and a reversal keeps the pointed, deliberate character it needs to read
## as "I am now facing the other way" rather than as the world rotating.
##
## Sized on the OUTGOING angle rather than on the octant count so the two
## cannot disagree if the octant step is ever retuned.
func _turn_ramp_for(step: float) -> float:
	var bigness := clampf((step - SNAP_STEP) / (PI - SNAP_STEP), 0.0, 1.0)
	return lerp(TURN_RAMP_SMALL, TURN_RAMP_LARGE, bigness)


## How long to give a turn of the given size, in radians.
##
## Not constant. A turn is not always one octant: a genuine reversal jumps
## straight to the opposite heading, four octants at once, and giving 180
## degrees the same quarter second as 45 makes it a 720 deg/s whip-pan —
## which is the single most disorienting thing a camera can do, and would
## undo the whole point of this model at the exact moment the player most
## needs to keep their bearings.
##
## Square root rather than proportional. Proportional (constant angular
## speed) would make a reversal take a full second, which reads as the
## camera being slow to obey; sqrt puts 180 degrees at twice the duration of
## 45, so a reversal takes half a second and still arrives with authority.
## Small turns keep their snap, large turns stop hurting.
func _turn_duration_for(step: float) -> float:
	return snap_turn_duration * sqrt(maxf(step, 0.0001) / SNAP_STEP)


## Which octant a yaw falls in, as an index into the SNAP_COUNT headings.
## Index 0 is yaw 0, which _yaw_from_forward() gives a FORWARD-facing
## character — so the eight headings are anchored to the world axes, not to
## wherever the character happened to be looking when ISOMETRIC started.
func _octant_of(yaw: float) -> int:
	return wrapi(int(roundf(yaw / SNAP_STEP)), 0, SNAP_COUNT)


## Yaw at the centre of an octant.
func _yaw_of_octant(index: int) -> float:
	return float(index) * SNAP_STEP


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


## Eases the cursor bias toward a bounded lean in the direction of whatever
## the player is pointing at.
##
## Measured from the CHARACTER rather than from the follow point, so the
## bias cannot feed back on itself: biasing the frame moves the follow
## point, which would move the measured distance, which would move the
## bias. Anchoring it to the character breaks the loop outright rather than
## relying on the fraction being small enough to keep it stable.
func _update_cursor_bias(delta: float, f: Frame) -> void:
	var want := Vector3.ZERO

	if f.cursor_valid and f.cursor_edge_weight > 0.0:
		var to_cursor := f.cursor_point - f.target_position
		to_cursor.y = 0.0
		var distance := to_cursor.length()
		if distance > 0.01:
			# Direction from the cursor's own ground point, magnitude from
			# how close to the screen edge it is. Keeping the two apart is
			# what lets the bias point at a real place in the world — which
			# a tilted camera needs, since a screen axis only approximates
			# a ground direction — while still being silent in the middle
			# of the screen.
			var reach: float = minf(distance * CURSOR_BIAS_FRACTION, CURSOR_BIAS_DISTANCE)
			want = to_cursor / distance * reach * f.cursor_edge_weight

	_cursor_offset = _cursor_offset.lerp(want, Smoothing.damp_factor(CURSOR_BIAS_RATE, delta))


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
## the character, plus the lead and the cursor bias, at tracked ground
## height rather than body height.
func _desired_point(f: Frame) -> Vector3:
	var p := f.target_position + _lead_offset + _cursor_offset
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
	#
	# The forward component carries an extra factor the sideways one does
	# not: the camera looks DOWN at the ground, so a metre running away
	# from it covers less screen than a metre running across it (see
	# Frame.forward_screen_scale). Leaving it out is what made dead_zone_y
	# behave as though it were 1.75x its stated value.
	var forward_scale := maxf(f.forward_screen_scale, 0.1)
	var error_right := error.dot(f.cam_right)
	var error_forward := error.dot(f.cam_forward)

	var px_per_world := 1.0 / maxf(f.world_per_pixel, 0.00001)
	var error_px := Vector2(error_right, error_forward * forward_scale) * px_per_world

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

	# Back out of screen space the same way we came in — the forward axis
	# divides by the factor it was multiplied by, or the follow point would
	# advance by the foreshortened distance instead of the real one.
	var move_world := move_px * f.world_per_pixel
	follow_point += f.cam_right * move_world.x + f.cam_forward * (move_world.y / forward_scale)


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
