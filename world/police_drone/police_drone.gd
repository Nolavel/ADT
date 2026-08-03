extends RigidBody3D

# Состояния дрона
enum State { PATROL, CHASE }
var current_state = State.PATROL

# Настройки
@export var patrol_radius: float = 100.0 # Локальный радиус 100м (квадрат 200х200)
@export var hover_height: float = 10.0   # Высота полета
@export var patrol_speed: float = 5.0    # Скорость патруля
@export var chase_speed: float = 12.0    # Скорость преследования

# Внутренние переменные
var start_position: Vector3
var start_yaw: float = 0.0              # Начальный разворот дрона в радианах
var patrol_target: Vector3
var target_player: Node3D = null

# Ссылки на дочерние узлы
@onready var height_ray = $HeightRayCast
@onready var drone_mesh = $DroneMesh

func _ready():
	# Запоминаем начальную позицию и разворот по Y (Yaw)
	start_position = global_position
	start_yaw = global_rotation.y
	
	# Принудительно отключаем гравитацию через код для надежности
	gravity_scale = 0.0
	
	pick_new_patrol_point()
	print("[DRONE] Дрон запущен. Старт в: ", start_position)

func _physics_process(delta):
	check_territory()
	handle_height(delta)
	handle_movement(delta)
	handle_rotation(delta)

# --- ПРОВЕРКА ГРАНИЦ ТЕРРИТОРИИ (ЛОКАЛЬНО) ---
func check_territory():
	if current_state == State.CHASE and is_instance_valid(target_player):
		# Переводим глобальную позицию игрока в локальную систему дрона
		var rel_pos = target_player.global_position - start_position
		var local_pos = rel_pos.rotated(Vector3.UP, -start_yaw)
		
		# Проверяем, вышел ли игрок за локальный квадрат 200х200 (±100м)
		if abs(local_pos.x) > patrol_radius or abs(local_pos.z) > patrol_radius:
			print("[DRONE] Игрок вышел за пределы территории 200х200. Возврат к патрулю.")
			target_player = null
			current_state = State.PATROL
			pick_new_patrol_point()

# --- ВЫСОТА ПОЛЕТА ---
func handle_height(delta):
	var target_y = global_position.y
	
	if height_ray and height_ray.is_colliding():
		var ground_y = height_ray.get_collision_point().y
		target_y = ground_y + hover_height
	
	var height_diff = target_y - global_position.y
	linear_velocity.y = lerp(linear_velocity.y, height_diff * 2.0, delta * 5.0)

# --- ДВИЖЕНИЕ ---
func handle_movement(delta):
	var speed = chase_speed if current_state == State.CHASE else patrol_speed
	var dest = patrol_target
	
	if current_state == State.CHASE and is_instance_valid(target_player):
		dest = target_player.global_position
	
	# Проект цели на текущую высоту дрона
	var dest_horizontal = Vector3(dest.x, global_position.y, dest.z)
	var dist = global_position.distance_to(dest_horizontal)
	
	# Если при патруле долетели до точки — выбираем новую
	if current_state == State.PATROL and dist < 2.5:
		pick_new_patrol_point()
		
	var direction = Vector3.ZERO
	if dist > 0.5:
		direction = (dest_horizontal - global_position).normalized()
		
	# Плавное управление скоростью
	var desired_velocity = direction * speed
	linear_velocity.x = lerp(linear_velocity.x, desired_velocity.x, delta * 3.0)
	linear_velocity.z = lerp(linear_velocity.z, desired_velocity.z, delta * 3.0)

# --- ВРАЩЕНИЕ МЕША ---
func handle_rotation(delta):
	if not drone_mesh:
		return
		
	var dest = patrol_target
	if current_state == State.CHASE and is_instance_valid(target_player):
		dest = target_player.global_position
		
	var look_pos = Vector3(dest.x, drone_mesh.global_position.y, dest.z)
	
	if drone_mesh.global_position.distance_to(look_pos) > 0.2:
		var target_transform = drone_mesh.global_transform.looking_at(look_pos, Vector3.UP)
		drone_mesh.global_transform = drone_mesh.global_transform.interpolate_with(target_transform, delta * 5.0)

# --- ВЫБОР ТОЧКИ ПАТРУЛЯ (БЕЗОПАСНАЯ ЛОКАЛЬНАЯ МАТЕМАТИКА) ---
func pick_new_patrol_point():
	var local_x = randf_range(-patrol_radius, patrol_radius)
	var local_z = randf_range(-patrol_radius, patrol_radius)
	
	# Поворачиваем локальную точку согласно стартовому развороту дрона
	var local_offset = Vector3(local_x, 0, local_z).rotated(Vector3.UP, start_yaw)
	patrol_target = start_position + local_offset
	print("[DRONE] Новая точка патруля (мировая): ", patrol_target)

# --- СИГНАЛЫ ОБНАРУЖЕНИЯ ---
func _on_detection_zone_body_entered(body):
	# Проверяем оба варианта регистра (и Player, и player)
	if body.is_in_group("Player") or body.is_in_group("player"):
		print("[DRONE] ИГРОК ОБНАРУЖЕН! Начинаю преследование.")
		target_player = body
		current_state = State.CHASE

func _on_detection_zone_body_exited(body):
	if body == target_player:
		print("[DRONE] Игрок скрылся из зоны. Возвращаюсь к патрулированию.")
		target_player = null
		current_state = State.PATROL
		pick_new_patrol_point()
