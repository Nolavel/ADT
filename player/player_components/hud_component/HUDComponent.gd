extends Node3D
class_name HUDComponent

@onready var target_indicator: TargetIndicator = $TargetIndicator

func _ready() -> void:
	InputSystems.move_target_requested.connect(_on_move_target_requested)
	InputSystems.move_target_invalid.connect(_on_move_target_invalid)
	InputSystems.move_target_cleared.connect(_on_move_target_cleared)
	InputSystems.control_mode_changed.connect(_on_control_mode_changed)
	InputSystems.player_registered.connect(_on_player_registered)
	InputSystems.player_unregistered.connect(_on_player_unregistered)

func _exit_tree() -> void:
	if InputSystems.move_target_requested.is_connected(_on_move_target_requested):
		InputSystems.move_target_requested.disconnect(_on_move_target_requested)
	if InputSystems.move_target_invalid.is_connected(_on_move_target_invalid):
		InputSystems.move_target_invalid.disconnect(_on_move_target_invalid)
	if InputSystems.move_target_cleared.is_connected(_on_move_target_cleared):
		InputSystems.move_target_cleared.disconnect(_on_move_target_cleared)
	if InputSystems.control_mode_changed.is_connected(_on_control_mode_changed):
		InputSystems.control_mode_changed.disconnect(_on_control_mode_changed)
	if InputSystems.player_registered.is_connected(_on_player_registered):
		InputSystems.player_registered.disconnect(_on_player_registered)
	if InputSystems.player_unregistered.is_connected(_on_player_unregistered):
		InputSystems.player_unregistered.disconnect(_on_player_unregistered)

func _is_active_mode() -> bool:
	## 🔑 Индикатор клика по земле имеет смысл ТОЛЬКО в режиме Player.
	## Flycar/Tube управляются иначе — там этот виджет не нужен.
	return InputSystems.current_control_mode == InputSystems.ControlMode.PLAYER

func _on_control_mode_changed(new_mode: InputSystems.ControlMode) -> void:
	if new_mode != InputSystems.ControlMode.PLAYER and target_indicator:
		target_indicator.hide_indicator()

func _on_move_target_requested(pos: Vector3, is_running: bool) -> void:
	if not _is_active_mode():
		return
	if target_indicator:
		target_indicator.show_at_position(pos, is_running)

func _on_move_target_invalid(pos: Vector3) -> void:
	if not _is_active_mode():
		return
	if target_indicator and pos != Vector3.ZERO:
		target_indicator.show_invalid_click(pos)

func _on_move_target_cleared() -> void:
	if target_indicator:
		target_indicator.hide_indicator()

func _on_player_registered(p: CharacterBody3D) -> void:
	if target_indicator:
		target_indicator.set_player_reference(p)

func _on_player_unregistered() -> void:
	if target_indicator:
		target_indicator.set_player_reference(null)
