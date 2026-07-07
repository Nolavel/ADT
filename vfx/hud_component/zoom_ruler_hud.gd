# =============================================================================
# zoom_ruler_hud.gd
#
# Экранный виджет-линейка зума: вертикальная шкала, старт по центру-низу
# экрана, 200px вверх, засечки = шаги зума в текущем диапазоне
# (ISOMETRIC/TOPDOWN/TPS — диапазон берётся из OnFootCameraComponent).
#
# Буква "V" появляется у соответствующего края шкалы (плавно, через Tween
# по alpha), когда зум упёрся в предел и доступен переход в другой вид —
# ровно то же условие "у края", что использует
# on_foot_camera_component._handle_view_toggle().
#
# Владелец: world.gd — создаёт через .new(), кладёт в CanvasLayer, сразу
# после вызывает setup(camera.get_on_foot_component()).
# =============================================================================
extends Control
class_name ZoomRulerHUD

const LINE_HEIGHT: float = 200.0
const LINE_WIDTH: float = 2.0
const TICK_LENGTH: float = 14.0
const BOTTOM_MARGIN: float = 24.0
const FONT_SIZE: int = 20
const FADE_TIME: float = 0.25
const EDGE_EPSILON: float = 0.05

var _on_foot: OnFootCameraComponent

var _v_top_alpha: float = 0.0
var _v_bottom_alpha: float = 0.0
var _was_at_top_edge: bool = false
var _was_at_bottom_edge: bool = false


## Вызывается world.gd сразу после инстанцирования — явная передача
## ссылки, никакого singleton-доступа по имени класса.
func setup(on_foot_component: OnFootCameraComponent) -> void:
	_on_foot = on_foot_component


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	if not _on_foot:
		return
	_update_edge_fades()
	queue_redraw()


## "Верхний" край шкалы = ближний предел зума (приблизили до упора).
## "Нижний" край шкалы = дальний предел зума (отдалили до упора).
## Условие ровно то же, что использует camera-компонент для гейтинга V.
func _update_edge_fades() -> void:
	var zoom_range: Vector2 = _on_foot.get_current_zoom_range()
	var min_z: float = zoom_range.x
	var max_z: float = zoom_range.y
	var d: float = _on_foot.target_zoom_distance

	var at_top_edge: bool = abs(d - min_z) <= EDGE_EPSILON
	var at_bottom_edge: bool = abs(d - max_z) <= EDGE_EPSILON

	if at_top_edge != _was_at_top_edge:
		_was_at_top_edge = at_top_edge
		_tween_alpha("_v_top_alpha", 1.0 if at_top_edge else 0.0)

	if at_bottom_edge != _was_at_bottom_edge:
		_was_at_bottom_edge = at_bottom_edge
		_tween_alpha("_v_bottom_alpha", 1.0 if at_bottom_edge else 0.0)


func _tween_alpha(property_name: String, target_value: float) -> void:
	var t := create_tween()
	t.tween_property(self, property_name, target_value, FADE_TIME)
	t.tween_callback(queue_redraw)


func _draw() -> void:
	if not _on_foot:
		return

	var cx: float = size.x / 2.0
	var baseline_y: float = size.y - BOTTOM_MARGIN
	var top_y: float = baseline_y - LINE_HEIGHT

	# Сама вертикальная линия
	draw_line(Vector2(cx, baseline_y), Vector2(cx, top_y), Color.WHITE, LINE_WIDTH)

	var zoom_range: Vector2 = _on_foot.get_current_zoom_range()
	var min_z: float = zoom_range.x
	var max_z: float = zoom_range.y
	var span: float = max_z - min_z

	if span > 0.0:
		var steps: int = max(1, int(round(span / _on_foot.ZOOM_STEP)))

		for i in range(steps + 1):
			var t: float = float(i) / float(steps)
			var y: float = lerp(baseline_y, top_y, t)
			draw_line(
				Vector2(cx - TICK_LENGTH / 2.0, y),
				Vector2(cx + TICK_LENGTH / 2.0, y),
				Color.WHITE,
				LINE_WIDTH
			)

		# Текущая позиция зума на шкале — маленький маркер поверх засечек
		var current_ratio: float = clamp((_on_foot.current_zoom_distance - min_z) / span, 0.0, 1.0)
		var marker_y: float = lerp(baseline_y, top_y, current_ratio)
		draw_circle(Vector2(cx, marker_y), 4.0, Color.WHITE)

	var font := ThemeDB.fallback_font

	if _v_top_alpha > 0.01:
		draw_string(
			font, Vector2(cx + TICK_LENGTH, top_y + FONT_SIZE * 0.35),
			"V", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE,
			Color(1.0, 1.0, 1.0, _v_top_alpha)
		)

	if _v_bottom_alpha > 0.01:
		draw_string(
			font, Vector2(cx + TICK_LENGTH, baseline_y + FONT_SIZE * 0.35),
			"V", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE,
			Color(1.0, 1.0, 1.0, _v_bottom_alpha)
		)
