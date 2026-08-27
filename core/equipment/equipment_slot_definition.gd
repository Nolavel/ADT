# =============================================================================
# equipment_slot_definition.gd — one socket, described as data.
#
# The same class describes a BODY slot (what the character has: legs, torso,
# feet, back-pack, back-unique) and a POCKET (what a garment brings with it).
# They are the same thing — a place that holds exactly one item, with a limit
# on what may go there — so they are not two classes.
#
# A socket, not a grid. Fit is one comparison against max_size; there is no
# packing, no rotation and no cell layout. See docs/planned_scope.md for why
# that is a design decision rather than a shortcut.
# =============================================================================
extends Resource
class_name EquipmentSlotDefinition

## Stable authored identity, unique within its owner (a layout, or one
## garment). StringName because this is an identity, the kind ActorBase's
## actor_id and LodgingRoom's room_id already are — not a state, which is
## what the enums are for. A garment names the body slot it occupies by this
## id, so a typo surfaces as "no such slot" rather than doing nothing
## quietly.
@export var id: StringName = &""

## Human-facing label, for debug output and a future inventory screen.
@export var display_name: String = ""

## The largest item this socket accepts. A jacket pocket is POCKET; the
## back-pack slot is BULKY.
@export var max_size: ItemTraits.SizeClass = ItemTraits.SizeClass.POCKET

## Refuse anything that reads as a threat to an observer. True on the
## back-unique slot and nowhere else today: a rifle slung across the back is
## a statement the player should have to make deliberately, not a storage
## decision. A pocket does not need this — its contents are not on display.
@export var refuses_threatening: bool = false

## May something that is NOT a garment go here. False everywhere clothing is
## worn (legs/torso/feet) and on every pocket — a pocket already holds loose
## items, and this question is only about BODY slots.
##
## True on the two back slots, because a long gun has nowhere else to be:
## it is CARRIED, so no jacket pocket takes it, and refusing it on the body
## too would mean a rifle could be picked up and then instantly dropped for
## want of anywhere to put it. max_size cannot answer this on its own —
## legs/torso/feet are CARRIED-sized as well, and a carbine strapped to a
## leg is not what that slot means.
##
## refuses_threatening still applies on top, and still decides which of the
## two back slots an automatic stow may use.
@export var accepts_non_garment: bool = false
