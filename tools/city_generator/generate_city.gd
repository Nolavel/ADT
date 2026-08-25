# =============================================================================
# generate_city.gd — EditorScript, точка входа для человека.
#
# ЗАПУСК: открыть этот файл в редакторе скриптов → File → Run (Ctrl+Shift+X).
# Открывать map_source.tscn или любую другую сцену НЕ нужно — генератор ничего
# не берёт из текущей сцены, он читает террейн из res://world/aogashima/.
#
# Вся логика в CityGenerator (city_generator.gd); здесь только вызов, чтобы
# ту же генерацию можно было прогнать и headless — см. generate_city_cli.gd.
# Параметры (число башен, высоты, шаг сетки, радиус кольца) — константы в
# city_generator.gd, правятся там же.
# =============================================================================
@tool
extends EditorScript


func _run() -> void:
	print("[CityGenerator] старт")
	var generator := CityGenerator.new()
	var report := generator.generate()
	print("[CityGenerator] готово — %d строк отчёта выше" % report.size())
	print("[CityGenerator] дальше: Project → Reload Current Project, затем F5")
