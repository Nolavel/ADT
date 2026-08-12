# =============================================================================
# incident_registry.gd — IncidentRegistry, a WORLD_SYSTEM_SCRIPTS entry
# (world.gd), created via .new() like every other Node-system.
#
# What the city has on record. Actors report; they do not remember —
# ambient NPCs are streamed in and out with their block, so nothing durable
# may live on them. This is what lets the crowd be disposable while
# consequences are not.
#
# This is a first slice of the WitnessSystem the roadmap describes, so the
# shape here is deliberately not player-specific: report() takes a stable
# perpetrator actor id (StringName) and an Incident.Kind, not "the player did
# X" — a future witness (an NPC who saw something, not just the one who did
# it) reports through the same call. Today the only producer is player.gd's
# punch_landed signal (see _on_punch_landed() below), and the only Kind is
# ASSAULT.
#
# Stores a bounded, aging list rather than everything ever reported —
# max_incidents/max_incident_age are exports because both are feel/scale
# values with no derivable "correct" number. Consumers ask has_recent_
# incident_by() for a yes/no, or get_incidents_near() for a catch-up list,
# rather than walking the list themselves, so the storage shape (Array
# today) can change later without touching a caller.
#
# Timestamps are GAME HOURS (GameClockSystem.total_game_hours), not real
# seconds — this is a deliberate reversal of an earlier version of this file,
# which used Time.get_ticks_msec() specifically because it didn't survive a
# reload and didn't need to. It needs to now: this registry is the durable
# record H1 (docs/scope_horizon.md) requires to survive a save/load
# boundary, and Time.get_ticks_msec() resets on launch — an incident's age
# would silently jump to "ancient" (or negative) the instant the engine
# restarts. GameClockSystem.total_game_hours is the one clock that is itself
# saved and restored (see its own get_save_data()), so pruning against it
# stays correct across a reload. This does mean max_incident_age and
# has_recent_incident_by()'s within_hours are in GAME hours now, not real
# seconds — at the default REAL_MINUTES_PER_GAME_DAY (48) and time_scale
# 1.0, 1 game hour = 120 real seconds. max_incident_age's own doc comment
# below has the current reasoning for its value; see the "pruning-on-load"
# paragraph further down for why an earlier value here (0.25, converted
# from a real-seconds figure that was never this field's to convert from)
# was wrong in kind, not just in magnitude.
#
# perpetrator is a stable StringName actor id (perpetrator_id on Incident),
# not a Node3D — see incident.gd's own header. report() takes the id
# directly; resolving "which node reported this" to an id is the caller's
# job (see player.gd's punch_landed handler below), not this registry's.
#
# max_incident_age and PatrolDroneController's alert_memory_time are NOT the
# same value under different names, even though they briefly shared the same
# rough magnitude — that was an artifact of history, not a design intent,
# and treating them as interchangeable caused a real bug (see CHANGELOG.md,
# 2026-08-12, the pruning-on-load incident). alert_memory_time is a drone's
# own short-lived, real-second memory of "when did I last have a reason to
# be alert" — a live-session reaction timer, reset by
# PatrolDroneController._on_incident_reported(), and none of this
# registry's business. max_incident_age is how long THE CITY keeps a fact on
# record at all, in game hours — the retention window a fact must survive to
# still be readable by a consumer days later, across streaming and across a
# save/load boundary. A drone forgetting to react after three seconds and a
# city forgetting a fact ever happened are different questions on different
# clocks; only one of them belongs here.
# =============================================================================
extends Node
class_name IncidentRegistry

## Lookup group for consumers that can't reach this through WorldContext —
## PatrolDroneController is the first: it's a static test instance placed
## directly in world.tscn, not a WORLD_SYSTEM_SCRIPTS/3D_ENTITY_SCENES/
## UI_SCENES entry, so it never receives on_world_ready(). Resolved via
## get_tree().get_first_node_in_group(), the same pattern
## PerceptionComponent already uses to find the player from anywhere in the
## tree — not a new lookup convention.
const GROUP_INCIDENT_REGISTRY: StringName = &"incident_registry"

signal incident_reported(incident: Incident)

## How long the city keeps a fact on record, GAME HOURS — not how fast a
## drone reacts (see the file header on why those are different questions;
## PatrolDroneController.alert_memory_time is that one, in real seconds, and
## is not read here). This is a retention window: a fact must outlive a
## normal play session and an ordinary walk to the next district to be worth
## recording at all, or nothing durable is actually being kept. 24.0 (one
## full in-game day, itself 48 real minutes at the default
## REAL_MINUTES_PER_GAME_DAY and time_scale 1.0) was chosen as a value long
## enough that no ordinary session or errand expires a record by accident,
## short enough that this still reads as an aging log and not the
## permanent, only-cleared-on-mission-completion record Sid's wanted broadcast
## is in canon — this registry is a first slice of WitnessSystem, not that
## system. max_incidents below is the actual safety valve against unbounded
## growth in a busy city, so raising this doesn't trade away that guarantee.
## A feel/scale value regardless — tune by eye like max_incidents always has
## been.
@export var max_incident_age: float = 24.0
## Oldest incidents are dropped past this count, regardless of age — a hard
## ceiling so a busy city can't grow this list unbounded.
@export var max_incidents: int = 32

var _incidents: Array[Incident] = []
## Captured in on_world_ready() — the one producer this registry knows about
## today. Duck-typed (connect by StringName, not a cast to a Player type
## that doesn't exist — player.gd has no class_name) so this file doesn't
## need to know player.gd's type, only that whatever WorldContext hands it
## as the player carries a punch_landed(position: Vector3) signal and a
## get_actor_id() -> StringName method (see player.gd's ACTOR_ID).
var _player: Node3D = null
## Captured in on_world_ready() — the source of truth for timestamp()'s
## "now" (see the file header on why game hours, not Time.get_ticks_msec()).
## Null (and _now() warns once) only if this registry somehow initializes
## before GameClockSystem, which WORLD_SYSTEM_SCRIPTS' declared order in
## world.gd does not allow today.
var _game_clock: GameClockSystem = null


func _ready() -> void:
	add_to_group(GROUP_INCIDENT_REGISTRY)


## WORLD_SYSTEM_SCRIPTS' optional lifecycle hook (world.gd) — same pattern
## ClickToMoveSystem uses to learn about the player. The wiring this
## registry does today: resolve GameClockSystem for timestamps, and listen
## for the player's own punches. A future witness (NPC-reported incidents)
## would connect here the same way, not by widening report()'s signature.
func on_world_ready(context: WorldContext) -> void:
	_game_clock = context.get_system(GameClockSystem) as GameClockSystem
	_player = context.player
	if _player and _player.has_signal(&"punch_landed"):
		_player.connect(&"punch_landed", _on_punch_landed)


## Records a fact: the actor behind perpetrator_id did kind at position, now.
## Prunes aged-out and overflow entries before emitting, so subscribers never
## see a list about to be trimmed out from under them.
func report(perpetrator_id: StringName, kind: Incident.Kind, position: Vector3) -> void:
	var incident := Incident.new()
	incident.perpetrator_id = perpetrator_id
	incident.kind = kind
	incident.position = position
	incident.timestamp = _now()
	_incidents.append(incident)
	_prune()
	incident_reported.emit(incident)


## True if perpetrator_id has an incident on record within the last
## within_hours GAME hours (see the file header on the unit). Read-only
## query — does not prune; report() keeps the list bounded on its own
## schedule.
func has_recent_incident_by(perpetrator_id: StringName, within_hours: float) -> bool:
	var now := _now()
	for incident in _incidents:
		if incident.perpetrator_id == perpetrator_id and now - incident.timestamp <= within_hours:
			return true
	return false


## Every incident within radius metres of point, reported within max_age
## game hours — for a consumer that needs to catch up on facts it missed
## rather than hear about them as they happen (a drone re-entering the world
## after its block streamed back in, or after a save/load boundary, neither
## of which fires incident_reported for anything already on record). A
## read-only query, same as has_recent_incident_by() — does not prune;
## report() and load_save_data() keep the list bounded on their own
## schedule. Meant to be called once per "I just appeared in the world",
## not polled — see PatrolDroneController._check_existing_incidents() for
## the one caller today and why it only runs once.
func get_incidents_near(point: Vector3, radius: float, max_age: float) -> Array[Incident]:
	var now := _now()
	var matches: Array[Incident] = []
	for incident in _incidents:
		if now - incident.timestamp > max_age:
			continue
		if incident.position.distance_to(point) > radius:
			continue
		matches.append(incident)
	return matches


## Most recent incident on record, or null if none — read by debug tooling.
func get_latest_incident() -> Incident:
	if _incidents.is_empty():
		return null
	return _incidents[-1]


## SaveSystem's key for this system's payload — stable independent of the
## class/file name (see save_system.gd's header for why).
func get_save_key() -> StringName:
	return &"incident_registry"


## Dictionaries/arrays/primitives only, per SaveSystem's contract — no
## Node3D, no Vector3/StringName objects stored raw (JSON has neither), so
## position is flattened to a 3-float array and perpetrator_id/kind to their
## String/int representations.
func get_save_data() -> Dictionary:
	var saved_incidents: Array = []
	for incident in _incidents:
		saved_incidents.append({
			"perpetrator_id": String(incident.perpetrator_id),
			"kind": int(incident.kind),
			"position": [incident.position.x, incident.position.y, incident.position.z],
			"timestamp": incident.timestamp,
		})
	return {"incidents": saved_incidents}


## Rebuilds _incidents from a payload get_save_data() produced. Replaces the
## current list outright rather than merging — a load is a full restore of
## this registry's state, not an append.
func load_save_data(data: Dictionary) -> void:
	_incidents.clear()
	for entry_variant in data.get("incidents", []) as Array:
		var entry := entry_variant as Dictionary
		var incident := Incident.new()
		incident.perpetrator_id = StringName(entry.get("perpetrator_id", ""))
		incident.kind = int(entry.get("kind", Incident.Kind.ASSAULT))
		var saved_position: Array = entry.get("position", [0.0, 0.0, 0.0])
		incident.position = Vector3(
			float(saved_position[0]), float(saved_position[1]), float(saved_position[2])
		)
		incident.timestamp = float(entry.get("timestamp", 0.0))
		_incidents.append(incident)
	_prune()


func _on_punch_landed(position: Vector3) -> void:
	if not (_player and _player.has_method(&"get_actor_id")):
		push_warning("[IncidentRegistry] player has no get_actor_id() — punch not reported")
		return
	report(StringName(_player.call(&"get_actor_id")), Incident.Kind.ASSAULT, position)


## "Now" for every timestamp this registry stamps or compares against — game
## hours, not real seconds (see the file header). Falls back to 0.0 with a
## warning if GameClockSystem hasn't been resolved yet; in practice
## on_world_ready() always resolves it before report()/_prune() can run.
func _now() -> float:
	if _game_clock == null:
		push_warning("[IncidentRegistry] GameClockSystem not resolved — timestamping as 0.0")
		return 0.0
	return _game_clock.total_game_hours


## Drops incidents past max_incident_age (oldest first — the array is
## append-ordered, so the front is always the oldest) and, if still over
## max_incidents after that, drops the oldest remainder too.
func _prune() -> void:
	var now := _now()
	while not _incidents.is_empty() and now - _incidents[0].timestamp > max_incident_age:
		_incidents.pop_front()
	while _incidents.size() > max_incidents:
		_incidents.pop_front()
