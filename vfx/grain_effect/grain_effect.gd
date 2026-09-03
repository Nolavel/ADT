# =============================================================================
# grain_effect.gd — full-screen film grain, thinnest at the character.
#
# A ColorRect over the whole viewport driving vfx/shaders/grain_effect.gdshader.
# The shader reads SCREEN_TEXTURE and mixes noise into it by DISTANCE FROM THE
# CENTRE OF THE FRAME: clear inside fade_radius, grain rising across
# fade_distance beyond it, both measured in fractions of the half-diagonal so
# 1.0 is the corner at any resolution. A vignette — grain in the corners and a
# little along the edges.
#
# It tracked the CHARACTER until 2026-09-03, unprojecting them every frame so
# the clear hole drove around the frame. That is why this file no longer needs a
# camera, a player reference or any per-frame unprojection.
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

# Основные параметры эффекта
## Clear out to here, as a FRACTION OF THE HALF-DIAGONAL — 1.0 is the corner.
## Not pixels: see the shader's own comment for why pixels could not describe a
## vignette at all.
@export var fade_radius: float = 0.42
## ...then grain ramps to full over this much more. 0.42 + 0.48 lands just past
## the corner, so the corners sit near full grain and the edge midpoints are
## partway up the ramp.
@export var fade_distance: float = 0.48
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
## Where the vignette closes to while the menu is up. The grain walks inward
## toward the centre and frames the menu window rather than covering it —
## Stan's call, 2026-09-03. Zero would put full grain over the menu itself.
@export var pause_fade_radius: float = 0.18
## The ramp while paused. Tighter than the resting one, so the closed-in
## vignette has a defined edge instead of a long smear.
@export var pause_fade_distance: float = 0.30

@onready var _material := material as ShaderMaterial    # Материал шейдера
var _prev_enabled := true                              # Пред. состояние эффекта
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
		## Closed: the screen starts fully grained and the fade-in opens the
		## vignette out to its resting size. Matches _animate_fade_in()'s own
		## start values, so there is no jump on the first frame of the tween.
		_material.set_shader_parameter("fade_radius", 0.0)
		_material.set_shader_parameter("fade_distance", pause_fade_distance)
		## The vignette is measured against the half-diagonal, so a resize
		## changes what its radii mean. One line here beats a per-frame write.
		get_viewport().size_changed.connect(_update_static_params)
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


## ============================================
## 🔵 PROCESS
## ============================================

func _process(_delta: float) -> void:
	## Nothing tracks the character any more — the vignette is anchored on the
	## frame — so the only per-frame question left is the inspector toggle.
	if not _material:
		return
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

	## Opens the vignette out from nothing to its resting size — so the screen
	## starts fully grained and clears to the middle. That reading of "fade in"
	## is the author's; see docs/NOW.md, it is on the open list.
	_active_tween.tween_method(
		func(value: float): _material.set_shader_parameter("fade_radius", value),
		0.0,
		fade_radius,
		fade_in_duration
	)

	_active_tween.tween_method(
		func(value: float): _material.set_shader_parameter("fade_distance", value),
		pause_fade_distance,
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

	## The vignette walks INWARD toward the centre and frames the menu window.
	## NOT to zero: zero would put full grain over the menu itself, and the
	## point of the move is to close around the menu, not to bury it.
	_active_tween.tween_method(
		func(value: float): _material.set_shader_parameter("fade_radius", value),
		_material.get_shader_parameter("fade_radius"),
		pause_fade_radius,
		pause_transition_duration
	)

	_active_tween.tween_method(
		func(value: float): _material.set_shader_parameter("fade_distance", value),
		_material.get_shader_parameter("fade_distance"),
		pause_fade_distance,
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
