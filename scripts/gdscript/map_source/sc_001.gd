extends Node3D
class_name SkyscraperMarker

@export var skyscraper_name: String = "Neo Finance Tower"

var tower_height: float = 0.0
var tower_position: Vector3

func _ready() -> void:
	tower_position = global_position

	var mesh_instance := _find_mesh(self)

	if mesh_instance != null and mesh_instance.mesh != null:
		var aabb := mesh_instance.mesh.get_aabb()

		tower_height = aabb.size.y * mesh_instance.scale.y

	print(
		"[Tower] ",
		skyscraper_name,
		" | height=",
		tower_height,
		" | pos=",
		tower_position
	)

func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node

	for child in node.get_children():
		var result := _find_mesh(child)
		if result != null:
			return result

	return null
