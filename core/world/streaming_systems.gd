# =============================================================================
# StreamingSystems.gd — Autoload (singleton)
#
# Конвейер стриминга мира. Единственный владелец стримимого контента:
# всё инстанцирует в StreamContainer, world.gd о ячейках не знает.
#
# ЧТО ОН ТЕПЕРЬ ДЕЛАЕТ (переезд на остров, 2026-08-25). Раньше он делал
# управляемым мир на 9,6 км — радиусы были 1000/1200 именно поэтому. Остров
# в 3,5 км в поперечнике целиком помещается в памяти, и смысл конвейера
# сменился: он управляет ПОДМЕНОЙ ПУСТЫШКИ НА ЖИВОЙ КОНТЕНТ, а не размером
# мира. Отсюда и радиусы 400/500: они выбраны от числа башен, которые должны
# быть живыми вокруг игрока, а не от того, сколько мира влезает.
#
# ДВА КОЛЬЦА:
#   Ring 0 (силуэты) — создаются один раз в initialize() и живут до reset():
#     • 9 силуэтов плит земли (своя сцена на плиту, позиции из WorldSystems);
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
#         Кварталы — сквозные колонны на всю высоту, вертикальный фильтр для
#         них бессмыслен.
#   • Пока контент ячейки ACTIVE — корень её силуэта скрыт (visible=false),
#     одинаково для плит и кварталов. Видимость в Godot НЕ отключает физику:
#     коллизия силуэта живёт всегда.
#   • Скан — не чаще, чем раз в STREAM_CHECK_DISTANCE пройденного пути;
#     прокачка загрузок/инстансов (_pump) — каждый кадр.
#
# СТРАТ-СЛОЁВ БОЛЬШЕ НЕТ (переезд на остров, 2026-08-25). Квартал приходит
# из своей контент-сцены целиком; контракта имён "Layer" + страта, его
# InstancePlaceholder-конвейера и посегментного гашения силуэта не существует.
# Вертикальная детализация на острове задаётся рельефом, а не тремя полосами.
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

## BLOCK: радиусная метрика в XZ, метры. Остров ~3,5 км в поперечнике, шаг
## застройки ~100 м в кальдере — 400 м это порядка 25 активных башен вокруг
## игрока. Подбирается глазом: если пустышка подменяется контентом прямо в
## лицо — радиус мал.
const BLOCK_STREAM_RADIUS := 400.0
const BLOCK_UNLOAD_RADIUS := 500.0   # > STREAM: гистерезис границы 25 %

const STREAM_CHECK_DISTANCE := 50.0

## Максимум одновременных фоновых load_threaded_request.
const MAX_CONCURRENT_LOADS := 2

## Максимум instantiate()+add_child за кадр (ячейки и слои суммарно).
## Фоновая загрузка кадр не грузит — дорого именно инстанцирование.
const INSTANTIATION_BUDGET_PER_FRAME := 1

## Temporary debug instrumentation for tracking down streaming-related
## "ripple between blocks at max hover speed" — remove once diagnosed.
const DEBUG_QUEUE_PRINTS: bool = true


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
	var silhouette_path: String
	var state:           CellState = CellState.UNLOADED
	var queued_at:       int = 0     # Time.get_ticks_msec() when enqueued — debug latency tracking
	var failed:          bool = false # битый путь/ресурс — исключена навсегда
	var silhouette_node: Node3D = null
	var content_node:    Node3D = null


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


# ── Точки входа ───────────────────────────────────────────────────────────────

func _ready() -> void:
	print("[StreamingSystems] 🌐 Ready, waiting for initialization...")
	if DEBUG_LOG_TRANSITIONS:
		cell_state_changed.connect(_log_cell_transition)


func _log_cell_transition(cell_id: String, _cell_type: CellType,
		old_state: CellState, new_state: CellState) -> void:
	print("[Stream %8.2f] %-14s %s -> %s" % [Time.get_ticks_msec() * 0.001,
			cell_id, CellState.keys()[old_state], CellState.keys()[new_state]])


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

	# Якорь стриминга: пешком — игрок; в ховере — сам ховер (капсула игрока
	# на борту выключена и неподвижна, следить за ней бессмысленно).
	var anchor: Node3D = _player
	if is_instance_valid(PlayerState.current_hover):
		anchor = PlayerState.current_hover
	var player_pos: Vector3 = anchor.global_position
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
		cell.id              = WorldSystems.get_tile_id(coords)
		cell.type            = CellType.GROUND_TILE
		cell.position        = WorldSystems.get_tile_position(coords)
		cell.coords          = coords
		cell.content_path    = td.content_scene_path
		cell.silhouette_path = td.silhouette_scene_path
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
	for cell: StreamCell in _cells.values():
		var packed: PackedScene = null
		match cell.type:
			CellType.GROUND_TILE:
				packed = _load_tile_silhouette(cell)
			CellType.BLOCK:
				packed = _load_block_silhouette(cell.id)
		if packed == null:
			continue
		var sil := packed.instantiate() as Node3D
		sil.name = cell.id + "_silhouette"
		_stream_container.add_child(sil)
		sil.global_position  = cell.position
		cell.silhouette_node = sil


func _load_tile_silhouette(cell: StreamCell) -> PackedScene:
	if cell.silhouette_path.is_empty():
		push_error("[StreamingSystems] Ground tile %s has no silhouette"
				% cell.id)
		return null
	var packed := load(cell.silhouette_path) as PackedScene
	if packed == null:
		push_error("[StreamingSystems] Ground tile silhouette not found: "
				+ cell.silhouette_path)
	return packed


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
	var newly_queued := 0
	for cell: StreamCell in _cells.values():
		if cell.failed:
			continue
		if _is_in_load_range(cell, player_pos):
			if cell.state == CellState.UNLOADED:
				cell.queued_at = Time.get_ticks_msec()
				_queue.append(cell)
				_set_state(cell, CellState.QUEUED)
				newly_queued += 1
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

	if DEBUG_QUEUE_PRINTS and newly_queued > 0:
		print("[StreamingSystems][DEBUG] scan queued=%d queue_size=%d loads_in_flight=%d anchor_speed=%.2f"
				% [newly_queued, _queue.size(), _loads_in_flight, _get_anchor_speed()])


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
	if DEBUG_QUEUE_PRINTS and not _queue.is_empty() and _loads_in_flight >= MAX_CONCURRENT_LOADS:
		print("[StreamingSystems][DEBUG] SATURATED queue_size=%d" % _queue.size())

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

	# Силуэт гасится для плит И кварталов одинаково. До переезда на остров
	# квартал вместо этого гасил силуэт посегментно, по одному сегменту на
	# материализованный страт-слой; слоёв больше нет, гасить нечего — контент
	# приходит целиком, значит и силуэт уходит целиком.
	if is_instance_valid(cell.silhouette_node):
		cell.silhouette_node.visible = false   # физика силуэта продолжает жить

	_set_state(cell, CellState.ACTIVE)

	if DEBUG_QUEUE_PRINTS and cell.queued_at > 0:
		print("[StreamingSystems][DEBUG] activated %-14s latency=%dms queue_size=%d"
				% [cell.id, Time.get_ticks_msec() - cell.queued_at, _queue.size()])


func _unload_content(cell: StreamCell) -> void:
	if is_instance_valid(cell.content_node):
		cell.content_node.queue_free()
	cell.content_node = null

	if is_instance_valid(cell.silhouette_node):
		cell.silhouette_node.visible = true

	if cell.state != CellState.UNLOADED:
		_set_state(cell, CellState.UNLOADED)


# ── Утилиты ───────────────────────────────────────────────────────────────────

func _set_state(cell: StreamCell, new_state: CellState) -> void:
	var old := cell.state
	cell.state = new_state
	cell_state_changed.emit(cell.id, cell.type, old, new_state)


func _dist_xz(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))


## Debug-only: current speed of the streaming anchor (player or hover, same
## resolution as _process()). Returns 0.0 if the anchor exposes no velocity.
func _get_anchor_speed() -> float:
	var anchor: Node3D = _player
	if is_instance_valid(PlayerState.current_hover):
		anchor = PlayerState.current_hover
	if anchor is CharacterBody3D:
		return (anchor as CharacterBody3D).velocity.length()
	return 0.0
