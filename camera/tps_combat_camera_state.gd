# =============================================================================
# tps_combat_camera_state.gd
# Под-состояние TPS-камеры внутри OnFootCameraComponent: Explore ↔ Locked.
# НЕ Node — просто держатель состояния, вызывается из update() хоста.
#
# Explore: TLOU-стиль — spring-damper lag + procedural breathing/sway.
# Locked:  Souls-стиль — фиксация на цели, orbit вокруг weighted pivot.
#
# TODO: сейчас поиск цели идёт через get_nodes_in_group("lockable") —
# когда появится RaycastService, заменить _find_best_target() на
# occlusion-aware версию (сейчас occlusion не проверяется вообще).
# =============================================================================
extends RefCounted
class_name TpsCombatCameraState

enum TpsState { EXPLORE, LOCKED, TRANSITION }

signal target_locked(target: Node3D)
signal target_lost()

var state: TpsState = TpsState.EXPLORE
var locked_target: Node3D = null

# --- Explore: spring-damper for yaw only, not for position — position is
# smoothed in _update_camera_position, at TPS_FOLLOW_SPEED once settled in
# steady-state TPS, or at view_transition_speed during the ISOMETRIC <->
# TPS transition animation. ---
@export var explore_spring_stiffness: float = 10.0
@export var explore_spring_damping: float = 6.0
var _yaw_velocity: float = 0.0

# --- Breathing / sway ---
@export var breathing_amplitude_deg: float = 0.4
@export var breathing_speed: float = 0.6
var _noise := FastNoiseLite.new()
var _noise_time: float = 0.0
## Внешний "уровень напряжения" 0..1 — подключишь позже к health/stamina.
## Пока просто публичное поле, которое можно дёргать откуда угодно.
var tension: float = 0.0

# --- Locked: pivot weighting ---
@export var player_pivot_weight: float = 0.65
@export var lock_distance_min: float = 4.0
@export var lock_distance_max: float = 8.0
@export var lock_search_radius: float = 15.0
@export var lock_search_angle_deg: float = 70.0  # конус перед игроком

# --- Transition ---
@export var transition_duration: float = 0.35
var _transition_time: float = 0.0
var _transition_from_state: TpsState = TpsState.EXPLORE


func _init() -> void:
	_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_noise.frequency = breathing_speed


## Вызывается из OnFootCameraComponent при нажатии кнопки lock-on.
## TODO: сейчас читает Input напрямую — перенести чтение кнопки в
## InputSystems (is_lock_on_just_pressed()), как у остальных инпутов проекта.
func try_toggle_lock(player: Node3D) -> void:
	if state == TpsState.LOCKED:
		_clear_lock()
		return

	var target := _find_best_target(player)
	if target == null:
		return

	locked_target = target
	_start_transition(TpsState.LOCKED)
	target_locked.emit(target)


func _clear_lock() -> void:
	locked_target = null
	_start_transition(TpsState.EXPLORE)
	target_lost.emit()


## Групповой скан-заглушка. Все "лочимые" враги должны быть в группе
## "lockable" (add_to_group в их скрипте). Скоринг: угол к центру экрана
## важнее чистого расстояния, устойчивость к дребезгу цели не реализована —
## это первое, что добавить, когда появятся жалобы на "прыгающий" lock.
func _find_best_target(player: Node3D) -> Node3D:
	var candidates := player.get_tree().get_nodes_in_group("lockable")
	var forward := -player.global_transform.basis.z
	var best_score := -INF
	var best: Node3D = null

	for c in candidates:
		if not (c is Node3D):
			continue
		var to_target: Vector3 = c.global_position - player.global_position
		var dist := to_target.length()
		if dist > lock_search_radius or dist < 0.01:
			continue

		var dir := to_target.normalized()
		var angle := rad_to_deg(forward.angle_to(dir))
		if angle > lock_search_angle_deg:
			continue

		# Чем меньше угол и чем ближе — тем выше score. Угол весит больше.
		var score := (1.0 - angle / lock_search_angle_deg) * 0.7 \
				+ (1.0 - dist / lock_search_radius) * 0.3
		if score > best_score:
			best_score = score
			best = c

	return best


## Read-only diagnostic for the lock-on debug overlay
## (ui/debug/stream_debug_panel.gd) — never call this from code that decides
## anything. Deliberately a separate scan, not a refactor of
## _find_best_target(): finds the single nearest "lockable" node by raw
## distance (regardless of angle) and reports which check would reject it,
## so the overlay can show "why" even when nothing would actually lock.
##
## NOTE: this intentionally uses the SAME forward vector _find_best_target()
## uses, whatever that currently is (bug included), so the overlay reflects
## what the real targeting code does. If that forward vector ever changes,
## update it here too in the same commit.
func get_lock_on_diagnostic(player: Node3D) -> Dictionary:
	var candidates := player.get_tree().get_nodes_in_group("lockable")
	var result := {
		"lockable_count": candidates.size(),
		"nearest_name": "",
		"distance": 0.0,
		"angle_deg": 0.0,
		"rejected_by": "none",   # "none" = no candidates, "radius", "cone", "" = would pass
		"forward": Vector3.ZERO,
		"to_nearest": Vector3.ZERO,
	}
	if candidates.is_empty():
		return result

	var forward := -player.global_transform.basis.z
	result.forward = forward

	var nearest: Node3D = null
	var nearest_dist := INF
	for c in candidates:
		if not (c is Node3D):
			continue
		var dist := player.global_position.distance_to(c.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = c

	if nearest == null:
		return result

	var to_target: Vector3 = nearest.global_position - player.global_position
	var dir := to_target.normalized() if nearest_dist > 0.001 else Vector3.ZERO
	var angle := rad_to_deg(forward.angle_to(dir))

	result.nearest_name = nearest.name
	result.distance = nearest_dist
	result.angle_deg = angle
	result.to_nearest = dir

	if nearest_dist > lock_search_radius:
		result.rejected_by = "radius"
	elif angle > lock_search_angle_deg:
		result.rejected_by = "cone"
	else:
		result.rejected_by = ""   # would pass both checks

	return result


func _start_transition(to_state: TpsState) -> void:
	_transition_from_state = state
	_transition_time = 0.0
	state = TpsState.TRANSITION
	_pending_target_state = to_state

var _pending_target_state: TpsState = TpsState.EXPLORE


## Возвращает (yaw, pitch_override, distance_override, is_pitch_locked).
## OnFootCameraComponent сам решает, как это применить к camera_target_*.
func update(delta: float, player: Node3D, current_yaw: float) -> Dictionary:
	match state:
		TpsState.TRANSITION:
			_transition_time += delta
			var t: float = clamp(_transition_time / transition_duration, 0.0, 1.0)
			var te = t * t * (3.0 - 2.0 * t)
			if _transition_time >= transition_duration:
				state = _pending_target_state
			return _blend_result(player, current_yaw, te)

		TpsState.LOCKED:
			if locked_target == null or not is_instance_valid(locked_target):
				_clear_lock()
				return _explore_result(player, current_yaw, delta)
			return _locked_result(player, current_yaw)

		_:
			return _explore_result(player, current_yaw, delta)


func _explore_result(player: Node3D, current_yaw: float, delta: float) -> Dictionary:
	var target_yaw := player.rotation.y + PI

	# Spring-damper вместо чистого lerp — даёт вязкость, а не резину.
	var diff := wrapf(target_yaw - current_yaw, -PI, PI)
	var accel := diff * explore_spring_stiffness - _yaw_velocity * explore_spring_damping
	_yaw_velocity += accel * delta
	var new_yaw := current_yaw + _yaw_velocity * delta

	# Breathing: небольшой шум по pitch, амплитуда растёт с tension.
	_noise_time += delta
	var sway := _noise.get_noise_1d(_noise_time * 20.0) * breathing_amplitude_deg * (0.4 + tension)

	return {
		"yaw": new_yaw,
		"pitch_offset_deg": sway,
		"distance_override": -1.0,  # -1 = не переопределять
	}


func _locked_result(player: Node3D, _current_yaw: float) -> Dictionary:
	var pivot := player.global_position.lerp(
			locked_target.global_position, 1.0 - player_pivot_weight)
	var to_pivot := pivot - player.global_position
	var desired_yaw := atan2(to_pivot.x, to_pivot.z) + PI

	# Дистанция авто-подстраивается под расстояние до цели, зажатая в диапазон.
	var dist_to_target := player.global_position.distance_to(locked_target.global_position)
	var distance: float = clamp(dist_to_target * 0.8, lock_distance_min, lock_distance_max)

	return {
		"yaw": desired_yaw,
		"pitch_offset_deg": 0.0,
		"distance_override": distance,
	}


func _blend_result(player: Node3D, current_yaw: float, te: float) -> Dictionary:
	var from_res: Dictionary
	var to_res: Dictionary

	if _transition_from_state == TpsState.LOCKED:
		from_res = _locked_result(player, current_yaw) if is_instance_valid(locked_target) else _explore_result(player, current_yaw, 0.0)
	else:
		from_res = _explore_result(player, current_yaw, 0.0)

	if _pending_target_state == TpsState.LOCKED and is_instance_valid(locked_target):
		to_res = _locked_result(player, current_yaw)
	else:
		to_res = _explore_result(player, current_yaw, 0.0)

	var blended_yaw := lerp_angle(from_res.yaw, to_res.yaw, te)
	var blended_pitch: float = lerp(
	float(from_res.pitch_offset_deg),
	float(to_res.pitch_offset_deg),
	te
)
	var blended_dist: float = float(from_res.distance_override)
	if to_res.distance_override > 0.0:
		var from_dist = from_res.distance_override if from_res.distance_override > 0.0 else lock_distance_max
		blended_dist = lerp(from_dist, to_res.distance_override, te)

	return {
		"yaw": blended_yaw,
		"pitch_offset_deg": blended_pitch,
		"distance_override": blended_dist,
	}
