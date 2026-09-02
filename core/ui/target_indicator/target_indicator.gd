extends Node3D
class_name TargetIndicator

## Lookup group carried by the ONE instance that marks a move destination.
## HUDComponent puts its `target_indicator` in it and deliberately leaves
## `candidate_indicator` out.
##
## NOTHING READS IT TODAY. Its only consumer was the ground stamina ring,
## which hung the walk/sprint icon over the destination marker; that ring is
## gone and the icons live inside StaminaGauge in the HUD. The group is kept
## rather than deleted on its own because the move-destination marker itself
## goes away with click-to-move in the isometric removal — one deletion, not
## two.
const GROUP_MOVE_TARGET: StringName = &"move_target_indicator"

# === ВИЗУАЛЬНЫЕ КОМПОНЕНТЫ ===
@onready var ground_decal: MeshInstance3D = $GroundDecal
var hover_ring: MeshInstance3D
var arrow_mesh: MeshInstance3D
var arrow_root: Node3D

# === НАСТРОЙКИ ===
@export_group("Visual Settings")
@export var appear_duration: float = 0.3
@export var hover_height: float = 0.15
@export var ring_radius: float = 0.8

@export_group("Animation")
@export var wave_speed: float = 2.0
@export var rotation_speed: float = 0.3
@export var hover_speed: float = 1.0
@export var hover_amplitude: float = 0.05

@export var arrow_orbit_radius: float = 1.5
@export var arrow_far_distance: float = 10.0
@export var arrow_near_distance: float = 3.0

@export_group("Colors - Sci-Fi Palette")
@export var color_walk: Color = Color(0.0, 1.0, 0.8, 0.9)
@export var color_run: Color = Color(1.0, 0.53, 0.0, 0.9)
@export var color_invalid: Color = Color(1.0, 0.0, 0.27, 0.9)

## SECOND ROLE: an interaction candidate, not a move order. Same node type,
## same appear/disappear, different palette — see show_candidate().
##
## Two colours because the two states mean different things to the player:
## dim = pressing F walks the character over, bright = pressing F acts right
## now. Which one applies is decided by InteractComponent, not here.
@export_group("Colors - Interaction Candidate")
## "I will walk there."
@export var color_candidate: Color = Color(0.55, 0.62, 0.70, 0.55)
## "I can reach it from here."
@export var color_in_reach: Color = Color(0.95, 0.85, 0.35, 0.9)

@export_group("Role")
## Build the ground decal only, with no hover ring and no arrow.
##
## The arrow points back at the player, which is exactly right for "your
## destination is over there" and pure noise on a thing lying at your feet;
## the ring is a second animated element competing with the decal for the
## same reading. A candidate marker wants one quiet shape, so the two are not
## created at all rather than created and hidden — a hidden TorusMesh with a
## shader still costs its setup every spawn.
@export var decal_only: bool = false

# === СОСТОЯНИЕ ===
var is_visible_indicator := false
var time_alive := 0.0
var is_running := false
var current_color := Color.WHITE
## Which of the two palettes _update_color() reads. Set by show_candidate() /
## show_at_position(), never guessed from state.
var _is_candidate_role := false
var _candidate_in_reach := false

# === МАТЕРИАЛЫ ===
var ground_material: ShaderMaterial
var ring_material: ShaderMaterial
var arrow_material: ShaderMaterial
var player_ref: Node3D = null

# ============================================
# ИНИЦИАЛИЗАЦИЯ
# ============================================
func _ready():
	visible = false
	_create_ground()
	if decal_only:
		return
	_create_hover_ring()
	_create_arrow() 

# === Ground Decal ===
func _create_ground():
	if not ground_decal:
		ground_decal = MeshInstance3D.new()
		add_child(ground_decal)
	var plane = PlaneMesh.new()
	plane.size = Vector2(ring_radius * 2.5, ring_radius * 2.5)
	plane.subdivide_width = 32
	plane.subdivide_depth = 32
	ground_decal.mesh = plane
	ground_decal.position.y = -hover_height + 0.01
	ground_decal.rotation.x = 0

	var shader = Shader.new()
	shader.code = """
shader_type spatial;
render_mode blend_add, depth_draw_opaque, cull_disabled, unshaded;

uniform vec3 base_color : source_color = vec3(0.0, 1.0, 0.8);
uniform float time_param;
uniform float wave_speed;
uniform float global_alpha : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float dist = length(uv);
	float fade = 1.0 - smoothstep(0.0, 1.0, dist);
	float rings = sin(dist * 15.0 - time_param * wave_speed) * 0.5 + 0.5;
	rings = pow(rings, 3.0);
	float scanline = sin(UV.y * 80.0 + time_param * 3.0) * 0.5 + 0.5;
	float pattern = rings * scanline * fade;
	ALBEDO = base_color;
	EMISSION = base_color * pattern * 2.0;
	ALPHA = pattern * 0.3 * global_alpha;
}
"""
	ground_material = ShaderMaterial.new()
	ground_material.shader = shader
	_update_ground_color(color_walk)
	ground_decal.material_override = ground_material

# === Hover Ring ===
func _create_hover_ring():
	hover_ring = MeshInstance3D.new()
	add_child(hover_ring)

	var torus := TorusMesh.new()
	torus.inner_radius = ring_radius * 0.75
	torus.outer_radius = ring_radius * 0.95
	torus.rings = 64
	torus.ring_segments = 64
	hover_ring.mesh = torus

	# Кольцо чуть над землёй
	hover_ring.position.y = hover_height * 1.2
	hover_ring.rotation_degrees = Vector3.ZERO  # лежит ровно по земле

	# === Шейдер в стиле sci-fi голограммы ===
	var shader = Shader.new()
	shader.code = """
shader_type spatial;
render_mode blend_add, cull_disabled, unshaded;

uniform vec3 base_color : source_color = vec3(0.0, 1.0, 0.8);
uniform float time_param;
uniform float global_alpha : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;

	// Голографические вращающиеся линии по окружности
	float angle = atan(uv.y, uv.x);
	float ring_pattern = abs(sin(angle * 25.0 + time_param * 3.0));

	// Мягкий пульс от центра
	float radial_fade = smoothstep(0.6, 1.0, length(uv));

	float pulse = sin(time_param * 4.0) * 0.5 + 0.5;
	float intensity = (1.0 - radial_fade) * ring_pattern * pulse;

	ALBEDO = base_color;
	EMISSION = base_color * (1.2 + intensity * 3.0);
	ALPHA = intensity * 0.35 * global_alpha;
}
"""
	ring_material = ShaderMaterial.new()
	ring_material.shader = shader
	hover_ring.material_override = ring_material

# === Arrow ===
func _create_arrow():
	arrow_root = Node3D.new()
	add_child(arrow_root)

	arrow_mesh = MeshInstance3D.new()
	arrow_root.add_child(arrow_mesh)  # СНАЧАЛА добавляем в дерево!
	
	# ========================================
	# Подставь свой .mesh / .res файл
	# ========================================
	var custom_mesh = preload("res://assets/tres/arrow_mesh.tres")
	arrow_mesh.mesh = custom_mesh

	#var cone: CylinderMesh = CylinderMesh.new()
	#cone.top_radius = 0.0
	#cone.bottom_radius = 0.15
	#cone.height = 0.4
	#cone.rings = 1
	#cone.radial_segments = 32
	#arrow_mesh.mesh = cone

	# Разворачиваем меш так, чтобы остриё смотрело вдоль -Z
	# CylinderMesh по умолчанию вдоль +Y. Переводим +Y -> +Z (−90° по X),
	# затем +Z -> −Z (180° по Y).
	arrow_mesh.rotation_degrees = Vector3(-90, 0, 0)

	# Позицию держим на родителе
	arrow_root.position = Vector3(arrow_orbit_radius, hover_height * 1.5, 0)

	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode blend_add, cull_disabled, unshaded;

uniform vec3 base_color : source_color = vec3(0.0, 1.0, 0.8);
uniform float time_param;
uniform float global_alpha : hint_range(0.0, 1.0) = 1.0;

void fragment() {
    // базовый цвет
    ALBEDO = base_color;

    // пульс как у кольца
    float pulse = sin(time_param * 4.0) * 0.5 + 0.5;

    // сканлайны как у земли
    float scanline = sin(UV.y * 80.0 + time_param * 3.0) * 0.5 + 0.5;

    // fade от центра стрелки
    float dist = length(UV * 2.0 - 1.0);
    float fade = 1.0 - smoothstep(0.0, 1.0, dist);

    // итоговый паттерн
    float intensity = (pulse * 0.7 + scanline * 0.3) * fade;

    EMISSION = base_color * (1.2 + intensity * 3.0);
    ALPHA = intensity * 0.4 * global_alpha;
}
"""
	arrow_material = ShaderMaterial.new()
	arrow_material.shader = shader
	arrow_mesh.material_override = arrow_material
	arrow_root.visible = false
# ============================================
# ОСНОВНЫЕ МЕТОДЫ
# ============================================
func show_at_position(pos: Vector3, is_run: bool = false):
	global_position = pos + Vector3.UP * hover_height
	_is_candidate_role = false
	is_running = is_run
	if not is_visible_indicator:
		_appear()
	_update_color()

func hide_indicator():
	if is_visible_indicator:
		_disappear()


## Shows this indicator as an INTERACTION CANDIDATE rather than a move order:
## the thing the player is currently aimed at, dim while it still needs
## walking to and bright once it is within arm's reach.
##
## Takes a position and a boolean and nothing else. This node knows nothing
## about items, equipment or pickup — InteractComponent decides what is
## targeted and HUDComponent decides that the answer should be drawn; this
## only draws it. Same split show_at_position() already has with
## ClickToMoveSystem.
##
## Safe to call every frame: repositioning an already-visible indicator does
## not restart the appear tween.
func show_candidate(pos: Vector3, in_reach: bool) -> void:
	global_position = pos + Vector3.UP * hover_height
	_is_candidate_role = true
	_candidate_in_reach = in_reach
	if not is_visible_indicator:
		_appear()
	_update_color()

func show_invalid_click(pos: Vector3):
	global_position = pos + Vector3.UP * hover_height
	_is_candidate_role = false
	_update_color(true)
	_appear()
	await get_tree().create_timer(0.5).timeout
	_disappear()

# ============================================
# АНИМАЦИИ
# ============================================
func _appear():
	visible = true
	is_visible_indicator = true
	time_alive = 0.0
	if ground_material:
		ground_material.set_shader_parameter("global_alpha", 0.0)
	if ring_material:
		ring_material.set_shader_parameter("global_alpha", 0.0)
	var tween = create_tween()
	tween.tween_method(_set_alpha, 0.0, 1.0, appear_duration).set_ease(Tween.EASE_OUT)

func _set_alpha(v: float):
	if ground_material:
		ground_material.set_shader_parameter("global_alpha", v)
	if ring_material:
		ring_material.set_shader_parameter("global_alpha", v)

func _disappear():
	var tween = create_tween()
	tween.tween_method(_set_alpha, 1.0, 0.0, appear_duration * 0.5).set_ease(Tween.EASE_IN)
	await tween.finished
	visible = false
	is_visible_indicator = false
	time_alive = 0.0

# ============================================
# ОБНОВЛЕНИЕ
# ============================================
func _process(delta: float):
	if not is_visible_indicator:
		return
	time_alive += delta

	if ground_material:
		ground_material.set_shader_parameter("time_param", time_alive)
		ground_material.set_shader_parameter("wave_speed", wave_speed)
	if ring_material:
		ring_material.set_shader_parameter("time_param", time_alive)

	rotate_y(delta * rotation_speed)
	if hover_ring:
		hover_ring.position.y = hover_height * 0.8 + sin(time_alive * hover_speed) * hover_amplitude
	
	if player_ref and arrow_root:
		var dist := global_position.distance_to(player_ref.global_position)
		
		# Минимальный порог для безопасности
		const MIN_DISTANCE := 0.5
		
		if dist > MIN_DISTANCE:
			var dir := (player_ref.global_position - global_position).normalized()
			var new_pos := global_position + dir * arrow_orbit_radius
			
			# КРИТИЧЕСКАЯ ПРОВЕРКА: проверяем дистанцию между arrow_root и целью
			var look_at_distance := new_pos.distance_to(player_ref.global_position)
			
			if look_at_distance > 0.1:  # Godot требует минимум ~0.01, берём с запасом
				arrow_root.global_position = new_pos
				arrow_root.look_at(player_ref.global_position, Vector3.UP)
				
				# Масштаб и видимость
				if dist > arrow_near_distance:
					var scale_factor: float = clamp(dist / arrow_far_distance, 0.5, 2.0) * 1.5
					arrow_root.scale = Vector3.ONE * scale_factor
					arrow_root.visible = true
				else:
					arrow_root.visible = false
			else:
				# Дистанция для look_at слишком мала
				arrow_root.visible = false
		else:
			# Слишком близко к индикатору
			arrow_root.visible = false
# ============================================
# ЦВЕТ
# ============================================
func _update_color(is_error: bool = false):
	var target: Color
	if is_error:
		target = color_invalid
	elif _is_candidate_role:
		target = color_in_reach if _candidate_in_reach else color_candidate
	elif is_running:
		target = color_run
	else:
		target = color_walk
	current_color = target
	_update_ground_color(target)
	_update_ring_color(target)
	_update_arrow_color(target)

func _update_ground_color(c: Color):
	if ground_material:
		ground_material.set_shader_parameter("base_color", Vector3(c.r, c.g, c.b))

func _update_ring_color(c: Color):
	if ring_material:
		ring_material.set_shader_parameter("base_color", Vector3(c.r, c.g, c.b))

func _update_arrow_color(c: Color):
	if arrow_material:
		arrow_material.set_shader_parameter("base_color", Vector3(c.r, c.g, c.b))

# ============================================
# ДОПОЛНИТЕЛЬНО
# ============================================
func set_player_reference(player: Node3D) -> void:
	player_ref = player
