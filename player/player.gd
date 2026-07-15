extends CharacterBody3D

## --- Movement Parameters ---
@export_group("Movement")
@export var walk_speed: float = 5.0
@export var run_speed: float = 10.0
@export var accel_time: float = 0.55
@export var decel_time: float = 0.8

@export_group("Jump/Gravity")
@export var jump_force: float = 8.0
@export var gravity: float = 20.0

@export_group("Animation")
@export var player_animation_player: AnimationPlayer

## --- Components ---
@onready var navigation_component: NavigationComponent = $NavComponent
@onready var stamina_manager: StaminaComponent = $StaminaComponent
@onready var animation_player: AnimationPlayer = $player_base_mesh/AnimationPlayer

## --- Movement State ---
enum MovementState { IDLE, WALKING, RUNNING, DECELERATING }
var current_state: MovementState = MovementState.IDLE
var speed: float = 0.0
var target_speed: float = 0.0
var movement_enabled: bool = true

## --- Direct movement (TPS, WASD) — кэш входных данных, пишет
## TPSMovementSystem каждый physics-кадр через set_direct_move_input().
## Сам velocity/анимацию/поворот считает player.gd, чтобы физика и
## стейт-машина оставались в одном месте, как и для клик-муфа.
var _direct_move_direction: Vector3 = Vector3.ZERO
var _direct_move_want_run: bool = false

## --- Sprint State (для UI курсора) ---
var is_running_mode: bool = false
var wants_to_run: bool = false  # 🔥 НОВЫЙ: игрок хочет бежать (даже если не может)
var sprint_blend: float = 0.0
var sprint_blend_speed: float = 4.0

## --- Animation Tree (программно собранный blend, без ручного .tres) ---
## Blend space по скорости даёт плавный переход шаг<->бег вместо
## резкого переключателя play(), синхронизирован с реальной speed,
## которая и так уже плавно едет через _update_speed()/accel_time.
var _anim_tree: AnimationTree
var _moving_blend_amount: float = 0.0  # 0 = idle, 1 = локомоция
const MOVE_BLEND_SPEED: float = 6.0
const IDLE_ENTER_SPEED: float = 0.15  # ниже этого — считаем, что стоим

## --- Signals ---
signal movement_started
signal movement_stopped
signal state_changed(new_state: MovementState)

## --- Initialization ---
func _ready():
	_setup_animation_tree()
	if navigation_component:
		navigation_component.path_updated.connect(_on_path_updated)
		navigation_component.destination_reached.connect(_on_destination_reached)
	else:
		push_warning("NavigationComponent not found - direct movement only")
	
	if stamina_manager == null:
		push_warning("StaminaManager not found - stamina system will not work")

## --- Animation Tree Setup ---
## Собирается полностью кодом: Blend2(idle <-> locomotion), где
## locomotion — BlendSpace1D(walk@0 .. run@1). Не требует ручного
## .tres/редакторной настройки, легко пересобрать при смене клипов.
func _setup_animation_tree() -> void:
	var idle_node := AnimationNodeAnimation.new()
	idle_node.animation = "new4/idle"

	var walk_node := AnimationNodeAnimation.new()
	walk_node.animation = "new4/root-sneak-walk"

	var run_node := AnimationNodeAnimation.new()
	run_node.animation = "new4/root-sneak-run-s"

	var locomotion := AnimationNodeBlendSpace1D.new()
	locomotion.min_space = 0.0
	locomotion.max_space = 1.0
	locomotion.add_blend_point(walk_node, 0.0)
	locomotion.add_blend_point(run_node, 1.0)

	var moving_blend := AnimationNodeBlend2.new()

	var tree_root := AnimationNodeBlendTree.new()
	tree_root.add_node("idle", idle_node)
	tree_root.add_node("locomotion", locomotion)
	tree_root.add_node("moving_blend", moving_blend)
	tree_root.connect_node("moving_blend", 0, "idle")
	tree_root.connect_node("moving_blend", 1, "locomotion")
	tree_root.connect_node("output", 0, "moving_blend")

	_anim_tree = AnimationTree.new()
	_anim_tree.tree_root = tree_root
	_anim_tree.anim_player = player_animation_player.get_path()
	add_child(_anim_tree)
	_anim_tree.active = true

## --- Public API ---
func move_to_position(pos: Vector3) -> void:
	if not movement_enabled:
		print("⚠️ Player: Движение заблокировано, игнорируем move_to_position()")
		return
	
	if navigation_component:
		navigation_component.set_target_position(pos)

func set_movement_speed(new_speed: float) -> void:
	if not movement_enabled:
		return
	
	target_speed = clamp(new_speed, 0.0, run_speed)
	
	# 🔥 Запоминаем, что игрок ХОЧЕТ бежать (даже если не может)
	wants_to_run = (new_speed > walk_speed * 1.1)
	
	# Определяем режим бега по скорости
	is_running_mode = wants_to_run
	
	_update_state()

## Вызывается TPSMovementSystem каждый _physics_process, пока активен TPS.
## direction — уже посчитанный, camera-relative, сплющенный по Y вектор
## (не обязательно нормализован — ноль-вектор значит "стоим на месте").
## Сама физика/анимация/поворот считаются здесь же, в player.gd — так же,
## как для клик-муфа их считает _handle_navigation.
func set_direct_move_input(direction: Vector3, want_run: bool) -> void:
	_direct_move_direction = direction
	_direct_move_want_run = want_run

func stop_moving(smooth: bool = true) -> void:
	if navigation_component:
		navigation_component.clear_path()
	
	is_running_mode = false
	wants_to_run = false 
	
	if smooth:
		target_speed = 0.0
		_change_state(MovementState.DECELERATING)
	else:
		target_speed = 0.0
		speed = 0.0
		_change_state(MovementState.IDLE)
	
	emit_signal("movement_stopped")

func is_moving() -> bool:
	return current_state != MovementState.IDLE

## СИСТЕМА БЛОКИРОВКИ ДВИЖЕНИЯ
func set_movement_enabled(enabled: bool):
	movement_enabled = enabled
	
	if not enabled:
		velocity = Vector3.ZERO
		speed = 0.0
		target_speed = 0.0
		is_running_mode = false
		wants_to_run = false  # 🔥
		
		if navigation_component:
			navigation_component.clear_path()
		
		if stamina_manager:
			stamina_manager.stop_consuming_stamina()
		
		if current_state != MovementState.IDLE:
			_change_state(MovementState.IDLE)
		
		print("🔒 Player: Движение ЗАБЛОКИРОВАНО")
	else:
		print("✅ Player: Движение РАЗБЛОКИРОВАНО")

func is_movement_enabled() -> bool:
	return movement_enabled

## === МЕТОДЫ ДЛЯ КУРСОРА (совместимость с MouseCursorUI) ===

## Проверяет, находится ли игрок в спринте (беге)
func is_currently_sprinting(current_velocity: Vector3) -> bool:
	if not movement_enabled:
		return false
	
	var horizontal_speed = Vector2(current_velocity.x, current_velocity.z).length()
	return is_running_mode and horizontal_speed > walk_speed * 1.2

## Возвращает прогресс спринта (0.0 - 1.0)
func get_sprint_blend() -> float:
	return sprint_blend

## Проверяет, хочет ли игрок бежать (независимо от стамины)
func is_wanting_to_run() -> bool:
	return wants_to_run

## --- Physics Update ---
func _physics_process(delta: float) -> void:
	if not movement_enabled:
		#_apply_gravity(delta)
		#move_and_slide()
		return
	
	_update_sprint_blend(delta)
	_handle_stamina_consumption()
	_handle_jump()
	_apply_gravity(delta)

	if PlayerState.view_mode == PlayerState.ViewMode.TPS:
		_update_direct_move_target_speed()

	_update_speed(delta)
	_update_animation_blend(delta)

	if PlayerState.view_mode == PlayerState.ViewMode.TPS:
		_apply_direct_movement(delta)
	else:
		_handle_navigation(delta)
		_apply_deceleration(delta)
	
	move_and_slide()

## --- Sprint Blend (для плавной UI анимации) ---
func _update_sprint_blend(delta: float) -> void:
	var target_blend = 1.0 if is_running_mode else 0.0
	sprint_blend = lerp(sprint_blend, target_blend, sprint_blend_speed * delta)

## --- Animation Blend (шаг<->бег, idle<->движение) ---
## Позиция в BlendSpace1D берётся из РЕАЛЬНОЙ speed (уже сглаженной
## через move_toward/accel_time в _update_speed), а не из is_running_mode —
## так анимация физически не может обогнать саму скорость персонажа,
## и истощение стамины визуально "садится" плавно, без рывка клипа.
func _update_animation_blend(delta: float) -> void:
	if not _anim_tree:
		return

	var locomotion_pos: float = 0.0
	if run_speed > walk_speed:
		locomotion_pos = clamp((speed - walk_speed) / (run_speed - walk_speed), 0.0, 1.0)
	_anim_tree.set("parameters/locomotion/blend_position", locomotion_pos)

	var target_moving: float = 1.0 if speed > IDLE_ENTER_SPEED else 0.0
	_moving_blend_amount = move_toward(_moving_blend_amount, target_moving, delta * MOVE_BLEND_SPEED)
	_anim_tree.set("parameters/moving_blend/blend_amount", _moving_blend_amount)

## --- Stamina Consumption (расход стамины при беге) ---
func _handle_stamina_consumption() -> void:
	if not stamina_manager:
		return
	
	var can_run = stamina_manager.is_sprint_allowed()
	
	if is_running_mode and is_moving():
		if can_run:
			if not stamina_manager.is_consuming_stamina:
				stamina_manager.start_consuming_stamina()
		else:
			## Стамина кончилась - принудительно переходим на ходьбу
			if stamina_manager.is_consuming_stamina:
				stamina_manager.stop_consuming_stamina()
			
			## Снижаем РЕАЛЬНУЮ скорость, но НЕ сбрасываем wants_to_run
			target_speed = walk_speed
			is_running_mode = false
			print("⚠️ Стамина истощена - переход на ходьбу")
	else:
		if stamina_manager.is_consuming_stamina:
			stamina_manager.stop_consuming_stamina()

## --- Jump Logic ---
func _handle_jump() -> void:
	if InputSystems.is_jump_just_pressed() and is_on_floor():
		if stamina_manager and stamina_manager.try_jump():
			velocity.y = jump_force
		elif not stamina_manager:
			velocity.y = jump_force

## --- Gravity ---
func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta

## --- Speed Interpolation ---
func _update_speed(delta: float) -> void:
	var acceleration = (run_speed - walk_speed) / accel_time
	speed = move_toward(speed, target_speed, delta * acceleration)

## --- Direct Movement (TPS, WASD) ---
## Считает целевую скорость ДО _update_speed(delta), чтобы бег/ходьба
## включались в том же кадре, а не с задержкой в один физ-тик.
func _update_direct_move_target_speed() -> void:
	var is_moving_input := _direct_move_direction.length() > 0.01

	if not is_moving_input:
		target_speed = 0.0
		is_running_mode = false
		wants_to_run = false
		return

	var can_run := stamina_manager == null or stamina_manager.is_sprint_allowed()
	var running := _direct_move_want_run and can_run

	wants_to_run = _direct_move_want_run
	is_running_mode = running
	target_speed = run_speed if running else walk_speed


## GTA-стиль: A/D — чистый стрейф относительно камеры, персонаж плавно
## разворачивается лицом по направлению суммарного вектора движения
## (тот же lerp_angle, что уже используется в _handle_navigation).
func _apply_direct_movement(delta: float) -> void:
	if _direct_move_direction.length() > 0.01:
		var dir := _direct_move_direction.normalized()
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed

		var target_facing := atan2(dir.x, dir.z)
		rotation.y = lerp_angle(rotation.y, target_facing, delta * 10.0)

		if current_state == MovementState.IDLE or current_state == MovementState.DECELERATING:
			_change_state(MovementState.RUNNING if is_running_mode else MovementState.WALKING)
		elif is_running_mode and current_state != MovementState.RUNNING:
			_change_state(MovementState.RUNNING)
		elif not is_running_mode and current_state != MovementState.WALKING:
			_change_state(MovementState.WALKING)
	else:
		# Инпута нет — тормозим тем же decel, что и клик-муф, чтобы ощущение
		# было единообразным между режимами.
		if speed > 0.1:
			var decel_rate = run_speed / decel_time
			velocity.x = move_toward(velocity.x, 0.0, delta * decel_rate)
			velocity.z = move_toward(velocity.z, 0.0, delta * decel_rate)
			if current_state != MovementState.DECELERATING:
				_change_state(MovementState.DECELERATING)
		else:
			velocity.x = 0.0
			velocity.z = 0.0
			if current_state != MovementState.IDLE:
				_change_state(MovementState.IDLE)


## --- Navigation Movement ---
func _handle_navigation(delta: float) -> void:
	if not navigation_component or not navigation_component.has_active_path():
		return
	
	var next_point = navigation_component.get_next_point()
	if next_point == Vector3.ZERO:
		return
	
	var direction = next_point - global_position
	direction.y = 0.0
	var distance = direction.length()
	
	# 🔥 ДЕМПФИРОВАНИЕ: замедляемся, когда близко к точке
	var distance_factor = clamp(distance / 1.0, 0.0, 1.0)  # 1.0 = радиус замедления
	var effective_speed = speed * distance_factor
	
	if distance > 0.05:  # ✅ Уменьшил порог (было 0.15)
		var normalized_dir = direction / distance
		velocity.x = normalized_dir.x * effective_speed  # ✅ Используем сниженную скорость
		velocity.z = normalized_dir.z * effective_speed
		
		if distance > 0.01:
			var target_angle = atan2(normalized_dir.x, normalized_dir.z)
			rotation.y = lerp_angle(rotation.y, target_angle, delta * 10.0)
	else:
		# ✅ Близко к точке - резко останавливаемся
		velocity.x = 0.0
		velocity.z = 0.0
		navigation_component.advance_path()

## --- Deceleration when not navigating ---
func _apply_deceleration(delta: float) -> void:
	if navigation_component and navigation_component.has_active_path():
		return
	
	if speed > 0.1:
		var decel_rate = run_speed / decel_time
		velocity.x = move_toward(velocity.x, 0.0, delta * decel_rate)
		velocity.z = move_toward(velocity.z, 0.0, delta * decel_rate)
		speed = move_toward(speed, 0.0, delta * decel_rate)
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		speed = 0.0
		if current_state != MovementState.IDLE:
			_change_state(MovementState.IDLE)

## --- State Management ---
func _update_state() -> void:
	var new_state: MovementState
	
	if not navigation_component or not navigation_component.has_active_path():
		new_state = MovementState.DECELERATING if speed > 0.1 else MovementState.IDLE
	elif is_running_mode:
		new_state = MovementState.RUNNING
	elif target_speed > walk_speed + 0.1:
		new_state = MovementState.RUNNING
	else:
		new_state = MovementState.WALKING
	
	if new_state != current_state:
		_change_state(new_state)

func _change_state(new_state: MovementState) -> void:
	current_state = new_state
	emit_signal("state_changed", new_state)

## --- Navigation Callbacks ---
func _on_path_updated() -> void:
	if not movement_enabled:
		return
	
	if navigation_component.has_active_path():
		emit_signal("movement_started")
		_update_state()

func _on_destination_reached() -> void:
	stop_moving(true)

## --- Getters ---
func get_current_speed() -> float:
	return speed

func get_state_name() -> String:
	if not movement_enabled:
		return "заблокирован"
	
	match current_state:
		MovementState.IDLE: return "не движется"
		MovementState.WALKING: return "идёт"
		MovementState.RUNNING: return "бежит"
		MovementState.DECELERATING: return "тормозит"
		_: return "неизвестно"
