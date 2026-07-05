extends Control

var pin_tween: Tween
var hover_tween: Tween
var idle_tween: Tween
var click_tween: Tween

var scifi_pin: Control
var core_node: ColorRect

var all_materials: Array[ShaderMaterial] = []
var is_clicked: bool = false
var is_hovering: bool = false


func _ready() -> void:
	# КРИТИЧЕСКИ ВАЖНО: задаем размер и включаем обработку мыши
	custom_minimum_size = Vector2(80, 80)
	size = Vector2(80, 80)
	mouse_filter = Control.MOUSE_FILTER_STOP
	
	_create_scifi_pin()
	
	## Визуальная отладка - показываем границы (ПОСЛЕ scifi_pin!)
	#var debug_rect = ColorRect.new()
	#debug_rect.size = Vector2(80, 80)
	#debug_rect.color = Color(1, 0, 0, 0.2)  # Полупрозрачный красный
	#debug_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE  # НЕ блокируем события!
	#debug_rect.z_index = -1  # Позади всего
	#add_child(debug_rect)
	
	# Подключаем сигналы мыши
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	
	print("SciFi Pin готов! Размер: ", size)
	print("SciFi Pin позиция: ", global_position)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		print("🎯 Клик по пину! Позиция: ", event.position)
		_activate_pin()
		accept_event()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var local_pos = get_local_mouse_position()
		var rect = Rect2(Vector2.ZERO, size)
		
		print("📍 Глобальный клик. Local pos: ", local_pos, " | Rect: ", rect)
		
		if not rect.has_point(local_pos) and is_clicked:
			print("❌ Клик вне пина - деактивация")
			_deactivate_pin()


###############################################################
#                     CREATE SCI-FI PIN
###############################################################
func _create_scifi_pin() -> void:
	# Создаем контейнер для визуальных элементов БЕЗ Control
	# Все элементы добавляем НАПРЯМУЮ к родителю с правильными позициями
	
	var offset = Vector2(20, 20)  # Смещение для центрирования в 80x80
	
	# Внешнее свечение
	var outer_glow = ColorRect.new()
	outer_glow.position = offset
	outer_glow.size = Vector2(40, 40)
	outer_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer_glow.z_index = 10
	outer_glow.material = _create_glow_shader()
	add_child(outer_glow)

	# Внешнее кольцо
	var outer_ring = ColorRect.new()
	outer_ring.position = offset + Vector2(4, 4)
	outer_ring.size = Vector2(32, 32)
	outer_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer_ring.z_index = 11
	outer_ring.material = _create_ring_shader(0.0)
	add_child(outer_ring)

	# Среднее кольцо
	var middle_ring = ColorRect.new()
	middle_ring.position = offset + Vector2(8, 8)
	middle_ring.size = Vector2(24, 24)
	middle_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	middle_ring.z_index = 12
	middle_ring.material = _create_ring_shader(2.0)
	add_child(middle_ring)

	# Центральное ядро
	core_node = ColorRect.new()
	core_node.position = offset + Vector2(12, 12)
	core_node.size = Vector2(16, 16)
	core_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	core_node.z_index = 13
	core_node.material = _create_core_shader()
	add_child(core_node)
	
	# Создаем невидимый Control для анимации вращения
	scifi_pin = Control.new()
	scifi_pin.position = offset + Vector2(20, 20)  # Центр вращения
	scifi_pin.size = Vector2(0, 0)
	scifi_pin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scifi_pin.z_index = 100
	add_child(scifi_pin)
	
	# Перемещаем визуальные элементы как дочерние к scifi_pin для вращения
	outer_glow.reparent(scifi_pin)
	outer_ring.reparent(scifi_pin)
	middle_ring.reparent(scifi_pin)
	core_node.reparent(scifi_pin)
	
	# Корректируем позиции относительно центра вращения
	outer_glow.position = Vector2(-20, -20)
	outer_ring.position = Vector2(-16, -16)
	middle_ring.position = Vector2(-12, -12)
	core_node.position = Vector2(-8, -8)

	# Собираем материалы
	all_materials = [
		outer_glow.material,
		outer_ring.material,
		middle_ring.material,
		core_node.material
	]

	# Инициализируем параметры шейдеров
	for mat in all_materials:
		mat.set_shader_parameter("warmth", 0.0)
		mat.set_shader_parameter("pulse_intensity", 1.0)
	
	core_node.material.set_shader_parameter("cross_mode", 0.0)

	_start_idle_animation()


###############################################################
#                    SHADERS
###############################################################

func _create_glow_shader() -> ShaderMaterial:
	var shader = Shader.new()
	shader.code = """
shader_type canvas_item;

uniform float warmth : hint_range(0,1) = 0.0;

// цифровой шум
float hash(vec2 p) {
    return fract(sin(dot(p ,vec2(12.9898,78.233))) * 43758.5453);
}

void fragment(){
    vec2 uv = UV - 0.5;
    float dist = length(uv);

    float glow = 1.0 - smoothstep(0.0, 0.55, dist);
    glow = pow(glow, 2.0);

    float pulse = sin(TIME * 2.0) * 0.3 + 0.7;

    // DIGITAL NOISE
    float noise = hash(UV * TIME * 40.0) * 0.25;

    vec3 cold = vec3(0.2, 0.8, 1.0);
    vec3 warm = vec3(1.0, 0.9, 0.2);
    vec3 final_color = mix(cold, warm, warmth);

    COLOR.rgb = final_color + noise * 0.4;
    COLOR.a = glow * pulse * 0.35;
}

"""
	var m := ShaderMaterial.new()
	m.shader = shader
	return m


func _create_ring_shader(time_offset: float) -> ShaderMaterial:
	var shader = Shader.new()
	shader.code = """
shader_type canvas_item;

uniform float time_offset = 0.0;
uniform float warmth : hint_range(0,1) = 0.0;
uniform float pulse_intensity : hint_range(0,1) = 1.0;

void fragment(){
	vec2 uv = UV - 0.5;
	float dist = length(uv);

	float ring = smoothstep(0.35, 0.38, dist) - smoothstep(0.48, 0.5, dist);

	float ang = atan(uv.y, uv.x);
	float rot = (sin(TIME * 2.0 + ang * 3.0 + time_offset) * 0.5 + 0.5) * pulse_intensity;

	ring *= rot;

	vec3 cold = vec3(0.3, 0.9, 1.0);
	vec3 warm = vec3(1.0, 0.9, 0.2);

	COLOR.rgb = mix(cold, warm, warmth);
	COLOR.a = ring;
}
"""
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("time_offset", time_offset)
	return m


func _create_core_shader() -> ShaderMaterial:
	var shader = Shader.new()
	shader.code = """
shader_type canvas_item;

uniform float warmth : hint_range(0,1) = 0.0;

float hash(vec2 p) {
    return fract(sin(dot(p ,vec2(17.123,91.222))) * 11234.441);
}

void fragment(){
    vec2 uv = UV - 0.5;
    float dist = length(uv);

    float pulse = sin(TIME * 3.0) * 0.3 + 0.7;

    // Базовое ядро
    float core = 1.0 - smoothstep(0.0, 0.45, dist);

    // DIGITAL NOISE
    float noise = hash(uv * TIME * 40.0) * 0.4;

    // горизонтальные/вертикальные цифровые линии
    float cross_h = smoothstep(0.06, 0.0, abs(uv.y));
    float cross_v = smoothstep(0.06, 0.0, abs(uv.x));
    float cross = max(cross_h, cross_v);

    // диагонали
    float diag1 = smoothstep(0.07, 0.0, abs(uv.x - uv.y));
    float diag2 = smoothstep(0.07, 0.0, abs(uv.x + uv.y));
    float diagonals = max(diag1, diag2) * 0.6;

    float glow = core + cross + diagonals + noise * 0.6;

    vec3 cold = vec3(0.6, 1.0, 1.0);
    vec3 warm = vec3(1.0, 0.9, 0.3);

    COLOR.rgb = mix(cold, warm, warmth) * glow * pulse;
    COLOR.a = glow;
}

"""
	var m := ShaderMaterial.new()
	m.shader = shader
	return m


###############################################################
#                     MOUSE EVENTS
###############################################################

func _on_mouse_entered():
	if is_hovering:  # Уже наведено - игнорируем
		return
		
	print("🟡 Мышь вошла!")
	is_hovering = true
	
	if is_clicked:
		return
		
	# НЕ останавливаем пульсацию! Только меняем цвет
	if idle_tween and idle_tween.is_running():
		idle_tween.kill()
	
	# Останавливаем вращение плавно
	var rotation_tween = create_tween()
	rotation_tween.set_trans(Tween.TRANS_SINE)
	rotation_tween.set_ease(Tween.EASE_OUT)
	rotation_tween.tween_property(scifi_pin, "rotation", 0.0, 0.2)

	if hover_tween:
		hover_tween.kill()

	hover_tween = create_tween()
	hover_tween.set_parallel(true)
	hover_tween.set_trans(Tween.TRANS_SINE)
	hover_tween.set_ease(Tween.EASE_OUT)

	# Просто меняем цвет на желтый, ВСЁ остальное работает как обычно
	for mat in all_materials:
		var current = mat.get_shader_parameter("warmth")
		if current == null:
			current = 0.0
		hover_tween.tween_method(
			func(v): mat.set_shader_parameter("warmth", v),
			current, 1.0, 0.3
		)


func _on_mouse_exited():
	if not is_hovering:  # Уже вышли - игнорируем
		return
		
	print("🔵 Мышь вышла!")
	is_hovering = false
	
	if is_clicked:
		return
		
	# Возвращаем пульсацию и вращение
	_start_idle_animation()

	if hover_tween:
		hover_tween.kill()

	hover_tween = create_tween()
	hover_tween.set_parallel(true)
	hover_tween.set_trans(Tween.TRANS_SINE)
	hover_tween.set_ease(Tween.EASE_IN)

	# Возвращаем холодный голубой цвет
	for mat in all_materials:
		var current = mat.get_shader_parameter("warmth")
		if current == null:
			current = 1.0
		hover_tween.tween_method(
			func(v): mat.set_shader_parameter("warmth", v),
			current, 0.0, 0.4
		)


###############################################################
#                     IDLE ANIMATION
###############################################################

func _start_idle_animation():
	if idle_tween and idle_tween.is_running():
		return
		
	idle_tween = create_tween()
	idle_tween.set_loops()
	idle_tween.set_trans(Tween.TRANS_SINE)
	idle_tween.set_ease(Tween.EASE_IN_OUT)

	idle_tween.tween_property(scifi_pin, "rotation", deg_to_rad(8), 2.5)
	idle_tween.tween_property(scifi_pin, "rotation", deg_to_rad(-8), 2.5)
	
	var pulse_tween = create_tween()
	pulse_tween.set_parallel(true)
	pulse_tween.set_trans(Tween.TRANS_SINE)
	pulse_tween.set_ease(Tween.EASE_OUT)
	
	for mat in all_materials:
		var current = mat.get_shader_parameter("pulse_intensity")
		if current == null:
			current = 0.0
		pulse_tween.tween_method(
			func(v): mat.set_shader_parameter("pulse_intensity", v),
			current, 1.0, 0.2
		)


func _stop_idle_animation():
	if idle_tween and idle_tween.is_running():
		idle_tween.kill()
	
	var pulse_tween = create_tween()
	pulse_tween.set_parallel(true)
	pulse_tween.set_trans(Tween.TRANS_SINE)
	pulse_tween.set_ease(Tween.EASE_IN)
	
	pulse_tween.tween_property(scifi_pin, "rotation", 0.0, 0.2)
	
	for mat in all_materials:
		var current = mat.get_shader_parameter("pulse_intensity")
		if current == null:
			current = 1.0
		pulse_tween.tween_method(
			func(v): mat.set_shader_parameter("pulse_intensity", v),
			current, 0.0, 0.2
		)


###############################################################
#                      CLICK ACTIONS
###############################################################

func _activate_pin():
	is_clicked = true
	print("🔴 PIN АКТИВИРОВАН!")
	
	
	
	if idle_tween and idle_tween.is_running():
		idle_tween.kill()
	
	if click_tween:
		click_tween.kill()
	
	click_tween = create_tween()
	click_tween.set_parallel(true)
	click_tween.set_trans(Tween.TRANS_CUBIC)
	click_tween.set_ease(Tween.EASE_OUT)
	
	# Останавливаем вращение всего пина
	click_tween.tween_property(scifi_pin, "rotation", 0.0, 0.2)
	
		# Масштаб ядра через UV, без смещения и багов
	click_tween.tween_method(
		func(v): core_node.material.set_shader_parameter("uv_scale", v),
		1.0, 0.5, 0.2
	)

	
	## УВЕЛИЧИВАЕМ ядро в 2 раза
	#click_tween.tween_property(core_node, "scale", Vector2(2.0, 2.0), 0.2)
	#
	## ПОВОРАЧИВАЕМ ядро на 45 градусов (крест станет X)
	#click_tween.tween_property(core_node, "rotation", deg_to_rad(45), 0.2)
	
	# Делаем чуть белее
	var core_mat = core_node.material as ShaderMaterial
	click_tween.tween_method(
		func(v): core_mat.set_shader_parameter("cross_mode", v),
		0.0, 1.0, 0.2
	)
	
	## Останавливаем пульсацию
	#for mat in all_materials:
		#var current = mat.get_shader_parameter("pulse_intensity")
		#if current == null:
			#current = 1.0
		#click_tween.tween_method(
			#func(v): mat.set_shader_parameter("pulse_intensity", v),
			#current, 0.0, 0.2
		#)
	
	# Сохраняем теплый цвет при клике
	for mat in all_materials:
		var current = mat.get_shader_parameter("warmth")
		if current == null:
			current = 0.0
		click_tween.tween_method(
			func(v): mat.set_shader_parameter("warmth", v),
			current, 1.0, 0.2
		)


func _deactivate_pin():
	is_clicked = false
	print("🟢 PIN ДЕАКТИВИРОВАН!")
	
	if click_tween:
		click_tween.kill()
	
	click_tween = create_tween()
	click_tween.set_parallel(true)
	click_tween.set_trans(Tween.TRANS_CUBIC)
	click_tween.set_ease(Tween.EASE_IN_OUT)
	
		# Масштаб ядра через UV, без смещения и багов
	click_tween.tween_method(
		func(v): core_node.material.set_shader_parameter("uv_scale", v),
		1.0, 1.0, 0.2
	)

	## Возвращаем размер ядра
	#click_tween.tween_property(core_node, "scale", Vector2(1.0, 1.0), 0.2)
	
	# Возвращаем поворот ядра
	click_tween.tween_property(core_node, "rotation", 0.0, 0.2)
	
	# Возвращаем параметр
	var core_mat = core_node.material as ShaderMaterial
	click_tween.tween_method(
		func(v): core_mat.set_shader_parameter("cross_mode", v),
		1.0, 0.0, 0.2
	)
	
	# Возвращаем цвет в холодный (если не наведен курсор)
	var target_warmth = 1.0 if is_hovering else 0.0
	for mat in all_materials:
		var current = mat.get_shader_parameter("warmth")
		if current == null:
			current = 0.0
		click_tween.tween_method(
			func(v): mat.set_shader_parameter("warmth", v),
			current, target_warmth, 0.2
		)
	
	# После завершения твина возвращаем пульсацию
	await click_tween.finished
	
	if not is_hovering:
		_start_idle_animation()
	else:
		# Если курсор наведен - просто возвращаем пульсацию без вращения
		var pulse_tween = create_tween()
		pulse_tween.set_parallel(true)
		pulse_tween.set_trans(Tween.TRANS_SINE)
		pulse_tween.set_ease(Tween.EASE_OUT)
		
		for mat in all_materials:
			var current = mat.get_shader_parameter("pulse_intensity")
			if current == null:
				current = 0.0
			pulse_tween.tween_method(
				func(v): mat.set_shader_parameter("pulse_intensity", v),
				current, 1.0, 0.2
			)
