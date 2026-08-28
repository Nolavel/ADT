extends Node3D
class_name HUDComponent

@onready var target_indicator: TargetIndicator = $TargetIndicator
## Second indicator, same class, different role: the object the player is
## currently aimed at. A separate node rather than a second mode on the one
## above, because in ISOMETRIC "where I am walking" and "what I am reaching
## for" can be on screen at the same time and one node would have to choose.
@onready var candidate_indicator: TargetIndicator = $CandidateIndicator

var _click_to_move: ClickToMoveSystem
var _interact: InteractComponent = null

## Единая точка входа — та же сигнатура, что и у Node-систем в
## WORLD_SYSTEM_SCRIPTS, только здесь её вызывает цикл по
## WORLD_3D_ENTITY_SCENES в world.gd. ClickToMoveSystem достаём из
## context.get_system(), а не через singleton-доступ по имени класса.
func on_world_ready(context: WorldContext) -> void:
	_click_to_move = context.get_system(ClickToMoveSystem)
	if not _click_to_move:
		push_error("[HUDComponent] ClickToMoveSystem не найден в WorldContext.systems")
		return

	_click_to_move.move_target_requested.connect(_on_move_target_requested)
	_click_to_move.move_target_invalid.connect(_on_move_target_invalid)
	_click_to_move.move_target_cleared.connect(_on_move_target_cleared)
	_click_to_move.player_registered.connect(_on_player_registered)
	_click_to_move.player_unregistered.connect(_on_player_unregistered)

	## Reached through the player rather than through context.systems:
	## InteractComponent is a child of the player, not a world system. Same
	## route PlayerHUD uses for HealthComponent.
	if context.player:
		_interact = context.player.get_node_or_null("InteractComponent") as InteractComponent
	if _interact:
		_interact.interact_target_changed.connect(_on_interact_target_changed)
	else:
		push_warning("[HUDComponent] InteractComponent не найден — декаль кандидата не появится")

func _ready() -> void:
	## Only the move-destination one. The candidate decal is a different
	## statement and must not attract the walk icon.
	if target_indicator:
		target_indicator.add_to_group(TargetIndicator.GROUP_MOVE_TARGET)
	PlayerState.mode_changed.connect(_on_player_state_changed)
	PlayerState.view_mode_changed.connect(_on_player_state_changed)

func _exit_tree() -> void:
	if _click_to_move:
		if _click_to_move.move_target_requested.is_connected(_on_move_target_requested):
			_click_to_move.move_target_requested.disconnect(_on_move_target_requested)
		if _click_to_move.move_target_invalid.is_connected(_on_move_target_invalid):
			_click_to_move.move_target_invalid.disconnect(_on_move_target_invalid)
		if _click_to_move.move_target_cleared.is_connected(_on_move_target_cleared):
			_click_to_move.move_target_cleared.disconnect(_on_move_target_cleared)
		if _click_to_move.player_registered.is_connected(_on_player_registered):
			_click_to_move.player_registered.disconnect(_on_player_registered)
		if _click_to_move.player_unregistered.is_connected(_on_player_unregistered):
			_click_to_move.player_unregistered.disconnect(_on_player_unregistered)
	if _interact and _interact.interact_target_changed.is_connected(_on_interact_target_changed):
		_interact.interact_target_changed.disconnect(_on_interact_target_changed)
	if PlayerState.mode_changed.is_connected(_on_player_state_changed):
		PlayerState.mode_changed.disconnect(_on_player_state_changed)
	if PlayerState.view_mode_changed.is_connected(_on_player_state_changed):
		PlayerState.view_mode_changed.disconnect(_on_player_state_changed)

## 🔑 Индикатор клика по земле имеет смысл ТОЛЬКО пешком (ON_FOOT)
## и только в ISOMETRIC — там навигация идёт кликом по земле.
## В TPS движение прямое (WASD), клик-инди не нужен; в VEHICLE_HOVER/
## TUBE_TRANSIT/MENU управление другое — виджет тоже не нужен.
func _is_move_marker_active() -> bool:
	if PlayerState.mode != PlayerState.Mode.ON_FOOT:
		return false
	return PlayerState.view_mode == PlayerState.ViewMode.ISOMETRIC


## The candidate decal deliberately does NOT share that gate. Interacting is
## the same in both views — F reaches the same objects and walks the same
## way — so the only thing that disqualifies it is not being on foot at all.
func _is_candidate_active() -> bool:
	return PlayerState.mode == PlayerState.Mode.ON_FOOT

## Единый обработчик — сигнатуры mode_changed(old, new) и
## view_mode_changed(old, new) совпадают, поэтому можно использовать один.
func _on_player_state_changed(_old, _new) -> void:
	if not _is_move_marker_active() and target_indicator:
		target_indicator.hide_indicator()
	if not _is_candidate_active() and candidate_indicator:
		candidate_indicator.hide_indicator()

func _on_move_target_requested(pos: Vector3, is_running: bool) -> void:
	if not _is_move_marker_active():
		return
	if target_indicator:
		target_indicator.show_at_position(pos, is_running)

func _on_move_target_invalid(pos: Vector3) -> void:
	if not _is_move_marker_active():
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


## What the player is aimed at changed, or they crossed into arm's reach of
## the same thing. Null object means nothing is targeted and the decal goes
## away — including right after a pickup, since the object is freed and
## InteractComponent reports null on the next frame.
func _on_interact_target_changed(object: InteractableObject, in_reach: bool) -> void:
	if not candidate_indicator:
		return
	## is_instance_valid() rather than "== null": InteractComponent normalises
	## a freed target away, but a freed Object also compares equal to null, so
	## the two questions look identical and only one of them is unambiguous.
	if not is_instance_valid(object) or not _is_candidate_active():
		candidate_indicator.hide_indicator()
		return
	candidate_indicator.show_candidate(object.global_position, in_reach)
