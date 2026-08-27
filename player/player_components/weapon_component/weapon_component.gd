# =============================================================================
# weapon_component.gd — how many rounds are actually in the magazine.
#
# One number per weapon id, on the character carrying it. Not on
# ItemResource: a resource is shared, so every carbine in the game is the
# same .tres and a live count there would be a count for all of them. Not on
# EquipmentComponent either — that component's own header limits it to what
# is worn and what is held, and rounds in a magazine are neither; it holds
# ids and knows nothing that changes between two identical items.
#
# Knows nothing about firing, animation or the HUD. It answers three
# questions — how many are left, may one be spent, refill — and emits an edge
# when the number moves. player.gd owns the gating (a shot at zero is refused
# there, before any gesture plays) and the HUD owns the display.
#
# WHICH weapons it tracks: any item whose ItemResource.magazine_size is
# non-zero. A weapon is entered into the table the first time it is asked
# about, full and with a full reserve — a carbine found in the world comes
# loaded, which is a design choice and the only one that makes a single
# pickup playable.
#
# TWO numbers per weapon, not one: the magazine, and the reserve behind it
# (ItemResource.reserve_capacity). A reload moves rounds from the second to
# the first and is REFUSED when the second is empty. The reserve is finite
# and nothing restores it — that is the point of having one, and when it
# starts to bite the answer is an ammunition pickup, not a bigger number.
#
# Reached by the save file through PlayerPersistenceSystem, which walks the
# player's direct children — so this must stay a direct child of Player.
# =============================================================================
extends Node
class_name WeaponComponent

## What `item_id` has to shoot with changed. Carries every number a display
## needs — magazine, its capacity, and the reserve — so the HUD renders
## "3 / 8 · 72" from one signal without resolving the item itself, and so a
## reload that moves both numbers is still one edge rather than two.
signal ammo_changed(item_id: StringName, rounds: int, capacity: int, reserve: int)

## item id -> rounds currently in the magazine. Only ever ints; the payload
## rule (dictionaries, arrays and primitives) is why.
var _magazines: Dictionary = {}
## item id -> rounds carried behind the magazine. Same shape, same rule, and
## seeded the same way on first ask.
var _reserves: Dictionary = {}


# -----------------------------------------------------------------------------
# ## ENG: Queries
# -----------------------------------------------------------------------------

## Rounds left in that weapon's magazine. A weapon never asked about before
## reports full — see this file's header on why found weapons come loaded.
## Zero for anything that is not a magazine weapon, which is also the honest
## answer: it has no magazine to have rounds in.
func get_rounds(item_id: StringName) -> int:
	var capacity := get_capacity(item_id)
	if capacity <= 0:
		return 0
	if not _magazines.has(item_id):
		_magazines[item_id] = capacity
	return _magazines[item_id]


## The magazine size from the catalog, or 0 when the item is not a magazine
## weapon (or is not in the catalog at all).
func get_capacity(item_id: StringName) -> int:
	if item_id == &"":
		return 0
	var item := ItemCatalog.get_item(item_id)
	if item == null:
		return 0
	return item.magazine_size


## Rounds left behind the magazine. Like get_rounds(), a weapon never asked
## about before reports its full authored reserve.
func get_reserve(item_id: StringName) -> int:
	var reserve_capacity := get_reserve_capacity(item_id)
	if reserve_capacity <= 0:
		return 0
	if not _reserves.has(item_id):
		_reserves[item_id] = reserve_capacity
	return _reserves[item_id]


func get_reserve_capacity(item_id: StringName) -> int:
	if item_id == &"":
		return 0
	var item := ItemCatalog.get_item(item_id)
	if item == null:
		return 0
	return item.reserve_capacity


func is_empty(item_id: StringName) -> bool:
	return get_capacity(item_id) > 0 and get_rounds(item_id) <= 0


func is_full(item_id: StringName) -> bool:
	var capacity := get_capacity(item_id)
	return capacity > 0 and get_rounds(item_id) >= capacity


## Would reload() do anything. Pure query, and it exists because the CALLER
## has to know before it commits: player.gd starts the gesture and locks
## movement at the key press, and only reaches reload() a second later, so
## without this it plays a full reload animation for a weapon with nothing to
## load — which is exactly the lie the empty magazine already refuses to tell
## on the firing side.
func can_reload(item_id: StringName) -> bool:
	var capacity := get_capacity(item_id)
	if capacity <= 0:
		return false
	if get_rounds(item_id) >= capacity:
		return false
	return get_reserve(item_id) > 0


# -----------------------------------------------------------------------------
# ## ENG: Mutations
# -----------------------------------------------------------------------------

## Spend one round. Returns false — and changes nothing — when there is none
## to spend, which is what makes this the gate rather than a counter the
## caller decrements after the fact: a caller that fires first and asks
## afterwards can never be made to refuse honestly.
func consume_round(item_id: StringName) -> bool:
	var capacity := get_capacity(item_id)
	if capacity <= 0:
		return false
	var rounds := get_rounds(item_id)
	if rounds <= 0:
		return false
	_magazines[item_id] = rounds - 1
	ammo_changed.emit(item_id, rounds - 1, capacity, get_reserve(item_id))
	return true


## Move rounds from the reserve into the magazine. Returns false when there
## is nothing to do — already full, nothing left in reserve, or not a
## magazine weapon at all — so the caller can refuse the GESTURE too. A
## reload animation with nothing to reload is a lie about what the character
## just did, which is the same rule an empty magazine already follows on the
## firing side.
##
## A partial reload is a success: eight rounds wanted and three left in
## reserve puts three in and reports true. Refusing that would strand the
## last of the ammunition permanently.
##
## Nothing restores the reserve — see ItemResource.reserve_capacity. When it
## reaches zero the weapon is spent, and an ammunition pickup is what fixes
## that, not a change here.
func reload(item_id: StringName) -> bool:
	var capacity := get_capacity(item_id)
	if capacity <= 0:
		return false

	var missing := capacity - get_rounds(item_id)
	if missing <= 0:
		return false

	var reserve := get_reserve(item_id)
	var taken := mini(missing, reserve)
	if taken <= 0:
		return false

	_magazines[item_id] = get_rounds(item_id) + taken
	_reserves[item_id] = reserve - taken
	ammo_changed.emit(item_id, _magazines[item_id], capacity, _reserves[item_id])
	return true


# -----------------------------------------------------------------------------
# ## ENG: Save contract — reached through PlayerPersistenceSystem
# -----------------------------------------------------------------------------

func get_save_key() -> StringName:
	return &"weapons"


func get_save_data() -> Dictionary:
	return {
		"magazines": _to_string_keys(_magazines),
		"reserves": _to_string_keys(_reserves),
	}


## JSON object keys are strings; StringName keys come back as strings anyway.
## Converting on the way out makes the payload honest about that rather than
## relying on the round trip — the same helper and the same reasoning
## EquipmentComponent already carries.
func _to_string_keys(source: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key in source:
		out[String(key)] = int(source[key])
	return out


## Re-validated rather than trusted, the same rule EquipmentComponent's own
## load states: a save is authoritative about what the player HAD, not about
## what the current catalog still allows. A weapon removed from the game, or
## one whose magazine shrank between builds, must not come back as a count
## nothing can spend.
func load_save_data(data: Dictionary) -> void:
	_magazines.clear()
	_reserves.clear()

	var saved: Dictionary = data.get("magazines", {})
	for key in saved:
		var item_id := StringName(key)
		var capacity := get_capacity(item_id)
		if capacity <= 0:
			push_warning("[Weapon] save names '%s', which has no magazine — dropped" % item_id)
			continue
		_magazines[item_id] = clampi(int(saved[key]), 0, capacity)

	var saved_reserves: Dictionary = data.get("reserves", {})
	for key in saved_reserves:
		var item_id := StringName(key)
		var reserve_capacity := get_reserve_capacity(item_id)
		if reserve_capacity <= 0:
			push_warning("[Weapon] save names a reserve for '%s', which has none — dropped" % item_id)
			continue
		_reserves[item_id] = clampi(int(saved_reserves[key]), 0, reserve_capacity)

	## Emitted after BOTH tables are rebuilt, not inside either loop: a
	## subscriber that heard about a magazine while the reserves were still
	## cleared would paint a full weapon with no ammunition behind it, and
	## then never hear a correction.
	for item_id in _magazines:
		ammo_changed.emit(
			item_id, _magazines[item_id], get_capacity(item_id), get_reserve(item_id)
		)
