# =============================================================================
# StreamManager.gd
# Autoload / Singleton — добавить в Project > Project Settings > Autoload
# Имя ноды: StreamManager
# =============================================================================

extends Node

const STREAM_RADIUS:          float = 1000.0
const UNLOAD_RADIUS:          float = 1200.0
const STREAM_CHECK_DISTANCE:  float = 50.0
const STREAM_RADIUS_VERTICAL: float = 800.0

var _world_data:           Dictionary = {}
var _loaded_ids:           Dictionary = {}
var _last_check_position:  Vector3    = Vector3(INF, INF, INF)
var _stream_container:     Node3D     = null
var _player:               Node3D     = null
var _initialized:          bool       = false

signal skyscraper_loaded(sc_id: String)
signal skyscraper_unloaded(sc_id: String)
signal initialized(skyscraper_count: int)


func _ready() -> void:
	print("[StreamManager] 🌐 Ready, waiting for initialization...")


func _process(_delta: float) -> void:
	if not _initialized:
		return
	if not is_instance_valid(_player):
		return

	var player_pos: Vector3 = _player.global_position
	GameManager.update_player_position(player_pos)

	var dist_since_check: float = player_pos.distance_to(_last_check_position)
	if dist_since_check >= STREAM_CHECK_DISTANCE:
		_last_check_position = player_pos
		_update_stream(player_pos)


func initialize(container: Node3D, player: Node3D = null) -> void:
	_stream_container = container
	_player = player

	var ok := _load_world_data(GameManager.world_data_path)
	if not ok:
		push_error("[StreamManager] Failed to load world data")
		return

	_initialized = true

	print("[StreamManager] Loaded %d skyscrapers" % _world_data.size())

	# ===== ВРЕМЕННЫЙ ДЕБАГ =====
	for sc_id in _world_data.keys():
		_load_skyscraper(sc_id)


func force_update() -> void:
	if _initialized and is_instance_valid(_player):
		_last_check_position = Vector3(INF, INF, INF)


func reset() -> void:
	_unload_all()
	_world_data.clear()
	_loaded_ids.clear()
	_player           = null
	_stream_container = null
	_initialized      = false
	print("[StreamManager] 🔄 Reset complete")


func _load_world_data(path: String) -> bool:
	print("--------------------------------")
	print("Loading file:", path)
	print("Exists:", FileAccess.file_exists(path))
	if not FileAccess.file_exists(path):
		push_warning("[StreamManager] ⚠️ World data file not found: %s" % path)
		_world_data = {}
		return true

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false

	var json_string: String = file.get_as_text()
	print(json_string)
	file.close()

	var json: JSON = JSON.new()
	var err: int   = json.parse(json_string)
	if err != OK:
		push_error("[StreamManager] ❌ JSON parse error: %s" % json.get_error_message())
		return false

	var raw = json.data
	print("JSON type:", typeof(raw))
	print(raw)
	if raw is Array:
		for entry in raw:
			if entry is Dictionary and entry.has("id"):
				_world_data[entry["id"]] = entry
	elif raw is Dictionary and raw.has("skyscrapers"):
		for entry in raw["skyscrapers"]:
			if entry is Dictionary and entry.has("id"):
				_world_data[entry["id"]] = entry

	return true


func _update_stream(player_pos: Vector3) -> void:
	var to_load:   Array[String] = []
	var to_unload: Array[String] = []

	# ── Что загрузить ────────────────────────────────────────────────────────
	for sc_id in _world_data:
		var data: Dictionary = _world_data[sc_id]
		var sc_pos: Vector3  = _vec3_from_array(data.get("position", [0.0, 0.0, 0.0]))

		# Строка 232 / 234 — было: var in_range := (выражение с Variant)
		# Фикс: явная типизация bool
		var dist_xz: float = Vector2(player_pos.x, player_pos.z).distance_to(
				Vector2(sc_pos.x, sc_pos.z))
		var dist_y: float  = abs(player_pos.y - sc_pos.y)
		var in_range: bool = dist_xz <= STREAM_RADIUS and dist_y <= STREAM_RADIUS_VERTICAL

		if in_range and not _loaded_ids.has(sc_id):
			to_load.append(sc_id)

	# ── Что выгрузить ────────────────────────────────────────────────────────
	for sc_id in _loaded_ids:
		var data: Dictionary = _world_data.get(sc_id, {})
		if data.is_empty():
			to_unload.append(sc_id)
			continue

		var sc_pos: Vector3  = _vec3_from_array(data.get("position", [0.0, 0.0, 0.0]))

		# Строка 249 — то же самое, dist_xz был Variant
		# Фикс: явная типизация float
		var dist_xz: float = Vector2(player_pos.x, player_pos.z).distance_to(
				Vector2(sc_pos.x, sc_pos.z))
		var dist_y: float  = abs(player_pos.y - sc_pos.y)

		if dist_xz > UNLOAD_RADIUS or dist_y > STREAM_RADIUS_VERTICAL * 1.2:
			to_unload.append(sc_id)

	for sc_id in to_unload:
		_unload_skyscraper(sc_id)
	for sc_id in to_load:
		_load_skyscraper(sc_id)


func _load_skyscraper(sc_id: String) -> void:
	var data: Dictionary = _world_data.get(sc_id, {})
	if data.is_empty():
		return

	var scene_path: String = data.get("scene_path", "")
	if scene_path.is_empty():
		return

	if not ResourceLoader.exists(scene_path):
		push_warning("[StreamManager] ⚠️ Scene not found: %s" % scene_path)
		return

	var packed: PackedScene = load(scene_path)
	if packed == null:
		return

	var instance: Node3D   = packed.instantiate()
	instance.name          = sc_id
	instance.global_position = _vec3_from_array(data.get("position", [0.0, 0.0, 0.0]))
	print("Spawned at:", instance.global_position)
	print("========================================")

	_stream_container.add_child(instance)
	_loaded_ids[sc_id] = instance
	skyscraper_loaded.emit(sc_id)
	print("")
	print("========================================")
	print("Loading skyscraper:", sc_id)


func _unload_skyscraper(sc_id: String) -> void:
	if not _loaded_ids.has(sc_id):
		return
	var node: Node3D = _loaded_ids[sc_id]
	if is_instance_valid(node):
		node.queue_free()
	_loaded_ids.erase(sc_id)
	skyscraper_unloaded.emit(sc_id)


func _unload_all() -> void:
	for sc_id in _loaded_ids.keys():
		_unload_skyscraper(sc_id)


## Конвертирует Array [x, y, z] → Vector3.
## JSON не знает типов Godot, позиции хранятся как массивы.
func _vec3_from_array(arr: Array) -> Vector3:
	if arr.size() < 3:
		return Vector3.ZERO
	return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
