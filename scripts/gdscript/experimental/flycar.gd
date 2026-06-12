extends MeshInstance3D

@export var travel_distance: float = 500.0
@export var move_duration: float = 5.0
@export var fade_duration: float = 0.5
@export var repeat_interval: float = 2.0

var _start_position: Vector3
var _time_since_last: float = 0.0
var _is_playing: bool = false

func _ready() -> void:
	_start_position = global_position

	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1, 1, 1, 0)
	material_override = mat

	_launch()

func _process(delta: float) -> void:
	_time_since_last += delta
	if _time_since_last >= repeat_interval && !_is_playing:
		_time_since_last = 0.0
		_launch()

func _launch() -> void:
	_is_playing = true
	global_position = _start_position
	_set_alpha(0.0)

	var tween = create_tween()
	tween.tween_method(_set_alpha, 0.0, 1.0, fade_duration)
	tween.tween_property(
		self,
		"global_position",
		_start_position + Vector3(travel_distance, 0, 0),
		move_duration
	).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_method(_set_alpha, 1.0, 0.0, fade_duration)
	tween.tween_callback(_on_sequence_done)

func _on_sequence_done() -> void:
	_is_playing = false
	_time_since_last = 0.0

func _set_alpha(alpha: float) -> void:
	if material_override is StandardMaterial3D:
		material_override.albedo_color.a = alpha
