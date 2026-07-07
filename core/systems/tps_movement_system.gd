# =============================================================================
# tps_movement_system.gd — обычная нода, братан click_to_move_system.gd.
#
# Владелец: world.gd — создаёт через .new() и регистрирует так же, как
# ClickToMoveSystem (register_player/register_camera).
#
# Активен ТОЛЬКО когда PlayerState.mode == ON_FOOT и
# view_mode == TPS — сам себя гейтит через PlayerState.mode_changed /
# view_mode_changed, ровно тот же принцип, что у ClickToMoveSystem.
#
# WASD/Shift — непрерывный held-инпут, поэтому читаем Input.get_vector()
# каждый _physics_process напрямую (сигнальная модель InputSystems сюда
# не подходит — она для дискретных нажатий, не для аналоговых осей).
#
# Направление считается camera-relative (сплющенное по Y) — GTA-стиль:
# A/D чистый стрейф, разворот персонажа лицом по движению делает сам
# player.gd в _apply_direct_movement(). Этот компонент только считает
# вектор направления и передаёт его игроку — никакой физики/анимации
# здесь нет, это не его ответственность.
# =============================================================================
extends Node
class_name TPSMovementSystem

var player_node: CharacterBody3D
var camera: Camera3D

var _is_active: bool = false


func _ready() -> void:
	PlayerState.mode_changed.connect(_on_player_state_changed)
	PlayerState.view_mode_changed.connect(_on_player_state_changed)
	_update_active_state()


func register_player(p: CharacterBody3D) -> void:
	player_node = p


func unregister_player() -> void:
	player_node = null


func register_camera(cam: Camera3D) -> void:
	camera = cam


func unregister_camera() -> void:
	camera = null


func _on_player_state_changed(_old, _new) -> void:
	_update_active_state()


func _update_active_state() -> void:
	_is_active = PlayerState.mode == PlayerState.Mode.ON_FOOT \
		and PlayerState.view_mode == PlayerState.ViewMode.TPS

	if not _is_active and player_node:
		# При выходе из TPS сразу гасим инпут, чтобы игрок не "доехал"
		# по инерции с зажатой клавишей в другой режим.
		player_node.set_direct_move_input(Vector3.ZERO, false)


func _physics_process(_delta: float) -> void:
	if not _is_active or not player_node or not camera:
		return

	var input_vec := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var want_run := Input.is_action_pressed("sprint")

	if input_vec.length() < 0.01:
		player_node.set_direct_move_input(Vector3.ZERO, want_run)
		return

	# camera-relative, сплющенное по Y — стандартный GTA/TPS паттерн
	var cam_basis := camera.global_transform.basis
	var forward := -cam_basis.z
	var right := cam_basis.x
	forward.y = 0.0
	right.y = 0.0
	forward = forward.normalized()
	right = right.normalized()

	var direction := (forward * -input_vec.y) + (right * input_vec.x)
	player_node.set_direct_move_input(direction, want_run)
