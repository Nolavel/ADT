# =============================================================================
# drag_handle_controller.gd
# ## RU: Контроллер drag-handle. Отпустил с толчком — хэндл летит к той цели,
#        что ближе всего по направлению толчка, и гарантированно попадает.
#        Отпустил без движения — интеракт по цели под хэндлом (если есть).
# ## ENG: Drag-handle controller. Release with a nudge — the handle flies to
#         whichever target best matches the nudge direction and always lands.
#         Release without motion — interact with the target underneath, if any.
#
# Рассчитан на НЕПОДВИЖНУЮ россыпь целей: выбор идёт по направлению и
# расстоянию. Для барабана главного меню он не подходит — там цель одна и она
# двигается, поэтому у барабана свой контроллер (revolver_hammer_controller.gd).
# =============================================================================
extends Node
class_name DragHandleController

signal target_interacted(target: DragTargetButton)

@export var nearest_radius: float = 130.0
## RU: Минимальная скорость толчка (px/сек), чтобы засчитать направление
## ENG: Minimum nudge speed (px/sec) for the direction to register
@export var nudge_threshold: float = 6.0
## RU: Время полёта до цели, сек / ENG: flight duration to the target, sec
@export var flight_time: float = 0.18

enum Phase { IDLE, DRAGGING, FLYING }

## RU: Окно усреднения скорости, сек / ENG: velocity averaging window, sec
const SAMPLE_WINDOW: float = 0.09

var handle: Control
var targets: Array[DragTargetButton] = []

var _phase: int = Phase.IDLE
var _handle_home: Vector2 = Vector2.ZERO
var _grab_offset: Vector2 = Vector2.ZERO
var _samples: Array[Dictionary] = []
var _velocity: Vector2 = Vector2.ZERO
## RU: Блокировка захвата на время переходов между экранами
## ENG: Blocks grabbing while screens are transitioning
var _locked: bool = false

# -----------------------------------------------------------------------------

func setup(p_handle: Control, p_targets: Array) -> void:
	handle = p_handle
	targets.clear()
	for t in p_targets:
		if t is DragTargetButton:
			targets.append(t)
	_handle_home = handle.position
	handle.button_down.connect(_on_handle_down)
	handle.button_up.connect(_on_handle_up)


func _process(delta: float) -> void:
	if _phase == Phase.DRAGGING:
		_process_drag(delta)


func set_locked(value: bool) -> void:
	_locked = value
	if handle != null:
		handle.disabled = value

# -----------------------------------------------------------------------------
# ## RU: Захват и протяжка / ENG: Grab and drag
# -----------------------------------------------------------------------------

func _on_handle_down() -> void:
	if _locked or _phase == Phase.FLYING:
		return
	_phase = Phase.DRAGGING
	_grab_offset = handle.get_global_mouse_position() - handle.global_position
	handle.z_index = 100
	_samples.clear()
	_velocity = Vector2.ZERO
	for t in targets:
		t.set_drag_state(DragTargetButton.DragState.AWAITING)


func _process_drag(_delta: float) -> void:
	var mouse: Vector2 = handle.get_global_mouse_position()
	handle.global_position = mouse - _grab_offset
	_push_sample(mouse)
	_velocity = _measure_velocity()

	var center: Vector2 = _handle_center()
	## RU: подсвечиваем ту, в которую полетим, если отпустить сейчас
	## ENG: highlight whichever target we'd fly to if released right now
	var candidate: DragTargetButton = _pick_target(center)

	for t in targets:
		if t == candidate:
			t.set_drag_state(DragTargetButton.DragState.NEAREST)
			t.lean_toward(center)
		else:
			t.set_drag_state(DragTargetButton.DragState.AWAITING)
			t.reset_position()


func _on_handle_up() -> void:
	if _phase != Phase.DRAGGING:
		return
	var target: DragTargetButton = _pick_target(_handle_center())
	if target != null:
		_fly_to(target)
	else:
		_clear_targets()
		reset_handle()

# -----------------------------------------------------------------------------
# ## RU: Выбор цели / ENG: Target selection
# -----------------------------------------------------------------------------

## RU: Приоритет: цель под хэндлом → цель по направлению толчка → ближайшая.
## ENG: Priority: target under handle → target matching nudge → nearest one.
func _pick_target(center: Vector2) -> DragTargetButton:
	for t in targets:
		if t.get_global_rect().has_point(center):
			return t

	if _velocity.length() >= nudge_threshold:
		return _best_by_direction(center, _velocity.normalized())

	return _nearest_target(center)


## RU: Из всех целей берём ту, что лучше всего совпадает с направлением.
##     Никакого конуса — что-то выбирается всегда.
## ENG: Pick whichever target best matches the direction.
##      No cone — something is always selected.
func _best_by_direction(origin: Vector2, dir: Vector2) -> DragTargetButton:
	var best: DragTargetButton = null
	var best_dot: float = -2.0
	for t in targets:
		var to_t: Vector2 = t.get_global_rect().get_center() - origin
		if to_t.length() < 1.0:
			continue
		var dot: float = dir.dot(to_t.normalized())
		if dot > best_dot:
			best_dot = dot
			best = t
	return best


func _nearest_target(point: Vector2) -> DragTargetButton:
	var best: DragTargetButton = null
	var best_d: float = nearest_radius
	for t in targets:
		var d: float = point.distance_to(t.get_global_rect().get_center())
		if d < best_d:
			best_d = d
			best = t
	return best

# -----------------------------------------------------------------------------
# ## RU: Полёт / ENG: Flight
# -----------------------------------------------------------------------------

func _fly_to(target: DragTargetButton) -> void:
	_phase = Phase.FLYING
	handle.disabled = true

	for t in targets:
		if t == target:
			t.set_drag_state(DragTargetButton.DragState.ACTIVE)
		else:
			t.set_drag_state(DragTargetButton.DragState.AWAITING)

	var dest: Vector2 = target.get_global_rect().get_center() - handle.size * 0.5

	var tw: Tween = handle.create_tween()
	tw.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(handle, "global_position", dest, flight_time)
	await tw.finished

	## RU: хэндл остаётся лежать на цели — домой не возвращаем.
	##     Позицию сбросит reset_handle() при следующем открытии виджета.
	## ENG: the handle stays where it landed — no return home.
	##      reset_handle() restores it when the widget is reopened.
	_phase = Phase.IDLE
	handle.z_index = 0
	handle.disabled = false
	_clear_targets()

	target_interacted.emit(target)

# -----------------------------------------------------------------------------

func _handle_center() -> Vector2:
	return handle.get_global_rect().get_center()


func _push_sample(pos: Vector2) -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	_samples.append({"t": now, "p": pos})
	while _samples.size() > 2 and now - _samples[0]["t"] > SAMPLE_WINDOW:
		_samples.pop_front()


func _measure_velocity() -> Vector2:
	if _samples.size() < 2:
		return Vector2.ZERO
	var dt: float = _samples[-1]["t"] - _samples[0]["t"]
	if dt <= 0.0001:
		return Vector2.ZERO
	return (_samples[-1]["p"] - _samples[0]["p"]) / dt


func _clear_targets() -> void:
	for t in targets:
		t.set_drag_state(DragTargetButton.DragState.IDLE)
		t.reset_position()


## RU: Вернуть хэндл на исходное место. Вызывать при открытии виджета.
## ENG: Return the handle to its home slot. Call when the widget opens.
func reset_handle(instant: bool = false) -> void:
	_phase = Phase.IDLE
	handle.z_index = 0
	handle.disabled = false
	_clear_targets()
	if instant:
		handle.position = _handle_home
		return
	var tw: Tween = handle.create_tween()
	tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(handle, "position", _handle_home, 0.3)
