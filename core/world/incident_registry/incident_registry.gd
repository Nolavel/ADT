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
# shape here is deliberately not player-specific: report() takes a plain
# perpetrator Node3D and an Incident.Kind, not "the player did X" — a future
# witness (an NPC who saw something, not just the one who did it) reports
# through the same call. Today the only caller is player.gd (see its
# punch_landed signal), and the only Kind is ASSAULT.
#
# Stores a bounded, aging list rather than everything ever reported —
# max_incidents/max_incident_age are exports because both are feel/scale
# values with no derivable "correct" number. Consumers ask has_recent_
# incident_by() for a yes/no rather than walking the list themselves, so the
# storage shape (Array today) can change later without touching a caller.
#
# Timestamps are real seconds (Time.get_ticks_msec() / 1000.0), not
# GameClockSystem's game-hours: GameClockSystem is the source of truth for
# game time, but that time runs at a heavily compressed, non-1:1 ratio to
# real time (1 game hour = 2 real minutes by default) and its time_scale is
# public API for future crafting/sleep mechanics that can change that ratio
# mid-game. has_recent_incident_by()'s within_seconds is a real-time
# responsiveness window (how fast a drone reacts), the same unit every other
# timer in this system already uses (alert_memory_time, etc.) — converting
# it through GameClockSystem's ratio would silently drift wrong the moment
# time_scale is ever not 1.0. Flagged in the report for the owner.
# =============================================================================
extends Node
class_name IncidentRegistry

signal incident_reported(incident: Incident)

## Oldest incidents are dropped past this age, regardless of count — a feel/
## scale value, tuned by eye.
@export var max_incident_age: float = 30.0
## Oldest incidents are dropped past this count, regardless of age — a hard
## ceiling so a busy city can't grow this list unbounded.
@export var max_incidents: int = 32

var _incidents: Array[Incident] = []
## Captured in on_world_ready() — the one producer this registry knows about
## today. Duck-typed (connect by StringName, not a cast to a Player type
## that doesn't exist — player.gd has no class_name) so this file doesn't
## need to know player.gd's type, only that whatever WorldContext hands it
## as the player carries a punch_landed(position: Vector3) signal.
var _player: Node3D = null


## WORLD_SYSTEM_SCRIPTS' optional lifecycle hook (world.gd) — same pattern
## ClickToMoveSystem uses to learn about the player. The only wiring this
## registry does today: listen for the player's own punches. A future
## witness (NPC-reported incidents) would connect here the same way, not by
## widening report()'s signature.
func on_world_ready(context: WorldContext) -> void:
	_player = context.player
	if _player and _player.has_signal(&"punch_landed"):
		_player.connect(&"punch_landed", _on_punch_landed)


## Records a fact: perpetrator did kind at position, now. Prunes aged-out and
## overflow entries before emitting, so subscribers never see a list about to
## be trimmed out from under them.
func report(perpetrator: Node3D, kind: Incident.Kind, position: Vector3) -> void:
	var incident := Incident.new()
	incident.perpetrator = perpetrator
	incident.kind = kind
	incident.position = position
	incident.timestamp = _now()
	_incidents.append(incident)
	_prune()
	incident_reported.emit(incident)


## True if perpetrator has an incident on record within the last
## within_seconds real seconds. Read-only query — does not prune; report()
## keeps the list bounded on its own schedule.
func has_recent_incident_by(perpetrator: Node3D, within_seconds: float) -> bool:
	var now := _now()
	for incident in _incidents:
		if incident.perpetrator == perpetrator and now - incident.timestamp <= within_seconds:
			return true
	return false


## Most recent incident on record, or null if none — read by debug tooling.
func get_latest_incident() -> Incident:
	if _incidents.is_empty():
		return null
	return _incidents[-1]


func _on_punch_landed(position: Vector3) -> void:
	report(_player, Incident.Kind.ASSAULT, position)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


## Drops incidents past max_incident_age (oldest first — the array is
## append-ordered, so the front is always the oldest) and, if still over
## max_incidents after that, drops the oldest remainder too.
func _prune() -> void:
	var now := _now()
	while not _incidents.is_empty() and now - _incidents[0].timestamp > max_incident_age:
		_incidents.pop_front()
	while _incidents.size() > max_incidents:
		_incidents.pop_front()
