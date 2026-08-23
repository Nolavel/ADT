# =============================================================================
# item_resource.gd — Resource-описание предмета.
#
# Один предмет = один .tres в data/items/ (напр. data/items/medkit.tres).
# На него ссылаются: InteractableObject (предмет в мире), InventoryComponent
# (запись в инвентаре), позже — оружейная система (оружие = предмет инвентаря,
# общая модель данных с tier-2 стрельбой).
#
# Namыренно минимален для октябрьского кора. Поля добавляются по мере
# надобности; иконки/меши для UI инвентаря — следующим проходом.
# =============================================================================

extends Resource
class_name ItemResource

@export_group("Identity")
## Уникальный id ("medkit", "pistol_m9"). По нему сравниваем и стакаем;
## имя файла .tres договорились держать равным id.
##
## StringName, not String — this is an identity, the same kind
## ActorBase.actor_id already is, and it is what ItemCatalog keys on.
## (BlockBase.id is still a plain String; that predates this and is not
## being changed here.) An existing .tres storing a plain string still
## loads: Godot converts on read and rewrites it as &"..." on the next save.
@export var id: StringName = &""
@export var display_name: String = "Item"

@export_group("Inventory")
## Антропоморфный инвентарь: вес — основной лимитирующий параметр
## ("нельзя взять больше, чем унесёшь").
@export var weight: float = 1.0
## Максимум штук в одном стеке (1 = нестакуемый).
@export var max_stack: int = 1

@export_group("Capabilities")
@export var can_throw: bool = false
@export var can_use_in_hands: bool = false

@export_group("Equipment")
## Does this fit a given socket — see ItemTraits.SizeClass.
@export var size_class: ItemTraits.SizeClass = ItemTraits.SizeClass.POCKET
## How this reads to someone looking at the player — see
## ItemTraits.Readability. THREATENING is refused by any slot that would put
## it on open display.
@export var readability: ItemTraits.Readability = ItemTraits.Readability.ORDINARY
## Set only on wearable items. Null — the ordinary case — means this is not a
## garment, same "unset is a no-op" contract NPCBase.archetype uses.
@export var garment: GarmentData = null
## The mesh shown in the hand while this item is drawn. A Mesh resource
## rather than a scene, so holding something costs one field instead of a
## .tscn per item. Null means the drawn STATE is still correct and nothing
## appears on screen — which is the honest position for every item until
## someone models it.
@export var held_mesh: Mesh = null
