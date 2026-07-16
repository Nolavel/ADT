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

const Y_CITY_ZONE_TOP: float = 0.0
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
@onready var blocks_container: Node3D = $BLOCKS

## Spawner — нода с Spawner.gd, её позиция → WorldSystems.spawn_point
@onready var spawner_node: Node3D = $Spawner


# ── Данные башен ─────────────────────────────────────────────────────────────

## { block_id: Dictionary } — рабочие метаданные текущей сессии
var _block_data: Dictionary = {}

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

	_register_scene_blocks()
	export_data()

	_build_hud()

	print("[MapSource] ✅ Ready. Blocks: %d" % _block_data.size())


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
func register_block(b_id: String, node: Node3D, height: float, district: String) -> void:
	var strata := _get_strata_for_height(height)

	var data := {
		"id":        b_id,
		"position":  [node.global_position.x, node.global_position.y, node.global_position.z],
		"height":    height,
		"district":  district,
		"scene_path": "",
		"strata_ids": {},
		"silhouette_scene_path": "",
	}

	for stratum in strata:
		var suffix := _strata_suffix(stratum)
		data["strata_ids"][stratum] = "%s-%s" % [b_id, suffix]

	_block_data[b_id] = data

	print("[MapSource] 🏙 Registered tower: %s  pos=%s  h=%dm  strata=%s" % [
		b_id, node.global_position, int(height), strata])


## Экспортировать все данные в WorldData.tres
func export_data() -> void:

	var world := WorldData.new()

	# ── Кварталы ────────────────────────────────────────────────────────────
	for dict in _block_data.values():
		var bd := BlockData.new()
		bd.id       = dict["id"]
		var p       = dict["position"]
		bd.position = Vector3(p[0], p[1], p[2])
		bd.height   = dict["height"]
		bd.district = dict["district"]
		bd.content_scene_path    = dict["scene_path"]
		bd.silhouette_scene_path = dict.get("silhouette_scene_path", "")
		bd.strata_ids = dict["strata_ids"]
		world.blocks.append(bd)
		
	# ── Плиты земли ─────────────────────────────────────────────────────────
	# Сетка 3×3 — геометрия в константах WorldSystems. Контент-сцены
	# чередуются a/b (как в прежнем ручном world_data.tres).
	const GT_CONTENT_PATHS := [
		"res://world/content/ground_tiles/gt_content_a.tscn",
		"res://world/content/ground_tiles/gt_content_b.tscn",
	]
	var gt_index := 0
	for row in WorldSystems.GROUND_GRID_SIZE.y:
		for col in WorldSystems.GROUND_GRID_SIZE.x:
			var gt := GroundTileData.new()
			gt.row = row
			gt.col = col
			gt.content_scene_path = GT_CONTENT_PATHS[gt_index % 2]
			world.ground_tiles.append(gt)
			gt_index += 1

	world.spawn_point = WorldSystems.spawn_point

	var err := ResourceSaver.save(world, EXPORT_PATH)
	if err != OK:
		push_error("[MapSource] Failed to save WorldData: %d" % err)
	else:
		print("[MapSource] ✅ Exported %d blocks → %s" % [world.blocks.size(), EXPORT_PATH])


func get_block_data(b_id: String) -> Dictionary:
	return _block_data.get(b_id, {})

func get_all_data() -> Dictionary:
	return _block_data

func update_block_position(b_id: String, new_pos: Vector3) -> void:
	if not _block_data.has(b_id):
		return
	_block_data[b_id]["position"] = [new_pos.x, new_pos.y, new_pos.z]


# ── Внутренняя логика — регистрация ──────────────────────────────────────────

func _register_scene_blocks() -> void:
	_block_data.clear()

	for child in blocks_container.get_children():
		if child is BlockBase:
			var marker := child as BlockBase
			# scene_path берём из маркера напрямую — редактор заполняет его через @export
			register_block(marker.id, marker, marker.block_height, marker.district)
			# Записываем scene_path из маркера в словарь
			_block_data[marker.id]["scene_path"] = marker.scene_path
			_block_data[marker.id]["silhouette_scene_path"] = marker.silhouette_scene_path

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
