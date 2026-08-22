# =============================================================================
# incident.gd — Incident, a single recorded fact: who, what, where, when.
#
# A real class, not a Dictionary — same reasoning as player_observation.gd:
# this project builds with warnings as errors, and a Dictionary would drag
# Variant into every consumer that reads a field off it. IncidentRegistry
# owns construction; nothing outside it should build one by hand.
#
# `perpetrator_id` is a plain StringName, not a Node3D: a node reference is
# meaningless after a reload, and meaningless once the block the reporting
# actor lived in has been streamed out. This is designed for WitnessSystem
# later, where the reporter may be any actor with something to say, not only
# the player — see actor_base.gd's own actor_id for where the id comes from.
# `kind` has exactly one value today (ASSAULT) — no placeholder values ahead
# of a producer that needs them, see CONTRIBUTING.md on not designing for
# hypothetical requirements.
#
# `timestamp` is game hours (GameClockSystem.total_game_hours), stamped by
# IncidentRegistry.report() — not real seconds. See that file's header for
# why: a fact that must survive a save/load boundary has to be timestamped
# in the time system that itself survives that boundary.
# =============================================================================
extends RefCounted
class_name Incident

## What happened. One value today — see the file header on why this isn't
## pre-populated with kinds nothing reports yet.
enum Kind { ASSAULT }

## HOW the city came to know, which is a different question from what
## happened and from who did it. DIRECT is the act itself entering the
## record — today that is player.gd's own punch handler, the world simply
## registering that something occurred. WITNESS_REPORT is a Votive
## transmission that ran its full duration and committed
## (IdleNPCController._commit_witness_report()).
##
## Consumers use this to separate two genuinely different channels, and the
## distinction is load-bearing rather than informational: a unit's OWN
## perception radius (PatrolDroneController.alert_incident_radius,
## IdleNPCController.earshot_radius) answers "did I notice this myself",
## and is unchanged by this field. A WITNESS_REPORT additionally reaches
## the whole city regardless of distance — that is what a report IS, and it
## is what makes a witness worth having. See NPC_REACTIONS.md §4.
enum Source { DIRECT, WITNESS_REPORT }

## Who did it — a stable actor id, not necessarily the player. See the file
## header.
var perpetrator_id: StringName = &""
## What happened.
var kind: Kind = Kind.ASSAULT
## Where it happened, world space.
var position: Vector3 = Vector3.ZERO
## When it happened, game hours (GameClockSystem.total_game_hours) — set by
## IncidentRegistry.report(), never by the caller.
var timestamp: float = 0.0
## How the city learned of it — see Source's own comment. Defaults to
## DIRECT so an incident built without thinking about it stays local, which
## is the conservative half of the pair.
var source: Source = Source.DIRECT
