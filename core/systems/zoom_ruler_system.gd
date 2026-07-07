# =============================================================================
# zoom_ruler_system.gd — обычная нода, братан click_to_move_system.gd /
# tps_movement_system.gd / menu_system.gd.
#
# Возврат к чисто программному построению (без .tscn) — заход через сцену
# спотыкался на артефактах сохранения в редакторе (терялся дочерний узел),
# которые я не могу проверить без самого Godot. Код строит CanvasLayer +
# Control руками через .new(), тем же паттерном, что MenuSystem строит
# CanvasLayer для меню — и с тем же самым фиксом: вешаем на реальный
# корень дерева (get_tree().root), а не на World (Node3D) напрямую.
# =============================================================================
extends Node
class_name ZoomRulerSystem

var _layer_instance: CanvasLayer
var _hud_instance: ZoomRulerHUD


func register_camera_component(on_foot_component: OnFootCameraComponent) -> void:
	if not _layer_instance:
		_spawn(on_foot_component)
	else:
		_hud_instance.setup(on_foot_component)


func _spawn(on_foot_component: OnFootCameraComponent) -> void:
	_layer_instance = CanvasLayer.new()
	_layer_instance.layer = 30
	get_tree().root.call_deferred("add_child", _layer_instance)

	_hud_instance = ZoomRulerHUD.new()
	_hud_instance.setup(on_foot_component)
	_layer_instance.call_deferred("add_child", _hud_instance)
