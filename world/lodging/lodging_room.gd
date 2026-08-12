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
# This step is scaffolding only — the room, tracking whether the player is
# in it, and a properly-configured BedPoint interactable. It does not sleep
# anyone: that is the next step's subject entirely (GameClockSystem,
# LodgingSystem, SaveSystem), and none of the three is referenced here.
#
# BedPoint is an ordinary InteractableObject, InteractionType.BUTTON,
# through the same InteractComponent path every other interactable already
# uses — see interact_component.gd's own comment on _activate_button(),
# previously an empty stub with nowhere to route to. No second input path
# for beds: this project already has one interaction system, and a bed is
# not special enough to need a different one.
# =============================================================================
extends Node3D
class_name LodgingRoom

## Stable, authored id — same convention as ActorBase.actor_id and
## BlockBase.id, never derived from this node's path in the tree. Empty by
## default; _ready() warns if left unset, the same way ActorBase does,
## since an unauthored room_id means whatever durable record eventually
## keys on it (LodgingSystem, next step) can never find this room again
## after a reload.
@export var room_id: StringName = &""

@onready var _presence_area: Area3D = $PresenceArea

## True while the player's own CharacterBody3D overlaps PresenceArea — the
## ONLY thing PresenceArea's signals are used for; no other logic reads the
## area directly. Not consumed by anything in this file yet — that arrives
## with the sleep interaction next step, which needs to know whether the
## player is actually here before it lets them sleep.
var _player_inside: bool = false


func _ready() -> void:
	if room_id == &"":
		push_warning("[LodgingRoom] %s: room_id is unset — a durable per-room record will never find this room again after a reload" % name)

	_presence_area.body_entered.connect(_on_presence_area_body_entered)
	_presence_area.body_exited.connect(_on_presence_area_body_exited)


func _on_presence_area_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_inside = true


func _on_presence_area_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_inside = false
