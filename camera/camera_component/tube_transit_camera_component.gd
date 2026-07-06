# =============================================================================
# tube_transit_camera_component.gd
# Компонент камеры для PlayerState.Mode.TUBE_TRANSIT.
#
# ЗАГЛУШКА: чистое наблюдение — камера фиксируется у точки входа в трубу
# и позволяет свободный осмотр мышью (freelook), без управления движением.
# Полноценная механика полёта по сплайну — отдельная задача, low priority
# (см. заметки проекта).
# =============================================================================
extends Node
class_name TubeTransitCameraComponent

@export var look_sensitivity: float = 0.01
@export var pitch_limit_deg: float = 80.0

var camera: Camera3D
var target: Node3D

var _fixed_pos: Vector3
var _yaw: float = 0.0
var _pitch: float = 0.0


func setup() -> void:
	pass


func enter() -> void:
	_fixed_pos = camera.global_position
	_yaw = camera.rotation.y
	_pitch = camera.rotation.x


func exit() -> void:
	pass


func update(delta: float) -> void:
	# ПРИМЕЧАНИЕ: сейчас dynamic_cursor_ui.gd ставит MOUSE_MODE_VISIBLE для
	# любого режима кроме ON_FOOT — значит freelook ниже не сработает, пока
	# для TUBE_TRANSIT отдельно не выставить MOUSE_MODE_CAPTURED. Это часть
	# полноценной реализации трубы, которой пока не занимаемся (low priority).
	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		var mouse_rel := Input.get_last_mouse_velocity() * delta
		_yaw -= mouse_rel.x * look_sensitivity
		_pitch = clamp(_pitch - mouse_rel.y * look_sensitivity, deg_to_rad(-pitch_limit_deg), deg_to_rad(pitch_limit_deg))

	camera.global_position = _fixed_pos
	camera.global_rotation = Vector3(_pitch, _yaw, 0)
