# =============================================================================
# witness_report.gd — WitnessReport, a witness's own statement about an
# incident they observed. Never a conclusion about who did it.
#
# docs/attribution.md section 1's central boundary: OBSERVATION is not CRIME,
# REPORT is not IDENTIFICATION. A witness knows what they saw, not who did it
# — this class has no field a suspect could ever be written into, on purpose.
# IdleNPCController (npc/controllers/) is the only producer; it owns
# construction the same way IncidentRegistry owns Incident's.
#
# observation_level is resolved once, at report creation (attribution.md
# section 2/section 7), and never changes afterward — a witness cannot walk
# closer and retroactively recognise a face. It is written and read by
# nothing else in this build: section 5 (attribution) is the deferred
# consumer, not scheduled. That is intentional, not dead code — see
# attribution.md section 7's own paragraph on this field before "cleaning it
# up".
#
# observed_equipment (attribution.md section 4's full struct) is deliberately
# NOT a field here: nothing in this build populates it — no clothing/held-item
# detection exists — and an empty field would read as the same kind of promise
# player_observation.gd's own header warns against for its missing held-item
# field. Add it only alongside whatever system would actually fill it in.
# =============================================================================
extends RefCounted
class_name WitnessReport

## docs/attribution.md section 2's ladder, collapsed to what distance alone
## resolves for this slice (PERSON is not a distinct achievable ceiling in
## the section 2 distance table, so it is omitted rather than left
## unreachable).
enum ObservationLevel { NONE, SILHOUETTE, EQUIPMENT, FACE, IRIS }

## PENDING while the Votive is transmitting; COMMITTED once the transmission
## completes and the report is actually sent; CANCELLED if the witness is
## suppressed first (attribution.md section 6/section 7).
enum Status { PENDING, COMMITTED, CANCELLED }

## The reporting NPC's own actor id (ActorBase.actor_id) — who is talking,
## never who they saw. See the file header on why there is no suspect field.
var witness_id: StringName = &""

## Resolved once by IdleNPCController._resolve_observation_level() — see the
## file header on why this is written and not yet read.
var observation_level: ObservationLevel = ObservationLevel.NONE

## Real-world seconds (Time.get_ticks_msec() / 1000.0) at the moment the
## report was created — not GameClockSystem.total_game_hours: unlike
## Incident, a WitnessReport is never saved (see IdleNPCController's own
## header on why extending IncidentRegistry's save format is out of scope
## for this slice), so it has no save/reload boundary to survive, and the
## real clock is simpler for a value nothing reads yet.
var observed_at: float = 0.0

## Witness's own position at the moment of observation — attribution.md
## section 4's "for later line-of-sight reasoning". Unread today, same as
## observation_level.
var observed_from: Vector3 = Vector3.ZERO

var status: Status = Status.PENDING
