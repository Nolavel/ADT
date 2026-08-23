# =============================================================================
# player_persistence_system.gd — PlayerPersistenceSystem, a
# WORLD_SYSTEM_SCRIPTS entry (world.gd), created via .new() like every other
# Node-system.
#
# The route the player's own components take into a save file. SaveSystem
# walks WorldContext.systems and nothing else, which is correct — it is a
# list of world systems, not a search of the scene tree — but it means a
# component hanging off the player (inventory, and equipment once it exists)
# has no way into a save at all. This system is that way in, and it is
# deliberately the only one: SaveSystem's contract does not widen, a second
# system implements it on the player's behalf.
#
# Why a system rather than teaching SaveSystem about the player: SaveSystem
# knows nothing about lodging, sleeping, or any other in-fiction meaning, and
# "the player has components" is exactly that kind of knowledge. Keeping it
# out here is what lets SaveSystem stay a thing that moves dictionaries.
#
# Nesting: this system's own payload is one level deep —
#   {"components": {"<component's own save_key>": {...}}}
# Each component states its own key, same rule and same reasoning as the
# top level: a renamed script must not orphan a save.
#
# A component opts in exactly as a system does, by implementing all three
# methods — the check is SaveSystem.implements_save_contract(), shared
# rather than restated here.
# =============================================================================
extends Node
class_name PlayerPersistenceSystem

## This system's slice of the payload. Not "player" — that name will be
## wanted later for the player's own transform/state, which is a different
## thing from what its components hold.
const SAVE_KEY: StringName = &"player_components"

## Captured in on_world_ready(). world.gd adds the player to the tree before
## it builds the WorldContext, so by the time this runs the player's children
## have had their own _ready() — Godot's ordering is bottom-up.
var _player: Node = null


func on_world_ready(context: WorldContext) -> void:
	_player = context.player


func get_save_key() -> StringName:
	return SAVE_KEY


func get_save_data() -> Dictionary:
	var components: Dictionary = {}
	for component in _saveable_components():
		var key := String(component.call(&"get_save_key"))
		if key.is_empty():
			push_error(
				"[PlayerPersistence] %s.get_save_key() returned an empty key — skipped"
				% component.name
			)
			continue
		if components.has(key):
			push_error(
				"[PlayerPersistence] duplicate component save key '%s' (from %s) — skipped"
				% [key, component.name]
			)
			continue
		components[key] = component.call(&"get_save_data")
	return {"components": components}


func load_save_data(data: Dictionary) -> void:
	var components: Dictionary = data.get("components", {})
	for component in _saveable_components():
		var key := String(component.call(&"get_save_key"))
		if components.has(key):
			component.call(&"load_save_data", components[key])


## Direct children of the player that implement the contract. Direct children
## only: the player's components are its own children by convention
## (player.tscn), and walking the whole subtree would sweep up meshes,
## attachments and anything a future component parents beneath itself.
##
## Unlike SaveSystem, a bad key here cannot abort the save — get_save_data()
## has no failure channel to report one through. So a component with an empty
## or duplicate key is skipped loudly instead, which loses that component's
## state rather than the whole file.
func _saveable_components() -> Array[Node]:
	var found: Array[Node] = []
	if _player == null:
		return found
	for child in _player.get_children():
		if SaveSystem.implements_save_contract(child):
			found.append(child)
	return found
