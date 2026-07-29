# =============================================================================
# revolver_menu.gd
# ## RU: Радиальное меню «барабан револьвера». Пристыковано к правому краю:
#        центр окружности уведён за экран, на виду только левая дуга.
#        Курок лежит по центру экрана.
# ## ENG: Radial "revolver drum" menu docked to the right edge; the hammer
#         rests at the centre of the screen.
#
# МОДЕЛЬ АКТИВАЦИИ. Пункт не «нажимается» — в него попадают. Терминальное
# состояние одно для любого ввода: нужная камора стоит на фронте, курок в неё
# прилетел, выстрел. Различается только порядок:
#   рука     — крутишь барабан (колесо / протяжка), тянешь курок, отпускаешь;
#   клавиша  — действие называет камору, барабан её доворачивает, курок летит
#              сам. Клавиша не обходит механику, она проигрывает жест за игрока.
# Клик по каморе и ui_accept идут тем же путём: они просят выстрел, а стреляет
# всегда курок.
#
# ESC — две разные команды на одной клавише:
#   короткое нажатие  — барабан возвращается в дефолт (default_slot_id на приём),
#                       ничего не стреляет;
#   удержание > 1 сек — полный проход по hold_slot_id: доворот + удар.
# Разрыв намеренный: сброс дёшев и делается на рефлексе, выход из игры дорог и
# требует осознанного удержания.
#
# Бюджет прохода: доворот 0.30 + удар 0.22 = 0.52 с до выстрела, пауза на
# попадании 0.10. Возврат курка домой идёт уже после выстрела и в бюджет не
# входит.
#
# Обязанности:
#   этот скрипт              — вращение барабана и последовательность выстрела;
#   RevolverSlot             — поведение одной каморы;
#   RevolverHammerController — курок;
#   .tscn                    — кнопки, тексты, slot_id, привязки действий.
# Кнопки НЕ создаются кодом. Порядок узлов внутри %Slots = порядок камор.
#
# Ввод намеренно на GUI-вводе, а не через InputSystems: тот автозагрузчик
# игровой (pause_pressed, interact_pressed, inventory_pressed), меню-навигации
# в нём нет. Прецедент для UI-виджетов уже есть — DragHandleController тоже
# читает мышь напрямую.
# =============================================================================
extends Control
class_name RevolverMenu

## RU: Барабан довернулся, под курком новая камора. Не является подтверждением.
signal slot_focused(index: int, slot_id: StringName)
## RU: Курок попал в камору. Вот это — подтверждение.
signal slot_fired(index: int, slot_id: StringName)

@export_group("Geometry")
@export var radius: float = 310.0
## RU: Центр окружности как доля собственного размера: (1, 0.5) — правый край,
##     середина по высоте. Считается от size, поэтому переживает ресайз окна.
@export var center_anchor: Vector2 = Vector2(1.0, 0.5)
## RU: Доп. сдвиг центра в пикселях. +X уводит центр дальше за правый край.
@export var center_offset: Vector2 = Vector2(180.0, 0.0)

@export_group("Feel")
@export var snap_duration: float = 0.30
## RU: Градусов поворота на пиксель протяжки мышью/пальцем.
@export var drag_sensitivity: float = 0.35

@export_group("Escape")
## RU: Дефолтная камора. Она стоит на приёме при открытии меню и туда же
##     возвращает короткое нажатие Esc.
@export var default_slot_id: StringName = &"continue"
## RU: Удержание Esc дольше этого времени запускает полный проход, сек.
@export var hold_threshold: float = 1.0
## RU: Камора, по которой бьёт удержание Esc.
##     Пусто — удержание бьёт по той каморе, что сейчас на фронте.
@export var hold_slot_id: StringName = &"quit"

@onready var _slots_root: Control = %Slots
@onready var _hammer: Button = %Hammer

var _slots: Array[RevolverSlot] = []
var _step_deg: float = 0.0
var _rotation_deg: float = 0.0
var _focused_index: int = -1

var _hammer_controller: RevolverHammerController
var _snap_tween: Tween
## RU: Идёт последовательность выстрела — весь ввод в барабан закрыт.
var _busy: bool = false

var _dragging: bool = false
var _drag_start_y: float = 0.0
var _drag_start_rotation: float = 0.0

## RU: Сколько Esc уже удерживают, сек. Отрицательное — не удерживают.
var _esc_held: float = -1.0
## RU: Удержание уже сработало — отпускание не должно ещё и сбросить барабан.
var _esc_consumed: bool = false


func _ready() -> void:
	_collect_slots()
	if _slots.is_empty():
		return

	_hammer_controller = RevolverHammerController.new()
	_hammer_controller.setup(_hammer, _front_chamber_center)
	_hammer_controller.aim_changed.connect(_on_hammer_aim_changed)
	_hammer_controller.struck.connect(_on_hammer_struck)
	add_child(_hammer_controller)   ## RU: обязательно — контроллеру нужен _process

	## RU: Центр барабана и дом курка зависят от size — пересобираем при ресайзе.
	resized.connect(_on_resized)

	## RU: Дефолтная камора встаёт на приём сразу, без анимации.
	var default_index: int = _index_of(default_slot_id)
	if default_index > 0:
		_rotation_deg = -float(default_index) * _step_deg

	set_process(false)   ## RU: _process нужен только пока удерживают Esc
	_render()


func _on_resized() -> void:
	## RU: Курок закреплён якорями по центру экрана — его домашняя точка
	##     уезжает вместе с окном, перезахватываем.
	if _hammer_controller != null:
		_hammer_controller.capture_home()
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
		## RU: Камора НЕ подписана на pressed. Нажатие по каморе не стреляет:
		##     стреляет только курок, долетевший до неё. Иначе курок был бы
		##     украшением при живой кнопке. Кнопкой камора остаётся ради
		##     фокуса и ui_accept, а тот идёт через invoke_slot() ниже.
		_slots.append(RevolverSlot.new(button, float(i) * _step_deg))


func _index_of(id: StringName) -> int:
	if id.is_empty():
		return -1
	for i in _slots.size():
		if _slots[i].button.slot_id == id:
			return i
	return -1


# -----------------------------------------------------------------------------
# ## RU: Раскладка / ENG: Layout
# -----------------------------------------------------------------------------

func _center() -> Vector2:
	return size * center_anchor + center_offset


## RU: Куда бьёт курок. Глобальный центр каморы на фронте.
##     Замечание: get_global_rect() не учитывает scale каморы, а барабан её
##     масштабирует. На фронте scale = MAX_SCALE = 1.0, расхождения нет.
##     Если MAX_SCALE станет не 1.0 — сюда придётся добавить поправку.
func _front_chamber_center() -> Vector2:
	if _focused_index < 0:
		return global_position
	return _slots[_focused_index].button.get_global_rect().get_center()


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

	## RU: Проход 3 — раскладка. После смены фронта размеры уже пересчитаны.
	var c: Vector2 = _center()
	for slot in _slots:
		slot.apply(c, _rotation_deg, radius)


# -----------------------------------------------------------------------------
# ## RU: Ввод / ENG: Input
# -----------------------------------------------------------------------------

## RU: Крутится только пока Esc удерживают.
func _process(delta: float) -> void:
	if _esc_held < 0.0:
		set_process(false)
		return
	_esc_held += delta
	if not _esc_consumed and _esc_held >= hold_threshold:
		_esc_consumed = true
		_fire_hold_target()


## RU: Стрелки и привязанные действия перехватываем в _shortcut_input, потому
##     что он идёт ДО обработки GUI. Иначе штатная навигация по фокусу
##     Viewport'а увела бы фокус на соседний контрол — каморы разложены по
##     кругу, «сосед сверху» там означает не то, что нужно.
func _shortcut_input(event: InputEvent) -> void:
	if _slots.is_empty() or not is_visible_in_tree():
		return

	## RU: Esc обрабатываем ДО проверки _busy — иначе отпускание клавиши
	##     потеряется, пока идёт проход, и счётчик удержания залипнет.
	if event.is_action_pressed("ui_cancel", false):
		_esc_held = 0.0
		_esc_consumed = false
		set_process(true)
		accept_event()
		return
	if event.is_action_released("ui_cancel"):
		var was_consumed: bool = _esc_consumed
		_esc_held = -1.0
		_esc_consumed = false
		set_process(false)
		accept_event()
		if not was_consumed:
			reset_to_default()
		return

	if _busy:
		return

	## RU: ui_accept — тот же автоматический проход, что у удержания Esc:
	##     клавиатура не обходит механику, курок всё равно летит.
	if event.is_action_pressed("ui_accept", false):
		invoke_slot(_focused_index)
		accept_event()
		return

	if event.is_action_pressed("ui_up", true):
		step_by(-1)
		accept_event()
		return
	if event.is_action_pressed("ui_down", true):
		step_by(1)
		accept_event()
		return

	## RU: Прямые привязки камор. Esc сюда не входит — у него своя логика выше.
	for i in _slots.size():
		var action: StringName = _slots[i].button.shortcut_action
		if action.is_empty():
			continue
		if event.is_action_pressed(action):
			invoke_slot(i)
			accept_event()
			return


func _gui_input(event: InputEvent) -> void:
	if _busy or _slots.is_empty():
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
				##     по каморе и по курку сюда не доходит — их съедают Button.
				if event.pressed:
					_dragging = true
					_drag_start_y = event.position.y
					_drag_start_rotation = _rotation_deg
					_kill_snap()
				elif _dragging:
					_dragging = false
					_snap()
				accept_event()

	elif event is InputEventMouseMotion and _dragging:
		_rotation_deg = _drag_start_rotation + (event.position.y - _drag_start_y) * drag_sensitivity
		_render()
		accept_event()


func _fire_hold_target() -> void:
	## RU: Пустой hold_slot_id — бьём по той каморе, что сейчас на фронте.
	var index: int = _index_of(hold_slot_id)
	if index < 0:
		index = _focused_index
	invoke_slot(index)


# -----------------------------------------------------------------------------
# ## RU: Курок / ENG: Hammer
# -----------------------------------------------------------------------------

## RU: Камора встаёт «на приём» не по факту захвата курка, а только когда жест
##     дотянул до зачёта. Игрок видит заранее, выстрелит отпускание или нет.
func _on_hammer_aim_changed(valid: bool) -> void:
	if _focused_index < 0:
		return
	_slots[_focused_index].button.set_chamber_state(
		RevolverSlotButton.ChamberState.ARMED if valid else RevolverSlotButton.ChamberState.READY
	)


func _on_hammer_struck() -> void:
	if _focused_index < 0:
		return
	var button: RevolverSlotButton = _slots[_focused_index].button
	button.set_chamber_state(RevolverSlotButton.ChamberState.STRUCK)
	slot_fired.emit(_focused_index, button.slot_id)

	await get_tree().create_timer(_hammer_controller.hold_time).timeout
	## RU: Фронт мог смениться, пока ждали — трогаем только если он тот же.
	if _focused_index >= 0 and _slots[_focused_index].button == button:
		button.set_chamber_state(RevolverSlotButton.ChamberState.READY)
	_busy = false


# -----------------------------------------------------------------------------
# ## RU: Публичный API / ENG: Public API
# -----------------------------------------------------------------------------

## RU: Полная последовательность: довернуть камору на фронт и ударить по ней.
##     Единственная точка входа для клика, ui_accept, привязанных действий и
##     удержания Esc.
func invoke_slot(index: int) -> void:
	if _busy or index < 0 or index >= _slots.size():
		return
	_busy = true
	_kill_snap()

	if index != _focused_index:
		var tw: Tween = _animate_to(_rotation_deg + _shortest_diff_to(index))
		await tw.finished

	_hammer_controller.strike()


## RU: Вернуть барабан в дефолт: default_slot_id на приём. Ничего не стреляет.
func reset_to_default() -> void:
	select_index(_index_of(default_slot_id))


## RU: Провернуть барабан на direction камор (+1 вниз по списку, -1 вверх).
func step_by(direction: int) -> void:
	if _busy:
		return
	var snapped_now: float = roundf(_rotation_deg / _step_deg) * _step_deg
	_animate_to(snapped_now - float(direction) * _step_deg)


## RU: Довернуть барабан к конкретной каморе по кратчайшей дуге.
func select_index(index: int) -> void:
	if _busy or index < 0 or index >= _slots.size():
		return
	_animate_to(_rotation_deg + _shortest_diff_to(index))


func focused_slot_id() -> StringName:
	if _focused_index < 0:
		return &""
	return _slots[_focused_index].button.slot_id


# -----------------------------------------------------------------------------
# ## RU: Доводка / ENG: Snapping
# -----------------------------------------------------------------------------

func _shortest_diff_to(index: int) -> float:
	var target: float = -float(index) * _step_deg
	return wrapf(target - _rotation_deg, -180.0, 180.0)


func _snap() -> void:
	_animate_to(roundf(_rotation_deg / _step_deg) * _step_deg)


func _animate_to(target_deg: float) -> Tween:
	_kill_snap()
	_snap_tween = create_tween()
	_snap_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_snap_tween.tween_method(_set_rotation, _rotation_deg, target_deg, snap_duration)
	return _snap_tween


func _kill_snap() -> void:
	if _snap_tween != null and _snap_tween.is_valid():
		_snap_tween.kill()
	_snap_tween = null


func _set_rotation(value: float) -> void:
	_rotation_deg = value
	_render()
