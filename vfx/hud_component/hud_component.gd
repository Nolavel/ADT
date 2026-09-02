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
# Dependencies: WorldContext (via on_world_ready) for the player, and the
# player's own InteractComponent.
# =============================================================================
extends Node3D
class_name HUDComponent

## The object the player is currently aimed at, drawn as a decal under it.
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
	if _interact:
		_interact.interact_target_changed.connect(_on_interact_target_changed)
	else:
		push_warning("[HUDComponent] InteractComponent не найден — декаль кандидата не появится")


func _ready() -> void:
	PlayerState.mode_changed.connect(_on_player_mode_changed)


func _exit_tree() -> void:
	if _interact and _interact.interact_target_changed.is_connected(_on_interact_target_changed):
		_interact.interact_target_changed.disconnect(_on_interact_target_changed)
	if PlayerState.mode_changed.is_connected(_on_player_mode_changed):
		PlayerState.mode_changed.disconnect(_on_player_mode_changed)


## Interacting is an on-foot thing; in a hover or a transit tube the controls
## are different and the decal would be describing something the player
## cannot do. view_mode is deliberately NOT consulted any more — both view
## modes are the same third-person camera, so there is nothing left to gate.
func _is_candidate_active() -> bool:
	return PlayerState.mode == PlayerState.Mode.ON_FOOT


func _on_player_mode_changed(_old, _new) -> void:
	if not _is_candidate_active() and candidate_indicator:
		candidate_indicator.hide_indicator()


## What the player is aimed at changed, or they crossed into arm's reach of
## the same thing. Null object means nothing is targeted and the decal goes
## away — including right after a pickup, since the object is freed and
## InteractComponent reports null on the next frame.
func _on_interact_target_changed(object: InteractableObject, in_reach: bool) -> void:
	if not candidate_indicator:
		return
	## is_instance_valid() rather than "== null": InteractComponent normalises
	## a freed target away, but a freed Object also compares equal to null, so
	## the two questions look identical and only one of them is unambiguous.
	if not is_instance_valid(object) or not _is_candidate_active():
		candidate_indicator.hide_indicator()
		return
	candidate_indicator.show_candidate(object.global_position, in_reach)
