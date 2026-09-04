# =============================================================================
# actor_memory_registry.gd — what individual actors personally remember.
#
# The durable home for something that already existed and already worked:
# IdleNPCController._remembers_player is set when an NPC sees an incident or
# is knocked down, is never cleared, and already sends a recognising NPC
# straight to RUNNING. What it could not do is outlive its own node. This
# registry is where that memory goes so it survives a block unloading and a
# save/load, exactly as IncidentRegistry does for the city's own record.
#
# NOT IncidentRegistry, and not a layer on top of it. That registry is what
# the CITY has on record; this is what one passer-by holds. Different
# lifetimes, different consumers, neither derived from the other.
#
# EVERY MEMORY AGES AT ITS OWN RATE. There is no single retention window
# here, which is the one structural difference from IncidentRegistry: a
# lifetime comes from how well the holder saw (lifetime_for()), so a
# silhouette across a square is gone in a few game hours and a face at arm's
# length lasts a week. That is one mechanism serving two separate contracts —
# the identity contract's rule that anything naming an identity must carry
# its own age or count bound, and docs/incident_knowledge_model.md §8's
# narrowed permission for a witness to read its OWN observation quality.
# Neither is optional, and both are satisfied by the same table.
#
# NO PROPAGATION BETWEEN ACTORS. Every query is about the caller's own
# holder_id. One actor remembering is the whole slice; an actor learning what
# another remembers is a separate decision nobody has made.
#
# Reached by group, not by WorldContext: the controllers that ask are static
# scene instances that never receive one — the same situation and the same
# fix IdleNPCController._try_resolve_incident_registry() already uses.
# =============================================================================
extends Node
class_name ActorMemoryRegistry

## Lookup group for controllers with no WorldContext — same role and same
## scheme as IncidentRegistry.GROUP_INCIDENT_REGISTRY.
const GROUP_ACTOR_MEMORY_REGISTRY: StringName = &"actor_memory_registry"

## A memory was written or strengthened. Nothing subscribes today; it exists
## so a debug panel can watch the record without polling it every frame,
## which is the only consumer this deserves before Task 7.
signal memory_recorded(memory: ActorMemory)

## How long a memory lasts, in GAME hours, by how well the holder saw.
##
## THE SHAPE IS THE POINT, and it is a clean x3 rather than a hand-picked
## curve. The first pass was 6 / 24 / 72 / 168, which reads as a rising
## progression and is not one — the ratios there are x4, x3, x2.3, i.e. it
## DECELERATES, so each better look bought proportionally less than the one
## before. Retuned 2026-09-04 (Stan: exponential, and the floor is 12 rather
## than 6): a face is worth three equipments, an iris three faces, all the way
## up. 324 game hours is 13.5 in-game days.
##
## Values tune by playing, the same status IncidentRegistry.max_incident_age
## has always had. What does NOT move is that a worse look must decay faster —
## without that, observation_level is not doing anything and the channel is
## decorative.
##
## NONE is absent on purpose rather than mapped to zero: an actor that did
## not see anything files no memory, and remember() refuses that case at the
## door instead of writing a row that expires immediately.
const LIFETIME_HOURS: Dictionary = {
	WitnessReport.ObservationLevel.SILHOUETTE: 12.0,
	WitnessReport.ObservationLevel.EQUIPMENT: 36.0,
	WitnessReport.ObservationLevel.FACE: 108.0,
	WitnessReport.ObservationLevel.IRIS: 324.0,
}

## Oldest memories are dropped past this count regardless of age — the hard
## ceiling against unbounded growth, the role max_incidents plays for
## IncidentRegistry. Higher than that one because these are per-actor rather
## than per-event: eighteen NPCs each remembering one thing is already
## eighteen rows, and that is a quiet afternoon.
##
## Not @export: this system is built with .new() from world.gd's
## WORLD_SYSTEM_SCRIPTS and has no node in any scene, so an export would draw
## an inspector field nobody can reach — the reason ComicEffectSystem's own
## tunables are const.
var max_memories: int = 64

var _memories: Array[ActorMemory] = []
## Source of truth for "now". Null only if this somehow initializes before
## GameClockSystem, which WORLD_SYSTEM_SCRIPTS' declared order in world.gd
## does not allow.
var _game_clock: GameClockSystem = null


func _ready() -> void:
	add_to_group(GROUP_ACTOR_MEMORY_REGISTRY)


func on_world_ready(context: WorldContext) -> void:
	_game_clock = context.get_system(GameClockSystem) as GameClockSystem


# -----------------------------------------------------------------------------
# ## ENG: Writing
# -----------------------------------------------------------------------------

## Holder remembers subject, having got `level` of a look at them.
##
## An existing memory is STRENGTHENED rather than replaced: the level becomes
## the best of the two and the timestamp becomes now. A clear look is not
## un-seen by a later glimpse from across the street, and seeing someone again
## is a reason to keep remembering them, not to start over at a worse grade.
##
## NONE is refused. An actor that saw nothing has nothing to remember, and a
## row that expires the instant it is written is worse than no row: it makes
## the record look like it holds something it does not.
func remember(
	holder_id: StringName, subject_id: StringName, level: WitnessReport.ObservationLevel
) -> void:
	if holder_id == &"" or subject_id == &"":
		## An actor with no id is EPHEMERAL under the identity contract, and
		## nothing may be filed against it. Silent rather than a warning:
		## once pooling exists this is the ordinary case for most of a crowd.
		return
	if level == WitnessReport.ObservationLevel.NONE:
		return

	var existing := _find(holder_id, subject_id)
	if existing != null:
		existing.observation_level = maxi(existing.observation_level, level) \
				as WitnessReport.ObservationLevel
		existing.timestamp = _now()
		_prune()
		memory_recorded.emit(existing)
		return

	var memory := ActorMemory.new()
	memory.holder_id = holder_id
	memory.subject_id = subject_id
	memory.observation_level = level
	memory.timestamp = _now()
	_memories.append(memory)
	_prune()
	memory_recorded.emit(memory)


# -----------------------------------------------------------------------------
# ## ENG: Queries
# -----------------------------------------------------------------------------

## Does holder still remember subject. Prunes first, so a caller can never
## read a memory that has already expired — the aging is invisible to
## consumers, which is what lets IdleNPCController keep asking one question.
func remembers(holder_id: StringName, subject_id: StringName) -> bool:
	_prune()
	return _find(holder_id, subject_id) != null


## The level holder remembers subject at, or NONE when it does not. Separate
## from remembers() because a consumer that wants to act on HOW WELL the
## holder saw should not have to re-derive it — see §8's narrowed permission
## in docs/incident_knowledge_model.md.
func recall_level(
	holder_id: StringName, subject_id: StringName
) -> WitnessReport.ObservationLevel:
	_prune()
	var memory := _find(holder_id, subject_id)
	if memory == null:
		return WitnessReport.ObservationLevel.NONE
	return memory.observation_level


## How long a memory at this level lasts, game hours. 0.0 for a level with no
## entry, which is NONE and means "not a memory at all".
func lifetime_for(level: WitnessReport.ObservationLevel) -> float:
	return LIFETIME_HOURS.get(level, 0.0)


## Live memory count, after pruning. Debug tooling and the verification probe.
func get_memory_count() -> int:
	_prune()
	return _memories.size()


# -----------------------------------------------------------------------------
# ## ENG: Save contract — walked by SaveSystem like any other system
# -----------------------------------------------------------------------------

func get_save_key() -> StringName:
	return &"actor_memory"


## Primitives only, per SaveSystem's contract — StringName and the enum are
## flattened to String and int, the same way IncidentRegistry flattens its own.
func get_save_data() -> Dictionary:
	var saved: Array = []
	for memory in _memories:
		saved.append({
			"holder_id": String(memory.holder_id),
			"subject_id": String(memory.subject_id),
			"observation_level": int(memory.observation_level),
			"timestamp": memory.timestamp,
		})
	return {"memories": saved}


## Replaces the list outright rather than merging — a load is a full restore,
## not an append, the same reading IncidentRegistry.load_save_data() takes.
## Pruned afterwards, so a save left running past a memory's lifetime does not
## restore expired rows.
func load_save_data(data: Dictionary) -> void:
	_memories.clear()
	for entry_variant in data.get("memories", []) as Array:
		var entry := entry_variant as Dictionary
		var memory := ActorMemory.new()
		memory.holder_id = StringName(entry.get("holder_id", ""))
		memory.subject_id = StringName(entry.get("subject_id", ""))
		memory.observation_level = int(
			entry.get("observation_level", WitnessReport.ObservationLevel.NONE)
		) as WitnessReport.ObservationLevel
		memory.timestamp = float(entry.get("timestamp", 0.0))
		_memories.append(memory)
	_prune()


# -----------------------------------------------------------------------------
# ## ENG: Internals
# -----------------------------------------------------------------------------

func _find(holder_id: StringName, subject_id: StringName) -> ActorMemory:
	for memory in _memories:
		if memory.holder_id == holder_id and memory.subject_id == subject_id:
			return memory
	return null


## Drops expired memories, then the oldest remainder if still over the count
## cap.
##
## A filtering pass rather than IncidentRegistry's pop_front() loop, and that
## is forced rather than chosen: every memory here has its OWN lifetime, so
## append order is not expiry order — a fresh silhouette expires before an
## older face, and popping from the front would drop the wrong one.
func _prune() -> void:
	var now := _now()
	var kept: Array[ActorMemory] = []
	for memory in _memories:
		if now - memory.timestamp <= lifetime_for(memory.observation_level):
			kept.append(memory)
	_memories = kept

	while _memories.size() > max_memories:
		var oldest := 0
		for i in _memories.size():
			if _memories[i].timestamp < _memories[oldest].timestamp:
				oldest = i
		_memories.remove_at(oldest)


func _now() -> float:
	if _game_clock == null:
		push_warning("[ActorMemory] GameClockSystem not resolved — timestamping as 0.0")
		return 0.0
	return _game_clock.total_game_hours
