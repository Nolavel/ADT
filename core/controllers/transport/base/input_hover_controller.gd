# =============================================================================
# input_hover_controller.gd — InputHoverController.
#
# Единственная задача: каждый физический кадр читать намерения игрока из
# InputSystems и кормить их в HoverBase.set_move_intent(). Никакой физики,
# никакого состояния — вся динамика в hover_base, весь ввод в InputSystems
# (этот скрипт Input.* не трогает, принцип единственного читателя ввода).
#
# ПОДКЛЮЧЕНИЕ: дочерняя нода сцены ховера (рядом с HoverEntryTrigger).
# Включается/выключается триггером через set_active() на SEATED/EXITING.
# Выключен по умолчанию — пустой припаркованный ховер не опрашивает ввод.
#
# ai_hover_controller (позже) — зеркальный класс с тем же hover-интерфейсом,
# но намерения берёт из своей логики, не из InputSystems.
# =============================================================================

extends Node
class_name InputHoverController

## Корень ховера (HoverBase). По умолчанию — родитель.
@export var hover_path: NodePath = ^".."

var _hover: HoverBase = null
var _active: bool = false


func _ready() -> void:
	_hover = get_node(hover_path) as HoverBase
	if _hover == null:
		push_error("[InputHoverController] Родитель '%s' — не HoverBase"
				% get_node(hover_path).name)
	set_physics_process(false)


## Вызывает HoverEntryTrigger: true на SEATED, false на EXITING.
func set_active(active: bool) -> void:
	_active = active
	set_physics_process(active)
	if _hover != null:
		_hover.set_controlled(active)


func _physics_process(_delta: float) -> void:
	# Страховка: управление только в режиме HOVER (меню поверх — намерения
	# не шлём, ховер сам затухает по несвежему intent).
	if PlayerState.mode != PlayerState.Mode.HOVER:
		return
	_hover.set_move_intent(
			InputSystems.get_move_vector(),
			InputSystems.get_hover_vertical_axis())
