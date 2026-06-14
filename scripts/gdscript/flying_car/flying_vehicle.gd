extends InteractableObject
class_name FlyingCar

# ============================================================
# FLYING CAR — полная переработка на RigidBody + силы
#
# АРХИТЕКТУРА:
#   • Физика через apply_force() на 4 двигателях — Godot сам
#     считает torque из точки применения силы. Инерция бесплатно.
#   • PID-стабилизатор выравнивает roll/pitch когда нет ввода.
#   • Визуальный меш (CarMesh) наклоняется отдельно от коллизии.
#   • Сопла поворачиваются в направлении тяги — визуал = физика.
#
# ДЕРЕВО СЦЕНЫ (обязательно):
#   FlyingCar (RigidBody3D)
#   ├── CollisionShape3D
#   ├── Area (Area3D — зона посадки)
#   ├── SeatPosition (Marker3D)
#   └── CarMesh (Node3D — визуальный меш)
#       ├── Thrusters
#       │   ├── FL (Node3D — передний левый)
#       │   ├── FR (Node3D — передний правый)
#       │   ├── BL (Node3D — задний левый)
#       │   └── BR (Node3D — задний правый)
#       └── [меши, огни, эффекты]
# ============================================================

@onready var enter_area:    Area3D   = $Area
@onready var seat_position: Marker3D = $SeatPosition
@onready var car_mesh:      Node3D   = $CarMesh

# Четыре двигателя — их global_position = точка применения силы
@onready var thruster_fl: Node3D = $CarMesh/Thrusters/FL
@onready var thruster_fr: Node3D = $CarMesh/Thrusters/FR
@onready var thruster_bl: Node3D = $CarMesh/Thrusters/BL
@onready var thruster_br: Node3D = $CarMesh/Thrusters/BR

# ============================================================
# СОСТОЯНИЕ ДВИГАТЕЛЯ
# ============================================================
enum EngineState { OFF, STARTING, RUNNING }
var engine_state: EngineState = EngineState.OFF

var is_occupied:            bool = false
var _player_original_parent: Node = null
var _input_manager:         InputManager = null
var _camera_controller                   = null

# ============================================================
# ПАРАМЕТРЫ ТЯГИ (экспорт для настройки в инспекторе)
# ============================================================
@export_group("Thrust")
# Базовая вертикальная тяга одного двигателя для hover.
# Hover = масса * gravity / 4. При mass=500, gravity=9.8 → ~1225 на двигатель.
# Ставь чуть больше чтобы машина могла подниматься без ввода.
@export var hover_thrust:       float = 1225.0

# Дополнительная тяга при нажатии Space/Crouch (вверх/вниз)
@export var vertical_thrust:    float = 1200.0

# Горизонтальная тяга (вперёд/назад/стрейф)
# Применяется через наклон сопел — чем больше угол, тем больше горизонт. компонент
@export var horizontal_thrust:  float = 10500.0

# Максимальный угол наклона сопел (градусы).
# 30° даёт хороший баланс между скоростью и стабильностью.
@export var max_thruster_angle: float = 30.0

# Скорость поворота сопел (lerp). 8.0 = быстрый отклик.
@export var thruster_tilt_speed: float = 8.0

# ============================================================
# ПАРАМЕТРЫ ПОВОРОТА
# ============================================================
@export_group("Rotation")
# Крутящий момент для рыскания (yaw). apply_torque по Y.
@export var yaw_torque:   float = 400.0

# Максимальная угловая скорость по Y (рад/с).
# Без ограничения машина будет бесконечно разгоняться.
@export var max_yaw_speed: float = 2.0

@export_group("Flight Dynamics")
@export var max_speed_kmh: float = 120.0
@export var air_drag: float = 0.05      # Чем выше, тем быстрее машина "вянет" при отпускании W
@export var tilt_responsiveness: float = 25.0 # Ускоряем наклон

# ============================================================
# PID СТАБИЛИЗАТОР
# ============================================================
@export_group("PID Stabilizer")
# PID выравнивает roll и pitch к нулю когда нет активного ввода.
# P — пропорциональный коэффициент (основная сила возврата)
# D — дифференциальный (гасит колебания, как демпфер)
# I — интегральный (убирает статическую ошибку, обычно мал)

@export var pid_p: float = 6.0   # Сила возврата к горизонту
@export var pid_d: float = 4.0   # Демпфирование (убирает осцилляции)
@export var pid_i: float = 0.1   # Интегральный (можно оставить 0)

# Угол (радианы) при котором стабилизатор активен.
# Если наклон меньше этого — стабилизатор не мешает управлению.
@export var stabilizer_deadzone: float = 0.05

# ============================================================
# ВИЗУАЛЬНЫЕ НАКЛОНЫ МЕША
# ============================================================
@export_group("Mesh Tilt")
# Эти наклоны только визуальные — применяются к CarMesh, не к коллизии.
# Физика при этом остаётся стабильной.
@export var tilt_pitch_forward: float = 6.0   # нос вниз при движении вперёд
@export var tilt_pitch_brake:   float = 5.0   # нос вверх при торможении
@export var tilt_roll_strafe:   float = 10.0  # крен при стрейфе
@export var tilt_speed:         float = 80.0   # скорость lerp наклонов

# ============================================================
# IDLE DRIFT (покачивание на холостых)
# ============================================================
@export_group("Idle Drift")
@export var drift_amplitude:  float = 1.2   # градусы покачивания
@export var drift_frequency:  float = 0.4   # скорость покачивания
@export var drift_idle_time:  float = 1.5   # задержка перед началом

# ============================================================
# ЗАВОДКА
# ============================================================
@export_group("Engine Start")
# При заводке применяем увеличенную тягу в течение lift_duration секунд.
# Это даёт визуальный подъём от земли перед переходом в hover.
@export var lift_thrust_multiplier: float = 1.8  # тяга × 1.8 при старте
@export var lift_duration:          float = 0.8  # секунд

# ============================================================
# ВНУТРЕННИЕ ПЕРЕМЕННЫЕ
# ============================================================

# Таймер фазы заводки
var _lift_timer: float = 0.0

# Текущие углы наклона меша (для lerp)
var _mesh_pitch: float = 0.0
var _mesh_roll:  float = 0.0

# Idle drift
var _idle_timer:    float = 0.0
var _drift_time:    float = 0.0
var _drift_phase_x: float = randf_range(0.0, TAU)
var _drift_phase_z: float = randf_range(0.0, TAU)

# PID — накопленные ошибки (для I-компонента)
var _pid_integral_roll:  float = 0.0
var _pid_integral_pitch: float = 0.0

# Предыдущие ошибки (для D-компонента)
var _pid_prev_roll:  float = 0.0
var _pid_prev_pitch: float = 0.0

# Кешированный ввод (заполняется из receive_input каждый кадр)
var _input_forward:  float = 0.0
var _input_strafe:   float = 0.0
var _input_vertical: float = 0.0
var _input_turn:     float = 0.0
var _input_exit:     bool  = false
var _input_shutdown: bool  = false
var _input_engine_start: bool = false

# ============================================================
# ИНИЦИАЛИЗАЦИЯ
# ============================================================
func _ready() -> void:
	super._ready()
	gravity_scale = 0.0   # ВЫКЛЮЧАЕМ встроенную гравитацию полностью
	can_sleep     = false
	freeze        = false
	linear_damp = 0.1   # Немного сопротивления среды
	angular_damp = 2.0  # Немного стабилизации вращения
	interaction_type         = InteractionType.VEHICLE
	name_interactable_object = "Летающий автомобиль"
	can_throw        = false
	can_use_in_hands = false
	collision_layer  = 1
	collision_mask   = 1

func setup_references(input_mgr: InputManager, cam_ctrl) -> void:
	_input_manager    = input_mgr
	_camera_controller = cam_ctrl

# ============================================================
# ГЛАВНЫЙ ФИЗИЧЕСКИЙ ЦИКЛ
# Весь расчёт сил здесь — InputManager только пишет в _input_*
# ============================================================
func _physics_process(delta: float) -> void:
	if not is_occupied:
		return
	
	match engine_state:
		EngineState.OFF:
			_process_engine_off(delta)
		EngineState.STARTING:
			_process_engine_starting(delta)
		EngineState.RUNNING:
			_process_engine_running(delta)
			

# ============================================================
# СОСТОЯНИЕ: ДВИГАТЕЛЬ ВЫКЛЮЧЕН
# Машина падает под гравитацией — двигатели не работают.
# Ждём нажатия W для заводки.
# ============================================================
func _process_engine_off(_delta: float) -> void:
	# Проверяем запрос заводки (пришёл из receive_input)
	if _input_engine_start:
		_input_engine_start = false
		_start_engine()

# ============================================================
# СОСТОЯНИЕ: ЗАВОДКА
# Увеличенная тяга подбрасывает машину вверх.
# После lift_duration секунд переходим в RUNNING.
# ============================================================
func _process_engine_starting(delta: float) -> void:
	_lift_timer -= delta

	# Применяем усиленную вертикальную тягу от всех двигателей
	var lift_force = Vector3.UP * hover_thrust * lift_thrust_multiplier
	_apply_thruster_force(thruster_fl, lift_force)
	_apply_thruster_force(thruster_fr, lift_force)
	_apply_thruster_force(thruster_bl, lift_force)
	_apply_thruster_force(thruster_br, lift_force)

	## Мягко выравниваем машину во время заводки
	_apply_pid_stabilization(delta, 0.0, 0.0)

	if _lift_timer <= 0.0:
		engine_state = EngineState.RUNNING
		apply_central_force(global_transform.basis.z * -5000.0)
	print("🚗 Двигатель запущен — переход в RUNNING")

# ============================================================
# СОСТОЯНИЕ: РАБОТА
# Основной цикл: hover + управление + стабилизация
# ============================================================
func _process_engine_running(delta: float) -> void:
	# ── 1. ПРОВЕРКИ ──────────────────────────────────────────
	if _input_exit:
		_input_exit = false
		_exit_vehicle()
		return

	if _input_shutdown:
		_input_shutdown = false
		_try_shutdown()

	# ── 2. НАСТРОЙКИ (ОЧЕНЬ ВАЖНО) ──────────────────────────
	# Drag 0.05 - это "почти вакуум". Машина будет долго лететь по инерции.
	# Попробуй от 0.02 до 0.1.
	var drag_coeff = 0.05 
	var max_speed_ms = 120.0 / 3.6 
	
	# Раздельная тяга: Вперед мощнее, чем вбок. Это дает ощущение "двигателей".
	var forward_thrust_force = horizontal_thrust * 2.0 
	var strafe_thrust_force = horizontal_thrust * 0.8
	
	# ── 3. ГРАВИТАЦИЯ И HOVER ──────────────────────────────
	# Вес машины (тянем вниз) и компенсирующая сила (вверх)
	var gravity_force = mass * 9.8
	apply_central_force(Vector3.DOWN * gravity_force)
	apply_central_force(Vector3.UP * gravity_force)

	# ── 4. ВЕРТИКАЛЬНАЯ ТЯГА ──────────────────────────────
	apply_central_force(Vector3.UP * _input_vertical * vertical_thrust)

	# ── 5. ГОРИЗОНТАЛЬНОЕ ДВИЖЕНИЕ (С РАЗГОНОМ) ──────────
	# Не нормализуем, а применяем отдельно, чтобы набрать скорость "честно"
	var forward_vec = -global_transform.basis.z # Вперед
	var strafe_vec = global_transform.basis.x   # Вбок
	
	# Считаем текущую скорость в направлении движения
	var current_vel = linear_velocity
	var speed_limit_factor = clamp(1.0 - (current_vel.length() / max_speed_ms), 0.0, 1.0)
	
	# Применяем силы раздельно
	apply_central_force(forward_vec * _input_forward * forward_thrust_force * speed_limit_factor)
	apply_central_force(strafe_vec * _input_strafe * strafe_thrust_force * speed_limit_factor)

	# ── 6. ИНЕРЦИЯ (Drag) ──────────────────────────────────
	# Применяем сопротивление только к линейной скорости
	apply_central_force(-linear_velocity * drag_coeff * mass)

	# ── 7. ПОВОРОТ (YAW) ──────────────────────────────────
	if abs(_input_turn) > 0.01:
		apply_torque(global_transform.basis.y * _input_turn * yaw_torque)

	# ── 8. СТАБИЛИЗАЦИЯ И ВИЗУАЛ ──────────────────────────
	_apply_pid_stabilization(delta, 0.0, 0.0)
	
	_update_mesh_tilt(delta)
	_update_idle_drift(delta)
	_update_thruster_visuals(delta)

# ============================================================
# ПРИМЕНЕНИЕ СИЛЫ ОТ ДВИГАТЕЛЯ
# apply_force(force, position) где position — offset от центра масс.
# Godot автоматически считает torque = cross(position, force).
# ============================================================
func _apply_thruster_force(thruster: Node3D, force: Vector3) -> void:
	if not thruster:
		return
	# Offset двигателя от центра масс машины
	var offset = thruster.global_position - global_position
	apply_force(force, offset)

# ============================================================
# PID СТАБИЛИЗАТОР
# Выравнивает машину к desired_pitch / desired_roll.
# Работает через apply_torque — не меняет позицию напрямую.
# ============================================================
func _apply_pid_stabilization(delta: float, desired_pitch: float, desired_roll: float) -> void:
	# Текущие углы наклона в локальных координатах
	# basis.x — правый вектор, basis.z — передний вектор машины
	# Проецируем вектор UP мира на локальные оси чтобы получить реальный наклон
	var world_up    = Vector3.UP
	var local_up    = global_transform.basis.inverse() * world_up

	# roll  = отклонение от вертикали по оси X (крен влево/вправо)
	# pitch = отклонение от вертикали по оси Z (наклон вперёд/назад)
	var current_roll  = -local_up.x  # знак: + = крен вправо
	var current_pitch =  local_up.z  # знак: + = нос вверх

	# Ошибки относительно желаемых углов
	var error_roll  = desired_roll  - current_roll
	var error_pitch = desired_pitch - current_pitch

	# Мёртвая зона — не корректируем если отклонение мало
	if abs(error_roll)  < stabilizer_deadzone: error_roll  = 0.0
	if abs(error_pitch) < stabilizer_deadzone: error_pitch = 0.0

	# I-компонент (накопленная ошибка)
	_pid_integral_roll  += error_roll  * delta
	_pid_integral_pitch += error_pitch * delta

	# Ограничиваем интегральную часть чтобы избежать windup
	_pid_integral_roll  = clamp(_pid_integral_roll,  -1.0, 1.0)
	_pid_integral_pitch = clamp(_pid_integral_pitch, -1.0, 1.0)

	# D-компонент (скорость изменения ошибки)
	var d_roll  = (error_roll  - _pid_prev_roll)  / max(delta, 0.001)
	var d_pitch = (error_pitch - _pid_prev_pitch) / max(delta, 0.001)

	_pid_prev_roll  = error_roll
	_pid_prev_pitch = error_pitch

	# PID формула: P*error + I*integral + D*derivative
	var torque_roll  = pid_p * error_roll  + pid_i * _pid_integral_roll  + pid_d * d_roll
	var torque_pitch = pid_p * error_pitch + pid_i * _pid_integral_pitch + pid_d * d_pitch

	# Применяем корректирующий момент
	# X-ось машины управляет roll, Z-ось управляет pitch
	var correction = global_transform.basis.x * torque_roll + \
					 global_transform.basis.z * torque_pitch
	apply_torque(correction)

# ============================================================
# ВИЗУАЛЬНЫЙ НАКЛОН МЕША
# Только CarMesh наклоняется — коллизия остаётся стабильной.
# Даёт ощущение тяжёлой машины без нарушения физики.
# ============================================================
func _update_mesh_tilt(delta: float) -> void:
	if not car_mesh:
		return

	var vel_local   = global_transform.basis.inverse() * linear_velocity
	var forward_vel = -vel_local.z

	# Pitch
	var target_pitch: float
	if _input_forward > 0.01 and forward_vel > 0.5:
		target_pitch = deg_to_rad(-tilt_pitch_forward)
	elif _input_forward < -0.01:
		target_pitch = deg_to_rad(tilt_pitch_brake)
	else:
		target_pitch = 0.0

	# Roll = стрейф + ПОВОРОТ Q/E (только меш, не сопла)
	var strafe_roll = -vel_local.x / max(abs(vel_local.x) + 1.0, 1.0) * tilt_roll_strafe
	var turn_roll   = _input_turn * 8.0  # крен в сторону поворота

	var target_roll = deg_to_rad(strafe_roll + turn_roll)

	_mesh_pitch = lerp(_mesh_pitch, target_pitch, tilt_speed * delta)
	_mesh_roll  = lerp(_mesh_roll,  target_roll,  tilt_speed * delta)

	car_mesh.rotation.x = _mesh_pitch
	car_mesh.rotation.z = _mesh_roll

# ============================================================
# IDLE DRIFT — органичное покачивание на холостых
# ============================================================
func _update_idle_drift(delta: float) -> void:
	if not car_mesh:
		return

	_idle_timer += delta

	if _idle_timer < drift_idle_time:
		_drift_time = 0.0
		return

	_drift_time += delta

	# Разные частоты по осям — не синхронное покачивание
	var dx = sin(_drift_time * drift_frequency       + _drift_phase_x) * deg_to_rad(drift_amplitude)
	var dz = sin(_drift_time * drift_frequency * 1.3 + _drift_phase_z) * deg_to_rad(drift_amplitude * 0.7)
	var dy = sin(_drift_time * drift_frequency * 0.7)                  * deg_to_rad(drift_amplitude * 0.4)

	# Накладываем поверх текущих наклонов от tilt
	car_mesh.rotation.x = _mesh_pitch + dx
	car_mesh.rotation.z = _mesh_roll  + dz
	car_mesh.rotation.y = dy

# ============================================================
# АНИМАЦИЯ СОПЕЛ
# Угол поворота сопла = вектор тяги в этом направлении.
# Визуал синхронизирован с физикой: куда смотрит сопло — туда тяга.
# ============================================================
func _update_thruster_visuals(delta: float) -> void:
	var max_rad = deg_to_rad(max_thruster_angle)

	# Сопла — только forward/strafe, поворот НЕ влияет
	var target_x = -_input_forward * max_rad
	var target_z = -_input_strafe  * max_rad

	for t in [thruster_fl, thruster_fr, thruster_bl, thruster_br]:
		if t:
			t.rotation.x = lerp(t.rotation.x, target_x, thruster_tilt_speed * delta)
			t.rotation.z = lerp(t.rotation.z, target_z, thruster_tilt_speed * delta)

# ============================================================
# ЗАВОДКА
# ============================================================
func _start_engine() -> void:
	engine_state = EngineState.STARTING
	_lift_timer  = lift_duration
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	# Сбрасываем PID чтобы не было рывка при старте
	_pid_integral_roll  = 0.0
	_pid_integral_pitch = 0.0
	_pid_prev_roll      = 0.0
	_pid_prev_pitch     = 0.0
	print("🚗 Заводка — подъём %.1f сек" % lift_duration)

# ============================================================
# ГЛУШЕНИЕ
# Проверяем что под машиной есть пол и горизонтальная скорость мала.
# ============================================================
func _try_shutdown() -> void:
	var space = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		global_position,
		global_position + Vector3.DOWN * 1.5
	)
	query.exclude = [self]
	var result = space.intersect_ray(query)

	if result and result.collider.is_in_group("floor"):
		var h_speed = Vector2(linear_velocity.x, linear_velocity.z).length()
		if h_speed < 1.5:
			engine_state        = EngineState.OFF
			linear_velocity     = Vector3.ZERO
			angular_velocity    = Vector3.ZERO
			print("🚗 Двигатель заглушен")

# ============================================================
# ПРИЁМ ВВОДА ОТ InputManager
# InputManager вызывает этот метод каждый кадр из _physics_process.
# Мы только пишем во внутренние переменные — физика считается выше.
# ============================================================
func receive_input(input: Dictionary, _delta: float) -> void:
	if engine_state == EngineState.OFF:
		if input.get("engine_start", false):
			_input_engine_start = true
		return

	if engine_state == EngineState.STARTING:
		return

	_input_forward  = input.get("forward",  0.0)
	_input_strafe   = input.get("strafe",   0.0)
	_input_vertical = input.get("vertical", 0.0)
	_input_turn     = input.get("turn",     0.0)
	_input_exit     = input.get("exit",     false)
	_input_shutdown = input.get("shutdown", false)

# ============================================================
# ПОСАДКА
# ============================================================
func enter_vehicle(player: CharacterBody3D) -> void:
	is_occupied             = true
	_player_original_parent = player.get_parent()

	player.call_deferred("reparent", self)
	await get_tree().process_frame

	player.position = seat_position.position if seat_position else Vector3.ZERO
	player.set_movement_enabled(false)
	player.visible = false

	if _camera_controller:
		_camera_controller.enter_vehicle_mode(self)

	on_player_entered_vehicle()
	print("🚗 Игрок сел | Жми W для заводки")

# ============================================================
# ВЫСАДКА
# ============================================================
func _exit_vehicle() -> void:
	if not _input_manager or not _player_original_parent:
		return

	var player       = _input_manager.player_node
	is_occupied      = false
	engine_state     = EngineState.OFF
	linear_velocity  = Vector3.ZERO
	angular_velocity = Vector3.ZERO

	# Выходим сбоку от машины
	var exit_pos = global_position + global_transform.basis.x * 2.5
	player.call_deferred("reparent", _player_original_parent)
	await get_tree().process_frame

	player.global_position = exit_pos
	player.visible         = true
	player.set_movement_enabled(true)

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
