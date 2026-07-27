# =============================================================================
# revolver_slot_button.gd
# ## RU: Кнопка-камора барабана. Хранит идентификатор пункта, необязательную
#        привязку к действию ввода и рисует контур своего состояния.
# ## ENG: Revolver chamber button. Holds the item id, an optional input-action
#         binding, and draws its own state contour.
#
# ГРАНИЦА ОТВЕТСТВЕННОСТИ — важно:
#   этот скрипт   — только _draw() и цвет/размер текста;
#   RevolverSlot  — position, scale, modulate, pivot_offset, disabled, focus.
# Здесь НЕ трогаем ни одно из тех свойств. Из-за этой границы камора и не
# наследуется от DragTargetButton: тот владеет position/scale/modulate сам.
#
# Мерцающий шейдер (neon_flicker) снят намеренно: он мигал по таймеру, а не по
# событию, и ничего не сообщал. Контур сообщает состояние.
# =============================================================================
extends Button
class_name RevolverSlotButton

## RU: Состояния каморы. Один в один со словарём DragTargetButton.DragState,
##     чтобы паузное и главное меню читались одинаково.
enum ChamberState {
	IDLE,    ## RU: не на фронте — контура нет
	READY,   ## RU: на фронте, ждёт курок — пунктир
	ARMED,   ## RU: курок взведён и полетит сюда — уголки
	STRUCK,  ## RU: попадание — сплошная рамка
}

## RU: Стабильный идентификатор пункта. Текст локализуется и переписывается,
##     поэтому обработчики матчатся ИМЕННО по slot_id, а не по text и не по name.
## ENG: Stable item id. Handlers match on slot_id — never on text or node name.
@export var slot_id: StringName = &""

## RU: Действие ввода, которое вызывает эту камору напрямую (например ui_cancel
##     на Quit). Пусто — привязки нет. Встроенный Button.shortcut сюда не
##     годится: он жмёт кнопку мгновенно и проезжает мимо доворота и курка,
##     ради которых всё и сделано.
## ENG: Input action that invokes this chamber. Button.shortcut is deliberately
##      not used — it fires instantly and skips the spin-and-strike animation.
@export var shortcut_action: StringName = &""

@export_group("Text: idle")
@export var idle_font_size: int = 20
@export var idle_color: Color = Color(0.60, 0.57, 0.51)

@export_group("Text: front")
@export var front_font_size: int = 28
@export var front_color: Color = Color(0.85, 0.83, 0.78)

@export_group("Contour")
@export var ready_color: Color  = Color(0.45, 0.80, 1.00, 0.70)
@export var armed_color: Color  = Color(0.70, 0.95, 1.00, 0.95)
@export var struck_color: Color = Color(1.00, 0.80, 0.25, 1.00)
@export var border_width: float  = 2.0
@export var dash_length: float   = 8.0
@export var dash_gap: float      = 6.0
@export var corner_length: float = 18.0
@export var frame_padding: float = 10.0

var chamber_state: int = ChamberState.IDLE

var _dash_offset: float = 0.0
var _pulse: float = 0.0


func _ready() -> void:
	if slot_id.is_empty():
		push_warning("RevolverSlotButton '%s': slot_id не задан — пункт не будет опознан обработчиком." % name)
	set_process(false)


func _process(delta: float) -> void:
	_dash_offset = fmod(_dash_offset + delta * 26.0, dash_length + dash_gap)
	_pulse = (sin(Time.get_ticks_msec() * 0.004) + 1.0) * 0.5
	queue_redraw()


## RU: Вызывает RevolverSlot. Процесс крутится только пока контур виден.
func set_chamber_state(new_state: int) -> void:
	if new_state == chamber_state:
		return
	chamber_state = new_state
	set_process(chamber_state != ChamberState.IDLE)
	queue_redraw()


func _contour_color() -> Color:
	match chamber_state:
		ChamberState.READY:  return ready_color
		ChamberState.ARMED:  return armed_color
		ChamberState.STRUCK: return struck_color
		_:                   return Color(0, 0, 0, 0)


func _draw() -> void:
	if chamber_state == ChamberState.IDLE:
		return

	var r := Rect2(
		Vector2(-frame_padding, -frame_padding),
		size + Vector2(frame_padding, frame_padding) * 2.0
	)
	var col: Color = _contour_color()

	match chamber_state:
		ChamberState.READY:
			col.a *= lerpf(0.45, 0.95, _pulse)
			TargetContour.draw_dashed_rect(self, r, col, border_width, dash_length, dash_gap, _dash_offset)
		ChamberState.ARMED:
			TargetContour.draw_corners(self, r, col, border_width + 1.0, corner_length)
		ChamberState.STRUCK:
			TargetContour.draw_frame(self, r, col, border_width + 1.0)
