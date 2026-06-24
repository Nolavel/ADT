# =============================================================================
# CameraSource.gd
# Прикрепить к Camera3D ноде внутри mapsource.tscn
# Имя ноды в сцене: CameraSource
#
# НАЗНАЧЕНИЕ:
#   Редакторская камера для сцены MapSource. Поведение аналогично камере
#   редактора Godot — свободное перемещение, зум скроллом, панорамирование.
#   Используется при расстановке небоскрёбов и работе со спавнером.
#
# УПРАВЛЕНИЕ:
#   WASD / Стрелки — перемещение в горизонтальной плоскости
#   Колесо мыши   — зум (приближение/удаление по Y)
#   ПКМ + движение — панорамирование (опционально, см. PAN_ENABLED)
#
#
# ЗУМ:
#   Диапазон 500–2000 единиц по Y.
#   500  = детальная работа (видно отдельные небоскрёбы)
#   2000 = обзор всего мира 2100×8600
#
# ОГРАНИЧЕНИЯ:
#   Камера не выходит за пределы WorldZone Area3D (2600×9200).
#   Небольшой отступ BOUNDS_PADDING не даёт камере вылететь за край.
#
# ПРОЕКЦИЯ:
#   Изометрический вид ~30° — rotation_degrees = (-30, -45, 0).
#   Это классический изо угол как в редакторах уровней.
# =============================================================================

extends Camera3D


# ── Параметры (можно менять в инспекторе) ────────────────────────────────────

@export_group("Movement")
## Базовая скорость перемещения камеры (юниты/сек)
@export var move_speed:    float = 800.0
## Множитель скорости при зажатом Shift
@export var fast_speed_multiplier: float = 3.0
## Плавность перемещения (lerp factor). 1.0 = мгновенно, 0.05 = очень плавно
@export var smooth_factor: float = 8.0

@export_group("Zoom")
## Минимальная высота камеры (детальный вид)
@export var zoom_min:   float = 500.0
## Максимальная высота камеры (обзор всего мира)
@export var zoom_max:   float = 2000.0
## Скорость зума за один тик колеса
@export var zoom_speed: float = 80.0
## Плавность зума
@export var zoom_smooth: float = 8.0

@export_group("Bounds")
## Отступ от края WorldZone — камера не подходит ближе этого значения к границе
@export var bounds_padding: float = 200.0

## Размеры WorldZone в XZ (должны совпадать с мешем в сцене).
## X = ширина 2600, Z = длина 9200. Origin WorldZone = (0, 0, 0).
@export var world_half_x: float = 1300.0   # 2600 / 2
@export var world_half_z: float = 4600.0   # 9200 / 2


# ── Внутреннее состояние ─────────────────────────────────────────────────────

## Целевая позиция к которой плавно двигаемся (lerp target)
var _target_pos:  Vector3

## Целевой зум (Y позиция камеры)
var _target_zoom: float = 900.0


# ── Жизненный цикл ───────────────────────────────────────────────────────────

func _ready() -> void:
	# Изометрический угол — стандарт для редакторов уровней
	# -30° по X = смотрим вниз под углом
	# -45° по Y = угол 45° в горизонтальной плоскости (классическое изо)
	rotation_degrees = Vector3(-30.0, -45.0, 0.0)

	# Стартовая позиция — центр мира на высоте 900
	position     = Vector3(0.0, 900.0, 0.0)
	_target_pos  = position
	_target_zoom = position.y

	print("[CameraSource] ✅ Ready at ", position)


func _process(delta: float) -> void:
	_handle_movement(delta)
	_handle_zoom(delta)


func _unhandled_input(event: InputEvent) -> void:
	# Зум колесом мыши
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_target_zoom = clamp(_target_zoom - zoom_speed, zoom_min, zoom_max)
			MOUSE_BUTTON_WHEEL_DOWN:
				_target_zoom = clamp(_target_zoom + zoom_speed, zoom_min, zoom_max)


# ── Движение ─────────────────────────────────────────────────────────────────

func _handle_movement(delta: float) -> void:
	# Вектор "вперёд" камеры спроецированный на горизонтальную плоскость.
	# Это направление в котором смотрит камера по XZ — именно туда движемся по W.
	var forward := -global_transform.basis.z
	var right   :=  global_transform.basis.x
	forward.y    = 0.0
	right.y      = 0.0
	forward      = forward.normalized()
	right        = right.normalized()

	var input := Vector3.ZERO

	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		input += forward
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		input -= forward
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		input += right
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		input -= right
	if Input.is_key_pressed(KEY_ESCAPE):
		get_tree().quit()

	if input == Vector3.ZERO:
		# Нет ввода — плавно догоняем текущий target (уже применён)
		position = position.lerp(_target_pos, smooth_factor * delta)
		return

	# Скорость
	var speed := move_speed

	_target_pos += input.normalized() * speed * delta

	# ── Клампинг по границам WorldZone ───────────────────────────────────────
	# Камера не выходит за пределы мира + отступ bounds_padding
	var limit_x := world_half_x - bounds_padding
	var limit_z := world_half_z - bounds_padding

	_target_pos.x = clamp(_target_pos.x, -limit_x, limit_x)
	_target_pos.z = clamp(_target_pos.z, -limit_z, limit_z)

	# Плавное движение к цели
	position = position.lerp(_target_pos, smooth_factor * delta)


func _handle_zoom(delta: float) -> void:
	# Плавно изменяем только Y — X и Z управляются movement
	var new_y: float = lerp(position.y, _target_zoom, zoom_smooth * delta)
	position.y = new_y
	# Синхронизируем target_pos.y чтобы movement не перетирал зум
	_target_pos.y = new_y
