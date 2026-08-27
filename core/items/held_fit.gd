# =============================================================================
# held_fit.gd — how one item sits in a hand.
#
# An optional sub-resource on ItemResource, the same "unset is a no-op" shape
# ItemResource.garment already uses: null means the item hangs at the grip
# pivot's own origin, which is a legitimate answer for anything roughly
# shaped like the pivot expects.
#
# WHY THIS IS PER-ITEM AND NOT PER-CHARACTER: it used to be two exports on
# EquipmentVisualsComponent, shared by everything ever drawn. Those numbers
# were tuned against the pistol, and the carbine inherited them — a component
# cannot hold a pose for geometry it knows nothing about. Where the hand is
# belongs to the character (the GripPivot nodes under each
# BoneAttachment3D); how the object sits in that hand belongs to the object.
#
# The values are in WORLD METRES, not skeleton units. player.tscn's
# player_base_mesh carries a uniform 0.38763407 scale, so the grip pivots
# carry its reciprocal and everything below them is metric — see
# EquipmentVisualsComponent's scale check, which fails loudly if that ever
# stops being true.
#
# Authored by addons/item_fitter/ rather than by hand: a grip is judged by
# eye against a running animation, which is exactly what a number in a text
# file cannot be.
#
# Deliberately its own Resource rather than three fields on ItemResource:
# the same shape is wanted again for where a weapon sits while STOWED (on the
# back, on a thigh), and that wants to be a second field of this type, not
# three more fields with a prefix.
# =============================================================================
extends Resource
class_name HeldFit

## Which hand this item is held in. The mesh attaches to ONE hand; a
## two-handed weapon is still attached to one, with the other placed by
## whatever the animation clips do — there is no second attachment and a
## wrong-looking off hand is an animation question, not a fit one.
##
## TODO(equipment): a parallel design (`ItemPose`, prototyped in
## tools/for_claude_addon_item_/ and deleted on 2026-08-27 — see the
## CHANGELOG for why) went further here and is worth taking if the carbine's
## off hand reads wrong: a SECOND mesh instance in the other hand with its
## own independent transform, so a long gun is posed at both grips rather
## than at one. That is two more Vector3 fields on this resource, a second
## instance in EquipmentVisualsComponent, and a second preview in the
## fitter. Not built, because nothing has been judged wrong by eye yet.
##
## The same prototype also proposed optional grip MARKERS on the item (a
## NodePath to a Marker3D, so the transform becomes a fine offset from a
## named point rather than from the mesh origin). That one is already
## answered differently: the carbine mesh has its origin AT its grip, which
## buys the same thing without a node per item.
enum Hand {
	RIGHT,
	LEFT,
}

@export var hand: Hand = Hand.RIGHT
## Position inside the grip pivot, in metres.
@export var offset: Vector3 = Vector3.ZERO
## Rotation inside the grip pivot, in degrees.
@export var rotation_deg: Vector3 = Vector3.ZERO
## Rarely anything but ONE. Here so a placeholder mesh authored at the wrong
## size can be corrected without regenerating it — not as a way to make a
## weapon bigger than it is.
@export var scale: Vector3 = Vector3.ONE
