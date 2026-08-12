# =============================================================================
# lodging_system.gd — LodgingSystem, a WORLD_SYSTEM_SCRIPTS entry (world.gd),
# created via .new() like every other Node-system.
#
# The durable record of rooms. It survives block unloading exactly the way
# IncidentRegistry does, and for the same reason: a room is content that can
# be streamed out, so nothing durable about it may live on a node — the
# record has to live in a registry that outlives any single LodgingRoom
# instance. A LodgingRoom scene (world/lodging/) is the interior itself and
# the interaction surface; this system is what remembers it existed.
#
# Dependency runs one way only, and this file enforces it by omission: it
# does not import SaveSystem, does not call save_to_slot(), and does not
# know sleeping is a save point. A room asks for a sleep (notify_slept()),
# the sleep advances GameClockSystem, and whoever handles that (LodgingRoom)
# is the one that asks SaveSystem to write — three separate decisions made
# by three separate files. If a future change makes this file mention
# SaveSystem, that is a sign the design has inverted, not a sign this file
# needs updating.
#
# For the same reason, notify_slept() takes an ABSOLUTE game-hour reading
# (slept_at_game_hours), not a duration — see that method's own comment for
# why, and for why this system still doesn't reach for GameClockSystem
# itself to get it.
#
# room_id is a stable, authored StringName — the same convention as
# BlockBase's id and ActorBase's actor_id, not derived from a node path
# (LodgingRoom instances are placed by hand today, not streamed content, but
# nothing here assumes that stays true).
# =============================================================================
extends Node
class_name LodgingSystem

## Lookup group for consumers that can't reach this through WorldContext —
## same reasoning as IncidentRegistry.GROUP_INCIDENT_REGISTRY: LodgingRoom
## (world/lodging/) is a static scene instance placed directly in a
## streamed block, not a WORLD_SYSTEM_SCRIPTS/3D_ENTITY_SCENES/UI_SCENES
## entry, so it never receives on_world_ready(). Resolved via
## get_tree().get_first_node_in_group(). Same string as get_save_key()'s
## return value, not a coincidence.
const GROUP_LODGING_SYSTEM: StringName = &"lodging"

## Sentinel for "never slept in this room" — distinct from any real
## GameClockSystem.total_game_hours reading, which only ever counts up from
## GameClockSystem.START_HOUR (16.0) and never goes negative. 0.0 would be
## wrong here: it collides with "slept in during the very first game hour",
## a real and reachable value, not just a theoretical one.
const NEVER_SLEPT: float = -1.0

## room_id -> Dictionary{"last_slept_game_hours": float, "storage": Array}.
## last_slept_game_hours is an ABSOLUTE reading — the value
## GameClockSystem.total_game_hours held at the moment this room was last
## slept in, directly comparable to that same property later ("how many
## game hours ago did I sleep here?" is now just a subtraction) — not a
## duration. NEVER_SLEPT until the first sleep. storage is empty and unused
## today — present so the record's shape doesn't change (and doesn't orphan
## old saves) the day something actually gets stored in a room.
var _rooms: Dictionary = {}


func _ready() -> void:
	add_to_group(GROUP_LODGING_SYSTEM)


## Returns this room's record, creating a default one on first access. Never
## returns null — a room that has never been slept in still has a record,
## with last_slept_game_hours == NEVER_SLEPT.
func get_room_record(room_id: StringName) -> Dictionary:
	if not _rooms.has(room_id):
		_rooms[room_id] = _make_default_record()
	return _rooms[room_id]


## Records that room_id was just slept in, at slept_at_game_hours — an
## ABSOLUTE GameClockSystem.total_game_hours reading, taken by the caller
## AFTER advancing the clock, not a duration. This system deliberately does
## not read GameClockSystem itself to fill this in: the one caller this
## exists for (LodgingRoom, world/lodging/) already has to hold a
## GameClockSystem reference anyway, to advance the clock to the next 07:00
## before calling this — so making this system resolve its own
## WorldContext/GameClockSystem dependency, purely to re-derive a value the
## caller already has in hand, would be a second copy of a lookup this file
## otherwise has zero use for. See this session's own report for the
## alternative considered (on_world_ready() resolving GameClockSystem
## directly) and why it was rejected.
func notify_slept(room_id: StringName, slept_at_game_hours: float) -> void:
	var record := get_room_record(room_id)
	record["last_slept_game_hours"] = slept_at_game_hours


## SaveSystem's key for this system's payload — stable independent of the
## class/file name (see save_system.gd's header for why).
func get_save_key() -> StringName:
	return &"lodging"


## Dictionaries/arrays/primitives only, per SaveSystem's contract. room_id
## (a StringName) becomes a String key, same conversion IncidentRegistry
## uses for perpetrator_id.
func get_save_data() -> Dictionary:
	var saved_rooms: Dictionary = {}
	for room_id in _rooms:
		var record: Dictionary = _rooms[room_id]
		saved_rooms[String(room_id)] = {
			"last_slept_game_hours": record.get("last_slept_game_hours", NEVER_SLEPT),
			"storage": record.get("storage", []),
		}
	return {"rooms": saved_rooms}


## Rebuilds _rooms from a payload get_save_data() produced. Replaces the
## current state outright rather than merging — a load is a full restore.
func load_save_data(data: Dictionary) -> void:
	_rooms.clear()
	var saved_rooms: Dictionary = data.get("rooms", {})
	for room_id_string in saved_rooms:
		var entry: Dictionary = saved_rooms[room_id_string]
		_rooms[StringName(room_id_string)] = {
			"last_slept_game_hours": float(entry.get("last_slept_game_hours", NEVER_SLEPT)),
			"storage": entry.get("storage", []),
		}


func _make_default_record() -> Dictionary:
	return {"last_slept_game_hours": NEVER_SLEPT, "storage": []}
