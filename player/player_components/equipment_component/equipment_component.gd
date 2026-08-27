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

## What is in the hands changed. &"" means they are now empty. Separate from
## slot_changed because a drawn item is not in a slot — that is the whole
## distinction, and the stance coupling listens to this one.
signal drawn_changed(item_id: StringName)

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
	## A garment aimed at a body slot that is not its own, or gear aimed at
	## a body slot that only takes clothing — see can_equip().
	WRONG_BODY_SLOT,
	## A garment cannot come off while its own pockets still hold something.
	POCKETS_NOT_EMPTY,
	## Not something that can be held — see ItemResource.can_use_in_hands.
	NOT_DRAWABLE,
	## Something is already drawn. One pair of hands.
	HANDS_FULL,
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

## Stowed from the first frame, wherever stow_anywhere() puts them.
##
## Empty since 2026-08-26, and this list said to empty it: it held a scrap
## pipe as a FIXTURE so draw/holster could be exercised before H6's pistol
## existed, with the instruction "empty this once there is a weapon the
## player actually finds in the world". H6 landed and that did not happen —
## so the pipe, sitting in an earlier pocket, won the draw key every time
## and the pistol could not be reached at all.
##
## Kept as an export because starting with something in a pocket is a
## legitimate thing to author. It just must not be a second DRAWABLE while
## the draw key is the only way to choose between them.
@export var starter_stowed_ids: Array[StringName] = []

## Prints every accepted and refused change. Off by default; there is no UI
## for equipment yet, so this is the only way to see it work.
@export var debug_log: bool = false

## body slot id -> item id. Only ever holds ids.
var _body: Dictionary = {}
## "<body slot>/<pocket>" -> item id.
var _pockets: Dictionary = {}
## What is in the hands, and the slot path it came out of. The origin is
## remembered rather than re-derived so holster() puts the thing back exactly
## where it was: that slot is guaranteed free (nothing else could have taken
## it while the item was out of it), whereas stow_anywhere() would drop a
## pistol into a different pocket every time.
var _drawn_item_id: StringName = &""
var _drawn_from: StringName = &""


func _ready() -> void:
	_equip_starter_garments()
	_stow_starter_items()


# -----------------------------------------------------------------------------
# ## ENG: Queries
# -----------------------------------------------------------------------------

## The item in a body slot, or &"" when empty.
func get_equipped(slot_id: StringName) -> StringName:
	return _body.get(slot_id, &"")


## The item in a pocket, or &"" when empty.
func get_pocket_item(body_slot_id: StringName, pocket_id: StringName) -> StringName:
	return _pockets.get(pocket_path(body_slot_id, pocket_id), &"")


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

	## Two different questions, depending on what is being put there. A
	## GARMENT names the one body slot it belongs in and may go nowhere
	## else — a jacket is not footwear. Anything else is gear rather than
	## clothing, and the slot decides whether it takes gear at all
	## (EquipmentSlotDefinition.accepts_non_garment, true on the two back
	## slots and nowhere else). Without that second path a carbine has no
	## legal place on the body: it is CARRIED, so no pocket takes it, and
	## body slots used to be garments-only.
	if item.garment != null:
		if item.garment.body_slot_id != slot_id:
			return Refusal.WRONG_BODY_SLOT
	elif not definition.accepts_non_garment:
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
		_log_refusal("stow", pocket_path(body_slot_id, pocket_id), item_id, refusal)
		return refusal
	var path := pocket_path(body_slot_id, pocket_id)
	_pockets[path] = item_id
	_log_change("stow", path, item_id)
	slot_changed.emit(path, item_id)
	return Refusal.NONE


## Empty a pocket and hand back what was in it, or &"" if it was empty.
func take_from_pocket(body_slot_id: StringName, pocket_id: StringName) -> StringName:
	var path := pocket_path(body_slot_id, pocket_id)
	var item_id: StringName = _pockets.get(path, &"")
	if item_id == &"":
		return &""
	_pockets.erase(path)
	_log_change("take", path, &"")
	slot_changed.emit(path, &"")
	return item_id


## What is in the hands, or &"" when they are empty.
func get_drawn() -> StringName:
	return _drawn_item_id


## Which slot the drawn item came from, or &"" when the hands are empty.
##
## Exists because the DRAW GESTURE has to start where the item actually was —
## a chest pocket reads as a hip-level grab, a thigh pocket as a reach down
## the leg — and only this component knows. It answers where, not what the
## animation should be: choosing the clip is the caller's job, the same way
## readability is read outside this file rather than turned into a stance
## here.
func get_drawn_from() -> StringName:
	return _drawn_from


## Take the item out of a slot and into the hands. `slot_path` is a body slot
## id, or "<body_slot>/<pocket>" for a pocket — the same addressing
## everything else here uses.
##
## can_use_in_hands is what decides whether something CAN be drawn. Whether
## drawing it is a declaration is a separate question, answered by
## readability, and it is answered outside this component: equipment does not
## know what a stance is.
func draw(slot_path: StringName) -> Refusal:
	if _drawn_item_id != &"":
		_log_refusal("draw", slot_path, _drawn_item_id, Refusal.HANDS_FULL)
		return Refusal.HANDS_FULL

	var item_id := _item_at(slot_path)
	if item_id == &"":
		_log_refusal("draw", slot_path, &"", Refusal.NO_SUCH_SLOT)
		return Refusal.NO_SUCH_SLOT

	var item := ItemCatalog.get_item(item_id)
	if item == null:
		return Refusal.UNKNOWN_ITEM
	if not item.can_use_in_hands:
		_log_refusal("draw", slot_path, item_id, Refusal.NOT_DRAWABLE)
		return Refusal.NOT_DRAWABLE

	_clear_slot(slot_path)
	_drawn_item_id = item_id
	_drawn_from = slot_path
	_log_change("draw", slot_path, item_id)
	slot_changed.emit(slot_path, &"")
	drawn_changed.emit(item_id)
	return Refusal.NONE


## Put the drawn item back where it came from. Returns what was holstered, or
## &"" when the hands were already empty — that early return is also what
## keeps the stance coupling from looping.
func holster() -> StringName:
	if _drawn_item_id == &"":
		return &""
	var item_id := _drawn_item_id
	var origin := _drawn_from
	_drawn_item_id = &""
	_drawn_from = &""
	_restore_to_slot(origin, item_id)
	_log_change("holster", origin, item_id)
	slot_changed.emit(origin, item_id)
	drawn_changed.emit(&"")
	return item_id


## Put an item away wherever it fits on the body: its own body slot if it is
## a garment, otherwise the first empty pocket that takes it — and failing
## that, the first empty body slot that accepts gear (the back).
##
## This is equipment deciding where something goes, which is the whole reason
## it sits between interaction and inventory. It still knows nothing about
## inventory — a caller that gets a refusal decides what to do next.
##
## Candidate pockets are tested with can_stow() and only the winner is
## actually stowed, so a full jacket does not produce four refusal lines in
## the log on the way to the fifth pocket.
func stow_anywhere(item_id: StringName) -> Refusal:
	var item := ItemCatalog.get_item(item_id)
	if item == null:
		return Refusal.UNKNOWN_ITEM

	if item.garment != null:
		var worn := equip(item.garment.body_slot_id, item_id)
		if worn == Refusal.NONE:
			return Refusal.NONE

	## Most informative refusal wins: NO_SUCH_SLOT only survives when there
	## were no empty pockets at all to judge.
	var reason := Refusal.NO_SUCH_SLOT
	for pocket in get_available_pockets():
		if pocket["item_id"] != &"":
			continue
		var refusal: Refusal = can_stow(pocket["body_slot"], pocket["pocket"], item_id)
		if refusal == Refusal.NONE:
			return stow(pocket["body_slot"], pocket["pocket"], item_id)
		reason = refusal

	## Pockets first, the body only after — so a can never ends up strapped
	## to the back while a pocket is free, and only what no pocket takes
	## (a carbine) gets there. Layout order decides which back slot wins,
	## and refuses_threatening is what keeps a weapon off back_unique: that
	## slot is the one that puts its contents on open display, and slinging
	## something threatening there is meant to be a deliberate act, not the
	## side effect of walking over it. Picking a thing up is not that act.
	for body_slot in layout.body_slots:
		if body_slot == null or not body_slot.accepts_non_garment:
			continue
		if get_equipped(body_slot.id) != &"":
			continue
		var refusal: Refusal = can_equip(body_slot.id, item_id)
		if refusal == Refusal.NONE:
			return equip(body_slot.id, item_id)
		reason = refusal
	return reason


# -----------------------------------------------------------------------------
# ## ENG: Save contract — reached through PlayerPersistenceSystem
# -----------------------------------------------------------------------------

func get_save_key() -> StringName:
	return &"equipment"


func get_save_data() -> Dictionary:
	return {
		"body": _to_string_keys(_body),
		"pockets": _to_string_keys(_pockets),
		"drawn": String(_drawn_item_id),
		"drawn_from": String(_drawn_from),
	}


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
	_drawn_item_id = &""
	_drawn_from = &""

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

	## The drawn item is state, not a view of a slot — it belongs to neither
	## dictionary above, so it is restored separately. Both halves are needed:
	## without drawn_from, holstering after a load would have nowhere to put
	## the thing back.
	var drawn := StringName(data.get("drawn", ""))
	var drawn_from := StringName(data.get("drawn_from", ""))
	if drawn != &"" and ItemCatalog.get_item(drawn) != null:
		_drawn_item_id = drawn
		_drawn_from = drawn_from
		drawn_changed.emit(drawn)

	_log_change("restore", &"(all)", _drawn_item_id)


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


## An EMPTY body slot is answered before the catalog is asked anything.
## get_available_pockets() walks every slot on every call, including the ones
## nothing is worn in, so without this guard get_item() warned "unknown item
## id ''" six times per startup for a question whose legitimate answer is
## "nothing is worn there". A non-empty id that fails to resolve is still a
## real failure and still warns.
func _garment_in(body_slot_id: StringName) -> GarmentData:
	var item_id: StringName = _body.get(body_slot_id, &"")
	if item_id == &"":
		return null
	var item := ItemCatalog.get_item(item_id)
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


## Whatever is in a slot, addressed by path — body slot or pocket.
func _item_at(slot_path: StringName) -> StringName:
	if String(slot_path).contains(POCKET_SEPARATOR):
		return _pockets.get(slot_path, &"")
	return _body.get(slot_path, &"")


func _clear_slot(slot_path: StringName) -> void:
	if String(slot_path).contains(POCKET_SEPARATOR):
		_pockets.erase(slot_path)
	else:
		_body.erase(slot_path)


## Deliberately bypasses can_stow(): the slot is guaranteed free — this item
## was taken out of it and nothing else could reach it while it was in the
## hands — and it already passed every check on the way in.
func _restore_to_slot(slot_path: StringName, item_id: StringName) -> void:
	if String(slot_path).contains(POCKET_SEPARATOR):
		_pockets[slot_path] = item_id
	else:
		_body[slot_path] = item_id


func _stow_starter_items() -> void:
	for item_id in starter_stowed_ids:
		var refusal := stow_anywhere(item_id)
		if refusal != Refusal.NONE:
			push_warning("[Equipment] starter '%s' had nowhere to go: %s"
					% [item_id, Refusal.keys()[refusal]])


## Builds the address of a pocket. Public because draw() takes a slot path
## and a caller iterating get_available_pockets() has to be able to name one
## — the format is this component's business, not the caller's to spell.
func pocket_path(body_slot_id: StringName, pocket_id: StringName) -> StringName:
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
