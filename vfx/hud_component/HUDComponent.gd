extends Node3D
class_name HUDComponent

@onready var target_indicator: TargetIndicator = $TargetIndicator

func _ready() -> void:
	InputSystems.move_target_requested.connect(_on_move_target_requested)
	InputSystems.move_target_invalid.connect(_on_move_target_invalid)
	InputSystems.move_target_cleared.connect(_on_move_target_cleared)
	InputSystems.player_registered.connect(_on_player_registered)
	InputSystems.player_unregistered.connect(_on_player_unregistered)

	PlayerState.mode_changed.connect(_on_player_state_changed)
	PlayerState.view_mode_changed.connect(_on_player_state_changed)

func _exit_tree() -> void:
	if InputSystems.move_target_requested.is_connected(_on_move_target_requested):
		InputSystems.move_target_requested.disconnect(_on_move_target_requested)
	if InputSystems.move_target_invalid.is_connected(_on_move_target_invalid):
		InputSystems.move_target_invalid.disconnect(_on_move_target_invalid)
	if InputSystems.move_target_cleared.is_connected(_on_move_target_cleared):
		InputSystems.move_target_cleared.disconnect(_on_move_target_cleared)
	if InputSystems.player_registered.is_connected(_on_player_registered):
		InputSystems.player_registered.disconnect(_on_player_registered)
	if InputSystems.player_unregistered.is_connected(_on_player_unregistered):
		InputSystems.player_unregistered.disconnect(_on_player_unregistered)
	if PlayerState.mode_changed.is_connected(_on_player_state_changed):
		PlayerState.mode_changed.disconnect(_on_player_state_changed)
	if PlayerState.view_mode_changed.is_connected(_on_player_state_changed):
		PlayerState.view_mode_changed.disconnect(_on_player_state_changed)

## 🔑 Индикатор клика по земле имеет смысл ТОЛЬКО пешком (ON_FOOT)
## и только в ISOMETRIC/TOPDOWN — там навигация идёт кликом по земле.
## В TPS движение прямое (WASD), клик-инди не нужен; в VEHICLE_HOVER/
## TUBE_TRANSIT/MENU управление другое — виджет тоже не нужен.
func _is_active_mode() -> bool:
	if PlayerState.mode != PlayerState.Mode.ON_FOOT:
		return false
	return PlayerState.view_mode in [PlayerState.ViewMode.ISOMETRIC, PlayerState.ViewMode.TOPDOWN]

## Единый обработчик — сигнатуры mode_changed(old, new) и
## view_mode_changed(old, new) совпадают, поэтому можно использовать один.
func _on_player_state_changed(_old, _new) -> void:
	if not _is_active_mode() and target_indicator:
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
