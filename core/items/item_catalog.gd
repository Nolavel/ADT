# =============================================================================
# item_catalog.gd — the one place an item id resolves to an ItemResource.
#
# Until this existed, an ItemResource reached the game exactly one way: hand-
# assigned in the inspector to InteractableObject's own @export. Nothing could
# turn "test_can" back into the resource, which is why anything that has to
# STORE an item rather than hold one — a save file, an equipment slot — had
# nowhere to go. Storing the resource reference instead is not an option:
# SaveSystem's payload rule is dictionaries, arrays and primitives only.
#
# NOT a WORLD_SYSTEM_SCRIPTS entry, deliberately. IncidentRegistry and
# ComicEffectSystem are nodes because they hold runtime state and have a
# lifecycle; a catalog is immutable data, and making it a node would buy a
# group lookup and a lifecycle for nothing.
#
# NOT reached through an @export either. InventoryComponent is a scene node
# and could take one, but EquipmentComponent, NPCs and anything built with
# .new() cannot, and an export wired per consumer is the thing that rots. The
# static accessor below is the same shape as MorphIcon.find_in().
#
# Found by PATH, not by scanning data/items/ — same trap ComicEffectSystem
# documents: an exported build converts .tres to binary behind .remap, so a
# runtime DirAccess search finds every item in the editor and none in a
# shipped build.
# =============================================================================
class_name ItemCatalog
extends Resource

## Where the shared catalog lives. One catalog, by convention, the same way
## res://data/comic_effects/catalog.tres is the one comic-effect catalog.
const CATALOG_PATH: String = "res://data/items/catalog.tres"

## Every item in the game. Order is irrelevant — lookup is by id, and a
## duplicate id simply wins by being later.
@export var items: Array[ItemResource] = []

## The lazily-loaded shared catalog, and whether its absence has already been
## reported. Static so a missing file warns once rather than once per call.
static var _shared: ItemCatalog = null
static var _warned_missing: bool = false

## id -> ItemResource, built on first lookup. Not exported; derived entirely
## from items above.
var _index: Dictionary = {}
var _index_built: bool = false


## The shared catalog, or null if it cannot be loaded. Null is survivable
## everywhere: an item that cannot be resolved is a missing item, not a
## crash.
static func shared() -> ItemCatalog:
	if _shared != null:
		return _shared
	_shared = load(CATALOG_PATH) as ItemCatalog
	if _shared == null and not _warned_missing:
		_warned_missing = true
		push_warning(
			"[ItemCatalog] no catalog at %s — no item id will resolve" % CATALOG_PATH
		)
	return _shared


## Convenience for the common case: resolve an id against the shared catalog.
## Warns on an id that resolves to nothing, because a caller reaching for a
## specific item expects it to exist — see find() for the silent query form.
static func get_item(id: StringName) -> ItemResource:
	var catalog := shared()
	if catalog == null:
		return null
	var item := catalog.find(id)
	if item == null:
		push_warning("[ItemCatalog] unknown item id '%s'" % id)
	return item


## Silent lookup. Returns null for an id this catalog does not hold, without
## warning — this is the "is there such an item" question, and a no is a
## legitimate answer to it.
func find(id: StringName) -> ItemResource:
	if not _index_built:
		_build_index()
	return _index.get(id) as ItemResource


func _build_index() -> void:
	_index.clear()
	for item in items:
		if item == null:
			continue
		if item.id == &"":
			push_warning("[ItemCatalog] an item has no id — it can never be resolved")
			continue
		_index[item.id] = item
	_index_built = true
