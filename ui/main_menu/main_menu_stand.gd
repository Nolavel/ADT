# =============================================================================
# main_menu_stand.gd
# ## RU: СТЕНД, не игровое меню. Не подключён к потоку сцен, run/main_scene
#        остаётся world.tscn. Существует, чтобы гонять барабан отдельно от мира.
#        Когда меню пойдёт в игру, обработчики переедут в реальный корень —
#        матчиться они будут по тем же slot_id, тело _on_slot_fired переносится
#        как есть, а этот файл удаляется целиком.
# ## ENG: TEST STAND, not the shipping menu. Deliberately outside the scene
#         flow. When the menu ships, _on_slot_fired moves to the real root
#         unchanged — it already matches on slot_id — and this file is deleted.
# =============================================================================
extends Control

## RU: Затухание перед выходом, сек. Совпадает с menu_controller._fade_out().
const FADE_TIME: float = 0.3
## RU: Пауза после затухания, чтобы выход не выглядел обрывом.
const QUIT_DELAY: float = 1.0

@onready var _revolver: RevolverMenu = $RevolverMenu

var _closing: bool = false


func _ready() -> void:
	_revolver.slot_focused.connect(_on_slot_focused)
	_revolver.slot_fired.connect(_on_slot_fired)


func _on_slot_focused(index: int, slot_id: StringName) -> void:
	print("[stand] focused  #%d  %s" % [index, slot_id])


## RU: Курок попал в камору. Матчимся по slot_id, а не по индексу и не по
##     тексту: порядок узлов в сцене и подписи ещё будут меняться.
func _on_slot_fired(index: int, slot_id: StringName) -> void:
	print("[stand] FIRED    #%d  %s" % [index, slot_id])

	match slot_id:
		&"quit":
			_close()
		_:
			## RU: Остальные пункты стенду не принадлежат — им место в реальном
			##     корне меню, когда он появится.
			print("[stand] '%s' — обработчик не реализован" % slot_id)


func _close() -> void:
	if _closing:
		return
	_closing = true

	var tween: Tween = create_tween()
	tween.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(self, "modulate:a", 0.0, FADE_TIME)
	await tween.finished

	## RU: true — таймер идёт и на паузе, стенд может быть запущен под ней.
	await get_tree().create_timer(QUIT_DELAY, true).timeout
	get_tree().quit()
