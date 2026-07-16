# =============================================================================
# inventory_component.gd — компонент игрока InventoryComponent.
#
# Минимальный инвентарь для октябрьского кора: приём/выдача ItemResource
# с весовым лимитом (антропоморфность: нельзя взять больше, чем унесёшь).
# Никакого UI — вся индикация через консоль-лог (решение от 2026-07-16),
# экран инвентаря — отдельным проходом.
#
# Хранение: массив стеков { "item": ItemResource, "count": int }.
# Стакуем по item.id до item.max_stack.
#
# Подключение: дочерняя нода игрока (player.tscn), рядом с InteractComponent.
# InteractComponent получает ссылку через $"../InventoryComponent".
# =============================================================================

extends Node
class_name InventoryComponent

## Суммарный вес, который игрок способен нести.
@export var max_carry_weight: float = 30.0

## Стеки: [{ "item": ItemResource, "count": int }, ...]
var _stacks: Array[Dictionary] = []

signal item_added(item: ItemResource, count_total: int)
signal item_removed(item: ItemResource, count_total: int)
signal add_rejected(item: ItemResource, reason: String)


## Попытаться положить предмет. false — инвентарь отказал (перевес).
func try_add(item: ItemResource) -> bool:
	if item == null:
		push_warning("[Inventory] try_add(null) — у объекта не назначен ItemResource")
		return false

	if get_total_weight() + item.weight > max_carry_weight:
		add_rejected.emit(item, "overweight")
		print("[Inventory] ✖ %s не влез: %.1f + %.1f > %.1f кг"
				% [item.display_name, get_total_weight(), item.weight, max_carry_weight])
		return false

	var stack := _find_stack_with_room(item)
	if stack.is_empty():
		stack = { "item": item, "count": 0 }
		_stacks.append(stack)
	stack["count"] += 1

	item_added.emit(item, get_count(item.id))
	print("[Inventory] ✔ +1 %s (всего: %d, вес: %.1f/%.1f кг)"
			% [item.display_name, get_count(item.id),
			   get_total_weight(), max_carry_weight])
	return true


## Забрать одну штуку по id. null — предмета нет.
func take(item_id: String) -> ItemResource:
	for i in _stacks.size():
		var stack := _stacks[i]
		if (stack["item"] as ItemResource).id != item_id:
			continue
		stack["count"] -= 1
		var item: ItemResource = stack["item"]
		if stack["count"] <= 0:
			_stacks.remove_at(i)
		item_removed.emit(item, get_count(item_id))
		print("[Inventory] − %s (осталось: %d)" % [item.display_name, get_count(item_id)])
		return item
	return null


func get_count(item_id: String) -> int:
	var total := 0
	for stack in _stacks:
		if (stack["item"] as ItemResource).id == item_id:
			total += stack["count"]
	return total


func get_total_weight() -> float:
	var total := 0.0
	for stack in _stacks:
		total += (stack["item"] as ItemResource).weight * stack["count"]
	return total


## Снимок содержимого для будущего UI/сейва (копия, не внутренние данные).
func get_stacks() -> Array[Dictionary]:
	return _stacks.duplicate(true)


func _find_stack_with_room(item: ItemResource) -> Dictionary:
	for stack in _stacks:
		if (stack["item"] as ItemResource).id == item.id \
				and stack["count"] < item.max_stack:
			return stack
	return {}
