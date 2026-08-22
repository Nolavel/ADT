# =============================================================================
# spring_point.gd
# ## ENG: Single 2D point with independent X/Y spring dynamics.
#         Pure RefCounted — no nodes, no draw. Owned by morph widgets.
#
#         STIFFNESS / DAMPING are constants, not exports, on purpose: they
#         are carried over unchanged from the HTML motion study this icon
#         family was designed in, so the feel is identical between that
#         prototype and the game UI. Change them only if the whole family
#         of morphs should feel different — a single morph wanting its own
#         feel is a reason to question the design, not to add a knob.
# =============================================================================
class_name SpringPoint
extends RefCounted


const STIFFNESS: float = 180.0
const DAMPING: float = 22.0
## Longest step this integrator is allowed to take, seconds.
##
## Semi-implicit Euler on a spring is only stable while the step stays under
## roughly 2/DAMPING — about 0.09s here. At the project's ~55 FPS target the
## margin is five-fold, but this build streams world content on threads with
## a per-frame instantiation budget, and a hitch past that bound does not
## degrade gracefully: it diverges, and the dots fly off screen. Clamping
## the step makes a long frame play back slightly slow instead, which is
## invisible on a menu glyph and cannot explode.
const MAX_STEP: float = 1.0 / 30.0

var x: float = 0.0
var y: float = 0.0
var target_x: float = 0.0
var target_y: float = 0.0
var vx: float = 0.0
var vy: float = 0.0


func _init(px: float = 0.0, py: float = 0.0) -> void:
	x = px
	y = py
	target_x = px
	target_y = py


func set_target(tx: float, ty: float) -> void:
	target_x = tx
	target_y = ty


func update(delta: float) -> void:
	delta = minf(delta, MAX_STEP)

	# X
	var ax: float = (target_x - x) * STIFFNESS - vx * DAMPING
	vx += ax * delta
	x += vx * delta
	if absf(target_x - x) < 0.001 and absf(vx) < 0.01:
		x = target_x
		vx = 0.0

	# Y
	var ay: float = (target_y - y) * STIFFNESS - vy * DAMPING
	vy += ay * delta
	y += vy * delta
	if absf(target_y - y) < 0.001 and absf(vy) < 0.01:
		y = target_y
		vy = 0.0


## Snap to target and clear velocity (instant settle).
func snap() -> void:
	x = target_x
	y = target_y
	vx = 0.0
	vy = 0.0
