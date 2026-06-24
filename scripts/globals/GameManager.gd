# ╔══════════════════════════════════════════════════════════════════════════╗
# ║  GameManager.gd — Autoload (singleton)                                  ║
# ║                                                                          ║
# ║  ЗАЧЕМ:                                                                  ║
# ║    Центральная шина состояния игры. Хранит всё что должно               ║
# ║    пережить смену сцен: точку спавна, текущую страту/район,             ║
# ║    путь к файлу метаданных мира.                                         ║
# ║                                                                          ║
# ║  ПОЧЕМУ AUTOLOAD:                                                        ║
# ║    MapSource пишет сюда (spawn_point, world_data_path).                 ║
# ║    World читает отсюда при старте. Никакого прямого моста               ║
# ║    между сценами — только через этот синглтон.                           ║
# ║                                                                          ║
# ║  ИСПОЛЬЗОВАНИЕ:                                                          ║
# ║    GameManager.spawn_point = Vector3(...)   ← из Spawner.gd             ║
# ║    GameManager.spawn_point                  → из world.tscn             ║
# ╚══════════════════════════════════════════════════════════════════════════╝

extends Node

# ── 🌍 МИРОВЫЕ КОНСТАНТЫ ────────────────────────────────────────────────────
# Физические размеры зон — единый источник истины.
# Все скрипты берут размеры отсюда, не хардкодят сами.

const WORLD_ZONE_SIZE       := Vector2(2600.0, 9200.0)   # абсолютный пол мира (XZ)
const CITY_ZONE_SIZE        := Vector2(2100.0, 8600.0)   # пол небоскрёбов (XZ)
const CITY_ZONE_Y           := 10.0                      # высота CityZone над Y=0
const GAMEPLAY_HEIGHT       := 1700.0                    # полная высота игрового объёма

# Страты — нижняя и верхняя граница относительно CITY_ZONE_Y
const STRATA_DOGGERLAND     := Vector2(0.0,    500.0)
const STRATA_MANIFOLD       := Vector2(500.0,  1000.0)
const STRATA_GLARE          := Vector2(1000.0, 1700.0)

# Районы — диапазон по оси Z (длина) относительно начала CityZone
const DISTRICT_SOUTH        := Vector2(0.0,    2000.0)
const DISTRICT_CENTRAL      := Vector2(2000.0, 6000.0)
const DISTRICT_NORTH        := Vector2(6000.0, 8600.0)

# ── 📍 СПАВН ────────────────────────────────────────────────────────────────
# Записывается из Spawner.gd в MapSource.
# Читается Player-ом в world.tscn при _ready().

var spawn_point: Vector3 = Vector3(
	CITY_ZONE_SIZE.x / 2.0,   # центр по X
	CITY_ZONE_Y,               # на полу CityZone
	CITY_ZONE_SIZE.y / 2.0    # центр по Z
)

# ── 📁 ПУТЬ К ДАННЫМ МИРА ───────────────────────────────────────────────────
# MapSource.gd сохраняет экспорт сюда.
# StreamManager.gd загружает отсюда при старте World.

var world_data_path: String = "user://world_data.json"

# ── 🎮 СОСТОЯНИЕ СЕССИИ ─────────────────────────────────────────────────────
# Заполняется во время игры. StreamManager и другие системы
# обновляют эти значения — GameManager просто хранит.

var current_strata:   String = "Doggerland"
var current_district: String = ""
var current_sc_id:    String = ""

# ── 🔔 СИГНАЛЫ ──────────────────────────────────────────────────────────────
# World-сцена и UI подписываются на эти сигналы чтобы реагировать
# на смену страты/района без поллинга.

signal strata_changed(new_strata: String)
signal district_changed(new_district: String)
signal spawn_point_updated(point: Vector3)

# ── 🛠 МЕТОДЫ ────────────────────────────────────────────────────────────────

## Вызывается из Spawner.gd когда игрок поставил маркер в MapSource.
## Сохраняет точку и эмитит сигнал для любых слушателей.
func set_spawn_point(point: Vector3) -> void:
	spawn_point = point
	emit_signal("spawn_point_updated", point)
	print("[GameManager] Spawn point set: ", point)


## Вызывается из StreamManager когда игрок переходит в новую страту.
func set_current_strata(strata: String) -> void:
	if strata == current_strata:
		return
	current_strata = strata
	emit_signal("strata_changed", strata)
	print("[GameManager] Strata changed: ", strata)


## Вызывается из StreamManager когда игрок переходит в новый район.
func set_current_district(district: String) -> void:
	if district == current_district:
		return
	current_district = district
	emit_signal("district_changed", district)
	print("[GameManager] District changed: ", district)


## Утилита — возвращает название страты по высоте Y над CityZone.
## Используется в HUD и StreamManager.
func get_strata_by_height(height_above_city: float) -> String:
	if height_above_city < STRATA_MANIFOLD.x:
		return "Doggerland"
	elif height_above_city < STRATA_GLARE.x:
		return "Manifold"
	else:
		return "Glare"
