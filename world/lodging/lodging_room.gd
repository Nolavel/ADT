# =============================================================================
# lodging_room.gd — LodgingRoom, an ordinary scene Stan places by hand into
# whichever streamed block he chooses (never instanced by any of world.gd's
# three declarative lists, and never should be — see world.gd's own header
# on what those lists are for).
#
# "Lodging", not safehouse or home — nothing in Blackrock belongs to the
# player, and the class name should not imply otherwise. Same convention as
# Hover* over Vehicle*: the word sets the expectation for whoever reads it
# next.
#
# This is the in-fiction save point H1 (docs/scope_horizon.md) exists to
# prove out — a debug keybind (SaveSystem's K/L) proves the plumbing; this
# proves the contract is worth having. The room itself knows nothing about
# save FORMAT — it only calls three things, in this order, once the player
# confirms a sleep: advance GameClockSystem, tell LodgingSystem what
# happened, ask SaveSystem to write. Three separate systems making three
# separate decisions; this file is only the place that sequences the calls,
# same one-way-dependency shape LodgingSystem's own header describes.
#
# A static scene instance dropped anywhere in the tree never receives a
# WorldContext the way WORLD_SYSTEM_SCRIPTS entries do — same situation
# PatrolDroneController is in, and the same fix: GameClockSystem,
# LodgingSystem and SaveSystem are each resolved via
# get_tree().get_first_node_in_group() against a lookup group each of them
# carries (GROUP_GAME_CLOCK / GROUP_LODGING_SYSTEM / GROUP_SAVE_SYSTEM),
# retried every _process() until all three succeed, exactly like
# PatrolDroneController's _try_resolve_incident_registry().
#
# An earlier version of this file assumed a single _ready() attempt was
# enough, on the theory that this scene "only ever exists inside streamed
# content, which loads after every WORLD_SYSTEM_SCRIPTS entry already
# exists." That assumption depended on WHERE the scene is placed, and this
# scene has no control over that — Stan's own first placement put it
# directly in world.tscn (see that file's LodgingRoom instance), not inside
# streamed content, and Godot calls _ready() bottom-up as the tree is built:
# a statically-placed child's _ready() fires during World's own tree-entry
# pass, before World._ready() even runs — which itself awaits a process
# frame before _init_world() creates any WORLD_SYSTEM_SCRIPTS entry at all
# (see world.gd). All three resolves failed for exactly this reason, not a
# hypothetical. This file makes no assumption about placement anymore: the
# retry is what makes correctness independent of where Stan puts the scene,
# streamed block or not.
#
# A single push_warning fires if systems_search_timeout passes with any of
# the three still unresolved, once per instance, not every frame — silence
# here would mean a room that quietly can never be slept in, with nothing
# in the log to explain why.
#
# BedPoint is an ordinary InteractableObject, InteractionType.BUTTON,
# through the same InteractComponent path every other interactable already
# uses — see interact_component.gd's own comment on _activate_button(),
# previously an empty stub with nowhere to route to. Sleep duration is
# chosen, not fixed: first interact opens a 1..8 hour picker, mouse wheel
# adjusts it, second interact confirms, the existing pause/cancel key backs
# out — no second input path for beds.
#
# Deliberately NOT wired to HealthComponent or any other recovery — this
# task's brief calls it a foundation, not the feature: the slept(room_id,
# hours) signal is the seam a future health/hunger pass subscribes to, not
# a subscription this file makes on their behalf. Writing a stub method for
# "future health recovery" would be exactly the kind of unbuilt scaffolding
# CONTRIBUTING.md warns against — the signal alone is the whole contract.
# =============================================================================
extends Node3D
class_name LodgingRoom

## Emitted once, right after a confirmed sleep advances the clock — hours is
## the chosen duration (not the wake time; GameClockSystem.total_game_hours
## after the jump is that). Nothing subscribes to this today; it exists so a
## future health/hunger recovery pass has somewhere to connect without this
## file needing to know that consumer exists.
signal slept(room_id: StringName, hours: float)

## Stable, authored id — same convention as ActorBase.actor_id and
## BlockBase.id, never derived from this node's path in the tree. Empty by
## default; _ready() warns if left unset, the same way ActorBase does,
## since an unauthored room_id means LodgingSystem's record for this room
## can never be found again after a reload.
@export var room_id: StringName = &""
## Seconds to keep retrying the three system lookups before giving up and
## warning once — see the file header on why this can't be a single
## _ready() call. Every WORLD_SYSTEM_SCRIPTS entry should exist within the
## first couple of frames after World starts (or immediately, for a scene
## that streams/instances in later, well after that); a wait this long past
## either means something is actually wrong, not a startup race.
@export var systems_search_timeout: float = 5.0

const MIN_SLEEP_HOURS: int = 1
const MAX_SLEEP_HOURS: int = 8
## Starting value when the picker opens — the middle of the range would
## also be defensible; 8 (the maximum, "sleep till you're done") was chosen
## as the more legible default for a first-time player scrolling DOWN to
## commit less time, rather than having to scroll up from a low number to
## reach a meaningful sleep. A feel value, not derived from anything.
const DEFAULT_SLEEP_HOURS: int = 8
## Seconds a refusal/cancel message stays on screen before the label hides
## itself again.
const MESSAGE_DISPLAY_TIME: float = 2.5

@onready var _presence_area: Area3D = $PresenceArea
@onready var _bed_point: InteractableObject = $BedPoint
## Not in the brief's own node diagram — added because "the selected hour
## count is visible on screen" and "a refusal is a message, not a silent
## failure" are both explicit requirements, and no reusable HUD/toast
## system exists anywhere in this project to satisfy them without one (see
## this session's own report). World-space Label3D, not a CanvasLayer/UI
## scene: keeps this room fully self-contained — Stan places the scene and
## it works, with no separate WORLD_UI_SCENES registration in world.gd
## needed, matching "Stan places it manually" for the rest of the scene.
@onready var _hour_label: Label3D = $HourLabel

## Resolved lazily via a group lookup, retried from _process() until it
## succeeds — see the file header on why this can't be a single _ready()
## call. Null until then.
var _game_clock: GameClockSystem = null
var _lodging_system: LodgingSystem = null
var _save_system: SaveSystem = null
## Seconds spent so far retrying the lookups — compared against
## systems_search_timeout to decide when to warn.
var _systems_search_time: float = 0.0
## Set once the timeout warning has fired, so it fires exactly once per
## instance instead of every frame the systems stay unresolved.
var _warned_missing_systems: bool = false

## True while the player's own CharacterBody3D overlaps PresenceArea — the
## ONLY thing PresenceArea's signals are used for; no other logic reads the
## area directly.
var _player_inside: bool = false

## True while the hour picker is open (after a first BedPoint interact,
## before a confirming second one or a cancel).
var _selecting: bool = false
var _selected_hours: int = DEFAULT_SLEEP_HOURS


func _ready() -> void:
	if room_id == &"":
		push_warning("[LodgingRoom] %s: room_id is unset — LodgingSystem will never find this room's record again after a reload" % name)

	_presence_area.body_entered.connect(_on_presence_area_body_entered)
	_presence_area.body_exited.connect(_on_presence_area_body_exited)
	_bed_point.activated.connect(_on_bed_activated)

	InputSystems.lodging_hours_increase_pressed.connect(_on_hours_increase_pressed)
	InputSystems.lodging_hours_decrease_pressed.connect(_on_hours_decrease_pressed)
	InputSystems.pause_pressed.connect(_on_pause_pressed)
	PlayerState.stance_changed.connect(_on_stance_changed)

	_hour_label.visible = false

	## Very likely to fail here if this instance sits statically in a scene
	## (see the file header) — kept anyway, harmless, and resolves
	## immediately in the case a scene actually does stream in after
	## every WORLD_SYSTEM_SCRIPTS entry exists. _process() is what actually
	## guarantees resolution regardless of placement.
	_try_resolve_systems()


func _process(delta: float) -> void:
	if _game_clock and _lodging_system and _save_system:
		return

	_try_resolve_systems()
	if _game_clock and _lodging_system and _save_system:
		return

	_systems_search_time += delta
	if not _warned_missing_systems and _systems_search_time >= systems_search_timeout:
		_warned_missing_systems = true
		push_warning(
			"[LodgingRoom] %s: still missing a required system after %.1fs (game_clock=%s lodging=%s save=%s) — sleeping here will not work"
			% [name, _systems_search_time, _game_clock != null, _lodging_system != null, _save_system != null]
		)


## Retried from _process() until all three succeed — see the file header on
## why a single _ready() call isn't enough. Idempotent past the first
## success for each: already-resolved references are left alone rather than
## looked up again, so this stays cheap (three early-out checks) once
## everything is found.
func _try_resolve_systems() -> void:
	if not _game_clock:
		_game_clock = get_tree().get_first_node_in_group(
			GameClockSystem.GROUP_GAME_CLOCK
		) as GameClockSystem
	if not _lodging_system:
		_lodging_system = get_tree().get_first_node_in_group(
			LodgingSystem.GROUP_LODGING_SYSTEM
		) as LodgingSystem
	if not _save_system:
		_save_system = get_tree().get_first_node_in_group(
			SaveSystem.GROUP_SAVE_SYSTEM
		) as SaveSystem


func _on_presence_area_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	_player_inside = true


func _on_presence_area_body_exited(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	_player_inside = false
	if _selecting:
		_cancel_selection("Left the room")


## BUTTON's activated signal fires on EVERY interact while this is the
## focused interactable, first press and second alike — the routing never
## changes; only this handler's own _selecting flag decides what a press
## means, the same "the object doesn't know who reacts to it" split
## interactables.gd already documents for activated().
func _on_bed_activated(_by: Node) -> void:
	if _selecting:
		_confirm_sleep()
	else:
		_try_begin_selection()


func _try_begin_selection() -> void:
	if not _player_inside:
		_flash_message("Too far from the bed")
		return
	if PlayerState.stance != PlayerState.Stance.PEACE:
		_flash_message("Can't sleep ready to fight")
		return
	if not (_game_clock and _lodging_system and _save_system):
		_flash_message("Something's wrong with this room")
		return

	_selecting = true
	_selected_hours = DEFAULT_SLEEP_HOURS
	_update_hour_label()
	_hour_label.visible = true


## Re-checks the same two gates _try_begin_selection() did — defence in
## depth, not the primary guard: _on_presence_area_body_exited() and
## _on_stance_changed() already cancel selection the instant either
## condition breaks while the picker is open, so reaching here with either
## false should not happen in practice.
func _confirm_sleep() -> void:
	if not _player_inside or PlayerState.stance != PlayerState.Stance.PEACE:
		_cancel_selection("Can't sleep right now")
		return
	if not (_game_clock and _lodging_system and _save_system):
		_cancel_selection("Something's wrong with this room")
		return

	_selecting = false
	_hour_label.visible = false

	var hours := float(_selected_hours)
	_game_clock.total_game_hours += hours
	_lodging_system.notify_slept(room_id, _game_clock.total_game_hours)
	slept.emit(room_id, hours)
	_save_system.save_to_slot()


func _cancel_selection(reason: String) -> void:
	_selecting = false
	_hour_label.visible = false
	_flash_message(reason)


func _on_hours_increase_pressed() -> void:
	if not _selecting:
		return
	_selected_hours = mini(_selected_hours + 1, MAX_SLEEP_HOURS)
	_update_hour_label()


func _on_hours_decrease_pressed() -> void:
	if not _selecting:
		return
	_selected_hours = maxi(_selected_hours - 1, MIN_SLEEP_HOURS)
	_update_hour_label()


func _on_pause_pressed() -> void:
	if not _selecting:
		return
	_cancel_selection("Sleep cancelled")


## Stance is not reset by open_menu()/close_menu() (see PlayerState's own
## comment), so this is the only place a stance change during the pause
## menu could matter — irrelevant in practice since the menu pauses the
## tree, but not assumed here.
func _on_stance_changed(_old_stance: PlayerState.Stance, new_stance: PlayerState.Stance) -> void:
	if _selecting and new_stance != PlayerState.Stance.PEACE:
		_cancel_selection("Can't sleep ready to fight")


func _update_hour_label() -> void:
	_hour_label.text = "Sleep for %d hour%s\n(scroll to adjust, interact to confirm)" \
			% [_selected_hours, "" if _selected_hours == 1 else "s"]


func _flash_message(text: String) -> void:
	_hour_label.text = text
	_hour_label.visible = true
	get_tree().create_timer(MESSAGE_DISPLAY_TIME).timeout.connect(_on_message_timeout)


func _on_message_timeout() -> void:
	if not _selecting:
		_hour_label.visible = false
