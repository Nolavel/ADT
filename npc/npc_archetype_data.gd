# =============================================================================
# npc_archetype_data.gd — NPCArchetypeData, one row of docs/npc_archetypes.md
# as data. Assigned to NPCBase.archetype; applied once in NPCBase._ready()
# via _apply_archetype().
#
# Carries three of the document's four readability channels (§3):
# silhouette & clothing, gait, attention. The fourth, density & mix, is not a
# field here — §5's per-stratum composition table is about how many of each
# archetype a scene places, not a property of one NPC, so it lives in scene
# data (which .tres each hand-placed NPC gets, and how many of each) rather
# than on this resource.
#
# placeholder_color is deliberately its own field, not the archetype's
# identity: §4 calls flat colour "scaffolding, not the design," meant to be
# replaced by a mesh/material variant later. NPCBase._apply_archetype()
# applies colour, gait and perception as three independent steps precisely
# so that swap touches only the colour step, not this resource or the other
# two channels.
#
# Witness (§2) still has no visual-identity field here — that remains a flag
# layered onto an instance of one of these five archetypes, later (H4,
# docs/scope_horizon.md). is_witness_caller (below) is a narrower thing: not
# identity, just whether this archetype ever reports what it witnesses —
# replacing the population-wide witness_density/call_probability pair that
# used to live on IdleNPCController with a deterministic per-archetype trait.
# =============================================================================
extends Resource
class_name NPCArchetypeData

## Matches npc_archetypes.md §1/§2 naming, for debug/reporting only — never
## branched on in code. The fields below are what behaviour actually reads.
@export var archetype_name: String = ""

@export_group("Two axes (§1)")
## "Worth taking?" — does this archetype carry anything worth robbing. Not
## consumed by any system yet (no search/robbery system exists — see
## planned_scope.md's Combat entry); carried now so this resource matches
## the spec in full rather than growing a second time once that system
## lands.
@export var worth_taking: bool = false
## "Watching me?" — alert vs absorbed. Drives the Attention channel exports
## below; kept as its own bool so the archetype's declared intent stays
## legible even though vision_range/vision_angle_deg are the actual
## mechanism a player will feel.
@export var alert: bool = false

@export_group("Silhouette & clothing (§3)")
## Prototype-stage stand-in for a mesh/material variant — §4 sanctions flat
## colour explicitly ("scaffolding, not the design"). Applied as
## material_override across body meshes tagged `archetype_body_mesh` in
## npc.tscn, so the whole silhouette reads as one flat colour without
## recolouring component-owned geometry (Votive, future equipment).
@export var placeholder_color: Color = Color.WHITE

@export_group("Gait (§3)")
## Multiplier on NPCBase.walk_speed. Posture and animation-set variation
## (also named by §3 as carrying this channel) are not implemented —
## NPCAnimationComponent has one idle<->walk blend and no per-archetype
## variants, and building those is explicitly delegated to a contributor in
## §6, not built this pass.
@export var walk_speed_multiplier: float = 1.0

@export_group("Attention (§3)")
## Fed into this NPC's sibling PerceptionComponent.vision_range/
## vision_angle_deg when applied — configuration, not a change to
## PerceptionComponent itself. An alert archetype notices the player from
## further away and across a wider cone; an absorbed one barely notices at
## all.
@export var vision_range: float = 8.0
@export var vision_angle_deg: float = 45.0

@export_group("Incident response (NPC_REACTIONS.md §4)")
## Probability this archetype flees rather than freezes-and-stares when it
## reacts to a nearby incident. A BIAS, not a rule: §4 is explicit that the
## crowd reacts by chance, and a deterministic "this archetype always flees"
## would turn the crowd into a lookup table — precisely what NPC_REACTIONS.md
## §2's "street literacy, learned by observation" argues against. Loosely
## tuned from the `alert` axis above (absorbed leans Flee, alert leans
## Freeze) but kept as its own number rather than derived from `alert` in
## code, so it can be retuned without changing what `alert` means.
@export_range(0.0, 1.0) var flee_probability: float = 0.5
## Patrolman-only — npc_archetypes.md §1 places it outside the two-axis
## grid entirely. True here means this archetype ignores flee_probability
## and the witness/Call check and instead walks toward the incident; that
## is its own behaviour, not a third crowd reaction. A patrolman already
## responds institutionally by going there, so it never also calls it in.
@export var responds_by_approaching: bool = false
## Whether this archetype ever calls in an incident it witnesses
## (docs/attribution.md §7) — deterministic, not a roll: replaces the old
## population-wide witness_density/call_probability pair that used to live
## on IdleNPCController. Clerk is the only archetype with this set true
## today; everyone else never becomes a caller, however clearly they saw
## the incident. `responds_by_approaching` above takes priority over this
## for Patrolman (see that field's own comment) — the two are mutually
## exclusive in practice, not because either checks the other.
@export var is_witness_caller: bool = false
