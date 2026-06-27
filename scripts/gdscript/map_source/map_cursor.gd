# =============================================================================
# MapCursor.gd
# Прикрепить к Camera3D ноде CameraSource в mapsource.tscn
# (добавляется поверх CameraSource.gd через вкладку скриптов — нет,
#  лучше сделать отдельную дочернюю ноду Node и повесить этот скрипт)
#
# ПРАВИЛЬНАЯ СТРУКТУРА:
#   CameraSource (Camera3D)
#   └── MapCursor (Node) ← этот скрипт
#
# НАЗНАЧЕНИЕ:
#   Информационный raycast из камеры в направлении курсора мыши.
#   Луч пересекает физическую геометрию (меши небоскрёбов, CityZone)
#   и определяет через какие Area3D он прошёл (страты, районы).
#
# КАК РАБОТАЕТ:
#   1. Каждый кадр стреляем Physics raycast из камеры по курсору мыши
#   2. Находим точку первого физического пересечения (hit_point)
#   3. Из hit_point проверяем все Area3D — какие содержат эту точку
#   4. Высота = hit_point.Y - Y_CITY_ZONE_TOP
#   5. Выводим в HUD: страта / район / небоскрёб ID / высота
#
# ВАЖНО — КУРСОР НЕ ПРИЛИПАЕТ К ПОЛУ:
#   Луч летит в геометрию мира и останавливается где первое пересечение.
#   Если луч попал в небоскрёб на высоте 567м — показываем 567м.
#   Если луч не попал никуда (мимо всего) — HUD показывает "нет данных".
#
# COLLISION LAYERS:
#   Слой 1 — статическая геометрия (WorldZone, CityZone, небоскрёбы-кубы)
#   Слой 2 — Area3D страт и районов (они мониторят тела, не блокируют луч)
#   Raycast бьёт только по слою 1 — физические меши.
#   Area3D проверяем отдельно через has_point().
# =============================================================================

extends Node


# ── Константы ────────────────────────────────────────────────────────────────

## Y верхней поверхности CityZone меша.
## От этого значения считаем высоту игрока/курсора над городом.
const Y_CITY_ZONE_TOP: float = 10.0

## Длина луча — должна перекрывать весь игровой объём по диагонали.
## 2100×8600×1700 → диагональ ~9100. Берём с запасом.
const RAY_LENGTH: float = 10000.0

## Коллизионная маска для raycast — бьём только по слою 1 (геометрия).
## Area3D должны быть на ДРУГИХ слоях чтобы не мешать лучу.
const RAY_COLLISION_MASK: int = 1


# ── Ссылки на ноды ───────────────────────────────────────────────────────────
# Пути идут от корня сцены MapSource (родитель CameraSource → корень сцены).

@onready var city_zone: StaticBody3D = $"../../../CityZone/StaticBody3D"

@onready var strata_doggerland: Area3D = $"../../../STRATA_Doggerland"
@onready var strata_manifold:   Area3D = $"../../../STRATA_Manifold"
@onready var strata_glare:      Area3D = $"../../../STRATA_Glare"

@onready var district_central: Area3D = $"../../../District_CENTRAL"
@onready var district_south:   Area3D = $"../../../District_SOUTH"
@onready var district_north:   Area3D = $"../../../District_NORTH"

## Камера-родитель — нужна для project_ray_*
@onready var _camera: Camera3D = $".."
var _hovered_tower: SkyscraperMarker = null

# ── Словари Area3D → читаемые имена ──────────────────────────────────────────
# Заполняются в _ready() после того как ноды инициализированы.

var _strata_map:   Dictionary = {}
var _district_map: Dictionary = {}


# ── HUD ноды (строятся процедурно) ───────────────────────────────────────────

var _canvas:      CanvasLayer
var _label_info:  Label
var _label_hover: Label


# ── Состояние ────────────────────────────────────────────────────────────────

## Последняя точка попадания луча в геометрию
var _hit_point:    Vector3 = Vector3.ZERO
## Был ли хит в этом кадре
var _has_hit:      bool    = false
## ID небоскрёба под курсором (пусто если нет)
var _hovered_sc:   String  = ""
var _tower_strata: String = ""


# ── Жизненный цикл ───────────────────────────────────────────────────────────

func _ready() -> void:
	# Ждём один кадр чтобы все @onready ссылки гарантированно разрешились
	await get_tree().process_frame

	_build_hud()
	_fill_area_maps()
	#debug_dump_world()
	print("[MapCursor] ✅ Ready")
	


func _process(_delta: float) -> void:
	_cast_ray()
	_update_hud()


# ── Raycast ───────────────────────────────────────────────────────────────────

func _cast_ray() -> void:
	if not is_instance_valid(_camera):
		_has_hit = false
		return

	var viewport   := get_viewport()
	var mouse_pos  := viewport.get_mouse_position()

	# Строим луч из экранной позиции курсора
	var ray_origin := _camera.project_ray_origin(mouse_pos)
	var ray_dir    := _camera.project_ray_normal(mouse_pos)
	var ray_end    := ray_origin + ray_dir * RAY_LENGTH

	# PhysicsRayQueryParameters3D — запрос к физическому серверу
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collision_mask = RAY_COLLISION_MASK
	# Исключаем Area3D из хита — они не должны останавливать луч
	# (Area3D на слое 2, маска = 1, поэтому они итак исключены)

	var space_state := _camera.get_world_3d().direct_space_state  # ← фикс
	var result      := space_state.intersect_ray(query)

	if result.is_empty():
		# Луч не попал ни в что физическое
		_has_hit     = false
		_hit_point   = Vector3.ZERO
		_hovered_sc  = ""
		_tower_strata = ""
		return

	# Луч попал — запоминаем точку и тело
	# Луч попал — запоминаем точку и тело
	_has_hit = true
	_hit_point = result["position"]

	_hovered_sc = ""
	_hovered_tower = null

	var collider = result.get("collider")

	if is_instance_valid(collider):
		_hovered_tower = _find_tower_in_ancestors(collider)

		if _hovered_tower:
			_hovered_sc = _hovered_tower.skyscraper_name
			
		_tower_strata = ""

		if collider.has_meta("strata_name"):
			_tower_strata = str(collider.get_meta("strata_name"))

## Ищем sc_id поднимаясь вверх по иерархии от collider до корня сцены.
## Raycast бьёт в CollisionShape/StaticBody — sc_id может быть на 1-2 уровня выше.
func _find_tower_in_ancestors(node: Node) -> SkyscraperMarker:
	var current := node

	while current:
		if current is SkyscraperMarker:
			return current

		current = current.get_parent()

	return null
# ── HUD ───────────────────────────────────────────────────────────────────────

func _update_hud() -> void:
	if not is_instance_valid(_label_info):
		return

	if not _has_hit:
		_label_info.text = _format_no_hit()
		return

	# ── Страта — проверяем какая Area3D содержит точку попадания ─────────────
	var strata_name := "—"
	for area: Area3D in _strata_map:
		if _point_in_area(area, _hit_point):
			strata_name = _strata_map[area]
			break

	# ── Район ─────────────────────────────────────────────────────────────────
	var district_name := "—"
	for area: Area3D in _district_map:
		if _point_in_area(area, _hit_point):
			district_name = _district_map[area]
			break

	# ── Высота над CityZone ───────────────────────────────────────────────────
	# Берём Y точки попадания и вычитаем Y верха CityZone меша
	var height := _hit_point.y - Y_CITY_ZONE_TOP
	height      = maxf(height, 0.0)   # не может быть отрицательной

	# ── Сборка строк HUD ──────────────────────────────────────────────────────
	var lines: Array[String] = []
	lines.append("🗺  MAP CURSOR")
	lines.append("──────────────────────")
	lines.append("Страта:  %s"  % strata_name)
	lines.append("Район:   %s"  % district_name)

	if _hovered_sc != "":
		lines.append("SC ID: %s" % _hovered_sc)
	else:
		lines.append("SC ID: —")

	if _hovered_tower:
		lines.append("Башня: %s" % _hovered_tower.skyscraper_name)
		lines.append("Высота башни: %.0f м" % _hovered_tower.tower_height)

		var p = _hovered_tower.global_transform.origin

		lines.append("Tower X: %.0f" % p.x)
		lines.append("Tower Y: %.0f" % p.y)
		lines.append("Tower Z: %.0f" % p.z)

	lines.append("Высота: %.0f м" % height)
	lines.append("──────────────────────")
	lines.append("X: %.0f  Z: %.0f" % [_hit_point.x, _hit_point.z])
	
	if _tower_strata != "":
		lines.append("Слой башни: %s" % _tower_strata)
	
	_label_info.text = "\n".join(lines)


func _format_no_hit() -> String:
	return "🗺  MAP CURSOR\n──────────────────────\nнет данных\n(курсор вне геометрии)"


# ── Утилиты Area3D ────────────────────────────────────────────────────────────

## Проверить находится ли точка внутри Area3D.
## Используем get_overlapping_bodies() не подходит для точки —
## вместо этого проверяем через AABB коллайдера Area3D.
## Для простых Box-коллайдеров это точно и быстро.
func _point_in_area(area: Area3D, point: Vector3) -> bool:
	if not is_instance_valid(area):
		return false

	for child in area.get_children():
		if not child is CollisionShape3D:
			continue
		var shape: Shape3D = (child as CollisionShape3D).shape
		if shape is BoxShape3D:
			var box    := shape as BoxShape3D
			var half   := box.size * 0.5
			# global_transform.origin учитывает transform всей цепочки родителей
			var center: Vector3 = (child as CollisionShape3D).global_transform.origin
			var aabb   := AABB(center - half, box.size)
			if aabb.has_point(point):
				return true
	return false


# ── Заполнение словарей Area3D → имена ───────────────────────────────────────

func _fill_area_maps() -> void:
	# Страты
	_strata_map = {}
	if is_instance_valid(strata_doggerland): _strata_map[strata_doggerland] = "Doggerland"
	if is_instance_valid(strata_manifold):   _strata_map[strata_manifold]   = "Manifold"
	if is_instance_valid(strata_glare):      _strata_map[strata_glare]      = "Glare"

	# Районы
	_district_map = {}
	if is_instance_valid(district_central): _district_map[district_central] = "Central"
	if is_instance_valid(district_south):   _district_map[district_south]   = "South"
	if is_instance_valid(district_north):   _district_map[district_north]   = "North"


# ── Построение HUD ────────────────────────────────────────────────────────────

func _build_hud() -> void:
	# CanvasLayer поверх всего — layer 20 чтобы перекрывать игровой UI
	_canvas       = CanvasLayer.new()
	_canvas.layer = 20
	# Добавляем к камере (нашему родителю Camera3D)
	_camera.add_child(_canvas)

	# ── Панель информации (левый верх) ────────────────────────────────────────
	_label_info          = Label.new()
	_label_info.position = Vector2(16.0, 16.0)
	_label_info.size     = Vector2(280.0, 200.0)
	_label_info.autowrap_mode = TextServer.AUTOWRAP_WORD

	var style_bg               := StyleBoxFlat.new()
	style_bg.bg_color           = Color(0.03, 0.03, 0.05, 0.90)
	style_bg.set_content_margin_all(12.0)
	style_bg.corner_radius_top_left     = 6
	style_bg.corner_radius_top_right    = 6
	style_bg.corner_radius_bottom_left  = 6
	style_bg.corner_radius_bottom_right = 6
	style_bg.border_color  = Color(0.2, 0.4, 0.6, 0.6)
	style_bg.border_width_left   = 1
	style_bg.border_width_right  = 1
	style_bg.border_width_top    = 1
	style_bg.border_width_bottom = 1

	_label_info.add_theme_stylebox_override("normal", style_bg)
	_label_info.add_theme_color_override("font_color", Color(0.88, 0.92, 1.0))
	_label_info.add_theme_font_size_override("font_size", 13)
	_canvas.add_child(_label_info)

	# ── Подсказка управления (правый верх) ───────────────────────────────────
	var label_help          := Label.new()
	label_help.text = "Управление:\nWASD / ←↑↓→ — движение\nПКМ + A/D — поворот камеры\nПКМ + W/S — наклон камеры\nКолесо мыши — высота\nEsc — выход"
	label_help.add_theme_font_size_override("font_size", 15)
	label_help.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7, 0.8))
	# Прибиваем к правому верхнему углу
	label_help.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	label_help.position = Vector2(-280.0, 16.0)
	_canvas.add_child(label_help)

## Вызвать в _ready() чтобы увидеть реальные AABB всех Area3D и позиции небоскрёбов.
## После проверки убрать вызов.
func debug_dump_world() -> void:
	print("\n=== [MapCursor] DEBUG DUMP ===")
	
	# Страты
	for area: Area3D in _strata_map:
		for child in area.get_children():
			if child is CollisionShape3D:
				var shape := (child as CollisionShape3D).shape
				if shape is BoxShape3D:
					var box  := shape as BoxShape3D
					var half := box.size * 0.5
					var ctr  := (child as CollisionShape3D).global_transform.origin
					print("STRATA [%s]: center=%s  size=%s  Y_range=[%.0f - %.0f]" % [
						_strata_map[area], ctr, box.size,
						ctr.y - half.y, ctr.y + half.y
					])
	
	# Районы
	for area: Area3D in _district_map:
		for child in area.get_children():
			if child is CollisionShape3D:
				var shape := (child as CollisionShape3D).shape
				if shape is BoxShape3D:
					var box  := shape as BoxShape3D
					var half := box.size * 0.5
					var ctr  := (child as CollisionShape3D).global_transform.origin
					print("DISTRICT [%s]: center=%s  X_range=[%.0f - %.0f]  Z_range=[%.0f - %.0f]" % [
						_district_map[area], ctr,
						ctr.x - half.x, ctr.x + half.x,
						ctr.z - half.z, ctr.z + half.z
					])
	
	# Небоскрёбы в контейнере
	var map_source := get_node_or_null("../../")
	if is_instance_valid(map_source):
		var sc_container := map_source.get_node_or_null("Skyscrapers")
		if is_instance_valid(sc_container):
			for child in sc_container.get_children():
				var has_id := child.has_meta("sc_id")
				print("SC_NODE [%s]: has_sc_id=%s  pos=%s" % [
					child.name, has_id,
					child.global_transform.origin
				])
	
	print("=== END DUMP ===\n")
