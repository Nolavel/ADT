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
## Уникальный строковый id ("medkit", "pistol_m9"). По нему сравниваем
## и стакаем; имя файла .tres договорились держать равным id.
@export var id: String = ""
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
