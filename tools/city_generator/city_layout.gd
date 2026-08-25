# =============================================================================
# city_layout.gd — CityLayout: вся логика генератора города.
#
# ЭТО НЕ ТОТ ФАЙЛ, КОТОРЫЙ ЗАПУСКАЮТ. Запускается generate_city.gd (File -> Run
# в редакторе) или generate_city_cli.gd (сухой прогон из CLI). Здесь только
# логика, общая для обоих.
#
# ПОЧЕМУ ОТДЕЛЬНЫЙ КЛАСС, А НЕ САМ EditorScript: EditorScript нельзя
# инстанцировать вне редактора — Godot отвечает «Class EditorScript can only be
# instantiated by editor». Значит headless-обёртка не может просто создать
# EditorScript и позвать его метод; общий код обязан жить в обычном RefCounted.
# Проверено попыткой сделать наоборот.
#
# -----------------------------------------------------------------------------
# ПОЧЕМУ РАСКЛАДКА ИМЕННО ТАКАЯ (первая версия выглядела «генеративно»)
#
# Первая версия сеяла решётку по всему острову, проверяла каждый перекрёсток на
# уклон и выбрасывала непрошедшие. Земля здесь рваная, поэтому от сетки
# оставалось конфетти: точки по шагу есть, а сквозных улиц нет ни одной. Сетка
# читается НЕ тем, что дома стоят по шагу, а тем, что между ними идут
# непрерывные коридоры.
#
# Отсюда два правила, на которых держится всё остальное:
#
#   1. Сетка растёт КОЛЬЦАМИ ОТ ГЛАВНОЙ БАШНИ, а не сеется по площади.
#   2. Непригодная ячейка остаётся ПУСТОЙ, а не пропускается ради далёкой
#      пригодной. Дыра в ряду читается как площадь или сквер; ряд при этом не
#      рвётся, и улица проходит насквозь.
#
# Высота падает от центра кольцами — так «главная башня окружена башнями меньше
# размера» получается геометрией, а не случайностью.
#
# ГОРОД СТОИТ НА ВУЛКАНЕ. Решение 2026-08-25, отменяет строку ТЗ про
# незастроенную Маруяму. Вершина конуса (~218 м) — якорь: башня в 1000 м на ней
# достаёт до 1218 при потолке мира 1250 и видна отовсюду, чего ТЗ и требует.
# Прежняя версия запрещала строить в радиусе 400 м от центра и оставляла ровно
# посреди острова дыру.
#
# -----------------------------------------------------------------------------
# ЧТО ЧИТАЕТ: карту высот PNG, а не HeightMapShape3D из сцены острова.
# Коллизия — то, на чём игрок реально стоит, и была первым выбором именно
# поэтому, но она лежит внутри текстовой сцены на 41 МБ, которая парсится
# минутами; инструмент, запускаемый руками, не может открываться столько.
# Оба источника сверены и расходятся в пределах полуметра.
#
# ЛОВУШКА УКЛОНА: карта высот 8-битная, ступень ~1.96 м на клетке 1.71 м. Уклон
# между соседними сэмплами меряет квантизацию, а не рельеф — ровное дно
# кальдеры читается как обрыв. Уклон здесь берётся по широкой базе
# (SLOPE_BASELINE_CELLS). Сузишь — генератор откажется строить на нормальной
# земле.
#
# ЧТО ПИШЕТ: библиотеку сцен башен (ключ = габарит + корзина высоты) и маркеры
# BlockBase в BLOCKS. world_data.tres пишет уже сам map_source своей кнопкой
# Export — это документированный путь, генератор в него не лезет.
# =============================================================================
extends RefCounted
class_name CityLayout


# ── Сколько и какой высоты ───────────────────────────────────────────────────

## Всего 151: 1 главная + 100 даунтаун + 30 обод + 20 внешний пояс.
## TOTAL_TOWERS — контракт: если какой-то пояс недобрал (на ободе бывает
## сектор без земли), недостачу добирает внешний пояс, и число сходится.
const TOTAL_TOWERS: int = 151
const LANDMARK_HEIGHT: float = 1000.0
const DOWNTOWN_TOWERS: int = 100
const OUTER_TOWERS: int = 20
const RIM_TOWERS: int = 30

const HEIGHT_MIN: float = 200.0
const HEIGHT_MAX: float = 700.0

## Высоты округляются до этого шага, чтобы библиотека сцен была конечной.
const HEIGHT_STEP: float = 25.0

## Во сколько раз падает высота на каждое кольцо от главной башни.
## 0.88 даёт 616 на первом кольце и 200 примерно на десятом — плавную корону
## вокруг доминанты. Ближе к 1.0 — плоский город, ближе к 0.7 — резкий обрыв.
const RING_FALLOFF: float = 0.88

## Разброс поверх кольцевого профиля, чтобы силуэт не был правильным конусом.
const HEIGHT_JITTER: float = 60.0


# ── Сетка ────────────────────────────────────────────────────────────────────
#
# Авеню идут с севера на юг (шаг по X), улицы — с запада на восток (шаг по Z).
# Шаги РАЗНЫЕ, и footprint вытянут вдоль X: именно несовпадение осей делает
# направление читаемым — с перекрёстка видно, какая ось длинная. Квадратная
# ячейка дала бы шахматную доску без севера.

const AVENUE_STEP_X: float = 85.0
const STREET_STEP_Z: float = 46.0
const CORE_FOOTPRINT: Vector2 = Vector2(64.0, 30.0)

## Внешний пояс на дне кальдеры: шаг реже, дома ниже. Нужен, чтобы центр и
## периферия отличались на глаз — в первой версии весь город был одним ковром.
const OUTER_STEP_X: float = 130.0
const OUTER_STEP_Z: float = 70.0
const OUTER_FOOTPRINT: Vector2 = Vector2(96.0, 48.0)
const OUTER_HEIGHT_SPAN: float = 150.0

## Дальше скольких колец даунтаун не растёт, даже если башни ещё не кончились.
const MAX_DOWNTOWN_RING: int = 24


# ── Обод кальдеры ────────────────────────────────────────────────────────────

const RIM_RADIUS: float = 840.0
const RIM_RADIUS_TOLERANCE: float = 260.0

## Доля башен обода, которым достаётся верх диапазона высот.
const RIM_TALL_SHARE: float = 0.7


# ── Пригодность земли ────────────────────────────────────────────────────────

const SEA_LEVEL: float = 45.0
const SHORE_MARGIN: float = 12.0

## 25°, а не 20: склоны Маруямы держатся в 20–25°, и при 20 даунтаун на конус
## просто не влезает.
const MAX_SLOPE_CORE: float = 25.0
const MAX_SLOPE_RIM: float = 26.0
const SLOPE_BASELINE_CELLS: int = 5

## Где искать вершину под главную башню.
const MARUYAMA_CENTRE: Vector2 = Vector2(40.0, 80.0)
const SUMMIT_SEARCH_RADIUS: float = 260.0


# ── Пути ─────────────────────────────────────────────────────────────────────

const HEIGHTMAP_PNG: String = "res://world/aogashima/aogashima_heightmap_16bit.png"

## Как PNG кодирует высоту: канал R на этот диапазон. Совпадает с
## shader_parameter/height_range в сцене острова.
const HEIGHT_RANGE: float = 500.0
const MAP_SIZE_M: float = 3500.0
const TERRAIN_BASE_Y: float = 0.55

const CONTENT_DIR: String = "res://world/content/blocks/city"
const SILHOUETTE_DIR: String = "res://world/silhouettes/blocks/city"

const MAT_CONTENT: String = "res://assets/tres/greybox_mat_content.tres"
const MAT_SILHOUETTE: String = "res://assets/tres/greybox_mat_silhouette.tres"

const BLOCKBASE_SCRIPT_PATH: String = "res://core/map_source/blockbase.gd"

## Конвенция docs/CONTRIBUTING.md: маркеры с этим префиксом принадлежат
## генератору и удаляются при следующем прогоне. Снимешь префикс — маркер
## становится авторским и переживёт регенерацию.
const MARKER_PREFIX: String = "GBX_"

const SEED: int = 20260825


# ── Состояние прогона ────────────────────────────────────────────────────────

var _heights: PackedFloat32Array = PackedFloat32Array()
var _map_w: int = 0
var _map_d: int = 0
var _cell_size: float = 1.0

var _rng := RandomNumberGenerator.new()


# ── Раскладка (работает и без редактора) ─────────────────────────────────────

## Считает позиции всех башен. Ничего не пишет на диск и не трогает сцену —
## поэтому её же зовёт сухой прогон из generate_city_cli.gd.
func compute_layout() -> Array[Dictionary]:
	_rng.seed = SEED
	if not _load_heightfield():
		return []

	var summit := _find_summit()
	print("[CityGenerator] Вершина под главную башню: (%.0f, %.0f), %.1f м"
			% [summit.x, summit.y, _height_at(summit.x, summit.y)])

	var placements: Array[Dictionary] = []
	placements.append(_placement("landmark", summit.x, summit.y,
			LANDMARK_HEIGHT, CORE_FOOTPRINT))

	placements.append_array(_place_belt(summit, placements,
			AVENUE_STEP_X, STREET_STEP_Z, CORE_FOOTPRINT,
			DOWNTOWN_TOWERS, 1, "cty", true))

	## Обод ставится РАНЬШЕ внешнего пояса. Порядок не косметический: пояс
	## расходится от центра и при обратном порядке успевает занять места на
	## ободе, после чего сектора отбраковываются по минимальной дистанции и
	## кольцо получается дырявым (было 19 секторов из 30).
	placements.append_array(_place_rim(placements))

	## Внешний пояс идёт по своей, более редкой сетке от того же якоря — так
	## улицы двух поясов остаются соосными и город не распадается на два
	## несвязанных куска.
	placements.append_array(_place_belt(summit, placements,
			OUTER_STEP_X, OUTER_STEP_Z, OUTER_FOOTPRINT,
			OUTER_TOWERS, 1, "out", false))

	var missing: int = TOTAL_TOWERS - placements.size()
	if missing > 0:
		placements.append_array(_place_belt(summit, placements,
				OUTER_STEP_X, OUTER_STEP_Z, OUTER_FOOTPRINT,
				missing, 1, "fil", false))

	print("[CityGenerator] Всего башен: %d" % placements.size())
	_report_heights(placements)
	return placements


## Один пояс: обход ячеек кольцами Чебышёва от якоря наружу.
##
## Непригодная ячейка ПРОПУСКАЕТСЯ БЕЗ ЗАМЕНЫ — это и есть то, что делает
## раскладку городом. Если вместо неё брать ближайшую пригодную, ряды съезжают
## и улицы перестают быть сквозными; так выглядела первая версия.
func _place_belt(anchor: Vector2, existing: Array[Dictionary],
		step_x: float, step_z: float, footprint: Vector2,
		want: int, start_ring: int, id_prefix: String,
		tall_profile: bool) -> Array[Dictionary]:

	var taken: Array[Dictionary] = []
	var min_gap: float = maxf(footprint.x, footprint.y) * 0.9
	var ring: int = start_ring
	var skipped: int = 0

	while taken.size() < want and ring <= MAX_DOWNTOWN_RING:
		for cell in _ring_cells(ring):
			if taken.size() >= want:
				break
			var pos := anchor + Vector2(float(cell.x) * step_x, float(cell.y) * step_z)
			if not _is_buildable(pos.x, pos.y, MAX_SLOPE_CORE):
				skipped += 1
				continue
			if _too_close(existing, pos, min_gap) or _too_close(taken, pos, min_gap):
				skipped += 1
				continue

			var h: float
			if tall_profile:
				h = HEIGHT_MAX * pow(RING_FALLOFF, float(ring))
			else:
				h = HEIGHT_MIN + _rng.randf_range(0.0, OUTER_HEIGHT_SPAN)
			h = clampf(h + _rng.randf_range(-HEIGHT_JITTER, HEIGHT_JITTER),
					HEIGHT_MIN, HEIGHT_MAX)

			taken.append(_placement("%s_%03d" % [id_prefix, taken.size() + 1],
					pos.x, pos.y, h, footprint))
		ring += 1

	print("[CityGenerator] Пояс '%s': %d башен, колец %d, пустых ячеек %d"
			% [id_prefix, taken.size(), ring - 1, skipped])
	if taken.size() < want:
		print("[CityGenerator] ВНИМАНИЕ: пояс '%s' недобрал %d — ослабь MAX_SLOPE_CORE или подними MAX_DOWNTOWN_RING"
				% [id_prefix, want - taken.size()])
	return taken


## Координаты ячеек одного кольца Чебышёва вокруг (0,0).
func _ring_cells(ring: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if ring <= 0:
		cells.append(Vector2i.ZERO)
		return cells
	for i in range(-ring, ring + 1):
		cells.append(Vector2i(i, -ring))
		cells.append(Vector2i(i, ring))
	for j in range(-ring + 1, ring):
		cells.append(Vector2i(-ring, j))
		cells.append(Vector2i(ring, j))
	return cells


## Обод кальдеры: по одной башне на сектор, от идеального радиуса расходимся
## наружу и внутрь, пока не найдём землю. Так кольцо остаётся кольцом на рваном
## рельефе вместо того, чтобы рассыпаться там, где окружность уходит в море.
func _place_rim(existing: Array[Dictionary]) -> Array[Dictionary]:
	var taken: Array[Dictionary] = []
	for i in RIM_TOWERS:
		var angle := TAU * float(i) / float(RIM_TOWERS)
		var dir := Vector2(cos(angle), sin(angle))
		var found := Vector2.INF
		var offset := 0.0
		while offset <= RIM_RADIUS_TOLERANCE:
			for sign_out: float in [1.0, -1.0]:
				var probe: Vector2 = dir * (RIM_RADIUS + sign_out * offset)
				if _is_buildable(probe.x, probe.y, MAX_SLOPE_RIM):
					found = probe
					break
			if found != Vector2.INF:
				break
			offset += 20.0

		if found == Vector2.INF:
			continue
		if _too_close(existing, found, 120.0) or _too_close(taken, found, 120.0):
			continue

		var tall: bool = _rng.randf() < RIM_TALL_SHARE
		var h: float
		if tall:
			h = _rng.randf_range(HEIGHT_MAX - 140.0, HEIGHT_MAX)
		else:
			h = _rng.randf_range(HEIGHT_MIN, HEIGHT_MIN + 180.0)
		taken.append(_placement("rim_%03d" % (i + 1), found.x, found.y,
				h, OUTER_FOOTPRINT))

	print("[CityGenerator] Обод: %d башен из %d секторов" % [taken.size(), RIM_TOWERS])
	return taken


func _too_close(taken: Array[Dictionary], p: Vector2, limit: float) -> bool:
	for t in taken:
		var tp: Vector3 = t["position"]
		if Vector2(tp.x, tp.z).distance_to(p) < limit:
			return true
	return false


func _placement(id: String, x: float, z: float, height: float,
		footprint: Vector2) -> Dictionary:
	var h: float = round(height / HEIGHT_STEP) * HEIGHT_STEP
	return {
		"id": id,
		"position": Vector3(x, _height_at(x, z), z),
		"height": h,
		"footprint": footprint,
	}


func _report_heights(placements: Array[Dictionary]) -> void:
	var lo := 99999.0
	var hi := 0.0
	for p in placements:
		var h: float = p["height"]
		lo = minf(lo, h)
		hi = maxf(hi, h)
	print("[CityGenerator] Высоты: %.0f..%.0f м" % [lo, hi])


# ── Поле высот ───────────────────────────────────────────────────────────────

## Читает PNG НАПРЯМУЮ через Image.load_from_file(), минуя импорт-пайплайн, и
## разбирает сырые байты. Через Texture2D.get_image() + get_pixel() это 4.2
## миллиона вызовов на карте 2048x2048 — минуты, и генератор, который человек
## запускает руками, столько открываться не может. Здесь один проход по
## PackedByteArray.
##
## Карта — 8-битная RGB, данные только в канале R (G и B нулевые). Имя файла
## обещает 16 бит, но save_png() их не сохранил; отсюда же и ступень ~1.96 м,
## из-за которой уклон приходится мерить по широкой базе.
func _load_heightfield() -> bool:
	var img := Image.load_from_file(HEIGHTMAP_PNG)
	if img == null:
		push_error("[CityGenerator] не открылась карта высот %s" % HEIGHTMAP_PNG)
		return false

	_map_w = img.get_width()
	_map_d = img.get_height()
	_cell_size = MAP_SIZE_M / float(_map_w - 1)

	var fmt := img.get_format()
	if fmt != Image.FORMAT_RGB8 and fmt != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGB8)
		fmt = Image.FORMAT_RGB8
	var stride: int = 4 if fmt == Image.FORMAT_RGBA8 else 3

	var raw: PackedByteArray = img.get_data()
	var count: int = _map_w * _map_d
	_heights.resize(count)
	var scale: float = HEIGHT_RANGE / 255.0
	for i in count:
		_heights[i] = float(raw[i * stride]) * scale

	print("[CityGenerator] Карта высот: %dx%d, клетка %.3f м" % [_map_w, _map_d, _cell_size])
	return true


func _height_at(x: float, z: float) -> float:
	var col: int = clampi(int(round(x / _cell_size + float(_map_w - 1) * 0.5)), 0, _map_w - 1)
	var row: int = clampi(int(round(z / _cell_size + float(_map_d - 1) * 0.5)), 0, _map_d - 1)
	return _heights[row * _map_w + col] + TERRAIN_BASE_Y


## Уклон по широкой базе — см. «ЛОВУШКА УКЛОНА» в шапке.
func _slope_at(x: float, z: float) -> float:
	var d: float = float(SLOPE_BASELINE_CELLS) * _cell_size
	var dx: float = (_height_at(x + d, z) - _height_at(x - d, z)) / (2.0 * d)
	var dz: float = (_height_at(x, z + d) - _height_at(x, z - d)) / (2.0 * d)
	return rad_to_deg(atan(Vector2(dx, dz).length()))


func _is_buildable(x: float, z: float, max_slope: float) -> bool:
	if _height_at(x, z) < SEA_LEVEL + SHORE_MARGIN:
		return false
	return _slope_at(x, z) <= max_slope


## Самая высокая точка рядом с центром конуса — якорь всего города.
func _find_summit() -> Vector2:
	var best := MARUYAMA_CENTRE
	var best_h := -1.0
	var r := 0.0
	while r <= SUMMIT_SEARCH_RADIUS:
		var steps: int = maxi(8, int(r / 12.0))
		for i in steps:
			var a := TAU * float(i) / float(steps)
			var p: Vector2 = MARUYAMA_CENTRE + Vector2(cos(a), sin(a)) * r
			var h := _height_at(p.x, p.y)
			if h > best_h:
				best_h = h
				best = p
		r += 15.0
	return best


# ── Библиотека сцен ──────────────────────────────────────────────────────────

## Ключ: одинаковый габарит и одинаковая высота — одна пара сцен на всех, и
## StreamingSystems._packed_cache грузит её один раз. Иначе 151 башня стоила бы
## 302 файла.
func _library_key(p: Dictionary) -> String:
	var f: Vector2 = p["footprint"]
	return "twr_%dx%d_h%d" % [int(f.x), int(f.y), int(p["height"])]


func build_library(placements: Array[Dictionary]) -> Dictionary:
	var mat_content := load(MAT_CONTENT) as Material
	var mat_silhouette := load(MAT_SILHOUETTE) as Material
	if mat_content == null or mat_silhouette == null:
		push_error("[CityGenerator] не загрузились материалы greybox")
		return {}

	DirAccess.make_dir_recursive_absolute(CONTENT_DIR)
	DirAccess.make_dir_recursive_absolute(SILHOUETTE_DIR)

	var library := {}
	for p in placements:
		var key := _library_key(p)
		if library.has(key):
			continue
		var f: Vector2 = p["footprint"]
		var size := Vector3(f.x, p["height"], f.y)
		var content_path := "%s/%s.tscn" % [CONTENT_DIR, key]
		var sil_path := "%s/%s_silhouette.tscn" % [SILHOUETTE_DIR, key]
		if not _save_content(content_path, key, size, mat_content):
			continue
		if not _save_silhouette(sil_path, key, size, mat_silhouette):
			continue
		library[key] = {"content": content_path, "silhouette": sil_path}

	print("[CityGenerator] Библиотека: %d уникальных башен (%d сцен)"
			% [library.size(), library.size() * 2])
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
		push_error("[CityGenerator] pack() провалился для %s (%d)" % [path, err])
		root.free()
		return false
	err = ResourceSaver.save(packed, path)
	root.free()
	if err != OK:
		push_error("[CityGenerator] не сохранилась сцена %s (%d)" % [path, err])
		return false
	return true


# ── Маркеры в открытой сцене (только редактор) ───────────────────────────────

## Удаляет только маркеры генератора. Авторские — без префикса — не трогает.
func clear_generated_markers(container: Node3D) -> int:
	var removed := 0
	for child in container.get_children():
		if String(child.name).begins_with(MARKER_PREFIX):
			container.remove_child(child)
			child.free()
			removed += 1
	return removed


func write_markers(container: Node3D, scene_root: Node,
		placements: Array[Dictionary], library: Dictionary) -> int:
	var written := 0
	for p in placements:
		var key := _library_key(p)
		if not library.has(key):
			continue
		var paths: Dictionary = library[key]

		var marker := Node3D.new()
		marker.set_script(load(BLOCKBASE_SCRIPT_PATH))
		marker.name = "%s%s" % [MARKER_PREFIX, p["id"]]
		marker.set("id", p["id"])
		marker.set("block_name", key)
		marker.set("district", "A1")
		marker.set("scene_path", paths["content"])
		marker.set("silhouette_scene_path", paths["silhouette"])

		container.add_child(marker)
		marker.owner = scene_root
		marker.global_position = p["position"]

		## Визуал маркера — инстанс его силуэта: башню видно в редакторе, и
		## BlockBase берёт высоту из AABB этого меша.
		var sil := (load(paths["silhouette"]) as PackedScene).instantiate()
		sil.name = "SilhouettePreview"
		marker.add_child(sil)
		sil.owner = scene_root

		written += 1
	return written
