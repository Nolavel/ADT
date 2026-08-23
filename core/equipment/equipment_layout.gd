# =============================================================================
# equipment_layout.gd — which body slots a character has.
#
# This is the answer to "who registers the slots", which was the one genuinely
# open question in the equipment design (docs/planned_scope.md): a component
# with a register_slot() nobody calls is an unfinished contract. The layout is
# a Resource assigned on the character, not constants inside the component, so
# a different character or a different build of the same one is data rather
# than an edit.
#
# It describes the BODY only — legs, torso, feet, back-pack, back-unique.
# Pockets are NOT here: slot count is a property of the garment, and a
# garment brings its own (see GarmentData). That split is what makes clothing
# replaceable — a different jacket brings a different number of pockets, and
# the character does not change.
# =============================================================================
extends Resource
class_name EquipmentLayout

## The fixed places on this character that hold a garment or a piece of
## equipment. Order is presentation only; lookup is by
## EquipmentSlotDefinition.id.
@export var body_slots: Array[EquipmentSlotDefinition] = []


## The slot with this id, or null. Silent — "is there such a slot" is a
## legitimate question with a legitimate no.
func find_slot(slot_id: StringName) -> EquipmentSlotDefinition:
	for slot in body_slots:
		if slot != null and slot.id == slot_id:
			return slot
	return null
