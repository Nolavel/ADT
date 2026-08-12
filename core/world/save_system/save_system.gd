# =============================================================================
# save_system.gd — SaveSystem, a WORLD_SYSTEM_SCRIPTS entry (world.gd),
# created via .new() like every other Node-system.
#
# Walks the other systems and moves dictionaries between them and disk. That
# is the entire job — it knows nothing about lodging, sleeping, or any
# in-fiction reason a save happens. Something else (today: LodgingRoom, once
# it exists) decides WHEN to call save_to_slot(); this file only decides HOW.
#
# The save/load contract is three optional methods, checked by has_method()
# exactly like WORLD_SYSTEM_SCRIPTS' existing on_world_ready(context) hook —
# a system opts in by implementing all three, and is skipped silently if it
# implements none:
#
#   get_save_key() -> StringName   — a key that outlives the system's own
#                                     class name (see below)
#   get_save_data() -> Dictionary  — primitives/arrays/dictionaries only
#   load_save_data(data: Dictionary) -> void
#
# get_save_key() exists so the payload's top-level keys are NOT class names:
# renaming a script (and its class_name with it) must not orphan a save
# file, so the key is a value the system states explicitly, independent of
# whatever its script happens to be called this week. GameClockSystem and
# IncidentRegistry are the two systems that implement this today, proving
# the lifecycle on a trivial payload and a hard one respectively — see
# docs/scope_horizon.md, H1.
#
# Payload shape on disk:
#   {"version": 1, "systems": {"<save_key>": {...system's own dict...}, ...}}
#
# "version" is written from the very first save this project ever produces.
# A save file with a version this code does not recognise is refused outright
# (push_warning, no partial apply) rather than half-loaded — a save format
# with no version field is a migration problem that can never be fixed after
# the fact, so it does not get the chance to happen here.
#
# No Node references, no Object instances, no scene-instance resource paths
# leave a system's get_save_data() — dictionaries/arrays/primitives only. If
# a system cannot express its state that way, that system has a defect;
# SaveSystem does not widen the contract to accommodate it (see
# IncidentRegistry's own history: it used to hold a Node3D perpetrator
# reference and had to grow a stable id specifically to become saveable).
# =============================================================================
extends Node
class_name SaveSystem

## Directory saves live under, one JSON file per slot.
const SAVE_DIRECTORY: String = "user://saves"
## Written into every save's "version" field. Bump only alongside a migration
## path for old saves — there is none today, so an old version is refused,
## not upgraded.
const SAVE_FORMAT_VERSION: int = 1

## Snapshot of WorldContext.systems, taken once in on_world_ready() — the
## same array world.gd builds from WORLD_SYSTEM_SCRIPTS, in that same order.
## Walked by both save_to_slot() and load_from_slot(); this system does not
## keep its own separate registry.
var _systems: Array[Node] = []


func _ready() -> void:
	InputSystems.debug_save_pressed.connect(_on_debug_save_pressed)
	InputSystems.debug_load_pressed.connect(_on_debug_load_pressed)


## WORLD_SYSTEM_SCRIPTS' optional lifecycle hook (world.gd) — the only thing
## this system needs from it is the already-built systems list; it has no
## use for player/camera/stream_container.
func on_world_ready(context: WorldContext) -> void:
	_systems = context.systems


## Collects every system's get_save_data() under its own get_save_key() and
## writes the result to user://saves/slot_<slot>.json. Returns false (and
## push_errors the specific reason) on any failure — a caller that ignores
## the return value has no way to know a save silently didn't happen.
func save_to_slot(slot: int = 0) -> bool:
	var systems_payload: Dictionary = {}
	for system in _systems:
		if not _implements_save_contract(system):
			continue
		var key := String(system.call(&"get_save_key"))
		if key.is_empty():
			push_error("[SaveSystem] %s.get_save_key() returned an empty key — save aborted" % system.name)
			return false
		if systems_payload.has(key):
			push_error("[SaveSystem] duplicate save key '%s' (from %s) — save aborted" % [key, system.name])
			return false
		systems_payload[key] = system.call(&"get_save_data")

	var make_dir_err := DirAccess.make_dir_recursive_absolute(SAVE_DIRECTORY)
	if make_dir_err != OK and make_dir_err != ERR_ALREADY_EXISTS:
		push_error("[SaveSystem] could not create %s: %s" % [SAVE_DIRECTORY, error_string(make_dir_err)])
		return false

	var path := _slot_path(slot)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("[SaveSystem] could not open %s for writing: %s" % [path, error_string(FileAccess.get_open_error())])
		return false

	var payload := {"version": SAVE_FORMAT_VERSION, "systems": systems_payload}
	file.store_string(JSON.stringify(payload))
	file.close()
	return true


## Reads user://saves/slot_<slot>.json and hands each system its own slice
## via load_save_data(). Refuses the whole file (no partial apply) if it is
## missing, unparsable, or carries a version this code does not recognise —
## see the file header on why a versionless/mismatched save is never
## half-loaded.
func load_from_slot(slot: int = 0) -> bool:
	var path := _slot_path(slot)
	if not FileAccess.file_exists(path):
		push_error("[SaveSystem] no save file at %s" % path)
		return false

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("[SaveSystem] could not open %s for reading: %s" % [path, error_string(FileAccess.get_open_error())])
		return false
	var raw_text := file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(raw_text)
	if not (parsed is Dictionary):
		push_error("[SaveSystem] %s does not contain a JSON object — refusing to load" % path)
		return false
	var payload: Dictionary = parsed

	var version := int(payload.get("version", -1))
	if version != SAVE_FORMAT_VERSION:
		push_warning(
			"[SaveSystem] %s has version %d, this build expects %d — refusing to load"
			% [path, version, SAVE_FORMAT_VERSION]
		)
		return false

	var systems_payload: Dictionary = payload.get("systems", {})
	for system in _systems:
		if not _implements_save_contract(system):
			continue
		var key := String(system.call(&"get_save_key"))
		if systems_payload.has(key):
			system.call(&"load_save_data", systems_payload[key])
	return true


func _on_debug_save_pressed() -> void:
	if save_to_slot(0):
		print("[SaveSystem] saved to slot 0")


func _on_debug_load_pressed() -> void:
	if load_from_slot(0):
		print("[SaveSystem] loaded from slot 0")


## A system opts into the save contract by implementing all three methods
## together — get_save_key() alone (or get_save_data() alone) is treated as
## not opting in, rather than guessing at a partial contract.
func _implements_save_contract(system: Node) -> bool:
	return system.has_method(&"get_save_key") \
			and system.has_method(&"get_save_data") \
			and system.has_method(&"load_save_data")


func _slot_path(slot: int) -> String:
	return SAVE_DIRECTORY + "/slot_%d.json" % slot
