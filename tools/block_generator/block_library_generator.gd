# =============================================================================
# block_library_generator.gd — EditorScript (шаг A генератора greybox-блоков)
#
# ЗАПУСК: положить в res://tools/block_generator/, открыть в редакторе скриптов,
# File → Run (Ctrl+Shift+X). Повторный запуск с тем же SEED даёт тот же результат.
#
# ЧТО ДЕЛАЕТ:
#   • Создаёт (если нет) два общих материала:
#       res://assets/tres/greybox_mat_content.tres    — Kenney Green, triplanar
#       res://assets/tres/greybox_mat_silhouette.tres — Kenney Dark,  triplanar
#   • Генерирует BLOCK_COUNT блоков в формате, идентичном ручным блокам репо:
#       world/content/blocks/greybox/block_gbx_NNN/
#           block_gbx_NNN.tscn      — корень: Shared + InstancePlaceholder-слои
#           layer_doggerland.tscn   — только для страт, которых блок достигает
#           layer_manifold.tscn
#           layer_glare.tscn
#       world/silhouettes/blocks/greybox/block_gbx_NNN_silhouette.tscn
#   • В корне контент- и силуэт-сцен пишет меты для плейсера (шаг B) и MapSource:
#       "gbx_size": Vector3, "gbx_strata_top": String, "gbx_kind": String
#
# ГЕОМЕТРИЯ:
#   • Footprint (X/Z) выбираются независимо друг от друга из FOOTPRINT_CHOICES.
#   • Высота = DOGGERLAND_HEIGHT + MANIFOLD_HEIGHT + случайная надбавка Glare
#     (2200–3000 суммарно) — каждый блок теперь ВСЕГДА пересекает все три
#     страты, strata_top всегда "Glare".
#   • Каждый слой страты — один сплошной BoxMesh на всю ширину/глубину блока
#     и точно на высоту своей полосы (без случайного разброса пристроек).
#   • Силуэт — точная копия габарита контента (без урезания высоты) и несёт
#     постоянную коллизию (StaticBody3D, группа "wall", физслой 3) — раньше
#     силуэты были чисто визуальными.
#
# КОНВЕНЦИИ (сверено с block_a1_001 / silhouette, HEAD 7e3c400):
#   • Меши — BoxMesh, StandardMaterial3D с uv1_triplanar = true.
#   • Нижняя грань блока на y=0 локально: MeshInstance смещён на height/2.
#   • Слои страт — InstancePlaceholder (replace=false на стороне стриминга),
#     имена "Layer" + Strata — контракт StreamingSystems не меняется.
#   • Страты по высоте над CityZone: Doggerland 0–1000, Manifold 1000–2000,
#     Glare 2000–3200 (константы WorldSystems).
# =============================================================================
@tool
extends EditorScript


# ── Параметры генерации ──────────────────────────────────────────────────────

const SEED: int = 20260716

## Сколько блоков сгенерировать всего.
const BLOCK_COUNT: int = 40

## Ширина/глубина блока (м) — X и Z выбираются независимо друг от друга.
const FOOTPRINT_CHOICES: PackedFloat32Array = [400.0, 450.0, 500.0, 600.0]

## Каждый блок теперь всегда пересекает все три страты: фиксированная высота
## Doggerland + Manifold, и случайная надбавка Glare сверху.
const DOGGERLAND_HEIGHT: float = 1000.0
const MANIFOLD_HEIGHT:   float = 1000.0
const GLARE_HEIGHT_RANGE: Vector2 = Vector2(200.0, 1000.0)


# ── Пути ─────────────────────────────────────────────────────────────────────

const CONTENT_DIR:    String = "res://world/content/blocks/greybox"
const SILHOUETTE_DIR: String = "res://world/silhouettes/blocks/greybox"

const MAT_CONTENT_PATH:    String = "res://assets/tres/greybox_mat_content.tres"
const MAT_SILHOUETTE_PATH: String = "res://assets/tres/greybox_mat_silhouette.tres"

const TEX_CONTENT_PATH:    String = "res://assets/textures/prototype_tex_kenney/PNG/Green/texture_01.png"
const TEX_SILHOUETTE_PATH: String = "res://assets/textures/prototype_tex_kenney/PNG/Dark/texture_01.png"

## Границы страт над CityZone (дубли констант WorldSystems — EditorScript
## выполняется без сцены, автолоад может быть недоступен; при изменении
## геометрии мира обновить здесь вручную).
const STRATA_DOGGERLAND_TOP: float = 1000.0
const STRATA_MANIFOLD_TOP:   float = 2000.0
const STRATA_GLARE_TOP:      float = 3200.0


# ── Точка входа ──────────────────────────────────────────────────────────────

func _run() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED

	var mat_content    := _ensure_material(MAT_CONTENT_PATH, TEX_CONTENT_PATH)
	var mat_silhouette := _ensure_material(MAT_SILHOUETTE_PATH, TEX_SILHOUETTE_PATH)
	if mat_content == null or mat_silhouette == null:
		return

	DirAccess.make_dir_recursive_absolute(CONTENT_DIR)
	DirAccess.make_dir_recursive_absolute(SILHOUETTE_DIR)

	var made := 0
	for i in BLOCK_COUNT:
		var block_id := "block_gbx_%03d" % (i + 1)
		var strata_top := "Glare"

		var size := Vector3(
				FOOTPRINT_CHOICES[rng.randi_range(0, FOOTPRINT_CHOICES.size() - 1)],
				DOGGERLAND_HEIGHT + MANIFOLD_HEIGHT
						+ rng.randf_range(GLARE_HEIGHT_RANGE.x, GLARE_HEIGHT_RANGE.y),
				FOOTPRINT_CHOICES[rng.randi_range(0, FOOTPRINT_CHOICES.size() - 1)])

		if _generate_block(block_id, size, strata_top, mat_content, mat_silhouette):
			made += 1

	print("[BlockLibraryGenerator] ✅ Готово: %d/%d блоков (seed=%d)" % [made, BLOCK_COUNT, SEED])
	print("[BlockLibraryGenerator] Контент: %s  Силуэты: %s" % [CONTENT_DIR, SILHOUETTE_DIR])


# ── Материалы ────────────────────────────────────────────────────────────────

func _ensure_material(mat_path: String, tex_path: String) -> StandardMaterial3D:
	if ResourceLoader.exists(mat_path):
		return load(mat_path)

	var tex := load(tex_path) as Texture2D
	if tex == null:
		push_error("[BlockLibraryGenerator] Текстура не найдена: %s" % tex_path)
		return null

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.uv1_triplanar = true

	var err := ResourceSaver.save(mat, mat_path)
	if err != OK:
		push_error("[BlockLibraryGenerator] Не сохранился материал %s (err %d)" % [mat_path, err])
		return null
	return mat


# ── Генерация одного блока ───────────────────────────────────────────────────

func _generate_block(block_id: String, size: Vector3, strata_top: String,
		mat_content: StandardMaterial3D, mat_silhouette: StandardMaterial3D) -> bool:

	var block_dir := CONTENT_DIR.path_join(block_id)
	DirAccess.make_dir_recursive_absolute(block_dir)

	# 1. Слои страт — отдельные сцены, только для достигнутых страт.
	var layer_paths := {}   # { "Doggerland": "res://.../layer_doggerland.tscn", ... }
	for stratum in _strata_reached(size.y):
		var path := block_dir.path_join("layer_%s.tscn" % stratum.to_lower())
		if not _save_layer_scene(path, stratum, size, mat_content):
			return false
		layer_paths[stratum] = path

	# 2. Корневая контент-сцена: Shared-стержень + плейсхолдеры слоёв.
	var content_path := block_dir.path_join("%s.tscn" % block_id)
	if not _save_content_scene(content_path, block_id, size, strata_top,
			layer_paths, mat_content):
		return false

	# 3. Силуэт.
	var silhouette_path := SILHOUETTE_DIR.path_join("%s_silhouette.tscn" % block_id)
	if not _save_silhouette_scene(silhouette_path, block_id, size, strata_top,
			mat_silhouette):
		return false

	return true


## Список страт, которых блок достигает по высоте (снизу вверх).
func _strata_reached(height: float) -> Array[String]:
	var result: Array[String] = ["Doggerland"]
	if height > STRATA_DOGGERLAND_TOP:
		result.append("Manifold")
	if height > STRATA_MANIFOLD_TOP:
		result.append("Glare")
	return result


# ── Сцены ────────────────────────────────────────────────────────────────────

## Слой страты: один сплошной объём на всю ширину/глубину блока, точно
## заполняющий высотную полосу своей страты.
func _save_layer_scene(path: String, stratum: String, block_size: Vector3,
		mat: StandardMaterial3D) -> bool:

	var band := _strata_band(stratum, block_size.y)
	var root := Node3D.new()
	root.name = "Layer%s" % stratum

	var h := band.y - band.x

	var mesh := BoxMesh.new()
	mesh.size = Vector3(block_size.x, h, block_size.z)
	mesh.material = mat

	var mi := MeshInstance3D.new()
	mi.name = "MeshInstance3D"
	mi.mesh = mesh
	mi.position = Vector3(0.0, band.x + h * 0.5, 0.0)
	root.add_child(mi)
	mi.owner = root

	return _pack_and_save(root, path)


## Высотная полоса страты, обрезанная сверху высотой блока.
func _strata_band(stratum: String, block_height: float) -> Vector2:
	match stratum:
		"Doggerland":
			return Vector2(0.0, minf(STRATA_DOGGERLAND_TOP, block_height))
		"Manifold":
			return Vector2(STRATA_DOGGERLAND_TOP, minf(STRATA_MANIFOLD_TOP, block_height))
		_:
			return Vector2(STRATA_MANIFOLD_TOP, minf(STRATA_GLARE_TOP, block_height))


## Корневая контент-сцена: сквозной стержень (Shared) + плейсхолдеры слоёв.
func _save_content_scene(path: String, block_id: String, size: Vector3,
		strata_top: String, layer_paths: Dictionary,
		mat: StandardMaterial3D) -> bool:

	var root := Node3D.new()
	root.name = block_id.to_pascal_case()
	root.set_meta("gbx_size", size)
	root.set_meta("gbx_strata_top", strata_top)
	root.set_meta("gbx_kind", "content")

	# Shared — сквозной контент, живёт при любой страте (конвенция репо).
	var shared := Node3D.new()
	shared.name = "Shared"
	root.add_child(shared)
	shared.owner = root

	var spine := BoxMesh.new()
	spine.size = Vector3(size.x * 0.15, size.y, size.z * 0.15)
	spine.material = mat

	var mi := MeshInstance3D.new()
	mi.name = "MeshInstance3D"
	mi.mesh = spine
	mi.position = Vector3(0.0, size.y * 0.5, 0.0)
	shared.add_child(mi)
	mi.owner = root

	# Слои страт — InstancePlaceholder на сцены слоёв.
	for stratum in layer_paths:
		var layer_scene := load(layer_paths[stratum]) as PackedScene
		if layer_scene == null:
			push_error("[BlockLibraryGenerator] Слой не загрузился: %s" % layer_paths[stratum])
			return false
		var inst := layer_scene.instantiate()
		inst.name = "Layer%s" % stratum
		root.add_child(inst)
		inst.owner = root
		inst.set_scene_instance_load_placeholder(true)

	return _pack_and_save(root, path)


## Силуэт: один сегмент-меш на каждую достигнутую страту (нижняя грань блока
## на y=0, каждый сегмент точно заполняет свою высотную полосу) — сегменты
## скрываются/показываются независимо, когда игрок проходит сквозь блок по
## страте. Коллизия НЕ сегментируется — один сплошной StaticBody3D на весь
## size, группа "wall" (физслой 3, project.godot), никогда не выгружается.
func _save_silhouette_scene(path: String, block_id: String, size: Vector3,
		strata_top: String, mat: StandardMaterial3D) -> bool:

	var root := Node3D.new()
	root.name = "%sSilhouette" % block_id.to_pascal_case()
	root.set_meta("gbx_size", size)
	root.set_meta("gbx_strata_top", strata_top)
	root.set_meta("gbx_kind", "silhouette")

	for stratum in _strata_reached(size.y):
		var band := _strata_band(stratum, size.y)
		var h := band.y - band.x

		var mesh := BoxMesh.new()
		mesh.size = Vector3(size.x, h, size.z)
		mesh.material = mat

		var mi := MeshInstance3D.new()
		mi.name = "Mesh%s" % stratum
		mi.mesh = mesh
		mi.position = Vector3(0.0, band.x + h * 0.5, 0.0)
		root.add_child(mi)
		mi.owner = root

	var body := StaticBody3D.new()
	body.name = "StaticBody3D"
	body.collision_layer = 1 << 2   # физслой 3 = "wall" (project.godot)
	body.collision_mask  = 0
	body.add_to_group("wall", true)   # persistent=true — иначе группа не сохранится в .tscn
	root.add_child(body)
	body.owner = root

	var shape := BoxShape3D.new()
	shape.size = size

	var cs := CollisionShape3D.new()
	cs.name = "CollisionShape3D"
	cs.shape = shape
	cs.position = Vector3(0.0, size.y * 0.5, 0.0)
	body.add_child(cs)
	cs.owner = root

	return _pack_and_save(root, path)


# ── Утилиты ──────────────────────────────────────────────────────────────────

func _pack_and_save(root: Node, path: String) -> bool:
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err != OK:
		push_error("[BlockLibraryGenerator] pack() провалился для %s (err %d)" % [path, err])
		root.free()
		return false

	err = ResourceSaver.save(packed, path)
	root.free()
	if err != OK:
		push_error("[BlockLibraryGenerator] Не сохранилась сцена %s (err %d)" % [path, err])
		return false
	return true
