# =============================================================================
# StreamingSystems.gd
# Autoload / Singleton
# Имя ноды: StreamingSystems
# =============================================================================

extends Node

const STREAM_RADIUS:          float = 1000.0
const UNLOAD_RADIUS:          float = 1200.0
const STREAM_CHECK_DISTANCE:  float = 50.0
const STREAM_RADIUS_VERTICAL: float = 800.0

var _world_data:           WorldData
var _loaded_ids:           Dictionary = {}
var _last_check_position:  Vector3    = Vector3(INF, INF, INF)
var _stream_container:     Node3D     = null
var _player:               Node3D     = null
var _initialized:          bool       = false

signal tower_loaded(t_id: String)
signal tower_unloaded(t_id: String)
signal initialized(tower_count: int)


func _ready() -> void:
	print("[StreamingSystems] 🌐 Ready, waiting for initialization...")


func _process(_delta: float) -> void:
	if not _initialized:
		return
	if not is_instance_valid(_player):
		return

	var player_pos: Vector3 = _player.global_position
	WorldSystems.update_player_position(player_pos)

	var dist_since_check: float = player_pos.distance_to(_last_check_position)
	if dist_since_check >= STREAM_CHECK_DISTANCE:
		_last_check_position = player_pos
		_update_stream(player_pos)


func initialize(container: Node3D, player: Node3D = null) -> void:
	_stream_container = container
	_player           = player

	if not _load_world_data(WorldSystems.world_data_path):
		push_error("[StreamingSystems] Failed to load world data")
		return

	_initialized = true
	emit_signal("initialized", _world_data.towers.size())
	print("[StreamingSystems] Loaded %d towers" % _world_data.towers.size())

	# DEBUG: грузим все башни сразу без проверки радиуса
	for td: TowerData in _world_data.towers:
		_load_tower(td)


func force_update() -> void:
	if _initialized and is_instance_valid(_player):
		_last_check_position = Vector3(INF, INF, INF)


func reset() -> void:
	_unload_all()
	_world_data       = null
	_player           = null
	_stream_container = null
	_initialized      = false
	_loaded_ids.clear()
	print("[StreamingSystems] Reset")


func _load_world_data(path: String) -> bool:
	if not ResourceLoader.exists(path):
		push_error("[StreamingSystems] World data not found: " + path)
		return false

	_world_data = load(path) as WorldData

	if _world_data == null:
		push_error("[StreamingSystems] WorldData cast failed")
		return false

	print("[StreamingSystems] Towers in data: %d" % _world_data.towers.size())

	for td: TowerData in _world_data.towers:
		print("  Tower %s | pos=%s | h=%.0f | district=%s | scene=%s" % [
			td.id, td.position, td.height, td.district, td.scene_path
		])

	return true


func _update_stream(player_pos: Vector3) -> void:
	# ---------- Загрузка ----------
	for td: TowerData in _world_data.towers:
		var dist_xz := Vector2(player_pos.x, player_pos.z).distance_to(
			Vector2(td.position.x, td.position.z))
		var dist_y: float = abs(player_pos.y - td.position.y)

		if dist_xz <= STREAM_RADIUS \
		and dist_y <= STREAM_RADIUS_VERTICAL \
		and not _loaded_ids.has(td.id):
			_load_tower(td)

	# ---------- Выгрузка ----------
	var to_unload: Array[String] = []

	for t_id in _loaded_ids.keys():
		var td: TowerData = _find_tower_data(t_id)

		if td == null:
			to_unload.append(t_id)
			continue

		var dist_xz := Vector2(player_pos.x, player_pos.z).distance_to(
			Vector2(td.position.x, td.position.z))
		var dist_y: float = abs(player_pos.y - td.position.y)

		if dist_xz > UNLOAD_RADIUS or dist_y > STREAM_RADIUS_VERTICAL * 1.2:
			to_unload.append(t_id)

	for t_id in to_unload:
		_unload_tower(t_id)


func _find_tower_data(t_id: String) -> TowerData:
	for td: TowerData in _world_data.towers:
		if td.id == t_id:
			return td
	return null


func _load_tower(td: TowerData) -> void:
	if _loaded_ids.has(td.id):
		return

	if td.scene_path.is_empty():
		push_warning("[StreamingSystems] Empty scene_path for tower: " + td.id)
		return

	if not ResourceLoader.exists(td.scene_path):
		push_warning("[StreamingSystems] Scene not found: " + td.scene_path)
		return

	var packed := load(td.scene_path) as PackedScene
	if packed == null:
		push_warning("[StreamingSystems] Cannot load PackedScene: " + td.scene_path)
		return

	var instance := packed.instantiate() as Node3D
	instance.name            = td.id
	_stream_container.add_child(instance)
	instance.global_position = td.position


	_loaded_ids[td.id] = instance

	print("[StreamingSystems] Spawned: %s at %s" % [td.id, td.position])
	emit_signal("tower_loaded", td.id)


func _unload_tower(t_id: String) -> void:
	if not _loaded_ids.has(t_id):
		return
	var node: Node3D = _loaded_ids[t_id]
	if is_instance_valid(node):
		node.queue_free()
	_loaded_ids.erase(t_id)
	emit_signal("tower_unloaded", t_id)


func _unload_all() -> void:
	for t_id in _loaded_ids.keys():
		_unload_tower(t_id)
