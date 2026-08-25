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
#       world/silhouettes/blocks/greybox/block_gbx_NNN_silhouette.tscn
#   • В корне контент- и силуэт-сцен пишет меты для плейсера (шаг B) и MapSource:
#       "gbx_size": Vector3, "gbx_kind": String
#
# ГЕОМЕТРИЯ:
#   • Footprint (X/Z) выбираются независимо друг от друга из FOOTPRINT_CHOICES.
#   • Высота — случайная из HEIGHT_RANGE. Диапазон островной: башни кальдеры
#     30–150 м, склона 200–500 м; вертикального города на 3200 м больше нет.
#   • Контент блока — один сплошной BoxMesh на всю ширину/глубину и высоту.
#   • Силуэт — точная копия габарита контента (без урезания высоты) и несёт
#     постоянную коллизию (StaticBody3D, группа "wall", физслой 3) — раньше
#     силуэты были чисто визуальными.
#
# КОНВЕНЦИИ (сверено с block_a1_001 / silhouette, HEAD 7e3c400):
#   • Меши — BoxMesh, StandardMaterial3D с uv1_triplanar = true.
#   • Нижняя грань блока на y=0 локально: MeshInstance смещён на height/2.
#   • Слоёв страт больше нет (переезд на остров, 2026-08-25): контент блока —
#     одна сцена целиком, InstancePlaceholder и контракт имён "Layer" + страта
#     удалены вместе со стратами в StreamingSystems.
# =============================================================================
@tool
extends EditorScript


# ── Параметры генерации ──────────────────────────────────────────────────────

const SEED: int = 20260716

## Сколько блоков сгенерировать всего.
const BLOCK_COUNT: int = 40

## Ширина/глубина блока (м) — X и Z выбираются независимо друг от друга.
const FOOTPRINT_CHOICES: PackedFloat32Array = [400.0, 450.0, 500.0, 600.0]

## Высота блока (м). Островной диапазон: дно кальдеры 30–150, полка 100–300,
## внешний склон 200–500. Одна смысловая башня на 1000 м ставится вручную и
## этим генератором не выбирается.
const HEIGHT_RANGE: Vector2 = Vector2(30.0, 500.0)


# ── Пути ─────────────────────────────────────────────────────────────────────

const CONTENT_DIR:    String = "res://world/content/blocks/greybox"
const SILHOUETTE_DIR: String = "res://world/silhouettes/blocks/greybox"

const MAT_CONTENT_PATH:    String = "res://assets/tres/greybox_mat_content.tres"
const MAT_SILHOUETTE_PATH: String = "res://assets/tres/greybox_mat_silhouette.tres"

const TEX_CONTENT_PATH:    String = "res://assets/textures/prototype_tex_kenney/PNG/Green/texture_01.png"
const TEX_SILHOUETTE_PATH: String = "res://assets/textures/prototype_tex_kenney/PNG/Dark/texture_01.png"


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

		var size := Vector3(
				FOOTPRINT_CHOICES[rng.randi_range(0, FOOTPRINT_CHOICES.size() - 1)],
				rng.randf_range(HEIGHT_RANGE.x, HEIGHT_RANGE.y),
				FOOTPRINT_CHOICES[rng.randi_range(0, FOOTPRINT_CHOICES.size() - 1)])

		if _generate_block(block_id, size, mat_content, mat_silhouette):
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

func _generate_block(block_id: String, size: Vector3,
		mat_content: StandardMaterial3D, mat_silhouette: StandardMaterial3D) -> bool:

	var block_dir := CONTENT_DIR.path_join(block_id)
	DirAccess.make_dir_recursive_absolute(block_dir)

	# 1. Контент-сцена — целиком, одним файлом.
	var content_path := block_dir.path_join("%s.tscn" % block_id)
	if not _save_content_scene(content_path, block_id, size, mat_content):
		return false

	# 2. Силуэт.
	var silhouette_path := SILHOUETTE_DIR.path_join("%s_silhouette.tscn" % block_id)
	if not _save_silhouette_scene(silhouette_path, block_id, size, mat_silhouette):
		return false

	return true


# ── Сцены ────────────────────────────────────────────────────────────────────

## Корневая контент-сцена: сквозной стержень (Shared) + плейсхолдеры слоёв.
func _save_content_scene(path: String, block_id: String, size: Vector3,
		mat: StandardMaterial3D) -> bool:

	var root := Node3D.new()
	root.name = block_id.to_pascal_case()
	root.set_meta("gbx_size", size)
	root.set_meta("gbx_kind", "content")

	# Shared — конвенция репо: сквозной узел контента. Раньше здесь жил
	# тонкий стержень, а объём блока приходил слоями страт; слоёв нет, поэтому
	# объём переехал сюда целиком.
	var shared := Node3D.new()
	shared.name = "Shared"
	root.add_child(shared)
	shared.owner = root

	var volume := BoxMesh.new()
	volume.size = size
	volume.material = mat

	var mi := MeshInstance3D.new()
	mi.name = "MeshInstance3D"
	mi.mesh = volume
	mi.position = Vector3(0.0, size.y * 0.5, 0.0)
	shared.add_child(mi)
	mi.owner = root

	return _pack_and_save(root, path)


## Силуэт: один меш на весь габарит (нижняя грань блока на y=0). Раньше он
## резался на сегменты "Mesh" + страта, которые гасились по одному по мере
## материализации соответствующего страт-слоя; слоёв нет, и стриминг теперь
## гасит силуэт целиком, так что сегментировать нечего.
## Коллизия — сплошной StaticBody3D на весь size, группа "wall" (физслой 3,
## project.godot), никогда не выгружается.
func _save_silhouette_scene(path: String, block_id: String, size: Vector3,
		mat: StandardMaterial3D) -> bool:

	var root := Node3D.new()
	root.name = "%sSilhouette" % block_id.to_pascal_case()
	root.set_meta("gbx_size", size)
	root.set_meta("gbx_kind", "silhouette")

	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat

	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = mesh
	mi.position = Vector3(0.0, size.y * 0.5, 0.0)
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
