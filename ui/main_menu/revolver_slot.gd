# =============================================================================
# revolver_slot.gd
# ## RU: Поведение одной каморы барабана. RefCounted, узлом не является —
#        владеет им RevolverMenu, живёт ровно столько же, сколько меню.
#        Тот же приём, что у TpsShoulderCameraState / TpsCombatCameraState
#        внутри OnFootCameraComponent.
# ## ENG: Behaviour of a single revolver chamber. RefCounted, not a node —
#         owned by RevolverMenu and lives exactly as long as it does. Same
#         pattern as TpsShoulderCameraState / TpsCombatCameraState inside
#         OnFootCameraComponent.
#
# Разделение обязанностей:
#   delta_to_front() — чистый расчёт, ничего не трогает;
#   apply()          — раскладка по кругу, вызывается каждый кадр анимации;
#   set_focused()    — смена состояния, вызывается ТОЛЬКО в момент перехода.
# Дорогие вещи (font_size override, reset_size, grab_focus) живут строго в
# set_focused и по построению не могут попасть в покадровый путь.
# =============================================================================
extends RefCounted
class_name RevolverSlot

## RU: За этим углом от фронта камора полностью прозрачна.
const FADE_ARC_DEG: float = 130.0
## RU: Дуга, на которой камора добирает масштаб от MIN_SCALE до MAX_SCALE.
const SCALE_ARC_DEG: float = 90.0
const MIN_SCALE: float = 0.72
const MAX_SCALE: float = 1.00

## RU: Цветовые слоты темы Button. Перекрываем все — иначе disabled-камора
##     уедет в серый по умолчанию, а focus-камора в цвет темы.
const COLOR_ITEMS: PackedStringArray = [
	"font_color",
	"font_hover_color",
	"font_pressed_color",
	"font_focus_color",
	"font_disabled_color",
]

var button: RevolverSlotButton
var base_angle_deg: float

var _focused: bool = false
var _shader: ShaderMaterial


func _init(p_button: RevolverSlotButton, p_base_angle_deg: float) -> void:
	button = p_button
	base_angle_deg = p_base_angle_deg
	_shader = button.material as ShaderMaterial
	## RU: Приводим камору к состоянию покоя из кода, а не полагаемся на то,
	##     что в сцене руками выставили нужные оверрайды.
	_apply_state(false)


## RU: Модуль угла (в градусах) между каморой и фронтом барабана.
## ENG: Absolute angle in degrees between this chamber and the front of the drum.
func delta_to_front(rotation_deg: float) -> float:
	return absf(wrapf(base_angle_deg + rotation_deg, -180.0, 180.0))


## RU: Раскладывает камору по окружности вокруг center.
##     Фронт барабана — точка слева от центра (угол 0).
func apply(center: Vector2, rotation_deg: float, radius: float) -> void:
	var current: float = base_angle_deg + rotation_deg
	var rad: float = deg_to_rad(current)
	var delta: float = absf(wrapf(current, -180.0, 180.0))

	var visibility: float = clampf(1.0 - delta / FADE_ARC_DEG, 0.0, 1.0)
	var s: float = MIN_SCALE + (MAX_SCALE - MIN_SCALE) * clampf(1.0 - delta / SCALE_ARC_DEG, 0.0, 1.0)

	## RU: pivot в центре кнопки — масштаб идёт от середины текста, а не от угла.
	var half: Vector2 = button.size * 0.5
	button.pivot_offset = half
	button.position = center + Vector2(-cos(rad), -sin(rad)) * radius - half
	button.scale = Vector2(s, s)
	button.modulate.a = visibility
	button.visible = visibility > 0.001
	button.z_index = int(1000.0 - delta)


## RU: Переход между покоем и фронтом. Ранний выход обязателен: без него
##     покадровый вызов вернул бы дорогую работу обратно в _render().
func set_focused(value: bool) -> void:
	if _focused == value:
		return
	_apply_state(value)


func is_focused() -> bool:
	return _focused


func _apply_state(value: bool) -> void:
	_focused = value

	button.add_theme_font_size_override(
		"font_size", button.front_font_size if value else button.idle_font_size
	)
	var c: Color = button.front_color if value else button.idle_color
	for item in COLOR_ITEMS:
		button.add_theme_color_override(item, c)

	## RU: Только фронтальная камора — рабочая кнопка. Остальные не жмутся,
	##     не ловят мышь и не берут фокус. Так спуск не надо ловить вручную:
	##     клик, ui_accept и кнопка геймпада приходят штатным Button.pressed.
	## ENG: Only the front chamber is a live button. This is what makes click,
	##      ui_accept and gamepad all work through plain Button.pressed.
	button.disabled = not value
	## RU: PASS, а не STOP: левый клик кнопка съедает сама, а колесо мыши
	##     не обрабатывает и пропускает выше — в _gui_input барабана.
	## ENG: PASS, not STOP: the button consumes left click but ignores the
	##      wheel, letting it bubble up to the drum's _gui_input.
	button.mouse_filter = Control.MOUSE_FILTER_PASS if value else Control.MOUSE_FILTER_IGNORE
	button.focus_mode = Control.FOCUS_ALL if value else Control.FOCUS_NONE

	## RU: Размер шрифта поменялся → минимальный размер кнопки устарел.
	button.reset_size()

	if _shader != null:
		_shader.set_shader_parameter("active", 1.0 if value else 0.0)

	if value and button.is_inside_tree():
		button.grab_focus()
