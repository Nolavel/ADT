# =============================================================================
# WorldSystems.gd — Autoload (singleton)
#
# Центральная шина состояния игры. Хранит всё, что должно пережить смену сцен:
# точку спавна, текущий район/тайл, путь к данным мира.
#
# Здесь же — единственный источник истины по геометрии мира:
#   • Конвенция высоты: уровень моря = Y 0, высота читается прямо с pos.y.
#     Страт как технической сущности больше нет (переезд на остров,
#     2026-08-25): высота = статус остаётся, но непрерывно, через рельеф.
#     Доггерленд / Манифолд / Глэйр живут только как разговорные имена
#     районов в диалогах и текстах — код о них не знает.
#   • Тайловая сетка земли: GROUND_GRID_SIZE плит по GROUND_TILE_SIZE метров.
#     CITY_ZONE_SIZE выводится из них и не хранится вторым числом.
#   • Координаты тайла everywhere = Vector2i(col, row):
#     .x = col (индекс по мировой оси X), .y = row (индекс по мировой оси Z).
#
# Никакой физики (Area3D и т.п.) — только чистая математика по позиции.
# =============================================================================

extends Node

# ── Константы мира ────────────────────────────────────────────────────────────

const WORLD_ZONE_SIZE    := Vector2(9600.0, 9600.0)

## Сторона одной плиты земли (квадрат), метры.
const GROUND_TILE_SIZE   := 2200.0

## Размерность сетки плит: (кол-во колонок по X, кол-во строк по Z).
const GROUND_GRID_SIZE   := Vector2i(3, 3)

## Габарит городской зоны — производная от сетки, не хардкод.
const CITY_ZONE_SIZE     := Vector2(
		GROUND_TILE_SIZE * GROUND_GRID_SIZE.x,
		GROUND_TILE_SIZE * GROUND_GRID_SIZE.y)

## Потолок игрового пространства над уровнем моря. 1000 м — решение
## островного ТЗ; самая высокая точка рельефа около 430 м, единственная
## смысловая башня достаёт до потолка.
const GAMEPLAY_HEIGHT    := 1000.0

const DISTRICT_A1        := Vector2(0.0,    1600.0)
const DISTRICT_A2        := Vector2(2000.0, 6000.0)
const DISTRICT_A3        := Vector2(6000.0, 8600.0)


# ── Данные сессии ─────────────────────────────────────────────────────────────

var spawn_point: Vector3 = Vector3(0.0, 2.0, 200.0)

var world_data_path: String = "res://data/world_data.tres"

var current_district: String = ""
var current_tower_id: String = ""

## Тайл, в котором находится игрок: Vector2i(col, row).
## (-1, -1) — позиция ещё не обновлялась либо игрок вне сетки.
var current_tile: Vector2i = Vector2i(-1, -1)


# ── Сигналы ───────────────────────────────────────────────────────────────────

signal district_changed(new_district: String)
signal spawn_point_updated(point: Vector3)
signal tile_changed(new_tile: Vector2i)


# ── Состояние сессии ──────────────────────────────────────────────────────────

func set_spawn_point(point: Vector3) -> void:
	spawn_point = point
	spawn_point_updated.emit(point)
	print("[WorldSystems] Spawn point: ", point)


func set_current_district(district: String) -> void:
	if district == current_district:
		return
	current_district = district
	district_changed.emit(district)
	print("[WorldSystems] District: ", district)


## Вызывается StreamingSystems каждый кадр с позицией игрока.
## Обновляет текущий тайл.
func update_player_position(pos: Vector3) -> void:
	var coords := get_tile_coords(pos)
	if coords != current_tile:
		current_tile = coords
		tile_changed.emit(coords)


# ── Математика тайловой сетки ─────────────────────────────────────────────────

## Каноничный id плиты. Формат согласован с данными и дебаг-панелью.
func get_tile_id(coords: Vector2i) -> String:
	return "gt_r%d_c%d" % [coords.y, coords.x]


## Мировая позиция плиты: центр её ВЕРХНЕЙ грани (пол = Y 0).
## Совпадает с origin-конвенцией сцен тайлов («нода стоит на полу»).
func get_tile_position(coords: Vector2i) -> Vector3:
	var half := CITY_ZONE_SIZE * 0.5
	return Vector3(
			-half.x + (coords.x + 0.5) * GROUND_TILE_SIZE,
			0.0,
			-half.y + (coords.y + 0.5) * GROUND_TILE_SIZE)


## Координаты тайла по мировой позиции. Может вернуть координаты ВНЕ сетки
## (игрок за пределами города) — при необходимости проверяй is_tile_inside_grid().
func get_tile_coords(pos: Vector3) -> Vector2i:
	var half := CITY_ZONE_SIZE * 0.5
	return Vector2i(
			int(floor((pos.x + half.x) / GROUND_TILE_SIZE)),
			int(floor((pos.z + half.y) / GROUND_TILE_SIZE)))


func is_tile_inside_grid(coords: Vector2i) -> bool:
	return coords.x >= 0 and coords.x < GROUND_GRID_SIZE.x \
			and coords.y >= 0 and coords.y < GROUND_GRID_SIZE.y
