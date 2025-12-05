# InputManager.gd
extends Node3D

class_name InputManager

## === СИГНАЛЫ ===
signal status_camera_toggled(status_is_active: bool)
signal menu_pause_toggled(mp_is_active: bool)
signal inventory_toggled(inventory_is_active: bool)
signal crafting_toggled(crafting_is_active: bool)
signal map_toggled(map_is_active: bool)
signal fog_effect_toggled(is_paused: bool)

## --- Экспортируемые референсы ---
@export_group("References")
@export var player: NodePath
@export var menu_pause: Control
@export var hud: NodePath

@export_subgroup("Cameras")
@export var camera_follow: Camera3D

## --- Визуальные эффекты ---
@onready var target_indicator: TargetIndicator = $TargetIndicator
@onready var orbital_particles: OrbitalParticleEffect = $OrbitalParticleEffect
@onready var terrain_scanner: TerrainScannerEffect = $TerrainScannerEffect
@onready var label_actives = $"WidgetCursor/VBoxContainer/P-actives"

@export_subgroup("Debug")
@export var label_debug: Label

@export_subgroup("Audio")
@export var error_sound: AudioStreamPlayer

## --- Константы ---
const GROUND_LAYER = 2

## --- Состояние ввода ---
var right_click_duration: float = 0.0
var is_running: bool = false
const RUN_TRIGGER_TIME: float = 0.5

var status_pressed_time: float = 0.0
var status_pressing: bool = false
var status_notifier: bool = false

## --- Флаги UI ---
var status_camera_active: bool = false
var menu_pause_active: bool = false
var inventory_active: bool = false
var crafting_active: bool = false
var map_active: bool = false

## --- Кешированные референсы ---
var player_node: CharacterBody3D
var camera: Camera3D
var hud_node: CanvasLayer

## --- Состояния UI ---
enum UIState { GAME, STATUS, INVENTORY, CRAFTING, MENU_PAUSE, MAP }
var current_ui_state: UIState = UIState.GAME

## ============================================
## ИНИЦИАЛИЗАЦИЯ
## ============================================
func _ready():
	## Получаем референс игрока
	player_node = get_node(player)
	
	if player_node:
		## Подключаем сигналы движения
		player_node.movement_started.connect(_on_movement_started)
		player_node.movement_stopped.connect(_on_movement_stopped)
		
		## Передаём игрока визуальным эффектам
		if target_indicator:
			target_indicator.set_player_reference(player_node)
		if orbital_particles:
			orbital_particles.set_player_reference(player_node)
		if terrain_scanner:
			terrain_scanner.set_player_reference(player_node)
	else:
		push_error("Player node not found!")
	
	## Получаем активную камеру
	camera = get_viewport().get_camera_3d()
	
	## Подключаем HUD
	if hud:
		hud_node = get_node(hud)
		if hud_node:
			print("✅ InputManager: HUD подключен")
		else:
			push_error("❌ HUD node not found!")
	
	## Активируем камеру слежения
	if camera_follow:
		camera_follow.make_current()
	
	## Валидация звука ошибки
	if not error_sound:
		push_warning("⚠️ AudioStreamPlayer для error_sound не назначен!")
	
	## Валидация индикатора
	if not target_indicator:
		push_warning("⚠️ TargetIndicator не найден!")

## ============================================
## ОСНОВНОЙ ЦИКЛ
## ============================================
func _physics_process(delta: float) -> void:
	if not player_node:
		return
	
	## Проверяем возможность управления движением
	var can_control_movement = current_ui_state == UIState.GAME
	
	## Обрабатываем взаимодействие с объектами
	if can_control_movement:
		_handle_interact_action()
	
	## Обрабатываем клики мыши только в режиме игры
	if can_control_movement and player_node.is_movement_enabled():
		_handle_right_click(delta)
		_handle_left_click()
	
	## Обновляем UI и обрабатываем хоткеи
	_update_ui()
	_update_system_press_time(delta)
	_handle_camera_status()
	_handle_menu_pause()
	_handle_inventory_hotkey()
	_handle_crafting_hotkey()
	_handle_map_hotkey()
	_handle_scanner_toggle()

## ============================================
## ХОТКЕИ
## ============================================

## Обработка клавиши взаимодействия (E)
func _handle_interact_action() -> void:
	if Input.is_action_just_pressed("Interact"):
		## Получаем InteractManager из игрока
		var interact_manager = player_node.get_node("InteractManager")
		if interact_manager and interact_manager.has_method("try_interact"):
			interact_manager.try_interact()

## Переключение сканера местности (S)
func _handle_scanner_toggle() -> void:
	## Работает только в режиме игры
	if current_ui_state != UIState.GAME:
		return
	
	if Input.is_action_just_pressed("toggle_scanner"):
		if terrain_scanner:
			if terrain_scanner.is_active:
				terrain_scanner.deactivate()
				print("🔍 Сканер: ВЫКЛ (через S)")
			else:
				terrain_scanner.activate()
				print("🔍 Сканер: ВКЛ (через S)")

## Хоткей Inventory (I)
func _handle_inventory_hotkey() -> void:
	if Input.is_action_just_pressed("Inventory"):
		## Блокируем если открыта пауза
		if menu_pause_active:
			print("⚠️ Нельзя открыть Inventory - активна Menu Pause")
			return
		_switch_to_tabs_state(UIState.INVENTORY)

## Хоткей Crafting (C)
func _handle_crafting_hotkey() -> void:
	if Input.is_action_just_pressed("Crafting"):
		## Блокируем если открыта пауза
		if menu_pause_active:
			print("⚠️ Нельзя открыть Crafting - активна Menu Pause")
			return
		_switch_to_tabs_state(UIState.CRAFTING)

## Хоткей Map (M)
func _handle_map_hotkey() -> void:
	if Input.is_action_just_pressed("Map"):
		## Блокируем если открыта пауза
		if menu_pause_active:
			print("⚠️ Нельзя открыть Map - активна Menu Pause")
			return
		_switch_to_tabs_state(UIState.MAP)

## Обработка паузы (ESC)
func _handle_menu_pause():
	if Input.is_action_just_released("pause"):
		## Если пауза уже открыта - закрываем
		if menu_pause_active:
			menu_pause_active = false
			current_ui_state = UIState.GAME
			menu_pause_toggled.emit(false)
			fog_effect_toggled.emit(false)
			print("🎮 Menu Pause: CLOSED")
			return
		
		## Если открыт другой UI - возвращаемся в игру
		if current_ui_state != UIState.GAME:
			_return_to_game_from_tabs()
			return
		
		## Открываем паузу
		menu_pause_active = true
		current_ui_state = UIState.MENU_PAUSE
		menu_pause_toggled.emit(true)
		fog_effect_toggled.emit(true)
		
		## Закрываем все табы
		if hud_node and hud_node.has_method("force_close_tabs"):
			hud_node.force_close_tabs()
		
		print("🎮 Menu Pause: OPENED")

## Возврат из вкладок в игру через ESC
func _return_to_game_from_tabs():
	var old_state = current_ui_state
	current_ui_state = UIState.GAME
	
	## Закрываем все активные UI
	if status_camera_active:
		status_camera_active = false
		status_camera_toggled.emit(false)
	if inventory_active:
		inventory_active = false
		inventory_toggled.emit(false)
	if crafting_active:
		crafting_active = false
		crafting_toggled.emit(false)
	if map_active:
		map_active = false
		map_toggled.emit(false)
	
	## Восстанавливаем движение
	if player_node and player_node.has_method("set_movement_enabled"):
		player_node.set_movement_enabled(true)
	
	## Отключаем туман
	fog_effect_toggled.emit(false)
	
	print("⏎ ESC: %s → GAME" % UIState.keys()[old_state])

## Закрытие паузы через кнопку Continue
func close_pause_menu():
	if menu_pause_active:
		menu_pause_active = false
		menu_pause_toggled.emit(false)
		fog_effect_toggled.emit(false)
		
		## Восстанавливаем движение
		if player_node and player_node.has_method("set_movement_enabled"):
			player_node.set_movement_enabled(true)
		
		print("🎮 Menu Pause закрыто через Continue | Движение восстановлено")

## ============================================
## STATUS CAMERA
## ============================================

## Подсчёт времени удержания клавиши TAB
func _update_system_press_time(delta: float) -> void:
	if status_pressing:
		status_pressed_time += delta
		if Input.is_action_just_released("toggle_tabs"):
			## Короткое нажатие - Status Notifier
			if status_pressed_time < 0.5:
				_toggle_status_notifier()
			## Долгое нажатие - Status Camera
			else:
				_toggle_status_camera()
			status_pressing = false

## Обработка нажатий Status Camera (TAB/P)
func _handle_camera_status() -> void:
	if Input.is_action_just_pressed("toggle_tabs"):
		status_pressed_time = 0.0
		status_pressing = true
	if Input.is_action_just_pressed("Status"):
		_toggle_status_camera()

## Переключение статус-нотификатора (короткое TAB)
func _toggle_status_notifier() -> void:
	status_notifier = !status_notifier
	label_debug.text = "Status Notifier: %s" % ("ON" if status_notifier else "OFF")

## Переключение камеры статуса (долгое TAB / P)
func _toggle_status_camera() -> void:
	## Блокируем если открыта пауза
	if menu_pause_active:
		print("⚠️ Нельзя открыть STATUS - активна Menu Pause")
		return
	_switch_to_tabs_state(UIState.STATUS)

## ============================================
## ОБРАБОТКА КЛИКОВ С ИНДИКАТОРОМ
## ============================================

## Правая кнопка мыши (движение)
func _handle_right_click(delta: float) -> void:
	## Начало клика - ходьба
	if Input.is_action_just_pressed("Mouse_Right_Button"):
		right_click_duration = 0.0
		is_running = false
		_set_target_from_raycast()
		player_node.set_movement_speed(player_node.walk_speed)
	
	## Удержание клика
	if Input.is_action_pressed("Mouse_Right_Button"):
		right_click_duration += delta
		_set_target_from_raycast()

		## Переход в бег после 0.5 секунды
		if right_click_duration > RUN_TRIGGER_TIME and not is_running:
			is_running = true
			player_node.set_movement_speed(player_node.run_speed)
			
			## Обновляем индикатор на оранжевый (бег)
			if target_indicator and target_indicator.is_visible:
				target_indicator.show_at_position(target_indicator.global_position, true)
	
	## Отпускание клика
	if Input.is_action_just_released("Mouse_Right_Button"):
		right_click_duration = 0.0
		is_running = false

## Левая кнопка мыши (остановка)
func _handle_left_click() -> void:
	if Input.is_action_just_pressed("Mouse_Left_Button"):
		## Останавливаем игрока
		player_node.stop_moving(true)
		right_click_duration = 0.0
		is_running = false
		
		## Скрываем индикатор
		if target_indicator:
			target_indicator.hide_indicator()

## Установка цели движения через рейкаст
func _set_target_from_raycast() -> void:
	if not camera:
		return
	
	## Создаём луч от камеры к курсору
	var mouse_pos = get_viewport().get_mouse_position()
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_direction = camera.project_ray_normal(mouse_pos)
	var ray_end = ray_origin + ray_direction * 1000.0
	
	## Настраиваем рейкаст только для ground слоя
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collision_mask = 1 << (GROUND_LAYER - 1)
	
	var result = get_world_3d().direct_space_state.intersect_ray(query)
	
	if result:
		var collider = result.collider
		
		## Валидная поверхность (группа ground)
		if collider.is_in_group("ground"):
			player_node.move_to_position(result.position)
			
			## Показываем индикатор (зелёный/оранжевый)
			if target_indicator:
				target_indicator.show_at_position(result.position, is_running)
		else:
			## Невалидная поверхность
			_handle_invalid_click(collider, "не в группе 'ground'")
	else:
		## Клик в пустоту
		_handle_invalid_click(null, "не является ground")

## Обработка клика по невалидной поверхности
func _handle_invalid_click(collider, reason: String) -> void:
	## Останавливаем игрока
	if player_node and player_node.has_method("stop_moving"):
		player_node.stop_moving(true)
	
	## Показываем красный индикатор ошибки
	if target_indicator and camera:
		var mouse_pos = get_viewport().get_mouse_position()
		var ray_origin = camera.project_ray_origin(mouse_pos)
		var ray_direction = camera.project_ray_normal(mouse_pos)
		var ray_end = ray_origin + ray_direction * 1000.0
		
		var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
		var result = get_world_3d().direct_space_state.intersect_ray(query)
		
		if result:
			target_indicator.show_invalid_click(result.position)
	
	## Воспроизводим звук ошибки
	if error_sound:
		error_sound.play()
	
	## Логируем причину
	if collider:
		print("⛔ Клик по объекту '%s' (%s)" % [collider.name, reason])
	else:
		print("⛔ Клик по объекту, который %s" % reason)

## ============================================
## КОЛЛБЭКИ ДВИЖЕНИЯ
## ============================================

## Игрок начал движение
func _on_movement_started() -> void:
	## Индикатор уже показан через show_at_position()
	if orbital_particles:
		orbital_particles.deactivate()

## Игрок остановился
func _on_movement_stopped() -> void:
	## Скрываем индикатор с анимацией
	if target_indicator:
		target_indicator.hide_indicator()
	if orbital_particles:
		orbital_particles.activate()

## ============================================
## UI
## ============================================

## Обновление текста UI
func _update_ui() -> void:
	var status_text = _get_status_text()
	var speed = player_node.get_current_speed()
	
	if status_camera_active:
		label_actives.text = "STATUS CAMERA ACTIVE | скорость: %.1f" % speed
	elif menu_pause_active:
		label_actives.text = "MENU PAUSE ACTIVE | скорость: %.1f" % speed
	else:
		label_actives.text = "%s | скорость: %.1f" % [status_text, speed]

## Получение текста статуса движения
func _get_status_text() -> String:
	if right_click_duration > RUN_TRIGGER_TIME:
		return "зажата ПКМ"
	return player_node.get_state_name()

## Переключение состояния UI (Inventory/Crafting/Status/Map)
func _switch_to_tabs_state(new_state: UIState):
	var old_state = current_ui_state
	current_ui_state = new_state
	
	## Сбрасываем все флаги
	status_camera_active = false
	inventory_active = false
	crafting_active = false
	map_active = false
	
	## Активируем нужный UI
	match new_state:
		UIState.STATUS:
			status_camera_active = true
			status_camera_toggled.emit(true)
		UIState.INVENTORY:
			inventory_active = true
			inventory_toggled.emit(true)
		UIState.CRAFTING:
			crafting_active = true
			crafting_toggled.emit(true)
		UIState.MAP:
			map_active = true
			map_toggled.emit(true)
	
	status_notifier = false
	print("🔄 Хоткей: %s → %s" % [UIState.keys()[old_state], UIState.keys()[new_state]])
