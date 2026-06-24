# =============================================================================
# Spawner.gd
# Прикрепить к Node3D ноде в mapsource.tscn
# Имя ноды в сцене: Spawner
#
# НАЗНАЧЕНИЕ:
#   Маркер точки спавна игрока. Находится в MapSource — пользователь
#   перемещает эту ноду в нужное место мира (на небоскрёб, на улицу и т.д.),
#   затем сохраняет координаты в GameManager.
#
# КАК ИСПОЛЬЗОВАТЬ:
#   1. Открыть mapsource.tscn
#   2. Выбрать ноду Spawner в дереве сцены
#   3. Переместить её в нужную точку мира (3D вьюпорт редактора)
#      ИЛИ нажать кнопку "Set Spawn Here" в HUD MapSource
#   4. Нажать "Save Spawn Point" — координаты запишутся в GameManager
#   5. Запустить world.tscn — игрок появится в этой точке
#
# ВИЗУАЛ:
#   В редакторе Spawner отображается как жёлтая сфера + вертикальная линия
#   (строится процедурно в _build_gizmo()). В игре визуал скрыт.
#
# СВЯЗЬ С WORLD:
#   Spawner ТОЛЬКО записывает в GameManager.
#   World.gd ТОЛЬКО читает из GameManager.
#   Прямой связи между сценами нет — это намеренно.
# =============================================================================

extends Node3D


# ── Константы ────────────────────────────────────────────────────────────────

## Y верхней поверхности CityZone. Дефолтная высота спавна если
## пользователь не двигал Spawner — игрок появится на полу города.
const DEFAULT_SPAWN_Y: float = 10.0

## Цвет визуального маркера в редакторе
const GIZMO_COLOR: Color = Color(1.0, 0.9, 0.0, 0.9)   # жёлтый


# ── Параметры (инспектор) ────────────────────────────────────────────────────

@export_group("Spawner Settings")
## Показывать визуальный маркер во время игры (обычно false)
@export var show_in_game: bool = false
## Автоматически сохранять позицию при старте сцены MapSource.
## Удобно при итерациях — не нужно каждый раз нажимать кнопку.
@export var auto_save_on_ready: bool = false


# ── Внутренние ноды визуала ──────────────────────────────────────────────────

var _gizmo_mesh:   MeshInstance3D = null
var _gizmo_line:   MeshInstance3D = null


# ── Жизненный цикл ───────────────────────────────────────────────────────────

func _ready() -> void:
	_build_gizmo()

	# Скрываем визуал в игровом запуске если не нужен
	if not show_in_game and not Engine.is_editor_hint():
		_set_gizmo_visible(false)

	# Автосохранение позиции при старте
	if auto_save_on_ready:
		save_spawn_point()

	print("[Spawner] ✅ Ready at position: ", global_position)


# ── Публичный API ─────────────────────────────────────────────────────────────

## Сохранить текущую позицию Spawner как точку спавна игрока.
## Вызывается кнопкой в HUD или из кода.
func save_spawn_point() -> void:
	var spawn_pos := global_position

	# Если Y не задан (нода в начале координат) — используем дефолт
	if spawn_pos.y < DEFAULT_SPAWN_Y:
		spawn_pos.y = DEFAULT_SPAWN_Y
		push_warning("[Spawner] ⚠️ Spawn Y was below CityZone, clamped to %.1f" % DEFAULT_SPAWN_Y)

	GameManager.set_spawn_point(spawn_pos)
	print("[Spawner] 💾 Spawn point saved: ", spawn_pos)


## Телепортировать Spawner в указанную позицию (например по клику в MapSource HUD).
func teleport_to(pos: Vector3) -> void:
	global_position = pos
	print("[Spawner] 📍 Moved to: ", pos)


## Получить текущую позицию спавна (удобный алиас).
func get_spawn_position() -> Vector3:
	return global_position


# ── Визуальный маркер ────────────────────────────────────────────────────────

## Строим процедурный гизмо — сфера + вертикальная линия.
## Видно в редакторе и в игре (если show_in_game = true).
func _build_gizmo() -> void:
	# ── Сфера маркера ────────────────────────────────────────────────────────
	_gizmo_mesh      = MeshInstance3D.new()
	_gizmo_mesh.name = "SpawnerGizmoSphere"

	var sphere        := SphereMesh.new()
	sphere.radius      = 30.0
	sphere.height      = 60.0
	sphere.radial_segments = 16
	sphere.rings           = 8

	var mat               := StandardMaterial3D.new()
	mat.albedo_color       = GIZMO_COLOR
	mat.emission_enabled   = true
	mat.emission           = GIZMO_COLOR * 0.5
	mat.transparency       = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a     = 0.85

	_gizmo_mesh.mesh              = sphere
	_gizmo_mesh.material_override = mat
	add_child(_gizmo_mesh)

	# ── Вертикальная линия вниз до пола ──────────────────────────────────────
	# Показывает где именно на земле стоит маркер (читаемость в изо-виде)
	_gizmo_line      = MeshInstance3D.new()
	_gizmo_line.name = "SpawnerGizmoLine"

	var cylinder        := CylinderMesh.new()
	cylinder.top_radius    = 3.0
	cylinder.bottom_radius = 3.0
	cylinder.height        = 200.0   # линия 200 единиц вниз

	var line_mat              := StandardMaterial3D.new()
	line_mat.albedo_color      = GIZMO_COLOR
	line_mat.emission_enabled  = true
	line_mat.emission          = GIZMO_COLOR * 0.3

	_gizmo_line.mesh              = cylinder
	_gizmo_line.material_override = line_mat
	# Смещаем линию вниз от центра сферы
	_gizmo_line.position          = Vector3(0.0, -100.0, 0.0)
	add_child(_gizmo_line)


func _set_gizmo_visible(visible_flag: bool) -> void:
	if is_instance_valid(_gizmo_mesh):
		_gizmo_mesh.visible = visible_flag
	if is_instance_valid(_gizmo_line):
		_gizmo_line.visible = visible_flag
