# =============================================================================
# zoom_ruler_hud.gd
#
# Экранный виджет-линейка зума: ГОРИЗОНТАЛЬНАЯ шкала по центру-низу экрана.
# Левый край = ближний предел (→ V → TPS), правый край = дальний предел
# зума в текущем виде (TOPDOWN как отдельный вид убран — см. заметку в
# идейнике Miro). Линия рисуется сегментами с разрывами в местах шагов
# зума (разрыв размером с бегунок, вместо перпендикулярных засечек).
#
# Буквы "V"-подсказки — БЕЗ рамки/фона, просто буквы шрифтом Special Elite.
# Появляются не просто fade-in, а въезжают с расстояния SLIDE_DISTANCE px
# от конца линии (наружу) к своему месту у самого конца линии — позиция
# анимируется вместе с альфой через один и тот же прогресс 0..1, который
# тюнится Tween'ом с ease-out.
#
# Логика ввода не менялась: единственный легитимный читатель zoom-инпута
# остаётся on_foot_camera_component._handle_zoom_input(), эта нода только
# подписана на zoom_input_received.
#
# Владелец: world.gd → ZoomRulerSystem — создаёт через .new(), кладёт в
# CanvasLayer, сразу после вызывает setup(camera.get_on_foot_component()).
# =============================================================================
extends Control
class_name ZoomRulerHUD

const CUSTOM_FONT: Font = preload("res://assets/fonts/Special_Elite/SpecialElite-Regular.ttf")

# --- Геометрия ---
const LINE_LENGTH: float = 220.0
const LINE_WIDTH: float = 2.0
const BOTTOM_MARGIN: float = 146.0
const FONT_SIZE: int = 22
const LETTER_MARGIN: float = 20.0   # отступ буквы от конца линии в состоянии покоя
const MARKER_RADIUS: float = 4.0
const SLIDE_DISTANCE: float = 200.0   # старт анимации — на столько px дальше от конца линии, наружу

# --- Тайминги ---
const EDGE_EPSILON: float = 0.05
const SHOW_FADE_TIME: float = 0.2
const HIDE_FADE_TIME: float = 0.9
const HIDE_DELAY: float = 1.2
const LETTER_MOVE_TIME: float = 0.45   # въезд буквы с края экрана

# --- Amber-палитра ---
const COLOR_AMBER_BRIGHT: Color = Color(1.0, 0.52, 0.08, 1.0)

var _on_foot: OnFootCameraComponent

## 0..1 — и альфа, и позиция буквы завязаны на одно и то же значение,
## анимируемое Tween'ом с ease-out (сам Tween уже даёт плавность, поэтому
## в _draw() достаточно линейного lerp по этому прогрессу).
var _v_left_progress: float = 0.0    # ближний предел (TPS)
var _v_right_progress: float = 0.0   # дальний предел текущего вида
var _was_at_left_edge: bool = false
var _was_at_right_edge: bool = false

var _hide_timer: float = 0.0
var _visible_tween: Tween


func setup(on_foot_component: OnFootCameraComponent) -> void:
	_on_foot = on_foot_component
	if not _on_foot:
		push_error("[ZoomRulerHUD] setup() получил null OnFootCameraComponent — линейка не будет рисоваться")
		return
	_on_foot.zoom_input_received.connect(_on_zoom_input_received)


func _on_zoom_input_received() -> void:
	_show_ruler()
	_hide_timer = HIDE_DELAY


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = get_viewport().get_visible_rect().size
	get_viewport().size_changed.connect(_on_viewport_resized)
	modulate.a = 0.0


func _on_viewport_resized() -> void:
	size = get_viewport().get_visible_rect().size


func _process(delta: float) -> void:
	if not _on_foot:
		return

	if _hide_timer > 0.0:
		_hide_timer -= delta
		if _hide_timer <= 0.0:
			_hide_ruler()

	_update_edge_fades()
	queue_redraw()


func _show_ruler() -> void:
	if _visible_tween:
		_visible_tween.kill()
	_visible_tween = create_tween()
	_visible_tween.tween_property(self, "modulate:a", 1.0, SHOW_FADE_TIME)


func _hide_ruler() -> void:
	if _visible_tween:
		_visible_tween.kill()
	_visible_tween = create_tween()
	_visible_tween.tween_property(self, "modulate:a", 0.0, HIDE_FADE_TIME)


func _update_edge_fades() -> void:
	var zoom_range: Vector2 = _on_foot.get_current_zoom_range()
	var min_z: float = zoom_range.x
	var max_z: float = zoom_range.y
	var d: float = _on_foot.target_zoom_distance

	var at_left_edge: bool = abs(d - min_z) <= EDGE_EPSILON
	var at_right_edge: bool = abs(d - max_z) <= EDGE_EPSILON

	if at_left_edge != _was_at_left_edge:
		_was_at_left_edge = at_left_edge
		_tween_progress("_v_left_progress", 1.0 if at_left_edge else 0.0)

	if at_right_edge != _was_at_right_edge:
		_was_at_right_edge = at_right_edge
		_tween_progress("_v_right_progress", 1.0 if at_right_edge else 0.0)


func _tween_progress(property_name: String, target_value: float) -> void:
	var t := create_tween()
	t.set_ease(Tween.EASE_OUT)
	t.set_trans(Tween.TRANS_CUBIC)
	t.tween_property(self, property_name, target_value, LETTER_MOVE_TIME)
	t.tween_callback(queue_redraw)


# =============================================================================
# РИСОВАНИЕ
# =============================================================================
func _draw() -> void:
	if not _on_foot:
		return

	var cy: float = size.y - BOTTOM_MARGIN
	var cx: float = size.x / 2.0
	var left_x: float = cx - LINE_LENGTH / 2.0
	var right_x: float = cx + LINE_LENGTH / 2.0

	var zoom_range: Vector2 = _on_foot.get_current_zoom_range()
	var min_z: float = zoom_range.x
	var max_z: float = zoom_range.y
	var span: float = max_z - min_z

	var gap_xs: Array = []
	if span > 0.0:
		var steps: int = max(1, int(round(span / _on_foot.ZOOM_STEP)))
		for i in range(steps + 1):
			var t: float = float(i) / float(steps)
			gap_xs.append(lerp(left_x, right_x, t))

	_draw_ruler_line_with_glow(left_x, right_x, cy, gap_xs)

	if span > 0.0:
		var current_ratio: float = clamp((_on_foot.current_zoom_distance - min_z) / span, 0.0, 1.0)
		var marker_x: float = lerp(left_x, right_x, current_ratio)
		_draw_glow_dot(Vector2(marker_x, cy), MARKER_RADIUS, COLOR_AMBER_BRIGHT)

	_draw_edge_hints(left_x, right_x, cy)


## Дешёвое "свечение" линии — несколько проходов с увеличивающейся
## толщиной и падающей альфой поверх основной яркой линии. Линия рисуется
## сегментами с разрывами в местах шагов зума — пустой интервал размером
## с бегунок (MARKER_RADIUS*2) вместо перпендикулярных засечек.
func _draw_ruler_line_with_glow(left_x: float, right_x: float, cy: float, gap_xs: Array) -> void:
	var gap_width: float = MARKER_RADIUS * 2.0

	var glow_passes := [
		[8.0, 0.06],
		[5.0, 0.12],
		[3.0, 0.22],
	]
	for pass_data in glow_passes:
		var w: float = pass_data[0]
		var a: float = pass_data[1]
		_draw_segmented_line(left_x, right_x, cy, gap_xs, gap_width, Color(COLOR_AMBER_BRIGHT.r, COLOR_AMBER_BRIGHT.g, COLOR_AMBER_BRIGHT.b, a), w)

	_draw_segmented_line(left_x, right_x, cy, gap_xs, gap_width, COLOR_AMBER_BRIGHT, LINE_WIDTH)


## Рисует горизонтальную линию отрезками, пропуская зазор шириной
## gap_width вокруг каждой x-позиции из gap_xs.
func _draw_segmented_line(left_x: float, right_x: float, cy: float, gap_xs: Array, gap_width: float, color: Color, width: float) -> void:
	var points: Array[float] = [left_x]
	for gx in gap_xs:
		points.append(gx - gap_width / 2.0)
		points.append(gx + gap_width / 2.0)
	points.append(right_x)

	var i := 0
	while i < points.size() - 1:
		var a: float = points[i]
		var b: float = points[i + 1]
		if b > a:
			draw_line(Vector2(a, cy), Vector2(b, cy), color, width)
		i += 2


func _draw_glow_dot(pos: Vector2, radius: float, color: Color) -> void:
	draw_circle(pos, radius * 2.2, Color(color.r, color.g, color.b, 0.15))
	draw_circle(pos, radius * 1.4, Color(color.r, color.g, color.b, 0.3))
	draw_circle(pos, radius, color)


## Буквы-подсказки — без рамки и без фона, только текст. Въезжают с
## позиции в SLIDE_DISTANCE px от конца линии (наружу) к позиции покоя
## у самого конца линии, синхронно с проявлением альфы — оба завязаны
## на один и тот же _v_*_progress, который уже анимирован Tween'ом с
## ease-out, так что здесь достаточно обычного lerp.
func _draw_edge_hints(left_x: float, right_x: float, cy: float) -> void:
	if _v_left_progress > 0.01:
		var resting_x: float = left_x - LETTER_MARGIN
		var start_x: float = resting_x - SLIDE_DISTANCE
		var x: float = lerp(start_x, resting_x, _v_left_progress)
		_draw_letter(Vector2(x, cy), "V", _v_left_progress, HORIZONTAL_ALIGNMENT_RIGHT)

	if _v_right_progress > 0.01:
		var resting_x: float = right_x + LETTER_MARGIN
		var start_x: float = resting_x + SLIDE_DISTANCE
		var x: float = lerp(start_x, resting_x, _v_right_progress)
		_draw_letter(Vector2(x, cy), "V", _v_right_progress, HORIZONTAL_ALIGNMENT_LEFT)


## alignment здесь используется только чтобы буква "росла" в нужную сторону
## от своей опорной точки (влево от x для левой стороны, вправо для правой) —
## сама draw_string не центрирует, поэтому считаем вручную через ширину строки.
func _draw_letter(anchor: Vector2, letter: String, alpha: float, alignment: HorizontalAlignment) -> void:
	var c := Color(COLOR_AMBER_BRIGHT.r, COLOR_AMBER_BRIGHT.g, COLOR_AMBER_BRIGHT.b, alpha)
	var text_width := CUSTOM_FONT.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	var ascent := CUSTOM_FONT.get_ascent(FONT_SIZE)
	var descent := CUSTOM_FONT.get_descent(FONT_SIZE)

	var x := anchor.x
	if alignment == HORIZONTAL_ALIGNMENT_RIGHT:
		x -= text_width

	var text_pos := Vector2(x, anchor.y + (ascent - descent) / 2.0)
	draw_string(CUSTOM_FONT, text_pos, letter, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, c)
