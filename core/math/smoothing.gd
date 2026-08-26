# =============================================================================
# smoothing.gd
# Static math helper, not a system — never instantiated, never autoloaded.
# Reachable from anywhere via the class_name below, same as Godot's own
# Geometry2D/Geometry3D. Exists so the same frame-rate-independent damping
# formula isn't hand-copied (and inevitably drifts) across every file that
# does exponential smoothing.
# =============================================================================
extends RefCounted
class_name Smoothing


## Frame-rate independent exponential damping factor.
## lerp(a, b, delta * rate) is only stable while delta * rate < 1: at 25 FPS
## with rate 30 it evaluates to 1.2 and extrapolates past the target, which
## reads as oscillation. This form stays inside (0, 1) for any delta and
## makes the smoothing rate mean the same thing at any frame rate.
static func damp_factor(rate: float, delta: float) -> float:
	return 1.0 - exp(-rate * delta)


## Critically damped spring toward a target. Returns the new position; the
## velocity is carried by the caller and must be passed back in every frame.
##
## WHEN TO REACH FOR THIS INSTEAD OF damp_factor(). The two differ in what
## they are continuous in, not in how smooth they look at rest:
##
## - damp_factor() is a first-order filter. Handed a target whose VELOCITY
##   changes in a step, it passes that step straight through — the output's
##   own velocity jumps in the same frame. It smooths position, never
##   velocity.
## - This is second order. Acceleration is bounded, so the output's velocity
##   cannot step no matter what the target does. It is the tool for a target
##   assembled from piecewise rules — zone thresholds, mode switches, a lead
##   that collapses when a destination is reached — where the value is
##   continuous but its rate of change is not.
##
## Critically damped specifically: no overshoot, no ringing, and it settles
## rather than approaching forever. An underdamped spring would answer the
## same continuity problem and add a wobble nobody asked for.
##
## [param smooth_time] Roughly how long it takes to reach the target. Also,
##   and this is the number worth budgeting with, the steady-state distance
##   behind a target moving at constant speed is speed * smooth_time — the
##   same lag damp_factor(rate) gives at smooth_time = 1/rate. Swapping one
##   for the other at matching values changes the continuity, not the lag.
## [param max_speed] Optional cap on the spring's own speed. Negative means
##   no cap, which is the normal case; a cap exists for the rare target that
##   can teleport and must not be chased at unbounded speed.
##
## The exp approximation is the standard Game Programming Gems formulation —
## a rational fit to exp(-x) chosen because it stays stable at any frame
## rate, which a naive integration of the same spring does not.
static func smooth_damp_vector3(
	current: Vector3,
	target: Vector3,
	velocity: Vector3,
	smooth_time: float,
	delta: float,
	max_speed: float = -1.0
) -> Array:
	var t := maxf(smooth_time, 0.0001)
	var omega := 2.0 / t

	var x := omega * delta
	var exp_factor := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)

	var change := current - target
	if max_speed > 0.0:
		var max_change := max_speed * t
		change = change.limit_length(max_change)

	var goal := current - change
	var temp := (velocity + change * omega) * delta
	var new_velocity := (velocity - temp * omega) * exp_factor
	var result := goal + (change + temp) * exp_factor

	# Guard against stepping past the target and letting the stored velocity
	# pull it back — the approximation is stable but not exact, and a spring
	# that overshoots is no longer critically damped.
	var original_to_target := target - current
	var result_to_target := target - result
	if original_to_target.dot(result_to_target) < 0.0:
		result = target
		new_velocity = (result - current) / delta if delta > 0.0 else Vector3.ZERO

	return [result, new_velocity]
