# =============================================================================
# generate_city_cli.gd — СУХОЙ ПРОГОН без редактора.
#
# ЗАПУСК: godot --headless --script res://tools/city_generator/generate_city_cli.gd
#
# ЕСЛИ ВЫ ЧЕЛОВЕК С ОТКРЫТЫМ РЕДАКТОРОМ — вам не сюда: откройте map_source.tscn
# как текущую сцену, затем generate_city.gd -> File -> Run.
#
# Считает раскладку и собирает библиотеку сцен башен — всё, что не зависит от
# открытой сцены. Маркеры НЕ пишет: они ставятся через get_scene(), а в headless
# открытой сцены нет. Нужен, чтобы проверить раскладку числами (сколько колец,
# сколько пустых ячеек, куда попала главная башня) до запуска человеком.
#
# _initialize(), а не _init(): у SceneTree первый — колбэк главного цикла,
# второй — конструктор. quit() из конструктора цикл не останавливает, и процесс
# висит без единой строки вывода.
# =============================================================================
extends SceneTree


func _initialize() -> void:
	var layout := CityLayout.new()
	var placements := layout.compute_layout()
	if placements.is_empty():
		push_error("[CityGenerator] раскладка пуста")
		quit(1)
		return
	layout.build_library(placements)
	print("[CityGenerator] Сухой прогон завершён. Маркеры не писались — для них нужен редактор.")
	quit()
