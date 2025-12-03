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
var active_cryopod: CryoPod = null
var is_player_at_terminal: bool = false
var is_initialized: bool = false
var is_animating: bool = false

const LAYER_3D_GUI := 1 << 19

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
	
	# Подключаемся к DynamicCursorUI
	zone_terminal.player_entered_control_zone.connect(_connect_to_cursor)
	
	# Ждем загрузки сцены
	await get_tree().process_frame
	await get_tree().process_frame
	
	_connect_silo_signals()
	
	# Скрываем все кнопки при старте
	_hide_all_buttons()
	
	print("✅ 3D_Screen: Инициализирован")

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
		silo_manager.cryopod_1.player_entered_capsule.connect(_on_player_entered_capsule)
		silo_manager.cryopod_1.player_exited_capsule.connect(_on_player_exited_capsule)
		silo_manager.cryopod_1.capsule_state_changed.connect(_on_capsule_changed)
		print("✅ 3D_Screen: Подключен к Cryopod 1")
	
	if silo_manager.cryopod_2:
		silo_manager.cryopod_2.player_entered_capsule.connect(_on_player_entered_capsule)
		silo_manager.cryopod_2.player_exited_capsule.connect(_on_player_exited_capsule)
		silo_manager.cryopod_2.capsule_state_changed.connect(_on_capsule_changed)
		print("✅ 3D_Screen: Подключен к Cryopod 2")
	
	if silo_manager.cryopod_3:
		silo_manager.cryopod_3.player_entered_capsule.connect(_on_player_entered_capsule)
		silo_manager.cryopod_3.player_exited_capsule.connect(_on_player_exited_capsule)
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
	_update_ui()

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
	print("📦 3D_Screen: Силос ", "поднят" if is_raised else "опущен")
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

func _on_player_entered_capsule(capsule_id: int) -> void:
	match capsule_id:
		1: active_cryopod = silo_manager.cryopod_1
		2: active_cryopod = silo_manager.cryopod_2
		3: active_cryopod = silo_manager.cryopod_3
	print("👤 3D_Screen: Игрок в капсуле ", capsule_id)
	_update_ui()

func _on_player_exited_capsule(capsule_id: int) -> void:
	active_cryopod = null
	print("🚶 3D_Screen: Игрок вышел из капсулы")
	_update_ui()

# === ОБРАБОТКА КЛИКОВ ПО 3D КНОПКАМ ===
func _on_3d_button_clicked(button_name: String) -> void:
	if is_animating:
		print("⏳ Анимация в процессе, ожидайте...")
		return
	
	print("🎮 3D_Screen получил клик: ", button_name)
	_flash_button(button_name)
	
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
func _flash_button(button_name: String) -> void:
	"""Визуальная вспышка экрана при нажатии любой кнопки"""
	if not screen_material:
		return
	
	var original_tint = screen_material.get_shader_parameter("tint_color")
	var original_flicker = screen_material.get_shader_parameter("flicker_strength")
	
	screen_material.set_shader_parameter("tint_color", Color(0.2, 1.0, 0.3, 1.0))
	screen_material.set_shader_parameter("flicker_strength", 0.2)
	
	await get_tree().create_timer(0.2).timeout
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
	
	# Показываем основные кнопки
	mesh_btn_silo.visible = true
	mesh_btn_manage_pit.visible = true
	
	# Обновляем текст кнопки силоса
	if silo_raised:
		lbl_btn_silo.text = "Lower CryoSilo"
		_set_button_enabled(mesh_btn_silo, not caps_raised and not is_animating)
	else:
		lbl_btn_silo.text = "Raise CryoSilo"
		_set_button_enabled(mesh_btn_silo, not is_animating)
	
	# Обновляем текст кнопки капсул
	if caps_raised:
		lbl_btn_pit.text = "Lower Cryopods"
		_set_button_enabled(mesh_btn_manage_pit, not _any_capsule_open() and not is_animating)
	else:
		lbl_btn_pit.text = "Raise Cryopods"
		_set_button_enabled(mesh_btn_manage_pit, silo_raised and not is_animating)
	
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
	"""Включение/выключение кнопки через прозрачность материала"""
	if not button:
		return
	
	var mat = button.get_active_material(0)
	if mat is StandardMaterial3D:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color.a = 1.0 if enabled else 0.3
	elif mat is ShaderMaterial:
		# Если у вас шейдер материал, добавьте параметр альфы
		if mat.get_shader_parameter("alpha") != null:
			mat.set_shader_parameter("alpha", 1.0 if enabled else 0.3)

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
