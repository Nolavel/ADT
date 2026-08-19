# =============================================================================
# witness_debug_system.gd — WitnessDebugSystem, a WORLD_SYSTEM_SCRIPTS entry
# (world.gd), created via .new() like every other Node-system.
#
# The witness/Call numbers (IdleNPCController.witness_density,
# call_probability, and every archetype's own vision_range) are correct BY
# DESIGN: in Doggerland almost nobody reports anything, which is why a
# playtest sees a Call maybe once every three or four punches, if the victim
# is lucky enough to be near a witness at all — see the incident telemetry
# from the previous task, which is what surfaced this as the actual problem:
# the mechanic works, the honest numbers are just too rare to observe on
# demand. This system exists to make the CHAIN observable on every hit
# during a test, without ever touching those honest numbers — the .tres
# archetypes and IdleNPCController's own exports stay exactly as authored.
#
# ONE switch (enabled), toggled by a hotkey (InputSystems.
# witness_debug_toggled, action "toggle_witness_debug", "[") rather than an
# @export in the inspector (see world_border_debug.gd's own note on that
# alternative) — the requirement is "on for the whole crowd, live, during
# play, no restart," and eighteen NPCs each carrying their own @export would
# defeat that outright (see this task's own brief). Not a new autoload: the
# autoload set is closed, but a WORLD_SYSTEM_SCRIPTS entry is not an
# autoload — it is an ordinary Node world.gd instantiates once and parents to
# itself, same as IncidentRegistry/LodgingSystem.
#
# IdleNPCController never receives a WorldContext (it is a per-NPC child
# node inside npc.tscn, not one of world.gd's three composition-root lists),
# so it cannot reach this system through context.get_system() the way an
# on_world_ready() consumer would. It resolves this system the exact same
# way it already resolves IncidentRegistry: a lazy, retried group lookup
# (GROUP_WITNESS_DEBUG_SYSTEM) — see idle_npc_controller.gd's own
# _try_resolve_witness_debug(). No timeout warning like IncidentRegistry's
# own missing-registry case: a missing WitnessDebugSystem just means the
# debug mode silently isn't available yet, not a bug worth nagging about —
# same "unset is a no-op" contract NPCArchetypeData already uses.
#
# THE SUBSTITUTION LIVES IN ONE PLACE. idle_npc_controller.gd's own decision
# logic (_on_incident_reported(), _evaluate_incident_vision()) never checks
# `enabled` itself and never learns this system exists — it calls four small
# _effective_*() getters instead of reading witness_density/call_probability/
# earshot_radius/_perception.vision_range directly, and those getters are
# the only place that know about WitnessDebugSystem at all. This was a
# deliberate requirement, not a style preference: scattering `if debug` next
# to the actual reaction rolls would make the decision logic itself harder
# to read for a change that has nothing to do with reaction selection.
#
# vision_range_multiplier and earshot_radius_multiplier are separate
# @export values, not one shared multiplier, even though both default to
# the same ~3.0 — sight and hearing are different channels in this design
# (attribution.md §2's vision cone versus NPC_REACTIONS.md's earshot_radius),
# and silently tying them together would make a bug in one channel look like
# a bug in both, or hide one behind the other, during exactly the kind of
# test this system exists to make legible.
#
# witness_density/call_probability are forced to a flat 1.0 rather than also
# being @export multipliers: they are probabilities, where "guaranteed" is
# the natural ceiling for a debug mode built to prove the chain fires at
# all — a multiplier on a 0..1 fraction would just be a second way to write
# "clamp to 1.0" for most starting values. vision_range/earshot_radius are
# continuous distances that vary per archetype (a Thug sees less far than a
# Clerk); MULTIPLYING each archetype's own value preserves that spread while
# still pulling everyone into typical incident range, where forcing every
# archetype to one identical constant would erase exactly the per-archetype
# difference a playtest might want to see.
#
# _is_witness (IdleNPCController) is rolled ONCE per NPC in _ready(), before
# this system's enabled state can possibly be known — toggling mid-session
# cannot retroactively flip an NPC that already rolled false. Re-rolling
# every NPC's flag on toggle was considered and rejected: it would need a
# second lazy-broadcast mechanism (every controller listening for a re-roll
# request) to fix a field this system has no reason to reach into directly.
# Instead, _effective_is_witness() checks `enabled` at the moment a witness
# candidacy is actually evaluated, per incident, and treats every candidate
# as a witness while debug mode is on regardless of what was rolled at spawn
# — simpler and correct for exactly the case that matters (every future
# incident is observable), without a second broadcast path to keep in sync.
# =============================================================================
extends Node
class_name WitnessDebugSystem

## Lookup group for controllers that cannot reach this system through a
## WorldContext (see the file header) — same discovery pattern as
## IncidentRegistry.GROUP_INCIDENT_REGISTRY.
const GROUP_WITNESS_DEBUG_SYSTEM: StringName = &"witness_debug_system"

@export_group("Multipliers")
## Multiplies the incident-vision range check only (idle_npc_controller.gd's
## own _evaluate_incident_vision(), not PerceptionComponent.vision_range
## itself, which stays untouched — sensing is out of scope for this task).
## A feel value, tuned by eye; the task's own starting point is ~3.0.
@export var vision_range_multiplier: float = 3.0
## Multiplies earshot_radius. Deliberately independent from
## vision_range_multiplier — see the file header on why hearing and sight
## are not tied together here.
@export var earshot_radius_multiplier: float = 3.0

## The one switch. Read live by IdleNPCController's _effective_*() getters
## every time they're called — never cached by a reader, so a toggle takes
## effect on the very next incident with no re-initialization step anywhere.
var enabled: bool = false


func _ready() -> void:
	add_to_group(GROUP_WITNESS_DEBUG_SYSTEM)
	InputSystems.witness_debug_toggled.connect(_on_toggle_pressed)


## Flips enabled and prints an unmissable warning either way — see the file
## header on why silence here is the actual risk: a forgotten override
## quietly shapes a month of playtest impressions about a "broken" or
## "too aggressive" witness chain that was never running honest numbers.
func _on_toggle_pressed() -> void:
	enabled = not enabled
	if enabled:
		var message := (
			"[WitnessDebugSystem] ENABLED — witness numbers are NOT the shipped "
			+ "values. witness_density -> 1.0, call_probability -> 1.0, "
			+ "vision_range x%.1f, earshot_radius x%.1f. Disable (\"[\") before "
			+ "drawing any conclusion about witness balance."
		) % [vision_range_multiplier, earshot_radius_multiplier]
		push_warning(message)
	else:
		push_warning("[WitnessDebugSystem] disabled — honest witness numbers restored.")
