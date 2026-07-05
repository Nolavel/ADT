# =============================================================================
# BlockHaze.gd
# class_name: BlockHaze
#
# Пример наследника BlockBase для жилых башен.
# Добавляет только своё — общая логика (поиск меша, высота, лог) не трогается.
# =============================================================================
extends BlockBase
class_name BlockHaze

@export_group("Current Block Specific")
@export var floor_count: int = 20
@export var has_rooftop_garden: bool = false


func get_marker_type_name() -> String:
	return "BlockHaze"

func _log_extra_info() -> void:
	print("Floors   :", floor_count)
	print("Garden   :", has_rooftop_garden)


func _on_marker_ready() -> void:
	# Пример специфичной логики: например, авто-расчёт этажей из высоты,
	# если разработчик не выставил floor_count руками
	if floor_count <= 0 and block_height > 0.0:
		const FLOOR_HEIGHT := 3.0
		floor_count = int(block_height / FLOOR_HEIGHT)


func get_marker_data() -> Dictionary:
	var data := super.get_marker_data()
	data["floor_count"] = floor_count
	data["has_rooftop_garden"] = has_rooftop_garden
	return data
