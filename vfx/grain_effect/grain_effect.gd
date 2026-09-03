# =============================================================================
# grain_effect.gd — full-screen film grain, thinnest at the character.
#
# A ColorRect over the whole viewport driving vfx/shaders/grain_effect.gdshader.
# The shader reads SCREEN_TEXTURE and mixes noise into it by DISTANCE from the
# character's projected screen position: clear inside fade_radius, grain rising
# across fade_distance beyond it. So this file's whole runtime job is to keep
# telling the shader where the character is on screen, in UV.
#
# Lives in vfx/ rather than ui/hud/ because it states nothing. Everything in
# ui/hud/ reports a fact — rounds, stamina, stance, what F is pointing at — and
# is read. This is a look applied to the picture, and its shader already lives
# next door in vfx/shaders/.
#
# It was ui/hud/fade_by_distance/fade_by_distance.gd until 2026-09-03, and was
# referenced by nothing: no scene, no material, and a pause hookup waiting on a
# signal (fog_effect_toggled) that no node in this project has ever emitted. The
# name went too — the header of the file already called it "эффект зерна", and
# the shader beside it was already called grain_effect.
# =============================================================================
extends ColorRect

## The character the clear area follows. Set through on_world_ready(), not in
## the inspector: the player is instantiated at runtime by world.gd, so there is
## nothing for a scene to point at.
var player: Node3D

# Основные параметры эффекта
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

@onready var _material := material as ShaderMaterial    # Материал шейдера
var _prev_player_uv := Vector2(-1, -1)                 # Пред. позиция игрока (UV)
var _prev_enabled := true                              # Пред. состояние эффекта
var _camera: Camera3D                                  # Кэш камеры
var _is_paused := false                                # Флаг паузы
var _active_tween: Tween                               # Активный tween-аниматор

func _ready() -> void:
	# The pause transition is an animation ABOUT the pause, so it has to keep
	# running while the tree is paused — otherwise the tween below is frozen on
	# its first value and the effect simply snaps.
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	if _material:
		_update_static_params()        # Записываем параметры в шейдер
		_material.set_shader_parameter("fade_radius", 0.0)
		_material.set_shader_parameter("fade_distance", 1.0)
	else:
		push_warning("[GrainEffect] No ShaderMaterial on this ColorRect — nothing to drive")

	# PlayerState is the project's only source of truth about the pause (it sets
	# get_tree().paused itself, in open_menu()/close_menu()). The signal this
	# file used to wait for, fog_effect_toggled on some InputManager NodePath,
	# has never existed anywhere in the project.
	PlayerState.mode_changed.connect(_on_player_mode_changed)

	# 🔷️ Запуск анимации появления (fade-in) после задержки
	await get_tree().create_timer(fade_in_delay).timeout
	_animate_fade_in()


## Called once by world.gd after the player and camera exist — see
## WORLD_UI_SCENES in world/world.gd.
func on_world_ready(context: WorldContext) -> void:
	player = context.player


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

func _on_player_mode_changed(old_mode: PlayerState.Mode, new_mode: PlayerState.Mode) -> void:
	var paused := new_mode == PlayerState.Mode.MENU
	if paused == _is_paused:
		return
	if old_mode != PlayerState.Mode.MENU and not paused:
		return

	if paused:
		_animate_to_paused()
	else:
		_animate_to_unpaused()

	_is_paused = paused

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
