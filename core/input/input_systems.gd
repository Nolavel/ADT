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
## A hold timer for Interact existed once, was removed as the wrong shape
## (holding R for ~1 s as a SEPARATE action), and comes back here in the
## shape the design settled on: same key, three edges, no interpretation.
##
## This relay reports WHEN and FOR HOW LONG, never "that was a tap" or "that
## counts as a hold" — the threshold belongs to whoever acts on it
## (HoverEntryTrigger owns its own interact_hold_time; InteractComponent
## treats a press as a press and has no threshold at all).
signal interact_pressed()
signal interact_held(duration: float)
signal interact_released(duration: float)

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

## --- Weapon reload (H6, docs/scope_horizon.md) ---
## The action has been bound to R since the input map was written and had no
## consumer at all until there was a magazine to refill. Relayed
## unconditionally like every other action here — player.gd decides whether
## anything is drawn, whether it feeds from a magazine, and whether that
## magazine has room.
signal weapon_reload_pressed()

## --- Key hints HUD toggle (H2, docs/scope_horizon.md) ---
signal key_hints_enabled_changed(enabled: bool)

## --- Lodging sleep-hour picker (H1 step 4, world/lodging/) ---
## Mouse wheel, one emit per tick, taken from the wheel EVENT rather than
## polled. It used to share both physical buttons with zoom_in/zoom_out,
## which is why every action here is matched with a separate `if` rather than
## an elif chain — the wheel is now the picker's alone (camera zoom went with
## the isometric camera on 2026-09-02) but the rule stands: one input can
## drive two actions and an elif would silently drop the second.
## Only consumer today is LodgingRoom's sleep-hour picker, while it's open.
signal lodging_hours_increase_pressed()
signal lodging_hours_decrease_pressed()

## ── Interact routing ──────────────────────────────────────────────────
## While a claim is held (player at a hover door or aboard one), interact
## goes straight to the claim's owner; NONE of the three signals above are
## emitted — InteractComponent is blind during that time. One owner makes
## the decision, instead of subscribers racing each other.
##
## The claim contract mirrors those signals, and a claimant implements as
## much of it as it needs:
##
##   on_interact_claimed()                  the key went down   (required)
##   on_interact_held(duration: float)      every frame it is down
##   on_interact_released(duration: float)  the key came up
##
## The last two are duck-typed through has_method(), so a claimant that only
## wants a press keeps working with the one method it always had.
var _interact_claimant: Node = null
## Seconds the interact key has been down, 0 while it is up.
var _interact_duration: float = 0.0
var _interact_active: bool = false

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

const RUN_TRIGGER_TIME: float = 0.5

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
	_apply_mouse_mode()

## ============================================
## WHERE EDGES COME FROM — and why this file stopped polling for them
## ============================================
## Every discrete action here used to be read as Input.is_action_just_pressed()
## inside _physics_process(). That is Godot's best-known input trap:
## "just pressed" is true for exactly one IDLE frame, and _physics_process does
## not run once per idle frame. As soon as the render rate and the physics tick
## drift apart, an edge falls entirely between two ticks and is never seen.
## Reload (R) is where it got noticed — it took three or four presses to fire
## once — but it was dropping presses for all twenty discrete actions equally,
## and no amount of buffering downstream can recover a press this file never
## observed.
##
## The rule now:
##
##   discrete edge   -> read from the InputEvent. Never polled.
##   held state/axis -> still Input.is_action_pressed() in _physics_process.
##                      A LEVEL read is frame-rate independent and correct.
##   hold duration   -> still accumulated in _physics_process, but started and
##                      stopped by events.
##
## Keyboard actions live in _unhandled_input() so the GUI keeps first refusal —
## that is where "pause" has always been, and it has never lost a press.
## Mouse buttons live in _input() instead: polling ignored GUI consumption
## entirely, so routing clicks behind the GUI would quietly change which ones
## reach gameplay. The single place that does consume a click is
## DynamicCursorUI over a 3D button, which is exactly where swallowing it is
## the intended behaviour.
##
## Actions matched with separate `if`s, never an elif chain: one physical input
## can drive two actions — wheel up drove both zoom_out and lodging_hours_up
## until zoom was removed — and polling used to fire both. An elif would
## silently drop the second.
## ============================================

## ── Edge latches ──────────────────────────────────────────────────────
## The QUERY METHODS at the bottom of this file cannot become signals: their
## callers poll inside their own update(delta) (the camera component) or their
## own physics frame (player.gd's jump). They are served from here instead —
## an event records the edge, a poll reads it back.
##
## action -> the physics frame the edge was recorded in. An entry survives
## until a LATER physics frame begins, so it is visible to every consumer
## polling during the one frame that follows the event, and to none after it.
##
## Expiry happens at the TOP of _physics_process, and that is load-bearing:
## autoloads run their physics callback before scene nodes do, so clearing at
## the bottom would erase the latch before camera_follow.gd ever polled it.
var _edge_frames: Dictionary = {}

## Discrete actions that are polled rather than relayed as a signal. Kept as
## data so the latch loop has one place to grow — adding an action here is the
## whole of wiring it up. Wheel actions are not in this list: they arrive as
## mouse events and are latched in _handle_mouse_button_event().
const POLLED_EDGE_ACTIONS: Array[StringName] = [
	&"jump",
	&"toggle_view",
	&"lock_on",
	&"switch_shoulder",
	&"toggle_stance",
]


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if PlayerState.mode != PlayerState.Mode.MENU:
			_mouse_look_delta += event.relative * MOUSE_SENSITIVITY
		return
	if event is InputEventMouseButton:
		_handle_mouse_button_event(event)


## Escape ("pause") works regardless of the current pause state or mode. The
## decision of what to do with this signal belongs to MenuSystem; InputSystems
## only notifies. Everything below it is the same relay this file has always
## done, moved off the polling path.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		pause_pressed.emit()
		get_viewport().set_input_as_handled()
		return

	# --- Interact: two edges here, the duration between them in physics ---
	if event.is_action_pressed("interact"):
		_begin_interact()
	if event.is_action_released("interact"):
		_end_interact()

	# --- UI hotkeys ---
	if event.is_action_pressed("status"):
		status_pressed.emit()
	if event.is_action_pressed("inventory"):
		inventory_pressed.emit()
	if event.is_action_pressed("map"):
		map_pressed.emit()
	if event.is_action_pressed("toggle_stream_debug"):
		stream_debug_toggled.emit()
	if event.is_action_pressed("toggle_perception_debug"):
		perception_debug_toggled.emit()

	# --- Debug save/load — see debug_save_pressed's own comment ---
	if event.is_action_pressed("debug_save"):
		debug_save_pressed.emit()
	if event.is_action_pressed("debug_load"):
		debug_load_pressed.emit()

	# --- Draw / holster and reload — see their signals' own comments ---
	if event.is_action_pressed("draw_holster"):
		draw_holster_pressed.emit()
	if event.is_action_pressed("weapon_reload"):
		weapon_reload_pressed.emit()

	# --- Key hints HUD switch — see key_hints_enabled's own comment ---
	if event.is_action_pressed("toggle_key_hints"):
		key_hints_enabled = not key_hints_enabled

	_latch_polled_edges(event)


## Mouse buttons and the wheel. Reached from _input(), ahead of the GUI, for
## the reason given in the header block above.
func _handle_mouse_button_event(event: InputEvent) -> void:
	if event.is_action_pressed("mouse_left_button"):
		primary_click_pressed.emit(get_viewport().get_mouse_position())
	if event.is_action_released("mouse_left_button"):
		primary_click_released.emit(get_viewport().get_mouse_position())

	if event.is_action_pressed("mouse_right_button"):
		_begin_secondary_click()
	if event.is_action_released("mouse_right_button"):
		_end_secondary_click()

	if event.is_action_pressed("lodging_hours_up"):
		lodging_hours_increase_pressed.emit()
	if event.is_action_pressed("lodging_hours_down"):
		lodging_hours_decrease_pressed.emit()


func _physics_process(delta: float) -> void:
	_expire_edges()

	if PlayerState.mode == PlayerState.Mode.MENU:
		_frame_look_delta = Vector2.ZERO
		_mouse_look_delta = Vector2.ZERO
	else:
		_frame_look_delta = _mouse_look_delta
		_mouse_look_delta = Vector2.ZERO

	# What is left in the physics frame is exactly what belongs there: two
	# hold timers, and a toggle read back from its latch.
	_tick_interact(delta)
	_tick_secondary_click(delta)
	_handle_stance_toggle()


## ============================================
## EDGE LATCH — see _edge_frames' own comment for the frame arithmetic.
## ============================================
func _latch_edge(action: StringName) -> void:
	_edge_frames[action] = Engine.get_physics_frames()


func _latch_polled_edges(event: InputEvent) -> void:
	for action in POLLED_EDGE_ACTIONS:
		if event.is_action_pressed(action):
			_latch_edge(action)


func _expire_edges() -> void:
	if _edge_frames.is_empty():
		return
	var current: int = Engine.get_physics_frames()
	# keys() returns a copy, so erasing inside the loop is safe here.
	for action in _edge_frames.keys():
		if int(_edge_frames[action]) < current:
			_edge_frames.erase(action)


func _has_edge(action: StringName) -> bool:
	return _edge_frames.has(action)


## ============================================
## MOUSE MODE — cursor visibility/capture is a physical Input.* effect, so it
## is applied here, driven by PlayerState.mode rather than read from it.
## ============================================
func _on_player_mode_changed(_old_mode: PlayerState.Mode, _new_mode: PlayerState.Mode) -> void:
	_apply_mouse_mode()

func _apply_mouse_mode() -> void:
	if PlayerState.mode == PlayerState.Mode.MENU:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	## Captured in every non-menu mode. The visible-cursor branch existed for
	## the isometric camera's click-to-move and went with it on 2026-09-02 —
	## with one camera there is no view in which the pointer is the input.
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## ============================================
## INTERACT
## ============================================
## Same shape as the secondary click: press / held-with-duration /
## release-with-duration, and the duration is the only thing measured. Both
## edges come from _unhandled_input(); only the duration is accumulated here.
func _begin_interact() -> void:
	_interact_duration = 0.0
	_interact_active = true
	if is_instance_valid(_interact_claimant):
		_interact_claimant.on_interact_claimed()
	else:
		interact_pressed.emit()


func _end_interact() -> void:
	if not _interact_active:
		return
	if is_instance_valid(_interact_claimant):
		if _interact_claimant.has_method(&"on_interact_released"):
			_interact_claimant.on_interact_released(_interact_duration)
	else:
		interact_released.emit(_interact_duration)
	_interact_active = false
	_interact_duration = 0.0


func _tick_interact(delta: float) -> void:
	if not _interact_active:
		return
	# A LEVEL read, deliberately, and the one place polling is still right: if
	# the release event never arrives — a Control ate it, the window lost focus
	# mid-press, the claimant was freed — the key would otherwise read as held
	# forever. The edge that STARTS a hold is an event; the one that ends it
	# has this net under it.
	if not Input.is_action_pressed("interact"):
		_end_interact()
		return

	_interact_duration += delta
	if is_instance_valid(_interact_claimant):
		if _interact_claimant.has_method(&"on_interact_held"):
			_interact_claimant.on_interact_held(_interact_duration)
	else:
		interact_held.emit(_interact_duration)


func claim_interact(claimant: Node) -> void:
	_interact_claimant = claimant

func release_interact(claimant: Node) -> void:
	if _interact_claimant == claimant:
		_interact_claimant = null


## Whether someone currently owns the interact key. A state read, the same
## category as is_jump_just_pressed() — it interprets nothing. Exists so
## InteractComponent can keep its own prompt off the screen while the claim
## owner is putting one there.
func is_interact_claimed() -> bool:
	return is_instance_valid(_interact_claimant)


## ============================================
## MOUSE CLICKS
## ============================================
## The primary click is a pure relay and lives entirely in
## _handle_mouse_button_event(). The secondary one measures a hold, so it is
## split the same way interact is: edges from the event, duration from physics.
func _begin_secondary_click() -> void:
	_secondary_click_duration = 0.0
	_secondary_click_active = true
	secondary_click_pressed.emit(get_viewport().get_mouse_position())


func _end_secondary_click() -> void:
	if not _secondary_click_active:
		return
	_secondary_click_active = false
	_secondary_click_duration = 0.0
	secondary_click_released.emit(get_viewport().get_mouse_position())


func _tick_secondary_click(delta: float) -> void:
	if not _secondary_click_active:
		return
	# Same safety net, same reason, as _tick_interact().
	if not Input.is_action_pressed("mouse_right_button"):
		_end_secondary_click()
		return

	_secondary_click_duration += delta
	secondary_click_held.emit(get_viewport().get_mouse_position(), _secondary_click_duration)


## ============================================
## TABS KEY — retired 2026-08-26. The action, its tap/hold timer and the
## tabs_key_tapped/tabs_key_held signals are gone: Tab now carries
## draw_holster (see input_map.md). Nothing ever subscribed to either
## signal, and both features they were emitted for — the notifier and the
## status camera — were never built, so this relayed a press to no one for
## its whole life. The timer pattern itself survives in git history if the
## notifier wants it on a different key later.
## ============================================

## ============================================
## UI HOTKEYS, DEBUG SAVE/LOAD, DRAW/HOLSTER, RELOAD, LODGING WHEEL and the
## KEY HINTS SWITCH used to have a _handle_* function each, all of them one
## `if Input.is_action_just_pressed(...)` deep and all of them polled. They are
## plain relays with nothing to time, so they now sit inline in
## _unhandled_input() / _handle_mouse_button_event() above — the wrapper only
## ever existed to give the polling loop something to call. The reasoning for
## each still lives on its signal's own declaration at the top of this file.
## ============================================


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
##
## The *_just_pressed ones are answered from the edge latch, NOT from
## Input.is_action_just_pressed(): a poll of Godot's own edge is exactly what
## was losing presses. The held/axis ones below are level reads and stay as
## direct Input.* calls, which is what they should have been all along.
## ============================================

## --- Camera (on_foot_camera_component.gd) ---
func is_toggle_view_just_pressed() -> bool:
	return _has_edge(&"toggle_view")

## Q/E are a HELD lean, so these are level reads and there is deliberately no
## *_just_pressed pair beside them: the discrete forms existed for the
## four-position orbit those keys used to step, and both the orbit and the
## isometric camera it belonged to were removed on 2026-09-02.
func is_lean_left_pressed() -> bool:
	return Input.is_action_pressed("lean_left")

func is_lean_right_pressed() -> bool:
	return Input.is_action_pressed("lean_right")


## --- Jump (player.gd + dynamic_cursor_ui.gd) ---
func is_jump_just_pressed() -> bool:
	return _has_edge(&"jump")

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
	return _has_edge(&"lock_on")

func is_switch_shoulder_just_pressed() -> bool:
	return _has_edge(&"switch_shoulder")


## --- Aim (TPSMovementSystem) ---
## mouse_right_button is unclaimed by anything else on foot — the click
## handler that used to share it went with the isometric camera on
## 2026-09-02. A raw held query, not a signal, since
## aiming is a hold like sprint — PlayerState.set_aiming() decides what the
## press means (and clamps it to Stance.COMBAT + Mode.ON_FOOT) exactly the
## way is_sprint_held()'s caller decides what sprint means.
func is_aim_pressed() -> bool:
	return Input.is_action_pressed("mouse_right_button")


## --- Stance ---
func is_stance_toggle_just_pressed() -> bool:
	return _has_edge(&"toggle_stance")


## Hover's vertical axis: +1 up (hover_up), -1 down (hover_down).
func get_hover_vertical_axis() -> float:
	return Input.get_axis("hover_down", "hover_up")
	
## --- Mouse look (TPS/FPS camera control) ---
func get_look_delta() -> Vector2:
	return _frame_look_delta
