# =============================================================================
# click_to_move_system.gd — обычная нода, НЕ автозагрузка.
#
# Владелец: world.gd — создаёт через .new() и держит как дочернюю ноду
# (тот же паттерн, что уже используется для камерных компонентов в
# camera_follow.gd). Всем, кому нужны сигналы/данные отсюда (HUDComponent),
# ссылка передаётся явно через setup()/публичный метод — никакого поиска
# по группам и никакого singleton-доступа по имени класса.
#
# Вся логика "клик по земле → игрок туда идёт": рейкаст, решение "валидная
# ли точка", вызов player_node.move_to_position(...). InputSystems (который
# остаётся автозагрузкой) ничего из этого не знает — только эмитит сырые
# primary/secondary click сигналы.
#
# Активен ТОЛЬКО когда PlayerState.mode == ON_FOOT и
# view_mode == ISOMETRIC — сам себя гейтит через
# PlayerState.mode_changed / view_mode_changed, никто снаружи это не решает.
#
# Also gated off during Stance.COMBAT (subscribes to PlayerState.stance_
# changed too): in COMBAT, mouse_left_button throws a punch instead (see
# player.gd's _on_primary_click_pressed()) — this system yields the whole
# button rather than the punch handler and this one racing to interpret the
# same click differently.
# =============================================================================
extends Node
class_name ClickToMoveSystem

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
	PlayerState.stance_changed.connect(_on_stance_changed)

	InputSystems.primary_click_pressed.connect(_on_primary_click_pressed)
	InputSystems.secondary_click_pressed.connect(_on_secondary_click_pressed)
	InputSystems.secondary_click_held.connect(_on_secondary_click_held)
	InputSystems.secondary_click_released.connect(_on_secondary_click_released)

	_update_active_state()


## ============================================
## РЕГИСТРАЦИЯ ИГРОКА / КАМЕРЫ (вызывается из world.gd при спавне)
## ============================================

## Единая точка входа, которую зовёт world.gd из декларативного списка
## WORLD_SYSTEM_SCRIPTS — вместо ручных register_player()/register_camera()
## по месту. Сами register_* методы остаются публичными (пригодятся, если
## понадобится перерегистрация без полного on_world_ready, например при
## будущей динамической смене игрока).
func on_world_ready(context: WorldContext) -> void:
	register_player(context.player)
	register_camera(context.camera)


func register_player(p: CharacterBody3D) -> void:
	if player_node and is_instance_valid(player_node):
		_disconnect_player(player_node)
	player_node = p
	if not player_node:
		push_error("ClickToMoveSystem.register_player: передан null!")
		return
	player_node.movement_stopped.connect(_on_movement_stopped)
	## Gives player.gd a way back to raycast_ground_point() below (see that
	## method's own comment) — player.gd isn't in world.gd's on_world_ready()
	## sweep, so this is the only route it has to a ClickToMoveSystem
	## reference. Duck-typed the same way _handle_invalid_click() already
	## calls player_node.stop_moving(), since player_node is typed
	## CharacterBody3D here, not Player.
	if player_node.has_method("set_click_to_move_system"):
		player_node.set_click_to_move_system(self)
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


## Handled separately from _on_player_state_changed() because a stance flip
## into COMBAT also needs to stop a path already in progress, not just
## deactivate: player.gd's navigation branch is keyed on view_mode alone
## (see its _physics_process()), so it keeps advancing an active path
## regardless of this system's _is_active — unlike a mode/view_mode change,
## which always also flips the navigation branch itself. _is_active is
## checked before _update_active_state() below recomputes it, so it still
## reflects whether a path could have been running under the stance that is
## ending.
func _on_stance_changed(_old_stance: PlayerState.Stance, new_stance: PlayerState.Stance) -> void:
	if new_stance == PlayerState.Stance.COMBAT and _is_active and player_node:
		player_node.stop_moving(true)
	_update_active_state()


func _update_active_state() -> void:
	_is_active = PlayerState.mode == PlayerState.Mode.ON_FOOT \
		and PlayerState.view_mode == PlayerState.ViewMode.ISOMETRIC \
		and PlayerState.stance == PlayerState.Stance.PEACE

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

## Raw ground-layer raycast shared by _raycast_and_move() and
## raycast_ground_point() below — pulled out so the second one is a real
## reuse of the same physics test, not a duplicate raycast against the
## camera. Returns Godot's raw intersect_ray() result: an empty Dictionary
## on no hit, a Dictionary with "position"/"collider"/etc. on a hit — the
## caller still decides what a hit that isn't in the "floor" group means, so
## this stays a plain wrapper rather than baking group-membership into it.
func _cast_ground_ray(screen_pos: Vector2) -> Dictionary:
	if not camera:
		return {}

	var ray_origin := camera.project_ray_origin(screen_pos)
	var ray_direction := camera.project_ray_normal(screen_pos)
	var ray_end := ray_origin + ray_direction * 1000.0

	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collision_mask = 1 << (GROUND_LAYER - 1)

	return camera.get_world_3d().direct_space_state.intersect_ray(query)


func _raycast_and_move() -> void:
	if not camera or not player_node:
		return

	var mouse_pos := camera.get_viewport().get_mouse_position()
	var result := _cast_ground_ray(mouse_pos)

	if result:
		var collider = result.collider
		if collider.is_in_group("floor"):
			player_node.move_to_position(result.position)
			move_target_requested.emit(result.position, _is_running)
		else:
			_handle_invalid_click(result.position, collider, "не в группе 'floor'")
	else:
		_handle_invalid_click(Vector3.ZERO, null, "не является ground")


## Ground-point lookup for callers outside click-to-move that need the same
## world point a move order would use, without issuing one — today just
## player.gd's COMBAT punch facing in ISOMETRIC (_face_punch_target()),
## reusing this instead of a second raycast from the camera. Same hit test
## as a move order (GROUND_LAYER, "floor" group); returns null instead of a
## Vector3 when nothing valid was hit, since Vector3 has no "no point" value
## of its own.
func raycast_ground_point(screen_pos: Vector2) -> Variant:
	var result := _cast_ground_ray(screen_pos)
	if result and result.collider.is_in_group("floor"):
		return result.position
	return null


func _handle_invalid_click(pos: Vector3, collider, reason: String) -> void:
	if player_node and player_node.has_method("stop_moving"):
		player_node.stop_moving(true)
	move_target_invalid.emit(pos)
	if collider:
		print("⛔ Клик по объекту '%s' (%s)" % [collider.name, reason])
	else:
		print("⛔ Клик по объекту, который %s" % reason)
