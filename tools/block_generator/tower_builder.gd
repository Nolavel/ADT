# =============================================================================
# tower_builder.gd — EditorScript (ОДНА башня на авторских мешах)
#
# ЗАПУСК: положить в res://tools/block_generator/, открыть → File → Run.
#
# ОТЛИЧИЕ ОТ test_block_builder: здесь НЕТ процедурных плит и НЕТ кластера.
# Геометрия целиком авторская — берётся из .tres, испечённых Стэном:
#   assets/floor_meshes/001/dog/001_dog_floor.tres   350×0.5×350
#   assets/floor_meshes/001/dog/001_dog_deck.tres    400×0.5×400
#   assets/floor_meshes/001/man/001_man_floor.tres   300×0.5×300
#   assets/floor_meshes/001/man/001_man_deck.tres    330×0.5×330
#   assets/floor_meshes/001/gla/001_glare_floor.tres 250×0.5×250
#   assets/floor_meshes/001/gla/001_glare_deck.tres  275×0.5×275
# Размер башни на каждой страте = AABB меша → ступенчатое сужение кверху
# (350→300→250) получается само, отдельный параметр taper не нужен.
#
# Меши грузятся ПО ПУТЯМ, а не по метаданным: ключи мет сейчас несогласованы
# (Floor_stratum / floor_stratum / у man_floor мет нет). Меты читаются только
# для сверки и печатаются в лог — опечатка в ключе сборку не ломает.
#
# ПИШЕТ:
#   res://world/content/blocks/test/tower_001/
#       tower_001.tscn          — Shared + Layer* (InstancePlaceholder)
#       layer_doggerland.tscn   — пирог визуальных этажей + 2 палубы
#       layer_manifold.tscn
#       layer_glare.tscn
#   res://world/silhouettes/blocks/test/tower_001_silhouette.tscn
#
# КОЛЛИЗИЯ (решение Стэна 2026-07-24): силуэт БЕЗ коллизии — только визуальный
# след для map_source. Физика есть ТОЛЬКО у палуб. Следствие: ховер пролетает
# сквозь башню насквозь — это не баг, это снятая коллизия силуэта на время
# отладки ритма и палуб.
#
# Коллизия палубы — trimesh по самому мешу (create_trimesh_shape), а не бокс:
# если в палубе есть вырез под шахту, бокс бы его заклеил, trimesh оставляет
# честную дыру. Слой 1|2 (world+floor) = как плиты земли, группа "floor".
#
# ШАХТЫ сквозные на всю страту: вырез уже внутри авторского меша, а стопка
# ставит один и тот же меш без поворотов — вырез совпадает по всей высоте.
# =============================================================================
@tool
extends EditorScript


const SEED: int = 20260724
const TOWER_ID: String = "tower_001"

const MESH_DIR:       String = "res://assets/floor_meshes/001"
const CONTENT_DIR:    String = "res://world/content/blocks/test"
const SILHOUETTE_DIR: String = "res://world/silhouettes/blocks/test"
const PROFILE_DIR:    String = "res://data/strata_deck_profiles"

## Верх башни (рваная верхушка Глэра). Играбельная полоса Глэра = [2100, TOWER_TOP].
const TOWER_TOP: float = 3000.0

const DECKS_PER_STRATUM: int = 2

## Материал greybox для авторских мешей (в самих .tres материала нет).
const MAT_CONTENT: String = "res://assets/tres/greybox_mat_content.tres"

## Пути мешей по стратам: [floor, deck].
const MESHES := {
	StrataGeometry.DOGGERLAND: ["dog/001_dog_floor.tres",   "dog/001_dog_deck.tres"],
	StrataGeometry.MANIFOLD:   ["man/001_man_floor.tres",   "man/001_man_deck.tres"],
	StrataGeometry.GLARE:      ["gla/001_glare_floor.tres", "gla/001_glare_deck.tres"],
}


func _run() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED

	var profiles := _load_profiles()
	if profiles.is_empty():
		return

	var mat := load(MAT_CONTENT) if ResourceLoader.exists(MAT_CONTENT) else null

	var tower_dir := CONTENT_DIR.path_join(TOWER_ID)
	DirAccess.make_dir_recursive_absolute(tower_dir)
	DirAccess.make_dir_recursive_absolute(SILHOUETTE_DIR)

	# 1. Слои страт.
	var layer_paths := {}
	var widest := 0.0
	for stratum in [StrataGeometry.DOGGERLAND, StrataGeometry.MANIFOLD, StrataGeometry.GLARE]:
		var floor_mesh := _load_mesh(stratum, 0)
		var deck_mesh  := _load_mesh(stratum, 1)
		if floor_mesh == null or deck_mesh == null:
			return

		var fw: float = floor_mesh.get_aabb().size.x
		var dw: float = deck_mesh.get_aabb().size.x
		widest = maxf(widest, maxf(fw, dw))
		print("[TowerBuilder] %-11s floor %.0f×%.0f  deck %.0f×%.0f  %s"
				% [stratum, fw, floor_mesh.get_aabb().size.z, dw,
				   deck_mesh.get_aabb().size.z, _meta_note(floor_mesh, deck_mesh)])

		var path := tower_dir.path_join("layer_%s.tscn" % stratum.to_lower())
		if not _save_layer(path, stratum, floor_mesh, deck_mesh,
				profiles[StrataGeometry.pattern_key(stratum)], mat, rng):
			return
		layer_paths[stratum] = path

	# 2. Корень контента.
	var content_path := tower_dir.path_join("%s.tscn" % TOWER_ID)
	if not _save_content(content_path, widest, layer_paths):
		return

	# 3. Силуэт — только визуальный след, БЕЗ коллизии.
	var sil_path := SILHOUETTE_DIR.path_join("%s_silhouette.tscn" % TOWER_ID)
	if not _save_silhouette(sil_path, widest, mat):
		return

	print("[TowerBuilder] ✅ Башня собрана: %s" % content_path)
	print("[TowerBuilder]    силуэт: %s" % sil_path)
	print("[TowerBuilder] Дальше — маркер в map_source (см. feature_test_block.gd).")


# ── Слой страты ──────────────────────────────────────────────────────────────

func _save_layer(path: String, stratum: String, floor_mesh: Mesh, deck_mesh: Mesh,
		profile: StrataDeckProfile, mat: Material,
		rng: RandomNumberGenerator) -> bool:

	var root := Node3D.new()
	root.name = "Layer%s" % stratum
	var band := StrataGeometry.playable_band(stratum, TOWER_TOP)

	_add_visual_floors(root, stratum, floor_mesh, band, profile, mat)
	_add_decks(root, stratum, deck_mesh, band, profile, mat, rng)

	return _pack_and_save(root, path)


## Пирог: авторский меш плиты, размноженный MultiMesh'ем по высоте полосы.
## Шаг = pitch × (skip+1): skip=0 — все плиты, 1 — через одну, 2 — через две.
func _add_visual_floors(root: Node3D, stratum: String, mesh: Mesh, band: Vector2,
		profile: StrataDeckProfile, mat: Material) -> void:

	var pitch: float = maxf(profile.visual_floor_pitch, 0.5) \
			* float(profile.visual_floor_skip + 1)
	var count := clampi(int((band.y - band.x) / pitch), 0, 600)
	if count <= 0:
		push_warning("[TowerBuilder] %s: шаг %.1f больше полосы — плит нет"
				% [stratum, pitch])
		return

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count
	for i in count:
		var y := band.x + (float(i) + 0.5) * pitch
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(0.0, y, 0.0)))

	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Floors_%s" % stratum
	mmi.multimesh = mm
	if mat:
		mmi.material_override = mat
	_own(root, mmi, root)
	print("[TowerBuilder]   %s: %d визуальных этажей, шаг %.1f м"
			% [stratum, count, pitch])


## Палубы: авторский широкий меш + trimesh-коллизия, 2 на страту, с разносом.
func _add_decks(root: Node3D, stratum: String, mesh: Mesh, band: Vector2,
		profile: StrataDeckProfile, mat: Material,
		rng: RandomNumberGenerator) -> void:

	var heights := _deck_heights(band, profile.deck_min_separation_frac, rng)
	for k in heights.size():
		var deck := StaticBody3D.new()
		deck.name = "Deck_%s_%d" % [stratum, k]
		# Слой 1|2 (world+floor) = как плиты земли: перс маскирует слой 1,
		# ховер 1|3 — оба цепляют через бит 1. Слой 2 несёт floor-семантику.
		deck.collision_layer = (1 << 0) | (1 << 1)
		deck.collision_mask = 0
		deck.add_to_group("floor", true)
		deck.position = Vector3(0.0, heights[k], 0.0)
		_own(root, deck, root)

		var mi := MeshInstance3D.new()
		mi.name = "Mesh"
		mi.mesh = mesh
		if mat:
			mi.material_override = mat
		_own(root, mi, deck)

		# Trimesh — точная коллизия по мешу: вырезы под шахты остаются дырами.
		var cs := CollisionShape3D.new()
		cs.name = "CollisionShape3D"
		cs.shape = mesh.create_trimesh_shape()
		_own(root, cs, deck)

	print("[TowerBuilder]   %s: палубы на %.0f и %.0f м"
			% [stratum, heights[0], heights[1]])


func _deck_heights(band: Vector2, frac: float, rng: RandomNumberGenerator) -> Array[float]:
	var lo := band.x
	var hi := band.y
	var size := hi - lo
	var sep := frac * size
	var margin := 0.05 * size

	var d0 := lo + rng.randf_range(0.10, 0.35) * size
	var d1 := lo + rng.randf_range(0.55, 0.90) * size
	if d1 - d0 < sep:
		d1 = d0 + sep
	d1 = minf(d1, hi - margin)
	if d1 - d0 < sep:
		d0 = maxf(lo + margin, d1 - sep)
	return [d0, d1]


# ── Корень контента и силуэт ─────────────────────────────────────────────────

func _save_content(path: String, widest: float, layer_paths: Dictionary) -> bool:
	var root := Node3D.new()
	root.name = TOWER_ID.to_pascal_case()
	root.set_meta("gbx_size", Vector3(widest, TOWER_TOP, widest))
	root.set_meta("gbx_strata_top", "Glare")
	root.set_meta("gbx_kind", "content")

	var shared := Node3D.new()
	shared.name = "Shared"
	_own(root, shared, root)

	for stratum in [StrataGeometry.DOGGERLAND, StrataGeometry.MANIFOLD, StrataGeometry.GLARE]:
		var scene := load(layer_paths[stratum]) as PackedScene
		if scene == null:
			push_error("[TowerBuilder] Слой не загрузился: %s" % layer_paths[stratum])
			return false
		var inst := scene.instantiate()
		inst.name = "Layer%s" % stratum
		_own(root, inst, root)
		inst.set_scene_instance_load_placeholder(true)

	return _pack_and_save(root, path)


## Силуэт БЕЗ коллизии — тонкий пад, чтобы башню было видно сверху в map_source.
func _save_silhouette(path: String, widest: float, mat: Material) -> bool:
	var root := Node3D.new()
	root.name = "%sSilhouette" % TOWER_ID.to_pascal_case()
	root.set_meta("gbx_size", Vector3(widest, TOWER_TOP, widest))
	root.set_meta("gbx_strata_top", "Glare")
	root.set_meta("gbx_kind", "silhouette")

	var pad := BoxMesh.new()
	pad.size = Vector3(widest, 3.0, widest)
	var mi := MeshInstance3D.new()
	mi.name = "Pad"
	mi.mesh = pad
	mi.position = Vector3(0.0, 1.5, 0.0)
	if mat:
		mi.material_override = mat
	_own(root, mi, root)

	return _pack_and_save(root, path)


# ── Загрузка ресурсов ────────────────────────────────────────────────────────

func _load_mesh(stratum: String, index: int) -> Mesh:
	var path := MESH_DIR.path_join(MESHES[stratum][index])
	if not ResourceLoader.exists(path):
		push_error("[TowerBuilder] Нет меша: %s" % path)
		return null
	var mesh := load(path) as Mesh
	if mesh == null:
		push_error("[TowerBuilder] Не Mesh: %s" % path)
	return mesh


## Меты только для сверки: ключи несогласованы, на логику не влияют.
func _meta_note(floor_mesh: Mesh, deck_mesh: Mesh) -> String:
	var notes: Array[String] = []
	if not (floor_mesh.has_meta("floor_stratum") or floor_mesh.has_meta("Floor_stratum")):
		notes.append("floor без меты")
	if not deck_mesh.has_meta("deck_stratum"):
		notes.append("deck без меты")
	return "" if notes.is_empty() else "⚠ " + ", ".join(notes)


func _load_profiles() -> Dictionary:
	var files := {"A": "profile_a.tres", "B": "profile_b.tres", "C": "profile_c.tres"}
	var result := {}
	for key in files:
		var path := PROFILE_DIR.path_join(files[key])
		if not ResourceLoader.exists(path):
			push_error("[TowerBuilder] Нет профиля %s — прогони test_block_builder один раз"
					% path)
			return {}
		result[key] = load(path)
	return result


# ── Утилиты ──────────────────────────────────────────────────────────────────

func _own(scene_root: Node, node: Node, parent: Node) -> void:
	parent.add_child(node)
	node.owner = scene_root


func _pack_and_save(root: Node, path: String) -> bool:
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err != OK:
		push_error("[TowerBuilder] pack() провалился для %s (err %d)" % [path, err])
		root.free()
		return false
	err = ResourceSaver.save(packed, path)
	root.free()
	if err != OK:
		push_error("[TowerBuilder] Не сохранилась сцена %s (err %d)" % [path, err])
		return false
	return true
