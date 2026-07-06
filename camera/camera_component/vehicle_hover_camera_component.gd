# =============================================================================
# vehicle_hover_camera_component.gd
# Компонент камеры для PlayerState.Mode.VEHICLE_HOVER.
#
# ЗАГЛУШКА: фиксированный офсет позади цели, без специфичной физики
# ховер-транспорта. Полноценная механика (пружина за машиной, скорость→FOV
# и т.п.) — отдельная задача, когда будет готов входной триггер транспорта.
# =============================================================================
extends Node
class_name VehicleHoverCameraComponent

@export var offset: Vector3 = Vector3(0, 2.5, 6.0)
@export var pitch_deg: float = -18.0
@export var follow_speed: float = 6.0

var camera: Camera3D
var target: Node3D


func setup() -> void:
	pass


func enter() -> void:
	pass


func exit() -> void:
	pass


func update(delta: float) -> void:
	if not target:
		return

	var local_offset := offset.rotated(Vector3.UP, target.rotation.y)
	var desired_pos := target.global_position + local_offset

	camera.global_position = camera.global_position.lerp(desired_pos, delta * follow_speed)

	var to_target := target.global_position - camera.global_position
	to_target.y = 0
	var yaw := atan2(to_target.x, to_target.z) if to_target.length() > 0.01 else camera.rotation.y
	camera.global_rotation = Vector3(deg_to_rad(pitch_deg), yaw, 0)
