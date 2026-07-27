extends Control
## Radial "revolver cylinder" menu. Dock this Control to the right edge of the
## screen (anchors: right=1, top=0, bottom=1, grow_horizontal=GROW_DIRECTION_BEGIN).
## Center of the circle sits off-screen to the right; only the left arc is visible.

signal item_selected(index: int, label: String)

@export var items: Array[String] = ["Continue", "New Game", "Load Game", "Settings", "Credits", "Quit"]
@export var radius: float = 310.0
@export var dock_offset: float = 0.58   ## fraction of radius pushed off-screen, matches translate(58%) in the HTML version
@export var rotation_speed: float = 0.18
@export var snap_duration: float = 0.26

var _rotation_deg: float = 0.0
var _step: float = 0.0
var _labels: Array[Label] = []
var _selected_index: int = 0
var _snap_tween: Tween
var _touch_start_y: float = 0.0
var _touch_start_rotation: float = 0.0
var _dragging: bool = false

const NEON_SHADER := preload("res://ui/main_menu/neon_flicker.gdshader")

func _ready() -> void:
	_step = 360.0 / items.size()
	position.x += radius * dock_offset  # push circle center further right, matching the CSS transform
	_build_labels()
	_render()

func _build_labels() -> void:
	for i in items.size():
		var lbl := Label.new()
		lbl.text = items[i]
		lbl.add_theme_font_size_override("font_size", 20)
		lbl.add_theme_color_override("font_color", Color(0.6, 0.57, 0.51))
		lbl.pivot_offset = Vector2.ZERO

		var mat := ShaderMaterial.new()
		mat.shader = NEON_SHADER
		mat.set_shader_parameter("seed", float(i) * 7.0)
		lbl.material = mat

		add_child(lbl)
		_labels.append(lbl)

func _render() -> void:
	var closest_delta := 360.0
	for i in _labels.size():
		var base_angle: float = i * _step
		var current: float = base_angle + _rotation_deg
		var rad: float = deg_to_rad(current)
		var x: float = -cos(rad) * radius
		var y: float = -sin(rad) * radius

		var delta: float = abs(wrapf(current, -180.0, 180.0))
		var visibility: float = clamp(1.0 - delta / 130.0, 0.0, 1.0)
		var s: float = 0.72 + 0.28 * clamp(1.0 - delta / 90.0, 0.0, 1.0)

		var lbl := _labels[i]
		lbl.position = Vector2(x, y)
		lbl.modulate.a = visibility
		lbl.scale = Vector2(s, s)
		lbl.z_index = int(1000 - delta)

		var is_active := delta < _step / 2.0
		var mat := lbl.material as ShaderMaterial
		if is_active:
			lbl.add_theme_font_size_override("font_size", 28)
			lbl.add_theme_color_override("font_color", Color(0.85, 0.83, 0.78))
			mat.set_shader_parameter("active", 1.0)
		else:
			lbl.add_theme_font_size_override("font_size", 20)
			lbl.add_theme_color_override("font_color", Color(0.6, 0.57, 0.51))
			mat.set_shader_parameter("active", 0.0)

		if delta < closest_delta:
			closest_delta = delta
			_selected_index = i

func _unhandled_input(event: InputEvent) -> void:
	# Mouse wheel (desktop)
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_rotation_deg += 20.0 * rotation_speed
			_render()
			_queue_snap()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_rotation_deg -= 20.0 * rotation_speed
			_render()
			_queue_snap()

	# Touch drag (mobile)
	if event is InputEventScreenTouch:
		if event.pressed:
			_dragging = true
			_touch_start_y = event.position.y
			_touch_start_rotation = _rotation_deg
			if _snap_tween:
				_snap_tween.kill()
		else:
			_dragging = false
			_queue_snap()

	if event is InputEventScreenDrag and _dragging:
		var dy: float = event.position.y - _touch_start_y
		_rotation_deg = _touch_start_rotation + dy * 0.35
		_render()

func _queue_snap() -> void:
	if _snap_tween:
		_snap_tween.kill()
	_snap_tween = create_tween()
	_snap_tween.tween_interval(0.14)
	_snap_tween.tween_callback(_snap)

func _snap() -> void:
	var target: float = round(_rotation_deg / _step) * _step
	_animate_to(target)

func _animate_to(target: float) -> void:
	if _snap_tween:
		_snap_tween.kill()
	_snap_tween = create_tween()
	_snap_tween.set_ease(Tween.EASE_OUT)
	_snap_tween.set_trans(Tween.TRANS_CUBIC)
	_snap_tween.tween_method(_set_rotation, _rotation_deg, target, snap_duration)
	_snap_tween.tween_callback(func():
		item_selected.emit(_selected_index, items[_selected_index])
	)

func _set_rotation(v: float) -> void:
	_rotation_deg = v
	_render()

## Call this to jump directly to an item (e.g. from a controller D-pad or a click on a visible label).
func select_index(i: int) -> void:
	var base_angle: float = i * _step
	var target: float = -base_angle
	var diff: float = wrapf(target - _rotation_deg, -180.0, 180.0)
	_animate_to(_rotation_deg + diff)
