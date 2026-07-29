# =============================================================================
# on_foot_camera_component.gd
# Компонент камеры для PlayerState.Mode.ON_FOOT.
#
# Логика перенесена из старого монолитного camera_follow.gd БЕЗ ИЗМЕНЕНИЙ
# (orbital Q/E, TPS↔ISOMETRIC переключение V, follow P, zoom колесом) — по
# ничего здесь пока не чистим и не переделываем, только переносим.
#
# Компонент не Camera3D сам по себе — он получает ссылку на реальную
# камеру (camera) и на цель (target) от хоста и пишет прямо в
# camera.global_position/global_rotation, когда активен.
# =============================================================================
extends Node
class_name OnFootCameraComponent

## Единственный сигнал наружу про зум — HUD-виджеты (линейка) подписываются
## сюда вместо того, чтобы сами читать Input. _handle_zoom_input() —
## единственное законное место в проекте, где физически читается
## zoom_in/zoom_out.
signal zoom_input_received()

const MOUSE_SENSITIVITY: float = 1.0   # доп. множитель поверх InputSystems
## Not proportional to BODY_HEIGHT on purpose — camera distance is taste, not
## anatomy. Proportional to the old 2.6 @ 2.32m body would be ~2.02; 2.2 is
## visually tighter framing for this camera family.
const TPS_DISTANCE: float = 2.2
const TPS_PITCH_MIN: float = -50.0
const TPS_PITCH_MAX: float = 20.0
## Vertical look is deliberately slower than horizontal — the traditional
## "mouse Y feels heavier than mouse X" convention for TPS/FPS cameras.
const TPS_PITCH_SENSITIVITY_RATIO: float = 0.7

## Position follow rate in TPS, separate from view_transition_speed (which
## owns the ISOMETRIC <-> TPS transition animation). Steady-state lag behind
## a target moving at constant speed is roughly speed / this value.
const TPS_FOLLOW_SPEED: float = 16.0

## Extra camera distance at full run speed, on top of TPS_DISTANCE. Explicit
## and tunable — the previous pull-back was an accidental by-product of the
## follow-lag, not a setting. At run_speed, the residual TPS_FOLLOW_SPEED lag
## (~0.6m) plus this (0.4m) adds up to roughly 1.0m total, versus the ~2.5m
## the old shared-lag setup produced by accident.
const TPS_SPRINT_PULLBACK: float = 0.4
## How fast the pull-back follows a change of speed. Lower than the follow
## rate on purpose, so it eases in instead of snapping when the run starts.
const TPS_PULLBACK_SMOOTHING: float = 3.0

## Used only if `target` doesn't expose character-metric getters (see
## _target_metric_height()) — a safe non-zero default instead of silently
## pivoting/casting at ground level.
const TPS_PIVOT_HEIGHT_FALLBACK: float = 1.45
const TPS_OCCLUSION_HEIGHT_FALLBACK: float = 1.5

## Frustum-vs-translation split for the shoulder offset — picked visually, not
## derived. Frustum offset keeps the look axis centered on screen (needed for
## aiming); translation keeps some camera-plane parallax.
const TPS_SHOULDER_FRUSTUM_RATIO: float = 0.6
const TPS_SHOULDER_TRANSLATION_RATIO: float = 0.4
## Sign depends on which way `right` points on screen — verify by running the game.
const TPS_SHOULDER_H_OFFSET_SIGN: float = 1.0

## Runtime pitch accumulated from mouse look. Base tps_angle is the starting offset.
var _tps_pitch_deg: float = -10.0
## Pitch offset from TpsCombatCameraState (explore sway / lock-on), added on top of _tps_pitch_deg.
var _tps_pitch_offset_deg: float = 0.0
## Set once _target_metric_height() has warned about a target with no
## character-metric getters, so the warning doesn't spam every frame.
var _warned_missing_target_metrics: bool = false
## Set once _target_speed_ratio() has warned about a target with no
## get_speed_ratio(), so the warning doesn't spam every frame.
var _warned_missing_speed_ratio: bool = false
## Smoothed sprint pull-back distance, eased toward speed_ratio *
## TPS_SPRINT_PULLBACK at TPS_PULLBACK_SMOOTHING. Only updated while in TPS
## (see _update_camera_position) — frozen at its last value otherwise, and
## resumes lerping toward the current ratio when TPS is re-entered.
var _tps_sprint_pullback: float = 0.0

@export var rotation_speed: float = 8.0

@export_group("Orbit")
@export var orbit_distance: float = 20.0
@export var orbit_height: float = 15.0
@export var camera_angle: float = -35.0

@export_group("View Transition")
@export var view_transition_speed: float = 4.0

@export_group("TPS View")
## Плейсхолдер — подобрать по месту, главное сохранена логика возврата в ISOMETRIC.
@export var tps_angle: float = -10.0


@export_group("Follow")
@export var follow_rotation_damping: float = 3.0
@export var follow_rotation_delay: float = 0.2

## --- Ссылки, назначаются хостом перед enter() ---
var camera: Camera3D
var target: Node3D

## --- Опциональные лейблы для дебага (назначаются хостом, могут быть null) ---
var lbl_current_mode: Label
var lbl_orbital: Label
var lbl_follow: Label

var follow_player_rotation: bool = false

# === ORBITAL SYSTEM ===
enum OrbitalPosition { NORTH, EAST, SOUTH, WEST }
const ORBITAL_POSITIONS = [OrbitalPosition.NORTH, OrbitalPosition.EAST, OrbitalPosition.SOUTH, OrbitalPosition.WEST]
const POSITION_ANGLES = {
	OrbitalPosition.NORTH: 0.0,
	OrbitalPosition.EAST: PI / 2,
	OrbitalPosition.SOUTH: PI,
	OrbitalPosition.WEST: 3 * PI / 2
}
var current_position: OrbitalPosition = OrbitalPosition.NORTH
var target_angle: float = 0.0
var current_angle: float = 0.0
var player_rotation_timer: float = 0.0
var last_player_rotation: float = 0.0

## Единственный источник истины о текущем виде — PlayerState.view_mode.
## Никакого параллельного bool/enum здесь больше не хранится.

var camera_target_pos: Vector3
var camera_current_pos: Vector3
var camera_target_pitch: float
var camera_current_pitch: float
var camera_target_yaw: float
var camera_current_yaw: float

# === ZOOM SYSTEM ===
# Единый "слайдер" через цепочку TPS ↔ ISOMETRIC.
# TOPDOWN убран (см. заметку в идейнике Miro) — на ON_FOOT остаются
# только TPS и ISOMETRIC.
# Внутри каждого режима — свой диапазон дистанции; переход между режимами
# происходит через V только когда зум упёрся в соответствующий край.
var current_zoom_distance: float = 0.0
var target_zoom_distance: float = 0.0
var zoom_animating: bool = false
var zoom_anim_time: float = 0.0
var zoom_start_distance: float = 0.0

const ISOMETRIC_ZOOM_MIN: float = 10.0   # ближний край (приблизили до упора) → V → TPS
const ISOMETRIC_ZOOM_MAX: float = 17.5   # дальний край — просто предел зума, без перехода
const TPS_ZOOM_MIN: float = 3.0          # дальше некуда, тупик (продолжение приближения)
const TPS_ZOOM_MAX: float = 6.0          # дальний край → V → назад в ISOMETRIC
const ZOOM_STEP: float = 2.5
const ZOOM_EDGE_EPSILON: float = 0.05    # допуск сравнения "упёрлись ли в край"

# === ORBITAL ROTATION (Q/E) ===
var orbit_rotation_animating: bool = false
var orbit_anim_time: float = 0.0
var orbit_start_angle: float = 0.0
var orbit_target_angle: float = 0.0

# === VIEW MODE SWITCHING (V) ===
var view_mode_animating: bool = false
var view_anim_time: float = 0.0
var view_start_distance: float = 0.0
var view_target_distance: float = 0.0
var view_start_pitch: float = 0.0
var view_target_pitch: float = 0.0

# === FOLLOW ROTATION (P) ===
var follow_rotation_animating: bool = false
var follow_anim_time: float = 0.0
var follow_start_angle: float = 0.0
var follow_target_angle: float = 0.0


var _tps_combat := TpsCombatCameraState.new()
var _shoulder := TpsShoulderCameraState.new()

## Вызывается хостом один раз перед первым использованием (camera/target уже назначены).
func setup() -> void:
	current_angle = POSITION_ANGLES[current_position]
	target_angle = current_angle
	camera_target_pitch = camera_angle
	camera_current_pitch = camera_angle
	camera_target_yaw = current_angle
	camera_current_yaw = current_angle
	camera_target_pos = camera.global_position
	camera_current_pos = camera.global_position
	current_zoom_distance = orbit_distance
	target_zoom_distance = orbit_distance
	
	_tps_pitch_deg = tps_angle


## Вызывается хостом при входе в ON_FOOT (в т.ч. при возврате из MENU).
func enter() -> void:
	camera_current_pos = camera.global_position


func exit() -> void:
	pass


func update(delta: float) -> void:
	if not target:
		return

	var view := PlayerState.view_mode

	_handle_zoom_input()
	_handle_view_toggle()

	if view == PlayerState.ViewMode.TPS:
		# В TPS камера всегда позади игрока — orbit (Q/E) и toggle_follow (P)
		# здесь не действуют, это не их зона ответственности.
		_handle_tps_follow(delta)
		_handle_shoulder_toggle()
	else:
		_handle_follow_toggle()
		if follow_player_rotation:
			_handle_follow_rotation(delta)
		else:
			_handle_rotation_input()

	_update_zoom_animation(delta)
	_update_orbit_rotation_animation(delta)
	_update_view_mode_animation(delta)
	_update_follow_rotation_animation(delta)

	if not orbit_rotation_animating and not follow_rotation_animating:
		current_angle = lerp_angle(current_angle, target_angle, delta * rotation_speed)

	_update_camera_position(delta)
	
	_update_labels()


func _handle_tps_follow(delta: float) -> void:
	# --- Free mouse look (TLOU-style) ---
	# `look` (InputSystems.get_look_delta()) is in radians — camera_target_yaw
	# is also radians, so it can be added directly. _tps_pitch_deg is stored
	# in DEGREES (clamped by TPS_PITCH_MIN/MAX, fed to deg_to_rad() later), so
	# it needs an explicit rad_to_deg() conversion — this mismatch was the bug
	# that made vertical look nearly unresponsive.
	var look := InputSystems.get_look_delta()
	camera_target_yaw += look.x * MOUSE_SENSITIVITY
	camera_target_yaw = wrapf(camera_target_yaw, -PI, PI)
	_tps_pitch_deg -= rad_to_deg(look.y) * MOUSE_SENSITIVITY * TPS_PITCH_SENSITIVITY_RATIO
	_tps_pitch_deg = clamp(_tps_pitch_deg, TPS_PITCH_MIN, TPS_PITCH_MAX)

	# --- Lock-on (combat state overrides yaw only when locked) ---
	if InputSystems.is_lock_on_just_pressed():
		_tps_combat.try_toggle_lock(target)

	var result := _tps_combat.update(delta, target, camera_target_yaw)
	_tps_pitch_offset_deg = result.pitch_offset_deg
	if _tps_combat.state == TpsCombatCameraState.TpsState.LOCKED:
		# distance is fixed in TPS — ignore combat distance_override
		camera_target_yaw = result.yaw


func _update_zoom_animation(delta: float):
	if not zoom_animating:
		return

	zoom_anim_time += delta
	var t: float = 0.0

	if zoom_anim_time < 0.4:
		var phase1_progress = zoom_anim_time / 0.4
		t = phase1_progress * 0.75
	elif zoom_anim_time < 0.6:
		var phase2_progress = (zoom_anim_time - 0.4) / 0.2
		t = 0.75 + phase2_progress * 0.25
	else:
		t = 1.0
		zoom_animating = false

	var te = t * t * (3.0 - 2.0 * t)
	current_zoom_distance = lerp(zoom_start_distance, target_zoom_distance, te)

	if not zoom_animating:
		current_zoom_distance = target_zoom_distance


func _update_orbit_rotation_animation(delta: float):
	if not orbit_rotation_animating:
		return

	orbit_anim_time += delta
	var t: float = 0.0

	if orbit_anim_time < 0.4:
		var phase1_progress = orbit_anim_time / 0.4
		t = phase1_progress * 0.75
	elif orbit_anim_time < 0.6:
		var phase2_progress = (orbit_anim_time - 0.4) / 0.2
		t = 0.75 + phase2_progress * 0.25
	else:
		t = 1.0
		orbit_rotation_animating = false

	var te = t * t * (3.0 - 2.0 * t)
	current_angle = lerp_angle(orbit_start_angle, orbit_target_angle, te)

	if not orbit_rotation_animating:
		current_angle = orbit_target_angle


func _update_view_mode_animation(delta: float):
	if not view_mode_animating:
		return

	view_anim_time += delta
	var t: float = 0.0

	if view_anim_time < 0.2:
		var phase1_progress = view_anim_time / 0.2
		t = phase1_progress * 0.25
	elif view_anim_time < 0.4:
		var phase2_progress = (view_anim_time - 0.2) / 0.2
		t = 0.25 + phase2_progress * 0.5
	elif view_anim_time < 0.6:
		var phase3_progress = (view_anim_time - 0.4) / 0.2
		t = 0.75 + phase3_progress * 0.25
	else:
		t = 1.0
		view_mode_animating = false

	var te = t * t * (3.0 - 2.0 * t)
	current_zoom_distance = lerp(view_start_distance, view_target_distance, te)
	camera_current_pitch = lerp(view_start_pitch, view_target_pitch, te)

	if not view_mode_animating:
		current_zoom_distance = view_target_distance
		camera_current_pitch = view_target_pitch


func _update_follow_rotation_animation(delta: float):
	if not follow_rotation_animating:
		return

	follow_anim_time += delta
	var t: float = 0.0

	if follow_anim_time < 0.4:
		var phase1_progress = follow_anim_time / 0.4
		t = phase1_progress * 0.25
	elif follow_anim_time < 0.6:
		var phase2_progress = (follow_anim_time - 0.4) / 0.2
		t = 0.25 + phase2_progress * 0.5
	elif follow_anim_time < 1.0:
		var phase3_progress = (follow_anim_time - 0.6) / 0.4
		t = 0.75 + phase3_progress * 0.25
	else:
		t = 1.0
		follow_rotation_animating = false

	var te = t * t * (3.0 - 2.0 * t)
	current_angle = lerp_angle(follow_start_angle, follow_target_angle, te)

	if not follow_rotation_animating:
		current_angle = follow_target_angle


## Reads a character-metric getter off `target` via duck typing — target is
## a generic Node3D, not necessarily the Player. Falls back to a fixed,
## non-zero height (with a one-time warning) if target doesn't expose it.
func _target_metric_height(method: StringName, fallback: float) -> float:
	if target.has_method(method):
		return float(target.call(method))
	if not _warned_missing_target_metrics:
		push_warning("OnFootCameraComponent: target '%s' has no %s() — using fallback height %.2f" % [target.name, method, fallback])
		_warned_missing_target_metrics = true
	return fallback


## Reads target.get_speed_ratio() via duck typing, same pattern as
## _target_metric_height(). Falls back to 0 (no pull-back) with a one-time
## warning if target doesn't expose it.
func _target_speed_ratio() -> float:
	if target.has_method(&"get_speed_ratio"):
		return float(target.call(&"get_speed_ratio"))
	if not _warned_missing_speed_ratio:
		push_warning("OnFootCameraComponent: target '%s' has no get_speed_ratio() — sprint pull-back disabled" % target.name)
		_warned_missing_speed_ratio = true
	return 0.0


func _update_camera_position(delta):
	match PlayerState.view_mode:
		PlayerState.ViewMode.TPS:
			var yaw_rad = camera_target_yaw
			var pitch_rad = deg_to_rad(_tps_pitch_deg)
			var horizontal_direction = Vector3(sin(yaw_rad), 0, cos(yaw_rad))

			var speed_ratio := _target_speed_ratio()
			_tps_sprint_pullback = lerp(_tps_sprint_pullback, speed_ratio * TPS_SPRINT_PULLBACK, delta * TPS_PULLBACK_SMOOTHING)
			var effective_distance := TPS_DISTANCE + _tps_sprint_pullback

			var horizontal_distance = effective_distance * cos(pitch_rad)
			var vertical_distance = -effective_distance * sin(pitch_rad)
			var right := Vector3(
				cos(yaw_rad),
				0.0,
				-sin(yaw_rad)
			)

			var shoulder_offset := _shoulder.update(delta)
			var shoulder := right * (shoulder_offset * TPS_SHOULDER_TRANSLATION_RATIO)

			# Base pivot: target + pivot height (shoulder level, not ground)
			var pivot_height := _target_metric_height(&"get_shoulder_height", TPS_PIVOT_HEIGHT_FALLBACK)
			var pivot := target.global_position + Vector3(0, pivot_height, 0)
			var offset = horizontal_direction * horizontal_distance + Vector3(0, vertical_distance, 0) + shoulder

			camera_target_pos = pivot + offset
			camera_target_pitch = _tps_pitch_deg + _tps_pitch_offset_deg

			var target_h_offset := shoulder_offset * TPS_SHOULDER_FRUSTUM_RATIO * TPS_SHOULDER_H_OFFSET_SIGN
			camera.h_offset = lerp(camera.h_offset, target_h_offset, delta * 8.0)

			# --- Wall & floor avoidance: pull camera in when geometry blocks ---
			var space_state := camera.get_world_3d().direct_space_state
			var occlusion_height := _target_metric_height(&"get_eye_height", TPS_OCCLUSION_HEIGHT_FALLBACK)
			var eye_pos := target.global_position + Vector3(0, occlusion_height, 0)
			var query := PhysicsRayQueryParameters3D.create(eye_pos, camera_target_pos, (1 << 1) | (1 << 2))
			query.collide_with_areas = false
			var hit := space_state.intersect_ray(query)
			if hit:
				camera_target_pos = hit.position + hit.normal * 0.25

		_:  # ISOMETRIC
			var horizontal_direction = Vector3(sin(current_angle), 0, cos(current_angle))
			var pitch_rad = deg_to_rad(camera_angle)
			var horizontal_distance = current_zoom_distance * cos(pitch_rad)
			var vertical_distance = -current_zoom_distance * sin(pitch_rad)
			var orbit_offset = horizontal_direction * horizontal_distance + Vector3(0, vertical_distance, 0)
			camera_target_pos = target.global_position + orbit_offset
			camera_target_pitch = camera_angle
			camera_target_yaw = current_angle

			# TPS shoulder framing must not leak into ISOMETRIC — decay it back to 0.
			camera.h_offset = lerp(camera.h_offset, 0.0, delta * 8.0)

	# Position follows at TPS_FOLLOW_SPEED once settled in TPS — decoupled
	# from view_transition_speed so steady-state follow lag and the
	# ISOMETRIC <-> TPS transition animation can be tuned independently.
	# During the transition animation (or in ISOMETRIC), position still
	# rides view_transition_speed, or the transition itself would jump.
	var position_follow_speed := view_transition_speed
	if PlayerState.view_mode == PlayerState.ViewMode.TPS and not view_mode_animating:
		position_follow_speed = TPS_FOLLOW_SPEED

	camera_current_pos = camera_current_pos.lerp(camera_target_pos, delta * position_follow_speed)
	if not view_mode_animating:
		camera_current_pitch = lerp(camera_current_pitch, camera_target_pitch, delta * view_transition_speed)
	camera_current_yaw = lerp_angle(camera_current_yaw, camera_target_yaw, delta * view_transition_speed)

	camera.global_position = camera_current_pos
	camera.global_rotation = Vector3(deg_to_rad(camera_current_pitch), camera_current_yaw, 0)


func _handle_follow_toggle():
	if PlayerState.view_mode == PlayerState.ViewMode.TPS:
		return  # в TPS слежение не переключаемо — оно всегда включено по своей природе
	if InputSystems.is_toggle_follow_just_pressed():
		follow_player_rotation = !follow_player_rotation
		if follow_player_rotation:
			last_player_rotation = target.rotation.y
			player_rotation_timer = 0.0


func _handle_view_toggle():
	if not InputSystems.is_toggle_view_just_pressed():
		return
	if zoom_animating or view_mode_animating:
		return

	match PlayerState.view_mode:
		PlayerState.ViewMode.ISOMETRIC:
			if is_equal_approx_eps(target_zoom_distance, ISOMETRIC_ZOOM_MIN):
				_transition_to_view(PlayerState.ViewMode.TPS)
		PlayerState.ViewMode.TPS:
			# No zoom requirement to exit TPS — V always switches back
			_transition_to_view(PlayerState.ViewMode.ISOMETRIC)


func is_equal_approx_eps(a: float, b: float) -> bool:
	return abs(a - b) <= ZOOM_EDGE_EPSILON


## Единая точка перехода между видами. Переход всегда срабатывает строго
## на краю диапазона (см. _handle_view_toggle), поэтому ratio-mapping не
## нужен — просто входим в новый вид на его граничном значении зума.
func _transition_to_view(new_view: PlayerState.ViewMode) -> void:
	view_start_distance = current_zoom_distance
	view_start_pitch = camera_current_pitch

	match new_view:
		PlayerState.ViewMode.TPS:
			view_target_distance = TPS_DISTANCE
			view_target_pitch = _tps_pitch_deg

		PlayerState.ViewMode.ISOMETRIC:
			# из TPS — входим на ближнем крае ISO, лицом куда смотрел игрок
			view_target_distance = ISOMETRIC_ZOOM_MIN
			target_angle = target.rotation.y + PI
			current_angle = target_angle
			view_target_pitch = camera_angle

	target_zoom_distance = view_target_distance
	view_anim_time = 0.0
	view_mode_animating = true
	PlayerState.set_view_mode(new_view)

func _handle_shoulder_toggle() -> void:

	if InputSystems.is_switch_shoulder_just_pressed():
		_shoulder.toggle()
		
func _handle_follow_rotation(delta):
	var player_y_rotation = target.rotation.y
	var desired_angle = player_y_rotation + PI

	if abs(player_y_rotation - last_player_rotation) > 0.01:
		player_rotation_timer += delta
		if player_rotation_timer >= follow_rotation_delay:
			if not follow_rotation_animating:
				follow_start_angle = current_angle
				follow_target_angle = desired_angle
				follow_anim_time = 0.0
				follow_rotation_animating = true
				target_angle = desired_angle
		last_player_rotation = player_y_rotation
	else:
		player_rotation_timer = 0.0


func _handle_rotation_input():
	if follow_player_rotation:
		return
	if PlayerState.view_mode == PlayerState.ViewMode.TPS:
		return  # орбита не применима — камера жёстко позади игрока
	if InputSystems.is_lean_left_just_pressed():
		_rotate_camera_left()
	elif InputSystems.is_lean_right_just_pressed():
		_rotate_camera_right()


func _rotate_camera_left():
	var idx = ORBITAL_POSITIONS.find(current_position)
	idx = (idx - 1) % ORBITAL_POSITIONS.size()
	if idx < 0: idx = ORBITAL_POSITIONS.size() - 1
	current_position = ORBITAL_POSITIONS[idx]

	orbit_start_angle = current_angle
	orbit_target_angle = POSITION_ANGLES[current_position]
	orbit_anim_time = 0.0
	orbit_rotation_animating = true

	target_angle = orbit_target_angle


func _rotate_camera_right():
	var idx = ORBITAL_POSITIONS.find(current_position)
	idx = (idx + 1) % ORBITAL_POSITIONS.size()
	if idx >= ORBITAL_POSITIONS.size(): idx = 0
	current_position = ORBITAL_POSITIONS[idx]

	orbit_start_angle = current_angle
	orbit_target_angle = POSITION_ANGLES[current_position]
	orbit_anim_time = 0.0
	orbit_rotation_animating = true

	target_angle = orbit_target_angle


func _handle_zoom_input():
	if InputSystems.is_zoom_in_just_released():
		zoom_input_received.emit()
		_start_zoom(-ZOOM_STEP)
	elif InputSystems.is_zoom_out_just_released():
		zoom_input_received.emit()
		_start_zoom(ZOOM_STEP)
		

func _start_zoom(amount: float):
	var min_zoom: float
	var max_zoom: float

	match PlayerState.view_mode:
		PlayerState.ViewMode.TPS:
			return  # zoom disabled in TPS — distance is fixed
		_:
			min_zoom = ISOMETRIC_ZOOM_MIN
			max_zoom = ISOMETRIC_ZOOM_MAX

	var new_distance = clamp(target_zoom_distance + amount, min_zoom, max_zoom)

	if abs(new_distance - target_zoom_distance) > 0.01:
		zoom_start_distance = current_zoom_distance
		target_zoom_distance = new_distance
		zoom_anim_time = 0.0
		zoom_animating = true


func _update_labels():
	if not lbl_current_mode:
		return

	lbl_current_mode.text = "Режим: %s (нажми V для изменения)" % get_current_mode()
	if follow_player_rotation or PlayerState.view_mode == PlayerState.ViewMode.TPS:
		lbl_orbital.visible = false
	else:
		lbl_orbital.visible = true
		lbl_orbital.text = "Изменить орбиту: Q или E"
	var follow_state = "ON" if follow_player_rotation else "OFF"
	lbl_follow.text = "Слежение за игроком (P): %s" % follow_state


func get_current_mode() -> String:
	match PlayerState.view_mode:
		PlayerState.ViewMode.TPS:
			return "TPS"
		_:
			if follow_player_rotation:
				return "Follow Player"
			return "Orbital (%s)" % get_current_direction_name()


func get_current_direction_name() -> String:
	match current_position:
		OrbitalPosition.NORTH: return "North"
		OrbitalPosition.EAST: return "East"
		OrbitalPosition.SOUTH: return "South"
		OrbitalPosition.WEST: return "West"
		_: return "Unknown"


## Публичный геттер для HUD-виджета (линейка зума) — какой диапазон
## дистанции актуален для текущего view_mode.
func get_current_zoom_range() -> Vector2:
	match PlayerState.view_mode:
		PlayerState.ViewMode.TPS:
			return Vector2(TPS_ZOOM_MIN, TPS_ZOOM_MAX)
		_:
			return Vector2(ISOMETRIC_ZOOM_MIN, ISOMETRIC_ZOOM_MAX)
