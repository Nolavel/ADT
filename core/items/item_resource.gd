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
## How that mesh sits in the hand — see HeldFit. Null means it hangs at the
## grip pivot's own origin, which is the honest default for an item nobody
## has fitted yet. Authored by addons/item_fitter/, not by hand.
@export var held_fit: HeldFit = null

@export_group("Ranged")
## Damage one shot deals, and by being non-zero, the fact that this item is
## a firearm at all. Zero means it is not — which is why there is no
## separate is_a_weapon bool: the number is the thing that differs between a
## pistol and a scrap pipe, and a flag beside it could disagree with it.
##
## readability cannot answer this question. A scrap pipe is THREATENING and
## can_use_in_hands too, and the equipment contract's "no invented is-a-
## weapon flag was needed" was about DRAWING, which genuinely needed none.
## Firing does.
##
## Range is deliberately NOT here: how far a character can reach is tuned on
## the character (player.gd's shot_range, next to punch_reach), the same way
## the punch's reach already is.
@export var ranged_damage: float = 0.0

## Rounds one full magazine holds, and by being non-zero, the fact that this
## weapon feeds from one at all. Zero is "not a magazine weapon" — the same
## shape ranged_damage above already uses for "not a firearm", and for the
## same reason: a count and a flag beside it could disagree.
##
## The COUNT is not here. This is the item, and an ItemResource is shared —
## every carbine in the game is this one .tres, so a live round count on it
## would be a round count for all of them. WeaponComponent holds the running
## number, per weapon id, on the character carrying it.
##
## Reserve ammunition is deliberately absent: today the magazine is the only
## number the player manages and a reload always refills it (see
## WeaponComponent.reload()). A reserve pool is a second number and a second
## place to run out, and it is not wanted yet.
@export var magazine_size: int = 0

## Rounds carried behind the magazine. Zero means none — a weapon that
## reloads from nothing, which is what this was until it had a number.
##
## Finite on purpose, and nothing in the world restores it: when it is gone
## the weapon is spent. That is a real consequence rather than an oversight,
## and the fix when it starts to bite is an ammunition pickup, not a bigger
## number here.
##
## Like magazine_size, the CAPACITY is on the item and the running count is
## on WeaponComponent — a resource is shared, so a live count on it would be
## one count for every carbine in the game.
@export var reserve_capacity: int = 0
