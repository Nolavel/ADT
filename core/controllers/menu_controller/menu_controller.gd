# =============================================================================
# menu_controller.gd
# ## RU: Корень паузного меню. Кнопки активируются только через drag-handle.
# ## ENG: Pause menu root. Buttons are activated via drag-handle only.
# process_mode = ALWAYS (выставляется снаружи при инстанцировании)
# =============================================================================
extends Control

@onready var continue_button: DragTargetButton = $btn_continue
@onready var quit_button: DragTargetButton      = $btn_out
@onready var settings_button: DragTargetButton  = $btn_settings
@onready var last_save: DragTargetButton        = $btn_last_save
@onready var drag_handle: Button                = $btn_drag_handle

var _drag := DragHandleController.new()

@export var settings_scene: PackedScene   ## RU: назначь res://ui/settings.tscn

var _settings: Control = null
var _in_settings: bool = false


func _ready() -> void:
	visible = false
	modulate.a = 0.0

	PlayerState.mode_changed.connect(_on_player_state_mode_changed)
	_drag.process_mode = Node.PROCESS_MODE_ALWAYS
	_drag.setup(drag_handle, [continue_button, quit_button, settings_button, last_save])
	_drag.target_interacted.connect(_on_target_interacted)
	add_child(_drag)   ## RU: обязательно — контроллеру нужен _process


#func _process(delta: float) -> void:
	#_drag.process(delta)

func _on_target_interacted(target: DragTargetButton) -> void:
	match target:
		continue_button: _on_continue_pressed()
		quit_button:     _on_quit_pressed()
		settings_button: _open_settings()
		last_save:       print("💾 Загрузка последнего сейва — не реализовано")

func _on_player_state_mode_changed(_old_mode, new_mode) -> void:
	if new_mode == PlayerState.Mode.MENU:
		_fade_in()
	elif _in_settings:
		await _settings.fade_out()
		_in_settings = false
		_drag.set_locked(false)
		visible = false
	elif visible:
		_fade_out()

func _on_continue_pressed() -> void:
	PlayerState.close_menu()

func _on_quit_pressed() -> void:
	drag_handle.disabled = true
	quit_button.text = "ouuut..."
	await _fade_out()
	await get_tree().create_timer(1.0, true).timeout
	get_tree().quit()

func _fade_in() -> void:
	_drag.reset_handle(true)
	visible = true
	modulate.a = 0.0
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(self, "modulate:a", 1.0, 0.3)

func _fade_out() -> void:
	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	await tween.finished
	visible = false

# -----------------------------------------------------------------------------
# ## RU: Настройки / ENG: Settings
# -----------------------------------------------------------------------------

func _open_settings() -> void:
	if _in_settings:
		return
	if settings_scene == null:
		push_error("menu_controller: settings_scene не назначена")
		return

	_in_settings = true
	_drag.set_locked(true)

	if _settings == null:
		_settings = settings_scene.instantiate()
		_settings.process_mode = Node.PROCESS_MODE_ALWAYS
		## RU: добавляем в РОДИТЕЛЯ меню, иначе visible=false меню
		##     скроет и настройки вместе с собой
		## ENG: parent it to the menu's PARENT — otherwise hiding the menu
		##      hides settings along with it
		get_parent().add_child(_settings)
		_settings.back_requested.connect(_close_settings)

	await _fade_out()
	await _settings.fade_in()

func _close_settings() -> void:
	if not _in_settings:
		return
	await _settings.fade_out()
	await _fade_in()
	_in_settings = false
	_drag.set_locked(false)
