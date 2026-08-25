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
# Размер башни на каждом ЯРУСЕ = AABB меша → ступенчатое сужение кверху
# (350→300→250) получается само, отдельный параметр taper не нужен.
#
# ЯРУСЫ, А НЕ СТРАТЫ (2026-08-25, переезд на остров). Раньше три меша были
# привязаны к Доггерленду / Манифолду / Глэру и выезжали тремя отдельными
# сценами через InstancePlaceholder. Страт больше нет, и стриминг больше не
# материализует слои — контент квартала приходит целиком. Ступенчатость при
# этом авторская и хорошая, поэтому она осталась: три яруса ОДНОЙ башни,
# полосы которых нарезаются из её собственной высоты.
#
# Меши грузятся ПО ПУТЯМ, а не по метаданным: ключи мет сейчас несогласованы
# (Floor_stratum / floor_stratum / у man_floor мет нет). Меты читаются только
# для сверки и печатаются в лог — опечатка в ключе сборку не ломает.
#
# ПИШЕТ:
#   res://world/content/blocks/test/tower_001/
#       tower_001.tscn          — Shared + три яруса целиком, одной сценой
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
# ШАХТЫ сквозные на весь ярус: вырез уже внутри авторского меша, а стопка
# ставит один и тот же меш без поворотов — вырез совпадает по всей высоте.
# =============================================================================
@tool
extends EditorScript


const SEED: int = 20260724
const TOWER_ID: String = "tower_001"

const MESH_DIR:       String = "res://assets/floor_meshes/001"
const CONTENT_DIR:    String = "res://world/content/blocks/test"
const SILHOUETTE_DIR: String = "res://world/silhouettes/blocks/test"
const PROFILE_DIR:    String = "res://data/deck_profiles"

## Верх башни. 1000 м — потолок острова: это та единственная смысловая башня,
## которая видна со дна кальдеры отовсюду.
const TOWER_TOP: float = 1000.0

## Глухая полоса снизу и сверху башни — ни этажей, ни палуб.
## Прежние 100 м пришли из страты высотой 1000 м и сюда не переносятся: на
## острове башни бывают по 30 м, и две техполосы по 100 м не оставили бы от
## такой башни ничего. 6 м — примерно один этаж; число ловится ногами.
const TECH_BAND: float = 6.0

const DECKS_PER_STRATUM: int = 2

## Материал greybox для авторских мешей (в самих .tres материала нет).
const MAT_CONTENT: String = "res://assets/tres/greybox_mat_content.tres"

## Ярусы башни снизу вверх: имя, пара мешей [floor, deck], профиль ритма.
## Профиль раньше выводился из страты (Доггерленд→A, Манифолд→B, Глэр→C);
## теперь он просто назван здесь, рядом с мешами, которым принадлежит.
const TIERS := [
	{"id": "Lower",  "meshes": ["dog/001_dog_floor.tres",   "dog/001_dog_deck.tres"],   "profile": "A"},
	{"id": "Middle", "meshes": ["man/001_man_floor.tres",   "man/001_man_deck.tres"],   "profile": "B"},
	{"id": "Upper",  "meshes": ["gla/001_glare_floor.tres", "gla/001_glare_deck.tres"], "profile": "C"},
]


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

	# 1. Корень контента с ярусами внутри — одной сценой, без плейсхолдеров:
	#    стриминг больше не материализует слои по отдельности.
	var content_path := tower_dir.path_join("%s.tscn" % TOWER_ID)
	var widest := _build_content(content_path, profiles, mat, rng)
	if widest <= 0.0:
		return

	# 2. Силуэт — только визуальный след, БЕЗ коллизии.
	var sil_path := SILHOUETTE_DIR.path_join("%s_silhouette.tscn" % TOWER_ID)
	if not _save_silhouette(sil_path, widest, mat):
		return

	print("[TowerBuilder] ✅ Башня собрана: %s" % content_path)
	print("[TowerBuilder]    силуэт: %s" % sil_path)
	print("[TowerBuilder] Дальше — маркер в map_source (см. feature_test_block.gd).")


# ── Ярусы башни ──────────────────────────────────────────────────────────────

## Собирает башню целиком и сохраняет её. Возвращает ширину самого широкого
## меша (нужна силуэту) или 0.0 при ошибке.
func _build_content(path: String, profiles: Dictionary, mat: Material,
		rng: RandomNumberGenerator) -> float:

	var root := Node3D.new()
	root.name = TOWER_ID.to_pascal_case()
	root.set_meta("gbx_kind", "content")

	var shared := Node3D.new()
	shared.name = "Shared"
	_own(root, shared, root)

	# Играбельная высота делится между ярусами поровну: полосы выводятся из
	# высоты САМОЙ башни, а не из внешней таблицы страт, которой больше нет.
	var playable_lo := TECH_BAND
	var playable_hi := maxf(playable_lo, TOWER_TOP - TECH_BAND)
	var tier_height := (playable_hi - playable_lo) / float(TIERS.size())

	var widest := 0.0
	for i in TIERS.size():
		var tier: Dictionary = TIERS[i]
		var tier_id: String = tier["id"]
		var floor_mesh := _load_mesh(tier, 0)
		var deck_mesh  := _load_mesh(tier, 1)
		if floor_mesh == null or deck_mesh == null:
			return 0.0

		var fw: float = floor_mesh.get_aabb().size.x
		var dw: float = deck_mesh.get_aabb().size.x
		widest = maxf(widest, maxf(fw, dw))
		print("[TowerBuilder] %-7s floor %.0f×%.0f  deck %.0f×%.0f  %s"
				% [tier_id, fw, floor_mesh.get_aabb().size.z, dw,
				   deck_mesh.get_aabb().size.z, _meta_note(floor_mesh, deck_mesh)])

		var band := Vector2(playable_lo + float(i) * tier_height,
				playable_lo + float(i + 1) * tier_height)
		var tier_root := Node3D.new()
		tier_root.name = "Tier%s" % tier_id
		_own(root, tier_root, root)

		var profile: DeckProfile = profiles[tier["profile"]]
		_add_visual_floors(root, tier_root, tier_id, floor_mesh, band, profile, mat)
		_add_decks(root, tier_root, tier_id, deck_mesh, band, profile, mat, rng)

	root.set_meta("gbx_size", Vector3(widest, TOWER_TOP, widest))
	if not _pack_and_save(root, path):
		return 0.0
	return widest


## Пирог: авторский меш плиты, размноженный MultiMesh'ем по высоте полосы.
## Шаг = pitch × (skip+1): skip=0 — все плиты, 1 — через одну, 2 — через две.
func _add_visual_floors(scene_root: Node3D, tier_root: Node3D, tier_id: String,
		mesh: Mesh, band: Vector2, profile: DeckProfile, mat: Material) -> void:

	var pitch: float = maxf(profile.visual_floor_pitch, 0.5) \
			* float(profile.visual_floor_skip + 1)
	var count := clampi(int((band.y - band.x) / pitch), 0, 600)
	if count <= 0:
		push_warning("[TowerBuilder] %s: шаг %.1f больше полосы — плит нет"
				% [tier_id, pitch])
		return

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count
	for i in count:
		var y := band.x + (float(i) + 0.5) * pitch
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(0.0, y, 0.0)))

	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Floors_%s" % tier_id
	mmi.multimesh = mm
	if mat:
		mmi.material_override = mat
	_own(scene_root, mmi, tier_root)
	print("[TowerBuilder]   %s: %d визуальных этажей, шаг %.1f м"
			% [tier_id, count, pitch])


## Палубы: авторский широкий меш + trimesh-коллизия, 2 на страту, с разносом.
func _add_decks(scene_root: Node3D, tier_root: Node3D, tier_id: String,
		mesh: Mesh, band: Vector2, profile: DeckProfile, mat: Material,
		rng: RandomNumberGenerator) -> void:

	var heights := _deck_heights(band, profile.deck_min_separation_frac, rng)
	for k in heights.size():
		var deck := StaticBody3D.new()
		deck.name = "Deck_%s_%d" % [tier_id, k]
		# Слой 1|2 (world+floor) = как плиты земли: перс маскирует слой 1,
		# ховер 1|3 — оба цепляют через бит 1. Слой 2 несёт floor-семантику.
		deck.collision_layer = (1 << 0) | (1 << 1)
		deck.collision_mask = 0
		deck.add_to_group("floor", true)
		deck.position = Vector3(0.0, heights[k], 0.0)
		_own(scene_root, deck, tier_root)

		var mi := MeshInstance3D.new()
		mi.name = "Mesh"
		mi.mesh = mesh
		if mat:
			mi.material_override = mat
		_own(scene_root, mi, deck)

		# Trimesh — точная коллизия по мешу: вырезы под шахты остаются дырами.
		var cs := CollisionShape3D.new()
		cs.name = "CollisionShape3D"
		cs.shape = mesh.create_trimesh_shape()
		_own(scene_root, cs, deck)

	print("[TowerBuilder]   %s: палубы на %.0f и %.0f м"
			% [tier_id, heights[0], heights[1]])


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


# ── Силуэт ───────────────────────────────────────────────────────────────────

## Силуэт БЕЗ коллизии — тонкий пад, чтобы башню было видно сверху в map_source.
func _save_silhouette(path: String, widest: float, mat: Material) -> bool:
	var root := Node3D.new()
	root.name = "%sSilhouette" % TOWER_ID.to_pascal_case()
	root.set_meta("gbx_size", Vector3(widest, TOWER_TOP, widest))
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

func _load_mesh(tier: Dictionary, index: int) -> Mesh:
	var path := MESH_DIR.path_join(tier["meshes"][index])
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
