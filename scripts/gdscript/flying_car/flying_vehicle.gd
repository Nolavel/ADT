extends InteractableObject
class_name FlyingCar

@onready var enter_area: Area3D = $Area
@onready var seat_position: Marker3D = $SeatPosition

# === СОСТОЯНИЕ ДВИГАТЕЛЯ ===
enum EngineState { OFF, STARTING, RUNNING }
var engine_state: EngineState = EngineState.OFF

# === СОСТОЯНИЕ МАШИНЫ ===
var is_occupied: bool = false
var _player_original_parent: Node = null

# === ПАРАМЕТРЫ ПОЛЁТА ===
@export_group("Speed")
@export var forward_max_speed: float = 20.0
@export var backward_max_speed: float = 7.0
@export var strafe_max_speed: float = 12.0
@export var vertical_max_speed: float = 8.0
@export var acceleration: float = 6.0
@export var drag: float = 3.5          # торможение после отпускания
@export var rotation_speed: float = 1.8

# === НАКЛОНЫ МЕША ===
@export_group("Tilt")
@export var pitch_forward: float = 5.0   # нос вниз при движении вперёд
@export var pitch_brake: float = 7.0     # нос вверх при торможении
@export var roll_strafe: float = 10.0    # крен при стрейфе
@export var roll_turn: float = 8.0       # крен при повороте Q/E
@export var tilt_speed: float = 5.0      # скорость lerp наклонов

# === ДРЕЙФ НА ХОЛОСТЫХ ===
@export_group("Idle Drift")
@export var drift_amplitude: float = 1.2
@export var drift_frequency: float = 0.4
@export var drift_idle_time: float = 1.5  # через сколько секунд начинается

# === ЗАВОДКА ===
@export_group("Engine")
@export var start_lift_height: float = 0.4
@export var start_lift_duration: float = 0.6
@export var floor_check_distance: float = 1.2  # raycast вниз для глушения

# === ВНУТРЕННИЕ ПЕРЕМЕННЫЕ ===
var current_velocity: Vector3 = Vector3.ZERO
var _input_manager: InputManager = null
var _camera_controller = null

# Наклоны — цели и текущие
var target_pitch: float = 0.0
var target_roll: float = 0.0
var current_pitch: float = 0.0
var current_roll: float = 0.0

# Дрейф
var idle_timer: float = 0.0
var drift_time: float = 0.0
var drift_offset_x: float = randf()   # уникальная фаза для каждой машины
var drift_offset_z: float = randf()

# Backward покачивание хвоста
var backward_timer: float = 0.0
var tail_swing_angle: float = 0.0

var lift_timer: float = 0.0
var lift_duration: float = 0.6

# Меш — отдельный узел для визуальных наклонов
@onready var car_mesh: Node3D = $CarMesh  # меш машины, не коллизия

func _ready() -> void:
	super._ready()

	gravity_scale = 0.0
	freeze = false
	can_sleep = false
	interaction_type = InteractionType.VEHICLE
	name_interactable_object = "Летающий автомобиль"
	can_throw = false
	can_use_in_hands = false
	collision_layer = 1
	collision_mask  = 1

func setup_references(input_mgr: InputManager, cam_ctrl) -> void:
	_input_manager = input_mgr
	_camera_controller = cam_ctrl

# ============================================
# ГЛАВНЫЙ ЦИКЛ
# ============================================
func _physics_process(delta: float) -> void:
	if not is_occupied:
		return

	if engine_state == EngineState.STARTING:
		lift_timer -= delta
		linear_velocity.y = 4.0

		if lift_timer <= 0.0:
			engine_state = EngineState.RUNNING
			linear_velocity.y = 0.0

		return

	if engine_state == EngineState.RUNNING:
		return

	if engine_state == EngineState.OFF:
		linear_velocity.y -= 20.0 * delta
		linear_velocity.y = maxf(linear_velocity.y, -20.0)

	return
		


# ============================================
# ЗАВОДКА
# ============================================
func _handle_engine_start() -> void:
	if Input.is_action_just_pressed("move_forward") or Input.is_action_just_pressed("ui_up"):
		engine_state = EngineState.STARTING
		_start_engine_lift()

func _start_engine_lift() -> void:
	lift_timer = lift_duration
	linear_velocity = Vector3.ZERO
	engine_state = EngineState.STARTING  # ← STARTING, не RUNNING
	print("🚗 Двигатель запущен")

# ============================================
# ГЛУШЕНИЕ
# ============================================
func _handle_shutdown(delta: float) -> void:
	if not Input.is_action_just_pressed("crouch"):
		return

	# Проверяем floor под машиной
	var space = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		global_position,
		global_position + Vector3.DOWN * floor_check_distance
	)
	query.exclude = [self]
	var result = space.intersect_ray(query)

	if result and result.collider.is_in_group("floor"):
		var h_speed = Vector2(linear_velocity.x, linear_velocity.z).length()
		if h_speed < 1.5:
			_shutdown_engine()
			
func _try_shutdown() -> void:
	var space = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		global_position,
		global_position + Vector3.DOWN * floor_check_distance
	)
	query.exclude = [self]
	var result = space.intersect_ray(query)
	if result and result.collider.is_in_group("floor"):
		var h_speed = Vector2(linear_velocity.x, linear_velocity.z).length()
		if h_speed < 1.5:
			engine_state = EngineState.OFF
			linear_velocity = Vector3.ZERO
			print("🚗 Двигатель заглушен")

func _shutdown_engine() -> void:
	engine_state = EngineState.OFF
	linear_velocity= Vector3.ZERO
	print("🚗 Двигатель заглушен")

# ============================================
# УПРАВЛЕНИЕ В ПОЛЁТЕ
# ============================================
func receive_input(input: Dictionary, delta: float) -> void:
	if engine_state == EngineState.OFF or engine_state == EngineState.STARTING:
		return  # просто ждём пока заведётся

	if engine_state != EngineState.RUNNING:
		return

	var input_forward: float = input.get("forward", 0.0)
	var input_strafe: float  = input.get("strafe", 0.0)
	var input_vertical: float = input.get("vertical", 0.0)
	var input_turn: float    = input.get("turn", 0.0)

	# Выход
	if input.get("exit", false):
		_exit_vehicle()
		return

	# Глушение
	if input.get("shutdown", false):
		_try_shutdown()

	# Поворот
	rotation.y += input_turn * rotation_speed * delta

	var max_fwd = forward_max_speed if input_forward > 0 else backward_max_speed
	var local_target = Vector3(
		input_strafe * strafe_max_speed,
		input_vertical * vertical_max_speed,
		-input_forward * max_fwd
	)
	var world_h = global_transform.basis * Vector3(local_target.x, 0, local_target.z)
	var world_target = Vector3(world_h.x, local_target.y, world_h.z)

	var has_horizontal = abs(input_forward) > 0.01 or abs(input_strafe) > 0.01
	var has_vertical   = abs(input_vertical) > 0.01

	if has_horizontal:
		linear_velocity.x = move_toward(linear_velocity.x, world_target.x, acceleration * delta)
		linear_velocity.z = move_toward(linear_velocity.z, world_target.z, acceleration * delta)
	else:
		linear_velocity.x = move_toward(linear_velocity.x, 0.0, drag * delta)
		linear_velocity.z = move_toward(linear_velocity.z, 0.0, drag * delta)

	if has_vertical:
		linear_velocity.y = move_toward(linear_velocity.y, world_target.y, acceleration * delta)
	else:
	# Жёсткий hover — гасим вертикальную скорость быстро
		linear_velocity.y = move_toward(linear_velocity.y, 0.0, 15.0 * delta)

	# Покачивание хвоста назад
	if input_forward < -0.01:
		backward_timer += delta
		if backward_timer > 1.0:
			tail_swing_angle = sin(backward_timer * 1.8) * deg_to_rad(5.0)
			rotation.y += tail_swing_angle * delta
	else:
		backward_timer = 0.0
		tail_swing_angle = 0.0

	if has_horizontal or has_vertical or abs(input_turn) > 0.01:
		idle_timer = 0.0

	_update_tilt(delta)
	_update_idle_drift(delta)
	print("RUNNING")
	print(linear_velocity)

# ============================================
# НАКЛОНЫ МЕША
# ============================================
func _update_tilt(delta: float) -> void:
	if not car_mesh:
		return

	var vel_local = global_transform.basis.inverse() * linear_velocity
	var forward_vel = -vel_local.z  # положительный = движение вперёд

	# Pitch — нос вниз при движении, вверх при торможении
	var pitch_input = Input.is_action_pressed("move_forward") or Input.is_action_pressed("ui_up")
	var brake_input = Input.is_action_pressed("move_backward") or Input.is_action_pressed("ui_down")

	if pitch_input and forward_vel > 0.5:
		target_pitch = deg_to_rad(-pitch_forward)   # нос вниз
	elif brake_input or (forward_vel > 2.0 and not pitch_input):
		target_pitch = deg_to_rad(pitch_brake)      # нос вверх при торможении
	else:
		target_pitch = 0.0

	# Roll — крен при стрейфе и повороте
	var strafe_vel = vel_local.x
	var turn_input = 0.0
	if Input.is_action_pressed("lean_left"):
		turn_input = 1.0
	elif Input.is_action_pressed("lean_right"):
		turn_input = -1.0

	target_roll = deg_to_rad(-strafe_vel / strafe_max_speed * roll_strafe)
	target_roll += deg_to_rad(turn_input * roll_turn)

	# Применяем через lerp — только к мешу, не к коллизии
	current_pitch = lerp(current_pitch, target_pitch, tilt_speed * delta)
	current_roll = lerp(current_roll, target_roll, tilt_speed * delta)

	car_mesh.rotation.x = current_pitch
	car_mesh.rotation.z = current_roll

# ============================================
# ДРЕЙФ НА ХОЛОСТЫХ
# ============================================
func _update_idle_drift(delta: float) -> void:
	if not car_mesh:
		return

	idle_timer += delta

	if idle_timer < drift_idle_time:
		# Возврат к нейтрали если недавно двигались
		drift_time = 0.0
		return

	drift_time += delta

	# Разные частоты по осям — органичное покачивание
	var drift_x = sin(drift_time * drift_frequency + drift_offset_x) * deg_to_rad(drift_amplitude)
	var drift_z = sin(drift_time * drift_frequency * 1.3 + drift_offset_z) * deg_to_rad(drift_amplitude * 0.7)
	var drift_y = sin(drift_time * drift_frequency * 0.7) * deg_to_rad(drift_amplitude * 0.5)

	# Накладываем поверх текущих наклонов
	car_mesh.rotation.x = current_pitch + drift_x
	car_mesh.rotation.z = current_roll + drift_z
	car_mesh.rotation.y = drift_y

# ============================================
# ПОСАДКА / ВЫСАДКА
# ============================================
func enter_vehicle(player: CharacterBody3D) -> void:
	is_occupied = true
	_player_original_parent = player.get_parent()

	player.call_deferred("reparent", self)
	await get_tree().process_frame

	if seat_position:
		player.position = seat_position.position
	else:
		player.position = Vector3.ZERO

	player.set_movement_enabled(false)
	player.visible = false

	if _camera_controller:
		_camera_controller.enter_vehicle_mode(self)

	on_player_entered_vehicle()

	# Сразу заводим — не ждём W
	_start_engine_lift()
	print("🚗 Игрок сел — двигатель заводится")

func _exit_vehicle() -> void:
	if not _input_manager or not _player_original_parent:
		return

	var player = _input_manager.player_node
	is_occupied = false

	var exit_world_pos = global_position + global_transform.basis.x * 2.5
	player.call_deferred("reparent", _player_original_parent)
	await get_tree().process_frame

	player.global_position = exit_world_pos
	player.visible = true
	player.set_movement_enabled(true)
	engine_state = EngineState.OFF
	linear_velocity = Vector3.ZERO

	# Сообщаем InputManager что вышли
	_input_manager.on_exit_vehicle()

	if _camera_controller:
		_camera_controller.exit_vehicle_mode()

	on_player_exited_vehicle()
	print("🚗 Игрок вышел")

func on_player_entered_vehicle() -> void:
	if enter_area:
		enter_area.monitoring  = false
		enter_area.monitorable = false

func on_player_exited_vehicle() -> void:
	if enter_area:
		enter_area.monitoring  = true
		enter_area.monitorable = true
		
		
func _has_vertical_input() -> bool:
	return Input.is_action_pressed("jump") or Input.is_action_pressed("crouch")
