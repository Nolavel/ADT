extends ColorRect

##============================================
## ✔️ Эффект зерна
## ============================================

# Основные параметры эффекта
@export var player: Node3D
@export var fade_radius: float = 400.0
@export var fade_distance: float = 400.0
@export var grain_intensity: float = 0.33
@export var grain_scale: float = 1.0
@export var time_speed: float = 0.05
@export var effect_enabled: bool = true

# Параметры анимации появления
@export_group("Fade In Animation")
@export var fade_in_delay: float = 1.5
@export var fade_in_duration: float = 2.0

# Параметры анимации паузы
@export_group("Pause Animation")
@export var pause_transition_duration: float = 0.8

# Референс на InputManager (NodePath)
@export_group("References")
@export var input_manager: NodePath

@onready var _material := material as ShaderMaterial    # Материал шейдера
var _prev_player_uv := Vector2(-1, -1)                 # Пред. позиция игрока (UV)
var _prev_enabled := true                              # Пред. состояние эффекта
var _camera: Camera3D                                  # Кэш камеры
var _is_paused := false                                # Флаг паузы
var _active_tween: Tween                               # Активный tween-аниматор
var _input_manager_node: Node3D                        # Кэш-узел InputManager

func _ready() -> void:
	if _material:
		_update_static_params()        # Записываем параметры в шейдер
		_material.set_shader_parameter("fade_radius", 0.0)
		_material.set_shader_parameter("fade_distance", 1.0)

	# 🔷️ Подключение сигнала из InputManager
	if input_manager:
		_input_manager_node = get_node(input_manager)
		if _input_manager_node and _input_manager_node.has_signal("fog_effect_toggled"):
			_input_manager_node.fog_effect_toggled.connect(_on_fog_effect_toggled)
		else:
			push_warning("⚠️ InputManager не найден или не имеет сигнала fog_effect_toggled")
	else:
		push_warning("⚠️ input_manager NodePath не задан!")

	# 🔷️ Запуск анимации появления (fade-in) после задержки
	await get_tree().create_timer(fade_in_delay).timeout
	_animate_fade_in()

## ============================================
## 🔵 PROCESS
## ============================================

func _process(_delta: float) -> void:
	# Проверяем player и материал
	if not player or not _material:
		return

	# Ленивая инициализация камеры 3D
	if not _camera:
		_camera = get_viewport().get_camera_3d()
	if not _camera:
		return

	# Трансляция позиции игрока из 3D в UV ColorRect (экран)
	var screen_pos_px := _camera.unproject_position(player.global_position)
	var local_px := screen_pos_px - global_position
	var player_uv := Vector2(local_px.x / size.x, local_px.y / size.y)

	# Обновление позиции игрока (только при изменении)
	if player_uv.distance_squared_to(_prev_player_uv) > 0.000004:
		_material.set_shader_parameter("player_screen_pos_uv", player_uv)
		_prev_player_uv = player_uv

	# Обновление включения/выключения эффекта
	if effect_enabled != _prev_enabled:
		_material.set_shader_parameter("effect_enabled", effect_enabled)
		_prev_enabled = effect_enabled

## ============================================
## 🔵 CALLBACK: ПАУЗА/ПЕРЕЗАПУСК ЭФФЕКТА ПО СИГНАЛУ
## ============================================

func _on_fog_effect_toggled(is_paused: bool) -> void:

	if is_paused:
		_animate_to_paused()
	else:
		_animate_to_unpaused()

	_is_paused = is_paused

## ============================================
## 🟦 АНИМАЦИИ: FADE-IN, PAUSE, UNPAUSE
## ============================================

func _animate_fade_in() -> void:
	if _active_tween:
		_active_tween.kill()

	_active_tween = create_tween()
	_active_tween.set_ease(Tween.EASE_OUT)
	_active_tween.set_trans(Tween.TRANS_CUBIC)
	_active_tween.set_parallel(true)

	_active_tween.tween_method(
		func(value: float): _material.set_shader_parameter("fade_radius", value),
		0.0,
		fade_radius,
		fade_in_duration
	)

	_active_tween.tween_method(
		func(value: float): _material.set_shader_parameter("fade_distance", value),
		1.0,
		fade_distance,
		fade_in_duration
	)

func _animate_to_paused() -> void:
	if _active_tween:
		_active_tween.kill()

	_active_tween = create_tween()
	_active_tween.set_ease(Tween.EASE_IN_OUT)
	_active_tween.set_trans(Tween.TRANS_CUBIC)
	_active_tween.set_parallel(true)

	# Убираем прозрачный круг (fade_radius → 0)
	_active_tween.tween_method(
		func(value: float): _material.set_shader_parameter("fade_radius", value),
		_material.get_shader_parameter("fade_radius"),
		0.0,
		pause_transition_duration
	)

	_active_tween.tween_method(
		func(value: float): _material.set_shader_parameter("fade_distance", value),
		_material.get_shader_parameter("fade_distance"),
		1.0,
		pause_transition_duration
	)

	# Замедляем время зерна
	_active_tween.tween_method(
		func(value: float): _material.set_shader_parameter("time_speed", value),
		time_speed,
		0.0,
		pause_transition_duration
	)


func _animate_to_unpaused() -> void:
	if _active_tween:
		_active_tween.kill()

	_active_tween = create_tween()
	_active_tween.set_ease(Tween.EASE_OUT)
	_active_tween.set_trans(Tween.TRANS_CUBIC)
	_active_tween.set_parallel(true)

	# Возвращаем прозрачный круг
	_active_tween.tween_method(
		func(value: float): _material.set_shader_parameter("fade_radius", value),
		_material.get_shader_parameter("fade_radius"),
		fade_radius,
		pause_transition_duration
	)

	_active_tween.tween_method(
		func(value: float): _material.set_shader_parameter("fade_distance", value),
		_material.get_shader_parameter("fade_distance"),
		fade_distance,
		pause_transition_duration
	)

	# Восстанавливаем время зерна
	_active_tween.tween_method(
		func(value: float): _material.set_shader_parameter("time_speed", value),
		0.0,
		time_speed,
		pause_transition_duration
	)

## ============================================
## 🟦 ОБНОВЛЕНИЕ СТАТИЧЕСКИХ ПАРАМЕТРОВ В МАТЕРИАЛ
## ============================================

func _update_static_params() -> void:
	if not _material:
		return
	_material.set_shader_parameter("viewport_size", get_viewport().get_visible_rect().size)
	_material.set_shader_parameter("grain_intensity", grain_intensity)
	_material.set_shader_parameter("grain_scale", grain_scale)
	_material.set_shader_parameter("time_speed", time_speed)

## ============================================
## 🟦 ПУБЛИЧНЫЕ ФУНКЦИИ (ОПЦИОНАЛЬНО)
## ============================================

func is_paused() -> bool:
	return _is_paused
