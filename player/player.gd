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
## Emitted once per punch that resolved WITHOUT connecting — the swing is a
## visible act, not a fact about the city, so it deliberately does NOT reach
## IncidentRegistry: nothing is recorded, nothing is attributed, nothing
## survives the frame. IdleNPCController is the only subscriber today,
## connecting to it the same lazy way it resolves IncidentRegistry (see that
## file's _try_connect_player_swing()); player.gd never learns who listened.
signal punch_missed(position: Vector3)

## --- Movement State ---
enum MovementState { IDLE, WALKING, RUNNING, DECELERATING }

## --- Save contract (H1, docs/scope_horizon.md) ---
## The player's stable actor id, read by IncidentRegistry (via the duck-typed
## get_actor_id() below) instead of a Node3D reference — see actor_base.gd's
## own actor_id for why. A constant, not an @export: there is exactly one
## player, so there is nothing to author per-instance the way an NPC's id is.
const ACTOR_ID: StringName = &"player"

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
## Speed below which the character counts as standing still for the purpose
## of throwing a punch. Not a balance number — a punch played over
## locomotion has nothing to blend with (no layered upper-body mixing in
## this project yet), so it reads as sliding. Standing still is also what
## makes the attack a decision rather than a click spam.
@export var punch_max_speed: float = 0.5
## Reach of the wind-up's INTENT search, as a multiple of punch_reach. The
## intent target is who this punch was thrown at — resolved once, at the
## moment the button is accepted — and the body turns toward them while the
## swing winds up, so an NPC that steps aside during punch_hit_delay is
## still swung at rather than swung past. Slightly wider than punch_reach on
## purpose: the player aimed at a person, not at a volume, and the hit check
## itself is unchanged, so a target that fully leaves the cone or the reach
## still makes this a miss.
@export var punch_intent_reach_multiplier: float = 1.4
## Full angular width of the intent search, degrees, centred on facing.
## Wider than punch_angle_deg for the same reason the reach is longer.
@export var punch_intent_angle_deg: float = 120.0
## Rate the body turns toward the intent target during the wind-up. Smoothed
## rather than snapped (unlike _face_punch_target()'s instant ISOMETRIC turn,
## which has to be exact before the hit check reads facing): this correction
## is meant to be visible as the character committing to a swing. Tuned to
## land most of the turn inside punch_hit_delay, not to guarantee a hit.
@export var punch_intent_turn_smoothing: float = 18.0

@export_group("Jump/Gravity")
## Apex height = jump_force^2 / (2 * gravity). At 6.0/20.0 that's 0.9m, half
## of body_height — a deliberate game-balance choice, not a value derived
## from body_height. Change this number with the formula in mind, not blind.
@export var jump_force: float = 6.0
@export var gravity: float = 20.0

@export_group("Fall Damage")
## Impact speed below which a landing costs nothing. Roughly a 3 m drop.
@export var fall_damage_min_speed: float = 8.0
## Impact speed that is always fatal. Roughly a 20 m drop — real-world lethality
## crosses fifty percent well below this, so nothing survives it here.
@export var fall_damage_lethal_speed: float = 20.0
## Damage above which the landing also breaks something.
@export var fall_fracture_damage: float = 20.0

@export_group("Animation")
@export var player_animation_player: AnimationPlayer

## --- Movement State ---
var current_state: MovementState = MovementState.IDLE
var speed: float = 0.0
var target_speed: float = 0.0
var movement_enabled: bool = true

## Permanently true once _on_died() fires. Distinct from movement_enabled: a
## punch also sets that false, but only temporarily, and only death needs to
## additionally silence _update_punch()'s call, which otherwise runs
## regardless of movement_enabled by design (see _physics_process()'s own
## comment). No revive in this task — TODO(save): clear this (and re-enable
## movement) on whatever respawn/load does once the save system exists.
var _is_dead: bool = false

## --- Sprint state (for the cursor UI) ---
var is_running_mode: bool = false
var wants_to_run: bool = false  # the player wants to run (even if they can't)

## --- Punch state (COMBAT only) ---
var _is_punching: bool = false
var _punch_timer: float = 0.0
var _punch_hit_resolved: bool = false
## Instance id of the NPC this punch was thrown at, 0 when the swing was
## aimed at nobody. An id, not a Node reference: the target can be freed
## mid-wind-up by its own block streaming out, and an id makes that a
## checked lookup (is_instance_id_valid()) instead of a dangling reference
## this node would otherwise be keeping alive for the length of a swing.
var _punch_intent_id: int = 0

## Injected by ClickToMoveSystem.register_player() at world-init time (see
## that file's on_world_ready()) — a separate route from the WorldContext
## player.gd's own on_world_ready() now also receives (see that method):
## that context has no dedicated ClickToMoveSystem field, and this
## injection predates it, so it was left in place rather than rerouted
## through context.get_system(). Used only to reuse its ground raycast for
## facing the COMBAT punch toward the click point in ISOMETRIC, see
## _face_punch_target().
var _click_to_move_system: ClickToMoveSystem = null

## --- Direct movement (TPS, WASD) — cached input data, written by
## TPSMovementSystem every physics frame via set_direct_move_input().
## player.gd itself computes velocity/animation/rotation, so physics and
## the state machine stay in one place, same as for click-to-move.
var _direct_move_direction: Vector3 = Vector3.ZERO
var _direct_move_want_run: bool = false

## Camera yaw reference for TLOU-style idle rotation and backpedal detection.
## Set by TPSMovementSystem every physics frame.
var _camera_yaw: float = 0.0

## --- Fall damage tracking ---
## is_on_floor() as of the end of the PREVIOUS physics frame's
## move_and_slide() — compared against the current frame's to detect the
## not-on-floor -> on-floor transition that means "just landed."
var _was_on_floor: bool = false
## velocity.y cached immediately before move_and_slide(), while it is still
## this frame's pre-collision value. is_on_floor() only reflects reality
## AFTER move_and_slide() resolves collisions, so by the moment a landing is
## actually detected the real impact speed is already gone from velocity.y
## itself — it has to be captured a step ahead of time.
var _pre_move_vertical_speed: float = 0.0

## ComicEffectSystem, resolved lazily by group — same scheme NPCBase and
## IdleNPCController use, and for the same reason: player.tscn is
## instantiated by world.gd before the systems finish coming up, and this
## node never receives a WorldContext of its own. Null is a silent no-op.
var _comic_effects: ComicEffectSystem = null

## Last health reading seen through health_changed, so a DECREASE can be
## told from a heal or from the initial paint. HealthComponent has no
## "damaged" signal of its own, and adding one for a decoration would be
## the wrong direction of dependency.
var _last_health_seen: float = -1.0

## --- Components ---
@onready var navigation_component: NavigationComponent = $NavComponent
@onready var stamina_manager: StaminaComponent = $StaminaComponent
@onready var animation_player: AnimationPlayer = $player_base_mesh/AnimationPlayer
@onready var _animation_component: PlayerAnimationComponent = $AnimationComponent
@onready var _health: HealthComponent = $HealthComponent
## Same node type npc_base.gd carries (core/components/votive_projector/) —
## driven every physics frame below, same "dumb component" pattern
## _animation_component already follows. Nothing drives its state past IDLE
## today: the player doesn't file witness reports about themselves, see
## votive_projector.gd's own header. Looked up by scene-unique name (%),
## not $VotiveProjector, since it now sits under a BoneAttachment3D bound to
## the head bone rather than directly under this node — see
## votive_projector.gd's own header on why.
@onready var _votive: VotiveProjector = %VotiveProjector


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

	_health.died.connect(_on_died)

	## Comic layer, event-driven throughout: every one of these is an EDGE
	## (took damage, sprint just became unavailable, stamina just hit the
	## floor, stance just flipped), never a per-frame reading of a state —
	## see docs/visual_language.md, a word marks an event and never a
	## condition.
	_health.health_changed.connect(_on_health_changed_for_comic)
	if stamina_manager:
		stamina_manager.sprint_allowed_changed.connect(_on_sprint_allowed_changed_for_comic)
		stamina_manager.stamina_depleted.connect(_on_stamina_depleted_for_comic)
	PlayerState.stance_changed.connect(_on_stance_changed_for_comic)

	## Reuses InputSystems' existing primary_click_pressed signal instead of
	## adding a new one. ClickToMoveSystem, the signal's other subscriber, is
	## now self-gated to Stance.PEACE too (on top of ON_FOOT + ISOMETRIC), so
	## the two subscribers never both react to the same click: in COMBAT this
	## handler is the only one listening, in either view mode. The gate on
	## what a press MEANS still lives here, same as every other InputSystems
	## subscriber.
	InputSystems.primary_click_pressed.connect(_on_primary_click_pressed)


## --- Physics Update ---
func _physics_process(delta: float) -> void:
	if _is_dead:
		## The one deliberate exception death makes to the movement lock:
		## gravity keeps running — a body that died mid-air must still fall
		## to the ground. Everything else (locomotion, jump, clicks, and the
		## punch continuation below) stays locked: _handle_jump() and
		## _on_primary_click_pressed() are already unreachable once
		## set_movement_enabled(false) has run (see _on_died()), and this
		## early return sits before the unconditional _update_punch() call
		## below, which is the one thing that check alone would NOT have
		## stopped.
		_apply_gravity(delta)
		move_and_slide()
		return

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
	_votive.update_projection(delta)

	if PlayerState.view_mode == PlayerState.ViewMode.TPS:
		_apply_direct_movement(delta)
	else:
		_handle_navigation(delta)
		_apply_deceleration(delta)

	_pre_move_vertical_speed = velocity.y
	move_and_slide()
	_check_fall_damage()


## --- Public API ---

## Called once by world.gd after context is fully populated (see world.gd's
## own on_world_ready sweep) — the player isn't part of the
## WORLD_SYSTEM_SCRIPTS/3D-entity/UI loops themselves, so this is the only
## route it has to a GameClockSystem reference. Passed straight through to
## HealthComponent.setup(), the only thing here that needs it.
func on_world_ready(context: WorldContext) -> void:
	var clock := context.get_system(GameClockSystem) as GameClockSystem
	_health.setup(clock)

	## HealthComponent and StaminaComponent know nothing about each other —
	## player.gd owns both, so it's the only place the tie belongs. See
	## _on_health_band_changed()'s own comment for why.
	_health.band_changed.connect(_on_health_band_changed)
	## Same reason player_hud.gd fires its own initial paint: HealthComponent
	## already reached full health in its own _ready(), before this
	## subscription existed, so the first signal would otherwise only arrive
	## on the first point of damage.
	_on_health_band_changed(_health.get_band())


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


## Called once by ClickToMoveSystem.register_player() at world-init time.
## See _click_to_move_system's own comment for why player.gd needs this at
## all instead of reaching ClickToMoveSystem some other way.
func set_click_to_move_system(system: ClickToMoveSystem) -> void:
	_click_to_move_system = system


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


## Stable id for IncidentRegistry (and any future consumer) to key on instead
## of this Node — see ACTOR_ID's own comment.
func get_actor_id() -> StringName:
	return ACTOR_ID


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


## --- Health Callbacks ---
## Locks the player out of control permanently — no revive in this task, see
## _is_dead's own comment. set_movement_enabled(false) alone already stops
## _handle_jump() and _on_primary_click_pressed() (both only reachable while
## movement_enabled is true); _is_dead is the extra flag _physics_process()
## checks first, ahead of its unconditional _update_punch() call, which
## movement_enabled alone does not gate.
func _on_died() -> void:
	_animation_component.play_death()
	set_movement_enabled(false)
	_is_dead = true
	_try_spawn_comic_effect(&"player_death")


## Comic layer handlers. Each is one edge; none of them reads a state per
## frame. See docs/visual_language.md for the rule and player.gd's own
## _ready() for why these are separate from the gameplay subscriptions
## already on the same signals.
func _on_health_changed_for_comic(current: float, _maximum: float) -> void:
	var dropped := _last_health_seen >= 0.0 and current < _last_health_seen
	_last_health_seen = current
	if dropped and not _is_dead:
		_try_spawn_comic_effect(&"player_hurt")


func _on_sprint_allowed_changed_for_comic(is_allowed: bool) -> void:
	if not is_allowed:
		_try_spawn_comic_effect(&"player_winded")


func _on_stamina_depleted_for_comic() -> void:
	_try_spawn_comic_effect(&"player_spent")


func _on_stance_changed_for_comic(
		_old_stance: PlayerState.Stance,
		new_stance: PlayerState.Stance
	) -> void:
	if new_stance == PlayerState.Stance.COMBAT:
		_try_spawn_comic_effect(&"player_combat")


## Resolves ComicEffectSystem on first use and asks it for one word above
## the player. The system owns the distance gate and the active-count cap.
func _try_spawn_comic_effect(id: StringName) -> void:
	if _comic_effects == null:
		_comic_effects = get_tree().get_first_node_in_group(
			ComicEffectSystem.GROUP_COMIC_EFFECT_SYSTEM
		) as ComicEffectSystem
	if _comic_effects:
		_comic_effects.try_spawn(id, global_position, self)


## Cuts the stamina CEILING in CRITICAL rather than blocking running
## outright: a player who has lost the ability to run at all is caught in a
## spiral — weakened, unable to get away, weakened further. A quarter of the
## tank is enough for a short burst, not enough to sprint away clean.
## Sprinting is still refused separately (set_sprint_blocked) — the lowered
## ceiling on its own doesn't stop is_running_mode from reading as a sprint.
func _on_health_band_changed(band: HealthComponent.Band) -> void:
	if not stamina_manager:
		return
	if band == HealthComponent.Band.CRITICAL:
		stamina_manager.set_capacity_ratio(stamina_manager.critical_capacity_ratio)
		stamina_manager.set_sprint_blocked(true)
	else:
		stamina_manager.set_capacity_ratio(1.0)
		stamina_manager.set_sprint_blocked(false)


## --- Punch (COMBAT only) ---
## Only a raised-fists stance earns a punch — this is the action the stance
## exists for, in both view modes: TPS's mouse_left_button was already
## unclaimed outside COMBAT (see the connection comment in _ready()), and in
## ISOMETRIC, ClickToMoveSystem's own click handler reacts to the same
## signal but never conflicts (see that file's header). ISOMETRIC
## additionally faces the body to the click point first — TPS never needs
## this, _apply_direct_movement() already faces the camera every frame,
## camera and threat being the same direction there.
## Also requires standing still (speed <= punch_max_speed, checked against
## actual speed, not input intent): a punch played over locomotion has
## nothing to blend with (no layered upper-body mixing in this project yet)
## and reads as sliding. A moving click is ignored silently — there is no
## feedback system in this project to tell the player why, and this isn't
## the place to invent one.
##
## A punch resolves one of two ways, and BOTH are announced. It connects:
## take_hit() on the target, punch_landed, and (through IncidentRegistry's
## own subscription) a fact the city now holds. It misses: punch_missed, a
## signal that reaches whichever NPCs happened to be watching and dies with
## the frame — see that signal's own comment on why an air swing must never
## reach the registry.
##
## The swing also remembers who it was aimed at. _start_punch() resolves an
## INTENT target once, up front (_acquire_punch_intent()), and the body
## turns toward them for the length of the wind-up (_face_punch_intent()),
## because punch_hit_delay is long enough for a walking NPC to step out of
## a cone the player was correctly aiming at when they clicked. The hit
## check itself is untouched — this improves the odds of a fair punch
## landing, it does not guarantee one.
func _on_primary_click_pressed(screen_pos: Vector2) -> void:
	if PlayerState.mode != PlayerState.Mode.ON_FOOT:
		return
	if PlayerState.stance != PlayerState.Stance.COMBAT:
		return
	if _is_punching or not movement_enabled:
		return
	if speed > punch_max_speed:
		return
	if PlayerState.view_mode == PlayerState.ViewMode.ISOMETRIC:
		_face_punch_target(screen_pos)
	_start_punch()


## ISOMETRIC has no camera-driven facing to fall back on (unlike TPS, see
## _on_primary_click_pressed()'s comment), so without this the punch would
## fire in whatever direction the body last happened to face. Turns
## instantly rather than smoothed: punch_hit_delay already buffers the swing
## before _resolve_punch_hit() reads get_facing_direction(), and an instant
## turn guarantees that read matches the click, where a smoothed one could
## still be catching up at resolve time. Reuses ClickToMoveSystem's ground
## raycast (via _click_to_move_system, see that var's comment) instead of a
## second raycast from the camera.
func _face_punch_target(screen_pos: Vector2) -> void:
	if _click_to_move_system == null:
		return
	var point: Variant = _click_to_move_system.raycast_ground_point(screen_pos)
	if point == null:
		return

	var to_point: Vector3 = (point as Vector3) - global_position
	to_point.y = 0.0
	if to_point.length() < 0.001:
		return

	# Same convention as _handle_navigation()'s target_angle and
	# get_facing_direction(): atan2(x, z), +Z forward, not Godot's usual -Z.
	rotation.y = atan2(to_point.x, to_point.z)


func _start_punch() -> void:
	_is_punching = true
	_punch_timer = 0.0
	_punch_hit_resolved = false
	_acquire_punch_intent()
	set_movement_enabled(false)
	_animation_component.play_punch()


## Who this punch was thrown at, decided once, at the moment the button is
## accepted — before punch_hit_delay has had a chance to make the answer
## stale. Runs after _face_punch_target() in ISOMETRIC (see
## _on_primary_click_pressed()'s call order), so the search is already
## centred on the click direction there; in TPS the body is facing the
## camera and there is nothing to correct first.
func _acquire_punch_intent() -> void:
	var target := _find_punch_target(
		punch_reach * punch_intent_reach_multiplier, punch_intent_angle_deg
	)
	_punch_intent_id = target.get_instance_id() if target else 0


## Live NPC behind _punch_intent_id, or null once it is gone — a target that
## streamed out mid-swing simply stops being aimed at, it does not cancel
## the punch (the swing was already thrown).
func _get_punch_intent_target() -> NPCBase:
	if _punch_intent_id == 0 or not is_instance_id_valid(_punch_intent_id):
		return null
	return instance_from_id(_punch_intent_id) as NPCBase


## Turns the body toward the intent target while the swing winds up. Same
## atan2(x, z) convention as _face_punch_target()/get_facing_direction(),
## and the same Smoothing.damp_factor() form _face_camera() uses, so the
## rate means the same thing here as everywhere else. Safe to run in both
## view modes: movement is locked for the whole punch, so nothing else is
## writing rotation.y while this does.
func _face_punch_intent(delta: float) -> void:
	var target := _get_punch_intent_target()
	if target == null:
		return

	var to_target := target.global_position - global_position
	to_target.y = 0.0
	if to_target.length() < 0.001:
		return

	var target_angle := atan2(to_target.x, to_target.z)
	rotation.y = lerp_angle(
		rotation.y, target_angle, Smoothing.damp_factor(punch_intent_turn_smoothing, delta)
	)


## Called from _physics_process() even while movement is locked — see that
## function's own comment on why.
func _update_punch(delta: float) -> void:
	## True only on the very first call after _start_punch() — used below to
	## skip the completion check for one frame, see that branch's comment.
	var is_first_frame := _punch_timer <= 0.0
	_punch_timer += delta

	if not _punch_hit_resolved:
		## Wind-up only. Once the hit has resolved the swing is over as far
		## as aiming goes, and letting the body keep tracking would turn a
		## missed punch into a slow pirouette.
		_face_punch_intent(delta)

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
		_punch_intent_id = 0
		set_movement_enabled(true)


## Cone check against perceived NPCs (ActorBase.GROUP_PERCEIVED_ACTOR,
## filtered to NPCBase) rather than reusing PlayerFocusCast — see
## punch_reach's own comment for why that cast doesn't fit. Drones are in
## the same group but excluded here: they have no take_hit() (see
## npc_base.gd's own header on why that contract is NPC-only, not
## ActorBase-wide).
func _resolve_punch_hit() -> void:
	var target := _find_punch_target(punch_reach, punch_angle_deg)
	if target == null:
		## An air swing is still something a bystander can see, so it is
		## announced — but only as a signal, never through IncidentRegistry:
		## nothing happened that the city could have a record of.
		punch_missed.emit(global_position)
		return
	target.take_hit(global_position)
	punch_landed.emit(target.global_position)


## Nearest NPC inside a forward cone. Parameterised because the same search
## answers two different questions with two different tolerances: the hit
## check (punch_reach/punch_angle_deg, unchanged) and the wind-up's intent
## search (see _acquire_punch_intent()).
func _find_punch_target(reach: float, angle_deg: float) -> NPCBase:
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
		if dist > reach or dist < 0.001:
			continue

		var angle := rad_to_deg(facing.angle_to(to_target.normalized()))
		if angle > angle_deg * 0.5:
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


## --- Fall damage ---
## Checked every physics frame right after move_and_slide(), the only point
## where is_on_floor() reflects this frame's actual collision result.
## Landing is the not-on-floor -> on-floor transition, not a height
## threshold: height is unreliable across slopes, ledges and moving
## platforms, but the vertical speed at the moment of impact is not.
func _check_fall_damage() -> void:
	var landed: bool = not _was_on_floor and is_on_floor()
	_was_on_floor = is_on_floor()
	if landed:
		_apply_fall_damage(-_pre_move_vertical_speed)


## impact_speed is the downward speed at the moment of landing, already
## flipped positive. Damage grows quadratically between the two thresholds
## (a normalised [0,1] ratio, squared, times max_health) rather than
## linearly: an eight-metre fall should barely register, while the gap
## between fifteen and twenty metres should read as dramatically worse —
## matching how real fall lethality curves, not a straight line.
func _apply_fall_damage(impact_speed: float) -> void:
	if impact_speed < fall_damage_min_speed:
		return

	var ratio: float = clampf(
		(impact_speed - fall_damage_min_speed)
				/ (fall_damage_lethal_speed - fall_damage_min_speed),
		0.0, 1.0
	)
	var damage: float = ratio * ratio * _health.max_health
	var taken: float = _health.apply_damage(damage)
	if taken >= fall_fracture_damage:
		_health.add_condition(HealthComponent.Condition.FRACTURE)


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
	rotation.y = lerp_angle(rotation.y, _camera_yaw + PI, Smoothing.damp_factor(smoothing, delta))


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
