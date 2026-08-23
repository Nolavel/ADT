# =============================================================================
# InputSystems.gd — autoload, extends Node.
#
# Single responsibility: turn Godot's physical Input into signals.
# NO game logic belongs here:
#   - it doesn't decide what a press means (that's the subscriber's job);
#   - it doesn't hold the player's mode (source of truth is PlayerState.mode/view_mode);
#   - it doesn't raycast, move the player, or open UI.
#
# Who subscribes to what, and when, is decided by the subscriber itself,
# reacting to PlayerState.mode_changed / view_mode_changed. InputSystems
# emits its signals unconditionally, always.
# =============================================================================
extends Node

## --- Mouse click (raw events, no interpretation of "what it means") ---
signal primary_click_pressed(screen_pos: Vector2)
signal primary_click_released(screen_pos: Vector2)

signal secondary_click_pressed(screen_pos: Vector2)
signal secondary_click_held(screen_pos: Vector2, duration: float)
signal secondary_click_released(screen_pos: Vector2)



## --- Interact ---
## The hold-timer prototype for Interact was removed (it wasn't actually
## what was needed — holding R for ~1s as a separate action).
## For now this just forwards just_pressed. Hold behaviour comes back as
## its own task once the final design is settled.
signal interact_pressed()

## --- UI hotkeys (no consumers yet — just relayed) ---
signal pause_pressed()
signal status_pressed()
signal inventory_pressed()
signal crafting_pressed()
signal map_pressed()
## Toggle for the streaming debug panel (action "toggle_stream_debug").
signal stream_debug_toggled()
## Toggle for the NPC perception debug panel (action "toggle_perception_debug").
signal perception_debug_toggled()

## --- Debug save/load (H1, docs/scope_horizon.md) ---
## A permanent developer tool, not a stand-in for the in-fiction save
## mechanism (sleeping in a LodgingRoom) — both remain after that lands.
signal debug_save_pressed()
signal debug_load_pressed()

## --- Draw / holster (H5, docs/scope_horizon.md) ---
## Its own action rather than a side effect of toggle_stance: hanging the
## draw off the stance key would mean entering COMBAT auto-draws, and raised
## fists are already a statement on their own. Relayed unconditionally like
## every other action here — EquipmentComponent decides whether there is
## anything to draw.
signal draw_holster_pressed()

## --- Key hints HUD toggle (H2, docs/scope_horizon.md) ---
signal key_hints_enabled_changed(enabled: bool)

## --- Lodging sleep-hour picker (H1 step 4, world/lodging/) ---
## Mouse wheel, read as discrete ticks via is_action_just_released() — same
## convention zoom_in/zoom_out already use for the same physical input, but
## a separate action rather than reusing those: they mean "camera zoom"
## everywhere else they're read, and overloading them for an unrelated
## "adjust a number" UI would make both meanings harder to reason about.
## Only consumer today is LodgingRoom's sleep-hour picker, while it's open.
signal lodging_hours_increase_pressed()
signal lodging_hours_decrease_pressed()

## Tap/hold on "toggle_tabs" — press timing is a property of the physical
## input, so the timer lives here, not in the consumer.
signal tabs_key_tapped()
signal tabs_key_held()

## ── Interact routing ──────────────────────────────────────────────────
## While a claim is held (player at a hover door or aboard one), interact
## goes straight to the claim's owner; the interact_pressed signal is NOT
## emitted — InteractComponent is blind during that time. One owner makes
## the decision, instead of subscribers racing each other.
var _interact_claimant: Node = null

## ── Key hints HUD switch (H2, docs/scope_horizon.md) ──────────────────
## Deliberately placed on InputSystems rather than on KeyHintsPanel itself,
## even though this file's own header says it carries no game logic and
## isn't a UI concern: InputSystems is the only system that actually knows
## about keys as physical things, so "should the panel explaining the keys
## be visible" is gated from the one place already reading Input.* rather
## than duplicating that knowledge on the panel. This DOES introduce a
## UI → input dependency that didn't exist before (KeyHintsPanel now reads
## an InputSystems field/signal, where previously nothing in ui/hud/ needed
## InputSystems at all) — accepted as a deliberate exception, not a pattern
## to repeat for other UI toggles without the same reasoning applying.
var key_hints_enabled: bool = true:
	set(value):
		if value == key_hints_enabled:
			return
		key_hints_enabled = value
		key_hints_enabled_changed.emit(key_hints_enabled)

const TABS_HOLD_TIME: float = 0.5
const RUN_TRIGGER_TIME: float = 0.5

var _tabs_pressed_time: float = 0.0
var _tabs_pressing: bool = false

var _secondary_click_duration: float = 0.0
var _secondary_click_active: bool = false

# --- Mouse Look ---
## Sensitivity baked in here so consumers get camera-ready deltas.
const MOUSE_SENSITIVITY: float = 0.003

var _mouse_look_delta: Vector2 = Vector2.ZERO
var _frame_look_delta: Vector2 = Vector2.ZERO


func _ready() -> void:
	# ALWAYS — otherwise after PlayerState.open_menu() (get_tree().paused = true)
	# this autoload stops receiving _unhandled_input and Escape stops working.
	process_mode = Node.PROCESS_MODE_ALWAYS
	PlayerState.mode_changed.connect(_on_player_mode_changed)
	PlayerState.view_mode_changed.connect(_on_player_view_mode_changed)
	_apply_mouse_mode()

func _input(event: InputEvent) -> void:
	if PlayerState.mode == PlayerState.Mode.MENU:
		return
	if event is InputEventMouseMotion:
		_mouse_look_delta += event.relative * MOUSE_SENSITIVITY

## Escape ("pause") is caught separately from physics — works regardless of
## the current pause state or mode. The decision of what to do with this
## signal belongs to MenuSystem; InputSystems only notifies.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		pause_pressed.emit()
		get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	if PlayerState.mode == PlayerState.Mode.MENU:
		_frame_look_delta = Vector2.ZERO
		_mouse_look_delta = Vector2.ZERO
	else:
		_frame_look_delta = _mouse_look_delta
		_mouse_look_delta = Vector2.ZERO
	
	_handle_interact()
	_handle_primary_click()
	_handle_secondary_click(delta)
	_handle_tabs_key(delta)
	_handle_ui_hotkeys()
	_handle_stance_toggle()
	_handle_debug_save_load()
	_handle_draw_holster()
	_handle_lodging_hours()
	_handle_key_hints_toggle()


## ============================================
## MOUSE MODE — cursor visibility/capture is a physical Input.* effect, so it
## is applied here, driven by PlayerState.mode/view_mode rather than read from them.
## ============================================
func _on_player_mode_changed(_old_mode: PlayerState.Mode, _new_mode: PlayerState.Mode) -> void:
	_apply_mouse_mode()

func _on_player_view_mode_changed(_old_view: PlayerState.ViewMode, _new_view: PlayerState.ViewMode) -> void:
	_apply_mouse_mode()

func _apply_mouse_mode() -> void:
	if PlayerState.mode == PlayerState.Mode.MENU:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if PlayerState.view_mode == PlayerState.ViewMode.TPS \
			else Input.MOUSE_MODE_VISIBLE


## ============================================
## INTERACT
## ============================================
func _handle_interact() -> void:
	if Input.is_action_just_pressed("interact"):
		if is_instance_valid(_interact_claimant):
			_interact_claimant.on_interact_claimed()
		else:
			interact_pressed.emit()
		
func claim_interact(claimant: Node) -> void:
	_interact_claimant = claimant

func release_interact(claimant: Node) -> void:
	if _interact_claimant == claimant:
		_interact_claimant = null


## ============================================
## MOUSE CLICKS
## ============================================
func _handle_primary_click() -> void:
	if Input.is_action_just_pressed("mouse_left_button"):
		primary_click_pressed.emit(get_viewport().get_mouse_position())
	if Input.is_action_just_released("mouse_left_button"):
		primary_click_released.emit(get_viewport().get_mouse_position())


func _handle_secondary_click(delta: float) -> void:
	if Input.is_action_just_pressed("mouse_right_button"):
		_secondary_click_duration = 0.0
		_secondary_click_active = true
		secondary_click_pressed.emit(get_viewport().get_mouse_position())

	if Input.is_action_pressed("mouse_right_button") and _secondary_click_active:
		_secondary_click_duration += delta
		secondary_click_held.emit(get_viewport().get_mouse_position(), _secondary_click_duration)

	if Input.is_action_just_released("mouse_right_button"):
		_secondary_click_active = false
		_secondary_click_duration = 0.0
		secondary_click_released.emit(get_viewport().get_mouse_position())


## ============================================
## TABS KEY (tap = notifier, hold = status camera) — the consumer
## interprets tap/hold itself; we just tell them apart by timing.
## ============================================
func _handle_tabs_key(delta: float) -> void:
	if Input.is_action_just_pressed("toggle_tabs"):
		_tabs_pressed_time = 0.0
		_tabs_pressing = true

	if _tabs_pressing:
		_tabs_pressed_time += delta
		if Input.is_action_just_released("toggle_tabs"):
			if _tabs_pressed_time < TABS_HOLD_TIME:
				tabs_key_tapped.emit()
			else:
				tabs_key_held.emit()
			_tabs_pressing = false


## ============================================
## OTHER UI HOTKEYS
## ============================================
func _handle_ui_hotkeys() -> void:
	if Input.is_action_just_pressed("status"):
		status_pressed.emit()
	if Input.is_action_just_pressed("inventory"):
		inventory_pressed.emit()
	if Input.is_action_just_pressed("map"):
		map_pressed.emit()
	if Input.is_action_just_pressed("toggle_stream_debug"):
		stream_debug_toggled.emit()
	if Input.is_action_just_pressed("toggle_perception_debug"):
		perception_debug_toggled.emit()


## ============================================
## DEBUG SAVE/LOAD — see debug_save_pressed's own comment. Relayed
## unconditionally, same as every other action here; SaveSystem does not
## gate on PlayerState.mode today.
## ============================================
func _handle_debug_save_load() -> void:
	if Input.is_action_just_pressed("debug_save"):
		debug_save_pressed.emit()
	if Input.is_action_just_pressed("debug_load"):
		debug_load_pressed.emit()


## ============================================
## DRAW / HOLSTER — see draw_holster_pressed's own comment.
## ============================================
func _handle_draw_holster() -> void:
	if Input.is_action_just_pressed("draw_holster"):
		draw_holster_pressed.emit()


## ============================================
## LODGING HOURS — mouse wheel, relayed unconditionally like every other
## action here; LodgingRoom decides whether a picker is actually open.
## just_released, not just_pressed: Godot delivers a wheel tick as a
## synthetic press+release in the same frame, and is_action_just_released()
## is the convention zoom_in/zoom_out already established for reading it.
## ============================================
func _handle_lodging_hours() -> void:
	if Input.is_action_just_released("lodging_hours_up"):
		lodging_hours_increase_pressed.emit()
	if Input.is_action_just_released("lodging_hours_down"):
		lodging_hours_decrease_pressed.emit()


## ============================================
## KEY HINTS HUD TOGGLE — see key_hints_enabled's own comment for why this
## switch lives here instead of on KeyHintsPanel.
## ============================================
func _handle_key_hints_toggle() -> void:
	if Input.is_action_just_pressed("toggle_key_hints"):
		key_hints_enabled = not key_hints_enabled


## ============================================
## STANCE
## Deliberate exception to this file's own "no game logic" rule: for every
## other action here, the interpretation of what a press MEANS lives in a
## subscriber (player.gd's jump handler, MenuSystem, the camera's lock-on
## call, ...). A stance toggle has no branching consequence to interpret —
## it is just "flip the one enum PlayerState already owns" — so this flips
## it directly instead of adding a subscriber whose only job would be
## "read this bool and toggle it." is_stance_toggle_just_pressed() is still
## exposed below for anything else that wants to react to the press itself
## (a UI hint, say) without re-deciding the toggle.
## ============================================
func _handle_stance_toggle() -> void:
	if not is_stance_toggle_just_pressed():
		return
	if PlayerState.mode != PlayerState.Mode.ON_FOOT:
		return
	var target_stance := PlayerState.Stance.PEACE if PlayerState.stance == PlayerState.Stance.COMBAT \
			else PlayerState.Stance.COMBAT
	PlayerState.set_stance(target_stance)


## ============================================
## QUERY METHODS — for places where the signal model doesn't fit directly
## (the camera reads input inside its own update(delta), driven by its host
## camera_follow.gd, not InputSystems' physics frame; WASD/Shift are
## per-frame held state, not a discrete event). These places used to call
## Input.* directly — now every Input.* call physically happens only here,
## in InputSystems, and consumers call these wrappers instead.
## ============================================

## --- Camera (on_foot_camera_component.gd) ---
func is_toggle_follow_just_pressed() -> bool:
	return Input.is_action_just_pressed("toggle_follow")

func is_toggle_view_just_pressed() -> bool:
	return Input.is_action_just_pressed("toggle_view")

func is_lean_left_just_pressed() -> bool:
	return Input.is_action_just_pressed("lean_left")

func is_lean_right_just_pressed() -> bool:
	return Input.is_action_just_pressed("lean_right")

func is_zoom_in_just_released() -> bool:
	return Input.is_action_just_released("zoom_in")

func is_zoom_out_just_released() -> bool:
	return Input.is_action_just_released("zoom_out")


## --- Jump (player.gd + dynamic_cursor_ui.gd) ---
func is_jump_just_pressed() -> bool:
	return Input.is_action_just_pressed("jump")

func is_jump_held() -> bool:
	return Input.is_action_pressed("jump")


## --- Move axis (tps_movement_system.gd, input_hover_controller.gd) ---
## Godot's own Input.get_vector() convention: x = right (+1), y follows the
## engine's screen-space Y, so W/move_forward reads as -1, not +1. Any
## consumer that wants "+Y = forward" (HoverBase.set_move_intent() does)
## must flip y itself, at the call site, with a comment saying why — do not
## add a second axis method with the sign pre-flipped. That's what used to
## exist here (get_move_vector()) and it was a trap: two near-identical
## methods whose only difference was an inverted y, each with exactly one
## caller, so nothing ever exercised the mismatch until a third caller
## picked the wrong one.
func get_move_axis() -> Vector2:
	return Input.get_vector("move_left", "move_right", "move_forward", "move_backward")

func is_sprint_held() -> bool:
	return Input.is_action_pressed("sprint")

func is_lock_on_just_pressed() -> bool:
	return Input.is_action_just_pressed("lock_on")

func is_switch_shoulder_just_pressed() -> bool:
	return Input.is_action_just_pressed("switch_shoulder")


## --- Aim (TPSMovementSystem) ---
## mouse_right_button is otherwise unclaimed in TPS: ClickToMoveSystem reads
## the same action for click-to-move, but self-gates to ON_FOOT + ISOMETRIC,
## so it never reacts to it here. A raw held query, not a signal, since
## aiming is a hold like sprint — PlayerState.set_aiming() decides what the
## press means (and clamps it to Stance.COMBAT + Mode.ON_FOOT) exactly the
## way is_sprint_held()'s caller decides what sprint means.
func is_aim_pressed() -> bool:
	return Input.is_action_pressed("mouse_right_button")


## --- Stance ---
func is_stance_toggle_just_pressed() -> bool:
	return Input.is_action_just_pressed("toggle_stance")


## Hover's vertical axis: +1 up (hover_up), -1 down (hover_down).
func get_hover_vertical_axis() -> float:
	return Input.get_axis("hover_down", "hover_up")
	
## --- Mouse look (TPS/FPS camera control) ---
func get_look_delta() -> Vector2:
	return _frame_look_delta
