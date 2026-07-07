# =============================================================================
# menu_system.gd — autoload.
#
# Владеет жизненным циклом сцены игрового паузного меню и решает,
# когда её открыть/закрыть. Единственный источник команды на toggle —
# сигнал InputSystems.pause_pressed (InputSystems сам ничего не решает,
# только сообщает "кнопка pause нажата").
#
# Сама сцена меню (in_game_menu.tscn / menu_controller.gd) реагирует
# на PlayerState.mode_changed напрямую и показывает/прячет себя — здесь
# её не дублируем, только инстанцируем один раз и переключаем PlayerState.
# =============================================================================
extends Node

const IN_GAME_MENU_SCENE: PackedScene = preload("res://ui/ingame_menu/in_game_menu.tscn")

var _menu_canvas_layer: CanvasLayer
var _menu_instance: Control


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_menu_canvas_layer = CanvasLayer.new()
	_menu_canvas_layer.layer = 50
	_menu_canvas_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.call_deferred("add_child", _menu_canvas_layer)

	_menu_instance = IN_GAME_MENU_SCENE.instantiate()
	_menu_instance.process_mode = Node.PROCESS_MODE_ALWAYS
	_menu_canvas_layer.call_deferred("add_child", _menu_instance)

	InputSystems.pause_pressed.connect(_on_pause_pressed)


func _on_pause_pressed() -> void:
	if PlayerState.mode == PlayerState.Mode.MENU:
		PlayerState.close_menu()
	else:
		PlayerState.open_menu()
