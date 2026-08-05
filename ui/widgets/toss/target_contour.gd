# =============================================================================
# target_contour.gd
# ## RU: Общий словарь отрисовки контура цели: пунктир → уголки → рамка.
#        Чистые статические функции, состояния не знают — рисуют то, что просят.
#        Вынесено из drag_target_button.gd, чтобы паузное меню и барабан
#        главного меню говорили одним визуальным языком из одного файла.
# ## ENG: Shared target-contour drawing vocabulary: dashes → corners → frame.
#         Pure static helpers, stateless. Extracted from drag_target_button.gd
#         so the pause menu and the main-menu drum share one visual language
#         from one file.
#
# Источник рисунка — drag_target_button.gd (этот проект), логика сохранена
# без изменений, вынесена дословно.
# =============================================================================
extends RefCounted
class_name TargetContour


## RU: Пунктирный прямоугольник. dash_offset гонит пунктир по кругу.
static func draw_dashed_rect(
	ci: CanvasItem, r: Rect2, col: Color,
	width: float, dash_length: float, dash_gap: float, dash_offset: float
) -> void:
	var pts: Array[Vector2] = [
		r.position,
		r.position + Vector2(r.size.x, 0.0),
		r.position + r.size,
		r.position + Vector2(0.0, r.size.y),
	]
	for i in 4:
		_dashed_line(ci, pts[i], pts[(i + 1) % 4], col, width, dash_length, dash_gap, dash_offset)


## RU: Уголки. length подрезается, чтобы не сомкнуться на узкой цели.
static func draw_corners(ci: CanvasItem, r: Rect2, col: Color, width: float, length: float) -> void:
	var l: float = minf(length, minf(r.size.x, r.size.y) * 0.45)
	var top_left: Vector2 = r.position
	var top_right: Vector2 = r.position + Vector2(r.size.x, 0.0)
	var bottom_right: Vector2 = r.position + r.size
	var bottom_left: Vector2 = r.position + Vector2(0.0, r.size.y)

	ci.draw_line(top_left, top_left + Vector2(l, 0.0), col, width)
	ci.draw_line(top_left, top_left + Vector2(0.0, l), col, width)
	ci.draw_line(top_right, top_right - Vector2(l, 0.0), col, width)
	ci.draw_line(top_right, top_right + Vector2(0.0, l), col, width)
	ci.draw_line(bottom_right, bottom_right - Vector2(l, 0.0), col, width)
	ci.draw_line(bottom_right, bottom_right - Vector2(0.0, l), col, width)
	ci.draw_line(bottom_left, bottom_left + Vector2(l, 0.0), col, width)
	ci.draw_line(bottom_left, bottom_left - Vector2(0.0, l), col, width)


## RU: Сплошная рамка с лёгкой заливкой — состояние «попали».
static func draw_frame(ci: CanvasItem, r: Rect2, col: Color, width: float) -> void:
	ci.draw_rect(r, col, false, width)
	ci.draw_rect(r, Color(col.r, col.g, col.b, 0.12), true)


static func _dashed_line(
	ci: CanvasItem, from: Vector2, to: Vector2, col: Color,
	width: float, dash_length: float, dash_gap: float, dash_offset: float
) -> void:
	var total: float = from.distance_to(to)
	var dir: Vector2 = (to - from).normalized()
	var step: float = dash_length + dash_gap
	var t: float = -dash_offset
	while t < total:
		var a: float = maxf(t, 0.0)
		var b: float = minf(t + dash_length, total)
		if b > a:
			ci.draw_line(from + dir * a, from + dir * b, col, width)
		t += step
