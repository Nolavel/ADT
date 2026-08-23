# =============================================================================
# equipment_component.gd — what is worn, and what is in its pockets.
#
# Two levels, and the split is the whole design (docs/planned_scope.md):
#
#   BODY SLOTS   fixed on the character, described by an EquipmentLayout
#                assigned in the inspector. legs / torso / feet / back_pack /
#                back_unique. They hold garments and equipment.
#   POCKETS      NOT fixed. Each equipped garment brings its own
#                (GarmentData.pockets), so taking a jacket off takes its
#                pockets — and whatever they could have hidden — with it.
#
# Holds item IDs, never ItemResource references. That is not a style choice:
# SaveSystem's payload rule is dictionaries, arrays and primitives only, so a
# slot holding an object would be unsaveable by construction. ItemCatalog
# resolves an id when this component actually needs the item's traits.
#
# Knows nothing about inventory, meshes, bones or stance. equip() into an
# occupied slot REFUSES rather than swapping — see that method for why an
# implicit swap is the bug this avoids. Routing a displaced item somewhere is
# the caller's job, and today there is no caller: this step is the rules, not
# the wiring.
#
# Reached by the save file through PlayerPersistenceSystem, which walks the
# player's direct children — so this must stay a direct child of Player.
# =============================================================================
extends Node
class_name EquipmentComponent

## A slot changed. `slot_path` is a body slot id, or "<body_slot>/<pocket>"
## for a pocket. `item_id` is &"" when the slot was emptied.
signal slot_changed(slot_path: StringName, item_id: StringName)

## Why an equip was refused — surfaced so a caller can tell the player
## something true instead of failing silently.
enum Refusal {
	NONE,
	## No slot by that id, on the layout or on any equipped garment.
	NO_SUCH_SLOT,
	## The id resolves to no item in ItemCatalog.
	UNKNOWN_ITEM,
	## Something is already there. Deliberately not an implicit swap.
	SLOT_OCCUPIED,
	## Bigger than the socket takes.
	TOO_LARGE,
	## Reads as a threat, and this slot puts its contents on display.
	READS_AS_THREAT,
	## Not a garment, or a garment for a different body slot.
	WRONG_BODY_SLOT,
	## A garment cannot come off while its own pockets still hold something.
	POCKETS_NOT_EMPTY,
}

## Separator between a body slot id and a pocket id in a slot path. Pocket
## ids are only unique within one garment, so they are addressed through the
## body slot the garment occupies.
const POCKET_SEPARATOR: String = "/"

## Which body slots this character has. Assigned in the inspector —
## res://data/equipment/player_layout.tres for the player. Without one this
## component is inert rather than broken: every equip is refused with
## NO_SUCH_SLOT.
@export var layout: EquipmentLayout = null

## Worn from the first frame, in order. The character starts dressed — there
## is no undressed baseline (docs/planned_scope.md). Overwritten wholesale by
## load_save_data() when a save is restored, which is the correct precedence:
## the file knows what was actually worn.
@export var starter_garment_ids: Array[StringName] = [
	&"starter_jumpsuit",
	&"starter_boots",
]

## Prints every accepted and refused change. Off by default; there is no UI
## for equipment yet, so this is the only way to see it work.
@export var debug_log: bool = false

## body slot id -> item id. Only ever holds ids.
var _body: Dictionary = {}
## "<body slot>/<pocket>" -> item id.
var _pockets: Dictionary = {}


func _ready() -> void:
	_equip_starter_garments()


# -----------------------------------------------------------------------------
# ## ENG: Queries
# -----------------------------------------------------------------------------

## The item in a body slot, or &"" when empty.
func get_equipped(slot_id: StringName) -> StringName:
	return _body.get(slot_id, &"")


## The item in a pocket, or &"" when empty.
func get_pocket_item(body_slot_id: StringName, pocket_id: StringName) -> StringName:
	return _pockets.get(_pocket_path(body_slot_id, pocket_id), &"")


## Every pocket currently available, in body-slot order. Availability is
## derived from what is worn RIGHT NOW — a pocket exists only while the
## garment carrying it is on.
func get_available_pockets() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if layout == null:
		return found
	for body_slot in layout.body_slots:
		if body_slot == null:
			continue
		var garment := _garment_in(body_slot.id)
		if garment == null:
			continue
		for pocket in garment.pockets:
			if pocket == null:
				continue
			found.append({
				"body_slot": body_slot.id,
				"pocket": pocket.id,
				"definition": pocket,
				"item_id": get_pocket_item(body_slot.id, pocket.id),
			})
	return found


## Refusal.NONE means this would be accepted. Pure query — changes nothing,
## so a UI can grey a slot out without attempting the move.
func can_equip(slot_id: StringName, item_id: StringName) -> Refusal:
	var definition := _find_body_slot(slot_id)
	if definition == null:
		return Refusal.NO_SUCH_SLOT
	if get_equipped(slot_id) != &"":
		return Refusal.SLOT_OCCUPIED
	var item := ItemCatalog.get_item(item_id)
	if item == null:
		return Refusal.UNKNOWN_ITEM
	if item.garment == null or item.garment.body_slot_id != slot_id:
		return Refusal.WRONG_BODY_SLOT
	return _check_fit(definition, item)


func can_stow(body_slot_id: StringName, pocket_id: StringName, item_id: StringName) -> Refusal:
	var definition := _find_pocket(body_slot_id, pocket_id)
	if definition == null:
		return Refusal.NO_SUCH_SLOT
	if get_pocket_item(body_slot_id, pocket_id) != &"":
		return Refusal.SLOT_OCCUPIED
	var item := ItemCatalog.get_item(item_id)
	if item == null:
		return Refusal.UNKNOWN_ITEM
	return _check_fit(definition, item)


# -----------------------------------------------------------------------------
# ## ENG: Mutations
# -----------------------------------------------------------------------------

## Wear a garment. Returns Refusal.NONE on success.
##
## An occupied slot is REFUSED, never swapped. An implicit swap has to put
## the old garment somewhere, and a component that knows nothing about
## inventory can only drop it — silently destroying the player's clothes to
## save the caller one line. The caller unequips first and deals with what
## comes back; that is what "you cannot replace a thing until the old one has
## somewhere to go" means in code.
func equip(slot_id: StringName, item_id: StringName) -> Refusal:
	var refusal := can_equip(slot_id, item_id)
	if refusal != Refusal.NONE:
		_log_refusal("equip", slot_id, item_id, refusal)
		return refusal
	_body[slot_id] = item_id
	_log_change("equip", slot_id, item_id)
	slot_changed.emit(slot_id, item_id)
	return Refusal.NONE


## Take a garment off and hand it back. Returns &"" and reports the reason
## when it cannot come off.
##
## Refused while its own pockets still hold something: those pockets go away
## with the garment, so their contents would have nowhere to be. Empty them
## first — the same rule as the body slot, one level down.
func unequip(slot_id: StringName) -> StringName:
	var item_id := get_equipped(slot_id)
	if item_id == &"":
		return &""
	if not _pockets_empty_for(slot_id):
		_log_refusal("unequip", slot_id, item_id, Refusal.POCKETS_NOT_EMPTY)
		return &""
	_body.erase(slot_id)
	_log_change("unequip", slot_id, &"")
	slot_changed.emit(slot_id, &"")
	return item_id


func stow(body_slot_id: StringName, pocket_id: StringName, item_id: StringName) -> Refusal:
	var refusal := can_stow(body_slot_id, pocket_id, item_id)
	if refusal != Refusal.NONE:
		_log_refusal("stow", _pocket_path(body_slot_id, pocket_id), item_id, refusal)
		return refusal
	var path := _pocket_path(body_slot_id, pocket_id)
	_pockets[path] = item_id
	_log_change("stow", path, item_id)
	slot_changed.emit(path, item_id)
	return Refusal.NONE


## Empty a pocket and hand back what was in it, or &"" if it was empty.
func take_from_pocket(body_slot_id: StringName, pocket_id: StringName) -> StringName:
	var path := _pocket_path(body_slot_id, pocket_id)
	var item_id: StringName = _pockets.get(path, &"")
	if item_id == &"":
		return &""
	_pockets.erase(path)
	_log_change("take", path, &"")
	slot_changed.emit(path, &"")
	return item_id


# -----------------------------------------------------------------------------
# ## ENG: Save contract — reached through PlayerPersistenceSystem
# -----------------------------------------------------------------------------

func get_save_key() -> StringName:
	return &"equipment"


func get_save_data() -> Dictionary:
	return {"body": _to_string_keys(_body), "pockets": _to_string_keys(_pockets)}


## Body slots are restored BEFORE pockets, and that order is load-bearing: a
## pocket exists only while the garment carrying it is worn, so restoring
## pocket contents against an undressed character would drop every one of
## them as NO_SUCH_SLOT.
##
## Everything is re-validated rather than trusted. A save is authoritative
## about what the player HAD, not about what the current layout and catalog
## still allow — a garment removed from the game, or a slot removed from the
## layout, must not resurrect as an entry nothing can address.
func load_save_data(data: Dictionary) -> void:
	_body.clear()
	_pockets.clear()

	var saved_body: Dictionary = data.get("body", {})
	for slot_key in saved_body:
		var slot_id := StringName(slot_key)
		var item_id := StringName(saved_body[slot_key])
		if _find_body_slot(slot_id) == null:
			push_warning("[Equipment] save names body slot '%s', the layout does not — dropped" % slot_id)
			continue
		if ItemCatalog.get_item(item_id) == null:
			continue
		_body[slot_id] = item_id

	var saved_pockets: Dictionary = data.get("pockets", {})
	for path_key in saved_pockets:
		var parts := String(path_key).split(POCKET_SEPARATOR)
		if parts.size() != 2:
			push_warning("[Equipment] save has malformed pocket path '%s' — dropped" % path_key)
			continue
		var item_id := StringName(saved_pockets[path_key])
		if _find_pocket(StringName(parts[0]), StringName(parts[1])) == null:
			push_warning("[Equipment] save names pocket '%s', nothing worn provides it — dropped" % path_key)
			continue
		if ItemCatalog.get_item(item_id) == null:
			continue
		_pockets[StringName(path_key)] = item_id

	_log_change("restore", &"(all)", &"")


# -----------------------------------------------------------------------------
# ## ENG: Internals
# -----------------------------------------------------------------------------

## Shared by can_equip() and can_stow() — the two rules a socket enforces,
## stated once.
func _check_fit(definition: EquipmentSlotDefinition, item: ItemResource) -> Refusal:
	if item.size_class > definition.max_size:
		return Refusal.TOO_LARGE
	if definition.refuses_threatening \
			and item.readability == ItemTraits.Readability.THREATENING:
		return Refusal.READS_AS_THREAT
	return Refusal.NONE


func _find_body_slot(slot_id: StringName) -> EquipmentSlotDefinition:
	if layout == null:
		return null
	return layout.find_slot(slot_id)


## A pocket definition, or null when nothing worn in that body slot provides
## one by that id. Derived every time rather than cached: what is worn
## changes, and a stale pocket table is a bug that hides.
func _find_pocket(body_slot_id: StringName, pocket_id: StringName) -> EquipmentSlotDefinition:
	var garment := _garment_in(body_slot_id)
	if garment == null:
		return null
	for pocket in garment.pockets:
		if pocket != null and pocket.id == pocket_id:
			return pocket
	return null


func _garment_in(body_slot_id: StringName) -> GarmentData:
	var item := ItemCatalog.find(_body.get(body_slot_id, &""))
	if item == null:
		return null
	return item.garment


func _pockets_empty_for(body_slot_id: StringName) -> bool:
	var prefix := String(body_slot_id) + POCKET_SEPARATOR
	for path in _pockets:
		if String(path).begins_with(prefix):
			return false
	return true


func _equip_starter_garments() -> void:
	for item_id in starter_garment_ids:
		var item := ItemCatalog.get_item(item_id)
		if item == null or item.garment == null:
			push_warning("[Equipment] starter '%s' is not a garment — skipped" % item_id)
			continue
		equip(item.garment.body_slot_id, item_id)


func _pocket_path(body_slot_id: StringName, pocket_id: StringName) -> StringName:
	return StringName(String(body_slot_id) + POCKET_SEPARATOR + String(pocket_id))


## JSON object keys are strings; StringName keys would come back as strings
## anyway. Converting on the way out makes the payload honest about that
## rather than relying on the round trip.
func _to_string_keys(source: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key in source:
		out[String(key)] = String(source[key])
	return out


func _log_change(action: String, slot_path: StringName, item_id: StringName) -> void:
	if debug_log:
		print("[Equipment] %s %s -> %s" % [action, slot_path, item_id if item_id != &"" else "(empty)"])


func _log_refusal(action: String, slot_path: StringName, item_id: StringName, refusal: Refusal) -> void:
	if debug_log:
		print("[Equipment] %s %s <- %s REFUSED: %s"
				% [action, slot_path, item_id, Refusal.keys()[refusal]])
