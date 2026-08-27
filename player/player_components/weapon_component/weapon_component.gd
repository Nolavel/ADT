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
# about, full — a carbine found in the world comes loaded, which is a design
# choice and the only one that makes a single pickup playable. Reserve
# ammunition does not exist yet; reload() always refills.
#
# Reached by the save file through PlayerPersistenceSystem, which walks the
# player's direct children — so this must stay a direct child of Player.
# =============================================================================
extends Node
class_name WeaponComponent

## The magazine count for `item_id` changed. Carries the capacity too, so a
## subscriber can render "3 / 8" without resolving the item itself.
signal ammo_changed(item_id: StringName, rounds: int, capacity: int)

## item id -> rounds currently in the magazine. Only ever ints; the payload
## rule (dictionaries, arrays and primitives) is why.
var _magazines: Dictionary = {}


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


func is_empty(item_id: StringName) -> bool:
	return get_capacity(item_id) > 0 and get_rounds(item_id) <= 0


func is_full(item_id: StringName) -> bool:
	var capacity := get_capacity(item_id)
	return capacity > 0 and get_rounds(item_id) >= capacity


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
	ammo_changed.emit(item_id, rounds - 1, capacity)
	return true


## Refill the magazine. Returns false when there is nothing to do — already
## full, or not a magazine weapon — so the caller can refuse a reload gesture
## for a full weapon instead of playing one that means nothing.
##
## Refills outright rather than drawing from a reserve: the magazine is the
## only ammunition number in the game today. A reserve pool is a second
## number and a second place to run out, and adding one changes this method,
## not its callers.
func reload(item_id: StringName) -> bool:
	var capacity := get_capacity(item_id)
	if capacity <= 0:
		return false
	if get_rounds(item_id) >= capacity:
		return false
	_magazines[item_id] = capacity
	ammo_changed.emit(item_id, capacity, capacity)
	return true


# -----------------------------------------------------------------------------
# ## ENG: Save contract — reached through PlayerPersistenceSystem
# -----------------------------------------------------------------------------

func get_save_key() -> StringName:
	return &"weapons"


func get_save_data() -> Dictionary:
	var magazines: Dictionary = {}
	for item_id in _magazines:
		magazines[String(item_id)] = int(_magazines[item_id])
	return {"magazines": magazines}


## Re-validated rather than trusted, the same rule EquipmentComponent's own
## load states: a save is authoritative about what the player HAD, not about
## what the current catalog still allows. A weapon removed from the game, or
## one whose magazine shrank between builds, must not come back as a count
## nothing can spend.
func load_save_data(data: Dictionary) -> void:
	_magazines.clear()
	var saved: Dictionary = data.get("magazines", {})
	for key in saved:
		var item_id := StringName(key)
		var capacity := get_capacity(item_id)
		if capacity <= 0:
			push_warning("[Weapon] save names '%s', which has no magazine — dropped" % item_id)
			continue
		_magazines[item_id] = clampi(int(saved[key]), 0, capacity)
		ammo_changed.emit(item_id, _magazines[item_id], capacity)
