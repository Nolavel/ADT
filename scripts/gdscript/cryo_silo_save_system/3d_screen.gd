extends MeshInstance3D

## 3D_Screen.gd - Главный контроллер 3D интерфейса

@onready var mesh_btn_silo: MeshInstance3D = $AreaGUI/MeshBTN_SILO
@onready var lbl_btn_silo: Label3D = $AreaGUI/MeshBTN_SILO/lbl_btn_silo

@onready var mesh_btn_manage_pit: MeshInstance3D = $AreaGUI/MeshBTN_MANAGE_PIT
@onready var lbl_btn_pit: Label3D = $AreaGUI/MeshBTN_MANAGE_PIT/lbl_btn_pit

@onready var btn_cryopod_1: MeshInstance3D = $AreaGUI/MeshBTN_Cryopod_1
@onready var lbl_btn_cryopod_one: Label3D = $AreaGUI/MeshBTN_Cryopod_1/lbl_btn_crypod_one

@onready var btn_cryopod_2: MeshInstance3D = $AreaGUI/MeshBTN_Cryopod_2
@onready var lbl_btn_crypod_two: Label3D = $AreaGUI/MeshBTN_Cryopod_2/lbl_btn_cryopod_two

@onready var btn_cryopod_3: MeshInstance3D = $AreaGUI/MeshBTN_Cryopod_3
@onready var lbl_btn_cryopod_three: Label3D = $AreaGUI/MeshBTN_Cryopod_3/lbl_btn_cryopod_three

@onready var zone_terminal: ZoneTerminal = $"../ZoneTerminal"
@onready var silo_manager: CryoBedSilo = $".."

var screen_material: ShaderMaterial
var button_materials: Dictionary = {}  # Храним материалы всех кнопок
var active_cryopod: CryoPod = null
var is_player_at_terminal: bool = false
var is_initialized: bool = false
var is_animating: bool = false

const LAYER_3D_GUI := 1 << 19

# Шейдер для кнопок в стиле CRT монитора 80-х
const BUTTON_SHADER_CODE = """
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_always;

uniform vec4 tint_color : source_color = vec4(0.4, 0.7, 0.35, 1.0);
uniform float alpha : hint_range(0.0, 1.0) = 1.0;
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.4;
uniform float scanline_density = 180.0;
uniform float glow_intensity : hint_range(0.0, 2.0) = 0.7;
uniform float edge_brightness : hint_range(0.0, 2.0) = 0.8;
uniform float press_effect : hint_range(0.0, 1.0) = 0.0;
uniform float flicker : hint_range(0.0, 0.2) = 0.02;
uniform float phosphor_trails : hint_range(0.0, 1.0) = 0.15;

float hash(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p.x * 43758.5453 + p.y * 12345.123) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	
	// Более четкие скан-линии как на старых мониторах
	float scan = sin(uv.y * scanline_density * 3.14159);
	float scan_mask = 0.5 + 0.5 * scan;
	scan_mask = mix(1.0, scan_mask, scanline_strength);
	
	// Эффект "фосфорного следа" - характерная черта CRT
	float trail = sin(uv.y * 100.0 + TIME * 2.0) * phosphor_trails;
	
	// Приглушенное свечение по краям (не яркое)
	vec2 centered = uv * 2.0 - 1.0;
	float dist = length(centered);
	float edge_glow = 1.0 - smoothstep(0.4, 1.0, dist);
	edge_glow = pow(edge_glow, 3.0) * edge_brightness;
	
	// Редкое мерцание (как у старых мониторов)
	float flicker_val = 1.0 + sin(TIME * 80.0) * flicker;
	
	// Легкий шум
	float noise = hash(vec2(uv * 400.0 + TIME * 30.0));
	noise = 1.0 + (noise - 0.5) * 0.08;
	
	// Эффект нажатия (более тонкий)
	float press_darken = 1.0 - press_effect * 0.3;
	float press_pulse = sin(TIME * 25.0) * press_effect * 0.2;
	
	// Приглушенный базовый цвет
	vec3 base_color = tint_color.rgb * glow_intensity;
	
	// Комбинируем все эффекты
	vec3 final_color = base_color * scan_mask * flicker_val * noise * press_darken;
	final_color += trail * tint_color.rgb * 0.3;
	final_color += edge_glow * tint_color.rgb * (0.5 + press_pulse);
	
	ALBEDO = final_color;
	ALPHA = alpha;
	EMISSION = final_color * 0.3;  // Приглушенное свечение
}
"""

func _ready() -> void:
	# Подключаем сигналы терминала
	zone_terminal.terminal_switch_ON.connect(_on_terminal_switch_on)
	zone_terminal.terminal_switch_OFF.connect(_on_terminal_switch_off)
	zone_terminal.player_entered_control_zone.connect(_on_player_entered_zone)
	zone_terminal.player_exited_control_zone.connect(_on_player_exited_zone)
	
	# Настраиваем материал экрана
	var mat := get_active_material(0)
	if mat is ShaderMaterial:
		screen_material = mat
		screen_material.set_shader_parameter("curvature", 0.1)
		screen_material.set_shader_parameter("vignette_strength", 0.7)
		screen_material.set_shader_parameter("scanline_strength", 0.35)
		screen_material.set_shader_parameter("scanline_density", 200.0)
		screen_material.set_shader_parameter("flicker_strength", 0.04)
		screen_material.set_shader_parameter("noise_strength", 0.2)
		screen_material.set_shader_parameter("tint_color", Color(0.6, 0.9, 0.5, 1.0))
	
	# Создаем шейдерные материалы для всех кнопок
	_setup_button_materials()
	
	# Подключаемся к DynamicCursorUI
	zone_terminal.player_entered_control_zone.connect(_connect_to_cursor)
	
	# Ждем загрузки сцены
	await get_tree().process_frame
	await get_tree().process_frame
	
	_connect_silo_signals()
	
	# Скрываем все кнопки при старте
	_hide_all_buttons()
	
	print("✅ 3D_Screen: Инициализирован")

func _setup_button_materials() -> void:
	"""Создаем кастомные шейдерные материалы для кнопок"""
	var shader = Shader.new()
	shader.code = BUTTON_SHADER_CODE
	
	# Массив всех кнопок для настройки
	var buttons = [
		mesh_btn_silo,
		mesh_btn_manage_pit,
		btn_cryopod_1,
		btn_cryopod_2,
		btn_cryopod_3
	]
	
	for button in buttons:
		if button:
			var mat = ShaderMaterial.new()
			mat.shader = shader
			
			# Настраиваем базовые параметры в стиле терминалов 80-х
			mat.set_shader_parameter("tint_color", Color(0.4, 0.7, 0.35, 1.0))  # Приглушенный зеленый
			mat.set_shader_parameter("alpha", 1.0)
			mat.set_shader_parameter("scanline_strength", 0.4)
			mat.set_shader_parameter("scanline_density", 180.0)
			mat.set_shader_parameter("glow_intensity", 0.7)
			mat.set_shader_parameter("edge_brightness", 0.8)
			mat.set_shader_parameter("press_effect", 0.0)
			mat.set_shader_parameter("flicker", 0.02)
			mat.set_shader_parameter("phosphor_trails", 0.15)
			
			# Применяем материал
			button.set_surface_override_material(0, mat)
			button_materials[button.name] = mat
			
			print("✅ Создан шейдер для: ", button.name)

func _connect_silo_signals() -> void:
	"""Подключаем сигналы от менеджера силоса и криокапсул"""
	if not silo_manager:
		push_error("❌ 3D_Screen: SiloManager не найден!")
		return
	
	# Сигналы менеджера
	silo_manager.silo_state_changed.connect(_on_silo_state_changed)
	silo_manager.capsules_state_changed.connect(_on_capsules_state_changed)
	silo_manager.animation_started.connect(_on_animation_started)
	silo_manager.animation_finished.connect(_on_animation_finished)
	print("✅ 3D_Screen: Подключен к SiloManager")
	
	# Сигналы криокапсул
	if silo_manager.cryopod_1:
		silo_manager.cryopod_1.capsule_state_changed.connect(_on_capsule_changed)
		print("✅ 3D_Screen: Подключен к Cryopod 1")
	
	if silo_manager.cryopod_2:
		silo_manager.cryopod_2.capsule_state_changed.connect(_on_capsule_changed)
		print("✅ 3D_Screen: Подключен к Cryopod 2")
	
	if silo_manager.cryopod_3:
		silo_manager.cryopod_3.capsule_state_changed.connect(_on_capsule_changed)
		print("✅ 3D_Screen: Подключен к Cryopod 3")
	
	is_initialized = true

func _connect_to_cursor() -> void:
	"""Прямое подключение к DynamicCursorUI когда игрок входит в зону"""
	var player = zone_terminal.player
	if not player:
		return
	
	var cursor = player.get_node_or_null("DynamicCursorUI")
	if not cursor:
		return
	
	if cursor.button_3d_clicked.is_connected(_on_3d_button_clicked):
		return
	
	cursor.button_3d_clicked.connect(_on_3d_button_clicked)
	print("✅ 3D_Screen: Подключен к DynamicCursorUI")

# === ОБРАБОТКА СИГНАЛОВ ТЕРМИНАЛА ===
func _on_terminal_switch_on() -> void:
	print("🔓 3D_Screen: Терминал включен")
	_boot_sequence()

func _on_terminal_switch_off() -> void:
	print("🔒 3D_Screen: Терминал выключен")
	_hide_all_buttons()

func _on_player_entered_zone() -> void:
	is_player_at_terminal = true
	print("👤 3D_Screen: Игрок у панели")
	_update_ui()

func _on_player_exited_zone() -> void:
	is_player_at_terminal = false
	print("🚶 3D_Screen: Игрок ушел от панели")
	_hide_all_buttons()

# === ОБРАБОТКА СИГНАЛОВ SILO ===
func _on_silo_state_changed(is_raised: bool) -> void:
	print("📦 3D_Screen: Сило ", "поднят" if is_raised else "опущен")
	_update_ui()

func _on_capsules_state_changed(are_raised: bool) -> void:
	print("🔧 3D_Screen: Капсулы ", "подняты" if are_raised else "опущены")
	_update_ui()

func _on_capsule_changed(is_open: bool, capsule_id: int) -> void:
	print("❄️ 3D_Screen: Капсула ", capsule_id, " ", "открыта" if is_open else "закрыта")
	_update_ui()

func _on_animation_started() -> void:
	is_animating = true
	_update_buttons_interactivity()

func _on_animation_finished() -> void:
	is_animating = false
	_update_ui()

# === ОБРАБОТКА КЛИКОВ ПО 3D КНОПКАМ ===
func _on_3d_button_clicked(button_name: String) -> void:
	if is_animating:
		print("⏳ Анимация в процессе, ожидайте...")
		return
	
	print("🎮 3D_Screen получил клик: ", button_name)
	
	# Эффекты при нажатии
	_press_button_effect(button_name)
	_flash_screen()
	
	match button_name:
		"MeshBTN_SILO":
			_handle_silo_button()
		"MeshBTN_MANAGE_PIT":
			_handle_pit_button()
		"MeshBTN_Cryopod_1":
			_handle_cryopod_button(1)
		"MeshBTN_Cryopod_2":
			_handle_cryopod_button(2)
		"MeshBTN_Cryopod_3":
			_handle_cryopod_button(3)
		_:
			print("   ❓ Неизвестная кнопка")

func _handle_silo_button() -> void:
	print("   📦 Переключение силоса")
	if silo_manager:
		silo_manager.toggle_silo()

func _handle_pit_button() -> void:
	print("   ⚙️ Переключение капсул")
	if silo_manager:
		silo_manager.toggle_capsules()

func _handle_cryopod_button(pod_number: int) -> void:
	print("   ❄️ Переключение криокапсулы ", pod_number)
	if not silo_manager:
		return
	
	var cryopod: CryoPod = null
	match pod_number:
		1: cryopod = silo_manager.cryopod_1
		2: cryopod = silo_manager.cryopod_2
		3: cryopod = silo_manager.cryopod_3
	
	if cryopod:
		await cryopod.toggle_capsule()

# === ВИЗУАЛЬНЫЕ ЭФФЕКТЫ ===
func _press_button_effect(button_name: String) -> void:
	"""Эффект нажатия на кнопку - затемнение и пульсация"""
	if not button_materials.has(button_name):
		return
	
	var mat: ShaderMaterial = button_materials[button_name]
	
	# Включаем эффект нажатия
	var tween = create_tween()
	tween.set_parallel(true)
	
	# Эффект нажатия
	tween.tween_method(
		func(val): mat.set_shader_parameter("press_effect", val),
		0.0, 1.0, 0.1
	)
	
	# Изменение свечения (более плавное)
	tween.tween_method(
		func(val): mat.set_shader_parameter("glow_intensity", val),
		0.7, 1.3, 0.1
	)
	
	# Возврат в нормальное состояние
	tween.chain().set_parallel(true)
	tween.tween_method(
		func(val): mat.set_shader_parameter("press_effect", val),
		1.0, 0.0, 0.3
	).set_ease(Tween.EASE_OUT)
	
	tween.tween_method(
		func(val): mat.set_shader_parameter("glow_intensity", val),
		1.3, 0.7, 0.3
	).set_ease(Tween.EASE_OUT)

func _flash_screen() -> void:
	"""Визуальная вспышка экрана при нажатии любой кнопки"""
	if not screen_material:
		return
	
	var original_tint = screen_material.get_shader_parameter("tint_color")
	var original_flicker = screen_material.get_shader_parameter("flicker_strength")
	
	# Приглушенная вспышка в стиле 80-х
	screen_material.set_shader_parameter("tint_color", Color(0.5, 0.8, 0.4, 1.0))
	screen_material.set_shader_parameter("flicker_strength", 0.15)
	
	await get_tree().create_timer(0.12).timeout
	
	screen_material.set_shader_parameter("tint_color", original_tint)
	screen_material.set_shader_parameter("flicker_strength", original_flicker)

# === ОБНОВЛЕНИЕ UI ===
func _update_ui() -> void:
	"""Обновление состояния всех кнопок"""
	if not is_initialized or not silo_manager or not zone_terminal:
		return
	
	var terminal_on = zone_terminal.is_terminal_on
	var silo_raised = silo_manager.is_silo_raised
	var caps_raised = silo_manager.are_capsules_raised
	
	# Если терминал выключен или игрок не у панели - скрываем всё
	if not terminal_on or not is_player_at_terminal:
		_hide_all_buttons()
		return
	
	# === ЛОГИКА ОТОБРАЖЕНИЯ КНОПОК ===
	
	# Если силос опущен - показываем ТОЛЬКО кнопку подъема силоса
	if not silo_raised:
		mesh_btn_silo.visible = true
		mesh_btn_manage_pit.visible = false
		btn_cryopod_1.visible = false
		btn_cryopod_2.visible = false
		btn_cryopod_3.visible = false
		
		lbl_btn_silo.text = "Raise CryoSilo"
		_set_button_enabled(mesh_btn_silo, not is_animating)
		return
	
	# Если силос поднят - показываем кнопки силоса и капсул
	mesh_btn_silo.visible = true
	mesh_btn_manage_pit.visible = true
	
	# Обновляем текст кнопки силоса
	lbl_btn_silo.text = "Lower CryoSilo"
	_set_button_enabled(mesh_btn_silo, not caps_raised and not is_animating)
	
	# Обновляем текст кнопки капсул
	if caps_raised:
		lbl_btn_pit.text = "Lower Cryopods"
		_set_button_enabled(mesh_btn_manage_pit, not _any_capsule_open() and not is_animating)
	else:
		lbl_btn_pit.text = "Raise Cryopods"
		_set_button_enabled(mesh_btn_manage_pit, not is_animating)
	
	# Показываем/скрываем кнопки криокапсул
	btn_cryopod_1.visible = caps_raised
	btn_cryopod_2.visible = caps_raised
	btn_cryopod_3.visible = caps_raised
	
	if caps_raised:
		if silo_manager.cryopod_1:
			lbl_btn_cryopod_one.text = "Lock Pod R1" if silo_manager.cryopod_1.is_open else "Unlock Pod R1"
			_set_button_enabled(btn_cryopod_1, not is_animating)
		
		if silo_manager.cryopod_2:
			lbl_btn_crypod_two.text = "Lock Pod R2" if silo_manager.cryopod_2.is_open else "Unlock Pod R2"
			_set_button_enabled(btn_cryopod_2, not is_animating)
		
		if silo_manager.cryopod_3:
			lbl_btn_cryopod_three.text = "Lock Pod R3" if silo_manager.cryopod_3.is_open else "Unlock Pod R3"
			_set_button_enabled(btn_cryopod_3, not is_animating)

func _update_buttons_interactivity() -> void:
	"""Блокировка/разблокировка всех кнопок"""
	_set_button_enabled(mesh_btn_silo, not is_animating)
	_set_button_enabled(mesh_btn_manage_pit, not is_animating)
	_set_button_enabled(btn_cryopod_1, not is_animating)
	_set_button_enabled(btn_cryopod_2, not is_animating)
	_set_button_enabled(btn_cryopod_3, not is_animating)

func _set_button_enabled(button: MeshInstance3D, enabled: bool) -> void:
	"""Включение/выключение кнопки через шейдер"""
	if not button or not button_materials.has(button.name):
		return
	
	var mat: ShaderMaterial = button_materials[button.name]
	
	# Изменяем прозрачность и цвет (приглушенные тона)
	var target_alpha = 1.0 if enabled else 0.25
	var target_color = Color(0.4, 0.7, 0.35, 1.0) if enabled else Color(0.15, 0.25, 0.15, 1.0)
	
	mat.set_shader_parameter("alpha", target_alpha)
	mat.set_shader_parameter("tint_color", target_color)
	mat.set_shader_parameter("glow_intensity", 0.7 if enabled else 0.3)

# === ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ===
func _any_capsule_open() -> bool:
	"""Проверка, открыта ли хотя бы одна капсула"""
	if silo_manager.cryopod_1 and silo_manager.cryopod_1.is_open:
		return true
	if silo_manager.cryopod_2 and silo_manager.cryopod_2.is_open:
		return true
	if silo_manager.cryopod_3 and silo_manager.cryopod_3.is_open:
		return true
	return false

func _hide_all_buttons() -> void:
	"""Скрытие всех кнопок"""
	mesh_btn_silo.visible = false
	mesh_btn_manage_pit.visible = false
	btn_cryopod_1.visible = false
	btn_cryopod_2.visible = false
	btn_cryopod_3.visible = false
	
func _random_glitch() -> void:
	if randf() < 0.02:  # 2% шанс каждый кадр
		screen_material.set_shader_parameter("noise_strength", 0.8)
		await get_tree().create_timer(0.05).timeout
		screen_material.set_shader_parameter("noise_strength", 0.2)
		
func _boot_sequence() -> void:
	if not screen_material:
		return
	
	# Эффект "прогрева" ЭЛТ монитора
	var tween = create_tween()
	tween.tween_method(
		func(val): screen_material.set_shader_parameter("vignette_strength", val),
		1.0, 0.7, 0.8
	)
	tween.parallel().tween_method(
		func(val): screen_material.set_shader_parameter("flicker_strength", val),
		0.2, 0.04, 0.8
	)
	
	await tween.finished
	_update_ui()
	_random_glitch()
