# =============================================================================
# generate_city.gd — ЭТОТ ФАЙЛ И НАДО ЗАПУСКАТЬ.
#
# ЗАПУСК:
#   1. открыть core/map_source/map_source.tscn как ТЕКУЩУЮ сцену;
#   2. открыть этот файл в редакторе скриптов -> File -> Run (Ctrl+Shift+X).
#
# Без открытой map_source.tscn скрипт остановится и скажет об этом: маркеры
# пишутся в её узел BLOCKS через get_scene(), как это делает
# tools/block_generator/block_placer.gd — способ в проекте уже принятый.
#
# Вся логика в CityLayout (city_layout.gd). Здесь только то, что умеет один
# редактор: достать открытую сцену и отдать в неё маркеры. Параметры генерации
# — константы в city_layout.gd, правятся там.
# =============================================================================
@tool
extends EditorScript


func _run() -> void:
	var scene_root := get_scene()
	if scene_root == null or not scene_root.has_node("BLOCKS"):
		push_error("[CityGenerator] Открой core/map_source/map_source.tscn как текущую сцену и запусти снова.")
		return

	var layout := CityLayout.new()
	var placements := layout.compute_layout()
	if placements.is_empty():
		return
	var library := layout.build_library(placements)
	if library.is_empty():
		return

	var blocks: Node3D = scene_root.get_node("BLOCKS")
	var removed := layout.clear_generated_markers(blocks)
	var written := layout.write_markers(blocks, scene_root, placements, library)

	print("[CityGenerator] Удалено старых GBX-маркеров: %d, поставлено: %d" % [removed, written])
	print("[CityGenerator] Дальше: подвинуть что нужно -> кнопка Export в HUD сцены -> Ctrl+S.")
	print("[CityGenerator] Чтобы правка положения пережила следующий прогон — убери префикс GBX_ из имени маркера.")
