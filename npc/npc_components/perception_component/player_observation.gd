# =============================================================================
# player_observation.gd — PlayerObservation, a plain fact PerceptionComponent
# hands back, never an interpretation of it.
#
# "The player is twelve metres away, with a clear line of sight" is a fact.
# What that fact MEANS is decided by whoever consumes it, differently for
# different consumers — a street vendor reacts to it one way, a patrol
# another, a future evidence system a third. If perception started deciding
# for them, that split would be lost and would have to be rebuilt by
# rewriting this file every time a new kind of consumer showed up.
#
# A real class, not a Dictionary: this project builds with warnings as
# errors, and a Dictionary would drag Variant into every consumer that reads
# a field off it.
#
# Fields are exactly what perception measures TODAY. No stance field, no
# held-item field — those systems don't exist yet, and an empty field here
# would read as a promise the same way an empty placeholder file does (see
# CONTRIBUTING.md). This class is itself the extension point: a new field
# is an additive change, never a break for existing consumers, which is
# exactly why this isn't a tuple.
# =============================================================================
extends RefCounted
class_name PlayerObservation

## True when the player is inside the vision cone, within range, and not
## occluded. False means "not seen", not "not there".
var is_seen: bool = false
## Metres from the NPC's eye to the player. Valid even when is_seen is false,
## as long as the player exists — proximity is knowable without sight.
var distance: float = INF
## Degrees between the NPC's facing direction and the direction to the
## player, horizontal. Valid regardless of is_seen.
var angle_deg: float = 180.0
## Where the player was when this observation was taken.
var position: Vector3 = Vector3.ZERO
