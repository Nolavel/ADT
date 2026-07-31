extends CharacterBody3D

## ============================================
## CHARACTER METRICS
## Single source of truth for the character's physical size. Every
## height-derived value in the project must be computed from these instead
## of being hardcoded, so that a change of scale stays local to this block.
## The origin of this CharacterBody3D sits at the feet: a returned height is
## also the height above the floor the character stands on. If the origin
## convention ever changes, only the getters below need to change — callers
## must keep asking for a named landmark height, never assume where origin is.
## ============================================
const BODY_HEIGHT: float = 1.8
## Landmark heights as fractions of BODY_HEIGHT, measured from the feet.
const EYE_RATIO: float = 0.94
const SHOULDER_RATIO: float = 0.82
const CHEST_RATIO: float = 0.72

## --- Movement Parameters ---
@export_group("Movement")
@export var walk_speed: float = 5.0
@export var run_speed: float = 10.0
@export var accel_time: float = 0.55
@export var decel_time: float = 0.8

@export_group("Jump/Gravity")
## Apex height = jump_force^2 / (2 * gravity). At 6.0/20.0 that's 0.9m, half
## of BODY_HEIGHT — a deliberate game-balance choice, not a value derived
## from BODY_HEIGHT. Change this number with the formula in mind, not blind.
@export var jump_force: float = 6.0
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

## --- Procedural Head LookAt ---
const HEAD_BONE_NAME: StringName = &"Head"
## RU: Скорость подтяжки маркера к целевой точке.
const HEAD_LOOK_SMOOTH: float = 8.0
## RU: На каком удалении держится точка взгляда, м.
const HEAD_LOOK_DISTANCE: float = 5.0
## RU: Скорость ввода/вывода модификатора через influence, 1/сек.
const HEAD_LOOK_FADE_SPEED: float = 4.0
 
var _skeleton: Skeleton3D
var _head_lookat: LookAtModifier3D
var _head_look_node: Node3D
## RU: Текущее влияние модификатора 0..1. Затухание идёт ИМ, а не подтяжкой
##     цели к нейтрали: influence не зависит от расстояния до цели, а прошлый
##     вариант сходился тем дольше, чем дальше смотрел персонаж.
var _head_look_influence: float = 0.0
 
## RU: Мировая точка взгляда для ISOMETRIC. Пишется снаружи через
##     set_head_look_point(); сам player.gd камеру не знает и рейкастов не шлёт.
var _look_point: Vector3 = Vector3.ZERO
var _look_point_valid: bool = false

## Camera yaw reference for TLOU-style idle rotation and backpedal detection.
## Set by TPSMovementSystem every physics frame.
var _camera_yaw: float = 0.0

## --- Direct movement (TPS, WASD) — cached input data, written by
## TPSMovementSystem every physics frame via set_direct_move_input().
## player.gd itself computes velocity/animation/rotation, so physics and
## the state machine stay in one place, same as for click-to-move.
var _direct_move_direction: Vector3 = Vector3.ZERO
var _direct_move_want_run: bool = false

## --- Sprint state (for the cursor UI) ---
var is_running_mode: bool = false
var wants_to_run: bool = false  # 🔥 NEW: the player wants to run (even if they can't)
var sprint_blend: float = 0.0
var sprint_blend_speed: float = 4.0

## --- Animation Tree (built entirely in code, no hand-authored .tres) ---
## A speed-driven blend space gives a smooth walk<->run transition instead
## of an abrupt play() switch, synced to the real speed value, which is
## already eased through _update_speed()/accel_time.
var _anim_tree: AnimationTree
var _moving_blend_amount: float = 0.0  # 0 = idle, 1 = locomotion
const MOVE_BLEND_SPEED: float = 6.0
const IDLE_ENTER_SPEED: float = 0.15  # below this we consider the character standing still

## --- Signals ---
signal movement_started
signal movement_stopped
signal state_changed(new_state: MovementState)

## --- Initialization ---
func _ready():
	add_to_group("player")
	_setup_animation_tree()
	_setup_head_look()
	if navigation_component:
		navigation_component.path_updated.connect(_on_path_updated)
		navigation_component.destination_reached.connect(_on_destination_reached)
	else:
		push_warning("NavigationComponent not found - direct movement only")
	
	if stamina_manager == null:
		push_warning("StaminaManager not found - stamina system will not work")

## --- Animation Tree Setup ---
## Assembled entirely in code: Blend2(idle <-> locomotion), where
## locomotion is a BlendSpace1D(walk@0 .. run@1). Needs no hand-authored
## .tres/editor setup, easy to rebuild when clips change.
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
	
func _setup_head_look() -> void:
	_skeleton = get_node_or_null(
		"player_base_mesh/GeneralSkeleton/RetargetModifier3D/OriginalSkeleton"
	) as Skeleton3D
	if _skeleton == null:
		push_warning("[Player] Skeleton3D не найден — head look отключён")
		return
 
	## RU: Сначала по имени, потом перебором по типу. В прошлой версии ветка
	##     перебора находила модификатор и тут же безусловно возвращалась,
	##     не дойдя до настройки — из-за этого весь head look молча не работал.
	_head_lookat = _skeleton.get_node_or_null("LookAt") as LookAtModifier3D
	if _head_lookat == null:
		for child in _skeleton.get_children():
			if child is LookAtModifier3D:
				_head_lookat = child
				break
	if _head_lookat == null:
		push_warning("[Player] LookAtModifier3D не найден под Skeleton3D — head look отключён")
		return
 
	## RU: Маркер цели. Создаём до того, как отдать путь модификатору.
	_head_look_node = Node3D.new()
	_head_look_node.name = "HeadLookTarget"
	add_child(_head_look_node)
	_head_look_node.global_position = (
		global_position + get_facing_direction() * HEAD_LOOK_DISTANCE
		+ Vector3.UP * get_eye_height()
	)
 
	_head_lookat.bone_name = HEAD_BONE_NAME
	## RU: Имя свойства именно use_angle_limitation. use_angle_limits не
	##     существует, присваивание в него — runtime-ошибка.
	_head_lookat.use_angle_limitation = true
	_head_lookat.target_node = _head_lookat.get_path_to(_head_look_node)
	## RU: active, а не enabled. enabled у SkeletonModifier3D нет.
	_head_lookat.active = false
	_head_lookat.influence = 0.0
 
	## RU: Если голова смотрит вбок или вниз при верной цели — дело не в
	##     математике, а в forward_axis: по умолчанию +Z, у импортированных
	##     ригов «вперёд» головы часто по −Z или +Y. Правится в инспекторе.

## --- Public API ---
func move_to_position(pos: Vector3) -> void:
	if not movement_enabled:
		print("⚠️ Player: movement disabled, ignoring move_to_position()")
		return
	
	if navigation_component:
		navigation_component.set_target_position(pos)

func set_movement_speed(new_speed: float) -> void:
	if not movement_enabled:
		return
	
	target_speed = clamp(new_speed, 0.0, run_speed)
	
	# 🔥 Remember that the player WANTS to run (even if they can't)
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
		
		print("🔒 Player: movement LOCKED")
	else:
		print("✅ Player: movement UNLOCKED")

func is_movement_enabled() -> bool:
	return movement_enabled

## === CURSOR METHODS (compatibility with MouseCursorUI) ===

## Checks whether the player is currently sprinting
func is_currently_sprinting(current_velocity: Vector3) -> bool:
	if not movement_enabled:
		return false
	
	var horizontal_speed = Vector2(current_velocity.x, current_velocity.z).length()
	return is_running_mode and horizontal_speed > walk_speed * 1.2

## Returns sprint progress (0.0 - 1.0)
func get_sprint_blend() -> float:
	return sprint_blend

## Checks whether the player wants to run (independent of stamina)
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
	_update_head_look(delta)

	if PlayerState.view_mode == PlayerState.ViewMode.TPS:
		_apply_direct_movement(delta)
	else:
		_handle_navigation(delta)
		_apply_deceleration(delta)
	
	move_and_slide()

## --- Sprint blend (for smooth UI animation) ---
func _update_sprint_blend(delta: float) -> void:
	var target_blend = 1.0 if is_running_mode else 0.0
	sprint_blend = lerp(sprint_blend, target_blend, sprint_blend_speed * delta)

## --- Animation blend (walk<->run, idle<->moving) ---
## The BlendSpace1D position comes from the REAL speed (already smoothed
## through move_toward/accel_time in _update_speed), not from
## is_running_mode — so the animation can never physically outrun the
## character's actual speed, and stamina running out visually "settles"
## smoothly, without a clip jump.
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

## --- Stamina consumption (drains while running) ---
func _handle_stamina_consumption() -> void:
	if not stamina_manager:
		return
	
	var can_run = stamina_manager.is_sprint_allowed()
	
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
			print("⚠️ Stamina depleted - switching to walking")
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
	
	# 🔥 DAMPING: slow down when close to the point
	var distance_factor = clamp(distance / 1.0, 0.0, 1.0)  # 1.0 = slowdown radius
	var effective_speed = speed * distance_factor

	if distance > 0.05:  # ✅ Lowered the threshold (was 0.15)
		var normalized_dir = direction / distance
		velocity.x = normalized_dir.x * effective_speed  # ✅ Use the reduced speed
		velocity.z = normalized_dir.z * effective_speed

		if distance > 0.01:
			var target_angle = atan2(normalized_dir.x, normalized_dir.z)
			rotation.y = lerp_angle(rotation.y, target_angle, delta * 10.0)
	else:
		# ✅ Close to the point - stop abruptly
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

## Character metric getters — callers (camera, future IK/effects) ask for a
## named landmark instead of hardcoding a height or knowing where origin is.
func get_eye_height() -> float:
	return BODY_HEIGHT * EYE_RATIO

func get_shoulder_height() -> float:
	return BODY_HEIGHT * SHOULDER_RATIO

func get_chest_height() -> float:
	return BODY_HEIGHT * CHEST_RATIO

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
		
## Head look-at: in TPS idle, head smoothly follows camera direction.
## Disabled during movement so animation clips control the head.
## Disabled in ISO/MENU/Hover so it doesn't fight click-to-move or cutscenes.
func _update_head_look(delta: float) -> void:
	if _head_lookat == null or _head_look_node == null:
		return
 
	var want: bool = false
	var target_pos: Vector3 = Vector3.ZERO
 
	if PlayerState.mode == PlayerState.Mode.ON_FOOT:
		match PlayerState.view_mode:
			PlayerState.ViewMode.TPS:
				if speed < IDLE_ENTER_SPEED:
					## RU: +PI обязателен. Камера смотрит вдоль −Z, а проект
					##     держит визуальным «вперёд» +Z (см. комментарий к
					##     get_facing_direction). Без +PI голова смотрит В
					##     объектив вместо того, куда смотрит игрок.
					var cam_angle: float = _camera_yaw + PI
					var cam_dir := Vector3(sin(cam_angle), 0.0, cos(cam_angle))
					target_pos = (
						global_position + cam_dir * HEAD_LOOK_DISTANCE
						+ Vector3.UP * get_eye_height()
					)
					want = true
			_:
				if _look_point_valid:
					## RU: Точка приходит с пола — поднимаем на грудь, иначе
					##     персонаж утыкается взглядом себе под ноги.
					target_pos = _look_point + Vector3.UP * get_chest_height()
					want = true
 
	if not want:
		target_pos = (
			global_position + get_facing_direction() * HEAD_LOOK_DISTANCE
			+ Vector3.UP * get_eye_height()
		)
 
	if want and _head_look_influence <= 0.001:
		## RU: Первый кадр включения — ставим маркер сразу, без замаха от того
		##     места, где он остался с прошлого раза.
		_head_look_node.global_position = target_pos
	else:
		_head_look_node.global_position = _head_look_node.global_position.lerp(
			target_pos, delta * HEAD_LOOK_SMOOTH
		)
 
	_head_look_influence = move_toward(
		_head_look_influence, 1.0 if want else 0.0, delta * HEAD_LOOK_FADE_SPEED
	)
	_head_lookat.influence = _head_look_influence
	_head_lookat.active = _head_look_influence > 0.001
	
func set_head_look_point(world_pos: Vector3) -> void:
	_look_point = world_pos
	_look_point_valid = true
 
func clear_head_look_point() -> void:
	_look_point_valid = false
		
func set_camera_yaw(yaw: float) -> void:
	_camera_yaw = yaw
