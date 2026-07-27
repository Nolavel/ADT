# =============================================================================
# main_menu_stand.gd
# ## RU: СТЕНД, не игровое меню. Никуда не подключён, run/main_scene остаётся
#        world.tscn. Существует, чтобы гонять барабан отдельно от мира и
#        видеть в выводе, что именно приходит наружу.
#        Когда меню пойдёт в игру — обработчики переезжают в реальный корень,
#        матчатся по slot_id, а этот файл удаляется целиком.
# ## ENG: TEST STAND, not the shipping menu. Deliberately not wired into
#         run/main_scene. Exists to exercise the drum in isolation.
# =============================================================================
extends Control

@onready var _revolver: RevolverMenu = $RevolverMenu


func _ready() -> void:
	_revolver.slot_focused.connect(_on_slot_focused)
	_revolver.slot_fired.connect(_on_slot_fired)


func _on_slot_focused(index: int, slot_id: StringName) -> void:
	print("[stand] focused  #%d  %s" % [index, slot_id])


func _on_slot_fired(index: int, slot_id: StringName) -> void:
	print("[stand] FIRED    #%d  %s" % [index, slot_id])
