# =============================================================================
# actor_memory.gd — one actor's memory of having seen another.
#
# Deliberately NOT an Incident. An Incident is what the CITY has on record;
# this is what one passer-by personally remembers, and the two have different
# lifetimes, different consumers and no derivation between them.
# IdleNPCController's own _remembers_player comment already drew that line —
# this keeps it drawn now that the memory outlives its holder.
#
# WHAT IT DOES NOT CARRY: where it happened, and what happened. Both are
# already in IncidentRegistry, and duplicating the city's record inside a
# bystander's head buys nothing and gives two places to disagree.
#
# `timestamp` is GAME HOURS (GameClockSystem.total_game_hours), never engine
# uptime — the same reason Incident.timestamp is: Time.get_ticks_msec()
# resets on launch, so anything that must survive a save has to be stamped by
# the one clock that survives it too.
#
# `observation_level` is what makes this record age at its own rate rather
# than on one global timer — see ActorMemoryRegistry.lifetime_for().
# =============================================================================
extends RefCounted
class_name ActorMemory

## Who remembers. An actor_id, per the identity contract in
## docs/architecture/npc_and_incidents.md — authored today, allocated once
## pooling exists, and indistinguishable to this record either way.
var holder_id: StringName = &""

## Who is remembered. The player today; nothing here assumes that.
var subject_id: StringName = &""

## How good a look the holder got. The BEST one it has ever got of this
## subject, not the most recent — a clear look is not un-seen by a later
## glimpse from across the street.
var observation_level: WitnessReport.ObservationLevel = WitnessReport.ObservationLevel.NONE

## When the holder last had a reason to remember, in game hours.
var timestamp: float = 0.0
