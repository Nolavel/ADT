# =============================================================================
# MapSource.gd
# Прикрепить к корневой ноде сцены mapsource.tscn
# Добавить ноду в группу: "map_source"
#
# НАЗНАЧЕНИЕ:
#   Главный скрипт редакторской сцены MapSource. Управляет метаданными мира:
#   хранит данные о небоскрёбах, экспортирует их в JSON для StreamManager,
#   обеспечивает snap небоскрёбов к поверхности CityZone.
#
# ЧТО ДЕЛАЕТ:
#   - Хранит словарь всех небоскрёбов расставленных в сцене
#   - Экспортирует данные в res://data/world_data.json
#   - Загружает ранее сохранённые данные при открытии сцены
#   - Предоставляет метод snap_to_city_zone() для привязки кубов к полу
#   - Регистрирует небоскрёбы которые добавлены как дочерние ноды
#
# СТРУКТУРА ДЕРЕВА СЦЕНЫ (mapsource.tscn):
#   MapSource (Node3D)  ← этот скрипт
#   ├── WorldZone       (StaticBody3D + MeshInstance3D + CollisionShape3D)
#   ├── CityZone        (StaticBody3D + MeshInstance3D + CollisionShape3D)
#   ├── STRATA_Doggerland  (Area3D)
#   ├── STRATA_Manifold    (Area3D)
#   ├── STRATA_Glare       (Area3D)
#   ├── District_Central   (Area3D)
#   ├── District_South     (Area3D)
#   ├── District_North     (Area3D)
#   ├── Skyscrapers        (Node3D) ← контейнер для кубов-небоскрёбов
#   ├── CameraSource       (Camera3D + CameraSource.gd)
#   └── Spawner            (Node3D + Spawner.gd)
#
# РАЗМЕРЫ МИРА (все значения в метрах = юнитах Godot):
#   WorldZone  : 2600 × 9200, Y = 0
#   CityZone   : 2100 × 8600, Y = 10  (высота меша 10м)
#   Игровой объём (CityZone Area3D): 2100 × 8600 × 1700
#
# СТРАТЫ (отсчёт от верхней поверхности CityZone = Y_CITY_ZONE_TOP):
#   Doggerland : 0   – 500  м
#   Manifold   : 500 – 1000 м
#   Glare      : 1000– 1700 м
#
# РАЙОНЫ (по длине 8600м):
#   Central : 4000 м
#   South   : 2000 м
#   North   : 2600 м
# =============================================================================

extends Node3D


# ── Константы мира ───────────────────────────────────────────────────────────

## Y верхней поверхности CityZone меша.
## Небоскрёбы ставятся на эту высоту (нижняя грань куба = этот Y).
## CityZone меш высотой 10м стоит с origin на Y=5, значит верх = Y=10.
const Y_CITY_ZONE_TOP: float = 10.0

## Путь куда сохраняем JSON с метаданными мира.
const EXPORT_PATH: String = "res://data/world_data.json"


# ── Ссылки на ноды сцены ─────────────────────────────────────────────────────
# Все пути относительно корня сцены MapSource.
# Имена нод должны совпадать с именами в редакторе Godot.

@onready var world_zone: StaticBody3D = $WorldZone/StaticBody3D
@onready var city_zone:  StaticBody3D = $CityZone/StaticBody3D

@onready var strata_doggerland: Area3D = $STRATA_Doggerland
@onready var strata_manifold:   Area3D = $STRATA_Manifold
@onready var strata_glare:      Area3D = $STRATA_Glare

@onready var district_central: Area3D = $District_CENTRAL
@onready var district_south:   Area3D = $District_SOUTH
@onready var district_north:   Area3D = $District_NORTH

## Контейнер — все небоскрёбы расставляются сюда как дочерние ноды.
@onready var skyscrapers_container: Node3D = $Skyscrapers


# ── Данные небоскрёбов ────────────────────────────────────────────────────────
# Словарь { sc_id: Dictionary } — основное хранилище метаданных.
# Заполняется при регистрации небоскрёбов и при загрузке из JSON.

var _skyscraper_data: Dictionary = {}


# ── Жизненный цикл ───────────────────────────────────────────────────────────

func _ready() -> void:
	add_to_group("map_source")
	#DirAccess.make_dir_recursive_absolute("res://data")
	#_load_data()
	#_register_scene_skyscrapers()
	#print("[MapSource] ✅ Ready. Skyscrapers registered: %d" % _skyscraper_data.size())
	#debug_full_scene_dump()  # ← временно


# ── Публичный API ─────────────────────────────────────────────────────────────

## Привязать нижнюю грань куба-небоскрёба к поверхности CityZone.
##
## node   — Node3D небоскрёба (его origin = центр куба)
## height — высота куба в метрах
##
## После вызова нижняя грань куба будет точно на Y_CITY_ZONE_TOP.
## Пример: куб высотой 400м → origin.y = 10 + 200 = 210
func snap_to_city_zone(node: Node3D, height: float) -> void:
	node.global_position.y = Y_CITY_ZONE_TOP + (height * 0.5)


## Зарегистрировать небоскрёб вручную (например при создании через код).
##
## sc_id    — уникальный ID вида "SC-C-001"
## node     — Node3D куба в сцене
## height   — высота небоскрёба в метрах
## district — "central" / "south" / "north"
func register_skyscraper(sc_id: String, node: Node3D, height: float, district: String) -> void:
	# Привязываем к полу CityZone
	snap_to_city_zone(node, height)

	# Определяем какие страты пронизывает небоскрёб
	var strata := _get_strata_for_height(height)

	# Формируем запись метаданных
	var data := {
		"id":        sc_id,
		"position":  [node.global_position.x, node.global_position.y, node.global_position.z],
		"height":    height,
		"district":  district,
		"scene_path": "",   # путь к реальной .tscn заполняется позже
		"strata_ids": {}
	}

	# Генерируем суб-ID для каждой страты которую пронизывает башня
	for stratum in strata:
		var suffix := _strata_suffix(stratum)
		data["strata_ids"][stratum] = "%s-%s" % [sc_id, suffix]

	_skyscraper_data[sc_id] = data
	print("[MapSource] 🏙️ Registered: %s at %s, height: %dm, strata: %s" % [
		sc_id, node.global_position, int(height), strata])


## Экспортировать все метаданные в JSON файл.
## Вызывается вручную или кнопкой в HUD MapSource.
## После экспорта StreamManager сможет загрузить этот файл в World.
func export_data() -> void:
	var export_array: Array = []
	for sc_id in _skyscraper_data:
		export_array.append(_skyscraper_data[sc_id])

	var json_string := JSON.stringify({"skyscrapers": export_array}, "\t")

	var file := FileAccess.open(EXPORT_PATH, FileAccess.WRITE)
	if file == null:
		push_error("[MapSource] ❌ Cannot write to: %s" % EXPORT_PATH)
		return

	file.store_string(json_string)
	file.close()

	# Обновляем путь в GameManager чтобы World знал где файл
	GameManager.world_data_path = EXPORT_PATH

	print("[MapSource] 💾 Exported %d skyscrapers to %s" % [_skyscraper_data.size(), EXPORT_PATH])


## Получить метаданные конкретного небоскрёба по ID.
func get_skyscraper_data(sc_id: String) -> Dictionary:
	return _skyscraper_data.get(sc_id, {})


## Получить все метаданные.
func get_all_data() -> Dictionary:
	return _skyscraper_data


## Обновить позицию небоскрёба в метаданных (после перемещения в редакторе).
func update_skyscraper_position(sc_id: String, new_pos: Vector3) -> void:
	if not _skyscraper_data.has(sc_id):
		return
	_skyscraper_data[sc_id]["position"] = [new_pos.x, new_pos.y, new_pos.z]


# ── Внутренняя логика ─────────────────────────────────────────────────────────

## Сканируем контейнер Skyscrapers и регистрируем все дочерние ноды
## у которых есть метаданные (через мета-свойство "sc_id").
## Это позволяет расставить кубы в редакторе и назначить им ID через
## Node > Add Custom Metadata > "sc_id" в инспекторе.
func _register_scene_skyscrapers() -> void:
	if not is_instance_valid(skyscrapers_container):
		return

	for child in skyscrapers_container.get_children():
		if not child is Node3D:
			continue

		# Проверяем есть ли у ноды мета-данные sc_id
		if not child.has_meta("sc_id"):
			# Нет ID — пропускаем (можно добавить предупреждение)
			continue

		var sc_id:   String = child.get_meta("sc_id")
		var height:  float  = float(child.get_meta("height",  400.0))
		var district: String = child.get_meta("district", "central")

		# Не перерегистрируем то что уже загружено из JSON
		if _skyscraper_data.has(sc_id):
			continue

		register_skyscraper(sc_id, child, height, district)


## Загрузить ранее сохранённые данные из JSON.
## Вызывается при _ready() — восстанавливает состояние между сессиями.
func _load_data() -> void:
	if not FileAccess.file_exists(EXPORT_PATH):
		return   # первый запуск, данных нет

	var file := FileAccess.open(EXPORT_PATH, FileAccess.READ)
	if file == null:
		return

	var json_string := file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(json_string) != OK:
		push_warning("[MapSource] ⚠️ Failed to parse saved data")
		return

	var raw = json.data
	if raw is Dictionary and raw.has("skyscrapers"):
		for entry in raw["skyscrapers"]:
			if entry is Dictionary and entry.has("id"):
				_skyscraper_data[entry["id"]] = entry

	print("[MapSource] 📂 Loaded %d skyscrapers from saved data" % _skyscraper_data.size())


## Определить в каких стратах находится небоскрёб заданной высоты.
## Отсчёт от Y_CITY_ZONE_TOP (= 0 относительно пола города).
##
## Логика: башня начинается на 0, заканчивается на height.
## Если диапазон башни перекрывается с диапазоном страты — она в этой страте.
func _get_strata_for_height(height: float) -> Array[String]:
	var result: Array[String] = []

	# Диапазоны страт (метры над полом CityZone)
	var strata_ranges := {
		"doggerland": [0.0,    500.0],
		"manifold":   [500.0,  1000.0],
		"glare":      [1000.0, 1700.0],
	}

	for stratum in strata_ranges:
		var range_min: float = strata_ranges[stratum][0]
		var range_max: float = strata_ranges[stratum][1]
		# Небоскрёб от 0 до height. Пересечение если height > range_min
		if height > range_min:
			result.append(stratum)

	return result


## Суффикс для суб-ID страты.
func _strata_suffix(stratum: String) -> String:
	match stratum:
		"doggerland": return "DG"
		"manifold":   return "MF"
		"glare":      return "GL"
	return "XX"

func debug_full_scene_dump() -> void:
	print("\n╔══════════════════════════════════════════════════════╗")
	print("║           FULL SCENE GEOMETRY DUMP                  ║")
	print("╚══════════════════════════════════════════════════════╝")

	# ── StaticBody меши (WorldZone, CityZone) ─────────────────────────────────
	print("\n── STATIC MESHES ──")
	for node in get_tree().get_nodes_in_group(""):
		pass  # не используем группы, сканируем вручную

	_dump_static_body($WorldZone, "WorldZone")
	_dump_static_body($CityZone,  "CityZone")

	# ── Area3D страты ─────────────────────────────────────────────────────────
	print("\n── STRATA AREAS ──")
	_dump_area3d($STRATA_Doggerland, "STRATA_Doggerland")
	_dump_area3d($STRATA_Manifold,   "STRATA_Manifold")
	_dump_area3d($STRATA_Glare,      "STRATA_Glare")

	# ── Area3D районы ─────────────────────────────────────────────────────────
	print("\n── DISTRICT AREAS ──")
	_dump_area3d($District_CENTRAL, "District_CENTRAL")
	_dump_area3d($District_SOUTH,   "District_SOUTH")
	_dump_area3d($District_NORTH,   "District_NORTH")

	# ── Небоскрёбы ────────────────────────────────────────────────────────────
	print("\n── SKYSCRAPERS ──")
	for child in $Skyscrapers.get_children():
		_dump_skyscraper(child)

	# ── Spawner ───────────────────────────────────────────────────────────────
	print("\n── SPAWNER ──")
	var sp := $Spawner
	print("  Spawner.global_position = %s" % sp.global_position)

	print("\n╔══════════════════════════════════════════════════════╗")
	print("║                    END DUMP                          ║")
	print("╚══════════════════════════════════════════════════════╝\n")


func _dump_static_body(parent: Node, label: String) -> void:
	print("\n  [%s]" % label)
	print("    parent.position       = %s" % (parent as Node3D).position)
	print("    parent.global_pos     = %s" % (parent as Node3D).global_position)
	for child in parent.get_children():
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			var aabb: AABB = mi.get_aabb()  # локальный AABB меша
			var world_aabb: AABB = mi.global_transform * aabb  # мировой
			print("    MeshInstance3D [%s]" % child.name)
			print("      local  AABB  pos=%s  size=%s" % [aabb.position, aabb.size])
			print("      world  AABB  pos=%s  size=%s" % [world_aabb.position, world_aabb.size])
			print("      world  end       =%s" % world_aabb.end)
		if child is StaticBody3D:
			var sb := child as StaticBody3D
			print("    StaticBody3D [%s]  pos=%s" % [child.name, sb.global_position])
			for cc in sb.get_children():
				if cc is CollisionShape3D:
					_dump_collision_shape(cc as CollisionShape3D, "      ")
		if child is CollisionShape3D:
			_dump_collision_shape(child as CollisionShape3D, "    ")


func _dump_area3d(area: Area3D, label: String) -> void:
	print("\n  [%s]" % label)
	print("    area.position         = %s" % area.position)
	print("    area.global_position  = %s" % area.global_position)
	for child in area.get_children():
		if child is CollisionShape3D:
			_dump_collision_shape(child as CollisionShape3D, "    ")


func _dump_collision_shape(cs: CollisionShape3D, indent: String) -> void:
	var shape := cs.shape
	print("%sCollisionShape3D [%s]" % [indent, cs.name])
	print("%s  .position        = %s" % [indent, cs.position])
	print("%s  .global_position = %s" % [indent, cs.global_transform.origin])
	if shape is BoxShape3D:
		var box  := shape as BoxShape3D
		var half := box.size * 0.5
		var ctr  := cs.global_transform.origin
		var world_min := ctr - half
		var world_max := ctr + half
		print("%s  BoxShape3D  size=%s" % [indent, box.size])
		print("%s  WORLD min  = %s" % [indent, world_min])
		print("%s  WORLD max  = %s" % [indent, world_max])
		print("%s  Y_range    = [%.1f  ..  %.1f]" % [indent, world_min.y, world_max.y])
		print("%s  X_range    = [%.1f  ..  %.1f]" % [indent, world_min.x, world_max.x])
		print("%s  Z_range    = [%.1f  ..  %.1f]" % [indent, world_min.z, world_max.z])
	elif shape is SphereShape3D:
		print("%s  SphereShape3D  radius=%.2f" % [indent, (shape as SphereShape3D).radius])
	elif shape is CapsuleShape3D:
		var cap := shape as CapsuleShape3D
		print("%s  CapsuleShape3D  r=%.2f  h=%.2f" % [indent, cap.radius, cap.height])
	else:
		print("%s  shape type = %s" % [indent, shape.get_class()])


func _dump_skyscraper(node: Node3D) -> void:
	var sc_id:    String = str(node.get_meta("sc_id",   "NO_ID"))
	var height:   float  = float(node.get_meta("height",  0.0))
	var district: String = str(node.get_meta("district", "?"))
	var pos     := node.global_transform.origin
	var bottom_y := pos.y - height * 0.5
	var top_y    := pos.y + height * 0.5
	print("\n  SC [%s]  district=%s" % [sc_id, district])
	print("    Node3D.global_pos = %s" % pos)
	print("    height            = %.0fm" % height)
	print("    bottom_y          = %.1f  (должен быть = Y_CITY_ZONE_TOP=10)" % bottom_y)
	print("    top_y             = %.1f" % top_y)
	# Дочерние CollisionShape
	for child in node.get_children():
		if child is CollisionShape3D:
			_dump_collision_shape(child as CollisionShape3D, "    ")
		elif child is StaticBody3D:
			for cc in (child as StaticBody3D).get_children():
				if cc is CollisionShape3D:
					_dump_collision_shape(cc as CollisionShape3D, "    ")
