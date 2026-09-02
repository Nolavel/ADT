# =============================================================================
# tps_movement_system.gd — обычная нода.
#
# Владелец: world.gd — создаёт через .new() (WORLD_SYSTEM_SCRIPTS) и отдаёт
# player/camera через on_world_ready().
#
# Активен ТОЛЬКО когда PlayerState.mode == ON_FOOT — сам себя гейтит через
# PlayerState.mode_changed. Раньше в гейте была ещё и половина про
# view_mode == TPS; она ушла вместе с изометрической камерой 2026-09-02:
# оба оставшихся view_mode — одна и та же камера от третьего лица, так что
# WASD там управление в любом случае. Парная система, ClickToMoveSystem,
# удалена тем же коммитом.
#
# WASD/Shift — непрерывный held-инпут, поэтому сигнальная модель не
# подходит (она для дискретных нажатий, не для аналоговых осей). Физически
# Input.get_vector()/is_action_pressed() теперь вызываются только внутри
# InputSystems (get_move_axis()/is_sprint_held()) — этот компонент лишь
# зовёт готовые query-методы, сам Input напрямую не читает.
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
	_update_active_state()


## Единая точка входа для world.gd (см. WORLD_SYSTEM_SCRIPTS) — вместо
## ручных register_player()/register_camera() по месту.
func on_world_ready(context: WorldContext) -> void:
	register_player(context.player)
	register_camera(context.camera)


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
	## ON_FOOT is the whole gate now. The view_mode half went with the
	## isometric camera on 2026-09-02: both remaining view modes are the
	## same third-person camera with a different lens shift, so WASD is the
	## input in either of them and there is nothing left to switch on.
	_is_active = PlayerState.mode == PlayerState.Mode.ON_FOOT

	if not _is_active and player_node:
		# При выходе из ON_FOOT сразу гасим инпут, чтобы игрок не "доехал"
		# по инерции с зажатой клавишей в другой режим.
		player_node.set_direct_move_input(Vector3.ZERO, false)
		PlayerState.set_aiming(false)


func _physics_process(_delta: float) -> void:
	if not _is_active or not player_node or not camera:
		return

	player_node.set_camera_yaw(camera.global_rotation.y)

	# Aim is a hold, independent of the move axis below — evaluated even
	# while standing still, unlike the early-out on zero input further down.
	PlayerState.set_aiming(InputSystems.is_aim_pressed())

	var input_vec := InputSystems.get_move_axis()
	var want_run := InputSystems.is_sprint_held()

	if input_vec.length() < 0.01:
		player_node.set_direct_move_input(Vector3.ZERO, want_run)
		return

	# camera-relative, flattened to Y — standard GTA/TPS pattern
	var cam_basis := camera.global_transform.basis
	var forward := -cam_basis.z
	var right := cam_basis.x
	forward.y = 0.0
	right.y = 0.0
	forward = forward.normalized()
	right = right.normalized()

	var direction := (forward * -input_vec.y) + (right * input_vec.x)
	player_node.set_direct_move_input(direction, want_run)
