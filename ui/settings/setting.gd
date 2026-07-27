# =============================================================================
# settings_controller.gd
# ## RU: Корень сцены настроек. Открывается из паузного меню, возврат — через
#        drag-handle на кнопку btn_back. Сам себя не удаляет — только сообщает
#        сигналом back_requested, решение принимает вызвавший.
# ## ENG: Settings scene root. Opened from the pause menu; going back is done
#         via the drag-handle onto btn_back. Does not free itself — it just
#         emits back_requested and lets the caller decide.
#
# process_mode = ALWAYS (выставляется снаружи при инстанцировании)
# =============================================================================
extends Control

signal back_requested

@export var fade_time: float = 0.3

@onready var back_button: DragTargetButton = $btn_back
@onready var drag_handle: Button = $btn_drag_handle

var _drag := DragHandleController.new()

func _ready() -> void:
	visible = false
	modulate.a = 0.0

	add_child(_drag)
	_drag.process_mode = Node.PROCESS_MODE_ALWAYS
	_drag.setup(drag_handle, [back_button])
	_drag.target_interacted.connect(_on_target_interacted)

func _on_target_interacted(target: DragTargetButton) -> void:
	match target.name:
		"btn_back":
			print("↩️ Настройки: возврат в меню")
			_drag.set_locked(true)   ## RU: запрет повторного захвата на время ухода
			back_requested.emit()
		_:
			push_warning("settings_controller: необработанная цель %s" % target.name)

# -----------------------------------------------------------------------------
# ## RU: Публичный API / ENG: Public API
# -----------------------------------------------------------------------------

func fade_in() -> void:
	_drag.reset_handle(true)
	_drag.set_locked(false)
	visible = true
	modulate.a = 0.0
	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(self, "modulate:a", 1.0, fade_time)
	await tw.finished

func fade_out() -> void:
	var tw := create_tween()
	tw.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(self, "modulate:a", 0.0, fade_time)
	await tw.finished
	visible = false
