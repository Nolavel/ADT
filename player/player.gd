# =============================================================================
# player.gd — Player (CharacterBody3D).
#
# Owns physics, the movement state machine and body rotation directly
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
## Emitted once per punch that actually connects with an NPC, after
## take_hit() has already been called on the target — IncidentRegistry is
## the only subscriber today (see its on_world_ready()), listening without
## player.gd needing to know it exists.
signal punch_landed(position: Vector3)

## --- Movement State ---
enum MovementState { IDLE, WALKING, RUNNING, DECELERATING }

## Character height, meters — the one value that varies per instance
## (NPCs carry their own body_height field too, see npc/npc_base.gd).
## Eye/shoulder/chest ratios are shared anatomy, not a trait of a specific
## character, so they live in core/characters/body_metrics.gd instead of
## being duplicated here. This CharacterBody3D's origin is at the feet, so a
## returned landmark height is also that landmark's height above the floor.
@export var body_height: float = 1.8

@export_group("Movement")
@export var walk_speed: float = 5.0
@export var run_speed: float = 15.5
@export var accel_time: float = 0.55
@export var decel_time: float = 0.8
## Movement speed multiplier while in COMBAT. Fighting stance trades speed
## for readiness — and the slower pace is what makes the stance readable at
## a glance, before any animation detail registers.
@export var combat_speed_multiplier: float = 0.7
## Speed multiplier while aiming, applied on top of the COMBAT multiplier.
## Aiming is a deeper commitment than standing ready: you give up more
## mobility for it.
@export var aim_speed_multiplier: float = 0.5
## How fast the body turns to face the camera in COMBAT — deliberately much
## faster than PEACE's backpedal-facing rate (delta * 6.0) or idle turn rate
## (delta * 3.0): in a fight the body tracks the camera almost without lag,
## since the camera is where the threat is. A feel value, tuned by eye.
@export var combat_face_camera_smoothing: float = 20.0

@export_group("Combat")
## Delay from throwing the punch to it registering a hit, seconds — a feel
## value standing in for a real impact frame: this project has no animation
## event/marker system, so the swing and the hit-check are tied together by
## a timer instead of a clip event. Confirm against the actual clip's impact
## frame in editor and retune.
@export var punch_hit_delay: float = 0.15
## Forward reach of the punch's hit check, metres. Not derived from
## PlayerFocusCast (InteractComponent's own reach volume, gated to the
## Interactables physics layer — NPCs aren't on it, and widening that mask
## would mix combat detection into interact-target selection) — a separate,
## independently tuned value instead, loosely informed by that cast's own
## ~1.8m forward reach.
@export var punch_reach: float = 1.8
## Full angular width of the punch's hit check, degrees, centred on facing.
@export var punch_angle_deg: float = 60.0

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

## --- Punch state (COMBAT only) ---
var _is_punching: bool = false
var _punch_timer: float = 0.0
var _punch_hit_resolved: bool = false

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

	## Reuses InputSystems' existing primary_click_pressed signal instead of
	## adding a new one — LMB has no other TPS meaning (ClickToMoveSystem,
	## the signal's only other subscriber, self-gates to ON_FOOT + ISOMETRIC
	## and never sees it in TPS). The gate on what a press MEANS lives here,
	## same as every other InputSystems subscriber.
	InputSystems.primary_click_pressed.connect(_on_primary_click_pressed)


## --- Physics Update ---
func _physics_process(delta: float) -> void:
	## Runs even while movement is locked (a punch locks it via
	## set_movement_enabled(false)) — everything below this needs the lock
	## to actually stop the body, but the punch's own timer/completion check
	## must keep running or it would never unlock itself.
	if _is_punching:
		_update_punch(delta)

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

	target_speed = clamp(new_speed, 0.0, run_speed * get_speed_multiplier())

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
	return clampf(speed / get_current_max_speed(), 0.0, 1.0)


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


## Current click-to-move destination, or ZERO when the character is not
## heading anywhere. Lets the camera lead toward a known destination
## instead of extrapolating from velocity — with click-to-move the
## destination is known before the first step is taken.
func get_move_target() -> Vector3:
	if not navigation_component:
		return Vector3.ZERO
	return navigation_component.get_final_target()


## Horizontal movement, relative to this character's own facing rather than
## world space: x = lateral (positive = this character's right), y =
## forward (positive = this character's own forward). Magnitude scales with
## speed as a fraction of run_speed — same normalisation as
## get_speed_ratio(), including that getter's same quirk: combat_speed_
## multiplier caps the achievable magnitude below 1.0 in COMBAT, since this
## reads real velocity, not intent. ZERO when standing still. Built for
## AnimationNodeBlendSpace2D's blend_position, which reads magnitude as
## "how far toward this direction," the same way AnimationNodeBlendSpace1D
## reads a get_speed_ratio()-style 0..1 position.
func get_movement_vector_relative_to_facing() -> Vector2:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if horizontal.length() < 0.001 or run_speed <= 0.0:
		return Vector2.ZERO

	var facing := get_facing_direction()
	# Matches Godot's own basis.x (the standard "right" vector) for this
	# rotation — verified algebraically, not derived from the basis
	# directly: facing == (sin y, 0, cos y) (see get_facing_direction()),
	# and Godot's basis.x for rotation.y == y is (cos y, 0, -sin y), i.e.
	# exactly (facing.z, 0, -facing.x).
	var right := Vector3(facing.z, 0.0, -facing.x)

	var result := Vector2(horizontal.dot(right), horizontal.dot(facing)) / get_current_max_speed()
	if result.length() > 1.0:
		result = result.normalized()
	return result


func get_current_speed() -> float:
	return speed


## Reexported from PlayerAnimationComponent — see get_sprint_blend()'s
## comment for the contract this preserves.
func set_head_look_point(world_pos: Vector3) -> void:
	_animation_component.set_head_look_point(world_pos)


func clear_head_look_point() -> void:
	_animation_component.clear_head_look_point()


## Head yaw relative to the body, degrees. Re-exported from
## PlayerAnimationComponent. Not consumed inside player.gd yet — added ahead
## of need for a body-rotation threshold planned for _apply_direct_movement
## (today the body turns purely from movement/camera direction, regardless
## of how far the head has already turned).
func get_head_yaw_relative_deg() -> float:
	return _animation_component.get_head_yaw_relative_deg()


func set_camera_yaw(yaw: float) -> void:
	_camera_yaw = yaw


## Added for PlayerAnimationComponent: it only ever reads player state
## through its own _player reference, never reaches into private fields
## directly (the component's contract, see its header), and needs camera
## yaw for the TPS-idle head look.
func get_camera_yaw() -> float:
	return _camera_yaw


## 1.0 in PEACE, combat_speed_multiplier in COMBAT, further scaled by
## aim_speed_multiplier while aiming — the one place every target_speed
## computation reads the stance/aim slowdown from, so the call sites (direct
## movement, click-to-move clamp, stamina-depleted forced walk) can't drift
## out of sync with each other. Public because PlayerAnimationComponent also
## needs it, to normalise its blend-space position against the current
## stance's speed ceiling rather than the raw walk_speed/run_speed exports —
## same reason get_current_max_speed() exists.
func get_speed_multiplier() -> float:
	if PlayerState.stance != PlayerState.Stance.COMBAT:
		return 1.0
	var multiplier := combat_speed_multiplier
	if PlayerState.is_aiming:
		multiplier *= aim_speed_multiplier
	return multiplier


## Top speed available in the current stance/aim state. Derived from
## get_speed_multiplier() rather than re-checking stance/is_aiming here too
## — two independent copies of the same condition is exactly how this drifted
## out of sync before (get_current_max_speed() didn't know about COMBAT
## until it was added deliberately; aiming would have repeated that mistake
## silently). Anything that normalises speed must divide by this, not by
## run_speed, or it will never reach 1.0 while slowed.
func get_current_max_speed() -> float:
	return run_speed * get_speed_multiplier()


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


## --- Punch (COMBAT only) ---
## Only a raised-fists stance earns a punch — this is the action the stance
## exists for. mouse_left_button is otherwise unclaimed in TPS (see the
## connection comment in _ready()).
func _on_primary_click_pressed(_screen_pos: Vector2) -> void:
	if PlayerState.mode != PlayerState.Mode.ON_FOOT:
		return
	if PlayerState.view_mode != PlayerState.ViewMode.TPS:
		return
	if PlayerState.stance != PlayerState.Stance.COMBAT:
		return
	if _is_punching or not movement_enabled:
		return
	_start_punch()


func _start_punch() -> void:
	_is_punching = true
	_punch_timer = 0.0
	_punch_hit_resolved = false
	set_movement_enabled(false)
	_animation_component.play_punch()


## Called from _physics_process() even while movement is locked — see that
## function's own comment on why.
func _update_punch(delta: float) -> void:
	## True only on the very first call after _start_punch() — used below to
	## skip the completion check for one frame, see that branch's comment.
	var is_first_frame := _punch_timer <= 0.0
	_punch_timer += delta

	if not _punch_hit_resolved and _punch_timer >= punch_hit_delay:
		_punch_hit_resolved = true
		_resolve_punch_hit()

	if is_first_frame:
		## AnimationTree processes the fire request on its own cadence, not
		## synchronously with play_punch() — checking is_punch_active() the
		## same frame it was requested can still read the pre-fire "not
		## active" state and end the punch before it visibly started.
		return

	if not _animation_component.is_punch_active():
		_is_punching = false
		set_movement_enabled(true)


## Cone check against perceived NPCs (ActorBase.GROUP_PERCEIVED_ACTOR,
## filtered to NPCBase) rather than reusing PlayerFocusCast — see
## punch_reach's own comment for why that cast doesn't fit. Drones are in
## the same group but excluded here: they have no take_hit() (see
## npc_base.gd's own header on why that contract is NPC-only, not
## ActorBase-wide).
func _resolve_punch_hit() -> void:
	var target := _find_punch_target()
	if target == null:
		return
	target.take_hit(global_position)
	punch_landed.emit(target.global_position)


func _find_punch_target() -> NPCBase:
	var facing := get_facing_direction()
	var best: NPCBase = null
	var best_dist := INF

	for candidate in get_tree().get_nodes_in_group(ActorBase.GROUP_PERCEIVED_ACTOR):
		if not (candidate is NPCBase):
			continue
		var npc: NPCBase = candidate

		var to_target := npc.global_position - global_position
		to_target.y = 0.0
		var dist := to_target.length()
		if dist > punch_reach or dist < 0.001:
			continue

		var angle := rad_to_deg(facing.angle_to(to_target.normalized()))
		if angle > punch_angle_deg * 0.5:
			continue

		if dist < best_dist:
			best_dist = dist
			best = npc

	return best


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
			target_speed = walk_speed * get_speed_multiplier()
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
	target_speed = (run_speed if running else walk_speed) * get_speed_multiplier()


## Turns the body to face the camera at the given rate. Factored out of
## _apply_direct_movement() so COMBAT's always-face-camera rotation, the
## PEACE backpedal/strafe case and the idle case all share one
## implementation instead of three copies of the same lerp_angle call — and
## aim-down-sights reuses it unchanged: aiming only exists inside COMBAT
## (PlayerState.set_aiming()'s own invariant), and COMBAT already faces the
## camera at combat_face_camera_smoothing in every branch below, moving or
## idle, so there is nothing ADS-specific to add here.
func _face_camera(delta: float, smoothing: float) -> void:
	rotation.y = lerp_angle(rotation.y, _camera_yaw + PI, delta * smoothing)


func _apply_direct_movement(delta: float) -> void:
	var in_combat := PlayerState.stance == PlayerState.Stance.COMBAT

	if _direct_move_direction.length() > 0.01:
		var dir := _direct_move_direction.normalized()
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed

		if in_combat:
			# Combat stance: the body always faces the camera — the threat —
			# and the legs strafe under it, unconditionally, regardless of
			# movement direction. This IS the fighting stance: corpus turned
			# to the threat, feet just carrying it around. Also covers aiming
			# (a COMBAT-only modifier, see PlayerState.is_aiming): no extra
			# branch needed, the rate is already the combat one.
			_face_camera(delta, combat_face_camera_smoothing)
		else:
			# Prototype: PEACE also always faces the camera now, same as
			# COMBAT, just softer (6.0 vs combat_face_camera_smoothing) — the
			# body no longer turns to face movement direction here. Today the
			# two stances are told apart by idle pose and this turn rate, not
			# by a distinct movement manner; giving PEACE its own facing
			# behavior back is future work, not something forgotten here.
			_face_camera(delta, 6.0)

		if current_state == MovementState.IDLE or current_state == MovementState.DECELERATING:
			_change_state(MovementState.RUNNING if is_running_mode else MovementState.WALKING)
		elif is_running_mode and current_state != MovementState.RUNNING:
			_change_state(MovementState.RUNNING)
		elif not is_running_mode and current_state != MovementState.WALKING:
			_change_state(MovementState.WALKING)
	else:
		# Idle: turn to face the camera — at COMBAT's faster rate while in
		# COMBAT (same "tracks the threat without lag" statement as strafing
		# above), at the slow PEACE rate otherwise.
		_face_camera(delta, combat_face_camera_smoothing if in_combat else 3.0)

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
