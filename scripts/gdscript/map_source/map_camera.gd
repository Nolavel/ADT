extends Camera3D

@export_group("Movement")
@export var move_speed: float = 800.0
@export var fast_speed_multiplier: float = 3.0
@export var smooth_factor: float = 8.0

@export_group("Zoom")
@export var zoom_min: float = 500.0
@export var zoom_max: float = 2000.0
@export var zoom_speed: float = 80.0
@export var zoom_smooth: float = 8.0

@export_group("Bounds")
@export var bounds_padding: float = 200.0
@export var world_half_x: float = 1300.0
@export var world_half_z: float = 4600.0

@export_group("Orbit")
@export var orbit_speed: float = 120.0
@export var pitch_speed: float = 90.0
@export var pitch_min_deg: float = -45.0
@export var pitch_max_deg: float = 45.0

@export_group("Camera Offset")
@export var orbit_distance: float = 1200.0

var _target_pos: Vector3
var _target_zoom: float = 900.0
var _yaw_deg: float = -45.0
var _pitch_deg: float = -30.0

@onready var _pivot: Node3D = get_parent() as Node3D

func _ready() -> void:
	if _pivot == null:
		push_error("Camera must be child of Pivot Node3D")
		return

	_target_pos = _pivot.global_position
	_target_zoom = position.y

	_apply_orbit()

func _process(delta: float) -> void:
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_handle_orbit(delta)
	else:
		_handle_movement(delta)

	_handle_zoom(delta)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_target_zoom = clamp(_target_zoom - zoom_speed, zoom_min, zoom_max)
			MOUSE_BUTTON_WHEEL_DOWN:
				_target_zoom = clamp(_target_zoom + zoom_speed, zoom_min, zoom_max)

func _handle_orbit(delta: float) -> void:
	var yaw_input := 0.0
	var pitch_input := 0.0

	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		yaw_input -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		yaw_input += 1.0

	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		pitch_input += 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		pitch_input -= 1.0

	if yaw_input == 0.0 and pitch_input == 0.0:
		return

	_yaw_deg += yaw_input * orbit_speed * delta
	_pitch_deg = clamp(
		_pitch_deg + pitch_input * pitch_speed * delta,
		pitch_min_deg,
		pitch_max_deg
	)

	_apply_orbit()

func _apply_orbit() -> void:
	_pivot.rotation_degrees.y = _yaw_deg

	rotation_degrees.x = _pitch_deg
	rotation_degrees.y = 0
	rotation_degrees.z = 0

	position = Vector3(
		0,
		_target_zoom,
		orbit_distance
	)

func _handle_movement(delta: float) -> void:
	var input := Vector3.ZERO

	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		input.z += 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		input.z -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		input.x += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		input.x -= 1

	if Input.is_key_pressed(KEY_ESCAPE):
		get_tree().quit()

	if input == Vector3.ZERO:
		_pivot.global_position = _pivot.global_position.lerp(
			_target_pos,
			smooth_factor * delta
		)
		return

	var speed := move_speed

	if Input.is_key_pressed(KEY_SHIFT):
		speed *= fast_speed_multiplier

	# ---------- ИСПРАВЛЕНО ----------
	var forward := -_pivot.global_basis.z
	var right := _pivot.global_basis.x

	forward.y = 0
	right.y = 0

	forward = forward.normalized()
	right = right.normalized()
	# -------------------------------

	var move := (right * input.x + forward * input.z).normalized()

	_target_pos += move * speed * delta

	var limit_x := world_half_x - bounds_padding
	var limit_z := world_half_z - bounds_padding

	_target_pos.x = clamp(_target_pos.x, -limit_x, limit_x)
	_target_pos.z = clamp(_target_pos.z, -limit_z, limit_z)

	_pivot.global_position = _pivot.global_position.lerp(
		_target_pos,
		smooth_factor * delta
	)

func _handle_zoom(delta: float) -> void:
	position.y = lerp(
		position.y,
		_target_zoom,
		zoom_smooth * delta
	)
