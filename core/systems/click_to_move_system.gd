# =============================================================================
# click_to_move_system.gd — autoload.
#
# Вся логика "клик по земле → игрок туда идёт" перенесена сюда из
# InputSystems: рейкаст, решение "валидная ли точка", вызов
# player_node.move_to_position(...). InputSystems теперь не знает
# ничего из этого — только эмитит сырые primary/secondary click сигналы.
#
# Активен ТОЛЬКО когда PlayerState.mode == ON_FOOT и
# view_mode in [ISOMETRIC, TOPDOWN] — сам себя гейтит через
# PlayerState.mode_changed / view_mode_changed, никто снаружи это не решает.
# =============================================================================
extends Node

const GROUND_LAYER = 2
const RUN_TRIGGER_TIME: float = 0.5

signal move_target_requested(world_position: Vector3, is_running: bool)
signal move_target_invalid(world_position: Vector3)
signal move_target_cleared()

signal player_registered(p: CharacterBody3D)
signal player_unregistered()

var player_node: CharacterBody3D
var camera: Camera3D

var _is_running: bool = false
var _is_active: bool = false


func _ready() -> void:
	PlayerState.mode_changed.connect(_on_player_state_changed)
	PlayerState.view_mode_changed.connect(_on_player_state_changed)

	InputSystems.primary_click_pressed.connect(_on_primary_click_pressed)
	InputSystems.secondary_click_pressed.connect(_on_secondary_click_pressed)
	InputSystems.secondary_click_held.connect(_on_secondary_click_held)
	InputSystems.secondary_click_released.connect(_on_secondary_click_released)

	_update_active_state()


## ============================================
## РЕГИСТРАЦИЯ ИГРОКА / КАМЕРЫ (вызывается из world.gd при спавне)
## ============================================
func register_player(p: CharacterBody3D) -> void:
	if player_node and is_instance_valid(player_node):
		_disconnect_player(player_node)
	player_node = p
	if not player_node:
		push_error("ClickToMoveSystem.register_player: передан null!")
		return
	player_node.movement_stopped.connect(_on_movement_stopped)
	player_registered.emit(player_node)


func unregister_player() -> void:
	if player_node and is_instance_valid(player_node):
		_disconnect_player(player_node)
	player_node = null
	player_unregistered.emit()


func _disconnect_player(p: CharacterBody3D) -> void:
	if p.movement_stopped.is_connected(_on_movement_stopped):
		p.movement_stopped.disconnect(_on_movement_stopped)


func register_camera(cam: Camera3D) -> void:
	camera = cam


func unregister_camera() -> void:
	camera = null


## ============================================
## ГЕЙТИНГ АКТИВНОСТИ
## ============================================
func _on_player_state_changed(_old, _new) -> void:
	_update_active_state()


func _update_active_state() -> void:
	_is_active = PlayerState.mode == PlayerState.Mode.ON_FOOT \
		and PlayerState.view_mode in [PlayerState.ViewMode.ISOMETRIC, PlayerState.ViewMode.TOPDOWN]

	if not _is_active:
		_is_running = false
		move_target_cleared.emit()


## ============================================
## ОБРАБОТКА КЛИКОВ
## ============================================
func _on_primary_click_pressed(_screen_pos: Vector2) -> void:
	if not _is_active or not player_node:
		return
	player_node.stop_moving(true)
	_is_running = false
	move_target_cleared.emit()


func _on_secondary_click_pressed(_screen_pos: Vector2) -> void:
	if not _is_active or not player_node:
		return
	_is_running = false
	player_node.set_movement_speed(player_node.walk_speed)
	_raycast_and_move()


func _on_secondary_click_held(_screen_pos: Vector2, duration: float) -> void:
	if not _is_active or not player_node:
		return
	_raycast_and_move()
	if duration > RUN_TRIGGER_TIME and not _is_running:
		_is_running = true
		player_node.set_movement_speed(player_node.run_speed)


func _on_secondary_click_released(_screen_pos: Vector2) -> void:
	_is_running = false


func _on_movement_stopped() -> void:
	move_target_cleared.emit()


## ============================================
## РЕЙКАСТ
## ============================================
func _raycast_and_move() -> void:
	if not camera or not player_node:
		return

	var mouse_pos := camera.get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_direction := camera.project_ray_normal(mouse_pos)
	var ray_end := ray_origin + ray_direction * 1000.0

	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collision_mask = 1 << (GROUND_LAYER - 1)

	var result := camera.get_world_3d().direct_space_state.intersect_ray(query)

	if result:
		var collider = result.collider
		if collider.is_in_group("floor"):
			player_node.move_to_position(result.position)
			move_target_requested.emit(result.position, _is_running)
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
