# =============================================================================
# BlockBase.gd
# class_name: BlockBase
#
# Базовый класс для всех маркеров башен/блоков в mapsource.tscn.
# Наследники переопределяют виртуальные хуки (_on_marker_ready, 
# _collect_extra_data, и т.д.), не трогая общую логику поиска меша
# и вычисления высоты.
#
# ИСПОЛЬЗОВАНИЕ:
#   extends BlockBase
#   class_name BlockCentral
#
#   func _on_marker_ready() -> void:
#       # своя логика конкретного плейсхолдера
# =============================================================================
extends Node3D
class_name BlockBase

@export_group("Identity")
@export var id: String = ""
@export var block_name: String = ""
@export var district: String = ""
@export var scene_path: String = "res://world/placeholders/towers_placeholder/T001.tscn"

## Высота заполняется автоматически из AABB меша в _ready().
## protected-по-конвенции: наследники могут читать, но не должны
## переопределять напрямую — только через _compute_height(), если нужна другая логика.
var block_height: float = 0.0

## Кешируем найденный меш, чтобы наследники могли переиспользовать
## без повторного обхода дерева.
var _found_mesh: MeshInstance3D = null


## ============================================
## ЖИЗНЕННЫЙ ЦИКЛ — final по конвенции, наследники НЕ переопределяют _ready()
## ============================================
func _ready() -> void:
	_found_mesh = _find_mesh(self)
	block_height = _compute_height(_found_mesh)

	_log_marker_info()

	# Хук для наследников — сюда добавляют свою специфичную логику
	_on_marker_ready()


## ============================================
## ВЫЧИСЛЕНИЕ ВЫСОТЫ — можно переопределить в наследнике при нестандартной геометрии
## ============================================
func _compute_height(mesh: MeshInstance3D) -> float:
	if mesh == null or mesh.mesh == null:
		return 0.0
	var aabb := mesh.mesh.get_aabb()
	# Учитываем scale ноды меша — scale родителя не учитывается намеренно,
	# потому что маркеры расставляются без scale трансформов
	return aabb.size.y * mesh.scale.y


## ============================================
## ПОИСК МЕША — общий для всех наследников
## ============================================
func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var result := _find_mesh(child)
		if result != null:
			return result
	return null


## ============================================
## ЛОГИРОВАНИЕ — единый формат для отладки в редакторе
## ============================================
func _log_marker_info() -> void:
	print("----------------------------")
	print("%s ready" % get_marker_type_name())
	print("ID       :", id)
	print("Name     :", block_name)
	print("District :", district)
	print("Scene    :", scene_path)
	print("Height   :", block_height)
	print("Position :", global_position)
	_log_extra_info()
	print("----------------------------")


## ============================================
## ВИРТУАЛЬНЫЕ ХУКИ — переопределяются в наследниках
## ============================================

## Возвращает имя типа маркера для логов. Переопределить в наследнике,
## например: return "BlockCentral"
func get_marker_type_name() -> String:
	return "BlockBase"

## Вызывается в конце _ready(), после того как высота и меш уже найдены.
## Сюда наследник кладёт свою уникальную логику (спавн доп. виджетов,
## регистрацию в WorldSystems, кастомные материалы и т.д.)
func _on_marker_ready() -> void:
	pass

## Дополнительная строка(и) для лога — переопределить если у наследника
## есть свои поля, которые полезно видеть при отладке.
func _log_extra_info() -> void:
	pass


## ============================================
## ПУБЛИЧНОЕ API — используется StreamingSystems / WorldBuilder
## ============================================

## Возвращает BlockData-совместимый набор полей.
## Наследники с доп. данными могут переопределить, вызвав super() и
## расширив словарь при необходимости.
func get_marker_data() -> Dictionary:
	return {
		"id": id,
		"name": block_name,
		"district": district,
		"scene_path": scene_path,
		"height": block_height,
		"position": global_position,
	}
