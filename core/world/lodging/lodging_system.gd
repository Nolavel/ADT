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
# room_id is a stable, authored StringName — the same convention as
# BlockBase's id and ActorBase's actor_id, not derived from a node path
# (LodgingRoom instances are placed by hand today, not streamed content, but
# nothing here assumes that stays true).
# =============================================================================
extends Node
class_name LodgingSystem

## room_id -> Dictionary{"last_slept_game_hours": float, "storage": Array}.
## storage is empty and unused today — present so the record's shape doesn't
## change (and doesn't orphan old saves) the day something actually gets
## stored in a room.
var _rooms: Dictionary = {}


## Returns this room's record, creating a default one on first access. Never
## returns null — a room that has never been slept in still has a record,
## just an empty/zeroed one.
func get_room_record(room_id: StringName) -> Dictionary:
	if not _rooms.has(room_id):
		_rooms[room_id] = _make_default_record()
	return _rooms[room_id]


## Records that room_id was just slept in, advancing the clock by
## hours_advanced game hours. This system does not advance the clock itself
## (that is GameClockSystem's job, driven by whoever handles the sleep
## interaction) — hours_advanced is reported here after the fact, purely as
## the room's own memory of its last use.
func notify_slept(room_id: StringName, hours_advanced: float) -> void:
	var record := get_room_record(room_id)
	record["last_slept_game_hours"] = hours_advanced


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
			"last_slept_game_hours": record.get("last_slept_game_hours", 0.0),
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
			"last_slept_game_hours": float(entry.get("last_slept_game_hours", 0.0)),
			"storage": entry.get("storage", []),
		}


func _make_default_record() -> Dictionary:
	return {"last_slept_game_hours": 0.0, "storage": []}
