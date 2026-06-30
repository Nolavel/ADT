# =============================================================================
# World.gd
# Прикрепить к корневой ноде сцены world.tscn
#
# СТРУКТУРА ДЕРЕВА (world.tscn):
#   World (Node3D)  ← этот скрипт
#   ├── StreamContainer  (Node3D)  ← башни от StreamingSystems
#   ├── PlayerSpawn      (Marker3D) ← опционально, для дебага
#   └── [CityZone создаётся программно через WorldBuilder]
#
# ВАЖНО:
#   CityZone больше не хардкодится в сцене — она создаётся WorldBuilder'ом
#   из данных CityZoneData в WorldData.tres. Это гарантирует что геометрия
#   world.tscn всегда совпадает с mapsource.tscn.
# =============================================================================

extends Node3D

@onready var stream_container: Node3D = $StreamContainer
@export var allow_exit_with_escape: bool = true

func _ready() -> void:
	# Ждём кадр — все @onready ссылки гарантированно готовы
	await get_tree().process_frame
	_init_world()


func _init_world() -> void:
	var world_data := _load_world_data()
	if world_data != null and world_data.city_zone != null:
		_build_city_zone(world_data.city_zone)
		
	if world_data != null and world_data.spawn_point != Vector3.ZERO:
		WorldSystems.spawn_point = world_data.spawn_point
	
	# Спавним игрока
	var player_scene := load("res://scenes/_player/_player.tscn") as PackedScene
	if player_scene != null:
		var player := player_scene.instantiate() as Node3D
		add_child(player)
		# global_position ставит сам Player._ready() из WorldSystems.spawn_point
	
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
	add_child(root)                    # сначала в дерево
	root.position = cz.position        # потом позиция (локальная = глобальная т.к. World в origin)
	
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

## Вызывается из Player.gd после его спавна чтобы передать ссылку в стриминг.
func register_player(player: Node3D) -> void:
	StreamingSystems._player = player
	StreamingSystems.force_update()
	print("[World] Player registered in StreamingSystems")
	
func _unhandled_input(event: InputEvent) -> void:
	if not allow_exit_with_escape:
		return

	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()
