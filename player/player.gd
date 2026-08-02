# =============================================================================
# player.gd — Player (CharacterBody3D).
#
# RU: Владеет физикой, конечным автоматом состояний движения и поворотом
# тела напрямую (не делегирует их компонентам) для обоих режимов движения:
# click-to-move/навигация (ISOMETRIC, через NavigationComponent,
# _handle_navigation) и прямое WASD-движение (TPS, TPSMovementSystem кормит
# set_direct_move_input() каждый физический кадр, _apply_direct_movement
# считает скорость/поворот/анимацию). Какой путь выполняется — решает
# PlayerState.view_mode внутри _physics_process().
# Сборка AnimationTree и процедурный Head LookAt делегированы
# PlayerAnimationComponent (player_components/animation_component/) —
# player.gd вызывает его update_*() явно в нужном месте _physics_process()
# и никогда не трогает его внутренние поля, только реэкспортирует часть его
# геттеров тонкими обёртками для внешних вызывающих (dynamic_cursor_ui.gd).
#
# EN: Owns physics, the movement state machine and body rotation directly
# (not delegated to components) for both movement modes: click-to-move/
# navigation (ISOMETRIC, via NavigationComponent, _handle_navigation) and
# direct WASD movement (TPS, TPSMovementSystem feeds set_direct_move_input()
# every physics frame, _apply_direct_movement computes velocity/rotation/
# animation). Which path runs is decided by PlayerState.view_mode inside
# _physics_process().
# AnimationTree assembly and the procedural Head LookAt are delegated to
# PlayerAnimationComponent (player_components/animation_component/) —
# player.gd calls its update_*() methods explicitly at the right point in
# _physics_process() and never reaches into its internals, only re-exports
# some of its getters as thin wrappers for outside callers
# (dynamic_cursor_ui.gd).
# =============================================================================
extends CharacterBody3D

## --- Signals ---
signal movement_started
signal movement_stopped
signal state_changed(new_state: MovementState)

## --- Movement State ---
enum MovementState { IDLE, WALKING, RUNNING, DECELERATING }

## RU: Высота персонажа, метры — единственная величина, которая варьируется
## по экземпляру (NPC хранят своё поле body_height так же, см.
## npc/npc_base.gd). Пропорции глаз/плеч/груди — общая анатомия, а не
## особенность конкретного персонажа, поэтому вынесены в
## core/characters/body_metrics.gd и не дублируются здесь. Origin этого
## CharacterBody3D — у ступней, так что возвращаемая высота landmark'а — это
## и есть его высота над полом.
## EN: Character height, meters — the one value that varies per instance
## (NPCs carry their own body_height field too, see npc/npc_base.gd).
## Eye/shoulder/chest ratios are shared anatomy, not a trait of a specific
## character, so they live in core/characters/body_metrics.gd instead of
## being duplicated here. This CharacterBody3D's origin is at the feet, so a
## returned landmark height is also that landmark's height above the floor.
@export var body_height: float = 1.8

@export_group("Movement")
@export var walk_speed: float = 5.0
@export var run_speed: float = 10.0
@export var accel_time: float = 0.55
@export var decel_time: float = 0.8

@export_group("Jump/Gravity")
## Apex height = jump_force^2 / (2 * gravity). At 6.0/20.0 that's 0.9m, half
## of body_height — a deliberate game-balance choice, not a value derived
## from body_height. Change this number with the formula in mind, not blind.
@export var jump_force: float = 6.0
@export var gravity: float = 20.0

@export_group("Animation")
@export var player_animation_player: AnimationPlayer

## --- Movement State ---
var current_state: MovementState = MovementState.IDLE
var speed: float = 0.0
var target_speed: float = 0.0
var movement_enabled: bool = true

## --- Sprint state (for the cursor UI) ---
var is_running_mode: bool = false
var wants_to_run: bool = false  # the player wants to run (even if they can't)

## --- Direct movement (TPS, WASD) — cached input data, written by
## TPSMovementSystem every physics frame via set_direct_move_input().
## player.gd itself computes velocity/animation/rotation, so physics and
## the state machine stay in one place, same as for click-to-move.
var _direct_move_direction: Vector3 = Vector3.ZERO
var _direct_move_want_run: bool = false

## Camera yaw reference for TLOU-style idle rotation and backpedal detection.
## Set by TPSMovementSystem every physics frame.
var _camera_yaw: float = 0.0

## --- Components ---
@onready var navigation_component: NavigationComponent = $NavComponent
@onready var stamina_manager: StaminaComponent = $StaminaComponent
@onready var animation_player: AnimationPlayer = $player_base_mesh/AnimationPlayer
@onready var _animation_component: PlayerAnimationComponent = $AnimationComponent


## --- Initialization ---
func _ready() -> void:
	add_to_group("player")
	if navigation_component:
		navigation_component.path_updated.connect(_on_path_updated)
		navigation_component.destination_reached.connect(_on_destination_reached)
	else:
		push_warning("NavigationComponent not found - direct movement only")

	if stamina_manager == null:
		push_warning("StaminaManager not found - stamina system will not work")


## --- Physics Update ---
func _physics_process(delta: float) -> void:
	if not movement_enabled:
		return

	_animation_component.update_sprint_blend(delta)
	_handle_stamina_consumption()
	_handle_jump()
	_apply_gravity(delta)

	if PlayerState.view_mode == PlayerState.ViewMode.TPS:
		_update_direct_move_target_speed()

	_update_speed(delta)
	_animation_component.update_animation_blend(delta)
	_animation_component.update_head_look(delta)

	if PlayerState.view_mode == PlayerState.ViewMode.TPS:
		_apply_direct_movement(delta)
	else:
		_handle_navigation(delta)
		_apply_deceleration(delta)

	move_and_slide()


## --- Public API ---
func move_to_position(pos: Vector3) -> void:
	if not movement_enabled:
		return

	if navigation_component:
		navigation_component.set_target_position(pos)


func set_movement_speed(new_speed: float) -> void:
	if not movement_enabled:
		return

	target_speed = clamp(new_speed, 0.0, run_speed)

	# Remember that the player WANTS to run (even if they can't)
	wants_to_run = (new_speed > walk_speed * 1.1)

	# Decide run mode from speed
	is_running_mode = wants_to_run

	_update_state()


## Called by TPSMovementSystem every _physics_process while TPS is active.
## direction is already computed, camera-relative, Y-flattened
## (not necessarily normalised — a zero vector means "standing still").
## Physics/animation/rotation are computed right here in player.gd — same
## as _handle_navigation does for click-to-move.
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


## MOVEMENT-LOCK SYSTEM
func set_movement_enabled(enabled: bool) -> void:
	movement_enabled = enabled

	if not enabled:
		velocity = Vector3.ZERO
		speed = 0.0
		target_speed = 0.0
		is_running_mode = false
		wants_to_run = false

		if navigation_component:
			navigation_component.clear_path()

		if stamina_manager:
			stamina_manager.stop_consuming_stamina()

		if current_state != MovementState.IDLE:
			_change_state(MovementState.IDLE)


func is_movement_enabled() -> bool:
	return movement_enabled


## === CURSOR METHODS (compatibility with MouseCursorUI) ===

## Checks whether the player is currently sprinting
func is_currently_sprinting(current_velocity: Vector3) -> bool:
	if not movement_enabled:
		return false

	var horizontal_speed: float = Vector2(current_velocity.x, current_velocity.z).length()
	return is_running_mode and horizontal_speed > walk_speed * 1.2


## Reexported from PlayerAnimationComponent so external callers
## (dynamic_cursor_ui.gd) keep working unchanged. See
## player_animation_component.gd's header for the read-only contract this
## wrapper preserves: the component never writes into player.gd, a getter
## is the only way information comes back out of it.
func get_sprint_blend() -> float:
	return _animation_component.get_sprint_blend()


## Checks whether the player wants to run (independent of stamina)
func is_wanting_to_run() -> bool:
	return wants_to_run


## Character metric getters — callers (camera, future IK/effects) ask for a
## named landmark instead of hardcoding a height or knowing where origin is.
func get_eye_height() -> float:
	return BodyMetrics.eye_height(body_height)


func get_shoulder_height() -> float:
	return BodyMetrics.shoulder_height(body_height)


func get_chest_height() -> float:
	return BodyMetrics.chest_height(body_height)


## Current horizontal speed as a 0..1 fraction of run_speed. Lets the camera
## react to how fast the character moves without knowing the balance numbers.
func get_speed_ratio() -> float:
	if run_speed <= 0.0:
		return 0.0
	return clampf(speed / run_speed, 0.0, 1.0)


## Horizontal movement direction, normalised, or ZERO when standing still.
## Lets the camera lead the character without reading its internals.
func get_horizontal_direction() -> Vector3:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if horizontal.length() < 0.001:
		return Vector3.ZERO
	return horizontal.normalized()


## Direction this character visually faces, horizontal and normalised.
## NOTE: this project rotates characters with atan2(dir.x, dir.z), which makes
## +Z the visual forward, not Godot's usual -Z. Read facing through this getter
## instead of deriving it from the basis, or the sign will be wrong.
func get_facing_direction() -> Vector3:
	return Vector3(sin(rotation.y), 0.0, cos(rotation.y))


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


## Reexported from PlayerAnimationComponent — see get_sprint_blend()'s
## comment for the contract this preserves.
func set_head_look_point(world_pos: Vector3) -> void:
	_animation_component.set_head_look_point(world_pos)


func clear_head_look_point() -> void:
	_animation_component.clear_head_look_point()


## RU: Угол головы относительно тела, градусы. Реэкспорт из
## PlayerAnimationComponent. Пока не используется внутри player.gd — заведён
## впрок для порога разворота корпуса, который планируется добавить в
## _apply_direct_movement (сейчас тело поворачивается только по направлению
## движения/камеры, независимо от того, куда уже довёрнута голова).
## EN: Head yaw relative to the body, degrees. Re-exported from
## PlayerAnimationComponent. Not consumed inside player.gd yet — added ahead
## of need for a body-rotation threshold planned for _apply_direct_movement
## (today the body turns purely from movement/camera direction, regardless
## of how far the head has already turned).
func get_head_yaw_relative_deg() -> float:
	return _animation_component.get_head_yaw_relative_deg()


func set_camera_yaw(yaw: float) -> void:
	_camera_yaw = yaw


## RU: Геттер добавлен ради PlayerAnimationComponent: тот читает состояние
## игрока только через свою ссылку _player и не лезет в приватные поля
## напрямую (контракт компонента, см. его заголовок), а camera yaw ему нужен
## для head look в TPS idle.
## EN: Added for PlayerAnimationComponent: it only ever reads player state
## through its own _player reference, never reaches into private fields
## directly (the component's contract, see its header), and needs camera
## yaw for the TPS-idle head look.
func get_camera_yaw() -> float:
	return _camera_yaw


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


## --- Stamina consumption (drains while running) ---
func _handle_stamina_consumption() -> void:
	if not stamina_manager:
		return

	var can_run: bool = stamina_manager.is_sprint_allowed()

	if is_running_mode and is_moving():
		if can_run:
			if not stamina_manager.is_consuming_stamina:
				stamina_manager.start_consuming_stamina()
		else:
			## Stamina ran out - force a switch to walking
			if stamina_manager.is_consuming_stamina:
				stamina_manager.stop_consuming_stamina()

			## Lower the REAL speed, but do NOT reset wants_to_run
			target_speed = walk_speed
			is_running_mode = false
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
	var acceleration: float = (run_speed - walk_speed) / accel_time
	speed = move_toward(speed, target_speed, delta * acceleration)


## --- Direct Movement (TPS, WASD) ---
## Computes the target speed BEFORE _update_speed(delta), so run/walk
## kicks in the same frame instead of one physics tick late.
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


func _apply_direct_movement(delta: float) -> void:
	if _direct_move_direction.length() > 0.01:
		var dir := _direct_move_direction.normalized()
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed

		# TLOU-style rotation: face movement direction when moving forward
		# relative to camera; face camera when backpedaling / strafing
		var move_facing := atan2(dir.x, dir.z)
		var cam_facing := _camera_yaw + PI   # "forward" from camera's POV
		var angle_diff := absf(wrapf(move_facing - cam_facing, -PI, PI))

		if angle_diff < PI * 0.5:
			# Forward hemisphere: face movement direction
			rotation.y = lerp_angle(rotation.y, move_facing, delta * 10.0)
		else:
			# Backward hemisphere: face camera (backpedal / strafe)
			rotation.y = lerp_angle(rotation.y, cam_facing, delta * 6.0)

		if current_state == MovementState.IDLE or current_state == MovementState.DECELERATING:
			_change_state(MovementState.RUNNING if is_running_mode else MovementState.WALKING)
		elif is_running_mode and current_state != MovementState.RUNNING:
			_change_state(MovementState.RUNNING)
		elif not is_running_mode and current_state != MovementState.WALKING:
			_change_state(MovementState.WALKING)
	else:
		# Idle: slowly turn to face camera direction
		rotation.y = lerp_angle(rotation.y, _camera_yaw + PI, delta * 3.0)

		# Deceleration — same rate as click-to-move for consistent feel
		if speed > 0.1:
			var decel_rate: float = run_speed / decel_time
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

	var next_point: Vector3 = navigation_component.get_next_point()
	if next_point == Vector3.ZERO:
		return

	var direction: Vector3 = next_point - global_position
	direction.y = 0.0
	var distance: float = direction.length()

	# Damping: slow down when close to the point
	var distance_factor: float = clamp(distance / 1.0, 0.0, 1.0)  # 1.0 = slowdown radius
	var effective_speed: float = speed * distance_factor

	if distance > 0.05:
		var normalized_dir: Vector3 = direction / distance
		velocity.x = normalized_dir.x * effective_speed
		velocity.z = normalized_dir.z * effective_speed

		if distance > 0.01:
			var target_angle: float = atan2(normalized_dir.x, normalized_dir.z)
			rotation.y = lerp_angle(rotation.y, target_angle, delta * 10.0)
	else:
		# Close to the point - stop abruptly
		velocity.x = 0.0
		velocity.z = 0.0
		navigation_component.advance_path()


## --- Deceleration when not navigating ---
func _apply_deceleration(delta: float) -> void:
	if navigation_component and navigation_component.has_active_path():
		return

	if speed > 0.1:
		var decel_rate: float = run_speed / decel_time
		velocity.x = move_toward(velocity.x, 0.0, delta * decel_rate)
		velocity.z = move_toward(velocity.z, 0.0, delta * decel_rate)
		speed = move_toward(speed, 0.0, delta * decel_rate)
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		speed = 0.0
		if current_state != MovementState.IDLE:
			_change_state(MovementState.IDLE)
