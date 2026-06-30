extends CharacterBody3D

#СТРУКТУРА ДЕРЕВА СЦЕНЫ:
#   Player (CharacterBody3D)  ← этот скрипт
#   ├── PlayerCollision    (CollisionShape3D)
#   ├── PlayerComponents   (Node3D)
#   	├── MovementComponent
#   	├── InteractComponent
#   	├── AttributesComponent
#   	├── InventoryComponent
#   	├── EquipmentComponent
#   	├── WalletComponent
#   	├── HealthComponent
#   	├── StaminaComponent
#   	├── ReactionComponent
#   	├── SleepComponent
#   	├── HungerComponent
#   	├── SavePlayerComponent
#   	├── ProgressionComponent


# =============================================================================
# Player.gd  — FPS
# Прикрепить к CharacterBody3D в player.tscn
#
# СТРУКТУРА ДЕРЕВА (player.tscn):
#   Player (CharacterBody3D)   ← этот скрипт
#   ├── CollisionShape3D       (CapsuleShape3D, r=0.4, h=1.8)
#   └── Head (Node3D)          ← pivot для pitch камеры, Y = 1.6
#       └── Camera3D           ← сама камера (position = Vector3.ZERO)
#
# УПРАВЛЕНИЕ:
#   WASD          — движение
#   Мышь          — поворот / прицел (захват курсора по клику, Esc — отпустить)
#   Пробел        — прыжок
#   Shift         — ускорение
#
# СПАВН:
#   Читаем WorldSystems.spawn_point, встаём туда.
#   Регистрируем себя в World.gd → StreamingSystems знает позицию.
# =============================================================================



# ── Параметры движения ────────────────────────────────────────────────────────

@export_group("Movement")
@export var move_speed:        float = 12.0
@export var sprint_multiplier: float = 2.5
@export var jump_velocity:     float = 8.0
@export var acceleration:      float = 14.0
@export var friction:          float = 16.0

@export_group("Mouse Look")
@export var mouse_sensitivity: float = 0.15   # градусов на пиксель
@export var pitch_min:         float = -89.0
@export var pitch_max:         float =  89.0


# ── Ссылки на ноды ────────────────────────────────────────────────────────────

## Node3D на высоте глаз (~1.6 м) — вращается по X (pitch)
@onready var head:   Node3D   = $Head
## Camera3D — дочерняя к Head, position = Vector3.ZERO
@onready var camera: Camera3D = $Head/Camera3D


# ── Состояние ─────────────────────────────────────────────────────────────────

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _mouse_captured: bool = false


# ── Жизненный цикл ────────────────────────────────────────────────────────────

func _ready() -> void:
	# Спавн
	var spawn := WorldSystems.spawn_point
	spawn.y += 2.0          # чуть выше пола — не проваливаемся
	global_position = spawn
	print("[Player] Spawned at: ", global_position)

	# Захватываем курсор сразу
	_capture_mouse()

	# Регистрируемся в World после кадра (чтобы World._ready() уже отработал)
	await get_tree().process_frame
	var world := get_tree().get_first_node_in_group("world_root")
	if is_instance_valid(world) and world.has_method("register_player"):
		world.register_player(self)


func _unhandled_input(event: InputEvent) -> void:
	# Клик в окно → захватить мышь
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_capture_mouse()

	# Esc → отпустить мышь
	if event.is_action_pressed("ui_cancel"):
		_release_mouse()

	# Поворот камеры мышью
	if event is InputEventMouseMotion and _mouse_captured:
		# Yaw — вращаем сам CharacterBody3D по Y
		rotate_y(deg_to_rad(-event.relative.x * mouse_sensitivity))
		# Pitch — вращаем Head по X, зажимаем угол
		head.rotation_degrees.x = clampf(
			head.rotation_degrees.x - event.relative.y * mouse_sensitivity,
			pitch_min,
			pitch_max
		)


func _physics_process(delta: float) -> void:
	_apply_gravity(delta)
	_apply_movement(delta)
	move_and_slide()


# ── Физика ────────────────────────────────────────────────────────────────────

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta

	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = jump_velocity


func _apply_movement(delta: float) -> void:
	var input := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	# ui_up = W = вперёд, ui_down = S = назад
	# input.y отрицательный при W → умножаем на -1 чтобы forward был "вперёд"
	var wish_dir := (
		global_transform.basis.x * input.x +
		-global_transform.basis.z * (-input.y)
	).normalized()

	var speed := move_speed
	if Input.is_key_pressed(KEY_SHIFT):
		speed *= sprint_multiplier

	if wish_dir != Vector3.ZERO:
		velocity.x = move_toward(velocity.x, wish_dir.x * speed, acceleration * delta * speed)
		velocity.z = move_toward(velocity.z, wish_dir.z * speed, acceleration * delta * speed)
	else:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta * move_speed)
		velocity.z = move_toward(velocity.z, 0.0, friction * delta * move_speed)


# ── Мышь ──────────────────────────────────────────────────────────────────────

func _capture_mouse() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_mouse_captured = true

func _release_mouse() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_mouse_captured = false
