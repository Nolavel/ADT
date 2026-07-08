# =============================================================================
# World.gd
#
# СТРУКТУРА ДЕРЕВА (world.tscn):
#   World (Node3D)  ← этот скрипт
#   ├── StreamContainer  (Node3D)  ← башни от StreamingSystems
#   └── [CityZone создаётся программно через WorldBuilder]
#
# =============================================================================
#
# МЕХАНИЗМ ИНИЦИАЛИЗАЦИИ — читай перед тем как добавлять что-то новое.
#
# Три РАЗНЫЕ категории вещей, которые world.gd поднимает при старте — они
# намеренно НЕ объединены в одну абстракцию, потому что у них разная
# природа (как создаются) и разный родитель в дереве сцены:
#
#   1) WORLD_SYSTEM_SCRIPTS — Node-классы (ClickToMoveSystem, MenuSystem,
#      ...), создаются через .new(), родитель — World (self). Обычно без
#      визуального представления, чистая логика/оркестрация.
#
#   2) WORLD_3D_ENTITY_SCENES — самостоятельные 3D-сцены (.tscn),
#      создаются через load()+instantiate(), родитель — stream_container
#      (3D-пространство). Пример: HUDComponent (индикатор клика — это
#      Node3D, не screen-UI!). Сюда же в будущем — NPC/агенты, "голый"
#      3D-инвентарь без иконок и т.п.
#
#   3) WORLD_UI_SCENES — screen-space UI сцены (.tscn с Control в корне),
#      создаются через load()+instantiate(), родитель — отдельный общий
#      CanvasLayer (не stream_container, не World). Пока пусто — сюда
#      позже лягут инвентарь-с-иконками, статус-камера, крафтинг и т.д.
#
# Все три категории поддерживают один и тот же необязательный интерфейс:
# если у ноды/сцены есть метод on_world_ready(context: WorldContext),
# он будет вызван один раз после того как player/camera заспавнены и все
# WORLD_SYSTEM_SCRIPTS уже созданы (см. world_context.gd — там же
# context.get_system(SomeClass), если сцене нужна конкретная система,
# а не только player/camera/stream_container).
#
# Добавление нового элемента в любую из трёх категорий = ОДНА строка в
# соответствующем списке ниже + (опционально) один метод on_world_ready()
# в самом скрипте/сцене. _init_world() НЕ растёт с каждым новым элементом
# — весь код ниже это фиксированные циклы.
#
# ВАЖНО — что все три категории НЕ делают: они не про КОНТЕНТ мира (башни,
# City Zone, districts, подгрузка/выгрузка блоков по дистанции от игрока).
# Контентом занимается StreamingSystems (autoload,
# core/systems/streaming_systems.gd) — это отдельный, уже существующий и
# полностью независимый от этого механизма пайплайн. Всё, что описано
# здесь — исключительно про жизненный цикл ИГРОВЫХ СИСТЕМ и связанных с
# игроком сцен (инпут/движение/меню/HUD/будущий UI), а не про то, какие
# башни сейчас заспавнены в StreamContainer.
# =============================================================================

extends Node3D

## 1) Node-системы — .new(), родитель = World (self).
var WORLD_SYSTEM_SCRIPTS: Array[GDScript] = [
	ClickToMoveSystem,
	TPSMovementSystem,
	MenuSystem,
	ZoomRulerSystem,
]

## 2) Самостоятельные 3D-сцены — instantiate(), родитель = stream_container.
var WORLD_3D_ENTITY_SCENES: Array[PackedScene] = [
	preload("res://vfx/hud_component/hud_component.tscn"),
]

## 3) Screen-space UI сцены — instantiate(), родитель = общий CanvasLayer.
## Пока пусто — заполнится инвентарём/статус-камерой/крафтингом позже.
var WORLD_UI_SCENES: Array[PackedScene] = []

const UI_CANVAS_LAYER_INDEX: int = 40

@onready var stream_container: Node3D = $StreamContainer
@export var allow_exit_with_escape: bool = true

var _systems: Array[Node] = []


func _ready() -> void:
	await get_tree().process_frame
	_init_world()


func _init_world() -> void:
	# --- 1. Node-системы ---
	for system_script in WORLD_SYSTEM_SCRIPTS:
		var instance: Node = system_script.new()
		add_child(instance)
		_systems.append(instance)

	# --- Контент мира (WorldData/City Zone) — зона ответственности
	# StreamingSystems/WorldBuilder, не системы выше. ---
	var world_data := _load_world_data()
	if world_data != null and world_data.city_zone != null:
		_build_city_zone(world_data.city_zone)

	if world_data != null and world_data.spawn_point != Vector3.ZERO:
		WorldSystems.spawn_point = world_data.spawn_point

	# --- Игрок ---
	var player_scene := load("res://player/player.tscn") as PackedScene
	var player: Node3D = null
	if player_scene != null:
		player = player_scene.instantiate() as Node3D
		add_child(player)

		# 🔥 Спавним на 10м выше, чтобы не проваливаться сквозь ещё не прогруженный пол
		player.global_position += Vector3(0, 10.0, 0)

	# --- Камера ---
	var camera_follow_scene := load("res://camera/camera_follow.tscn") as PackedScene
	var camera: Camera3D = null
	if camera_follow_scene != null:
		camera = camera_follow_scene.instantiate() as Camera3D
		add_child(camera)

	if camera and player:
		camera.set_target_reference(player)
		camera.make_current()

	# --- Контекст, общий для всех трёх категорий ---
	var context := WorldContext.new()
	context.player = player
	context.camera = camera
	context.stream_container = stream_container
	context.systems = _systems

	for system in _systems:
		if system.has_method("on_world_ready"):
			system.on_world_ready(context)

	# --- 2. Самостоятельные 3D-сцены (родитель — stream_container) ---
	for scene in WORLD_3D_ENTITY_SCENES:
		var instance: Node = scene.instantiate()
		stream_container.add_child(instance)
		if instance.has_method("on_world_ready"):
			instance.on_world_ready(context)

	# --- 3. Screen-space UI сцены (родитель — общий CanvasLayer) ---
	if WORLD_UI_SCENES.size() > 0:
		var ui_canvas := CanvasLayer.new()
		ui_canvas.layer = UI_CANVAS_LAYER_INDEX
		get_tree().root.call_deferred("add_child", ui_canvas)

		for scene in WORLD_UI_SCENES:
			var instance: Node = scene.instantiate()
			ui_canvas.call_deferred("add_child", instance)
			if instance.has_method("on_world_ready"):
				instance.on_world_ready(context)

	StreamingSystems.initialize(stream_container)

	print("[World] ✅ Initialized")


func _load_world_data() -> WorldData:
	var path := WorldSystems.world_data_path
	if not ResourceLoader.exists(path):
		push_error("[World] WorldData not found: " + path)
		return null
	return load(path) as WorldData


## Создаём CityZone программно из CityZoneData.
## Результат идентичен тому что в mapsource.tscn — никакого ручного дублирования.
func _build_city_zone(cz: CityZoneData) -> void:
	var root := StaticBody3D.new()
	root.name = "CityZone"
	add_child(root)
	root.position = cz.position

	# 🔥 Обязательно: слой земли + группа "floor",
	# иначе клик-рейкаст в InputSystems его не увидит
	root.collision_layer = 3          # слой 2 (floor)
	root.collision_mask  = 3
	root.add_to_group("floor")

	var mesh_inst := MeshInstance3D.new()
	var box_mesh  := BoxMesh.new()
	box_mesh.size  = cz.size
	mesh_inst.mesh = box_mesh
	var mat               := StandardMaterial3D.new()
	mat.albedo_color       = cz.debug_color
	mesh_inst.set_surface_override_material(0, mat)
	root.add_child(mesh_inst)

	var cs        := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = cz.size
	cs.shape       = box_shape
	root.add_child(cs)

	print("[World] CityZone built: size=%s  pos=%s" % [cz.size, cz.position])
	
func _unhandled_input(event: InputEvent) -> void:
	if not allow_exit_with_escape:
		return

	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()
