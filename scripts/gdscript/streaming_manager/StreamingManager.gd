extends Node3D
class_name StreamingManager

# Сигналы для UI
signal deck_changed(deck_name: String)
signal chunk_changed(chunk_name: String)

@onready var deck_container = $".."
@onready var player = $"../Player"
@onready var lift = $"../Lift/LIFT"
@onready var zone_deck_a: Area3D = $"../COMMAND_DECK_A"
@onready var zone_deck_b: Area3D = $"../DROP_DECK_B"

@export_group("Chunk Zones")
@export var chunks_deck_a: Array[Area3D] = []
@export var chunks_deck_b: Array[Area3D] = []

@onready var deck_a_res = preload("res://scenes/starship_scene/deck_a.tscn")
@onready var deck_b_res = preload("res://scenes/starship_scene/deck_b.tscn")

# Ссылки на инстансы декков
var deck_a_instance: Node = null
var deck_b_instance: Node = null

# Сохраненные позиции и трансформы декков
var deck_a_transform: Transform3D
var deck_b_transform: Transform3D

var current_deck: String = ""
var current_chunk: String = ""
var is_loading: bool = false

# Словарь для хранения визуальных нод чанков {chunk_name: Node3D}
var chunk_nodes: Dictionary = {}

# 🔥 НОВОЕ: Кэшируем только меши {chunk_name: [MeshInstance3D]}
var chunk_meshes: Dictionary = {}

# Целевая прозрачность для каждого чанка {chunk_name: target_alpha}
var chunk_target_alpha: Dictionary = {}

# Текущая прозрачность {chunk_name: current_alpha}
var chunk_current_alpha: Dictionary = {}

# 🔥 НОВОЕ: Оригинальные материалы {mesh: {surface_idx: material}}
var mesh_original_materials: Dictionary = {}

# Скорость изменения прозрачности
const CHUNK_FADE_SPEED: float = 4.0
var chunk_transition_timer: float = 0.0
const CHUNK_TRANSITION_DELAY: float = 0.1 # 100ms защита от дребезга

func _ready() -> void:
	lift.connect("player_moved_between_decks", Callable(self, "_on_player_moved_between_decks"))
	zone_deck_a.body_entered.connect(_on_deck_a_entered)
	zone_deck_b.body_entered.connect(_on_deck_b_entered)
	
	# Подключаем все чанки
	_connect_chunk_zones()
	
	# Найти существующие деки в сцене и сохранить их трансформы
	_find_existing_decks()
	
	# Удалить все деки при старте
	_unload_all_decks()
	
	# Определить стартовую позицию игрока (с задержкой)
	await get_tree().process_frame
	_check_initial_player_position()

func _process(delta: float):
	# 🔥 Пропускаем кадры для оптимизации (каждый 2-й кадр)
	if Engine.get_process_frames() % 2 != 0:
		return
	
	# Плавная анимация прозрачности чанков
	var updated_count = 0
	for chunk_name in chunk_meshes.keys():
		if not chunk_target_alpha.has(chunk_name):
			continue
		
		var current = chunk_current_alpha.get(chunk_name, 1.0)
		var target = chunk_target_alpha[chunk_name]
		
		# 🔥 ЗАЩИТА: Если уже достигли цели - пропускаем
		if abs(current - target) <= 0.005: # Увеличен порог для оптимизации
			if current != target:
				chunk_current_alpha[chunk_name] = target
				_set_chunk_alpha(chunk_name, target)
			continue
		
		# Плавное изменение
		current = lerp(current, target, delta * CHUNK_FADE_SPEED)
		chunk_current_alpha[chunk_name] = current
		_set_chunk_alpha(chunk_name, current)
		updated_count += 1

func _connect_chunk_zones():
	# Подключаем все чанки Deck A
	for chunk in chunks_deck_a:
		if chunk and chunk is Area3D:
			chunk.body_entered.connect(_on_chunk_entered.bind(chunk))
			chunk.body_exited.connect(_on_chunk_exited.bind(chunk))
	
	# Подключаем все чанки Deck B
	for chunk in chunks_deck_b:
		if chunk and chunk is Area3D:
			chunk.body_entered.connect(_on_chunk_entered.bind(chunk))
			chunk.body_exited.connect(_on_chunk_exited.bind(chunk))
	
	print("Подключено чанков: A=", chunks_deck_a.size(), " B=", chunks_deck_b.size())

func _on_chunk_entered(body: Node, chunk: Area3D):
	if body.name != "Player":
		return
	
	# 🔥 Защита от "дребезга" при быстром входе/выходе
	chunk_transition_timer = CHUNK_TRANSITION_DELAY
	current_chunk = chunk.name
	chunk_changed.emit(chunk.name)
	print("✅ Игрок вошёл в чанк: %s" % chunk.name)
	_update_chunk_visibility(chunk.name)

func _on_chunk_exited(body: Node, chunk: Area3D):
	if body.name != "Player":
		return
	
	# 🔥 КРИТИЧНО: Проверяем валидность перед await
	if not is_instance_valid(self) or not is_inside_tree():
		return
	
	# 🔥 Ждём обновления физики
	await get_tree().process_frame
	
	# 🔥 Повторная проверка после await (узел мог быть удалён)
	if not is_instance_valid(self) or not is_inside_tree():
		return
	
	var all_chunks = chunks_deck_a + chunks_deck_b
	var found_new_chunk = false
	
	for other_chunk in all_chunks:
		if not other_chunk or other_chunk == chunk:
			continue
		if not is_instance_valid(other_chunk):
			continue
		
		var overlapping = other_chunk.get_overlapping_bodies()
		if player in overlapping:
			found_new_chunk = true
			print("🔄 Игрок перешёл из %s в %s" % [chunk.name, other_chunk.name])
			break
	
	# 🔥 Только если игрок ДЕЙСТВИТЕЛЬНО вышел из всех чанков
	if not found_new_chunk:
		current_chunk = ""
		chunk_changed.emit("")
		print("🚶 Игрок вышел из всех чанков")
		_update_chunk_visibility("")

func _find_existing_decks():
	# Ищем уже загруженные деки по имени или пути
	for child in deck_container.get_children():
		if child is Node3D:
			if child.name.contains("deck_a") or child.scene_file_path == "res://scenes/starship_scene/deck_a.tscn":
				deck_a_instance = child
				deck_a_transform = child.transform
				print("Deck A найден на позиции: ", child.position)
			elif child.name.contains("deck_b") or child.scene_file_path == "res://scenes/starship_scene/deck_b.tscn":
				deck_b_instance = child
				deck_b_transform = child.transform
				print("Deck B найден на позиции: ", child.position)

func _find_chunk_nodes():
	"""Ищет Node3D чанков и кэширует их меши"""
	chunk_nodes.clear()
	chunk_meshes.clear()
	mesh_original_materials.clear()
	
	var all_chunk_areas = chunks_deck_a + chunks_deck_b
	
	for deck_instance in [deck_a_instance, deck_b_instance]:
		if deck_instance == null or not is_instance_valid(deck_instance):
			continue
		
		for chunk_area in all_chunk_areas:
			if chunk_area == null:
				continue
			
			var chunk_name = chunk_area.name
			var chunk_node = _find_node_by_name(deck_instance, chunk_name)
			
			if chunk_node:
				chunk_nodes[chunk_name] = chunk_node
				chunk_current_alpha[chunk_name] = 1.0
				chunk_target_alpha[chunk_name] = 1.0
				
				# 🔥 КЭШИРУЕМ ВСЕ МЕШИ СРАЗУ
				var meshes = _collect_meshes(chunk_node)
				chunk_meshes[chunk_name] = meshes
				print("✅ Найден визуальный чанк: %s (мешей: %d)" % [chunk_name, meshes.size()])

func _collect_meshes(node: Node) -> Array[MeshInstance3D]:
	"""Собирает все MeshInstance3D из узла (один раз при загрузке)"""
	var meshes: Array[MeshInstance3D] = []
	
	if node is MeshInstance3D:
		meshes.append(node)
		
		# 🔥 Сразу дублируем и сохраняем материалы
		for surface_idx in range(node.get_surface_override_material_count()):
			var material = node.get_surface_override_material(surface_idx)
			if material == null:
				var base_mat = node.get_active_material(surface_idx)
				if base_mat and base_mat is StandardMaterial3D:
					material = base_mat.duplicate()
					node.set_surface_override_material(surface_idx, material)
					material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			
			# Сохраняем оригинальный материал
			if material and material is StandardMaterial3D:
				if not mesh_original_materials.has(node):
					mesh_original_materials[node] = {}
				mesh_original_materials[node][surface_idx] = material
	
	# Рекурсия только здесь, при загрузке!
	for child in node.get_children():
		meshes.append_array(_collect_meshes(child))
	
	return meshes

func _find_node_by_name(parent: Node, target_name: String) -> Node3D:
	"""Рекурсивный поиск Node3D по имени"""
	if parent.name == target_name and parent is Node3D:
		return parent
	
	for child in parent.get_children():
		var result = _find_node_by_name(child, target_name)
		if result:
			return result
	
	return null

func _update_chunk_visibility(active_chunk_name: String):
	"""Плавно меняет прозрачность чанков (БЕЗ багов)"""
	# 🔥 Если игрок ВНЕ всех чанков - ВСЕ видимы
	if active_chunk_name == "":
		for chunk_name in chunk_meshes.keys():
			chunk_target_alpha[chunk_name] = 1.0
		print("🌍 Игрок вне чанков - все видимы (alpha=1.0)")
		return
	
	# 🔥 Если игрок В чанке - только он видимый
	for chunk_name in chunk_meshes.keys():
		if chunk_name == active_chunk_name:
			chunk_target_alpha[chunk_name] = 1.0
			print("👁️ Активный чанк: %s (alpha=1.0)" % chunk_name)
		else:
			chunk_target_alpha[chunk_name] = 0.15 # Почти невидимы
			print("🌫️ Скрываем чанк: %s (alpha=0.15)" % chunk_name)

func _set_chunk_alpha(chunk_name: String, alpha: float):
	"""Устанавливает прозрачность ТОЛЬКО для мешей чанка"""
	if not chunk_meshes.has(chunk_name):
		return
	
	var meshes = chunk_meshes[chunk_name]
	for mesh in meshes:
		if not is_instance_valid(mesh) or not mesh_original_materials.has(mesh):
			continue
		
		# Меняем только альфу, материалы уже готовы
		for surface_idx in mesh_original_materials[mesh].keys():
			var material = mesh_original_materials[mesh][surface_idx]
			if material and material is StandardMaterial3D:
				material.albedo_color.a = alpha

func _check_initial_player_position():
	# Проверяем, в какой зоне находится игрок при старте
	var overlapping_bodies_a = zone_deck_a.get_overlapping_bodies()
	var overlapping_bodies_b = zone_deck_b.get_overlapping_bodies()
	
	if player in overlapping_bodies_a:
		await _load_deck("DECK_A")
	elif player in overlapping_bodies_b:
		await _load_deck("DECK_B")
	else:
		# По умолчанию загружаем Deck B
		await _load_deck("DECK_B")
	
	# Проверяем начальный чанк
	_check_initial_chunk()

func _check_initial_chunk():
	var all_chunks = chunks_deck_a + chunks_deck_b
	
	for chunk in all_chunks:
		if chunk:
			var overlapping = chunk.get_overlapping_bodies()
			if player in overlapping:
				current_chunk = chunk.name
				chunk_changed.emit(chunk.name)
				_update_chunk_visibility(chunk.name)
				print("Начальный чанк: ", chunk.name)
				break

func _unload_all_decks():
	_unload_deck(deck_a_instance)
	deck_a_instance = null
	_unload_deck(deck_b_instance)
	deck_b_instance = null

func _load_deck(deck_name: String):
	if is_loading:
		print("Загрузка уже в процессе, ожидание...")
		return
	
	if current_deck == deck_name:
		return # Уже загружен
	
	is_loading = true
	current_deck = deck_name
	
	# Отправляем сигнал об изменении дека
	deck_changed.emit(deck_name)
	
	match deck_name:
		"DECK_A":
			_unload_deck(deck_b_instance)
			deck_b_instance = null
			await get_tree().process_frame
			await _ensure_deck_loaded("A")
		"DECK_B":
			_unload_deck(deck_a_instance)
			deck_a_instance = null
			await get_tree().process_frame
			await _ensure_deck_loaded("B")
	
	is_loading = false
	print("Загрузка завершена: ", deck_name)

func _ensure_deck_loaded(deck_letter: String):
	match deck_letter:
		"A":
			if deck_a_instance == null:
				deck_a_instance = deck_a_res.instantiate()
				deck_container.add_child(deck_a_instance)
				# Восстанавливаем трансформ
				if deck_a_instance is Node3D:
					deck_a_instance.transform = deck_a_transform
				print("Deck A загружен на позиции: ", deck_a_instance.position)
			
			await get_tree().process_frame
			_find_chunk_nodes()
			
			# 🔥 ПОКАЗЫВАЕМ ТОЛЬКО ТЕКУЩИЙ
			if current_chunk != "":
				_update_chunk_visibility(current_chunk)
			else:
				_update_chunk_visibility("")
		
		"B":
			if deck_b_instance == null:
				deck_b_instance = deck_b_res.instantiate()
				deck_container.add_child(deck_b_instance)
				# Восстанавливаем трансформ
				if deck_b_instance is Node3D:
					deck_b_instance.transform = deck_b_transform
				print("Deck B загружен на позиции: ", deck_b_instance.position)
			
			await get_tree().process_frame
			_find_chunk_nodes()
			
			# 🔥 ПОКАЗЫВАЕМ ТОЛЬКО ТЕКУЩИЙ
			if current_chunk != "":
				_update_chunk_visibility(current_chunk)
			else:
				_update_chunk_visibility("")

func _hide_all_chunks():
	"""Устанавливает начальную видимость (ВСЕ ВИДИМЫ по умолчанию)"""
	for chunk_name in chunk_meshes.keys():
		chunk_target_alpha[chunk_name] = 1.0
		chunk_current_alpha[chunk_name] = 1.0
		_set_chunk_alpha(chunk_name, 1.0)
	print("✅ Инициализация: все чанки видимы (alpha=1.0)")

func _unload_deck(instance: Node):
	if instance != null and is_instance_valid(instance):
		print("Выгружаем дек: ", instance.name)
		instance.queue_free()

func _on_deck_a_entered(body):
	if body.name == "Player" and not is_loading:
		_load_deck("DECK_A")

func _on_deck_b_entered(body):
	if body.name == "Player" and not is_loading:
		_load_deck("DECK_B")

func _on_player_moved_between_decks(from_deck: String, to_deck: String):
	print("Игрок переместился с ", from_deck, " на ", to_deck)
	# Здесь можно добавить дополнительную логику при необходимости
