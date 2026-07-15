# =============================================================================
# StreamingSystems.gd — Autoload (singleton)
#
# Конвейер стриминга мира. Единственный владелец стримимого контента:
# всё инстанцирует в StreamContainer, world.gd о ячейках не знает.
#
# ДВА КОЛЬЦА:
#   Ring 0 (силуэты) — создаются один раз в initialize() и живут до reset():
#     • 9 силуэтов плит земли (одна общая сцена, позиции из WorldSystems);
#       несут ПОСТОЯННУЮ коллизию пола — страховочная поверхность.
#     • Силуэты кварталов (своя сцена на квартал).
#   Ring 1 (контент) — ячейки конвейера (плиты + кварталы), грузятся и
#     выгружаются по XZ-радиусу от игрока.
#
# ЖИЗНЕННЫЙ ЦИКЛ ЯЧЕЙКИ:
#   UNLOADED ─(вошла в зону загрузки своей метрики)→ QUEUED
#   QUEUED   ─(взята конвейером, load_threaded_request)→ LOADING
#   LOADING  ─(THREAD_LOAD_LOADED)→ READY
#   READY    ─(кадровый бюджет инстансов)→ ACTIVE
#   ACTIVE   ─(вышла за зону выгрузки)→ UNLOADED (queue_free контента)
#   Откат: QUEUED/READY при выходе за зону выгрузки возвращаются в UNLOADED
#   без инстанцирования (кэш threaded-загрузки остаётся тёплым).
#
# ПРАВИЛА:
#   • Две метрики дистанции — по типу ячейки:
#       GROUND_TILE — КОЛЬЦЕВАЯ по координатам сетки: плита загружена, если
#         расстояние Чебышёва до плиты игрока ≤ TILE_LOAD_RING; выгружается
#         при ≥ TILE_UNLOAD_RING. Гистерезис встроен в метрику (целая плита
#         зазора). Радиусная метрика тайлам не подходит: при радиусе меньше
#         полуплиты (1100) контент выгружается под ногами игрока.
#       BLOCK — радиусная в XZ (BLOCK_STREAM_RADIUS / BLOCK_UNLOAD_RADIUS).
#         Кварталы — сквозные колонны на всю GAMEPLAY_HEIGHT, вертикальный
#         фильтр для них бессмыслен; вертикальную детализацию дают страт-слои.
#   • Пока контент ячейки ACTIVE — корень её силуэта скрыт (visible=false).
#     Видимость в Godot НЕ отключает физику: коллизия силуэта живёт всегда.
#   • Скан — не чаще, чем раз в STREAM_CHECK_DISTANCE пройденного пути;
#     прокачка загрузок/инстансов (_pump) — каждый кадр.
#
# СТРАТ-СЛОИ (только кварталы):
#   Контент-сцена квартала обязана содержать ноды InstancePlaceholder с
#   именами "Layer" + имя страты из WorldSystems: LayerDoggerland,
#   LayerManifold, LayerGlare. Это КОНТРАКТ ИМЁН — нарушение даст warning.
#   Для ACTIVE-квартала материализован ровно один слой — текущая страта.
#   Материализация: get_instance_path() → load_threaded_request() →
#   create_instance(replace = false, custom_scene = packed).
#   replace = false обязателен: плейсхолдер остаётся в дереве, слой можно
#   выгружать (queue_free инстанса) и материализовывать повторно.
#   TODO(backlog): гистерезис по высоте на границе страт — сейчас не
#   воспроизводим (нет вертикального перемещения кроме дебаг-телепорта).
# =============================================================================

extends Node

# ── Настройки конвейера ───────────────────────────────────────────────────────

## true — все ячейки грузятся при initialize() без учёта радиуса.
## Отладочный режим; для демо стриминга ДОЛЖЕН быть false.
const DEBUG_LOAD_ALL := false

## Консольная трассировка переходов ячеек и слоёв — для сверки прогонов
## демо. Шумно; выключить после стабилизации стриминга.
const DEBUG_LOG_TRANSITIONS := true

## GROUND_TILE: кольцевая метрика по координатам сетки (Чебышёв).
const TILE_LOAD_RING   := 1   # текущая плита + соседи
const TILE_UNLOAD_RING := 2   # гистерезис — целая плита зазора

## BLOCK: радиусная метрика в XZ, метры.
const BLOCK_STREAM_RADIUS := 1000.0
const BLOCK_UNLOAD_RADIUS := 1200.0   # > STREAM: гистерезис границы

const STREAM_CHECK_DISTANCE := 50.0

## Максимум одновременных фоновых load_threaded_request.
const MAX_CONCURRENT_LOADS := 2

## Максимум instantiate()+add_child за кадр (ячейки и слои суммарно).
## Фоновая загрузка кадр не грузит — дорого именно инстанцирование.
const INSTANTIATION_BUDGET_PER_FRAME := 1


# ── Типы ──────────────────────────────────────────────────────────────────────

enum CellType { GROUND_TILE, BLOCK }
enum CellState { UNLOADED, QUEUED, LOADING, READY, ACTIVE }


## Одна ячейка конвейера (Ring 1) + ссылка на её силуэт (Ring 0).
class StreamCell:
	var id:              String
	var type:            CellType
	var position:        Vector3      # мировая позиция (низ/пол ячейки)
	var coords:          Vector2i     # координаты сетки — только GROUND_TILE
	var content_path:    String
	var state:           CellState = CellState.UNLOADED
	var failed:          bool = false # битый путь/ресурс — исключена навсегда
	var silhouette_node: Node3D = null
	var content_node:    Node3D = null
	# --- только кварталы ---
	var layer_instance:  Node = null  # материализованный слой текущей страты
	var layer_strata:    String = ""  # чья страта материализована
	var pending_strata:  String = ""  # слой в фоновой загрузке
	var pending_path:    String = ""


# ── Состояние ─────────────────────────────────────────────────────────────────

var _world_data:          WorldData
var _cells:               Dictionary = {}   # id: String -> StreamCell
var _queue:               Array[StreamCell] = []

## Кэш загруженных сцен: path -> PackedScene. Обязателен: ячейки ДЕЛЯТ
## контент-сцены (тайлы-шахматка), а load_threaded_get() потребляет задачу —
## без кэша вторая ячейка с тем же путём получила бы INVALID_RESOURCE.
## Бонус: повторный вход в радиус инстанцируется без фоновой загрузки.
## TODO(backlog): политика вытеснения кэша при росте числа сцен.
var _packed_cache:        Dictionary = {}
var _loads_in_flight:     int = 0
var _last_check_position: Vector3 = Vector3(INF, INF, INF)
var _stream_container:    Node3D = null
var _player:              Node3D = null
var _initialized:         bool = false


# ── Сигналы ───────────────────────────────────────────────────────────────────

signal initialized(cell_count: int)
signal cell_state_changed(cell_id: String, cell_type: CellType,
		old_state: CellState, new_state: CellState)
signal layer_changed(block_id: String, strata: String, loaded: bool)


# ── Точки входа ───────────────────────────────────────────────────────────────

func _ready() -> void:
	print("[StreamingSystems] 🌐 Ready, waiting for initialization...")
	if DEBUG_LOG_TRANSITIONS:
		cell_state_changed.connect(_log_cell_transition)
		layer_changed.connect(_log_layer_event)


func _log_cell_transition(cell_id: String, _cell_type: CellType,
		old_state: CellState, new_state: CellState) -> void:
	print("[Stream %8.2f] %-14s %s -> %s" % [Time.get_ticks_msec() * 0.001,
			cell_id, CellState.keys()[old_state], CellState.keys()[new_state]])


func _log_layer_event(block_id: String, strata: String, loaded: bool) -> void:
	print("[Stream %8.2f] %-14s layer %s %s" % [Time.get_ticks_msec() * 0.001,
			block_id, strata, "loaded" if loaded else "freed"])


func initialize(container: Node3D, player: Node3D) -> void:
	if player == null:
		push_error("[StreamingSystems] initialize() requires a player node")
		return

	_stream_container = container
	_player           = player

	if not _load_world_data(WorldSystems.world_data_path):
		push_error("[StreamingSystems] Failed to load world data")
		return

	_build_cells()
	_spawn_ring0()

	WorldSystems.strata_changed.connect(_on_strata_changed)

	_initialized = true
	initialized.emit(_cells.size())
	print("[StreamingSystems] Cells: %d (tiles + blocks)" % _cells.size())

	if DEBUG_LOAD_ALL:
		push_warning("[StreamingSystems] DEBUG_LOAD_ALL is ON — no streaming")
		for cell: StreamCell in _cells.values():
			_activate_immediately(cell)


func _process(_delta: float) -> void:
	if not _initialized or not is_instance_valid(_player):
		return

	var player_pos: Vector3 = _player.global_position
	WorldSystems.update_player_position(player_pos)

	if DEBUG_LOAD_ALL:
		return

	# Скан радиусов — дросселирован по пройденному пути.
	if player_pos.distance_to(_last_check_position) >= STREAM_CHECK_DISTANCE:
		_last_check_position = player_pos
		_scan(player_pos)

	# Прокачка конвейера — каждый кадр (фоновые загрузки идут и когда
	# игрок стоит на месте).
	_pump(player_pos)


func force_update() -> void:
	if _initialized and is_instance_valid(_player):
		_last_check_position = Vector3(INF, INF, INF)


func reset() -> void:
	if WorldSystems.strata_changed.is_connected(_on_strata_changed):
		WorldSystems.strata_changed.disconnect(_on_strata_changed)

	for cell: StreamCell in _cells.values():
		_unload_content(cell)
		if is_instance_valid(cell.silhouette_node):
			cell.silhouette_node.queue_free()

	_cells.clear()
	_queue.clear()
	_packed_cache.clear()
	_loads_in_flight     = 0
	_world_data          = null
	_player              = null
	_stream_container    = null
	_initialized         = false
	_last_check_position = Vector3(INF, INF, INF)
	print("[StreamingSystems] Reset")


## Снимок состояния для дебаг-панели. Только чтение.
func get_cells_snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for cell: StreamCell in _cells.values():
		result.append({
			"id":     cell.id,
			"type":   cell.type,
			"state":  cell.state,
			"strata": cell.layer_strata,
		})
	return result


# ── Данные и построение ячеек ─────────────────────────────────────────────────

func _load_world_data(path: String) -> bool:
	if not ResourceLoader.exists(path):
		push_error("[StreamingSystems] World data not found: " + path)
		return false

	_world_data = load(path) as WorldData
	if _world_data == null:
		push_error("[StreamingSystems] WorldData cast failed")
		return false

	print("[StreamingSystems] Data: %d tiles, %d blocks" % [
			_world_data.ground_tiles.size(), _world_data.blocks.size()])
	return true


func _build_cells() -> void:
	for td: GroundTileData in _world_data.ground_tiles:
		var coords := Vector2i(td.col, td.row)
		var cell := StreamCell.new()
		cell.id           = WorldSystems.get_tile_id(coords)
		cell.type         = CellType.GROUND_TILE
		cell.position     = WorldSystems.get_tile_position(coords)
		cell.coords       = coords
		cell.content_path = td.content_scene_path
		_register_cell(cell)

	for bd: BlockData in _world_data.blocks:
		var cell := StreamCell.new()
		cell.id           = bd.id
		cell.type         = CellType.BLOCK
		cell.position     = bd.position
		cell.content_path = bd.content_scene_path
		_register_cell(cell)


func _register_cell(cell: StreamCell) -> void:
	if _cells.has(cell.id):
		push_warning("[StreamingSystems] Duplicate cell id: " + cell.id)
		return
	if not ResourceLoader.exists(cell.content_path):
		push_warning("[StreamingSystems] Content scene not found for %s: %s"
				% [cell.id, cell.content_path])
		cell.failed = true
	_cells[cell.id] = cell


## Ring 0: силуэты создаются синхронно один раз и живут до reset().
func _spawn_ring0() -> void:
	var tile_sil := load(_world_data.ground_tile_silhouette_path) as PackedScene
	if tile_sil == null:
		push_error("[StreamingSystems] Ground tile silhouette not found: "
				+ _world_data.ground_tile_silhouette_path)

	for cell: StreamCell in _cells.values():
		var packed: PackedScene = null
		match cell.type:
			CellType.GROUND_TILE:
				packed = tile_sil
			CellType.BLOCK:
				packed = _load_block_silhouette(cell.id)
		if packed == null:
			continue
		var sil := packed.instantiate() as Node3D
		sil.name = cell.id + "_silhouette"
		_stream_container.add_child(sil)
		sil.global_position  = cell.position
		cell.silhouette_node = sil


func _load_block_silhouette(block_id: String) -> PackedScene:
	for bd: BlockData in _world_data.blocks:
		if bd.id != block_id:
			continue
		if bd.silhouette_scene_path.is_empty():
			push_warning("[StreamingSystems] Block %s has no silhouette"
					% block_id)
			return null
		return load(bd.silhouette_scene_path) as PackedScene
	return null


# ── Скан (по метрике типа ячейки) ─────────────────────────────────────────────

func _scan(player_pos: Vector3) -> void:
	for cell: StreamCell in _cells.values():
		if cell.failed:
			continue
		if _is_in_load_range(cell, player_pos):
			if cell.state == CellState.UNLOADED:
				_queue.append(cell)
				_set_state(cell, CellState.QUEUED)
		elif _is_out_of_range(cell, player_pos):
			match cell.state:
				CellState.QUEUED:
					_queue.erase(cell)
					_set_state(cell, CellState.UNLOADED)
				CellState.ACTIVE:
					_unload_content(cell)

	# Ближайшее — в голову очереди.
	_queue.sort_custom(func(a: StreamCell, b: StreamCell) -> bool:
		return _dist_xz(player_pos, a.position) < _dist_xz(player_pos, b.position))


func _is_in_load_range(cell: StreamCell, player_pos: Vector3) -> bool:
	match cell.type:
		CellType.GROUND_TILE:
			return _tile_ring(cell, player_pos) <= TILE_LOAD_RING
		_:
			return _dist_xz(player_pos, cell.position) <= BLOCK_STREAM_RADIUS


## Между load- и unload-порогом — зона гистерезиса: уже загруженное живёт,
## ещё не загруженное не стартует.
func _is_out_of_range(cell: StreamCell, player_pos: Vector3) -> bool:
	match cell.type:
		CellType.GROUND_TILE:
			return _tile_ring(cell, player_pos) >= TILE_UNLOAD_RING
		_:
			return _dist_xz(player_pos, cell.position) > BLOCK_UNLOAD_RADIUS


## Расстояние Чебышёва (в плитах) от плиты игрока до плиты ячейки.
func _tile_ring(cell: StreamCell, player_pos: Vector3) -> int:
	var player_tile := WorldSystems.get_tile_coords(player_pos)
	return maxi(absi(player_tile.x - cell.coords.x),
			absi(player_tile.y - cell.coords.y))


# ── Прокачка конвейера (каждый кадр) ─────────────────────────────────────────

func _pump(player_pos: Vector3) -> void:
	# 1. Старт фоновых загрузок из очереди (кэш-хит идёт сразу в READY).
	while not _queue.is_empty() and _loads_in_flight < MAX_CONCURRENT_LOADS:
		var cell: StreamCell = _queue.pop_front()
		if _packed_cache.has(cell.content_path):
			_set_state(cell, CellState.READY)
			continue
		ResourceLoader.load_threaded_request(cell.content_path)
		_loads_in_flight += 1
		_set_state(cell, CellState.LOADING)

	var budget := INSTANTIATION_BUDGET_PER_FRAME

	# 2. Опрос фоновых загрузок + инстанцирование готовых.
	for cell: StreamCell in _cells.values():
		match cell.state:
			CellState.LOADING:
				match ResourceLoader.load_threaded_get_status(cell.content_path):
					ResourceLoader.THREAD_LOAD_LOADED:
						_loads_in_flight -= 1
						_packed_cache[cell.content_path] = \
								ResourceLoader.load_threaded_get(cell.content_path)
						_set_state(cell, CellState.READY)
					ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
						# Задачу уже потребила другая ячейка с тем же путём.
						_loads_in_flight -= 1
						if _packed_cache.has(cell.content_path):
							_set_state(cell, CellState.READY)
						else:
							cell.failed = true
							push_warning("[StreamingSystems] Load failed: "
									+ cell.content_path)
							_set_state(cell, CellState.UNLOADED)
					ResourceLoader.THREAD_LOAD_FAILED:
						_loads_in_flight -= 1
						cell.failed = true
						push_warning("[StreamingSystems] Load failed: "
								+ cell.content_path)
						_set_state(cell, CellState.UNLOADED)
			CellState.READY:
				if _is_out_of_range(cell, player_pos):
					# Игрок уже ушёл — не инстанцируем (кэш остался тёплым).
					_set_state(cell, CellState.UNLOADED)
				elif budget > 0:
					budget -= 1
					_activate(cell)

	# 3. Материализация страт-слоёв (тот же кадровый бюджет).
	_pump_layers(budget)


func _activate(cell: StreamCell) -> void:
	var packed: PackedScene = _packed_cache.get(cell.content_path)
	if packed == null:
		cell.failed = true
		push_warning("[StreamingSystems] Packed cache miss: " + cell.content_path)
		_set_state(cell, CellState.UNLOADED)
		return
	_add_content(cell, packed)


## Путь DEBUG_LOAD_ALL: синхронная загрузка в обход конвейера.
func _activate_immediately(cell: StreamCell) -> void:
	if cell.failed:
		return
	var packed := load(cell.content_path) as PackedScene
	if packed != null:
		_add_content(cell, packed)


func _add_content(cell: StreamCell, packed: PackedScene) -> void:
	var instance := packed.instantiate() as Node3D
	instance.name = cell.id
	_stream_container.add_child(instance)
	instance.global_position = cell.position
	cell.content_node = instance

	if is_instance_valid(cell.silhouette_node):
		cell.silhouette_node.visible = false   # физика силуэта продолжает жить

	_set_state(cell, CellState.ACTIVE)

	if cell.type == CellType.BLOCK:
		_request_layer(cell, WorldSystems.current_strata)


func _unload_content(cell: StreamCell) -> void:
	if is_instance_valid(cell.content_node):
		cell.content_node.queue_free()   # слой-инстанс освобождается вместе с ним
	cell.content_node   = null
	cell.layer_instance = null
	cell.layer_strata   = ""
	cell.pending_strata = ""
	cell.pending_path   = ""

	if is_instance_valid(cell.silhouette_node):
		cell.silhouette_node.visible = true

	if cell.state != CellState.UNLOADED:
		_set_state(cell, CellState.UNLOADED)


# ── Страт-слои кварталов ──────────────────────────────────────────────────────

func _on_strata_changed(new_strata: String) -> void:
	for cell: StreamCell in _cells.values():
		if cell.type == CellType.BLOCK and cell.state == CellState.ACTIVE:
			_request_layer(cell, new_strata)


func _request_layer(cell: StreamCell, strata: String) -> void:
	if cell.layer_strata == strata or cell.pending_strata == strata:
		return

	# Слой прежней страты выгружаем сразу — плейсхолдер остаётся в дереве.
	if is_instance_valid(cell.layer_instance):
		cell.layer_instance.queue_free()
		layer_changed.emit(cell.id, cell.layer_strata, false)
	cell.layer_instance = null
	cell.layer_strata   = ""

	var placeholder := _find_layer_placeholder(cell, strata)
	if placeholder == null:
		return

	cell.pending_strata = strata
	cell.pending_path   = placeholder.get_instance_path()
	if not _packed_cache.has(cell.pending_path):
		ResourceLoader.load_threaded_request(cell.pending_path)


func _pump_layers(budget: int) -> void:
	for cell: StreamCell in _cells.values():
		if budget <= 0:
			return
		if cell.pending_strata.is_empty() or cell.state != CellState.ACTIVE:
			continue

		var packed: PackedScene = _packed_cache.get(cell.pending_path)
		if packed == null:
			match ResourceLoader.load_threaded_get_status(cell.pending_path):
				ResourceLoader.THREAD_LOAD_LOADED:
					packed = ResourceLoader.load_threaded_get(cell.pending_path) \
							as PackedScene
					_packed_cache[cell.pending_path] = packed
				ResourceLoader.THREAD_LOAD_FAILED, \
				ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
					push_warning("[StreamingSystems] Layer load failed: "
							+ cell.pending_path)
					cell.pending_strata = ""
					cell.pending_path   = ""
					continue
				_:
					continue   # ещё грузится

		budget -= 1
		var placeholder := _find_layer_placeholder(cell, cell.pending_strata)
		if placeholder != null:
			# replace = false: плейсхолдер живёт дальше, слой можно
			# выгрузить и материализовать снова.
			cell.layer_instance = placeholder.create_instance(false, packed)
			cell.layer_strata   = cell.pending_strata
			layer_changed.emit(cell.id, cell.layer_strata, true)
		cell.pending_strata = ""
		cell.pending_path   = ""


## Контракт имён: нода InstancePlaceholder в корне контент-сцены квартала
## называется "Layer" + имя страты (LayerDoggerland / LayerManifold / LayerGlare).
func _find_layer_placeholder(cell: StreamCell, strata: String) -> InstancePlaceholder:
	if not is_instance_valid(cell.content_node):
		return null
	var node := cell.content_node.get_node_or_null("Layer" + strata)
	if node == null or not node is InstancePlaceholder:
		push_warning("[StreamingSystems] Block %s: no InstancePlaceholder 'Layer%s'"
				% [cell.id, strata])
		return null
	return node


# ── Утилиты ───────────────────────────────────────────────────────────────────

func _set_state(cell: StreamCell, new_state: CellState) -> void:
	var old := cell.state
	cell.state = new_state
	cell_state_changed.emit(cell.id, cell.type, old, new_state)


func _dist_xz(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
