# =============================================================================
# garment_data.gd — the facet that makes an item wearable.
#
# Attached to an ItemResource through its optional `garment` field. Null means
# "not a garment", and that is the ordinary case — the same "unset is a no-op"
# contract NPCBase.archetype already uses. A can of food does not carry empty
# garment fields.
#
# A garment does two things: it occupies one body slot, and it brings its own
# pockets. The second is the load-bearing half — **slot count belongs to the
# garment, not the character**. A jacket with four pockets and a jacket with
# none are both legitimate jackets, and swapping one for the other changes
# what the player can carry without touching the character at all.
#
# Consequence worth knowing: concealed carry is granted by the garment. Take
# the jacket off and the pistol has nowhere to hide, because the pocket left
# with it.
# =============================================================================
extends Resource
class_name GarmentData

## Which body slot this occupies, by the id the character's EquipmentLayout
## defines. An id no layout knows is refused at equip time with a warning —
## it does not fail silently.
@export var body_slot_id: StringName = &""

## The pockets this garment brings. Empty is valid and means exactly what it
## says: a garment you cannot put anything in.
@export var pockets: Array[EquipmentSlotDefinition] = []

## The skinned MeshInstance3D that IS this garment on screen, named rather
## than pathed. A NodePath would be scene-specific and would not survive
## being read by an NPC; the name is a convention both rigs already satisfy
## (npc.tscn carries the same five mesh names as player.tscn).
##
## Clothing is a skinned mesh whose visibility is toggled, never a
## BoneAttachment3D child — a bone attachment follows one bone rigidly, which
## is right for a prop and wrong for trousers, which bend at the knee.
##
## Empty means "no visual yet", which is the honest state of a garment whose
## mesh has not been authored. One name, not a list: nothing today needs two,
## and a list would be a placeholder ahead of its own producer.
@export var mesh_node_name: StringName = &""
