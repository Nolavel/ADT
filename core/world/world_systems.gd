# =============================================================================
# WorldSystems.gd — Autoload (singleton)
#
# Центральная шина состояния игры. Хранит всё что должно пережить смену сцен:
# точку спавна, текущую страту/район, путь к данным мира.
# =============================================================================

extends Node

# ── Константы мира ────────────────────────────────────────────────────────────

const WORLD_ZONE_SIZE    := Vector2(9600.0, 9600.0)
const CITY_ZONE_SIZE     := Vector2(6600.0, 6600.0)
const CITY_ZONE_Y        := 10.0
const GAMEPLAY_HEIGHT    := 3200.0

const STRATA_DOGGERLAND  := Vector2(0.0,    1000.0)
const STRATA_MANIFOLD    := Vector2(1000.0,  2000.0)
const STRATA_GLARE       := Vector2(2000.0, 3200.0)

const DISTRICT_A1        := Vector2(0.0,    1600.0)
const DISTRICT_A2        := Vector2(2000.0, 6000.0)
const DISTRICT_A3        := Vector2(6000.0, 8600.0)


# ── Данные сессии ─────────────────────────────────────────────────────────────

var spawn_point: Vector3 = Vector3(0.0, CITY_ZONE_Y + 2.0, 200.0)

var world_data_path: String = "res://data/world_data.tres"

var current_strata:   String = "Doggerland"
var current_district: String = ""
var current_tower_id: String = ""   # был current_sc_id


# ── Сигналы ───────────────────────────────────────────────────────────────────

signal strata_changed(new_strata: String)
signal district_changed(new_district: String)
signal spawn_point_updated(point: Vector3)


# ── Методы ───────────────────────────────────────────────────────────────────

func set_spawn_point(point: Vector3) -> void:
	spawn_point = point
	emit_signal("spawn_point_updated", point)
	print("[WorldSystems] Spawn point: ", point)


func set_current_strata(strata: String) -> void:
	if strata == current_strata:
		return
	current_strata = strata
	emit_signal("strata_changed", strata)
	print("[WorldSystems] Strata: ", strata)


func set_current_district(district: String) -> void:
	if district == current_district:
		return
	current_district = district
	emit_signal("district_changed", district)
	print("[WorldSystems] District: ", district)


## Вызывается StreamingSystems каждый кадр с позицией игрока.
## Обновляет текущую страту.
func update_player_position(pos: Vector3) -> void:
	var height_above_city := pos.y - CITY_ZONE_Y
	var strata := get_strata_by_height(height_above_city)
	set_current_strata(strata)


func get_strata_by_height(height_above_city: float) -> String:
	if height_above_city < STRATA_MANIFOLD.x:
		return "Doggerland"
	elif height_above_city < STRATA_GLARE.x:
		return "Manifold"
	else:
		return "Glare"
