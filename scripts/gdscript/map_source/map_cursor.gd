# =============================================================================
# MapCursor.gd
# Прикрепить как дочернюю Node к CameraSource (Camera3D) в mapsource.tscn
#
# ПРАВИЛЬНАЯ СТРУКТУРА:
#   CameraSource (Camera3D + CameraSource.gd)
#   └── MapCursor (Node) ← этот скрипт
#
# НАЗНАЧЕНИЕ:
#   Информационный raycast из камеры по курсору мыши.
#   Определяет: страту, район, башню под курсором, высоту точки попадания.
#   Выводит всё в HUD-лейбл.
#
# COLLISION LAYERS:
#   Слой 1 — статическая геометрия (WorldZone, CityZone, кубы башен)
#   Слой 2 — Area3D страт и районов (не блокируют луч)
#   Raycast бьёт только по слою 1. Area3D проверяем через AABB отдельно.
# =============================================================================

extends Node


# ── Константы ────────────────────────────────────────────────────────────────

const Y_CITY_ZONE_TOP:    float = 10.0
const RAY_LENGTH:         float = 10000.0
const RAY_COLLISION_MASK: int   = 1


# ── Ссылки на ноды сцены ─────────────────────────────────────────────────────
# Пути: MapCursor → CameraSource → MapSource (корень)
# Значит ".." = CameraSource, "../.." = MapSource

@onready var strata_doggerland: Area3D = $"../../../STRATA_Doggerland"
@onready var strata_manifold:   Area3D = $"../../../STRATA_Manifold"
@onready var strata_glare:      Area3D = $"../../../STRATA_Glare"

@onready var district_A1: Area3D = $"../../../Districts/A1"
@onready var district_A2: Area3D = $"../../../Districts/A2"
@onready var district_A3: Area3D = $"../../../Districts/A3"
@onready var district_A4: Area3D = $"../../../Districts/A4"
@onready var district_A5: Area3D = $"../../../Districts/A5"
@onready var district_A6: Area3D = $"../../../Districts/A6"
@onready var district_A7: Area3D = $"../../../Districts/A7"
@onready var district_A8: Area3D = $"../../../Districts/A8"
@onready var district_A9: Area3D = $"../../../Districts/A9"

## Камера-родитель — нужна для project_ray_origin / project_ray_normal
@onready var _camera: Camera3D = $".."


# ── Словари Area3D → читаемые имена ──────────────────────────────────────────

var _strata_map:   Dictionary = {}
var _district_map: Dictionary = {}


# ── HUD ──────────────────────────────────────────────────────────────────────

var _canvas:     CanvasLayer
var _label_info: Label


# ── Состояние raycast ────────────────────────────────────────────────────────

var _hit_point:    Vector3     = Vector3.ZERO
var _has_hit:      bool        = false
var _hovered_tower: TowerMarker = null   # был SkyscraperMarker
var _hovered_id:   String      = ""     # был _hovered_sc (sc_id)
var _tower_strata: String      = ""


# ── Жизненный цикл ───────────────────────────────────────────────────────────

func _ready() -> void:
	await get_tree().process_frame
	_fill_area_maps()
	_build_hud()
	print("[MapCursor] ✅ Ready")


func _process(_delta: float) -> void:
	_cast_ray()
	_update_hud()


# ── Raycast ───────────────────────────────────────────────────────────────────

func _cast_ray() -> void:
	if not is_instance_valid(_camera):
		_has_hit = false
		return

	var mouse_pos  := get_viewport().get_mouse_position()
	var ray_origin := _camera.project_ray_origin(mouse_pos)
	var ray_dir    := _camera.project_ray_normal(mouse_pos)
	var ray_end    := ray_origin + ray_dir * RAY_LENGTH

	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collision_mask = RAY_COLLISION_MASK

	var space_state := _camera.get_world_3d().direct_space_state
	var result      := space_state.intersect_ray(query)

	if result.is_empty():
		_has_hit      = false
		_hit_point    = Vector3.ZERO
		_hovered_id   = ""
		_hovered_tower = null
		_tower_strata  = ""
		return

	_has_hit   = true
	_hit_point = result["position"]

	_hovered_id    = ""
	_hovered_tower = null
	_tower_strata  = ""

	var collider = result.get("collider")

	if is_instance_valid(collider):
		# Поднимаемся по иерархии — raycast бьёт в StaticBody/CollisionShape,
		# а TowerMarker может быть на 1-2 уровня выше
		_hovered_tower = _find_tower_in_ancestors(collider)

		if _hovered_tower != null:
			_hovered_id = _hovered_tower.tower_name   # был skyscraper_name

		# Опциональный мета-тег на коллайдере для имени страты башни
		if collider.has_meta("strata_name"):
			_tower_strata = str(collider.get_meta("strata_name"))


## Поднимаемся по иерархии нод пока не найдём TowerMarker или не достигнем корня.
func _find_tower_in_ancestors(node: Node) -> TowerMarker:
	var current := node
	while current != null:
		if current is TowerMarker:
			return current
		current = current.get_parent()
	return null


# ── HUD ───────────────────────────────────────────────────────────────────────

func _update_hud() -> void:
	if not is_instance_valid(_label_info):
		return

	if not _has_hit:
		_label_info.text = "🗺  MAP CURSOR\n──────────────────────\nнет данных\n(курсор вне геометрии)"
		return

	# Страта по точке попадания
	var strata_name := "—"
	for area: Area3D in _strata_map:
		if _point_in_area(area, _hit_point):
			strata_name = _strata_map[area]
			break

	# Район по точке попадания
	var district_name := "—"
	for area: Area3D in _district_map:
		if _point_in_area(area, _hit_point):
			district_name = _district_map[area]
			break

	# Высота над CityZone
	var height := maxf(_hit_point.y - Y_CITY_ZONE_TOP, 0.0)

	var lines: Array[String] = []
	lines.append("🗺  MAP CURSOR")
	lines.append("──────────────────────")
	lines.append("Страта:  %s" % strata_name)
	lines.append("Район:   %s" % district_name)

	if _hovered_tower != null:
		lines.append("Башня:   %s" % _hovered_tower.tower_name)
		lines.append("ID:      %s" % _hovered_tower.id)
		lines.append("Высота башни: %.0f м" % _hovered_tower.tower_height)
		var p := _hovered_tower.global_transform.origin
		lines.append("Pos X: %.0f  Y: %.0f  Z: %.0f" % [p.x, p.y, p.z])
	else:
		lines.append("Башня:   —")

	lines.append("Высота курсора: %.0f м" % height)
	lines.append("──────────────────────")
	lines.append("X: %.0f  Z: %.0f" % [_hit_point.x, _hit_point.z])

	if _tower_strata != "":
		lines.append("Слой башни: %s" % _tower_strata)

	_label_info.text = "\n".join(lines)


# ── Утилиты Area3D ────────────────────────────────────────────────────────────

## Проверяем находится ли точка внутри AABB CollisionShape3D Area3D.
## Работает корректно только для BoxShape3D — для страт и районов этого достаточно.
func _point_in_area(area: Area3D, point: Vector3) -> bool:
	if not is_instance_valid(area):
		return false

	for child in area.get_children():
		if not child is CollisionShape3D:
			continue
		var shape := (child as CollisionShape3D).shape
		if not shape is BoxShape3D:
			continue

		var box    := shape as BoxShape3D
		var half   := box.size * 0.5
		var center := (child as CollisionShape3D).global_transform.origin
		var aabb   := AABB(center - half, box.size)

		if aabb.has_point(point):
			return true

	return false


# ── Заполнение словарей ───────────────────────────────────────────────────────

func _fill_area_maps() -> void:
	_strata_map = {}
	if is_instance_valid(strata_doggerland): _strata_map[strata_doggerland] = "Doggerland"
	if is_instance_valid(strata_manifold):   _strata_map[strata_manifold]   = "Manifold"
	if is_instance_valid(strata_glare):      _strata_map[strata_glare]      = "Glare"

	_district_map = {}
	if is_instance_valid(district_A1): _district_map[district_A1] = "A1"
	if is_instance_valid(district_A2): _district_map[district_A2] = "A2"
	if is_instance_valid(district_A3): _district_map[district_A3] = "A3"
	if is_instance_valid(district_A4): _district_map[district_A4] = "A4"
	if is_instance_valid(district_A5): _district_map[district_A1] = "A5"
	if is_instance_valid(district_A6): _district_map[district_A6] = "A6"
	if is_instance_valid(district_A7): _district_map[district_A7] = "A7"
	if is_instance_valid(district_A8): _district_map[district_A8] = "A8"
	if is_instance_valid(district_A9): _district_map[district_A9] = "A9"

# ── Построение HUD ────────────────────────────────────────────────────────────

func _build_hud() -> void:
	_canvas       = CanvasLayer.new()
	_canvas.layer = 20
	_camera.add_child(_canvas)

	# Панель информации — левый верхний угол
	_label_info               = Label.new()
	_label_info.position      = Vector2(200.0, 16.0)
	_label_info.size          = Vector2(300.0, 260.0)
	_label_info.autowrap_mode = TextServer.AUTOWRAP_WORD

	var style_bg := StyleBoxFlat.new()
	style_bg.bg_color = Color(0.03, 0.03, 0.05, 0.90)
	style_bg.set_content_margin_all(12.0)
	style_bg.corner_radius_top_left     = 6
	style_bg.corner_radius_top_right    = 6
	style_bg.corner_radius_bottom_left  = 6
	style_bg.corner_radius_bottom_right = 6
	style_bg.border_color        = Color(0.2, 0.4, 0.6, 0.6)
	style_bg.border_width_left   = 1
	style_bg.border_width_right  = 1
	style_bg.border_width_top    = 1
	style_bg.border_width_bottom = 1

	_label_info.add_theme_stylebox_override("normal", style_bg)
	_label_info.add_theme_color_override("font_color", Color(0.88, 0.92, 1.0))
	_label_info.add_theme_font_size_override("font_size", 13)
	_canvas.add_child(_label_info)

	# Подсказка управления — правый верхний угол
	var label_help := Label.new()
	label_help.text = "Управление:\nWASD / ←↑↓→ — движение\nПКМ + A/D — поворот камеры\nПКМ + W/S — наклон камеры\nКолесо мыши — высота\nEsc — выход"
	label_help.add_theme_font_size_override("font_size", 13)
	label_help.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7, 0.8))
	label_help.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	label_help.position = Vector2(-290.0, 16.0)
	_canvas.add_child(label_help)


# ── Debug ─────────────────────────────────────────────────────────────────────

## Раскомментировать вызов в _ready() для диагностики AABB страт и районов.
func debug_dump_world() -> void:
	print("\n=== [MapCursor] DEBUG DUMP ===")

	for area: Area3D in _strata_map:
		for child in area.get_children():
			if child is CollisionShape3D:
				var shape := (child as CollisionShape3D).shape
				if shape is BoxShape3D:
					var box  := shape as BoxShape3D
					var half := box.size * 0.5
					var ctr  := (child as CollisionShape3D).global_transform.origin
					print("STRATA [%s]: center=%s  size=%s  Y=[%.0f..%.0f]" % [
						_strata_map[area], ctr, box.size,
						ctr.y - half.y, ctr.y + half.y
					])

	for area: Area3D in _district_map:
		for child in area.get_children():
			if child is CollisionShape3D:
				var shape := (child as CollisionShape3D).shape
				if shape is BoxShape3D:
					var box  := shape as BoxShape3D
					var half := box.size * 0.5
					var ctr  := (child as CollisionShape3D).global_transform.origin
					print("DISTRICT [%s]: center=%s  X=[%.0f..%.0f]  Z=[%.0f..%.0f]" % [
						_district_map[area], ctr,
						ctr.x - half.x, ctr.x + half.x,
						ctr.z - half.z, ctr.z + half.z
					])

	# Башни в контейнере
	var map_source := get_node_or_null("../../")
	if is_instance_valid(map_source):
		var towers_container := map_source.get_node_or_null("Towers")  # был "Skyscrapers"
		if is_instance_valid(towers_container):
			for child in towers_container.get_children():
				print("TOWER [%s]: pos=%s" % [child.name, child.global_transform.origin])

	print("=== END DUMP ===\n")
