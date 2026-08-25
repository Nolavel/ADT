# =============================================================================
# city_generator.gd — CityGenerator
#
# Step 5 of docs/island_rescope_brief.md: the buildings. Reads the island's own
# terrain, lays a Manhattan grid on the caldera floor, hangs a ring of towers
# on the slopes outside it, and writes both the tower scenes and
# data/world_data.tres.
#
# WHY THIS IS A RefCounted AND NOT THE EditorScript ITSELF: an EditorScript
# only runs from the editor's File -> Run; `--script` from the CLI silently
# does nothing with one (verified). Splitting the logic out gives two entry
# points over one implementation — generate_city.gd for a person in the editor,
# generate_city_cli.gd for a headless agent run. Neither duplicates the other.
#
# WHAT IT READS: the heightmap PNG, not the island scene's HeightMapShape3D.
# The collision array is what the player actually stands on and was the first
# choice for exactly that reason — but it lives inside a 41 MB text scene that
# takes minutes to parse, and a tool a person runs by hand cannot open with a
# multi-minute stall. The two were measured against each other and agree to
# within half a metre, which is nothing beside terrain quantized in 2 m steps.
# If the shader and the collision ever stop agreeing, this is the line to
# revisit.
#
# THE SLOPE TRAP: the heightmap is 8-bit, so height quantizes in ~1.96 m steps
# on a 6.84 m grid. Measuring slope between neighbouring samples therefore
# measures the quantization — a flat floor reads as 16 degrees. Slope here is
# taken over a wide baseline (SLOPE_BASELINE_CELLS) which averages the steps
# out. Narrow it and the generator will refuse to build on perfectly good
# ground.
#
# WHAT IT WRITES: a LIBRARY of tower scenes keyed by (footprint family, height
# bucket) and one BlockData per placement pointing into it. Not one scene per
# tower: 201 towers would be 402 files, and StreamingSystems._packed_cache
# exists precisely so cells sharing a content path cost one load between them.
# =============================================================================
@tool

extends RefCounted
class_name CityGenerator


# ── Что генерируется ─────────────────────────────────────────────────────────

## Обычных башен (высоты в диапазоне ниже) плюс одна смысловая на LANDMARK_HEIGHT.
const CORE_TOWERS: int = 160
const RING_TOWERS: int = 40
const LANDMARK_HEIGHT: float = 1000.0

const HEIGHT_MIN: float = 200.0
const HEIGHT_MAX: float = 700.0

## Высоты округляются до этого шага, чтобы библиотека сцен была конечной:
## (700-200)/25 + 1 = 21 корзина на семейство footprint'ов. Уменьшишь шаг —
## получишь больше файлов и более гладкий силуэт.
const HEIGHT_STEP: float = 25.0


# ── Манхэттенская сетка ──────────────────────────────────────────────────────
#
# Авеню идут с севера на юг (шаг по X), улицы — с запада на восток (шаг по Z).
# Шаг по X заметно больше шага по Z, и footprint вытянут вдоль X: именно
# несовпадение двух шагов делает направление читаемым — стоя на перекрёстке
# видно, какая ось «длинная». Сделаешь ячейку квадратной — направления
# пропадут, и город станет шахматной доской без севера.

const AVENUE_STEP_X: float = 85.0
const STREET_STEP_Z: float = 46.0

## Габарит башни в плане; разница с шагом — ширина проезда: 85-64 = 21 м вдоль
## авеню, 46-30 = 16 м вдоль улицы. Башня получается лезвием (700 м высоты на
## 30 м узкой стороны), и это НАМЕРЕННО: узкая сторона смотрит вдоль улицы, а
## широкая вдоль авеню, так что с любого перекрёстка видно, какая ось какая.
const CORE_FOOTPRINT: Vector2 = Vector2(64.0, 30.0)

## Кольцевые башни квадратные — они стоят не в сетке, и вытянутость там
## читалась бы как случайный поворот.
const RING_FOOTPRINT: Vector2 = Vector2(56.0, 56.0)


# ── Кольцо ───────────────────────────────────────────────────────────────────

## Радиус кольца от центра острова, метры. Обод кальдеры лежит на 700-1000.
const RING_RADIUS: float = 840.0
const RING_RADIUS_TOLERANCE: float = 260.0

## Доля кольцевых башен, которым достаётся верх диапазона высот.
## ТЗ: «во вне по кольцу тоже высокие башни иногда, преимущественно».
const RING_TALL_SHARE: float = 0.7


# ── Пригодность земли ────────────────────────────────────────────────────────

const SEA_LEVEL: float = 45.0

## Запас над водой: башня на самом урезе выглядит тонущей.
const SHORE_MARGIN: float = 12.0

## Максимальный уклон под башней. Читается по широкой базе — см. шапку.
const MAX_SLOPE_CORE: float = 20.0
const MAX_SLOPE_RING: float = 26.0
const SLOPE_BASELINE_CELLS: int = 5

## Конус Маруямы остаётся незастроенным (ТЗ). Центр смещён от центра острова.
const MARUYAMA_CENTRE: Vector2 = Vector2(40.0, 80.0)
const MARUYAMA_RADIUS: float = 400.0


# ── Пути ─────────────────────────────────────────────────────────────────────

const HEIGHTMAP_PNG: String = "res://world/aogashima/aogashima_heightmap_16bit.png"

## Как PNG кодирует высоту: канал R, растянутый на этот диапазон. Совпадает с
## shader_parameter/height_range в сцене острова.
const HEIGHT_RANGE: float = 500.0

## Физический размер карты по стороне и сдвиг тела террейна по Y — оба из сцены
## острова (PlaneMesh 3500x3500, TerrainStaticBody на Y 0.55).
const MAP_SIZE_M: float = 3500.0
const TERRAIN_BASE_Y: float = 0.55
const CONTENT_DIR: String = "res://world/content/blocks/city"
const SILHOUETTE_DIR: String = "res://world/silhouettes/blocks/city"
const WORLD_DATA_PATH: String = "res://data/world_data.tres"

const MAT_CONTENT: String = "res://assets/tres/greybox_mat_content.tres"
const MAT_SILHOUETTE: String = "res://assets/tres/greybox_mat_silhouette.tres"

const SEED: int = 20260825


# ── Поле высот, снятое со сцены острова ──────────────────────────────────────

var _heights: PackedFloat32Array = PackedFloat32Array()
var _map_w: int = 0
var _map_d: int = 0
var _cell_size: float = 1.0
var _base_y: float = 0.0

var _rng := RandomNumberGenerator.new()
var _log: PackedStringArray = PackedStringArray()


## Единственная публичная точка входа. Возвращает отчёт строками — обе
## обёртки просто печатают его.
func generate() -> PackedStringArray:
	_rng.seed = SEED
	_log = PackedStringArray()

	if not _load_heightfield():
		return _log

	var mat_content := load(MAT_CONTENT) as Material
	var mat_silhouette := load(MAT_SILHOUETTE) as Material
	if mat_content == null or mat_silhouette == null:
		_say("ОШИБКА: не загрузились материалы greybox — генерация отменена")
		return _log

	DirAccess.make_dir_recursive_absolute(CONTENT_DIR)
	DirAccess.make_dir_recursive_absolute(SILHOUETTE_DIR)

	var placements: Array[Dictionary] = []
	placements.append_array(_place_core())
	placements.append_array(_place_ring())
	var landmark := _place_landmark()
	if not landmark.is_empty():
		placements.append(landmark)

	if placements.is_empty():
		_say("ОШИБКА: не нашлось ни одной пригодной точки — генерация отменена")
		return _log

	var library := _build_library(placements, mat_content, mat_silhouette)
	_write_world_data(placements, library)

	_say("Итог: %d башен, %d сцен в библиотеке" % [placements.size(), library.size() * 2])
	return _log


# ── Поле высот ───────────────────────────────────────────────────────────────

## Снимает высоты из PNG. Изображение читается один раз в PackedFloat32Array,
## потому что Image.get_pixel() на каждый из сотен тысяч запросов уклона —
## главный источник тормозов в таких генераторах.
func _load_heightfield() -> bool:
	var tex := load(HEIGHTMAP_PNG) as Texture2D
	if tex == null:
		_say("ОШИБКА: не открылась карта высот %s" % HEIGHTMAP_PNG)
		return false
	var img := tex.get_image()
	if img == null:
		_say("ОШИБКА: из %s не достать Image" % HEIGHTMAP_PNG)
		return false

	_map_w = img.get_width()
	_map_d = img.get_height()
	_cell_size = MAP_SIZE_M / float(_map_w - 1)
	_base_y = TERRAIN_BASE_Y

	_heights.resize(_map_w * _map_d)
	for row in _map_d:
		for col in _map_w:
			_heights[row * _map_w + col] = img.get_pixel(col, row).r * HEIGHT_RANGE

	_say("Карта высот: %dx%d, клетка %.3f м, база Y %.2f"
			% [_map_w, _map_d, _cell_size, _base_y])
	return true


func _height_at(x: float, z: float) -> float:
	var col := int(round(x / _cell_size + float(_map_w - 1) * 0.5))
	var row := int(round(z / _cell_size + float(_map_d - 1) * 0.5))
	col = clampi(col, 0, _map_w - 1)
	row = clampi(row, 0, _map_d - 1)
	return _heights[row * _map_w + col] + _base_y


## Уклон в градусах по широкой базе — см. «THE SLOPE TRAP» в шапке.
func _slope_at(x: float, z: float) -> float:
	var d := float(SLOPE_BASELINE_CELLS) * _cell_size
	var dx := (_height_at(x + d, z) - _height_at(x - d, z)) / (2.0 * d)
	var dz := (_height_at(x, z + d) - _height_at(x, z - d)) / (2.0 * d)
	return rad_to_deg(atan(Vector2(dx, dz).length()))


func _is_buildable(x: float, z: float, max_slope: float) -> bool:
	if Vector2(x, z).distance_to(MARUYAMA_CENTRE) < MARUYAMA_RADIUS:
		return false
	if _height_at(x, z) < SEA_LEVEL + SHORE_MARGIN:
		return false
	return _slope_at(x, z) <= max_slope


# ── Ядро: манхэттенская сетка ────────────────────────────────────────────────

## Кладёт сетку на весь остров, оставляет пригодные перекрёстки и берёт
## CORE_TOWERS лучших. «Лучших» = ближе к центру застройки: так город получает
## плотную середину и разрежается к краю, вместо ровного ковра до самой воды.
func _place_core() -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	var half := 1750.0
	var x := -half
	while x <= half:
		var z := -half
		while z <= half:
			if _is_buildable(x, z, MAX_SLOPE_CORE):
				candidates.append({"x": x, "z": z})
			z += STREET_STEP_Z
		x += AVENUE_STEP_X

	_say("Сетка: %d пригодных перекрёстков (уклон <= %.0f°)"
			% [candidates.size(), MAX_SLOPE_CORE])
	if candidates.is_empty():
		return []

	## Центр даунтауна — не центроид всех пригодных точек, а самая ПЛОТНАЯ из
	## них. Центроид на рваном острове попадает в середину между разрозненными
	## пятнами земли, и «ядро» расползается по всему берегу вместо того, чтобы
	## быть кварталом, по которому видно, где ты.
	var centre := _densest_of(candidates)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return centre.distance_to(Vector2(a["x"], a["z"])) \
				< centre.distance_to(Vector2(b["x"], b["z"])))

	var taken: Array[Dictionary] = []
	var count: int = mini(CORE_TOWERS, candidates.size())
	## Радиус застройки — до самой дальней взятой точки; по нему же считается
	## профиль высот, чтобы «мидтаун» оказался там, где город плотный.
	var reach := 1.0
	for i in count:
		var c: Dictionary = candidates[i]
		reach = maxf(reach, centre.distance_to(Vector2(c["x"], c["z"])))

	for i in count:
		var c: Dictionary = candidates[i]
		var pos := Vector2(c["x"], c["z"])
		## Манхэттенский профиль: высоко в середине, ниже к окраине. Именно это
		## делает силуэт городом с центром, а не полем одинаковых столбов.
		var t := clampf(centre.distance_to(pos) / reach, 0.0, 1.0)
		var h := lerpf(HEIGHT_MAX, HEIGHT_MIN, t * t)
		## Джиттер ПОСЛЕ профиля и с зажимом здесь же: _placement() зажимает по
		## LANDMARK_HEIGHT, потому что смысловой башне нужны её 1000, и общий
		## зажим выпускал обычные башни на 725-750.
		h = clampf(h + _rng.randf_range(-60.0, 60.0), HEIGHT_MIN, HEIGHT_MAX)
		taken.append(_placement("cty_%03d" % (i + 1), c["x"], c["z"], h, CORE_FOOTPRINT))

	if count < CORE_TOWERS:
		_say("ВНИМАНИЕ: сетка дала только %d точек из %d — ослабь MAX_SLOPE_CORE или сожми шаг"
				% [count, CORE_TOWERS])
	_say("Ядро: %d башен, центр (%.0f, %.0f), радиус застройки %.0f м"
			% [taken.size(), centre.x, centre.y, reach])
	return taken


## Точка с наибольшим числом соседей в радиусе DENSITY_RADIUS. Квадратичный
## проход, но кандидатов сотни, а не миллионы.
const DENSITY_RADIUS: float = 320.0

func _densest_of(points: Array[Dictionary]) -> Vector2:
	var best := Vector2(points[0]["x"], points[0]["z"])
	var best_n := -1
	for a in points:
		var pa := Vector2(a["x"], a["z"])
		var n := 0
		for b in points:
			if pa.distance_to(Vector2(b["x"], b["z"])) <= DENSITY_RADIUS:
				n += 1
		if n > best_n:
			best_n = n
			best = pa
	return best


# ── Кольцо ───────────────────────────────────────────────────────────────────

## По одной башне на сектор: от идеального радиуса расходимся наружу и внутрь,
## пока не найдём землю. Так кольцо остаётся кольцом на рваном рельефе, вместо
## того чтобы рассыпаться там, где идеальная окружность уходит в море.
func _place_ring() -> Array[Dictionary]:
	var taken: Array[Dictionary] = []
	for i in RING_TOWERS:
		var angle := TAU * float(i) / float(RING_TOWERS)
		var dir := Vector2(cos(angle), sin(angle))
		var found := Vector2.INF
		var step := 20.0
		var offset := 0.0
		while offset <= RING_RADIUS_TOLERANCE:
			for sign_out: float in [1.0, -1.0]:
				var probe: Vector2 = dir * (RING_RADIUS + sign_out * offset)
				if _is_buildable(probe.x, probe.y, MAX_SLOPE_RING):
					found = probe
					break
			if found != Vector2.INF:
				break
			offset += step

		if found == Vector2.INF:
			continue
		if _too_close(taken, found, RING_FOOTPRINT.x * 1.6):
			continue

		var tall := _rng.randf() < RING_TALL_SHARE
		var h := _rng.randf_range(HEIGHT_MAX - 140.0, HEIGHT_MAX) if tall \
				else _rng.randf_range(HEIGHT_MIN, HEIGHT_MIN + 180.0)
		taken.append(_placement("rng_%03d" % (i + 1), found.x, found.y, h, RING_FOOTPRINT))

	_say("Кольцо: %d башен из %d секторов (радиус %.0f ± %.0f м)"
			% [taken.size(), RING_TOWERS, RING_RADIUS, RING_RADIUS_TOLERANCE])
	return taken


func _too_close(taken: Array[Dictionary], p: Vector2, limit: float) -> bool:
	for t in taken:
		if Vector2(t["position"].x, t["position"].z).distance_to(p) < limit:
			return true
	return false


# ── Смысловая башня ──────────────────────────────────────────────────────────

## Одна на 1000 м — ТЗ требует, чтобы её было видно со дна кальдеры отовсюду,
## поэтому она ищет самую ровную точку рядом с центром, а не случайную.
func _place_landmark() -> Dictionary:
	var best := Vector2.INF
	var best_slope := 999.0
	var r := 0.0
	while r <= 420.0:
		var steps: int = maxi(8, int(r / 25.0))
		for i in steps:
			var a := TAU * float(i) / float(steps)
			var p := Vector2(cos(a), sin(a)) * r
			if not _is_buildable(p.x, p.y, MAX_SLOPE_CORE):
				continue
			var s := _slope_at(p.x, p.y)
			if s < best_slope:
				best_slope = s
				best = p
		r += 30.0

	if best == Vector2.INF:
		_say("ВНИМАНИЕ: смысловой башне не нашлось места — она пропущена")
		return {}
	_say("Смысловая башня: (%.0f, %.0f), уклон %.1f°" % [best.x, best.y, best_slope])
	return _placement("landmark", best.x, best.y, LANDMARK_HEIGHT, RING_FOOTPRINT)


# ── Общее ────────────────────────────────────────────────────────────────────

func _placement(id: String, x: float, z: float, height: float,
		footprint: Vector2) -> Dictionary:
	var h := clampf(height, HEIGHT_MIN, LANDMARK_HEIGHT)
	h = round(h / HEIGHT_STEP) * HEIGHT_STEP
	return {
		"id": id,
		"position": Vector3(x, _height_at(x, z), z),
		"height": h,
		"footprint": footprint,
	}


## Ключ библиотеки: одинаковый footprint и одинаковая высота — одна пара сцен
## на всех, и _packed_cache грузит её один раз.
func _library_key(p: Dictionary) -> String:
	var f: Vector2 = p["footprint"]
	return "twr_%dx%d_h%d" % [int(f.x), int(f.y), int(p["height"])]


func _build_library(placements: Array[Dictionary], mat_content: Material,
		mat_silhouette: Material) -> Dictionary:
	var library := {}
	for p in placements:
		var key := _library_key(p)
		if library.has(key):
			continue
		var size := Vector3(p["footprint"].x, p["height"], p["footprint"].y)
		var content_path := "%s/%s.tscn" % [CONTENT_DIR, key]
		var sil_path := "%s/%s_silhouette.tscn" % [SILHOUETTE_DIR, key]
		if not _save_content(content_path, key, size, mat_content):
			continue
		if not _save_silhouette(sil_path, key, size, mat_silhouette):
			continue
		library[key] = {"content": content_path, "silhouette": sil_path}
	_say("Библиотека: %d уникальных башен" % library.size())
	return library


## Контент — только визуал (зелёный greybox). Коллизию несёт силуэт: она
## постоянная и не выгружается, поэтому башня твёрдая и вне радиуса стриминга.
func _save_content(path: String, key: String, size: Vector3, mat: Material) -> bool:
	var root := Node3D.new()
	root.name = key.to_pascal_case()
	root.set_meta("gbx_size", size)
	root.set_meta("gbx_kind", "content")

	var shared := Node3D.new()
	shared.name = "Shared"
	root.add_child(shared)
	shared.owner = root

	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.name = "MeshInstance3D"
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = Vector3(0.0, size.y * 0.5, 0.0)
	shared.add_child(mi)
	mi.owner = root

	return _pack_and_save(root, path)


## Силуэт — тёмный меш того же габарита плюс постоянная коллизия стены
## (физслой 3, группа "wall"), как у остальных силуэтов в проекте.
func _save_silhouette(path: String, key: String, size: Vector3, mat: Material) -> bool:
	var root := Node3D.new()
	root.name = "%sSilhouette" % key.to_pascal_case()
	root.set_meta("gbx_size", size)
	root.set_meta("gbx_kind", "silhouette")

	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = Vector3(0.0, size.y * 0.5, 0.0)
	root.add_child(mi)
	mi.owner = root

	var body := StaticBody3D.new()
	body.name = "StaticBody3D"
	body.collision_layer = 1 << 2
	body.collision_mask = 0
	body.add_to_group("wall", true)
	root.add_child(body)
	body.owner = root

	var box := BoxShape3D.new()
	box.size = size
	var cs := CollisionShape3D.new()
	cs.name = "CollisionShape3D"
	cs.shape = box
	cs.position = Vector3(0.0, size.y * 0.5, 0.0)
	body.add_child(cs)
	cs.owner = root

	return _pack_and_save(root, path)


func _pack_and_save(root: Node, path: String) -> bool:
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err != OK:
		_say("ОШИБКА: pack() провалился для %s (%d)" % [path, err])
		root.free()
		return false
	err = ResourceSaver.save(packed, path)
	root.free()
	if err != OK:
		_say("ОШИБКА: не сохранилась сцена %s (%d)" % [path, err])
		return false
	return true


func _write_world_data(placements: Array[Dictionary], library: Dictionary) -> void:
	var world := WorldData.new()
	for p in placements:
		var key := _library_key(p)
		if not library.has(key):
			continue
		var bd := BlockData.new()
		bd.id = p["id"]
		bd.position = p["position"]
		bd.height = p["height"]
		bd.district = "A1"
		bd.content_scene_path = library[key]["content"]
		bd.silhouette_scene_path = library[key]["silhouette"]
		world.blocks.append(bd)

	## Точку спавна не трогаем: её ставят отдельно, и перезаписывать её
	## застройкой значило бы терять её при каждом прогоне генератора.
	var existing := load(WORLD_DATA_PATH) as WorldData
	world.spawn_point = existing.spawn_point if existing != null else Vector3.ZERO

	var err := ResourceSaver.save(world, WORLD_DATA_PATH)
	if err != OK:
		_say("ОШИБКА: не сохранился %s (%d)" % [WORLD_DATA_PATH, err])
		return
	_say("Записан %s: %d кварталов, спавн %s"
			% [WORLD_DATA_PATH, world.blocks.size(), world.spawn_point])


func _say(line: String) -> void:
	_log.append(line)
	print("[CityGenerator] ", line)
