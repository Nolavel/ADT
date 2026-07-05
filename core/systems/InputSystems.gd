# InputSystems.gd — autoload, extends Node (НЕ Node3D — визуала тут нет)
extends Node

## === РЕЖИМ УПРАВЛЕНИЯ ===
enum ControlMode { PLAYER, FLYCAR, TUBE }
var current_control_mode: ControlMode = ControlMode.PLAYER

## === СИГНАЛЫ (логика → визуал) ===
signal status_camera_toggled(status_is_active: bool)
signal menu_pause_toggled(mp_is_active: bool)
signal inventory_toggled(inventory_is_active: bool)
signal crafting_toggled(crafting_is_active: bool)
signal map_toggled(map_is_active: bool)
signal fog_effect_toggled(is_paused: bool)

signal move_target_requested(world_position: Vector3, is_running: bool)
signal move_target_invalid(world_position: Vector3)
signal move_target_cleared()
signal control_mode_changed(new_mode: ControlMode)

signal player_registered(p: CharacterBody3D)
signal player_unregistered()

const GROUND_LAYER = 2

## --- Состояние ввода ---
var interact_button_pressed_time: float = 0.0
var interact_button_held: bool = false
const INTERACT_HOLD_TIME: float = 0.5

var right_click_duration: float = 0.0
var is_running: bool = false
const RUN_TRIGGER_TIME: float = 0.5

var status_pressed_time: float = 0.0
var status_pressing: bool = false
var status_notifier: bool = false

var status_camera_active: bool = false
var menu_pause_active: bool = false
var inventory_active: bool = false
var crafting_active: bool = false
var map_active: bool = false

enum UIState { GAME, STATUS, INVENTORY, CRAFTING, MENU_PAUSE, MAP, VEHICLE }
var current_ui_state: UIState = UIState.GAME

## ============================================
## РЕФЕРЕНСЫ
## ============================================
var player_node: CharacterBody3D
var camera: Camera3D
var hud_node: CanvasLayer

func register_player(p: CharacterBody3D) -> void:
	if player_node and is_instance_valid(player_node):
		_disconnect_player(player_node)
	player_node = p
	if not player_node:
		push_error("InputSystems.register_player: передан null!")
		return
	player_node.movement_started.connect(_on_movement_started)
	player_node.movement_stopped.connect(_on_movement_stopped)
	player_registered.emit(player_node)
	print("✅ InputSystems: player_node назначен")

func unregister_player() -> void:
	if player_node and is_instance_valid(player_node):
		_disconnect_player(player_node)
	player_node = null
	player_unregistered.emit()

func _disconnect_player(p: CharacterBody3D) -> void:
	if p.movement_started.is_connected(_on_movement_started):
		p.movement_started.disconnect(_on_movement_started)
	if p.movement_stopped.is_connected(_on_movement_stopped):
		p.movement_stopped.disconnect(_on_movement_stopped)

func register_camera(cam: Camera3D) -> void:
	camera = cam

func unregister_camera() -> void:
	camera = null

func register_hud(hud: CanvasLayer) -> void:
	hud_node = hud

func unregister_hud() -> void:
	hud_node = null

func set_control_mode(mode: ControlMode) -> void:
	if current_control_mode == mode:
		return
	current_control_mode = mode
	control_mode_changed.emit(mode)

## ============================================
## ОСНОВНОЙ ЦИКЛ
## ============================================
func _physics_process(delta: float) -> void:
	if not player_node or not is_instance_valid(player_node):
		return

	var can_control_movement = current_ui_state == UIState.GAME \
		and current_control_mode == ControlMode.PLAYER

	if can_control_movement:
		_handle_interact_action()

	if can_control_movement and player_node.is_movement_enabled():
		_handle_right_click(delta)
		_handle_left_click()

	_update_system_press_time(delta)
	_handle_camera_status()
	_handle_menu_pause()
	_handle_inventory_hotkey()
	_handle_crafting_hotkey()
	_handle_map_hotkey()

## ============================================
## ХОТКЕИ
## ============================================
func _handle_interact_action() -> void:
	if Input.is_action_just_pressed("Interact"):
		interact_button_pressed_time = 0.0
		interact_button_held = true

	elif Input.is_action_pressed("Interact") and interact_button_held:
		interact_button_pressed_time += get_process_delta_time()

		if interact_button_pressed_time >= INTERACT_HOLD_TIME:
			var interact_manager = player_node.get_node("InteractManager")
			if interact_manager and interact_manager.has_method("try_interact"):
				interact_manager.try_interact()
				interact_button_held = false

	elif Input.is_action_just_released("Mouse_Left_Button") and interact_button_held:
		interact_button_held = false
		interact_button_pressed_time = 0.0

func _handle_inventory_hotkey() -> void:
	if Input.is_action_just_pressed("Inventory"):
		if menu_pause_active:
			print("⚠️ Нельзя открыть Inventory - активна Menu Pause")
			return
		_switch_to_tabs_state(UIState.INVENTORY)

func _handle_crafting_hotkey() -> void:
	if Input.is_action_just_pressed("Crafting"):
		if menu_pause_active:
			print("⚠️ Нельзя открыть Crafting - активна Menu Pause")
			return
		_switch_to_tabs_state(UIState.CRAFTING)

func _handle_map_hotkey() -> void:
	if Input.is_action_just_pressed("Map"):
		if menu_pause_active:
			print("⚠️ Нельзя открыть Map - активна Menu Pause")
			return
		_switch_to_tabs_state(UIState.MAP)

func _handle_menu_pause() -> void:
	if Input.is_action_just_released("pause"):
		if menu_pause_active:
			menu_pause_active = false
			current_ui_state = UIState.GAME
			menu_pause_toggled.emit(false)
			fog_effect_toggled.emit(false)
			print("🎮 Menu Pause: CLOSED")
			return

		if current_ui_state != UIState.GAME:
			_return_to_game_from_tabs()
			return

		menu_pause_active = true
		current_ui_state = UIState.MENU_PAUSE
		menu_pause_toggled.emit(true)
		fog_effect_toggled.emit(true)

		if hud_node and hud_node.has_method("force_close_tabs"):
			hud_node.force_close_tabs()

		print("🎮 Menu Pause: OPENED")

func _return_to_game_from_tabs() -> void:
	var old_state = current_ui_state
	current_ui_state = UIState.GAME

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

	if player_node and player_node.has_method("set_movement_enabled"):
		player_node.set_movement_enabled(true)

	fog_effect_toggled.emit(false)

	print("⏎ ESC: %s → GAME" % UIState.keys()[old_state])

func close_pause_menu() -> void:
	if menu_pause_active:
		menu_pause_active = false
		menu_pause_toggled.emit(false)
		fog_effect_toggled.emit(false)

		if player_node and player_node.has_method("set_movement_enabled"):
			player_node.set_movement_enabled(true)

		print("🎮 Menu Pause закрыто через Continue | Движение восстановлено")

## ============================================
## STATUS CAMERA
## ============================================
func _update_system_press_time(delta: float) -> void:
	if status_pressing:
		status_pressed_time += delta
		if Input.is_action_just_released("toggle_tabs"):
			if status_pressed_time < 0.5:
				_toggle_status_notifier()
			else:
				_toggle_status_camera()
			status_pressing = false

func _handle_camera_status() -> void:
	if Input.is_action_just_pressed("toggle_tabs"):
		status_pressed_time = 0.0
		status_pressing = true
	if Input.is_action_just_pressed("Status"):
		_toggle_status_camera()

func _toggle_status_notifier() -> void:
	status_notifier = !status_notifier
	print("Status Notifier: %s" % ("ON" if status_notifier else "OFF"))

func _toggle_status_camera() -> void:
	if menu_pause_active:
		print("⚠️ Нельзя открыть STATUS - активна Menu Pause")
		return
	_switch_to_tabs_state(UIState.STATUS)

## ============================================
## РЕЙКАСТ / КЛИКИ
## ============================================
func _handle_right_click(delta: float) -> void:
	if Input.is_action_just_pressed("Mouse_Right_Button"):
		right_click_duration = 0.0
		is_running = false
		_set_target_from_raycast()
		player_node.set_movement_speed(player_node.walk_speed)

	if Input.is_action_pressed("Mouse_Right_Button"):
		right_click_duration += delta
		_set_target_from_raycast()

		if right_click_duration > RUN_TRIGGER_TIME and not is_running:
			is_running = true
			player_node.set_movement_speed(player_node.run_speed)

	if Input.is_action_just_released("Mouse_Right_Button"):
		right_click_duration = 0.0
		is_running = false

func _handle_left_click() -> void:
	if Input.is_action_just_pressed("Mouse_Left_Button"):
		player_node.stop_moving(true)
		right_click_duration = 0.0
		is_running = false
		move_target_cleared.emit()

func _set_target_from_raycast() -> void:
	if not camera:
		return

	var mouse_pos = camera.get_viewport().get_mouse_position()
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_direction = camera.project_ray_normal(mouse_pos)
	var ray_end = ray_origin + ray_direction * 1000.0

	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collision_mask = 1 << (GROUND_LAYER - 1)

	var result = camera.get_world_3d().direct_space_state.intersect_ray(query)

	if result:
		var collider = result.collider
		if collider.is_in_group("floor"):
			player_node.move_to_position(result.position)
			move_target_requested.emit(result.position, is_running)
		else:
			_handle_invalid_click(result.position, collider, "не в группе 'floor'")
	else:
		_handle_invalid_click(Vector3.ZERO, null, "не является ground")

func _handle_invalid_click(pos: Vector3, collider, reason: String) -> void:
	if player_node and player_node.has_method("stop_moving"):
		player_node.stop_moving(true)
	move_target_invalid.emit(pos)
	if collider:
		print("⛔ Клик по объекту '%s' (%s)" % [collider.name, reason])
	else:
		print("⛔ Клик по объекту, который %s" % reason)

## ============================================
## КОЛЛБЭКИ ДВИЖЕНИЯ ИГРОКА
## ============================================
func _on_movement_started() -> void:
	pass  # индикатор сам реагирует на move_target_requested

func _on_movement_stopped() -> void:
	move_target_cleared.emit()

## ============================================
## UI STATE SWITCH
## ============================================
func _switch_to_tabs_state(new_state: UIState) -> void:
	var old_state = current_ui_state
	current_ui_state = new_state

	status_camera_active = false
	inventory_active = false
	crafting_active = false
	map_active = false

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
