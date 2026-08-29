# =============================================================================
# stamina_indicator_3d.gd — StaminaIndicator3D.
#
# The player's stamina, drawn on the ground around their feet instead of on
# the mouse cursor.
#
# WHY IT MOVED. MouseCursorUI was doing two unrelated jobs at once: saying how
# much wind the character has left, and saying what they are aiming at. Aiming
# is a fast, precise read; stamina is a slow, ambient one. Stacked on the same
# few pixels they fight each other, and the aiming half loses. So stamina goes
# where a slow ambient read belongs — in the world, attached to the body it
# describes — and the cursor is left to do one thing.
#
# WHAT IT DOES NOT DO: arithmetic. StaminaComponent owns the number, the
# drain, the recovery delay and the fatigue curve; this node subscribes and
# renders. Deleting it must change nothing except what is on screen — the same
# contract EquipmentVisualsComponent already states for itself.
#
# The visual is a port, not a rewrite. Every formula, colour ramp and duration
# below came from MouseCursorUI's _draw_sprint_arcs() / _draw_recovery_effect_
# shader() / _draw_jump_arc() / _draw_movement_indicators() and is kept
# deliberately identical — what changed is the surface it is painted on
# (2D canvas -> a shader on a ground quad), not how it looks or feels.
#
# Dependencies: StaminaComponent (sibling), the player (parent), InputSystems
# (is_jump_held query only — never Input directly).
# =============================================================================
extends Node3D
class_name StaminaIndicator3D

@export_group("Placement")
## Height above the player's origin. The origin sits at the feet, so this is
## literally the clearance above the floor — enough that the quad does not
## z-fight with the ground it lies on.
@export var ground_clearance: float = 0.30
## Outer radius of the ring, metres. Sized to read as "around this character"
## rather than as a puddle they are standing in.
@export var ring_radius: float = 0.85

@export_group("Arcs")
## Four quarter arcs, their length driven by the remaining stamina ratio.
## Band width of the arcs, metres. Was declared and never used — the shader
## had 0.10 hard-coded. Wired up and widened to match the ORIGINAL's visual
## weight: the 2D cursor drew 6 px arcs on a 12 px radius, half the radius,
## where this was drawing a hairline. That thinness is most of what "it is
## not the effect it was" meant.
@export var arc_thickness: float = 0.13
@export var arc_rotation_speed: float = 2.0
## How fast the arcs' own alpha chases its target. Ported unchanged.
@export var arc_alpha_speed: float = 6.0
## Stamina full -> empty. Ported from _draw_sprint_arcs()'s ramp, which walks
## this colour toward yellow, then orange, then red as the ratio falls.
@export var arc_color: Color = Color(0.8, 0.9, 1.0, 1.0)
## Brightness multiplier for everything the ring draws. Lives here because
## the shader is `unshaded`, where EMISSION is ignored outright — the port
## set EMISSION and the glow it was meant to have never arrived.
@export var ring_glow: float = 1.5

@export_group("Recovery")
@export var recovery_pulse_speed: float = 3.0
@export var recovery_color: Color = Color(0.4, 1.0, 0.6, 1.0)

@export_group("Movement icons")
## The same textures the cursor used to draw under itself. Billboarded above
## the ring rather than laid flat on it: flat, they read only from directly
## above, which is exactly the angle TPS never gives.
@export var walk_icon: Texture2D = null
@export var sprint_icon: Texture2D = null
## Height above whatever the icon is standing on.
##
## It used to be measured from the player's own origin, which put the icon
## over the character's head. It now rides the MOVE-TARGET indicator instead —
## the marker for where the character is going — because that is where a
## "walking / running" statement belongs. Stan, 2026-08-28.
@export var icon_height: float = 1.15
@export var icon_pixel_size: float = 0.0022
## Bounce on appear, ported from _animate_indicator_appear().
@export var icon_scale_bounce: float = 1.2

@export_group("Debug")
@export var debug_log: bool = false

## Speed below which the character counts as standing still. Same threshold
## the cursor used (player_move_stationary_speed).
const STATIONARY_SPEED: float = 0.05

var _player: CharacterBody3D = null
var _stamina: StaminaComponent = null

var _ring: MeshInstance3D = null
var _ring_material: ShaderMaterial = null
## The move-destination marker the icons ride, resolved by group and cached.
## Null is normal — there is no destination marker in TPS, and none before the
## first click in ISOMETRIC.
var _move_target: TargetIndicator = null
## Where the icons stand this frame, written by _resolve_icon_anchor().
var _icon_anchor: Vector3 = Vector3.ZERO
var _walk_sprite: Sprite3D = null
var _sprint_sprite: Sprite3D = null
var _no_stamina_sprite: Sprite3D = null

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

var _last_player_pos: Vector3 = Vector3.ZERO


func _ready() -> void:
	_player = get_parent() as CharacterBody3D
	if _player == null:
		push_warning("[StaminaIndicator3D] parent is not the player — inert")
		return
	_last_player_pos = _player.global_position

	_stamina = _player.get_node_or_null("StaminaComponent") as StaminaComponent
	if _stamina == null:
		push_warning("[StaminaIndicator3D] no StaminaComponent — ring stays idle")
	else:
		_stamina.stamina_changed.connect(_on_stamina_changed)
		_stamina.jump_performed.connect(_on_jump_performed)
		_stamina_ratio = _stamina.get_stamina_ratio()

	## top_level, and this is the whole reason the node exists as a child at
	## all rather than as a sibling: it must FOLLOW the player's position but
	## must NOT inherit their rotation. In COMBAT the body turns to face the
	## camera constantly, and a ring welded to that yaw would swing with every
	## turn — a ground marker that spins when you look sideways reads as a bug.
	## Position is copied each frame in _process(); the ring's own rotation is
	## the arc animation and nothing else.
	top_level = true

	_build_ring()
	_build_icons()


func _process(delta: float) -> void:
	if _player == null:
		return

	global_position = _player.global_position + Vector3(0.0, ground_clearance, 0.0)

	var speed: float = (_player.global_position - _last_player_pos).length() / maxf(delta, 0.0001)
	_last_player_pos = _player.global_position

	_update_movement_state(delta, speed <= STATIONARY_SPEED)
	_update_recovery_state(delta)
	_update_icons(delta)
	_push_shader_parameters()


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
		_show_icon("no_stamina")
	elif _is_sprinting:
		_show_icon("sprint")
	elif _is_moving:
		_show_icon("walk")
	else:
		_fade_icon("walk")
		_fade_icon("sprint")
		_fade_icon("no_stamina")

	## The ring dims by half while standing still — present, but not asking
	## for attention when nothing is being spent. Ported verbatim.
	## Exactly the original: full while moving, half at rest. The 0.5 was
	## never the problem — the problem was the SHADER multiplying it again,
	## which is now gone, so this number finally means what it says.
	var target_alpha: float = _stamina_ratio if _is_moving else _stamina_ratio * 0.5
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


## The colour ramp from _draw_sprint_arcs(), unchanged: cool while there is
## wind left, then yellow, orange and red as it runs out.
func _arc_color_for_ratio() -> Color:
	if _stamina_ratio > 0.5:
		return arc_color.lerp(Color(1.0, 1.0, 0.0), (1.0 - _stamina_ratio) * 2.0)
	if _stamina_ratio > 0.25:
		return Color(1.0, 1.0, 0.0).lerp(Color(1.0, 0.5, 0.0), (0.5 - _stamina_ratio) * 4.0)
	return Color(1.0, 0.5, 0.0).lerp(Color(1.0, 0.0, 0.0), (0.25 - _stamina_ratio) * 4.0)


func _push_shader_parameters() -> void:
	if _ring_material == null:
		return
	var colour := _arc_color_for_ratio()
	_ring_material.set_shader_parameter("arc_color", Vector3(colour.r, colour.g, colour.b))
	_ring_material.set_shader_parameter("arc_alpha", _arcs_alpha)
	_ring_material.set_shader_parameter("arc_angle", _arc_angle)
	## While sprinting the arcs also shorten with the sprint blend, so the
	## ring visibly closes as the character commits. Ported from the
	## quarter_length branch in _draw_sprint_arcs().
	var span: float = _stamina_ratio * (_sprint_progress if _is_sprinting else 1.0)
	_ring_material.set_shader_parameter("arc_span", clampf(span, 0.0, 1.0))
	_ring_material.set_shader_parameter("ring_glow", ring_glow)
	_ring_material.set_shader_parameter("arc_width", arc_thickness / maxf(ring_radius, 0.001))
	_ring_material.set_shader_parameter("recovery_time", _recovery_pulse_time)
	_ring_material.set_shader_parameter(
		"recovery_alpha", 1.0 if (_is_recovering and _stamina_ratio < 0.95) else 0.0
	)
	_ring_material.set_shader_parameter(
		"recovery_color", Vector3(recovery_color.r, recovery_color.g, recovery_color.b)
	)
	_ring_material.set_shader_parameter("jump_alpha", _jump_alpha)
	_ring_material.set_shader_parameter("jump_progress", _jump_progress)


# -----------------------------------------------------------------------------
# ## ENG: Signals from StaminaComponent
# -----------------------------------------------------------------------------

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

func _show_icon(which: String) -> void:
	match which:
		"walk":
			if _walk_alpha < 0.9:
				_appear_icon("walk")
			_fade_icon("sprint")
			_fade_icon("no_stamina")
		"sprint":
			if _sprint_alpha < 0.9:
				_appear_icon("sprint")
			_fade_icon("walk")
			_fade_icon("no_stamina")
		"no_stamina":
			if _no_stamina_alpha < 0.9:
				_appear_icon("no_stamina")
			_fade_icon("walk")
			_fade_icon("sprint")


func _appear_icon(which: String) -> void:
	var alpha_property := "_%s_alpha" % which
	var scale_property := "_%s_scale" % which
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, alpha_property, 1.0, 0.2)
	tween.tween_property(self, scale_property, icon_scale_bounce, 0.1)
	tween.chain().tween_property(self, scale_property, 1.0, 0.15) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_store_icon_tween(which, tween)


func _fade_icon(which: String) -> void:
	var alpha_property := "_%s_alpha" % which
	if get(alpha_property) <= 0.001:
		return
	var tween := create_tween()
	tween.tween_property(self, alpha_property, 0.0, 0.3)
	_store_icon_tween(which, tween)


## Each icon keeps ONE tween, killed before the next replaces it — two tweens
## writing the same property is how an icon ends up stuck half-faded.
func _store_icon_tween(which: String, tween: Tween) -> void:
	match which:
		"walk":
			if _walk_tween:
				_walk_tween.kill()
			_walk_tween = tween
		"sprint":
			if _sprint_tween:
				_sprint_tween.kill()
			_sprint_tween = tween
		"no_stamina":
			if _no_stamina_tween:
				_no_stamina_tween.kill()
			_no_stamina_tween = tween


func _update_icons(_delta: float) -> void:
	var anchored: bool = _resolve_icon_anchor()
	var anchor: Vector3 = _icon_anchor
	_apply_icon(_walk_sprite, _walk_alpha, _walk_scale, Color.WHITE, anchor, anchored)
	_apply_icon(_sprint_sprite, _sprint_alpha, _sprint_scale, Color.WHITE, anchor, anchored)
	_apply_icon(
		_no_stamina_sprite, _no_stamina_alpha, _no_stamina_scale, Color.RED, anchor, anchored
	)


## Where the movement icons should stand this frame, and whether there is
## anywhere at all.
##
## They ride the move-destination marker. When there is none — TPS, or
## ISOMETRIC before the first click — the icons do not fall back to the
## character's head: that is the placement being moved away from, and putting
## it back "just for that case" would mean the icon jumps between two
## completely different places depending on how the player is steering.
## No destination, no destination icon.
## Writes _icon_anchor and reports whether it means anything. Deliberately NOT
## an out-parameter: Vector3 is a value type in GDScript, so assigning to an
## argument inside a function changes nothing for the caller — the first
## version of this did exactly that and would have pinned every icon to the
## origin.
func _resolve_icon_anchor() -> bool:
	if not is_instance_valid(_move_target):
		_move_target = get_tree().get_first_node_in_group(
			TargetIndicator.GROUP_MOVE_TARGET
		) as TargetIndicator
	if not is_instance_valid(_move_target):
		return false
	if not _move_target.is_visible_indicator:
		return false
	_icon_anchor = _move_target.global_position
	return true


func _apply_icon(
		sprite: Sprite3D,
		alpha: float,
		icon_scale: float,
		tint: Color,
		anchor: Vector3,
		anchored: bool
	) -> void:
	if sprite == null:
		return
	sprite.visible = anchored and alpha > 0.01
	if not sprite.visible:
		return
	## global_position, not position: this node is welded to the player every
	## frame, and the icon is deliberately somewhere else entirely.
	sprite.global_position = anchor + Vector3(0.0, icon_height, 0.0)
	var colour := tint
	colour.a = alpha
	sprite.modulate = colour
	sprite.scale = Vector3.ONE * icon_scale


# -----------------------------------------------------------------------------
# ## ENG: Construction
# -----------------------------------------------------------------------------

## A quad on the floor with everything drawn inside one shader, the same
## approach TargetIndicator already uses. A quad rather than a TorusMesh
## because the arcs, the recovery rings and the jump arc all live at
## different radii and would otherwise be three meshes.
func _build_ring() -> void:
	_ring = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(ring_radius * 2.0, ring_radius * 2.0)
	_ring.mesh = plane
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)

	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode blend_add, depth_draw_never, depth_test_disabled, cull_disabled, unshaded;

uniform vec3 arc_color : source_color = vec3(0.8, 0.9, 1.0);
uniform float arc_alpha : hint_range(0.0, 1.0) = 0.0;
uniform float arc_angle = 0.0;
uniform float arc_span : hint_range(0.0, 1.0) = 1.0;
uniform float ring_glow = 1.5;
uniform float arc_width = 0.26;

uniform vec3 recovery_color : source_color = vec3(0.4, 1.0, 0.6);
uniform float recovery_time = 0.0;
uniform float recovery_alpha : hint_range(0.0, 1.0) = 0.0;

uniform float jump_alpha : hint_range(0.0, 1.0) = 0.0;
uniform float jump_progress : hint_range(0.0, 1.0) = 0.0;

const float PI2 = 6.28318530718;

// A band of `width` centred on `target`: FLAT across its thickness with a
// small feather at each edge.
//
// It used to be `1.0 - smoothstep(0.0, width, abs(d - target))`, which is a
// gradient spanning the whole width and has no flat part at all — at any
// thickness worth seeing it reads as a blurred donut rather than an arc.
// Caught by looking at a render, not by reading.
float band(float d, float target, float width) {
	float half_w = width * 0.5;
	float feather = max(width * 0.25, 0.012);
	float inner = smoothstep(target - half_w - feather, target - half_w, d);
	float outer = 1.0 - smoothstep(target + half_w, target + half_w + feather, d);
	return inner * outer;
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float dist = length(uv);
	if (dist > 1.0) {
		discard;
	}
	float ang = atan(uv.y, uv.x) - arc_angle;
	ang = mod(ang, PI2);

	// FOUR quarter arcs, each spanning arc_span OF ITS WHOLE QUARTER. That
	// means they meet into a closed ring at full stamina and open into four
	// separate arcs as it drains — which is exactly what the 2D cursor did
	// with its four _draw_arc() calls (quarter_length = PI*0.5 * ratio). An
	// earlier attempt here kept a permanent gap so four arcs "read as four";
	// that was a change to the design, not a fix, and it is reverted.
	float quarter = mod(ang, PI2 * 0.25);
	float in_arc = step(quarter, PI2 * 0.25 * arc_span);
	float arc_ring = band(dist, 0.82, arc_width) * in_arc * arc_alpha;

	// Recovery: two rings chasing round at different rates, plus a pulse.
	float pulse = sin(recovery_time) * 0.5 + 0.5;
	float sweep_a = fract(ang / PI2 - recovery_time / PI2);
	float sweep_b = fract(ang / PI2 - recovery_time / PI2 * 1.5);
	float grad_a = smoothstep(0.0, 0.3, sweep_a) * (1.0 - smoothstep(0.7, 1.0, sweep_a));
	float grad_b = smoothstep(0.0, 0.2, sweep_b) * (1.0 - smoothstep(0.8, 1.0, sweep_b));
	float rec = band(dist, 0.62, 0.07) * grad_a * 0.6;
	rec += band(dist, 0.72, 0.05) * grad_b * 0.4;
	rec *= pulse * recovery_alpha;

	// Inner glow, the one piece of the recovery effect the port dropped: the
	// 2D version filled a soft disc inside the rings that breathed with the
	// same pulse. Without it recovery is two thin sweeps and reads as noise.
	float inner_glow = (1.0 - smoothstep(0.0, 0.5, dist)) * pulse * recovery_alpha * 0.35;

	// Jump charge: a ring that closes as the charge builds.
	float jump = band(dist, 0.94, 0.05) * step(fract(ang / PI2), jump_progress) * jump_alpha;

	vec3 col = arc_color * arc_ring
		+ recovery_color * (rec + inner_glow)
		+ arc_color * jump;
	// No second opacity factor. The arcs' alpha is decided ONCE, in
	// _update_movement_state(), exactly as the 2D cursor decided it; this
	// shader used to multiply it again by 0.55 and turn a half-strength ring
	// into a quarter-strength one.
	float alpha = arc_ring + rec + inner_glow + jump;

	// unshaded ignores EMISSION entirely, so the glow has to be in ALBEDO.
	// The port set EMISSION and the ring simply never lit.
	ALBEDO = col * ring_glow;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
"""
	_ring_material = ShaderMaterial.new()
	_ring_material.shader = shader
	_ring.material_override = _ring_material


func _build_icons() -> void:
	_walk_sprite = _make_icon(walk_icon)
	_sprint_sprite = _make_icon(sprint_icon)
	## Same texture as sprint, tinted red — exactly what the cursor did for
	## "wants to run and cannot".
	_no_stamina_sprite = _make_icon(sprint_icon)


func _make_icon(texture: Texture2D) -> Sprite3D:
	if texture == null:
		return null
	var sprite := Sprite3D.new()
	sprite.texture = texture
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.no_depth_test = true
	sprite.shaded = false
	sprite.pixel_size = icon_pixel_size
	sprite.position = Vector3(0.0, icon_height, 0.0)
	sprite.visible = false
	add_child(sprite)
	return sprite
