# =============================================================================
# camera_follow.gd
# Camera3D — хост. Держит саму камеру, слушает PlayerState.mode_changed
# и переключает активный компонент поведения (см. camera/components/).
# Shake применяется поверх результата активного компонента, как чистое
# аддитивное смещение (см. CameraShakeComponent) — сюда никогда не пишет
# напрямую ни один компонент.
#
# MENU обрабатывается отдельно от компонентов: камера просто плавно
# отъезжает в menu_pause_offset и замирает, пока PlayerState.mode == MENU,
# а при выходе возвращается туда, где был активный компонент.
#
# STATUS/INVENTORY/CRAFTING/MAP-состояния камеры убраны полностью
# (см. историю проекта) — будем пересматривать подход к ним отдельно позже.
# X-Ray-система убрана полностью.
#
# The scene sets physics_interpolation_mode = OFF on this node, and it has to
# stay off: this camera already smooths itself exponentially in _physics_process
# and then writes its own global_transform in _process (plus the additive shake),
# so the engine's interpolation on top would be a second smoother fighting the
# first — the transform it would blend from is one this file has already blended.
# =============================================================================
extends Camera3D

@export var target: Node3D

@export_group("MENU_PAUSE")
@export var menu_pause_offset: Vector3 = Vector3(0, 1.5, -5.0)
@export var menu_pause_pitch_deg: float = -7.5
@export var menu_pause_transition_duration: float = 0.6

@export_group("Shake")
@export var shake_enabled_in_game_only: bool = true
@export var shake_area: NodePath

@export var player_animation_player: AnimationPlayer

@onready var lbl_current_mode: Label = $CameraSettings/VBoxContainer/CurrentMode
@onready var lbl_orbital: Label = $CameraSettings/VBoxContainer/Orbital
@onready var lbl_follow: Label = $CameraSettings/VBoxContainer/Follow

# === Компоненты по PlayerState.Mode ===
var _on_foot: OnFootCameraComponent
var _hover: HoverCameraComponent
var _tube_transit: TubeTransitCameraComponent
var _active_component: Node

var _shake: CameraShakeComponent

## Публичный геттер. Единственный потребитель сегодня —
## ui/debug/stream_debug_panel.gd (состояние lock-on). Линейка зума, которая
## его завела, удалена вместе с изо-камерой.
func get_on_foot_component() -> OnFootCameraComponent:
	return _on_foot

# === MENU / переход между состояниями (только GAME <-> MENU_PAUSE) ===
enum CameraState { GAME, MENU_PAUSE }
var current_state: CameraState = CameraState.GAME
var saved_game_transform: Transform3D

var state_animating: bool = false
var state_anim_time: float = 0.0
var state_start_transform: Transform3D
var state_target_transform: Transform3D
var state_duration: float = 0.6


func _ready():
	projection = PROJECTION_PERSPECTIVE

	_on_foot = OnFootCameraComponent.new()
	_on_foot.camera = self
	_on_foot.lbl_current_mode = lbl_current_mode
	_on_foot.lbl_orbital = lbl_orbital
	_on_foot.lbl_follow = lbl_follow
	add_child(_on_foot)

	_hover = HoverCameraComponent.new()
	_hover.camera = self
	add_child(_hover)

	_tube_transit = TubeTransitCameraComponent.new()
	_tube_transit.camera = self
	add_child(_tube_transit)

	_shake = CameraShakeComponent.new()
	add_child(_shake)

	if shake_area:
		var area = get_node_or_null(shake_area)
		if area:
			area.shake_cam_process.connect(_on_shake_cam_process)
			area.stop_shake_cam_process.connect(_on_stop_shake_cam_process)
			print("✅ Камера подключена к Area3D для ShakeCam")

	PlayerState.mode_changed.connect(_on_player_state_mode_changed)
	_switch_active_component(PlayerState.mode)

	make_current()


func _process(delta):
	if not target:
		return

	# Меню-анимация и MENU_PAUSE — кадровые (визуальные твины), остаются здесь.
	if state_animating:
		_update_state_animation(delta)
		_apply_shake_on_top(delta)
		return

	if current_state == CameraState.MENU_PAUSE:
		global_transform = state_target_transform
		if not shake_enabled_in_game_only:
			_apply_shake_on_top(delta)
		return

	# GAME: следование камеры ушло в _physics_process (см. ниже).
	# Здесь в GAME только shake поверх уже посчитанной физикой трансформации.
	_apply_shake_on_top(delta)


func _physics_process(delta):
	if not target:
		return
	if state_animating or current_state == CameraState.MENU_PAUSE:
		return   # в эти состояния камера пишется из _process

	# Следование считаем в фиксированном такте — dt здесь всегда стабилен,
	# поэтому exp-сглаживание идёт ровными шагами (лог 2026-07-22: в _process
	# dt плясал 0.022↔0.032 и колбасил камеру на дистанции при гладкой цели).
	if _active_component and _active_component.has_method("update"):
		_active_component.update(delta)


## Shake считается ПОСЛЕ того как компонент/анимация уже посчитали базовую
## трансформацию камеры на этот кадр — поэтому shake не может накопиться
## и не может оставить смещение, если вдруг перестанет вызываться.
func _apply_shake_on_top(delta: float) -> void:
	_shake.update(delta)
	if not _shake.is_active():
		return
	global_position += _shake.get_offset()
	global_rotation += _shake.get_rotation_offset()


# ============================================
# ПЕРЕКЛЮЧЕНИЕ АКТИВНОГО КОМПОНЕНТА ПО PlayerState.Mode
# ============================================
func _switch_active_component(mode) -> void:
	if _active_component and _active_component.has_method("exit"):
		_active_component.exit()

	match mode:
		PlayerState.Mode.ON_FOOT:
			_active_component = _on_foot
		PlayerState.Mode.HOVER:
			_hover.target = PlayerState.current_hover
			_active_component = _hover
		PlayerState.Mode.TUBE_TRANSIT:
			_active_component = _tube_transit
		_:
			_active_component = null

	if _active_component and _active_component.has_method("enter"):
		_active_component.enter()


func _on_player_state_mode_changed(old_mode, new_mode) -> void:
	if new_mode == PlayerState.Mode.MENU:
		_transition_to_menu()
		if player_animation_player:
			player_animation_player.play("new3/legs_idle_2")
		return

	if old_mode == PlayerState.Mode.MENU:
		if player_animation_player:
			player_animation_player.play("new4/idle")
		_return_to_game()

	_switch_active_component(new_mode)


# ============================================
# УНИФИЦИРОВАННАЯ АНИМАЦИЯ GAME <-> MENU_PAUSE (25% - 50% - 25%)
# ============================================
func _update_state_animation(delta: float):
	state_anim_time += delta
	var t: float = 0.0
	var phase1 = state_duration * 0.33
	var phase2 = state_duration * 0.67

	if state_anim_time < phase1:
		var progress = state_anim_time / phase1
		t = progress * 0.25
	elif state_anim_time < phase2:
		var progress = (state_anim_time - phase1) / (phase2 - phase1)
		t = 0.25 + progress * 0.5
	elif state_anim_time < state_duration:
		var progress = (state_anim_time - phase2) / (state_duration - phase2)
		t = 0.75 + progress * 0.25
	else:
		t = 1.0
		state_animating = false

	var te = t * t * (3.0 - 2.0 * t)
	var interp_pos = state_start_transform.origin.lerp(state_target_transform.origin, te)
	var start_quat = Quaternion(state_start_transform.basis)
	var target_quat = Quaternion(state_target_transform.basis)
	var interp_quat = start_quat.slerp(target_quat, te)
	global_transform = Transform3D(Basis(interp_quat), interp_pos)

	if not state_animating:
		global_transform = state_target_transform


func _transition_to_menu() -> void:
	if current_state == CameraState.MENU_PAUSE:
		return

	saved_game_transform = global_transform
	current_state = CameraState.MENU_PAUSE

	var frozen_pos = target.global_position
	var frozen_yaw = target.rotation.y

	var local_offset = menu_pause_offset.rotated(Vector3.UP, frozen_yaw)
	var target_pos = frozen_pos + local_offset

	var rot = Basis()
	rot = rot.rotated(Vector3.RIGHT, deg_to_rad(menu_pause_pitch_deg))
	rot = rot.rotated(Vector3.UP, frozen_yaw + PI)

	state_start_transform = global_transform
	state_target_transform = Transform3D(rot, target_pos)
	state_anim_time = 0.0
	state_duration = menu_pause_transition_duration
	state_animating = true


func _return_to_game() -> void:
	if current_state == CameraState.GAME:
		return

	current_state = CameraState.GAME

	state_start_transform = global_transform
	state_target_transform = saved_game_transform
	state_anim_time = 0.0
	state_duration = 0.6
	state_animating = true


# ============================================
# CAMERA SHAKE — публичный API, делегирует в CameraShakeComponent
# ============================================
func _on_shake_cam_process(amplitude: float, time: float) -> void:
	if shake_enabled_in_game_only and current_state != CameraState.GAME:
		return
	_shake.start(amplitude, time)


func _on_stop_shake_cam_process() -> void:
	_shake.stop()


func add_impulse_shake(strength: float = 1.0) -> void:
	if shake_enabled_in_game_only and current_state != CameraState.GAME:
		return
	_shake.add_impulse(strength)


# ============================================
# ПУБЛИЧНОЕ API
# ============================================
func set_target_reference(p: Node3D) -> void:
	target = p
	if _on_foot:
		_on_foot.target = p
		_on_foot.setup()
	if _hover:
		_hover.target = p
	if _tube_transit:
		_tube_transit.target = p
	print("✅ SystemCamera: target назначен")
