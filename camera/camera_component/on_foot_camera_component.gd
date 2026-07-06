# =============================================================================
# on_foot_camera_component.gd
# Компонент камеры для PlayerState.Mode.ON_FOOT.
#
# Логика перенесена из старого монолитного camera_follow.gd БЕЗ ИЗМЕНЕНИЙ
# (orbital Q/E, top-down V, follow P, zoom колесом) — по договорённости
# ничего здесь пока не чистим и не переделываем, только переносим.
#
# Компонент не Camera3D сам по себе — он получает ссылку на реальную
# камеру (camera) и на цель (target) от хоста и пишет прямо в
# camera.global_position/global_rotation, когда активен.
# =============================================================================
extends Node
class_name OnFootCameraComponent

@export var rotation_speed: float = 8.0

@export_group("Orbit")
@export var orbit_distance: float = 20.0
@export var orbit_height: float = 15.0
@export var camera_angle: float = -35.0

@export_group("Top-Down View")
@export var top_down_height: float = 15.0
@export var top_down_angle: float = -85.0
@export var view_transition_speed: float = 4.0

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
var is_top_down_view: bool = false
var topdown_target_yaw: float = 0.0
var topdown_current_yaw: float = 0.0

var camera_target_pos: Vector3
var camera_current_pos: Vector3
var camera_target_pitch: float
var camera_current_pitch: float
var camera_target_yaw: float
var camera_current_yaw: float

# === ZOOM SYSTEM ===
var current_zoom_distance: float = 0.0
var target_zoom_distance: float = 0.0
var zoom_animating: bool = false
var zoom_anim_time: float = 0.0
var zoom_start_distance: float = 0.0

const ISOMETRIC_ZOOM_MIN: float = 10.0
const ISOMETRIC_ZOOM_MAX: float = 17.5
const TOPDOWN_ZOOM_MIN: float = 7.5
const TOPDOWN_ZOOM_MAX: float = 15.0
const ZOOM_STEP: float = 2.5

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


## Вызывается хостом один раз перед первым использованием (camera/target уже назначены).
func setup() -> void:
	current_angle = POSITION_ANGLES[current_position]
	target_angle = current_angle
	topdown_target_yaw = POSITION_ANGLES[current_position]
	topdown_current_yaw = topdown_target_yaw
	camera_target_pitch = camera_angle
	camera_current_pitch = camera_angle
	camera_target_yaw = current_angle
	camera_current_yaw = current_angle
	camera_target_pos = camera.global_position
	camera_current_pos = camera.global_position
	current_zoom_distance = orbit_distance
	target_zoom_distance = orbit_distance


## Вызывается хостом при входе в ON_FOOT (в т.ч. при возврате из MENU).
func enter() -> void:
	camera_current_pos = camera.global_position


func exit() -> void:
	pass


func update(delta: float) -> void:
	if not target:
		return

	_handle_follow_toggle()
	_handle_view_toggle()
	_handle_zoom_input()

	if follow_player_rotation and is_top_down_view:
		_handle_topdown_follow_rotation(delta)
	elif follow_player_rotation and not is_top_down_view:
		_handle_follow_rotation(delta)
	else:
		_handle_rotation_input()

	_update_zoom_animation(delta)
	_update_orbit_rotation_animation(delta)
	_update_view_mode_animation(delta)
	_update_follow_rotation_animation(delta)

	if not orbit_rotation_animating and not follow_rotation_animating:
		current_angle = lerp_angle(current_angle, target_angle, delta * rotation_speed)
	topdown_current_yaw = lerp_angle(topdown_current_yaw, topdown_target_yaw, delta * rotation_speed)

	_update_camera_position(delta)
	_update_labels()


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


func _update_camera_position(delta):
	if is_top_down_view:
		camera_target_pos = target.global_position + Vector3(0, current_zoom_distance, 0)
		camera_target_pitch = top_down_angle
		camera_target_yaw = topdown_current_yaw
	else:
		var horizontal_direction = Vector3(sin(current_angle), 0, cos(current_angle))
		var pitch_rad = deg_to_rad(camera_angle)
		var horizontal_distance = current_zoom_distance * cos(pitch_rad)
		var vertical_distance = -current_zoom_distance * sin(pitch_rad)
		var orbit_offset = horizontal_direction * horizontal_distance + Vector3(0, vertical_distance, 0)
		camera_target_pos = target.global_position + orbit_offset
		camera_target_pitch = camera_angle
		camera_target_yaw = current_angle

	camera_current_pos = camera_current_pos.lerp(camera_target_pos, delta * view_transition_speed)
	if not view_mode_animating:
		camera_current_pitch = lerp(camera_current_pitch, camera_target_pitch, delta * view_transition_speed)
	camera_current_yaw = lerp_angle(camera_current_yaw, camera_target_yaw, delta * view_transition_speed)

	camera.global_position = camera_current_pos
	camera.global_rotation = Vector3(deg_to_rad(camera_current_pitch), camera_current_yaw, 0)


func _handle_follow_toggle():
	if Input.is_action_just_pressed("toggle_follow"):
		follow_player_rotation = !follow_player_rotation
		if follow_player_rotation:
			last_player_rotation = target.rotation.y
			player_rotation_timer = 0.0


func _handle_view_toggle():
	if Input.is_action_just_pressed("toggle_view"):
		is_top_down_view = !is_top_down_view

		view_start_distance = current_zoom_distance
		view_start_pitch = camera_current_pitch

		if is_top_down_view:
			var ratio = (current_zoom_distance - ISOMETRIC_ZOOM_MIN) / (ISOMETRIC_ZOOM_MAX - ISOMETRIC_ZOOM_MIN)
			view_target_distance = TOPDOWN_ZOOM_MIN + ratio * (TOPDOWN_ZOOM_MAX - TOPDOWN_ZOOM_MIN)
			view_target_pitch = top_down_angle
			topdown_target_yaw = current_angle
			topdown_current_yaw = current_angle
		else:
			var ratio = (current_zoom_distance - TOPDOWN_ZOOM_MIN) / (TOPDOWN_ZOOM_MAX - TOPDOWN_ZOOM_MIN)
			view_target_distance = ISOMETRIC_ZOOM_MIN + ratio * (ISOMETRIC_ZOOM_MAX - ISOMETRIC_ZOOM_MIN)
			view_target_pitch = camera_angle
			target_angle = topdown_current_yaw

		target_zoom_distance = view_target_distance
		view_anim_time = 0.0
		view_mode_animating = true


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


func _handle_topdown_follow_rotation(delta):
	var player_y_rotation = target.rotation.y + PI

	if abs(player_y_rotation - last_player_rotation - PI) > 0.01:
		player_rotation_timer += delta
		if player_rotation_timer >= follow_rotation_delay:
			if not follow_rotation_animating:
				topdown_target_yaw = player_y_rotation
		last_player_rotation = target.rotation.y
	else:
		player_rotation_timer = 0.0


func _handle_rotation_input():
	if follow_player_rotation:
		return
	if Input.is_action_just_pressed("lean_left"):
		_rotate_camera_left()
	elif Input.is_action_just_pressed("lean_right"):
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
	topdown_target_yaw = orbit_target_angle


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
	topdown_target_yaw = orbit_target_angle


func _handle_zoom_input():
	if Input.is_action_just_released("zoom_in"):
		_start_zoom(-ZOOM_STEP)
	elif Input.is_action_just_released("zoom_out"):
		_start_zoom(ZOOM_STEP)


func _start_zoom(amount: float):
	var min_zoom: float
	var max_zoom: float

	if is_top_down_view:
		min_zoom = TOPDOWN_ZOOM_MIN
		max_zoom = TOPDOWN_ZOOM_MAX
	else:
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
	if follow_player_rotation:
		lbl_orbital.visible = false
	else:
		lbl_orbital.visible = true
		lbl_orbital.text = "Изменить орбиту: Q или E"
	var follow_state = "ON" if follow_player_rotation else "OFF"
	lbl_follow.text = "Слежение за игроком (P): %s" % follow_state


func get_current_mode() -> String:
	if is_top_down_view:
		return "Top-Down"
	elif follow_player_rotation:
		return "Follow Player"
	else:
		return "Orbital (%s)" % get_current_direction_name()


func get_current_direction_name() -> String:
	match current_position:
		OrbitalPosition.NORTH: return "North"
		OrbitalPosition.EAST: return "East"
		OrbitalPosition.SOUTH: return "South"
		OrbitalPosition.WEST: return "West"
		_: return "Unknown"
