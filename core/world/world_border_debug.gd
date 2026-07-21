# =============================================================================
# world_border_debug.gd — debug-only визуализация границ World Zone.
#
# Владелец: world.gd, WORLD_SYSTEM_SCRIPTS. Рисует проволочный бокс точно по
# WorldSystems.WORLD_ZONE_SIZE / GAMEPLAY_HEIGHT — чисто debug-инструмент,
# не путать с core/checker_indicators (те — gameplay-прототипы, не debug).
# Переключается export'ом в инспекторе, не горячей клавишей.
# =============================================================================
extends Node3D
class_name WorldBorderDebugSystem

@export var debug_visible: bool = true:
	set(value):
		debug_visible = value
		if is_instance_valid(_mesh_instance):
			_mesh_instance.visible = value

var _mesh_instance: MeshInstance3D


func _ready() -> void:
	var half := WorldSystems.WORLD_ZONE_SIZE * 0.5
	var size := Vector3(half.x * 2.0, WorldSystems.GAMEPLAY_HEIGHT, half.y * 2.0)

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "BorderWireframe"
	_mesh_instance.mesh = _build_wireframe_box(size)
	_mesh_instance.position = Vector3(0.0, size.y * 0.5, 0.0)
	_mesh_instance.visible = debug_visible
	add_child(_mesh_instance)


## Рёбра габаритного бокса как отдельные отрезки (PRIMITIVE_LINES) — дёшево,
## не требует отдельного шейдера, видно сквозь геометрию не будет (это не
## приоритет для debug-инструмента).
func _build_wireframe_box(size: Vector3) -> ArrayMesh:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5

	var corners := [
		Vector3(-hx, -hy, -hz), Vector3(hx, -hy, -hz),
		Vector3(hx, -hy, hz),   Vector3(-hx, -hy, hz),
		Vector3(-hx, hy, -hz),  Vector3(hx, hy, -hz),
		Vector3(hx, hy, hz),    Vector3(-hx, hy, hz),
	]
	var edge_indices := [
		0, 1, 1, 2, 2, 3, 3, 0,   # нижняя грань
		4, 5, 5, 6, 6, 7, 7, 4,   # верхняя грань
		0, 4, 1, 5, 2, 6, 3, 7,   # вертикальные рёбра
	]

	var points := PackedVector3Array()
	for i in edge_indices:
		points.append(corners[i])

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.15, 0.15)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.surface_set_material(0, mat)

	return mesh
