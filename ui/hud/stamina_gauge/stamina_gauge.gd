# =============================================================================
# stamina_gauge.gd — StaminaGauge.
#
# The player's stamina, drawn as the ring it originally was, in the HUD.
#
# WHERE IT HAS BEEN. It started on the mouse cursor (MouseCursorUI, before
# commit e40eab4), which meant the cursor was saying two unrelated things at
# once — how much wind is left, and what you are aiming at. It was moved into
# the world as a ring on the ground (StaminaIndicator3D) to separate those two
# reads, and that solved the wrong half: a slow ambient gauge does not belong
# on the floor either, where it fights the camera angle, needs a clearance
# hack to stay out of the terrain and — with depth testing off, which is what
# it took to stay visible at all — draws straight through the character.
#
# So it lands where a slow ambient gauge belongs: the status stack, beside
# health. On a flat canvas there is no depth to test, nothing to clip into and
# nothing to draw over. The over-the-player bug is not fixed here, it is
# structurally absent.
#
# THE LOOK IS THE ORIGINAL ONE, restored from e40eab4's _draw_sprint_arcs(),
# _draw_recovery_effect_shader(), _draw_jump_arc() and
# _draw_movement_indicators(): four quarter arcs whose length is the stamina
# ratio, a cool→yellow→orange→red ramp, two counter-running recovery sweeps
# with a pulse and an inner glow, and the jump-charge arc. The geometry is
# still expressed in the original pixel radii around an 8 px cursor and simply
# multiplied by `gauge_scale`, so the proportions cannot drift from what they
# were while being big enough to read in a corner.
#
# WHAT CHANGED ON PURPOSE: the walk / sprint / no-stamina icon is drawn INSIDE
# the ring instead of below the cursor. Stan, 2026-09-02 — the ring is a
# frame, and the thing it frames is what the legs are currently doing.
#
# WHAT IT DOES NOT DO: arithmetic. StaminaComponent owns the number, the
# drain, the recovery delay and the fatigue curve; this widget subscribes and
# draws. Deleting it must change nothing except what is on screen.
#
# Dependencies: the player and its StaminaComponent, handed over by PlayerHUD
# through bind(); InputSystems for the jump-held query only (never Input).
# =============================================================================
class_name StaminaGauge
extends Control

## Everything below is in the ORIGINAL cursor's pixels, around a cursor of
## this radius, and is multiplied by gauge_scale at draw time. Keeping the
## numbers rather than re-deriving them is what makes this a port.
const BASE_RADIUS: float = 8.0
## Speed below which the character counts as standing still, m/s. The same
## threshold the cursor used (player_move_stationary_speed).
const STATIONARY_SPEED: float = 0.05

@export_group("Layout")
## Scales every radius and thickness below. 1.0 would be the cursor's own
## size, which is far too small to read from the corner of the screen.
@export var gauge_scale: float = 1.8:
	set(value):
		gauge_scale = maxf(value, 0.1)
		_update_minimum_size()

@export_group("Arcs")
## Floor under the arcs' opacity. The ported rule was alpha = the remaining
## ratio, which meant the ring faded toward invisible exactly as it ran out —
## the one moment the player most needs to read it. Seen on the six-state
## render, 2026-09-02, and raised rather than silently changed because it was
## the original's behaviour; Stan's call was to put a floor under it.
##
## It floors the OPACITY only. Arc length still goes to zero, the colour ramp
## still runs to red, so "almost nothing left" still reads as almost nothing
## left — it just stays legible while saying so.
@export var arc_min_alpha: float = 0.35
@export var arc_thickness: float = 6.0
@export var arc_color: Color = Color(0.8, 0.9, 1.0, 1.0)
@export var arc_rotation_speed: float = 2.0
## How fast the arcs' own alpha chases its target. Ported unchanged.
@export var arc_alpha_speed: float = 6.0

@export_group("Recovery")
@export var recovery_ring_thickness: float = 3.0
@export var recovery_pulse_speed: float = 3.0
@export var recovery_color: Color = Color(0.4, 1.0, 0.6, 1.0)
@export var recovery_show_inner_glow: bool = true
## Segment count for the two gradient rings. The original imitated a shader
## with 64 straight lines and that is what gives the sweep its softness.
@export var recovery_gradient_segments: int = 64

@export_group("Icons")
@export var walk_icon: Texture2D = null
@export var sprint_icon: Texture2D = null
## Icon box as a fraction of the ring's inner diameter.
@export var icon_fill: float = 0.8
## Bounce on appear, ported from _animate_indicator_appear().
@export var icon_scale_bounce: float = 1.2

var _player: CharacterBody3D = null
var _stamina: StaminaComponent = null

## --- Ported state ---
var _stamina_ratio: float = 1.0
var _arcs_alpha: float = 0.0
var _arc_angle: float = 0.0
var _sprint_progress: float = 0.0
var _is_moving: bool = false
var _is_sprinting: bool = false
var _wants_to_sprint_but_cannot: bool = false

var _is_recovering: bool = false
var _recovery_pulse_time: float = 0.0

var _jump_alpha: float = 0.0
var _jump_progress: float = 0.0
var _jump_is_charging: bool = false
var _jump_time: float = 0.0
var _jump_tween: Tween = null

var _walk_alpha: float = 0.0
var _sprint_alpha: float = 0.0
var _no_stamina_alpha: float = 0.0
var _walk_scale: float = 1.0
var _sprint_scale: float = 1.0
var _no_stamina_scale: float = 1.0
var _walk_tween: Tween = null
var _sprint_tween: Tween = null
var _no_stamina_tween: Tween = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_update_minimum_size()
	set_process(false)


## Handed the player by PlayerHUD, which is the one node that already holds
## the WorldContext. Without it the gauge simply never processes — it does not
## go hunting for the player through a group.
func bind(player: Node) -> void:
	_player = player as CharacterBody3D
	if _player == null:
		push_warning("[StaminaGauge] no player — gauge stays idle")
		return

	_stamina = _player.get_node_or_null("StaminaComponent") as StaminaComponent
	if _stamina == null:
		push_warning("[StaminaGauge] player has no StaminaComponent — gauge stays idle")
		return

	_stamina.stamina_changed.connect(_on_stamina_changed)
	_stamina.jump_performed.connect(_on_jump_performed)
	_stamina_ratio = _stamina.get_stamina_ratio()
	_arcs_alpha = maxf(_stamina_ratio, arc_min_alpha) * 0.5
	set_process(true)


func _process(delta: float) -> void:
	if _player == null:
		return
	var speed: float = Vector2(_player.velocity.x, _player.velocity.z).length()
	_update_movement_state(delta, speed <= STATIONARY_SPEED)
	_update_recovery_state(delta)
	if _jump_is_charging:
		_jump_time += delta
	else:
		_jump_time = 0.0
	queue_redraw()


# -----------------------------------------------------------------------------
# ## ENG: State — ported from MouseCursorUI._update_movement_state()
# -----------------------------------------------------------------------------

func _update_movement_state(delta: float, player_stationary: bool) -> void:
	_is_moving = not player_stationary
	_is_sprinting = _player.is_currently_sprinting(_player.velocity)

	var wants_sprint: bool = _player.is_wanting_to_run() and _is_moving
	var can_sprint: bool = _stamina != null and _stamina.is_sprint_allowed()
	_wants_to_sprint_but_cannot = wants_sprint and not can_sprint

	_sprint_progress = clampf(_player.get_sprint_blend(), 0.0, 1.0)
	if _stamina != null:
		_stamina_ratio = _stamina.get_stamina_ratio()

	## Icon priority, ported exactly: cannot-sprint beats sprinting beats
	## walking beats nothing.
	if _wants_to_sprint_but_cannot:
		_show_icon(&"no_stamina")
	elif _is_sprinting:
		_show_icon(&"sprint")
	elif _is_moving:
		_show_icon(&"walk")
	else:
		_fade_icon(&"walk")
		_fade_icon(&"sprint")
		_fade_icon(&"no_stamina")

	## Full while moving, half at rest — present, but not asking for attention
	## when nothing is being spent. Ported verbatim.
	## Full while moving, half at rest, never below arc_min_alpha — see that
	## export for why the floor exists. The rest multiplier applies to the
	## floor too, so standing still with an empty bar is still the quieter of
	## the two readings rather than jumping to full strength.
	var target_alpha: float = maxf(_stamina_ratio, arc_min_alpha)
	if not _is_moving:
		target_alpha *= 0.5
	_arcs_alpha = lerpf(_arcs_alpha, target_alpha, arc_alpha_speed * delta)

	## Arcs spin faster the harder the character is running.
	if _is_sprinting:
		_arc_angle += arc_rotation_speed * delta * (0.5 + _sprint_progress * 0.5)
	else:
		_arc_angle += 0.3 * delta
	if _arc_angle > TAU:
		_arc_angle -= TAU

	## Jump charge, read through InputSystems' query method rather than Input
	## directly — the project's own rule about who may touch Input.
	var on_floor: bool = _player.is_on_floor()
	var charging: bool = InputSystems.is_jump_held() and on_floor
	if charging and not _jump_is_charging:
		_jump_alpha = 0.6
	elif not charging and _jump_is_charging and on_floor:
		_jump_alpha = 0.0
	_jump_is_charging = charging


func _update_recovery_state(delta: float) -> void:
	if _stamina == null:
		return
	_is_recovering = _stamina.is_recovering()
	if _is_recovering:
		_recovery_pulse_time += delta * recovery_pulse_speed
		if _recovery_pulse_time > TAU:
			_recovery_pulse_time -= TAU


func _on_stamina_changed(current_stamina: float, max_stamina: float) -> void:
	_stamina_ratio = current_stamina / maxf(max_stamina, 0.0001)


## Ported from MouseCursorUI._on_jump_performed(), timings included.
func _on_jump_performed() -> void:
	if _jump_tween:
		_jump_tween.kill()
	_jump_tween = create_tween()
	_jump_tween.set_parallel(true)
	_jump_tween.tween_method(_set_jump_progress, 0.0, 1.0, 0.15)
	_jump_tween.tween_method(_set_jump_progress, 1.0, 0.0, 0.25).set_delay(0.15)
	_jump_tween.tween_method(_set_jump_alpha, 0.8, 0.0, 0.4)


func _set_jump_progress(value: float) -> void:
	_jump_progress = value


func _set_jump_alpha(value: float) -> void:
	_jump_alpha = value


# -----------------------------------------------------------------------------
# ## ENG: Icons — ported appear/fade tweens
# -----------------------------------------------------------------------------

func _show_icon(which: StringName) -> void:
	match which:
		&"walk":
			if _walk_alpha < 0.9:
				_appear_icon(&"walk")
			_fade_icon(&"sprint")
			_fade_icon(&"no_stamina")
		&"sprint":
			if _sprint_alpha < 0.9:
				_appear_icon(&"sprint")
			_fade_icon(&"walk")
			_fade_icon(&"no_stamina")
		&"no_stamina":
			if _no_stamina_alpha < 0.9:
				_appear_icon(&"no_stamina")
			_fade_icon(&"walk")
			_fade_icon(&"sprint")


func _appear_icon(which: StringName) -> void:
	var alpha_property := "_%s_alpha" % which
	var scale_property := "_%s_scale" % which
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, alpha_property, 1.0, 0.2)
	tween.tween_property(self, scale_property, icon_scale_bounce, 0.1)
	tween.chain().tween_property(self, scale_property, 1.0, 0.15) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_store_icon_tween(which, tween)


func _fade_icon(which: StringName) -> void:
	var alpha_property := "_%s_alpha" % which
	if float(get(alpha_property)) <= 0.001:
		return
	var tween := create_tween()
	tween.tween_property(self, alpha_property, 0.0, 0.3)
	_store_icon_tween(which, tween)


## Each icon keeps ONE tween, killed before the next replaces it — two tweens
## writing the same property is how an icon ends up stuck half-faded.
func _store_icon_tween(which: StringName, tween: Tween) -> void:
	match which:
		&"walk":
			if _walk_tween:
				_walk_tween.kill()
			_walk_tween = tween
		&"sprint":
			if _sprint_tween:
				_sprint_tween.kill()
			_sprint_tween = tween
		&"no_stamina":
			if _no_stamina_tween:
				_no_stamina_tween.kill()
			_no_stamina_tween = tween


# -----------------------------------------------------------------------------
# ## ENG: Drawing — the port. Order matches the original _draw().
# -----------------------------------------------------------------------------

func _draw() -> void:
	var centre: Vector2 = size * 0.5

	_draw_movement_icon(centre)

	if _arcs_alpha > 0.01:
		_draw_sprint_arcs(centre)

	if _is_recovering and _stamina_ratio < 0.95:
		_draw_recovery_effect(centre)

	if _jump_alpha > 0.0:
		_draw_jump_arc(centre)


## The colour ramp from _draw_sprint_arcs(), unchanged: cool while there is
## wind left, then yellow, orange and red as it runs out.
func _ramp_color(base: Color) -> Color:
	if _stamina_ratio > 0.5:
		return base.lerp(Color(1.0, 1.0, 0.0), (1.0 - _stamina_ratio) * 2.0)
	if _stamina_ratio > 0.25:
		return Color(1.0, 1.0, 0.0).lerp(Color(1.0, 0.5, 0.0), (0.5 - _stamina_ratio) * 4.0)
	return Color(1.0, 0.5, 0.0).lerp(Color(1.0, 0.0, 0.0), (0.25 - _stamina_ratio) * 4.0)


## FOUR quarter arcs, each spanning quarter_length OF ITS OWN QUARTER, so they
## meet into a closed ring at full stamina and open into four separate arcs as
## it drains. That closing is the whole read, and an earlier attempt to keep a
## permanent gap between them "so four arcs read as four" was a change to the
## design rather than a fix.
func _draw_sprint_arcs(centre: Vector2) -> void:
	var colour: Color = _ramp_color(arc_color)
	colour.a *= _arcs_alpha

	var radius: float = (BASE_RADIUS + 4.0) * gauge_scale
	var quarter_length: float
	if _is_sprinting:
		quarter_length = PI * 0.5 * _sprint_progress * _stamina_ratio
	else:
		quarter_length = PI * 0.5 * _stamina_ratio

	for i in 4:
		var base_angle: float = i * PI * 0.5 + _arc_angle
		_arc(
			centre, radius, base_angle, base_angle + quarter_length,
			colour, arc_thickness * gauge_scale
		)


## Two rings chasing round at different rates plus a pulse, imitated with
## straight segments exactly as the original did — the segment count IS the
## softness of the sweep.
func _draw_recovery_effect(centre: Vector2) -> void:
	var pulse: float = sin(_recovery_pulse_time) * 0.5 + 0.5
	var inner_radius: float = (BASE_RADIUS + 8.0) * gauge_scale \
			+ sin(_recovery_pulse_time * 2.0) * 2.0 * gauge_scale
	var outer_radius: float = inner_radius + 4.0 * gauge_scale
	var segments: int = maxi(recovery_gradient_segments, 8)

	for i in segments:
		var start: float = (TAU / segments) * i
		var end: float = (TAU / segments) * (i + 1)
		var progress: float = fmod(i / float(segments) - _recovery_pulse_time / TAU + 1.0, 1.0)
		var alpha: float = smoothstep(0.0, 0.3, progress) * (1.0 - smoothstep(0.7, 1.0, progress))
		var colour: Color = recovery_color
		colour.a = alpha * pulse * 0.6
		_arc(centre, inner_radius, start, end, colour, recovery_ring_thickness * gauge_scale)

	for i in segments:
		var start: float = (TAU / segments) * i
		var end: float = (TAU / segments) * (i + 1)
		var progress: float = fmod(
			i / float(segments) - _recovery_pulse_time / TAU * 1.5 + 1.0, 1.0
		)
		var alpha: float = smoothstep(0.0, 0.2, progress) * (1.0 - smoothstep(0.8, 1.0, progress))
		var colour: Color = recovery_color
		colour.a = alpha * pulse * 0.4
		_arc(centre, outer_radius, start, end, colour, recovery_ring_thickness * 0.6 * gauge_scale)

	if recovery_show_inner_glow:
		var glow: Color = recovery_color
		glow.a = pulse * 0.3
		draw_circle(centre, (BASE_RADIUS + 3.0) * gauge_scale, glow)


## Charging: a short arc at the bottom that grows and jitters. Released: a
## ring that closes as the tween runs, becoming a full circle at the peak.
func _draw_jump_arc(centre: Vector2) -> void:
	var radius: float = (BASE_RADIUS + 12.0) * gauge_scale
	var colour: Color = _ramp_color(Color(0.4, 0.8, 1.0, 1.0))
	colour.a = _jump_alpha
	var width: float = 2.0 * gauge_scale

	if _jump_is_charging:
		var span: float = PI * 0.2 + sin(_jump_time * 20.0) * 0.1 + PI * 0.3 * _jump_progress
		var centre_angle: float = PI * 0.5
		_arc(centre, radius, centre_angle - span * 0.5, centre_angle + span * 0.5, colour, width)
		return

	var progress: float = clampf(_jump_progress, 0.0, 1.0)
	if progress >= 1.0:
		_arc(centre, radius, 0.0, TAU, colour, width)
		return
	var from_angle: float = PI * 1.5 - TAU * 0.5 * progress
	var to_angle: float = PI * 1.5 + TAU * 0.5 * progress
	_arc(centre, radius, from_angle, to_angle, colour, width)


## Inside the ring, not below it — see this file's header. One icon at a time
## in practice; all three are drawn so a cross-fade between two of them reads
## as a cross-fade rather than a pop.
func _draw_movement_icon(centre: Vector2) -> void:
	## The clear disc inside the arcs: their radius less HALF their thickness,
	## which is where the band actually ends.
	var box: float = ((BASE_RADIUS + 4.0) - arc_thickness * 0.5) \
			* gauge_scale * 2.0 * icon_fill
	_icon(walk_icon, centre, box, _walk_alpha, _walk_scale, Color.WHITE)
	_icon(sprint_icon, centre, box, _sprint_alpha, _sprint_scale, Color.WHITE)
	## Same texture as sprint, tinted red — exactly what the cursor did for
	## "wants to run and cannot".
	_icon(sprint_icon, centre, box, _no_stamina_alpha, _no_stamina_scale, Color.RED)


func _icon(
		texture: Texture2D,
		centre: Vector2,
		box: float,
		alpha: float,
		icon_scale: float,
		tint: Color
	) -> void:
	if texture == null or alpha <= 0.01 or box <= 0.0:
		return
	var extent := Vector2(box, box) * icon_scale
	var colour := tint
	colour.a = alpha
	draw_texture_rect(texture, Rect2(centre - extent * 0.5, extent), false, colour)


## draw_arc() exists, but the original walked the arc by hand and the segment
## count it chose is part of how the sweep looks — kept.
func _arc(
		centre: Vector2,
		radius: float,
		from_angle: float,
		to_angle: float,
		colour: Color,
		width: float
	) -> void:
	if colour.a <= 0.001 or radius <= 0.0:
		return
	var segments: int = maxi(8, int(absf(to_angle - from_angle) * radius * 0.5))
	var step: float = (to_angle - from_angle) / segments
	for i in segments:
		var a1: float = from_angle + i * step
		var a2: float = from_angle + (i + 1) * step
		draw_line(
			centre + Vector2(cos(a1), sin(a1)) * radius,
			centre + Vector2(cos(a2), sin(a2)) * radius,
			colour,
			width,
			true
		)


## The widest thing drawn is the jump ring plus half its line width.
func _update_minimum_size() -> void:
	var extent: float = ((BASE_RADIUS + 12.0) + 2.0) * gauge_scale
	custom_minimum_size = Vector2(extent * 2.0, extent * 2.0)
