# =============================================================================
# drag_target_button.gd
# ## RU: Кнопка-цель drag-handle паттерна. Состояние выставляет контроллер.
#        Визуал состояний рисуется в _draw(): пунктир (1) → уголки (2) → рамка (3).
#        Сам рисунок живёт в target_contour.gd — там же, откуда его берёт
#        барабан главного меню.
# ## ENG: Drag-handle target button. State is driven by the controller.
#         State visuals are drawn in _draw(): dashes (1) → corners (2) → frame (3).
#         The drawing itself lives in target_contour.gd, shared with the
#         main-menu revolver drum.
#
# ВНИМАНИЕ: этот класс владеет position / scale / modulate кнопки
# (_home_position, lean_toward, reset_position, _apply_state). Не наследуй от
# него кнопку, чья раскладка считается снаружи — будет два владельца на одни
# свойства. Именно поэтому RevolverSlotButton наследуется от Button, а не отсюда.
# =============================================================================
extends Button
class_name DragTargetButton

enum DragState { IDLE, AWAITING, NEAREST, ACTIVE }

@export_group("Colors")
@export var idle_color: Color     = Color(1, 1, 1, 0.20)
@export var awaiting_color: Color = Color(0.45, 0.80, 1.00, 0.70)
@export var nearest_color: Color  = Color(0.70, 0.95, 1.00, 0.95)
@export var active_color: Color   = Color(1.00, 0.80, 0.25, 1.00)

@export_group("Shape")
@export var nearest_scale: float = 1.04
@export var active_scale: float  = 1.10
@export var lean_distance: float = 10.0   ## RU: сдвиг к хэндлу / ENG: lean toward handle
@export var border_width: float  = 2.0
@export var dash_length: float   = 8.0
@export var dash_gap: float      = 6.0
@export var corner_length: float = 18.0
@export var frame_padding: float = 6.0

var drag_state: int = DragState.IDLE

var _tween: Tween
var _home_position: Vector2
var _dash_offset: float = 0.0
var _pulse: float = 0.0
## RU: 0 = уголки далеко, 1 = уголки прижаты / ENG: 0 = corners far, 1 = tight
var _corner_tightness: float = 0.0


func _ready() -> void:
	disabled = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	pivot_offset = size * 0.5
	_home_position = position
	resized.connect(func() -> void: pivot_offset = size * 0.5)
	_apply_state(true)


func _process(delta: float) -> void:
	if drag_state == DragState.IDLE:
		return
	_dash_offset = fmod(_dash_offset + delta * 26.0, dash_length + dash_gap)
	_pulse = (sin(Time.get_ticks_msec() * 0.004) + 1.0) * 0.5
	queue_redraw()

# -----------------------------------------------------------------------------
# ## RU: Публичный API для контроллера / ENG: Public API for the controller
# -----------------------------------------------------------------------------

func set_drag_state(new_state: int) -> void:
	if new_state == drag_state:
		return
	drag_state = new_state
	_apply_state(false)
	queue_redraw()


## RU: направление на хэндл в глобальных координатах (для наклона)
## ENG: direction toward the handle in global space (used for lean)
func lean_toward(handle_global_center: Vector2) -> void:
	if drag_state != DragState.NEAREST and drag_state != DragState.ACTIVE:
		return
	var dir: Vector2 = (handle_global_center - get_global_rect().get_center()).normalized()
	position = position.lerp(_home_position + dir * lean_distance, 0.25)


func reset_position() -> void:
	position = _home_position

# -----------------------------------------------------------------------------

func _state_color() -> Color:
	match drag_state:
		DragState.AWAITING: return awaiting_color
		DragState.NEAREST:  return nearest_color
		DragState.ACTIVE:   return active_color
		_:                  return idle_color


func _apply_state(instant: bool) -> void:
	var target_scale: float = 1.0
	var target_tight: float = 0.0
	match drag_state:
		DragState.NEAREST:
			target_scale = nearest_scale
			target_tight = 0.5
		DragState.ACTIVE:
			target_scale = active_scale
			target_tight = 1.0
		DragState.IDLE:
			position = _home_position

	if instant:
		modulate = _state_color()
		scale = Vector2.ONE * target_scale
		_corner_tightness = target_tight
		return

	if _tween != null and _tween.is_running():
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_tween.tween_property(self, "modulate", _state_color(), 0.12)
	_tween.tween_property(self, "scale", Vector2.ONE * target_scale, 0.12)
	_tween.tween_property(self, "_corner_tightness", target_tight, 0.15)

	## RU: короткий импульс при захвате / ENG: quick pop on lock-on
	if drag_state == DragState.ACTIVE:
		var pop: Tween = create_tween()
		pop.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		pop.tween_property(self, "scale", Vector2.ONE * (active_scale + 0.06), 0.06)
		pop.tween_property(self, "scale", Vector2.ONE * active_scale, 0.10)

# -----------------------------------------------------------------------------
# ## RU: Отрисовка / ENG: Drawing
# -----------------------------------------------------------------------------

func _draw() -> void:
	if drag_state == DragState.IDLE:
		return

	## RU: рамка отходит наружу когда цель ещё "далеко"
	## ENG: frame sits further out while the target is still "far"
	var pad: float = lerpf(frame_padding + 10.0, frame_padding, _corner_tightness)
	var r := Rect2(Vector2(-pad, -pad), size + Vector2(pad, pad) * 2.0)
	var col: Color = _state_color()

	match drag_state:
		DragState.AWAITING:
			col.a *= lerpf(0.45, 0.95, _pulse)
			TargetContour.draw_dashed_rect(self, r, col, border_width, dash_length, dash_gap, _dash_offset)
		DragState.NEAREST:
			var l: float = lerpf(corner_length, corner_length * 1.6, _corner_tightness)
			TargetContour.draw_corners(self, r, col, border_width + 1.0, l)
		DragState.ACTIVE:
			TargetContour.draw_frame(self, r, col, border_width + 1.0)
