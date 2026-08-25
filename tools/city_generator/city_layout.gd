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

const TOTAL_TOWERS: int = 151

## Главная башня. 800 на вершине конуса (~220 м) = макушка на 1020 при потолке
## мира 1250 — запас есть, доминанта читается.
const LANDMARK_HEIGHT: float = 800.0

## Первое кольцо вокруг главной башни — свита. Выше остального города, ниже
## доминанты: именно этот перепад и делает центр центром.
const INNER_RING_MIN: float = 300.0
const INNER_RING_MAX: float = 500.0

## Все остальные кольца.
const HEIGHT_MIN: float = 200.0
const HEIGHT_MAX: float = 400.0

## Высоты округляются до этого шага, чтобы библиотека сцен была конечной.
## 20 при диапазоне 200 даёт 11 корзин — столько же ступеней на метр, сколько
## давали 25 при прежнем диапазоне 500.
const HEIGHT_STEP: float = 20.0


# ── Кольца и лучи ────────────────────────────────────────────────────────────
#
# Схема радиально-кольцевая, а не манхэттенская: концентрические окружности от
# главной башни плюс лучевые проспекты насквозь.
#
# ЧИТАЕМОСТЬ ДЕРЖИТСЯ НА РАЗНИЦЕ ДВУХ ПРОСВЕТОВ, и это единственное, чем её
# здесь можно сделать: развернуть башню по касательной к кольцу нельзя —
# BlockData не хранит поворот, а map_source.export_data() пишет только
# global_position, так что поворот маркера умрёт при экспорте.
#
#   вдоль радиуса:  RING_STEP - footprint = 110 - 48 = 62 м — кольцевая дуга
#   вдоль кольца:   ARC_SPACING - footprint = 70 - 48 = 22 м — проулок
#
# Разница почти втрое: широкая дуга читается магистралью, узкая щель — щелью.
# Сблизишь числа — оба просвета станут одинаковыми и город снова превратится в
# однородную россыпь.

const RING_START_RADIUS: float = 140.0
const RING_STEP: float = 110.0
const ARC_SPACING: float = 70.0
const RING_FOOTPRINT: Vector2 = Vector2(48.0, 48.0)

## Докуда кольца растут, даже если башни ещё не набраны. 12 колец от 140 с
## шагом 110 — это радиус 1350, то есть весь остров.
const MAX_RINGS: int = 12

## Лучевые проспекты. Луч задан УГЛОМ, а не номером слота: на разных кольцах
## разное число башен, и по номеру луч съезжал бы от кольца к кольцу вместо
## того, чтобы идти насквозь.
const SPOKE_COUNT: int = 6
const SPOKE_HALF_ARC: float = 34.0

## Потолок угловой ширины луча, в долях сектора между лучами.
## Постоянная ширина В МЕТРАХ у центра съедает почти половину окружности:
## на радиусе 140 шесть лучей по 34 м забирали 46% кольца, и свита вокруг
## главной башни выходила из пяти домов. Здесь луч у центра сужается до
## доли сектора, а дальше снова растёт метрами.
const SPOKE_MAX_SECTOR_SHARE: float = 0.22

## Разброс высоты внутри пояса, чтобы кольцо не читалось забором одной высоты.
const HEIGHT_JITTER: float = 40.0


# ── Пригодность земли ────────────────────────────────────────────────────────

const SEA_LEVEL: float = 45.0
const SHORE_MARGIN: float = 12.0

## 25°, а не 20: склоны Маруямы держатся в 20–25°, и при 20 даунтаун на конус
## просто не влезает.
const MAX_SLOPE_CORE: float = 28.0
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
			LANDMARK_HEIGHT, RING_FOOTPRINT))
	placements.append_array(_place_rings(summit, placements))

	print("[CityGenerator] Всего башен: %d" % placements.size())
	_report_heights(placements)
	_report_inner_ring(placements, summit)
	return placements


## Концентрические кольца от главной башни наружу, с лучевыми проспектами
## насквозь.
##
## Слотов на кольце столько, чтобы шаг вдоль дуги держался около ARC_SPACING:
## иначе дальние кольца разрежались бы, и город растворялся к краю вместо того,
## чтобы обрываться там, где кончается земля.
##
## Непригодный слот остаётся ПУСТЫМ, а не подменяется соседним. Подмена — ровно
## то, из-за чего первая версия рассыпалась в конфетти: ряды съезжали и ни один
## просвет не проходил насквозь.
func _place_rings(centre: Vector2, existing: Array[Dictionary]) -> Array[Dictionary]:
	var taken: Array[Dictionary] = []
	var min_gap: float = RING_FOOTPRINT.x * 0.9
	var skipped_land: int = 0
	var skipped_spoke: int = 0

	for ring in range(1, MAX_RINGS + 1):
		if taken.size() >= TOTAL_TOWERS - 1:
			break
		var radius: float = RING_START_RADIUS + float(ring - 1) * RING_STEP
		var slots: int = maxi(6, int(round(TAU * radius / ARC_SPACING)))
		var on_ring: int = 0

		for slot in slots:
			if taken.size() >= TOTAL_TOWERS - 1:
				break
			var angle: float = TAU * float(slot) / float(slots)
			if _on_spoke(angle, radius):
				skipped_spoke += 1
				continue

			var pos: Vector2 = centre + Vector2(cos(angle), sin(angle)) * radius
			if not _is_buildable(pos.x, pos.y, MAX_SLOPE_CORE):
				skipped_land += 1
				continue
			if _too_close(existing, pos, min_gap) or _too_close(taken, pos, min_gap):
				skipped_land += 1
				continue

			var h: float
			if ring == 1:
				h = _rng.randf_range(INNER_RING_MIN, INNER_RING_MAX)
			else:
				h = _rng.randf_range(HEIGHT_MIN, HEIGHT_MAX)
			h = clampf(h + _rng.randf_range(-HEIGHT_JITTER, HEIGHT_JITTER),
					INNER_RING_MIN if ring == 1 else HEIGHT_MIN,
					INNER_RING_MAX if ring == 1 else HEIGHT_MAX)

			taken.append(_placement("cty_%03d" % (taken.size() + 1),
					pos.x, pos.y, h, RING_FOOTPRINT))
			on_ring += 1

		print("[CityGenerator]   кольцо %2d: r=%4.0f м, слотов %3d, поставлено %3d"
				% [ring, radius, slots, on_ring])

	print("[CityGenerator] Кольца: %d башен, срезано лучами %d, рельефом %d"
			% [taken.size(), skipped_spoke, skipped_land])
	if taken.size() < TOTAL_TOWERS - 1:
		print("[CityGenerator] ВНИМАНИЕ: недобрано %d — подними MAX_RINGS или MAX_SLOPE_CORE"
				% [TOTAL_TOWERS - 1 - taken.size()])
	return taken


## Попадает ли угол в один из лучевых проспектов.
##
## Полуширина задана В МЕТРАХ ПО ДУГЕ и переводится в угол на текущем радиусе:
## задай её в градусах — и у центра луч был бы щелью в пару метров, а у берега
## разъехался бы на просеку в полкилометра.
func _on_spoke(angle: float, radius: float) -> bool:
	if radius <= 0.001:
		return false
	var sector: float = TAU / float(SPOKE_COUNT)
	var half_angle: float = minf(SPOKE_HALF_ARC / radius,
			sector * SPOKE_MAX_SECTOR_SHARE)
	for i in SPOKE_COUNT:
		var spoke: float = TAU * float(i) / float(SPOKE_COUNT)
		var delta: float = absf(wrapf(angle - spoke, -PI, PI))
		if delta <= half_angle:
			return true
	return false


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


## Отдельная сводка по свите: она задана другим диапазоном, и если бы он
## разъехался с общим, на глаз это заметили бы позже всего.
func _report_inner_ring(placements: Array[Dictionary], centre: Vector2) -> void:
	var lo := 99999.0
	var hi := 0.0
	var n := 0
	for p in placements:
		var pos: Vector3 = p["position"]
		var d: float = Vector2(pos.x, pos.z).distance_to(centre)
		if d < RING_START_RADIUS + RING_STEP * 0.5 and p["id"] != "landmark":
			var h: float = p["height"]
			lo = minf(lo, h)
			hi = maxf(hi, h)
			n += 1
	if n > 0:
		print("[CityGenerator] Свита (кольцо 1): %d башен, %.0f..%.0f м" % [n, lo, hi])


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
