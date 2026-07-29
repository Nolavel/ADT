# =============================================================================
# PlayerState.gd
# Autoload / Singleton — единственный источник правды о режиме игрока.
# =============================================================================
extends Node

enum Mode { ON_FOOT, HOVER, TUBE_TRANSIT, MENU }
enum ViewMode { TPS, ISOMETRIC }

var mode: Mode = Mode.ON_FOOT   # менять ТОЛЬКО через set_mode()/open_menu()/close_menu()
var view_mode: ViewMode = ViewMode.ISOMETRIC

## Персистентный под-режим камеры ховера (HoverCameraComponent.HoverView):
## переживает выход-вход в транспорт. 0 = CHASE, 1 = COCKPIT.
var hover_camera_view: int = 0

## Текущий ховер игрока (корень HoverBase). null вне транспорта.
## Пишет HoverEntryTrigger, читает camera_follow при входе в Mode.HOVER.
var current_hover: Node3D = null

## Режим, который был активен до входа в MENU — чтобы корректно вернуться
var _mode_before_menu: Mode = Mode.ON_FOOT

signal mode_changed(old_mode: Mode, new_mode: Mode)
signal view_mode_changed(old_view: ViewMode, new_view: ViewMode)


## Смена любого режима, КРОМЕ MENU. MENU управляется исключительно
## через open_menu()/close_menu(), чтобы пауза не расходилась с mode.
func set_mode(new_mode: Mode) -> void:
	if new_mode == Mode.MENU:
		push_error("[PlayerState] Используй open_menu() вместо set_mode(MENU)")
		return
	if mode == Mode.MENU:
		push_error("[PlayerState] Нельзя менять mode напрямую пока активно MENU — используй close_menu()")
		return
	if new_mode == mode:
		return

	var old_mode := mode
	mode = new_mode
	mode_changed.emit(old_mode, new_mode)
	print("[PlayerState] Mode: %s → %s" % [Mode.keys()[old_mode], Mode.keys()[new_mode]])


func open_menu() -> void:
	if mode == Mode.MENU:
		return

	_mode_before_menu = mode
	var old_mode := mode
	mode = Mode.MENU
	get_tree().paused = true # пауза выставляется ДО сигнала
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	mode_changed.emit(old_mode, Mode.MENU)
	print("[PlayerState] Mode: %s → MENU (paused)" % Mode.keys()[old_mode])


func close_menu() -> void:
	if mode != Mode.MENU:
		return

	get_tree().paused = false # снимаем паузу ДО сигнала
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if view_mode == ViewMode.TPS else Input.MOUSE_MODE_VISIBLE
	var restored := _mode_before_menu
	mode = restored
	mode_changed.emit(Mode.MENU, restored)
	print("[PlayerState] Mode: MENU → %s (unpaused)" % Mode.keys()[restored])


func set_view_mode(new_view: ViewMode) -> void:
	if new_view == view_mode:
		return
	var old_view := view_mode
	view_mode = new_view
	view_mode_changed.emit(old_view, new_view)
	
	# Mouse mode: captured in TPS, visible in ISOMETRIC
	match new_view:
		ViewMode.TPS:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		ViewMode.ISOMETRIC:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Удобный геттер для проверки "можно ли сейчас двигаться игроку ногами"
func is_on_foot() -> bool:
	return mode == Mode.ON_FOOT
