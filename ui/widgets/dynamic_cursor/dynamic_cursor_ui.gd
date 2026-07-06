extends Control
class_name MouseCursorUI

signal button_3d_clicked(button_name: String)

# === НАСТРОЙКИ КУРСОРА ===
@export_group("Основной курсор")
@export var cursor_radius: float = 8.0
@export var cursor_thickness: float = 2.0
@export var cursor_color: Color = Color.WHITE

# === НАСТРОЙКИ ИНДИКАЦИИ ДВИЖЕНИЯ ===
@export_group("Индикация движения")
@export var walk_indicator_texture: Texture2D  # 🔥 Текстура ходьбы
@export var sprint_indicator_texture: Texture2D  # 🔥 Текстура спринта
@export var indicator_size: Vector2 = Vector2(32, 32)
@export var indicator_offset: float = 16.0
@export var indicator_fade_speed: float = 8.0  # 🔥 Скорость появления/исчезновения
@export var indicator_scale_bounce: float = 1.2  # 🔥 Масштаб при появлении

# === НАСТРОЙКИ ДУГ СПРИНТА ===
@export_group("Дуги спринта")
@export var sprint_arc_thickness: float = 6.0
@export var sprint_arc_color: Color = Color(0.8, 0.9, 1.0, 1.0)
@export var sprint_animation_speed: float = 2.0

# === НАСТРОЙКИ ВОССТАНОВЛЕНИЯ ===
@export_group("Восстановление стамины")
@export var recovery_ring_thickness: float = 3.0
@export var recovery_pulse_speed: float = 3.0
@export var recovery_glow_color: Color = Color(0.4, 1.0, 0.6, 1.0)
@export var recovery_show_inner_glow: bool = true
@export var recovery_gradient_segments: int = 64  # 🔥 Сегменты для градиента

# === НАСТРОЙКИ СТАТИЧНОСТИ ===
@export_group("Статичность")
@export var mouse_stationary_px: float = 2.0
@export var player_move_stationary_speed: float = 0.05

# === НАСТРОЙКИ 3D КУРСОРА ===
@export_group("3D UI")
@export var bracket_3d_width: float = 8.0
@export var bracket_3d_height: float = 20.0
@export var bracket_3d_offset: float = 12.0  # Начальное расстояние от центра
@export var bracket_3d_max_offset: float = 30.0  # Максимальное расстояние при наведении
@export var bracket_3d_color: Color = Color(0.3, 0.8, 1.0, 0.9)
@export var bracket_3d_animation_speed: float = 8.0

# === СОСТОЯНИЕ 3D UI ===
var is_over_3d_ui: bool = false
var is_over_3d_button: bool = false
var current_3d_button_name: String = ""
var bracket_offset_current: float = 12.0

# === ССЫЛКИ ===
@onready var player: CharacterBody3D = $".."
@onready var stamina_manager: StaminaManager = $"../StaminaManager"

# === СОСТОЯНИЕ КУРСОРА ===
var current_cursor_color: Color
var cursor_position: Vector2 = Vector2.ZERO
var mouse_stationary_timer: float = 0.0
var last_mouse_pos: Vector2 = Vector2.ZERO
var last_player_pos: Vector3 = Vector3.ZERO

# === СОСТОЯНИЕ ИНДИКАЦИИ ДВИЖЕНИЯ ===
var is_player_moving: bool = false
var is_player_sprinting: bool = false
var wants_to_sprint: bool = false  # 🔥 Игрок хочет бежать, но не может
var sprint_progress: float = 0.0
var sprint_arc_angle: float = 0.0

# 🔥 Альфа для каждого индикатора отдельно
var walk_indicator_alpha: float = 0.0
var sprint_indicator_alpha: float = 0.0
var no_stamina_indicator_alpha: float = 0.0  # Красный спринт

# 🔥 Масштаб для bounce эффекта
var walk_indicator_scale: float = 1.0
var sprint_indicator_scale: float = 1.0
var no_stamina_indicator_scale: float = 1.0

var sprint_arcs_alpha: float = 0.0

# === СОСТОЯНИЕ СТАМИНЫ ДЛЯ UI ===
var current_stamina_ratio: float = 1.0
var is_stamina_recovering: bool = false
var recovery_pulse_time: float = 0.0

# === СОСТОЯНИЕ ПРЫЖКА ===
var jump_arc_alpha: float = 0.0
var jump_arc_progress: float = 0.0
var jump_is_charging: bool = false
var jump_animation_tween: Tween
var jump_time: float = 0.0

# === ТВИНЫ ===
var walk_tween: Tween
var sprint_tween: Tween
var no_stamina_tween: Tween
var arcs_tween: Tween

func _ready() -> void:
	current_cursor_color = cursor_color
	PlayerState.mode_changed.connect(_on_player_state_mode_changed)
	_apply_cursor_for_mode(PlayerState.mode)

	if player:
		last_player_pos = player.global_transform.origin
		
		if stamina_manager == null:
			stamina_manager = player.get_node_or_null("StaminaManager")
			if stamina_manager == null:
				push_warning("⚠️ StaminaManager не найден!")
		
		# Подключаемся к сигналам стамины
		if stamina_manager:
			stamina_manager.stamina_changed.connect(_on_stamina_changed)
			stamina_manager.stamina_depleted.connect(_on_stamina_depleted)
			stamina_manager.stamina_recovered.connect(_on_stamina_recovered)
			stamina_manager.jump_performed.connect(_on_jump_performed)
			print("✅ Курсор: Подключен к StaminaManager")
	else:
		push_error("❌ Player не найден!")
			
	last_mouse_pos = get_viewport().get_mouse_position()
	
func _on_player_state_mode_changed(_old_mode, new_mode) -> void:
	_apply_cursor_for_mode(new_mode)

func _process(delta: float) -> void:
	if not player:
		return

	cursor_position = get_viewport().get_mouse_position()

	# 1) Курсор стоит?
	var mouse_moved: bool = cursor_position.distance_to(last_mouse_pos) > mouse_stationary_px
	if mouse_moved:
		mouse_stationary_timer = 0.0
		last_mouse_pos = cursor_position
	else:
		mouse_stationary_timer += delta

	# 2) Игрок стоит?
	var player_pos: Vector3 = player.global_transform.origin
	var lin_speed: float = (player_pos - last_player_pos).length() / max(delta, 0.0001)
	last_player_pos = player_pos
	var player_stationary: bool = lin_speed <= player_move_stationary_speed

	# 3) Обновление состояния движения
	_update_movement_state(delta, player_stationary)
	# 6) Обновление 3D UI состояния
	_update_3d_ui_state(delta)

	# 4) Прыжок
	if jump_is_charging:
		jump_time += delta
	else:
		jump_time = 0.0
	
	# 5) Обновление состояния восстановления
	_update_recovery_state(delta)

	queue_redraw()

func _update_movement_state(delta: float, player_stationary: bool) -> void:
	var was_sprinting: bool = is_player_sprinting
	var was_moving: bool = is_player_moving
	
	is_player_moving = not player_stationary
	is_player_sprinting = player.is_currently_sprinting(player.velocity)
	
	# 🔥 ИСПРАВЛЕНА ЛОГИКА: Используем новый метод is_wanting_to_run()
	var wants_sprint = player.is_wanting_to_run() and is_player_moving
	var can_sprint = stamina_manager and stamina_manager.is_sprint_allowed()
	wants_to_sprint = wants_sprint and not can_sprint
	
	# Получаем прогресс спринта
	sprint_progress = player.get_sprint_blend()
	
	# Обновляем стамину из StaminaManager
	if stamina_manager:
		current_stamina_ratio = stamina_manager.get_stamina_ratio()
	
	sprint_progress = clamp(sprint_progress, 0.0, 1.0)
	
	# 🔥 ЛОГИКА ИНДИКАТОРОВ
	if wants_to_sprint:
		# Игрок хочет бежать, но нет стамины → красный спринт
		_show_no_stamina_indicator()
	elif is_player_sprinting:
		# Игрок бежит → синий спринт
		_show_sprint_indicator()
	elif is_player_moving:
		# Игрок идёт → зелёный walk
		_show_walk_indicator()
	else:
		# Не движется → скрываем всё
		_hide_all_indicators()
	
	# Дуги видны ВСЕГДА когда есть стамина
	var target_arcs_alpha: float = current_stamina_ratio if is_player_moving else current_stamina_ratio * 0.5
	sprint_arcs_alpha = lerp(sprint_arcs_alpha, target_arcs_alpha, 6.0 * delta)
	
	if is_player_sprinting:
		sprint_arc_angle += sprint_animation_speed * delta * (0.5 + sprint_progress * 0.5)
		if sprint_arc_angle > TAU:
			sprint_arc_angle -= TAU
	else:
		sprint_arc_angle += 0.3 * delta
		if sprint_arc_angle > TAU:
			sprint_arc_angle -= TAU
	
	# Отслеживание зарядки прыжка
	var player_on_floor = player.is_on_floor()
	var jump_charging = Input.is_action_pressed("jump") and player_on_floor

	if jump_charging and not jump_is_charging:
		jump_is_charging = true
		jump_arc_alpha = 0.6
	elif not jump_charging and jump_is_charging:
		jump_is_charging = false
		if player_on_floor:
			jump_arc_alpha = 0.0

	jump_is_charging = jump_charging

# 🔥 ПОКАЗАТЬ ИНДИКАТОР ХОДЬБЫ
func _show_walk_indicator() -> void:
	if walk_indicator_alpha < 0.9:
		_animate_indicator_appear("walk")
	_animate_indicator_fade("sprint", 0.0)
	_animate_indicator_fade("no_stamina", 0.0)

# 🔥 ПОКАЗАТЬ ИНДИКАТОР СПРИНТА
func _show_sprint_indicator() -> void:
	if sprint_indicator_alpha < 0.9:
		_animate_indicator_appear("sprint")
	_animate_indicator_fade("walk", 0.0)
	_animate_indicator_fade("no_stamina", 0.0)

# 🔥 ПОКАЗАТЬ КРАСНЫЙ ИНДИКАТОР (НЕТ СТАМИНЫ)
func _show_no_stamina_indicator() -> void:
	if no_stamina_indicator_alpha < 0.9:
		_animate_indicator_appear("no_stamina")
	_animate_indicator_fade("walk", 0.0)
	_animate_indicator_fade("sprint", 0.0)

# 🔥 СКРЫТЬ ВСЕ ИНДИКАТОРЫ
func _hide_all_indicators() -> void:
	_animate_indicator_fade("walk", 0.0)
	_animate_indicator_fade("sprint", 0.0)
	_animate_indicator_fade("no_stamina", 0.0)

# 🔥 АНИМАЦИЯ ПОЯВЛЕНИЯ С BOUNCE
func _animate_indicator_appear(type: String) -> void:
	match type:
		"walk":
			if walk_tween:
				walk_tween.kill()
			walk_tween = create_tween()
			walk_tween.set_parallel(true)
			walk_tween.tween_property(self, "walk_indicator_alpha", 1.0, 0.2)
			walk_tween.tween_property(self, "walk_indicator_scale", indicator_scale_bounce, 0.1)
			walk_tween.chain().tween_property(self, "walk_indicator_scale", 1.0, 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		
		"sprint":
			if sprint_tween:
				sprint_tween.kill()
			sprint_tween = create_tween()
			sprint_tween.set_parallel(true)
			sprint_tween.tween_property(self, "sprint_indicator_alpha", 1.0, 0.2)
			sprint_tween.tween_property(self, "sprint_indicator_scale", indicator_scale_bounce, 0.1)
			sprint_tween.chain().tween_property(self, "sprint_indicator_scale", 1.0, 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		
		"no_stamina":
			if no_stamina_tween:
				no_stamina_tween.kill()
			no_stamina_tween = create_tween()
			no_stamina_tween.set_parallel(true)
			no_stamina_tween.tween_property(self, "no_stamina_indicator_alpha", 1.0, 0.2)
			no_stamina_tween.tween_property(self, "no_stamina_indicator_scale", indicator_scale_bounce, 0.1)
			no_stamina_tween.chain().tween_property(self, "no_stamina_indicator_scale", 1.0, 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

# 🔥 АНИМАЦИЯ ИСЧЕЗНОВЕНИЯ
func _animate_indicator_fade(type: String, target_alpha: float) -> void:
	match type:
		"walk":
			if walk_tween:
				walk_tween.kill()
			walk_tween = create_tween()
			walk_tween.tween_property(self, "walk_indicator_alpha", target_alpha, 0.3)
		
		"sprint":
			if sprint_tween:
				sprint_tween.kill()
			sprint_tween = create_tween()
			sprint_tween.tween_property(self, "sprint_indicator_alpha", target_alpha, 0.3)
		
		"no_stamina":
			if no_stamina_tween:
				no_stamina_tween.kill()
			no_stamina_tween = create_tween()
			no_stamina_tween.tween_property(self, "no_stamina_indicator_alpha", target_alpha, 0.3)

# 🔥 Обновление состояния восстановления
func _update_recovery_state(delta: float) -> void:
	if not stamina_manager:
		return
	
	is_stamina_recovering = stamina_manager.is_recovering()
	
	if is_stamina_recovering:
		recovery_pulse_time += delta * recovery_pulse_speed
		if recovery_pulse_time > TAU:
			recovery_pulse_time -= TAU

func _draw() -> void:
	# Внешний контур основного курсора
	_draw_circle_outline(cursor_position, cursor_radius, current_cursor_color, cursor_thickness)

	# Внутренний мягкий круг
	var inner_color: Color = current_cursor_color
	inner_color.a *= 0.3
	draw_circle(cursor_position, cursor_radius * 0.3, inner_color)

	# === ИНДИКАЦИЯ ДВИЖЕНИЯ ===
	
	# 🔥 Индикаторы (walk/sprint/no_stamina)
	_draw_movement_indicators()

	# 🔥 Дуги стамины
	if sprint_arcs_alpha > 0.01:
		_draw_sprint_arcs()
	
	# 🔥 Эффект восстановления стамины (с шейдером)
	if is_stamina_recovering and current_stamina_ratio < 0.95:
		_draw_recovery_effect_shader()
		
	# Дуга прыжка
	if jump_arc_alpha > 0.0:
		_draw_jump_arc()
		
	# === 3D UI КУРСОР ===
	if is_over_3d_ui:
		_draw_3d_ui_brackets()
		
func _update_3d_ui_state(delta: float) -> void:
	# Проверяем raycast для 3D UI
	var viewport := get_viewport()
	var cam := viewport.get_camera_3d()
	if not cam:
		is_over_3d_ui = false
		is_over_3d_button = false
		return
	
	var mouse_pos: Vector2 = cursor_position
	var from: Vector3 = cam.project_ray_origin(mouse_pos)
	var dir: Vector3 = cam.project_ray_normal(mouse_pos)
	var to: Vector3 = from + dir * 1000.0
	
	var space := get_world_3d()
	if not space:
		return
	
	var direct_space := space.direct_space_state
	var params := PhysicsRayQueryParameters3D.create(from, to)
	params.collision_mask = 1 << 19  # Слой 20 (3D_GUI)
	
	var result := direct_space.intersect_ray(params)
	
	if result.is_empty():
		is_over_3d_ui = false
		is_over_3d_button = false
		bracket_offset_current = lerp(bracket_offset_current, bracket_3d_offset, bracket_3d_animation_speed * delta)
		return
	
	# Попали в 3D UI область
	var collider: Node = result.get("collider")
	if collider:
		is_over_3d_ui = true
		
		# Проверяем, это кнопка?
		if collider is StaticBody3D:
			var parent = collider.get_parent()
			if parent and parent is MeshInstance3D:
				is_over_3d_button = true
				current_3d_button_name = parent.name
				# Раздвигаем скобки
				bracket_offset_current = lerp(bracket_offset_current, bracket_3d_max_offset, bracket_3d_animation_speed * delta)
			else:
				is_over_3d_button = false
				bracket_offset_current = lerp(bracket_offset_current, bracket_3d_offset, bracket_3d_animation_speed * delta)
		else:
			is_over_3d_button = false
			bracket_offset_current = lerp(bracket_offset_current, bracket_3d_offset, bracket_3d_animation_speed * delta)

func get_world_3d() -> World3D:
	if player:
		return player.get_world_3d()
	return get_viewport().get_world_3d()

# 🔥 Рисуем индикаторы движения
func _draw_movement_indicators() -> void:
	var indicator_pos = cursor_position + Vector2(0, cursor_radius + indicator_offset)
	
	# 1. Индикатор ходьбы (зелёный)
	if walk_indicator_alpha > 0.01 and walk_indicator_texture:
		var size = indicator_size * walk_indicator_scale
		var texture_rect = Rect2(indicator_pos - size * 0.5, size)
		var modulate_color = Color.WHITE
		modulate_color.a = walk_indicator_alpha
		draw_texture_rect(walk_indicator_texture, texture_rect, false, modulate_color)
	
	# 2. Индикатор спринта (синий)
	if sprint_indicator_alpha > 0.01 and sprint_indicator_texture:
		var size = indicator_size * sprint_indicator_scale
		var texture_rect = Rect2(indicator_pos - size * 0.5, size)
		var modulate_color = Color.WHITE
		modulate_color.a = sprint_indicator_alpha
		draw_texture_rect(sprint_indicator_texture, texture_rect, false, modulate_color)
	
	# 3. Индикатор нехватки стамины (красный спринт)
	if no_stamina_indicator_alpha > 0.01 and sprint_indicator_texture:
		var size = indicator_size * no_stamina_indicator_scale
		var texture_rect = Rect2(indicator_pos - size * 0.5, size)
		var modulate_color = Color.RED  # 🔥 КРАСНЫЙ!
		modulate_color.a = no_stamina_indicator_alpha
		draw_texture_rect(sprint_indicator_texture, texture_rect, false, modulate_color)

func _draw_sprint_arcs() -> void:
	var base_color: Color = sprint_arc_color

	# Меняем цвет в зависимости от уровня стамины
	if current_stamina_ratio > 0.5:
		var t: float = (1.0 - current_stamina_ratio) * 2.0
		base_color = base_color.lerp(Color(1.0, 1.0, 0.0), t)
	elif current_stamina_ratio > 0.25:
		var t: float = (0.5 - current_stamina_ratio) * 4.0
		base_color = Color(1.0, 1.0, 0.0).lerp(Color(1.0, 0.5, 0.0), t)
	else:
		var t: float = (0.25 - current_stamina_ratio) * 4.0
		base_color = Color(1.0, 0.5, 0.0).lerp(Color(1.0, 0.0, 0.0), t)

	base_color.a *= sprint_arcs_alpha

	var arc_radius: float = cursor_radius + 4.0
	
	var quarter_length: float
	if is_player_sprinting:
		quarter_length = PI * 0.5 * sprint_progress * current_stamina_ratio
	else:
		quarter_length = PI * 0.5 * current_stamina_ratio

	for i in range(4):
		var base_angle: float = i * PI * 0.5 + sprint_arc_angle
		_draw_arc(cursor_position, arc_radius, base_angle, base_angle + quarter_length, base_color, sprint_arc_thickness)

# 🔥 ШЕЙДЕРНЫЙ эффект восстановления стамины
func _draw_recovery_effect_shader() -> void:
	var pulse_alpha = (sin(recovery_pulse_time) * 0.5 + 0.5)
	
	var recovery_radius = cursor_radius + 8.0 + sin(recovery_pulse_time * 2.0) * 2.0
	var outer_radius = recovery_radius + 4.0
	
	# 🔥 Рисуем градиентное кольцо (имитация шейдера через много сегментов)
	var segments = recovery_gradient_segments
	for i in range(segments):
		var angle_start = (TAU / segments) * i
		var angle_end = (TAU / segments) * (i + 1)
		
		# 🔥 Градиент от зелёного к прозрачному (эффект зарядки)
		var gradient_progress = fmod(i / float(segments) - recovery_pulse_time / TAU + 1.0, 1.0)
		var gradient_alpha = smoothstep(0.0, 0.3, gradient_progress) * (1.0 - smoothstep(0.7, 1.0, gradient_progress))
		
		var segment_color = recovery_glow_color
		segment_color.a = gradient_alpha * pulse_alpha * 0.6
		
		_draw_arc(cursor_position, recovery_radius, angle_start, angle_end, segment_color, recovery_ring_thickness)
	
	# 🔥 Второе внешнее кольцо
	for i in range(segments):
		var angle_start = (TAU / segments) * i
		var angle_end = (TAU / segments) * (i + 1)
		
		var gradient_progress = fmod(i / float(segments) - recovery_pulse_time / TAU * 1.5 + 1.0, 1.0)
		var gradient_alpha = smoothstep(0.0, 0.2, gradient_progress) * (1.0 - smoothstep(0.8, 1.0, gradient_progress))
		
		var segment_color = recovery_glow_color
		segment_color.a = gradient_alpha * pulse_alpha * 0.4
		
		_draw_arc(cursor_position, outer_radius, angle_start, angle_end, segment_color, recovery_ring_thickness * 0.6)
	
	# 🔥 Внутреннее свечение
	if recovery_show_inner_glow:
		var inner_glow_color = recovery_glow_color
		inner_glow_color.a = pulse_alpha * 0.3
		draw_circle(cursor_position, cursor_radius + 3.0, inner_glow_color)

func _draw_arc(center: Vector2, radius: float, start_angle: float, end_angle: float, color: Color, thickness: float) -> void:
	var segments: int = max(8, int(abs(end_angle - start_angle) * radius * 0.5))
	var angle_step: float = (end_angle - start_angle) / segments
	
	for i in range(segments):
		var angle1: float = start_angle + i * angle_step
		var angle2: float = start_angle + (i + 1) * angle_step
		
		var point1: Vector2 = center + Vector2(cos(angle1), sin(angle1)) * radius
		var point2: Vector2 = center + Vector2(cos(angle2), sin(angle2)) * radius
		
		draw_line(point1, point2, color, thickness)

func _draw_circle_outline(center: Vector2, radius: float, color: Color, thickness: float) -> void:
	var segments: int = 32
	var points: Array[Vector2] = []
	points.resize(segments + 1)

	for i in range(segments + 1):
		var angle: float = (i / float(segments)) * TAU
		points[i] = center + Vector2(cos(angle), sin(angle)) * radius

	for i in range(segments):
		draw_line(points[i], points[i + 1], color, thickness)
		
func _draw_jump_arc() -> void:
	var jump_radius = cursor_radius + 12.0
	var jump_color: Color = Color(0.4, 0.8, 1.0, jump_arc_alpha)

	if current_stamina_ratio > 0.5:
		jump_color = jump_color.lerp(Color(1, 1, 0), (1.0 - current_stamina_ratio) * 2.0)
	elif current_stamina_ratio > 0.25:
		jump_color = Color(1, 1, 0).lerp(Color(1, 0.5, 0), (0.5 - current_stamina_ratio) * 4.0)
	else:
		jump_color = Color(1, 0.5, 0).lerp(Color(1, 0, 0), (0.25 - current_stamina_ratio) * 4.0)

	jump_color.a *= jump_arc_alpha

	if jump_is_charging:
		var base_arc_length = PI * 0.2
		var pulse = sin(jump_time * 20.0) * 0.1
		var total_arc_length = base_arc_length + pulse + (PI * 0.3 * jump_arc_progress)
		var center_angle = PI * 0.5
		var start_angle = center_angle - total_arc_length * 0.5
		var end_angle = center_angle + total_arc_length * 0.5
		_draw_arc(cursor_position, jump_radius, start_angle, end_angle, jump_color, 2.0)
	else:
		var full_progress = clamp(jump_arc_progress, 0.0, 1.0)
		var circle_center_angle = PI * 1.5
		var start_angle = circle_center_angle - TAU * 0.5 * full_progress
		var end_angle = circle_center_angle + TAU * 0.5 * full_progress

		if full_progress >= 1.0:
			_draw_circle_outline(cursor_position, jump_radius, jump_color, 2.0)
		else:
			_draw_arc(cursor_position, jump_radius, start_angle, end_angle, jump_color, 2.0)

func _draw_3d_ui_brackets() -> void:
	var color = bracket_3d_color
	if is_over_3d_button:
		color = bracket_3d_color.lightened(0.3)
	
	# Левая скобка [
	var left_offset = bracket_offset_current
	_draw_bracket_left(cursor_position.x - left_offset, cursor_position.y, bracket_3d_width, bracket_3d_height, color)
	
	# Правая скобка ]
	var right_offset = bracket_offset_current
	_draw_bracket_right(cursor_position.x + right_offset, cursor_position.y, bracket_3d_width, bracket_3d_height, color)

func _draw_bracket_left(x: float, y: float, width: float, height: float, color: Color) -> void:
	var half_h = height / 2.0
	var top = Vector2(x, y - half_h)
	var bottom = Vector2(x, y + half_h)
	var top_right = Vector2(x + width, y - half_h)
	var bottom_right = Vector2(x + width, y + half_h)
	
	draw_line(top, bottom, color, 2.5, true)
	draw_line(top, top_right, color, 2.5, true)
	draw_line(bottom, bottom_right, color, 2.5, true)

func _draw_bracket_right(x: float, y: float, width: float, height: float, color: Color) -> void:
	var half_h = height / 2.0
	var top = Vector2(x, y - half_h)
	var bottom = Vector2(x, y + half_h)
	var top_left = Vector2(x - width, y - half_h)
	var bottom_left = Vector2(x - width, y + half_h)
	
	draw_line(top, bottom, color, 2.5, true)
	draw_line(top, top_left, color, 2.5, true)
	draw_line(bottom, bottom_left, color, 2.5, true)

func _on_jump_performed() -> void:
	if jump_animation_tween:
		jump_animation_tween.kill()
	jump_animation_tween = create_tween()
	jump_animation_tween.set_parallel(true)
	
	jump_animation_tween.tween_method(_set_jump_arc_progress, 0.0, 1.0, 0.15)
	jump_animation_tween.tween_method(_set_jump_arc_progress, 1.0, 0.0, 0.25).set_delay(0.15)
	jump_animation_tween.tween_method(_set_jump_arc_alpha, 0.8, 0.0, 0.4)
	
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if is_over_3d_button:
			_on_3d_button_clicked(current_3d_button_name)
			get_viewport().set_input_as_handled()

func _on_3d_button_clicked(button_name: String) -> void:
	button_3d_clicked.emit(button_name)

func _set_jump_arc_progress(value: float) -> void:
	jump_arc_progress = value

func _set_jump_arc_alpha(value: float) -> void:
	jump_arc_alpha = value

func _on_stamina_changed(current_stamina: float, max_stamina: float) -> void:
	current_stamina_ratio = current_stamina / max_stamina

func _on_stamina_depleted() -> void:
	print("💥 Курсор: Стамина истощена!")
	
## Кастомный курсор (нарисованный вручную) актуален только в ON_FOOT.
## В остальных режимах (MENU, VEHICLE_HOVER, TUBE_TRANSIT) прячем его
## и возвращаем системный курсор — иначе в меню не видно, куда кликать.
func _apply_cursor_for_mode(mode) -> void:
	if mode == PlayerState.Mode.ON_FOOT:
		Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
		visible = true
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		visible = false

func _on_stamina_recovered() -> void:
	print("✨ Курсор: Стамина восстановлена!")
