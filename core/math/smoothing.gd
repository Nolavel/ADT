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
