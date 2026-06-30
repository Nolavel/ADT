# =============================================================================
# TowerMarker.gd
# class_name: TowerMarker  (был SkyscraperMarker)
#
# Прикрепить к нодам внутри контейнера Towers в mapsource.tscn.
# Каждый маркер — редакторский куб, описывающий башню на карте.
#
# ВЫСОТА:
#   Вычисляется автоматически из AABB первого найденного MeshInstance3D.
#   Убедись что меш существует до _ready() дочерних нод MapSource.
# =============================================================================

extends Node3D
class_name TowerMarker

@export var id: String = "T-001"
@export var tower_name: String = "New Tower"
@export var district: String = "central"
@export var scene_path: String = "res://scenes/towers/T001.tscn"

# Высота заполняется автоматически из AABB меша в _ready()
var tower_height: float = 0.0


func _ready() -> void:
	# Ищем первый MeshInstance3D в дереве потомков
	var mesh := _find_mesh(self)

	if mesh != null and mesh.mesh != null:
		var aabb := mesh.mesh.get_aabb()
		# Учитываем scale ноды меша — scale родителя не учитывается намеренно,
		# потому что маркеры расставляются без scale трансформов
		tower_height = aabb.size.y * mesh.scale.y

	print("----------------------------")
	print("TowerMarker ready")
	print("ID       :", id)
	print("Name     :", tower_name)
	print("District :", district)
	print("Scene    :", scene_path)
	print("Height   :", tower_height)
	print("Position :", global_position)
	print("----------------------------")


func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var result := _find_mesh(child)
		if result != null:
			return result
	return null
