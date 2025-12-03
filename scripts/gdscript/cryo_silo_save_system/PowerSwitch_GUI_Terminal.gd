extends Control
class_name PowerSwitchGUI

@onready var btn_toggle: Button = $btn_Toggle  # Переименуем в btn_toggle, но в сцене остается btn_Boot
@onready var _3d_screen: MeshInstance3D = $"../3D_Screen"
#@onready var debug_gui_2d: Control = $"../CryoUIController"
@onready var zone_terminal: ZoneTerminal = $"../ZoneTerminal"

@export var on_texture: Texture2D
@export var off_texture: Texture2D

# 🔥 ВИБРАЦИЯ КНОПКИ
var _is_vibrating: bool = false
var _vibration_tween: Tween
var _vibration_timer: Timer


var _base_global_pos: Vector2
var _tween: Tween

var _pulse_timer: Timer
var _pulse_phase: float = 0.0  # Фаза пульсации 0..1

# Переменные для кружка
var _circle_radius: float = 40.0
var _circle_center: Vector2
var _circle_current_pos: Vector2
var _is_dragging: bool = false
var _is_hovering: bool = false
var _is_over_button: bool = false
var _circle_color: Color = Color(0.4, 0.7, 1.0, 0.8)
var _circle_hover_color: Color = Color(0.3, 0.5, 0.8, 0.6)
var _circle_area: Area2D
var _circle_collision: CollisionShape2D
var _animation_time: float = 0.0

var _circle_ghost_visible: bool = false  # 🔥 Показывать ли "след" кружка
var _circle_ghost_pos: Vector2  # 🔥 Позиция "следа"

# Состояние системы
var _is_system_on: bool = false

func _ready() -> void:
	btn_toggle.z_index = 10
	btn_toggle.z_as_relative = false
	btn_toggle.pressed.connect(_on_btn_toggle_pressed)
	
	# ⚡ КРИТИЧЕСКИ ВАЖНО: блокируем прямое взаимодействие с кнопкой
	btn_toggle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn_toggle.focus_mode = Control.FOCUS_NONE
	
	pivot_offset = size / 2.0
	
	await get_tree().process_frame
	_base_global_pos = global_position
	
	_circle_center = size / 2.0
	_circle_current_pos = _circle_center
	
	_setup_circle_area()
	
	_3d_screen.visible = false
	#debug_gui_2d.visible = false
	visible = false
	modulate.a = 0.0
	
	# Создаем таймер для пульсации стрелок
	_pulse_timer = Timer.new()
	_pulse_timer.wait_time = 0.02  # 60 FPS
	_pulse_timer.one_shot = false
	_pulse_timer.autostart = true
	add_child(_pulse_timer)
	_pulse_timer.timeout.connect(_on_pulse_timer_timeout)
	
	# Начальное состояние
	_update_button_state()
	
	if zone_terminal:
		zone_terminal.movement_blocked.connect(_on_movement_blocked)
		
	# 🔥 Таймер для остановки вибрации
	_vibration_timer = Timer.new()
	_vibration_timer.one_shot = true
	add_child(_vibration_timer)
	_vibration_timer.timeout.connect(_stop_vibration)
	
func _on_pulse_timer_timeout() -> void:
	# Увеличиваем фазу (скорость пульсации)
	_pulse_phase += 0.02
	if _pulse_phase > 1.0:
		_pulse_phase -= 1.0

	queue_redraw()  # Обновляем draw()


func _setup_circle_area() -> void:
	_circle_area = Area2D.new()
	_circle_area.monitoring = true
	_circle_area.monitorable = false
	add_child(_circle_area)
	
	_circle_collision = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = _circle_radius
	_circle_collision.shape = shape
	_circle_area.add_child(_circle_collision)
	
	_circle_area.position = _circle_current_pos
	
	_circle_area.mouse_entered.connect(_on_circle_mouse_entered)
	_circle_area.mouse_exited.connect(_on_circle_mouse_exited)

func _on_circle_mouse_entered() -> void:
	_is_hovering = true
	queue_redraw()

func _on_circle_mouse_exited() -> void:
	if not _is_dragging:
		_is_hovering = false
		queue_redraw()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var local_mouse_pos = get_local_mouse_position()
			if local_mouse_pos.distance_to(_circle_current_pos) <= _circle_radius:
				_is_dragging = true
				_is_hovering = true
				_circle_ghost_visible = true
				_circle_ghost_pos = _circle_center 
				get_viewport().set_input_as_handled()
		else:
			if _is_dragging:
				_is_dragging = false
				_check_button_release()
				_return_circle_to_center()
				get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if _is_dragging:
		_circle_current_pos = get_local_mouse_position()
		_circle_area.position = _circle_current_pos
		_check_button_hover()
	
	if _is_over_button:
		_animation_time += delta * 5.0
	else:
		_animation_time = 0.0
	
	if _is_dragging or _is_over_button:
		queue_redraw()

func _check_button_hover() -> void:
	var over_button = _is_circle_over_button(btn_toggle)
	_is_over_button = over_button and btn_toggle.visible
	
	# ⚡ ТОЛЬКО кружок активирует кнопку
	if _is_over_button:
		btn_toggle.disabled = false
	else:
		btn_toggle.disabled = true

func _is_circle_over_button(button: Button) -> bool:
	if not button.visible:
		return false
	
	var button_rect = button.get_global_rect()
	var circle_global_pos = global_position + _circle_current_pos
	
	return button_rect.has_point(circle_global_pos)

func _check_button_release() -> void:
	if _is_circle_over_button(btn_toggle) and btn_toggle.visible:
		_on_btn_toggle_pressed()
	
	_check_button_hover()
	_is_over_button = false

func _return_circle_to_center() -> void:
	if _tween:
		_tween.kill()
	
	_tween = create_tween()
	_tween.tween_property(self, "_circle_current_pos", _circle_center, 0.2)\
		.set_trans(Tween.TRANS_CUBIC)\
		.set_ease(Tween.EASE_OUT)
	_tween.tween_callback(func():
		_circle_area.position = _circle_current_pos
		_is_hovering = false
		_circle_ghost_visible = false
		queue_redraw()
	)

func _draw() -> void:
	
	if _circle_ghost_visible:
		var ghost_color = Color(0.4, 0.7, 1.0, 0.3)  # Полупрозрачный
		_draw_dashed_circle(_circle_ghost_pos, _circle_radius, ghost_color, 1.5, 8.0, 4.0)
	
	var tex: Texture2D = on_texture if btn_toggle.text == "BOOT" else off_texture
	if tex:
		var tex_size = Vector2(85, 85)
		var tex_pos = _circle_current_pos - tex_size / 2
		draw_texture_rect(tex, Rect2(tex_pos, tex_size), false)

		
	var color = _circle_hover_color if _is_hovering else _circle_color
	var current_radius = _circle_radius
	var pulse_intensity = 1.0
	
	if _is_over_button:
		var pulse = sin(_animation_time * 2.0) * 0.15 + 1.0
		current_radius = _circle_radius * pulse
		pulse_intensity = sin(_animation_time * 2.0) * 0.3 + 1.0
		color = Color(color.r * pulse_intensity, color.g * pulse_intensity, color.b * pulse_intensity, color.a)
		
		var glow_color = Color(0.3, 0.8, 1.0, 0.3 * (sin(_animation_time * 2.0) * 0.5 + 0.5))
		_draw_dashed_circle(_circle_current_pos, current_radius + 8.0, glow_color, 1.5, 10.0, 5.0)
	
	_draw_dashed_circle(_circle_current_pos, current_radius, color, 2.5, 10.0, 5.0)

	
	# ✨ Рисуем sci-fi стрелки над кружком (только если не тащим)
	if not _is_dragging:
		_draw_scifi_arrows()
	
	# ✨ Рисуем динамические скобки у кнопки (только при перетаскивании)
	if _is_dragging:
		_draw_dynamic_brackets()

func _draw_dashed_circle(center: Vector2, radius: float, color: Color, width: float, dash_length: float, gap_length: float) -> void:
	var circumference = 1.0 * PI * radius
	var total_dash = dash_length + gap_length
	var num_segments = int(ceil(circumference / total_dash))
	
	for i in range(num_segments):
		var angle_start = (i * total_dash / circumference) * 2.0 * PI
		var angle_end = angle_start + (dash_length / circumference) * 2.0 * PI
		
		if angle_end > 2.0 * PI:
			angle_end = 2.0 * PI
		
		var steps = max(4, int(dash_length / 1.5))
		for j in range(steps):
			var t1 = float(j) / steps
			var t2 = float(j + 1) / steps
			var a1 = lerp(angle_start, angle_end, t1)
			var a2 = lerp(angle_start, angle_end, t2)
			
			var p1 = center + Vector2(cos(a1), sin(a1)) * radius
			var p2 = center + Vector2(cos(a2), sin(a2)) * radius
			
			draw_line(p1, p2, color, width, true)

# ✨ Рисуем sci-fi стрелки над кружком
func _draw_scifi_arrows() -> void:
	var base_color = Color(0.2, 0.8, 1.0, 1.0)
	var arrow_offset = 22.0
	var spacing = 16.0
	var arrow_h = 10.0
	var arrow_w = 12.0

	var phase = _pulse_phase  # 0..1, управляется таймером

	for i in range(2):
		var active = (i == 0 and phase < 0.5) or (i == 1 and phase >= 0.5)

		# плавная пульсация
		var intensity = abs(sin(phase * PI * 2))
		if not active:
			intensity *= 0.15  # неактивная стрелка тусклая

		# позиция стрелки
		var y = _circle_current_pos.y - _circle_radius - arrow_offset - i * spacing

		# рисуем стрелку
		var col = Color(base_color.r, base_color.g, base_color.b, intensity)
		_draw_arrow_up(_circle_current_pos.x, y, arrow_w, arrow_h, col, 2.0)

		# glow
		var glow = Color(base_color.r, base_color.g, base_color.b, intensity * 0.3)
		_draw_arrow_up(_circle_current_pos.x, y, arrow_w + 4, arrow_h + 2, glow, 1.0)


# Рисуем одну стрелку вверх (улучшенная версия)
func _draw_arrow_up(x: float, y: float, width: float, height: float, color: Color, line_width: float = 2.5) -> void:
	var tip = Vector2(x, y)
	var left = Vector2(x - width / 2, y + height)
	var right = Vector2(x + width / 2, y + height)
	var mid_left = Vector2(x - width / 4, y + height / 2)
	var mid_right = Vector2(x + width / 4, y + height / 2)
	
	# Рисуем стрелку с дополнительными деталями
	draw_line(tip, left, color, line_width, true)
	draw_line(tip, right, color, line_width, true)
	
	# Добавляем "хвост" стрелки для sci-fi эффекта
	draw_line(left, Vector2(x - width / 6, y + height), color, line_width, true)
	draw_line(right, Vector2(x + width / 6, y + height), color, line_width, true)
	
	# Внутренние линии для детализации
	draw_line(tip, Vector2(x, y + height * 0.6), color, line_width * 0.6, true)

# ✨ Рисуем динамические скобки у кнопки
func _draw_dynamic_brackets() -> void:
	if not btn_toggle.visible:
		return
	
	# Вычисляем расстояние от кружка до кнопки
	var button_center = btn_toggle.position + btn_toggle.size / 2
	var distance = _circle_current_pos.distance_to(button_center)
	
	# Максимальное расстояние для видимости скобок
	var max_distance = 200.0
	
	# Нормализуем расстояние (0.0 = над кнопкой, 1.0 = далеко)
	var distance_factor = clamp(distance / max_distance, 0.0, 1.0)
	
	# Если кружок над кнопкой - скобки исчезают
	if _is_over_button:
		distance_factor = 0.0
	
	# Размер и позиция скобок зависят от расстояния
	var bracket_alpha = distance_factor * 0.8
	var bracket_offset = 15.0 + (distance_factor * 50.0)  # От 5px до 35px
	var bracket_height = btn_toggle.size.y * 0.8
	var bracket_width = 10.0
	
	if bracket_alpha > 0.05:
		var bracket_color = Color(0.3, 0.8, 1.0, bracket_alpha)
		
		# Левая скобка [
		var left_x = btn_toggle.position.x - bracket_offset
		_draw_bracket_left(left_x, btn_toggle.position.y + btn_toggle.size.y / 2, 
						   bracket_width, bracket_height, bracket_color)
		
		# Правая скобка ]
		var right_x = btn_toggle.position.x + btn_toggle.size.x + bracket_offset
		_draw_bracket_right(right_x, btn_toggle.position.y + btn_toggle.size.y / 2,
							bracket_width, bracket_height, bracket_color)

# Рисуем левую скобку [
func _draw_bracket_left(x: float, y: float, width: float, height: float, color: Color) -> void:
	var half_h = height / 1.5
	var top = Vector2(x, y - half_h)
	var bottom = Vector2(x, y + half_h)
	var top_right = Vector2(x + width, y - half_h)
	var bottom_right = Vector2(x + width, y + half_h)
	
	draw_line(top, bottom, color, 2.5, true)
	draw_line(top, top_right, color, 2.5, true)
	draw_line(bottom, bottom_right, color, 2.5, true)

# Рисуем правую скобку ]
func _draw_bracket_right(x: float, y: float, width: float, height: float, color: Color) -> void:
	var half_h = height / 1.5
	var top = Vector2(x, y - half_h)
	var bottom = Vector2(x, y + half_h)
	var top_left = Vector2(x - width, y - half_h)
	var bottom_left = Vector2(x - width, y + half_h)
	
	draw_line(top, bottom, color, 2.5, true)
	draw_line(top, top_left, color, 2.5, true)
	draw_line(bottom, bottom_left, color, 2.5, true)

# ✨ ОБНОВЛЕНИЕ СОСТОЯНИЯ КНОПКИ
func _update_button_state() -> void:
	if _is_system_on:
		btn_toggle.text = "SHUTDOWN"
		btn_toggle.modulate = Color(1.0, 0.3, 0.3)  # Красноватый оттенок
	else:
		btn_toggle.text = "BOOT"
		btn_toggle.modulate = Color(0.3, 1.0, 0.3)  # Зеленоватый оттенок
	
	# ⚡ КРИТИЧЕСКИ ВАЖНО: кнопка ВСЕГДА disabled
	btn_toggle.disabled = true
	btn_toggle.visible = true
	btn_toggle.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Игнорируем клики мыши

# ✨ ОБРАБОТЧИК ПЕРЕКЛЮЧЕНИЯ
func _on_btn_toggle_pressed() -> void:
	# Блокируем ввод
	set_process_input(false)
	
	# Переключаем состояние
	_is_system_on = !_is_system_on
	
	if _is_system_on:
		print("🟢 BOOT pressed - система включается")
		_turn_on_system()
	else:
		print("🔴 SHUTDOWN pressed - система выключается")
		_turn_off_system()
	
	# Обновляем кнопку
	_update_button_state()
	
	# Разблокируем ввод через кадр
	await get_tree().process_frame
	set_process_input(true)

func _turn_on_system() -> void:
	if zone_terminal and not zone_terminal.is_terminal_on:
		zone_terminal.toggle_terminal()
	
	_3d_screen.visible = true
	
	#if debug_gui_2d:
		#debug_gui_2d.visible = true
		#if debug_gui_2d.has_method("show_ui_with_buttons"):
			#debug_gui_2d.show_ui_with_buttons()

func _turn_off_system() -> void:
	if zone_terminal and zone_terminal.is_terminal_on:
		zone_terminal.toggle_terminal()
	
	_3d_screen.visible = false
	
	#if debug_gui_2d:
		#debug_gui_2d.visible = false

# =========================
# SHOW / HIDE ANIM
# =========================
func show_with_anim() -> void:
	if _tween:
		_tween.kill()
	
	visible = true
	scale = Vector2(0.5, 0.5)
	modulate.a = 0.0
	
	_tween = create_tween()
	_tween.set_parallel()
	
	_tween.tween_property(self, "scale", Vector2.ONE, 0.35)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_OUT)
	
	_tween.tween_property(self, "modulate:a", 1.0, 0.3)\
		.set_trans(Tween.TRANS_CUBIC)\
		.set_ease(Tween.EASE_OUT)
	
	# ⚡ После анимации принудительно disabled
	_tween.tween_callback(func():
		btn_toggle.disabled = true
		btn_toggle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	)

func hide_with_anim() -> void:
	if _tween:
		_tween.kill()
	
	_tween = create_tween()
	_tween.set_parallel()
	
	_tween.tween_property(self, "scale", Vector2(3.0, 3.0), 0.3)\
		.set_trans(Tween.TRANS_CUBIC)\
		.set_ease(Tween.EASE_IN)
	
	_tween.tween_property(self, "modulate:a", 0.0, 0.25)\
		.set_trans(Tween.TRANS_CUBIC)\
		.set_ease(Tween.EASE_IN)
	
	_tween.tween_callback(func():
		visible = false
		scale = Vector2.ONE
		modulate.a = 1.0
)

# 🔥 ВИБРАЦИЯ КНОПКИ ПРИ ПОПЫТКЕ ДВИЖЕНИЯ
func _on_movement_blocked() -> void:
	if not _is_system_on or not btn_toggle.visible:
		return
	
	_start_vibration()

func _start_vibration() -> void:
	if _is_vibrating:
		return
	
	_is_vibrating = true
	
	# Останавливаем предыдущую анимацию
	if _vibration_tween:
		_vibration_tween.kill()
	
	# Создаем вибрацию
	_vibration_tween = create_tween()
	_vibration_tween.set_loops(6)  # 6 циклов вибрации
	_vibration_tween.tween_property(btn_toggle, "position:x", btn_toggle.position.x + 5, 0.05)
	_vibration_tween.tween_property(btn_toggle, "position:x", btn_toggle.position.x - 5, 0.05)
	_vibration_tween.tween_property(btn_toggle, "position:x", btn_toggle.position.x, 0.05)
	
	# Мигание цвета
	var original_color = btn_toggle.modulate
	_vibration_tween.parallel().tween_property(btn_toggle, "modulate", Color(1.5, 0.3, 0.3), 0.1)
	_vibration_tween.parallel().tween_property(btn_toggle, "modulate", original_color, 0.1)
	
	# Запускаем таймер на остановку
	_vibration_timer.start(0.6)
	
	print("⚠️ КНОПКА ВИБРИРУЕТ - закройте терминал для движения!")

func _stop_vibration() -> void:
	_is_vibrating = false
	
	if _vibration_tween:
		_vibration_tween.kill()
	
	# Возвращаем кнопку в нормальное положение
	var reset_tween = create_tween()
	reset_tween.tween_property(btn_toggle, "position", btn_toggle.position.snapped(Vector2.ONE), 0.1)
	reset_tween.tween_property(btn_toggle, "modulate", Color(1.0, 0.3, 0.3), 0.1)
