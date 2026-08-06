# =============================================================================
# incident.gd — Incident, a single recorded fact: who, what, where, when.
#
# A real class, not a Dictionary — same reasoning as player_observation.gd:
# this project builds with warnings as errors, and a Dictionary would drag
# Variant into every consumer that reads a field off it. IncidentRegistry
# owns construction; nothing outside it should build one by hand.
#
# `perpetrator` is a plain Node3D, not a narrower type: this is designed for
# WitnessSystem later, where the reporter may be any actor with something to
# say, not only the player. `kind` has exactly one value today (ASSAULT) —
# no placeholder values ahead of a producer that needs them, see
# CONTRIBUTING.md on not designing for hypothetical requirements.
#
# `timestamp` is real seconds (Time.get_ticks_msec() / 1000.0), stamped by
# IncidentRegistry.report() — see that file's header for why real time was
# chosen over GameClockSystem's game-hours.
# =============================================================================
extends RefCounted
class_name Incident

## What happened. One value today — see the file header on why this isn't
## pre-populated with kinds nothing reports yet.
enum Kind { ASSAULT }

## Who did it. Not necessarily the player — see the file header.
var perpetrator: Node3D = null
## What happened.
var kind: Kind = Kind.ASSAULT
## Where it happened, world space.
var position: Vector3 = Vector3.ZERO
## When it happened, real seconds since engine start (Time.get_ticks_msec() /
## 1000.0) — set by IncidentRegistry.report(), never by the caller.
var timestamp: float = 0.0
