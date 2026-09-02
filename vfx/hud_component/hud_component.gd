# =============================================================================
# hud_component.gd — HUDComponent.
#
# A WORLD_3D_ENTITY_SCENES entry: world-space decals, not screen UI. One
# indicator is left, and it is the one about INTERACTION.
#
# THE MOVE-DESTINATION MARKER IS GONE (2026-09-02). It existed for
# click-to-move, which existed for the isometric camera, and both were
# removed with it — a marker for "where I clicked to walk" has nothing to
# mark when walking is WASD. TargetIndicator itself stays: the candidate
# decal is the same class in its decal_only role.
#
# IT PULLS, IT IS NOT PUSHED, AND IT RE-STATES ITSELF EVERY FRAME. The decal
# used to be driven from InteractComponent.interact_target_changed — an EDGE —
# while the key panel above it was driven per frame. That asymmetry was a real
# bug rather than a style difference: anything else that hid the decal (a
# hover door's trigger releasing as the player walked past) won permanently,
# because no edge was left to raise it again. Measured 2026-09-02 — standing
# at the lodging bed after passing a hover door showed the F panel with no
# decal under it.
#
# Reading InteractComponent here, rather than having it call this node, keeps
# the dependency pointing the way it always did: the component that finds
# things does not know who draws them. That is also what PlayerHUD does with
# HealthComponent.
#
# A CLAIMANT OVERRIDES. While something owns the interact key through
# InputSystems.claim_interact() — a hover door, today the only one — this node
# stops reading and lets the claimant place the decal itself through
# show_candidate_at(). One owner of the key, one owner of the picture.
#
# Dependencies: WorldContext (via on_world_ready) for the player, the player's
# own InteractComponent, PlayerState and InputSystems. Claimants find this
# node by group.
# =============================================================================
extends Node3D
class_name HUDComponent

## Lookup group, so an interact-key CLAIMANT can put the decal under its own
## anchor. HoverEntryTrigger is a static scene instance that never receives a
## WorldContext — exactly the case CLAUDE.md's dependency rule names, and the
## same route HoldPrompt is already found by.
const GROUP_HUD_COMPONENT: StringName = &"hud_component"

## The thing the player could act on, drawn as a decal under it.
@onready var candidate_indicator: TargetIndicator = $CandidateIndicator

var _interact: InteractComponent = null


## Единая точка входа — та же сигнатура, что и у Node-систем в
## WORLD_SYSTEM_SCRIPTS, только здесь её вызывает цикл по
## WORLD_3D_ENTITY_SCENES в world.gd.
func on_world_ready(context: WorldContext) -> void:
	## Reached through the player rather than through context.systems:
	## InteractComponent is a child of the player, not a world system. Same
	## route PlayerHUD uses for HealthComponent.
	if context.player:
		_interact = context.player.get_node_or_null("InteractComponent") as InteractComponent
	if _interact == null:
		push_warning("[HUDComponent] InteractComponent не найден — декаль кандидата не появится")


func _ready() -> void:
	add_to_group(GROUP_HUD_COMPONENT)
	PlayerState.mode_changed.connect(_on_player_mode_changed)


func _exit_tree() -> void:
	if PlayerState.mode_changed.is_connected(_on_player_mode_changed):
		PlayerState.mode_changed.disconnect(_on_player_mode_changed)


## Physics rather than idle, so this reads the same tick InteractComponent
## wrote — its detection runs in _physics_process, and an idle read would be
## one frame behind it half the time.
func _physics_process(_delta: float) -> void:
	if not _is_candidate_active():
		hide_candidate()
		return
	## Someone else owns the key and therefore the picture. Deliberately a
	## bare return and not a hide: hiding here would stomp the decal the
	## claimant just placed, which is exactly the bug the key panel had.
	if InputSystems.is_interact_claimed():
		return
	if _interact == null:
		return

	var target: InteractableObject = _interact.current_interactable
	## is_instance_valid() rather than "== null": a freed Object compares
	## EQUAL to null in Godot, so the two questions look identical and only
	## one of them is unambiguous. A picked-up item is freed, not cleared.
	if not is_instance_valid(target):
		hide_candidate()
		return
	show_candidate_at(target, _interact.is_target_in_reach())


## Raises the decal under `anchor`. Safe to call every frame — TargetIndicator
## repositions an already-visible marker without restarting its appear tween,
## which is what makes per-frame assertion cheap enough to be the contract.
##
## `in_reach` picks the palette: dim means pressing F walks the character
## over, bright means it acts from here. The caller decides which, because the
## caller is the one that knows the distance rule it is applying.
func show_candidate_at(anchor: Node3D, in_reach: bool) -> void:
	if candidate_indicator == null or not is_instance_valid(anchor):
		return
	if not _is_candidate_active():
		return
	candidate_indicator.show_candidate(anchor.global_position, in_reach)


func hide_candidate() -> void:
	if candidate_indicator != null:
		candidate_indicator.hide_indicator()


## Interacting is an on-foot thing; in a hover or a transit tube the controls
## are different and the decal would be describing something the player
## cannot do. view_mode is deliberately NOT consulted any more — both view
## modes are the same third-person camera, so there is nothing left to gate.
func _is_candidate_active() -> bool:
	return PlayerState.mode == PlayerState.Mode.ON_FOOT


func _on_player_mode_changed(_old, _new) -> void:
	if not _is_candidate_active() and candidate_indicator:
		candidate_indicator.hide_indicator()
