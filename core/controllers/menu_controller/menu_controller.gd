# =============================================================================
# menu_controller.gd
# Скрипт корневой ноды сцены игрового паузного меню (НЕ главное меню).
# Инстанцируется и показывается/скрывается извне (InputSystems).
# Сам input НЕ ловит — только реагирует на PlayerState.mode_changed
# и обрабатывает нажатия своих кнопок.
#
# process_mode ОБЯЗАТЕЛЬНО ALWAYS (выставляется кодом снаружи, при
# инстанцировании) — иначе после get_tree().paused = true
# кнопки перестанут получать input и Continue/Quit не нажмутся.
# =============================================================================
extends Control

@onready var continue_button: Button = $btn_continue
@onready var quit_button: Button = $btn_out


func _ready() -> void:
	visible = false
	modulate.a = 0.0

	PlayerState.mode_changed.connect(_on_player_state_mode_changed)

	if continue_button:
		continue_button.pressed.connect(_on_continue_pressed)
	if quit_button:
		quit_button.pressed.connect(_on_quit_pressed)


func _on_player_state_mode_changed(_old_mode, new_mode) -> void:
	if new_mode == PlayerState.Mode.MENU:
		_fade_in()
	elif visible:
		_fade_out()


func _on_continue_pressed() -> void:
	PlayerState.close_menu()


func _on_quit_pressed() -> void:
	if continue_button:
		continue_button.disabled = true
	if quit_button:
		quit_button.disabled = true
		quit_button.text = "ouuut..."

	await _fade_out()
	await get_tree().create_timer(1.0, true).timeout  # true = игнорировать паузу
	get_tree().quit()


func _fade_in() -> void:
	visible = true
	modulate.a = 0.0
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.tween_property(self, "modulate:a", 1.0, 0.3)


func _fade_out() -> void:
	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	await tween.finished
	visible = false
