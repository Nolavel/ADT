@tool
extends EditorScript

## Построитель 3D-сцены острова Аогасима на основе Heightmap PNG.
## Запуск: Открыть скрипт в редакторе -> File -> Run (Ctrl+Shift+X).

const HEIGHTMAP_PATH := "res://aogashima_heightmap_16bit.png"
const SHADER_PATH := "res://vfx/shaders/aogashima_terrain.gdshader"
const OUTPUT_SCENE_PATH := "res://world/aogashima/Xaogashima_island.tscn"

const MAP_SIZE_M := 3500.0        # Размер острова по оси X/Z в метрах
const HEIGHT_RANGE_M := 500.0     # Максимальная высота (65535 = 500m)
const SEA_LEVEL_M := 0.0          # Уровень моря (отметка Y = 0)

# Разрешение сетки коллизии (256x256 дает высочайшую точность при минимальной нагрузке на CPU)
const COLLISION_GRID_RES := 256


func _run() -> void:
	print("[Terrain Builder] Старт сборки сцены острова Аогасима...")
	
	if not FileAccess.file_exists(HEIGHTMAP_PATH):
		push_error("[Terrain Builder] Файл heightmap не найден: " + HEIGHTMAP_PATH)
		return

	var img := Image.load_from_file(HEIGHTMAP_PATH)
	if img == null or img.is_empty():
		push_error("[Terrain Builder] Не удалось загрузить Image из: " + HEIGHTMAP_PATH)
		return

	var root_node := Node3D.new()
	root_node.name = "AogashimaIsland"

	# 1. Создание визуального меша ландшафта (PlaneMesh + Shader)
	var terrain_mesh_inst := _create_terrain_visuals(img)
	root_node.add_child(terrain_mesh_inst)
	terrain_mesh_inst.owner = root_node

	# 2. Создание физики ландшафта (StaticBody3D + HeightMapShape3D)
	var terrain_collider := _create_terrain_collision(img)
	root_node.add_child(terrain_collider)
	terrain_collider.owner = root_node
	for child in terrain_collider.get_children():
		child.owner = root_node

	# 3. Создание плоскости воды и зоны непроходимости
	var water_group := _create_water_system()
	root_node.add_child(water_group)
	water_group.owner = root_node
	for child in water_group.get_children():
		child.owner = root_node

	# 4. Сохранение итоговой сцены
	var packed_scene := PackedScene.new()
	var pack_err := packed_scene.pack(root_node)
	if pack_err == OK:
		var save_err := ResourceSaver.save(packed_scene, OUTPUT_SCENE_PATH)
		if save_err == OK:
			print("[Terrain Builder] Сцена острова успешно сохранена: ", OUTPUT_SCENE_PATH)
		else:
			push_error("[Terrain Builder] Ошибка сохранения сцены: " + str(save_err))
	else:
		push_error("[Terrain Builder] Ошибка упаковки сцены: " + str(pack_err))


func _create_terrain_visuals(img: Image) -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "TerrainVisual"
	
	var plane_mesh := PlaneMesh.new()
	plane_mesh.size = Vector2(MAP_SIZE_M, MAP_SIZE_M)
	plane_mesh.subdivide_width = 512
	plane_mesh.subdivide_depth = 512
	mesh_inst.mesh = plane_mesh

	var height_tex := ImageTexture.create_from_image(img)
	var shader := load(SHADER_PATH) as Shader
	var shader_mat := ShaderMaterial.new()
	shader_mat.shader = shader
	shader_mat.set_shader_parameter("heightmap", height_tex)
	shader_mat.set_shader_parameter("height_range", HEIGHT_RANGE_M)
	shader_mat.set_shader_parameter("sea_level", SEA_LEVEL_M)

	mesh_inst.material_override = shader_mat
	return mesh_inst


func _create_terrain_collision(img: Image) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "TerrainStaticBody"
	
	var col_shape := CollisionShape3D.new()
	col_shape.name = "HeightMapCollision"

	var height_shape := HeightMapShape3D.new()
	height_shape.map_width = COLLISION_GRID_RES
	height_shape.map_depth = COLLISION_GRID_RES

	var map_data := PackedFloat32Array()
	map_data.resize(COLLISION_GRID_RES * COLLISION_GRID_RES)

	var img_w := img.get_width()
	var img_h := img.get_height()

	# Дискретизация высот из PNG под сетку HeightMapShape3D
	for z in range(COLLISION_GRID_RES):
		for x in range(COLLISION_GRID_RES):
			var u := float(x) / float(COLLISION_GRID_RES - 1)
			var v := float(z) / float(COLLISION_GRID_RES - 1)
			
			var px := int(u * float(img_w - 1))
			var py := int(v * float(img_h - 1))
			
			var h_norm := img.get_pixel(px, py).r
			var h_m := h_norm * HEIGHT_RANGE_M
			
			# Отсечение океана по отметке моря
			if h_m <= SEA_LEVEL_M:
				h_m = SEA_LEVEL_M
				
			map_data[z * COLLISION_GRID_RES + x] = h_m

	height_shape.map_data = map_data
	col_shape.shape = height_shape

	# Центрирование и масштабирование коллизии относительно размера карты
	var scale_factor := MAP_SIZE_M / float(COLLISION_GRID_RES - 1)
	col_shape.scale = Vector3(scale_factor, 1.0, scale_factor)

	body.add_child(col_shape)
	return body


func _create_water_system() -> Node3D:
	var water_root := Node3D.new()
	water_root.name = "WaterSystem"

	# Плоскость океана (Y = 0)
	var water_mesh := MeshInstance3D.new()
	water_mesh.name = "OceanSurface"
	var plane := PlaneMesh.new()
	plane.size = Vector2(MAP_SIZE_M * 1.5, MAP_SIZE_M * 1.5)
	water_mesh.mesh = plane
	water_mesh.position.y = SEA_LEVEL_M

	# Простой полупрозрачный материал воды
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.05, 0.18, 0.28, 0.85)
	mat.roughness = 0.1
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water_mesh.material_override = mat
	water_root.add_child(water_mesh)

	# Коллизия непроходимости океана (Area3D для блокировки/уведомления)
	var water_area := Area3D.new()
	water_area.name = "WaterImpassableZone"
	water_area.position.y = SEA_LEVEL_M - 10.0 # Смещение ниже уровня земли
	
	var area_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(MAP_SIZE_M * 2.0, 20.0, MAP_SIZE_M * 2.0)
	area_shape.shape = box
	water_area.add_child(area_shape)
	
	water_root.add_child(water_area)
	return water_root
