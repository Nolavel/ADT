# =============================================================================
# MapSource.gd
# Прикрепить к корневой ноде сцены mapsource.tscn
# Добавить в группу: "map_source"
#
# ИЗМЕНЕНИЯ v2:
#   - Skyscraper → Tower везде
#   - CityZone теперь экспортируется в WorldData
#   - Исправлен _load_data (был смешан тип Resource и Dictionary — убран как
#     избыточный: _register_scene_towers() всегда перезаписывает данные)
#   - Добавлена кнопка SetSpawn в HUD
# =============================================================================

extends Node3D


# ── Константы ────────────────────────────────────────────────────────────────

const Y_CITY_ZONE_TOP: float = 10.0
const EXPORT_PATH:     String = "res://data/world_data.tres"

## Высота спавн-маркера над CityZone (чтобы шар не проваливался сквозь меш)
const SPAWN_MARKER_OFFSET_Y: float = 5.0

## Радиус визуального шара спавн-маркера (чисто декоративно)
const SPAWN_MARKER_RADIUS: float = 50.0


# ── Ссылки на ноды ───────────────────────────────────────────────────────────

@onready var city_zone_body: StaticBody3D = $CityZone/StaticBody3D

@onready var strata_doggerland: Area3D = $STRATA_Doggerland
@onready var strata_manifold:   Area3D = $STRATA_Manifold
@onready var strata_glare:      Area3D = $STRATA_Glare

@onready var district_A1: 	Area3D = $Districts/A1
@onready var district_A2: 	Area3D = $Districts/A2
@onready var district_A3: 	Area3D = $Districts/A3
@onready var district_A4: 	Area3D = $Districts/A4
@onready var district_A5: 	Area3D = $Districts/A5
@onready var district_A6: 	Area3D = $Districts/A6
@onready var district_A7: 	Area3D = $Districts/A7
@onready var district_A8: 	Area3D = $Districts/A8
@onready var district_A9: 	Area3D = $Districts/A9

## Контейнер башен — TowerMarker-ноды расставляются сюда
@onready var towers_container: Node3D = $Towers

## Spawner — нода с Spawner.gd, её позиция → WorldSystems.spawn_point
@onready var spawner_node: Node3D = $Spawner


# ── Данные башен ─────────────────────────────────────────────────────────────

## { tower_id: Dictionary } — рабочие метаданные текущей сессии
var _tower_data: Dictionary = {}

## Визуальный шар спавн-маркера (создаётся при нажатии кнопки)
var _spawn_marker: MeshInstance3D = null

## Флаг: идёт ли сейчас перемещение спавн-маркера (ЛКМ drag)
var _placing_spawn: bool = false

## Ждём первого нажатия ЛКМ после активации режима.
## Без этого _process сразу видит "ЛКМ не нажата" и мгновенно фиксирует точку.
var _waiting_for_lmb: bool = false


# ── Жизненный цикл ───────────────────────────────────────────────────────────

func _ready() -> void:
	add_to_group("map_source")

	# Ждём кадр — гарантируем что все TowerMarker._ready() уже вызваны
	# и tower_height заполнен из AABB
	await get_tree().process_frame

	_register_scene_towers()
	export_data()

	_build_hud()

	print("[MapSource] ✅ Ready. Towers: %d" % _tower_data.size())


func _process(_delta: float) -> void:
	if not _placing_spawn:
		return

	var lmb := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)

	# Ждём первого нажатия ЛКМ после того как кнопка HUD была отпущена
	if _waiting_for_lmb:
		if lmb:
			_waiting_for_lmb = false   # ЛКМ нажата — начинаем drag
		return  # пока ждём — ничего не делаем

	# Drag: двигаем маркер пока ЛКМ зажата
	if lmb:
		_update_spawn_marker_from_raycast()
	else:
		# ЛКМ отпущена — фиксируем точку
		_placing_spawn = false
		_commit_spawn_point()


# ── Публичный API ─────────────────────────────────────────────────────────────

## Привязать нижнюю грань башни к верхней поверхности CityZone.
func snap_to_city_zone(node: Node3D, height: float) -> void:
	node.global_position.y = Y_CITY_ZONE_TOP + (height * 0.5)


## Зарегистрировать башню вручную (для создания через код).
func register_tower(t_id: String, node: Node3D, height: float, district: String) -> void:
	var strata := _get_strata_for_height(height)

	var data := {
		"id":        t_id,
		"position":  [node.global_position.x, node.global_position.y, node.global_position.z],
		"height":    height,
		"district":  district,
		"scene_path": "",
		"strata_ids": {}
	}

	for stratum in strata:
		var suffix := _strata_suffix(stratum)
		data["strata_ids"][stratum] = "%s-%s" % [t_id, suffix]

	_tower_data[t_id] = data

	print("[MapSource] 🏙 Registered tower: %s  pos=%s  h=%dm  strata=%s" % [
		t_id, node.global_position, int(height), strata])


## Экспортировать все данные в WorldData.tres
func export_data() -> void:
	
	var world := WorldData.new()

	# ── Башни ────────────────────────────────────────────────────────────────
	for dict in _tower_data.values():
		var td := TowerData.new()
		td.id         = dict["id"]
		var p         = dict["position"]
		td.position   = Vector3(p[0], p[1], p[2])
		td.height     = dict["height"]
		td.district   = dict["district"]
		td.scene_path = dict["scene_path"]
		td.strata_ids = dict["strata_ids"]
		world.towers.append(td)
		

	# ── CityZone ─────────────────────────────────────────────────────────────
	# Читаем реальный размер из CollisionShape3D чтобы не хардкодить
	var cz := CityZoneData.new()
	var cs_node := _find_city_zone_collision_shape()
	if cs_node != null and cs_node.shape is BoxShape3D:
		var box := cs_node.shape as BoxShape3D
		cz.size     = box.size
		cz.position = cs_node.global_transform.origin
	else:
		# Fallback на константы из WorldSystems
		cz.size     = Vector3(WorldSystems.CITY_ZONE_SIZE.x, 10.0, WorldSystems.CITY_ZONE_SIZE.y)
		cz.position = Vector3(0.0, 5.0, 0.0)
	world.city_zone = cz
	
	world.spawn_point = WorldSystems.spawn_point
	
	var err := ResourceSaver.save(world, EXPORT_PATH)
	if err != OK:
		push_error("[MapSource] Failed to save WorldData: %d" % err)
	else:
		print("[MapSource] ✅ Exported %d towers + CityZone → %s" % [world.towers.size(), EXPORT_PATH])


func get_tower_data(t_id: String) -> Dictionary:
	return _tower_data.get(t_id, {})

func get_all_data() -> Dictionary:
	return _tower_data

func update_tower_position(t_id: String, new_pos: Vector3) -> void:
	if not _tower_data.has(t_id):
		return
	_tower_data[t_id]["position"] = [new_pos.x, new_pos.y, new_pos.z]


# ── Внутренняя логика — регистрация ──────────────────────────────────────────

func _register_scene_towers() -> void:
	_tower_data.clear()

	for child in towers_container.get_children():
		if child is TowerMarker:
			var marker := child as TowerMarker
			# scene_path берём из маркера напрямую — редактор заполняет его через @export
			register_tower(marker.id, marker, marker.tower_height, marker.district)
			# Записываем scene_path из маркера в словарь
			_tower_data[marker.id]["scene_path"] = marker.scene_path


# ── Спавн-маркер ─────────────────────────────────────────────────────────────

## Вызывается кнопкой HUD "Поставить спавн".
## Создаёт или активирует перемещение шара-маркера.
func _begin_spawn_placement() -> void:
	if not is_instance_valid(_spawn_marker):
		_spawn_marker = MeshInstance3D.new()
		var sphere        := SphereMesh.new()
		sphere.radius      = SPAWN_MARKER_RADIUS
		sphere.height      = SPAWN_MARKER_RADIUS * 2.0
		_spawn_marker.mesh = sphere

		var mat           := StandardMaterial3D.new()
		mat.albedo_color   = Color(0.2, 0.8, 0.4, 0.85)
		mat.transparency   = BaseMaterial3D.TRANSPARENCY_ALPHA
		_spawn_marker.set_surface_override_material(0, mat)

		add_child(_spawn_marker)

	# Ставим шар в центр CityZone как стартовую позицию
	_spawn_marker.global_position = Vector3(0.0, Y_CITY_ZONE_TOP + SPAWN_MARKER_OFFSET_Y, 0.0)

	_placing_spawn  = true
	_waiting_for_lmb = true   # ждём нажатия ЛКМ, игнорируем отпускание кнопки HUD
	print("[MapSource] 📍 Нажми и удерживай ЛКМ над CityZone чтобы поставить спавн")


## Двигаем шар по поверхности CityZone следуя за курсором мыши.
## Луч бьёт по слою 1 (геометрия CityZone).
func _update_spawn_marker_from_raycast() -> void:
	if not is_instance_valid(_spawn_marker):
		return

	# Камера MapSource — ищем в группе или напрямую
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return

	var mouse_pos  := get_viewport().get_mouse_position()
	var ray_origin := cam.project_ray_origin(mouse_pos)
	var ray_dir    := cam.project_ray_normal(mouse_pos)
	var ray_end    := ray_origin + ray_dir * 10000.0

	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collision_mask = 1  # только геометрия

	var space := get_world_3d().direct_space_state
	var hit   := space.intersect_ray(query)

	if hit.is_empty():
		return

	var hit_pos: Vector3 = hit["position"]

	# Ограничиваем Y — шар не должен лететь выше 5м от пола CityZone
	var clamped_y := clampf(
		hit_pos.y + SPAWN_MARKER_OFFSET_Y,
		Y_CITY_ZONE_TOP,
		Y_CITY_ZONE_TOP + SPAWN_MARKER_OFFSET_Y
	)

	_spawn_marker.global_position = Vector3(hit_pos.x, clamped_y, hit_pos.z)


## Фиксируем финальную позицию спавна в WorldSystems.
func _commit_spawn_point() -> void:
	if not is_instance_valid(_spawn_marker):
		return

	var spawn := Vector3(
		_spawn_marker.global_position.x,
		Y_CITY_ZONE_TOP,
		_spawn_marker.global_position.z
	)

	WorldSystems.set_spawn_point(spawn)
	export_data()   # ← ДОБАВИТЬ: сразу записываем в .tres
	print("[MapSource] ✅ Spawn point set and exported: ", spawn)


# ── CityZone ColiisionShape helper ───────────────────────────────────────────

func _find_city_zone_collision_shape() -> CollisionShape3D:
	# Ищем CollisionShape3D внутри CityZone ноды (любая вложенность)
	var cz_node := get_node_or_null("CityZone")
	if cz_node == null:
		return null
	return _find_collision_shape_recursive(cz_node)


func _find_collision_shape_recursive(node: Node) -> CollisionShape3D:
	if node is CollisionShape3D:
		return node
	for child in node.get_children():
		var result := _find_collision_shape_recursive(child)
		if result != null:
			return result
	return null


# ── Страты ───────────────────────────────────────────────────────────────────

func _get_strata_for_height(height: float) -> Array[String]:
	var result: Array[String] = []
	var strata_ranges := {
		"doggerland": [0.0,    500.0],
		"manifold":   [500.0,  1000.0],
		"glare":      [1000.0, 1700.0],
	}
	for stratum in strata_ranges:
		var range_min: float = strata_ranges[stratum][0]
		if height > range_min:
			result.append(stratum)
	return result


func _strata_suffix(stratum: String) -> String:
	match stratum:
		"doggerland": return "DG"
		"manifold":   return "MF"
		"glare":      return "GL"
	return "XX"


# ── HUD ──────────────────────────────────────────────────────────────────────

var _hud_canvas: CanvasLayer

func _build_hud() -> void:
	_hud_canvas        = CanvasLayer.new()
	_hud_canvas.layer  = 10
	add_child(_hud_canvas)

	# ── Кнопка "Экспорт данных" ──────────────────────────────────────────────
	var btn_export          := Button.new()
	btn_export.text          = "Export World Data"
	btn_export.position      = Vector2(16, 16)
	btn_export.size          = Vector2(180, 36)
	btn_export.pressed.connect(func(): export_data())
	_hud_canvas.add_child(btn_export)

	# ── Кнопка "Поставить спавн" ─────────────────────────────────────────────
	var btn_spawn          := Button.new()
	btn_spawn.text          = "Поставить спавн (ЛКМ)"
	btn_spawn.position      = Vector2(16, 60)
	btn_spawn.size          = Vector2(220, 36)
	btn_spawn.pressed.connect(func(): _begin_spawn_placement())
	_hud_canvas.add_child(btn_spawn)

	# ── Метка текущего спавна ─────────────────────────────────────────────────
	var lbl_spawn          := Label.new()
	lbl_spawn.position      = Vector2(16, 104)
	lbl_spawn.size          = Vector2(280, 24)
	lbl_spawn.add_theme_font_size_override("font_size", 12)

	# Обновляем лейбл при изменении спавн-точки
	WorldSystems.spawn_point_updated.connect(func(p: Vector3):
		lbl_spawn.text = "Spawn: (%.0f, %.0f, %.0f)" % [p.x, p.y, p.z]
	)
	lbl_spawn.text = "Spawn: не задан"
	_hud_canvas.add_child(lbl_spawn)
