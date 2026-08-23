# =============================================================================
# item_traits.gd — the vocabulary an item and a slot both have to speak.
#
# Two enums, no state, never instantiated — the same shape CollisionLayers
# uses for the layer table. They live here rather than on ItemResource for a
# concrete reason: EquipmentSlotDefinition has to name a size class, and
# ItemResource has to reach GarmentData, which reaches slot definitions. Put
# the enums on ItemResource and that becomes a cycle GDScript resolves badly.
# A vocabulary nothing else depends on breaks it.
#
# Enums rather than strings or bare ints on purpose: a mistyped tag fails
# silently, an enum fails at parse time. Identities stay StringName — see
# EquipmentSlotDefinition.id.
# =============================================================================
extends RefCounted
class_name ItemTraits


## Does this fit that socket. Three steps, because three is what today's
## rules actually need — a pistol has to fit a jacket pocket and a rifle has
## to not. A fourth is added when something needs it, not ahead of time.
enum SizeClass {
	## Fits in a pocket: a can, a pistol, a tool.
	POCKET,
	## Too big to pocket; carried, slung or strapped.
	CARRIED,
	## Needs a pack, a vehicle, or both hands.
	BULKY,
}


## How the item reads to someone looking at the player. This is the axis the
## city sees, and it is the only reason "a machine gun on your back gives
## away your intent" can be expressed at all — the rule is about observers,
## so it cannot live anywhere except on the item.
##
## Deliberately the smallest slice of the wider item model
## (docs/planned_scope.md): one axis, added because an agreed rule needs it.
## NPC reaction and Iris Access are expected to read the same field later.
enum Readability {
	## Can be hidden under clothing. Worn openly it is still visible — this
	## says it CAN be concealed, not that it is.
	CONCEALABLE,
	## Visible and unremarkable. A bag, a coat, a lunch tin.
	ORDINARY,
	## Visible and reads as intent. Refused by any slot that would put it on
	## open display.
	THREATENING,
}
