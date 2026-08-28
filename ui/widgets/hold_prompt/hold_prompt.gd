# =============================================================================
# hold_prompt.gd — HoldPrompt.
#
# The screen-space answer to "this can be taken, and here is the key". A
# tapered plate with the letter F on it, hanging over whatever the prompt was
# shown for; holding the key turns it yellow and morphs the letter into a
# circle and then a filled dot.
#
# REFLECTS, NEVER OWNS. This widget decides nothing. It does not know about
# inventory, store_item(), InteractableObject, or how long a hold has to last
# — the caller owns all of that and pushes state in through the five methods
# below. Delete the node and every interaction still works; only the picture
# goes away. Same contract EquipmentVisualsComponent and StaminaIndicator3D
# state for themselves.
#
# PROGRESS IS A TARGET, NOT A VALUE. set_progress() says where the caller
# thinks the hold is; this node eases its own displayed value toward that.
# Rising is nearly instant (a commit must never land before the dot is
# drawn), falling is slow, so a cancelled hold rolls back on its own without
# the caller animating anything. Truth belongs to the caller, feel belongs
# here.
#
# It is a FACT, not a hint: the panel says there is a candidate and that a
# hold is under way. The prototype's "hold button" / "42%" / "done" captions
# are deliberately not ported — docs/visual_language.md is explicit that the
# frame names things and never advises. The letter F stays, because that is
# the name of a key rather than a piece of advice.
#
# Found by its group, the way ComicEffectSystem is: HoverEntryTrigger is a
# static scene instance that never receives a WorldContext, and CLAUDE.md's
# dependency rule names exactly that case.
#
# Dependencies: WorldContext.camera (via on_world_ready) for unprojection.
# =============================================================================
class_name HoldPrompt
extends Control

## Lookup group for callers that have no reference to hand — same role as
## ComicEffectSystem.GROUP_COMIC_EFFECT_SYSTEM.
const GROUP_HOLD_PROMPT: StringName = &"hold_prompt"

## Appear spring, carried over unchanged from the HTML motion study. Not
## SpringPoint: that class states in its own header that its constants exist
## to keep the morph-icon family identical to ITS study and must not be
## retuned for one widget. Two scalar springs here is honest; bending someone
## else's contract to reuse forty lines is not.
const APPEAR_STIFFNESS: float = 160.0
const APPEAR_DAMPING: float = 20.0
const SHAKE_STIFFNESS: float = 420.0
const SHAKE_DAMPING: float = 12.0

## How fast the drawn progress may climb toward the target. Also exactly the
## length of the tap morph: a tap sets the target to 1.0 in one call, so this
## rate IS the F → circle → dot animation the player sees on a pickup.
const RISE_RATE: float = 1.0 / 0.12
## ...and fall, on a cancelled hold. From the study.
const FALL_RATE: float = 2.2
## How long the finished dot stays up after a tap before the panel leaves.
const COMMIT_HOLD_TIME: float = 0.12

## Morph thresholds, from the study. F is gone by 45%, the circle is fully in
## by 35%, the dot starts at 50%.
const F_FADE_END: float = 0.45
const CIRCLE_FADE_END: float = 0.35
const DOT_START: float = 0.5

## Corner arcs are sampled, not analytic — a quadratic through the corner,
## the same curve the study's roundRect() draws.
const CORNER_SAMPLES: int = 6

@export_group("Plate")
@export var box_size: Vector2 = Vector2(76.0, 76.0)
@export var corner_radius: float = 14.0
@export var line_width: float = 3.5
## How far each BOTTOM corner pulls inward, pixels. The top stays square, so
## the plate reads as a light shield pointing down at what it belongs to. A
## plain rounded rectangle reads as a tooltip instead.
@export var bottom_taper: float = 10.0

@export_group("Colour")
## Idle: a candidate exists, nothing is being held.
@export var idle_color: Color = Color("e8edf2")
## Active: the key is down, or progress has not yet rolled back.
@export var active_color: Color = Color("eab308")

@export_group("Type")
@export var key_label: String = "F"
@export var key_font_size: int = 36

@export_group("Placement")
## Lift above the followed node's origin, metres. Items lie on the ground, so
## this is measured from the object, not from its top.
@export var anchor_offset: Vector3 = Vector3(0.0, 0.6, 0.0)

var _camera: Camera3D = null
var _follow: Node3D = null

var _shown: bool = false
var _appear: float = 0.0
var _appear_vel: float = 0.0
var _shake_x: float = 0.0
var _shake_vel: float = 0.0
var _pulse_t: float = 0.0
var _rot: float = 0.0

var _holding: bool = false
var _progress: float = 0.0
var _progress_target: float = 0.0

## Seconds left of the "let the dot be seen" lock started by instant_complete().
## A pickup frees the world object, so InteractComponent reports "nothing
## targeted" on the very next frame and would otherwise hide the panel one
## frame after the morph began — the payoff would never be drawn.
var _commit_lock: float = 0.0
var _hide_pending: bool = false

var _font: Font = null


func _ready() -> void:
	add_to_group(GROUP_HOLD_PROMPT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	size = box_size
	pivot_offset = size * 0.5
	visible = false


## world.gd hands this over for every WORLD_UI_SCENES entry. The camera is
## the only thing this widget needs from the world — it unprojects the
## followed node itself, the same way ComicEffectLabel does.
func on_world_ready(context: WorldContext) -> void:
	_camera = context.camera


## Start showing, anchored to `follow`. Called repeatedly for the same target
## (interact_target_changed also fires when the player walks into reach), so
## a repeat on the SAME node deliberately does not restart the entrance —
## re-shaking on every edge would read as flicker.
func show_prompt(follow: Node3D) -> void:
	if _commit_lock > 0.0:
		return
	if not is_instance_valid(follow):
		return
	if _shown and follow == _follow:
		return

	_follow = follow
	_shown = true
	_hide_pending = false
	_appear = 0.0
	_appear_vel = 0.0
	_shake_x = (1.0 if randf() > 0.5 else -1.0) * randf_range(40.0, 70.0)
	_shake_vel = (1.0 if randf() > 0.5 else -1.0) * randf_range(1100.0, 1600.0)
	_progress = 0.0
	_progress_target = 0.0
	_holding = false
	_rot = 0.0
	visible = true


## Idempotent — InteractComponent asks every physics frame, so this must be
## free to call on a panel that is already going away.
func hide_prompt() -> void:
	if _commit_lock > 0.0:
		_hide_pending = true
		return
	if not _shown:
		return
	_shown = false
	_holding = false
	_follow = null


## The register, not the value: white while nothing is held, yellow while it
## is. Kept separate from set_progress() so a hold that has only just started
## already reads as a hold.
func set_holding(on: bool) -> void:
	_holding = on


## Where the caller thinks the hold is, 0..1.
func set_progress(t: float) -> void:
	_progress_target = clampf(t, 0.0, 1.0)


## A tap committed. Runs the morph through to the dot at RISE_RATE and holds
## the panel up long enough for it to be seen, ignoring the hide that a freed
## target is about to trigger.
func instant_complete() -> void:
	if not _shown:
		return
	_progress_target = 1.0
	_commit_lock = (1.0 / RISE_RATE) + COMMIT_HOLD_TIME


func is_showing() -> bool:
	return _shown


func _process(delta: float) -> void:
	if not _shown and _appear <= 0.01:
		if visible:
			visible = false
		return

	## is_instance_valid() and NOT "!= null": a freed Object compares EQUAL to
	## null in Godot, so a guard reading `_follow != null` is false for a
	## freed anchor and the panel would hang on a dead reference forever.
	## show_prompt() refuses an invalid node, so _shown implies there was one.
	if _shown and not is_instance_valid(_follow):
		hide_prompt()

	_advance_commit_lock(delta)
	_advance_springs(delta)
	_advance_progress(delta)

	if not _update_position():
		visible = false
		return

	visible = true
	queue_redraw()


func _advance_commit_lock(delta: float) -> void:
	if _commit_lock <= 0.0:
		return
	_commit_lock = maxf(_commit_lock - delta, 0.0)
	if _commit_lock == 0.0 and _hide_pending:
		_hide_pending = false
		hide_prompt()


func _advance_springs(delta: float) -> void:
	## Clamped for the reason SpringPoint.MAX_STEP gives: both springs here
	## are semi-implicit Euler and diverge past roughly 2 / damping — 0.10 s
	## for appear, 0.17 s for shake. A diverged _shake_x reaches the panel's
	## position and then draw_polyline(), which is exactly how the cursor's
	## own spring produced thousands of warnings before this was understood.
	## _appear is clamped to 0..1 below and could not run away, but _shake_x
	## has no such ceiling.
	var step: float = minf(delta, SpringPoint.MAX_STEP)

	var appear_target: float = 1.0 if _shown else 0.0
	var a_acc: float = (appear_target - _appear) * APPEAR_STIFFNESS - _appear_vel * APPEAR_DAMPING
	_appear_vel += a_acc * step
	_appear = clampf(_appear + _appear_vel * step, 0.0, 1.0)

	var s_acc: float = (0.0 - _shake_x) * SHAKE_STIFFNESS - _shake_vel * SHAKE_DAMPING
	_shake_vel += s_acc * step
	_shake_x += _shake_vel * step
	if absf(_shake_x) < 0.04 and absf(_shake_vel) < 0.8:
		_shake_x = 0.0
		_shake_vel = 0.0

	_pulse_t += delta


func _advance_progress(delta: float) -> void:
	var rate: float = RISE_RATE if _progress_target > _progress else FALL_RATE
	_progress = move_toward(_progress, _progress_target, rate * delta)

	if _holding:
		# clockwise, and faster the closer the hold is to done
		_rot += (2.5 + _progress * 4.5) * delta
	else:
		_rot += (0.0 - _rot) * minf(1.0, 6.0 * delta)


## Places the panel over its anchor. False means there is nowhere to put it —
## no camera yet, no anchor, or the anchor is behind the viewer, which is the
## same rule ComicEffectLabel applies.
func _update_position() -> bool:
	if _camera == null or not is_instance_valid(_camera):
		return false
	if not is_instance_valid(_follow):
		return false
	var world: Vector3 = _follow.global_position + anchor_offset
	if _camera.is_position_behind(world):
		return false
	position = _camera.unproject_position(world) - size * 0.5
	return true


func _draw() -> void:
	if _appear < 0.01:
		return
	if _font == null:
		_font = get_theme_default_font()
	if _font == null:
		return

	var settled: bool = absf(_shake_x) < 0.6
	var pulse: float = 1.0
	if not _holding and settled:
		pulse = 1.0 + sin(_pulse_t * 2.4) * 0.04

	# The entrance goes from a smeared ghost to a hard edge. sharp lags
	# appear on purpose, so the plate is still resolving after it has
	# finished moving.
	var sharp: float = pow(minf(1.0, _appear * 0.95), 1.8)
	var alpha: float = _appear * (0.45 + 0.55 * sharp)
	var center: Vector2 = size * 0.5 + Vector2(_shake_x, 0.0)
	var col: Color = active_color if (_holding or _progress > 0.02) else idle_color

	var outline: PackedVector2Array = _plate_outline(center, pulse)

	if sharp < 0.97:
		_draw_entrance_ghost(outline, center, col, sharp, pulse)

	draw_polyline(outline, Color(col, alpha), line_width, true)
	_draw_morph(center, col, alpha, pulse)


## Jittered low-alpha copies of the plate and the letter — the "not yet in
## focus" look of the study. Random per frame ON PURPOSE here: it is a
## ~0.2 s entrance that should shimmer, unlike ComicEffectLabel's panel
## jitter, which is fixed at spawn because that panel hangs still.
func _draw_entrance_ghost(
		outline: PackedVector2Array, center: Vector2, col: Color, sharp: float, pulse: float
	) -> void:
	var spread: float = (1.0 - sharp) * 26.0
	var copies: int = 8 if sharp < 0.5 else 5
	var ghost_a: float = _appear * (0.08 + 0.1 * sharp)
	var letter_a: float = _appear * (0.06 + 0.08 * sharp)
	for _i in copies:
		var off := Vector2(
			randf_range(-0.5, 0.5) * spread,
			randf_range(-0.5, 0.5) * spread * 0.45
		)
		var ghost := PackedVector2Array()
		for p in outline:
			ghost.append(p + off)
		draw_polyline(ghost, Color(col, ghost_a), line_width, true)
		_draw_key_letter(center + off, 0.0, Color(col, letter_a), pulse)


## F → circle → dot. The letter is gone before the circle is finished, so the
## two never read as two glyphs stacked on one another.
func _draw_morph(center: Vector2, col: Color, alpha: float, pulse: float) -> void:
	var t: float = _progress
	var f_alpha: float = 0.0 if t >= F_FADE_END else maxf(0.0, 1.0 - t / F_FADE_END)
	var circle_alpha: float = minf(1.0, t / CIRCLE_FADE_END)
	var dot_t: float = maxf(0.0, (t - DOT_START) / (1.0 - DOT_START))

	if f_alpha > 0.01:
		_draw_key_letter(center, _rot, Color(col, alpha * f_alpha), pulse)

	if circle_alpha > 0.02:
		var cr: float = 16.0 * pulse * (0.85 + 0.15 * circle_alpha)
		draw_arc(
			center, cr, 0.0, TAU, 32,
			Color(col, alpha * circle_alpha * (1.0 - dot_t * 0.15)), 3.0, true
		)

	if dot_t > 0.01:
		var dr: float = (4.0 + 6.0 * dot_t) * pulse
		draw_circle(center, dr, Color(col, alpha * minf(1.0, dot_t * 1.4)))


func _draw_key_letter(at: Vector2, rotation_rad: float, col: Color, pulse: float) -> void:
	var fs: int = maxi(1, roundi(key_font_size * pulse))
	var extent: Vector2 = _font.get_string_size(
		key_label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs
	)
	# Baseline that puts the glyph's optical middle on `at`.
	var baseline := Vector2(
		-extent.x * 0.5,
		(_font.get_ascent(fs) - _font.get_descent(fs)) * 0.5
	)
	draw_set_transform(at, rotation_rad, Vector2.ONE)
	draw_string(_font, baseline, key_label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The plate, as a closed polyline. Four corners with the bottom two pulled
## inward, then every corner replaced by a quadratic arc — Godot has no
## rounded-rectangle STROKE primitive, and a StyleBoxFlat cannot taper.
func _plate_outline(center: Vector2, pulse: float) -> PackedVector2Array:
	var half: Vector2 = box_size * pulse * 0.5
	var taper: float = bottom_taper * pulse
	var corners := PackedVector2Array([
		center + Vector2(-half.x, -half.y),
		center + Vector2(half.x, -half.y),
		center + Vector2(half.x - taper, half.y),
		center + Vector2(-half.x + taper, half.y),
	])
	var rounded: PackedVector2Array = _round_corners(corners, corner_radius * pulse)
	rounded.append(rounded[0])
	return rounded


static func _round_corners(points: PackedVector2Array, radius: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n: int = points.size()
	for i in n:
		var p: Vector2 = points[i]
		var prev: Vector2 = points[(i - 1 + n) % n]
		var next: Vector2 = points[(i + 1) % n]
		# Never eat more than a bit under half an edge, or two adjacent
		# corners would overlap and the outline would fold on itself.
		var enter: Vector2 = p + (prev - p).normalized() * minf(radius, p.distance_to(prev) * 0.45)
		var exit: Vector2 = p + (next - p).normalized() * minf(radius, p.distance_to(next) * 0.45)
		out.append(enter)
		for s in range(1, CORNER_SAMPLES):
			var t: float = float(s) / float(CORNER_SAMPLES)
			out.append(enter.lerp(p, t).lerp(p.lerp(exit, t), t))
		out.append(exit)
	return out
