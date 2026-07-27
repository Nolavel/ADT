# =============================================================================
# revolver_menu.gd
# ## RU: Радиальное меню «барабан револьвера». Пристыковано к правому краю:
#        центр окружности уведён за экран, на виду только левая дуга.
#        Камора на фронте — рабочая кнопка, она же спуск.
# ## ENG: Radial "revolver drum" menu docked to the right edge: the circle
#         centre sits off-screen, only the left arc is visible. The chamber at
#         the front is the live button and doubles as the trigger.
#
# Обязанности:
#   этот скрипт   — только вращение барабана и раздача состояния фронта;
#   RevolverSlot  — поведение одной каморы;
#   .tscn         — сами кнопки, тексты, slot_id, материалы.
# Кнопки НЕ создаются кодом. Порядок узлов внутри %Slots = порядок камор.
#
# Наружу отдаются два разных события — раньше это было одно, из-за чего
# прокрутка колесом читалась как подтверждение пункта:
#   slot_focused — барабан довернулся, пункт под спуском (звук щелчка, превью);
#   slot_fired   — по пункту нажали (переход).
# =============================================================================
extends Control
class_name RevolverMenu

## RU: Барабан довернулся, под спуском новая камора. Не является подтверждением.
signal slot_focused(index: int, slot_id: StringName)
## RU: Спуск нажат по камере на фронте.
signal slot_fired(index: int, slot_id: StringName)

@export_group("Geometry")
@export var radius: float = 310.0
## RU: Центр окружности как доля собственного размера: (1, 0.5) — правый край,
##     середина по высоте. Считается от size, поэтому переживает ресайз окна.
## ENG: Circle centre as a fraction of own size. Derived from size, so it
##      survives window resizes — nothing mutates position at _ready().
@export var center_anchor: Vector2 = Vector2(1.0, 0.5)
## RU: Доп. сдвиг центра в пикселях. +X уводит центр дальше за правый край.
@export var center_offset: Vector2 = Vector2(180.0, 0.0)

@export_group("Feel")
@export var snap_duration: float = 0.26
## RU: Градусов поворота на пиксель протяжки мышью/пальцем.
@export var drag_sensitivity: float = 0.35

@onready var _slots_root: Control = %Slots

var _slots: Array[RevolverSlot] = []
var _step_deg: float = 0.0
var _rotation_deg: float = 0.0
var _focused_index: int = -1

var _snap_tween: Tween
var _dragging: bool = false
var _drag_start_y: float = 0.0
var _drag_start_rotation: float = 0.0


func _ready() -> void:
	_collect_slots()
	if _slots.is_empty():
		return
	## RU: Центр зависит от size — пересобираем раскладку при любом ресайзе.
	resized.connect(_render)
	_render()


# -----------------------------------------------------------------------------
# ## RU: Сборка / ENG: Setup
# -----------------------------------------------------------------------------

func _collect_slots() -> void:
	_slots.clear()

	var buttons: Array[RevolverSlotButton] = []
	for child in _slots_root.get_children():
		if child is RevolverSlotButton:
			buttons.append(child)

	if buttons.is_empty():
		push_error("RevolverMenu: под %Slots нет ни одной RevolverSlotButton — барабан пуст.")
		return

	_step_deg = 360.0 / float(buttons.size())

	for i in buttons.size():
		var button: RevolverSlotButton = buttons[i]
		button.reset_size()
		button.pressed.connect(_on_slot_pressed.bind(i))
		_slots.append(RevolverSlot.new(button, float(i) * _step_deg))


# -----------------------------------------------------------------------------
# ## RU: Раскладка / ENG: Layout
# -----------------------------------------------------------------------------

func _center() -> Vector2:
	return size * center_anchor + center_offset


func _render() -> void:
	if _slots.is_empty():
		return

	## RU: Проход 1 — кто ближе к фронту. Чистый расчёт, ничего не мутирует.
	var nearest: int = 0
	var nearest_delta: float = 360.0
	for i in _slots.size():
		var d: float = _slots[i].delta_to_front(_rotation_deg)
		if d < nearest_delta:
			nearest_delta = d
			nearest = i

	## RU: Проход 2 — смена фронта, если он действительно сменился.
	if nearest != _focused_index:
		if _focused_index >= 0:
			_slots[_focused_index].set_focused(false)
		_focused_index = nearest
		_slots[nearest].set_focused(true)
		slot_focused.emit(nearest, _slots[nearest].button.slot_id)

	## RU: Проход 3 — раскладка. После смены фонта размеры уже пересчитаны.
	var c: Vector2 = _center()
	for slot in _slots:
		slot.apply(c, _rotation_deg, radius)


# -----------------------------------------------------------------------------
# ## RU: Ввод / ENG: Input
# -----------------------------------------------------------------------------

## RU: ui_up / ui_down перехватываем в _shortcut_input, потому что он идёт
##     ДО обработки GUI. Иначе штатная навигация по фокусу Viewport'а увела бы
##     фокус на соседний контрол — камеры разложены по кругу, «сосед сверху»
##     там означает не то, что нужно.
## ENG: Intercepted in _shortcut_input because it runs BEFORE GUI input —
##      otherwise the viewport's focus navigation would hijack the arrows.
func _shortcut_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or _slots.is_empty():
		return
	if event.is_action_pressed("ui_up", true):
		step_by(-1)
		accept_event()
	elif event.is_action_pressed("ui_down", true):
		step_by(1)
		accept_event()


func _gui_input(event: InputEvent) -> void:
	if _slots.is_empty():
		return

	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					step_by(-1)
					accept_event()
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					step_by(1)
					accept_event()
			MOUSE_BUTTON_LEFT:
				## RU: Протяжка стартует только с пустого места дуги. Нажатие
				##     по самой фронтальной каморе — это спуск, оно до сюда
				##     не доходит: Button съедает его раньше.
				if event.pressed:
					_dragging = true
					_drag_start_y = event.position.y
					_drag_start_rotation = _rotation_deg
					_kill_snap()
				else:
					if _dragging:
						_dragging = false
						_snap()
				accept_event()

	elif event is InputEventMouseMotion and _dragging:
		_rotation_deg = _drag_start_rotation + (event.position.y - _drag_start_y) * drag_sensitivity
		_render()
		accept_event()


func _on_slot_pressed(index: int) -> void:
	## RU: Страховка: выстрелить может только камора на фронте.
	if index != _focused_index:
		return
	slot_fired.emit(index, _slots[index].button.slot_id)


# -----------------------------------------------------------------------------
# ## RU: Публичный API / ENG: Public API
# -----------------------------------------------------------------------------

## RU: Провернуть барабан на direction камор (+1 вниз по списку, -1 вверх).
func step_by(direction: int) -> void:
	var snapped_now: float = roundf(_rotation_deg / _step_deg) * _step_deg
	_animate_to(snapped_now - float(direction) * _step_deg)


## RU: Довернуть барабан к конкретной каморе по кратчайшей дуге.
func select_index(index: int) -> void:
	if index < 0 or index >= _slots.size():
		return
	var target: float = -float(index) * _step_deg
	var diff: float = wrapf(target - _rotation_deg, -180.0, 180.0)
	_animate_to(_rotation_deg + diff)


func focused_slot_id() -> StringName:
	if _focused_index < 0:
		return &""
	return _slots[_focused_index].button.slot_id


# -----------------------------------------------------------------------------
# ## RU: Доводка / ENG: Snapping
# -----------------------------------------------------------------------------

func _snap() -> void:
	_animate_to(roundf(_rotation_deg / _step_deg) * _step_deg)


func _animate_to(target_deg: float) -> void:
	_kill_snap()
	_snap_tween = create_tween()
	_snap_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_snap_tween.tween_method(_set_rotation, _rotation_deg, target_deg, snap_duration)


func _kill_snap() -> void:
	if _snap_tween != null and _snap_tween.is_valid():
		_snap_tween.kill()
	_snap_tween = null


func _set_rotation(value: float) -> void:
	_rotation_deg = value
	_render()
