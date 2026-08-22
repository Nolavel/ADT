# =============================================================================
# comic_effect_catalog.gd — the full set of ComicEffectDef resources
# ComicEffectSystem draws from. One catalog,
# res://data/comic_effects/catalog.tres by convention.
#
# Same shape as KeyHintsCatalog: a Resource holding the list, so the comic
# vocabulary is data, editable in the inspector, and growing it never touches
# code. Unlike KeyHintsCatalog it is not reached through an @export — see
# ComicEffectSystem.CATALOG_PATH for why a .new()-created system has to load
# it by path instead.
# =============================================================================
class_name ComicEffectCatalog
extends Resource

## One entry per event id. Order is irrelevant — the system keys them by
## ComicEffectDef.id, and a duplicate id simply wins by being later.
@export var effects: Array[ComicEffectDef] = []
