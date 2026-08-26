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
## Minimum time spent airborne before a landing can deal fall damage.
## Filters out brief floor-contact flicker on slopes (island heightmap).
## 0.15 s ≈ 0.2–0.3 m free fall at current gravity.
@export var fall_damage_min_air_time: float = 0.15

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
## Continuous time spent not on the floor. Reset on contact. Used to ignore
## brief air gaps on slopes that would otherwise register as landings.
var _air_time: float = 0.0

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

## The two places a picked-up item can end up. The player holds both because
## the ORDER between them — worn first, carried second — is a decision about
## this character's belongings, and neither component should have to know the
## other exists. See store_item().
@onready var _equipment: EquipmentComponent = $EquipmentComponent
@onready var _inventory: InventoryComponent = $InventoryComponent
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

	## Draw/holster and stance are one state, symmetric both ways (H5). The
	## player wires it because it owns the component and PlayerState is the
	## only thing allowed to change a stance — equipment knows nothing about
	## stances, and InputSystems knows nothing about equipment.
	##
	## No loop and no guard flag: set_stance() returns early on an unchanged
	## value and holster() returns early with empty hands, so
	## PEACE -> holster -> set_stance(PEACE) dies on the second hop.
	InputSystems.draw_holster_pressed.connect(_on_draw_holster_pressed)
	PlayerState.stance_changed.connect(_on_stance_changed_for_equipment)
	if _equipment:
		_equipment.drawn_changed.connect(_on_drawn_changed)

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


## --- Fall damage ---
## Checked every physics frame right after move_and_slide(), the only point
## where is_on_floor() reflects this frame's actual collision result.
## Landing is the not-on-floor -> on-floor transition, not a height
## threshold: height is unreliable across slopes, ledges and moving
## platforms, but the vertical speed at the moment of impact is not.
## Additionally requires a minimum airborne duration so brief floor-contact
## flicker on slopes (island heightmap) does not count as a fall.
func _check_fall_damage() -> void:
	var on_floor: bool = is_on_floor()
	if on_floor:
		if not _was_on_floor and _air_time >= fall_damage_min_air_time:
			_apply_fall_damage(-_pre_move_vertical_speed)
		_air_time = 0.0
	else:
		_air_time += get_physics_process_delta_time()
	_was_on_floor = on_floor


## Current horizontal speed as a 0..1 fraction of run_speed. Lets the camera
## react to how fast the character moves without knowing the balance numbers.
func get_speed_ratio() -> float:
	if run_speed <= 0.0:
		return 0.0
	return clampf(speed / get_current_max_speed(), 0.0, 1.0)

# --- rest of file unchanged ---
