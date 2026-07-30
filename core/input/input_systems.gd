# =============================================================================
# InputSystems.gd — autoload, extends Node.
#
# Единственная ответственность: превращать физический Input Godot в сигналы.
# НИКАКОЙ игровой логики здесь быть не должно:
#   - не решает, что означает нажатие (это дело подписчика);
#   - не хранит режим игрока (источник истины — PlayerState.mode/view_mode);
#   - не делает рейкасты, не двигает игрока, не открывает UI.
#
# Кто на что подписывается и когда — решает сам подписчик, реагируя на
# PlayerState.mode_changed / view_mode_changed. InputSystems эмитит сигналы
# безусловно, всегда.
# =============================================================================
extends Node

## --- Клик мышью (сырые события, без интерпретации "что это значит") ---
signal primary_click_pressed(screen_pos: Vector2)
signal primary_click_released(screen_pos: Vector2)

signal secondary_click_pressed(screen_pos: Vector2)
signal secondary_click_held(screen_pos: Vector2, duration: float)
signal secondary_click_released(screen_pos: Vector2)



## --- Interact ---
## Прототип-эксперимент с hold-таймером на Interact убран (был не тем,
## что нужно по факту — держать R ~1 сек как отдельный action).
## Пока просто пробрасываем just_pressed. Hold-механику вернём отдельной
## задачей, когда будет ясна финальная задумка.
signal interact_pressed()

## --- Хоткеи UI (пока без потребителей — просто транслируются) ---
signal pause_pressed()
signal status_pressed()
signal inventory_pressed()
signal crafting_pressed()
signal map_pressed()
## Тумблер дебаг-панели стриминга (action "toggle_stream_debug").
signal stream_debug_toggled()
## Тумблер дебаг-панели восприятия NPC (action "toggle_perception_debug").
signal perception_debug_toggled()

## Тап/холд по "toggle_tabs" — тайминг нажатия это свойство физического
## ввода, поэтому таймер живёт здесь, а не в потребителе.
signal tabs_key_tapped()
signal tabs_key_held()

## ── Маршрутизация interact ──────────────────────────────────────────────
## Пока claim удерживается (игрок в зоне двери ховера или на борту),
## interact уходит владельцу claim напрямую, сигнал interact_pressed
## НЕ излучается — InteractComponent в это время слеп. Один владелец
## решения вместо гонки подписчиков.
var _interact_claimant: Node = null

const TABS_HOLD_TIME: float = 0.5
const RUN_TRIGGER_TIME: float = 0.5

var _tabs_pressed_time: float = 0.0
var _tabs_pressing: bool = false

var _secondary_click_duration: float = 0.0
var _secondary_click_active: bool = false

# --- Mouse Look ---
## Sensitivity baked in here so consumers get camera-ready deltas.
const MOUSE_SENSITIVITY: float = 0.003

var _mouse_look_delta: Vector2 = Vector2.ZERO
var _frame_look_delta: Vector2 = Vector2.ZERO


func _ready() -> void:
	# ALWAYS — иначе после PlayerState.open_menu() (get_tree().paused = true)
	# этот autoload перестанет получать _unhandled_input и Escape не сработает.
	process_mode = Node.PROCESS_MODE_ALWAYS
	PlayerState.mode_changed.connect(_on_player_mode_changed)
	PlayerState.view_mode_changed.connect(_on_player_view_mode_changed)
	_apply_mouse_mode()

func _input(event: InputEvent) -> void:
	if PlayerState.mode == PlayerState.Mode.MENU:
		return
	if event is InputEventMouseMotion:
		_mouse_look_delta += event.relative * MOUSE_SENSITIVITY

## Escape ("pause") ловим отдельно от физики — работает независимо от
## текущей паузы и режима. Само решение что делать по этому сигналу —
## у MenuSystem, InputSystems лишь оповещает.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		pause_pressed.emit()
		get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	if PlayerState.mode == PlayerState.Mode.MENU:
		_frame_look_delta = Vector2.ZERO
		_mouse_look_delta = Vector2.ZERO
	else:
		_frame_look_delta = _mouse_look_delta
		_mouse_look_delta = Vector2.ZERO
	
	_handle_interact()
	_handle_primary_click()
	_handle_secondary_click(delta)
	_handle_tabs_key(delta)
	_handle_ui_hotkeys()


## ============================================
## MOUSE MODE — cursor visibility/capture is a physical Input.* effect, so it
## is applied here, driven by PlayerState.mode/view_mode rather than read from them.
## ============================================
func _on_player_mode_changed(_old_mode: PlayerState.Mode, _new_mode: PlayerState.Mode) -> void:
	_apply_mouse_mode()

func _on_player_view_mode_changed(_old_view: PlayerState.ViewMode, _new_view: PlayerState.ViewMode) -> void:
	_apply_mouse_mode()

func _apply_mouse_mode() -> void:
	if PlayerState.mode == PlayerState.Mode.MENU:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if PlayerState.view_mode == PlayerState.ViewMode.TPS \
			else Input.MOUSE_MODE_VISIBLE


## ============================================
## INTERACT
## ============================================
func _handle_interact() -> void:
	if Input.is_action_just_pressed("interact"):
		if is_instance_valid(_interact_claimant):
			_interact_claimant.on_interact_claimed()
		else:
			interact_pressed.emit()
		
func claim_interact(claimant: Node) -> void:
	_interact_claimant = claimant

func release_interact(claimant: Node) -> void:
	if _interact_claimant == claimant:
		_interact_claimant = null


## ============================================
## КЛИКИ МЫШЬЮ
## ============================================
func _handle_primary_click() -> void:
	if Input.is_action_just_pressed("mouse_left_button"):
		primary_click_pressed.emit(get_viewport().get_mouse_position())
	if Input.is_action_just_released("mouse_left_button"):
		primary_click_released.emit(get_viewport().get_mouse_position())


func _handle_secondary_click(delta: float) -> void:
	if Input.is_action_just_pressed("mouse_right_button"):
		_secondary_click_duration = 0.0
		_secondary_click_active = true
		secondary_click_pressed.emit(get_viewport().get_mouse_position())

	if Input.is_action_pressed("mouse_right_button") and _secondary_click_active:
		_secondary_click_duration += delta
		secondary_click_held.emit(get_viewport().get_mouse_position(), _secondary_click_duration)

	if Input.is_action_just_released("mouse_right_button"):
		_secondary_click_active = false
		_secondary_click_duration = 0.0
		secondary_click_released.emit(get_viewport().get_mouse_position())


## ============================================
## TABS KEY (тап = notifier, холд = status-camera) — интерпретацию тапа/
## холда потребитель делает сам, мы просто различаем их по таймингу.
## ============================================
func _handle_tabs_key(delta: float) -> void:
	if Input.is_action_just_pressed("toggle_tabs"):
		_tabs_pressed_time = 0.0
		_tabs_pressing = true

	if _tabs_pressing:
		_tabs_pressed_time += delta
		if Input.is_action_just_released("toggle_tabs"):
			if _tabs_pressed_time < TABS_HOLD_TIME:
				tabs_key_tapped.emit()
			else:
				tabs_key_held.emit()
			_tabs_pressing = false


## ============================================
## ПРОЧИЕ UI-ХОТКЕИ
## ============================================
func _handle_ui_hotkeys() -> void:
	if Input.is_action_just_pressed("status"):
		status_pressed.emit()
	if Input.is_action_just_pressed("inventory"):
		inventory_pressed.emit()
	if Input.is_action_just_pressed("map"):
		map_pressed.emit()
	if Input.is_action_just_pressed("toggle_stream_debug"):
		stream_debug_toggled.emit()
	if Input.is_action_just_pressed("toggle_perception_debug"):
		perception_debug_toggled.emit()


## ============================================
## QUERY-МЕТОДЫ — для мест, где сигнальная модель не подходит напрямую
## (камера читает ввод в своём собственном update(delta), которым управляет
## хост camera_follow.gd, а не физический кадр InputSystems; WASD/Shift —
## per-frame held-состояние, а не дискретное событие). Раньше эти места
## звали Input.* напрямую — теперь физически весь Input.* вызывается
## только здесь, в InputSystems, а потребители зовут эти обёртки.
## ============================================

## --- Камера (on_foot_camera_component.gd) ---
func is_toggle_follow_just_pressed() -> bool:
	return Input.is_action_just_pressed("toggle_follow")

func is_toggle_view_just_pressed() -> bool:
	return Input.is_action_just_pressed("toggle_view")

func is_lean_left_just_pressed() -> bool:
	return Input.is_action_just_pressed("lean_left")

func is_lean_right_just_pressed() -> bool:
	return Input.is_action_just_pressed("lean_right")

func is_zoom_in_just_released() -> bool:
	return Input.is_action_just_released("zoom_in")

func is_zoom_out_just_released() -> bool:
	return Input.is_action_just_released("zoom_out")


## --- Прыжок (player.gd + dynamic_cursor_ui.gd) ---
func is_jump_just_pressed() -> bool:
	return Input.is_action_just_pressed("jump")

func is_jump_held() -> bool:
	return Input.is_action_pressed("jump")


## --- Движение TPS (tps_movement_system.gd) ---
func get_move_axis() -> Vector2:
	return Input.get_vector("move_left", "move_right", "move_forward", "move_backward")

func is_sprint_held() -> bool:
	return Input.is_action_pressed("sprint")
	
func is_lock_on_just_pressed() -> bool:
	return Input.is_action_just_pressed("lock_on")
	
func is_switch_shoulder_just_pressed() -> bool:
	return Input.is_action_just_pressed("switch_shoulder")

## Горизонтальные намерения: x = вправо, y = вперёд (+1), длина ≤ 1.
func get_move_vector() -> Vector2:
	return Input.get_vector("move_left", "move_right",
			"move_backward", "move_forward")

## Вертикальная ось ховера: +1 вверх (hover_up), −1 вниз (hover_down).
func get_hover_vertical_axis() -> float:
	return Input.get_axis("hover_down", "hover_up")
	
## --- Mouse look (TPS/FPS camera control) ---
func get_look_delta() -> Vector2:
	return _frame_look_delta
