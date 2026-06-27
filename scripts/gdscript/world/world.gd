# =============================================================================
# World.gd
# Прикрепить к корневой ноде сцены world.tscn
#
# НАЗНАЧЕНИЕ:
#   Главная игровая сцена. Инициализирует игрока, передаёт координаты
#   спавна из GameManager, запускает StreamManager.
#
# ЧТО ДЕЛАЕТ:
#   - Спавнит игрока на координатах из GameManager.spawn_point
#   - Инициализирует StreamManager (передаёт контейнер + ссылку на игрока)
#   - Передаёт CameraMap ссылку на игрока для слежения
#   - Обновляет GameManager.game_state
#
# СТРУКТУРА ДЕРЕВА СЦЕНЫ (world.tscn):
#   World (Node3D)  ← этот скрипт
#   ├── WorldZone     (StaticBody3D) — физический пол 2600×9200, Y=0
#   ├── CityZone      (StaticBody3D) — пол небоскрёбов 2100×8600, Y=10
#   ├── STRATA_Doggerland  (Area3D)
#   ├── STRATA_Manifold    (Area3D)
#   ├── STRATA_Glare       (Area3D)
#   ├── District_Central   (Area3D)
#   ├── District_South     (Area3D)
#   ├── District_North     (Area3D)
#   ├── StreamContainer    (Node3D) ← сюда StreamManager добавляет небоскрёбы
#   ├── CameraMap      (Camera3D + CameraMap.gd, mode=FOLLOW)
#   └── PlayerSpawner  (Node3D)    ← сюда инстанцируем игрока
#
# ПОЧЕМУ СКЕЛЕТ ВСЕГДА В СЦЕНЕ:
#   WorldZone, CityZone и Area3D страт/районов — лёгкие ноды без контента.
#   Они должны быть всегда загружены потому что:
#   - WorldZone даёт физический пол (игрок не падает в пустоту)
#   - Area3D нужны StreamManager для определения что грузить
#   - Координаты из MapSource имеют смысл только если система координат совпадает
#
# ВАЖНО — ОДИНАКОВЫЕ КООРДИНАТЫ:
#   WorldZone и CityZone в world.tscn должны иметь те же позиции что
#   в mapsource.tscn. Иначе координаты спавна из MapSource не совпадут
#   с геометрией World. Рекомендуется вынести их в отдельную .tscn
#   и инстанцировать в обеих сценах.
# =============================================================================

extends Node3D


# ── Экспортируемые пути ──────────────────────────────────────────────────────

@export_group("Scene Paths")
## Путь к сцене игрока. Должна содержать CharacterBody3D.
#@export var player_scene_path: String = "res://scenes/player/Player.tscn"


# ── Ссылки на ноды ───────────────────────────────────────────────────────────

## Контейнер куда StreamManager добавляет загруженные небоскрёбы
@onready var stream_container: Node3D = $StreamContainer

## Точка где спавним игрока (позиция этой ноды игнорируется —
## используем GameManager.spawn_point)
#@onready var player_spawner: Node3D = $PlayerSpawner

## Камера слежения за игроком
#@onready var camera_map: Camera3D = $CameraMap


# ── Внутреннее состояние ─────────────────────────────────────────────────────

## Ссылка на заспавненного игрока
var _player: Node3D = null


# ── Жизненный цикл ───────────────────────────────────────────────────────────

func _ready() -> void:
	#GameManager.game_state = GameManager.GameState.LOADING
	#print("[World] 🌍 Loading world...")

	# Ждём один кадр — даём физике и Area3D инициализироваться
	await get_tree().process_frame

	#_spawn_player()
	_init_stream()
	#_init_camera()

	#GameManager.game_state = GameManager.GameState.PLAYING
	#print("[World] ✅ World ready. Player at: ", _player.global_position if _player else "N/A")


# ── Инициализация подсистем ───────────────────────────────────────────────────

#func _spawn_player() -> void:
	## Проверяем существует ли сцена игрока
	#if not ResourceLoader.exists(player_scene_path):
		#push_error("[World] ❌ Player scene not found: %s" % player_scene_path)
		## В прототипе создаём заглушку чтобы не крашиться
		#_player = _create_player_placeholder()
	#else:
		#var packed: PackedScene = load(player_scene_path)
		#_player = packed.instantiate()
#
	## Добавляем в сцену
	##player_spawner.add_child(_player)
#
	## Устанавливаем позицию из GameManager
	#var spawn_pos: Vector3 = GameManager.get_spawn_point()
	#_player.global_position = spawn_pos
#
	#print("[World] 👤 Player spawned at: ", spawn_pos)


func _init_stream() -> void:
	StreamManager.initialize(stream_container)
	print("[World] StreamManager initialized (DEBUG MODE)")
#
	## Передаём StreamManager контейнер и игрока
	#StreamManager.initialize(stream_container, _player)
	#print("[World] 🌐 StreamManager initialized")


#func _init_camera() -> void:
	#if not is_instance_valid(camera_map):
		#return
	#if not is_instance_valid(_player):
		#return
#
	## CameraMap.gd должен быть в режиме FOLLOW
	## Передаём ссылку на игрока
	#if camera_map.has_method("set_follow_target"):
		#camera_map.set_follow_target(_player)
		#print("[World] 📷 CameraMap following player")


# ── Заглушка игрока для прототипа ────────────────────────────────────────────
# Когда реальной сцены игрока ещё нет — создаём простую CharacterBody3D
# чтобы StreamManager имел за кем следить.

#func _create_player_placeholder() -> CharacterBody3D:
	#push_warning("[World] ⚠️ Using player placeholder (no Player.tscn found)")
#
	#var body := CharacterBody3D.new()
	#body.name = "PlayerPlaceholder"
#
	## Коллайдер
	#var col   := CollisionShape3D.new()
	#var shape := CapsuleShape3D.new()
	#shape.radius = 40.0
	#shape.height = 180.0
	#col.shape    = shape
	#body.add_child(col)
#
	## Визуал — простая капсула
	#var mesh_inst  := MeshInstance3D.new()
	#var capsule    := CapsuleMesh.new()
	#capsule.radius  = 40.0
	#capsule.height  = 180.0
	#mesh_inst.mesh  = capsule
#
	#var mat              := StandardMaterial3D.new()
	#mat.albedo_color      = Color(0.2, 0.8, 0.4)
	#mat.emission_enabled  = true
	#mat.emission          = Color(0.1, 0.5, 0.2)
	#mesh_inst.material_override = mat
	#body.add_child(mesh_inst)
#
	#return body
