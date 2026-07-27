# =============================================================================
# revolver_slot_button.gd
# ## RU: Кнопка-камора барабана. Хранит идентификатор пункта и палитру двух
#        состояний (покой / на фронте). Позицией, масштабом, фокусом и
#        disabled управляет RevolverSlot — из этого скрипта туда не лезем.
# ## ENG: Revolver chamber button. Holds the item id and the palette for its
#         two states (idle / at front). Position, scale, focus and disabled are
#         driven by RevolverSlot — never from here.
#
# Кнопки создаются в сцене revolver_menu.tscn, а не кодом. Порядок узлов в
# дереве = порядок камор в барабане. Добавить пункт = добавить узел.
# =============================================================================
extends Button
class_name RevolverSlotButton

## RU: Стабильный идентификатор пункта. Текст локализуется и переписывается,
##     поэтому обработчики матчатся ИМЕННО по slot_id, а не по text и не по name.
## ENG: Stable item id. Text gets localized and rewritten, so handlers must
##      match on slot_id — never on text, never on node name.
@export var slot_id: StringName = &""

@export_group("Idle")
@export var idle_font_size: int = 20
@export var idle_color: Color = Color(0.60, 0.57, 0.51)

@export_group("Front")
@export var front_font_size: int = 28
@export var front_color: Color = Color(0.85, 0.83, 0.78)


func _ready() -> void:
	if slot_id.is_empty():
		push_warning("RevolverSlotButton '%s': slot_id не задан — пункт не будет опознан обработчиком." % name)
