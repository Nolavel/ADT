# =============================================================================
# World.gd
#
# СТРУКТУРА ДЕРЕВА (world.tscn):
#   World (Node3D)  ← этот скрипт
#   ├── StreamContainer  (Node3D)  ← башни от StreamingSystems
#   └── [CityZone создаётся программно через WorldBuilder]
#
# =============================================================================

extends Node3D

@onready var stream_container: Node3D = $StreamContainer
@export var allow_exit_with_escape: bool = true

func _ready() -> void:
	await get_tree().process_frame
	_init_world()


func _init_world() -> void:
	var world_data := _load_world_data()
	if world_data != null and world_data.city_zone != null:
		_build_city_zone(world_data.city_zone)

	if world_data != null and world_data.spawn_point != Vector3.ZERO:
		WorldSystems.spawn_point = world_data.spawn_point

	# Спавним игрока
	var player_scene := load("res://player/player.tscn") as PackedScene
	var player: Node3D = null
	if player_scene != null:
		player = player_scene.instantiate() as Node3D
		add_child(player)

		# 🔥 Спавним на 10м выше, чтобы не проваливаться сквозь ещё не прогруженный пол
		player.global_position += Vector3(0, 10.0, 0)

	# Спавним камеру
	var camera_follow_scene := load("res://cameras/camera_follow.tscn") as PackedScene
	var camera: Camera3D = null
	if camera_follow_scene != null:
		camera = camera_follow_scene.instantiate() as Camera3D
		add_child(camera)

	if player:
		var input_systems := get_node_or_null("InputSystems")
		if input_systems and input_systems.has_method("set_player_reference"):
			input_systems.set_player_reference(player)

		if camera and camera.has_method("set_target_reference"):
			camera.set_target_reference(player)
			camera.make_current()
			
		# World.gd, после camera.make_current()
		if input_systems and input_systems.has_method("set_camera_reference"):
			input_systems.set_camera_reference(camera)

		register_player(player)

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
