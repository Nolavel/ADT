# =============================================================================
# test_block_builder.gd — EditorScript (шаг A: библиотечный блок из 3 башен)
#
# ЗАПУСК: положить в res://tools/block_generator/, открыть в редакторе скриптов,
# File → Run (Ctrl+Shift+X). Детерминировано по SEED.
#
# ПИШЕТ (в том же формате, что block_library_generator, но многобашенный):
#   res://world/content/blocks/test/block_3tower/
#       block_3tower.tscn        — корень: Shared + Layer* (InstancePlaceholder)
#       layer_doggerland.tscn    — пирог визуальных этажей + палубы этой страты
#       layer_manifold.tscn        по всем башням, что достают страту
#       layer_glare.tscn
#   res://world/silhouettes/blocks/test/block_3tower_silhouette.tscn
#   res://data/strata_deck_profiles/profile_{a,b,c}.tres  (если нет)
#
# РАСКЛАДКА ПО КОЛЬЦАМ (сверено со streaming_systems.gd):
#   • Ring 0 (силуэт, постоянный): по-башенная wall-коллизия (StaticBody, слой 3,
#     группа "wall") + тонкий футпринт-пад на башню (виден сверху в map_source,
#     вертикаль НЕ загораживает — открытый пирог остаётся виден). Дальний
#     LOD-фасад — отдельный шаг позже.
#   • Ring 1 (контент, по радиусу): слои-страты Layer<Страта> (контракт имён!).
#     В каждом слое — для каждой башни, что достаёт эту страту: MultiMesh «пирог»
#     визуальных этажей (без коллизии) + 2 палубы (StaticBody слой 2 "floor",
#     группа "floor"). Стриминг держит живой ОДНУ страту за раз.
#
# ПАЛУБА: открытая полка, торчащая из башни в каньон (deck_overhang). Слой floor(2)
# — маску floor у ховера правишь ты. Позже полка может стать нишей в фасаде.
#
# ГРАНИЦЫ ПОЛОС берутся из StrataGeometry — единый источник истины.
# =============================================================================
@tool
extends EditorScript


# ── Параметры ────────────────────────────────────────────────────────────────

const SEED: int = 20260722
const BLOCK_ID: String = "block_3tower"

const CONTENT_DIR:    String = "res://world/content/blocks/test"
const SILHOUETTE_DIR: String = "res://world/silhouettes/blocks/test"
const PROFILE_DIR:    String = "res://data/strata_deck_profiles"

## Зазор-каньон между башнями (мин по договорённости 20, рабочее 40).
const GAP: float = 40.0

## Три башни разной формы: footprint X/Z (м). Σ ширин + 2*GAP должно влезть в
## подъячейку map_source (~733 м): 480 + 80 = 560 < 733. ✅
const TOWER_FOOTPRINTS: Array[Vector2] = [
	Vector2(160.0, 180.0),
	Vector2(140.0, 220.0),
	Vector2(180.0, 150.0),
]
## Куда башня выпускает палубы-полки (в сторону каньона): +X / -X.
const DECK_DIR_X: Array[float] = [1.0, 1.0, -1.0]

## Рваный верх Глэра: высота башни случайна в диапазоне (все три страты
## достаются, в Глэре влезают 2 палубы с разносом).
const TOWER_TOP_RANGE: Vector2 = Vector2(2600.0, 3200.0)

const TEX_PATH: String = "res://assets/textures/prototype_tex_kenney/PNG/Green/texture_01.png"


# ── Точка входа ──────────────────────────────────────────────────────────────

func _run() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED

	var profiles := _ensure_profiles()
	var mat_floor := _make_material(Color(0.55, 0.62, 0.55))   # пирог
	var mat_deck  := _make_material(Color(0.95, 0.72, 0.30))   # палуба «сюда можно»
	var mat_sil   := _make_material(Color(0.22, 0.24, 0.28))   # силуэт

	var layout := _compute_layout(rng)          # Array[Dictionary] по башням
	var cluster := _cluster_size(layout)

	var block_dir := CONTENT_DIR.path_join(BLOCK_ID)
	DirAccess.make_dir_recursive_absolute(block_dir)
	DirAccess.make_dir_recursive_absolute(SILHOUETTE_DIR)

	# 1. Слои страт (все три — башни гарантированно достают Glare).
	var layer_paths := {}
	for stratum in [StrataGeometry.DOGGERLAND, StrataGeometry.MANIFOLD, StrataGeometry.GLARE]:
		var path := block_dir.path_join("layer_%s.tscn" % stratum.to_lower())
		if not _save_layer_scene(path, stratum, layout, profiles, mat_floor, mat_deck, rng):
			return
		layer_paths[stratum] = path

	# 2. Корень контента: Shared + Layer*-плейсхолдеры.
	var content_path := block_dir.path_join("%s.tscn" % BLOCK_ID)
	if not _save_content_scene(content_path, cluster, layer_paths):
		return

	# 3. Силуэт: по-башенная wall-коллизия + футпринт-пады.
	var sil_path := SILHOUETTE_DIR.path_join("%s_silhouette.tscn" % BLOCK_ID)
	if not _save_silhouette_scene(sil_path, cluster, layout, mat_sil):
		return

	print("[TestBlockBuilder] ✅ Блок собран: %s" % content_path)
	print("[TestBlockBuilder]    силуэт: %s" % sil_path)
	print("[TestBlockBuilder] Дальше — feature_test_block.gd: воткнуть маркер в map_source.")


# ── Раскладка ────────────────────────────────────────────────────────────────

## Считаем позиции/размеры/высоты башен ОДИН раз — потом все сцены (слои +
## силуэт) берут одну и ту же раскладку, чтобы башни совпадали.
func _compute_layout(rng: RandomNumberGenerator) -> Array[Dictionary]:
	var total_x := GAP * float(TOWER_FOOTPRINTS.size() - 1)
	for fp in TOWER_FOOTPRINTS:
		total_x += fp.x

	var out: Array[Dictionary] = []
	var cursor := -total_x * 0.5
	for i in TOWER_FOOTPRINTS.size():
		var fp: Vector2 = TOWER_FOOTPRINTS[i]
		var top := snappedf(rng.randf_range(TOWER_TOP_RANGE.x, TOWER_TOP_RANGE.y), 10.0)
		out.append({
			"x":        cursor + fp.x * 0.5,
			"fw":       fp.x,
			"fd":       fp.y,
			"top":      top,
			"deck_dir": DECK_DIR_X[i],
		})
		cursor += fp.x + GAP
	return out


func _cluster_size(layout: Array[Dictionary]) -> Vector3:
	var min_x := INF
	var max_x := -INF
	var max_d := 0.0
	var max_top := 0.0
	for t in layout:
		min_x = minf(min_x, t["x"] - t["fw"] * 0.5)
		max_x = maxf(max_x, t["x"] + t["fw"] * 0.5)
		max_d = maxf(max_d, t["fd"])
		max_top = maxf(max_top, t["top"])
	return Vector3(max_x - min_x, max_top, max_d)


# ── Слой страты (Ring 1) ─────────────────────────────────────────────────────

func _save_layer_scene(path: String, stratum: String, layout: Array[Dictionary],
		profiles: Dictionary, mat_floor: StandardMaterial3D,
		mat_deck: StandardMaterial3D, rng: RandomNumberGenerator) -> bool:

	var root := Node3D.new()
	root.name = "Layer%s" % stratum
	var profile: StrataDeckProfile = profiles[StrataGeometry.pattern_key(stratum)]

	for i in layout.size():
		var t: Dictionary = layout[i]
		var band := StrataGeometry.playable_band(stratum, t["top"])
		if band.y - band.x < profile.visual_floor_pitch:
			continue   # башня не достаёт эту страту содержательно

		var tower := Node3D.new()
		tower.name = "Tower_%d" % i
		tower.position = Vector3(t["x"], 0.0, 0.0)
		_own(root, tower, root)

		_add_visual_floors(root, tower, stratum, t, band, profile, mat_floor)
		_add_decks(root, tower, stratum, t, band, profile, mat_deck, rng)

	return _pack_and_save(root, path)


## Пирог: тонкие плиты на всю ширину/глубину башни с шагом pitch, только внутри
## играбельной полосы. Один MultiMesh на башню-страту — дёшево при масштабе.
func _add_visual_floors(root: Node3D, tower: Node3D, stratum: String,
		t: Dictionary, band: Vector2, profile: StrataDeckProfile,
		mat: StandardMaterial3D) -> void:

	var pitch: float = maxf(profile.visual_floor_pitch, 0.5)
	var count := clampi(int((band.y - band.x) / pitch), 0, 600)
	if count <= 0:
		return

	var slab := BoxMesh.new()
	slab.size = Vector3(t["fw"], profile.visual_floor_thickness, t["fd"])
	slab.material = mat

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = slab
	mm.instance_count = count
	for i in count:
		var y := band.x + (float(i) + 0.5) * pitch
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(0.0, y, 0.0)))

	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Floors_%s" % stratum
	mmi.multimesh = mm
	_own(root, mmi, tower)


## 2 палубы на страту: открытые полки в каньон, на разных высотах с разносом.
func _add_decks(root: Node3D, tower: Node3D, stratum: String, t: Dictionary,
		band: Vector2, profile: StrataDeckProfile, mat: StandardMaterial3D,
		rng: RandomNumberGenerator) -> void:

	var heights := _deck_heights(band, profile.deck_min_separation_frac, rng)
	var overhang: float = profile.deck_overhang
	var depth := clampf(t["fd"] * 0.6, 20.0, 60.0)
	var dir: float = t["deck_dir"]
	var face_x := dir * float(t["fw"]) * 0.5

	for k in heights.size():
		var deck := StaticBody3D.new()
		deck.name = "Deck_%s_%d" % [stratum, k]
		deck.collision_layer = 1 << 1          # физслой 2 = "floor"
		deck.collision_mask = 0
		deck.add_to_group("floor", true)       # persistent=true — иначе не в .tscn
		deck.position = Vector3(face_x + dir * overhang * 0.5, heights[k], 0.0)
		_own(root, deck, tower)

		var box := BoxShape3D.new()
		box.size = Vector3(overhang, profile.deck_slab_thickness, depth)
		var cs := CollisionShape3D.new()
		cs.name = "CollisionShape3D"
		cs.shape = box
		_own(root, cs, deck)

		var mesh := BoxMesh.new()
		mesh.size = box.size
		mesh.material = mat
		var mi := MeshInstance3D.new()
		mi.name = "Mesh"
		mi.mesh = mesh
		_own(root, mi, deck)


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


# ── Корень контента (Ring 1) ─────────────────────────────────────────────────

func _save_content_scene(path: String, cluster: Vector3, layer_paths: Dictionary) -> bool:
	var root := Node3D.new()
	root.name = BLOCK_ID.to_pascal_case()
	root.set_meta("gbx_size", cluster)
	root.set_meta("gbx_strata_top", "Glare")
	root.set_meta("gbx_kind", "content")

	# Shared — сквозной контент (контракт репо). Держим пустым: пирог живёт в
	# слоях, коллизия — в силуэте. Ничего не загораживает.
	var shared := Node3D.new()
	shared.name = "Shared"
	_own(root, shared, root)

	# Layer* — InstancePlaceholder на сцены слоёв (контракт имён стриминга).
	for stratum in [StrataGeometry.DOGGERLAND, StrataGeometry.MANIFOLD, StrataGeometry.GLARE]:
		var layer_scene := load(layer_paths[stratum]) as PackedScene
		if layer_scene == null:
			push_error("[TestBlockBuilder] Слой не загрузился: %s" % layer_paths[stratum])
			return false
		var inst := layer_scene.instantiate()
		inst.name = "Layer%s" % stratum
		_own(root, inst, root)
		inst.set_scene_instance_load_placeholder(true)

	return _pack_and_save(root, path)


# ── Силуэт (Ring 0, постоянный) ──────────────────────────────────────────────

func _save_silhouette_scene(path: String, cluster: Vector3,
		layout: Array[Dictionary], mat: StandardMaterial3D) -> bool:

	var root := Node3D.new()
	root.name = "%sSilhouette" % BLOCK_ID.to_pascal_case()
	root.set_meta("gbx_size", cluster)
	root.set_meta("gbx_strata_top", "Glare")
	root.set_meta("gbx_kind", "silhouette")

	for i in layout.size():
		var t: Dictionary = layout[i]

		# По-башенная wall-коллизия на всю высоту → каньоны пустые, башня твёрдая.
		var wall := StaticBody3D.new()
		wall.name = "Wall_%d" % i
		wall.collision_layer = 1 << 2          # физслой 3 = "wall"
		wall.collision_mask = 0
		wall.add_to_group("wall", true)
		wall.position = Vector3(t["x"], 0.0, 0.0)
		_own(root, wall, root)

		var shape := BoxShape3D.new()
		shape.size = Vector3(t["fw"], t["top"], t["fd"])
		var cs := CollisionShape3D.new()
		cs.name = "CollisionShape3D"
		cs.shape = shape
		cs.position = Vector3(0.0, t["top"] * 0.5, 0.0)
		_own(root, cs, wall)

		# Тонкий футпринт-пад: виден сверху в map_source (авторинг), вертикаль
		# не загораживает — открытый пирог остаётся виден.
		var pad := BoxMesh.new()
		pad.size = Vector3(t["fw"], 3.0, t["fd"])
		pad.material = mat
		var mi := MeshInstance3D.new()
		mi.name = "Pad_%d" % i
		mi.mesh = pad
		mi.position = Vector3(t["x"], 1.5, 0.0)
		_own(root, mi, root)

	return _pack_and_save(root, path)


# ── Профили / материалы / утилиты ────────────────────────────────────────────

func _ensure_profiles() -> Dictionary:
	DirAccess.make_dir_recursive_absolute(PROFILE_DIR)
	var defaults := {
		"A": {"pitch": 5.0,  "path": "profile_a.tres"},
		"B": {"pitch": 7.0,  "path": "profile_b.tres"},
		"C": {"pitch": 12.0, "path": "profile_c.tres"},
	}
	var result := {}
	for key in defaults:
		var path := PROFILE_DIR.path_join(defaults[key]["path"])
		var profile: StrataDeckProfile
		if ResourceLoader.exists(path):
			profile = load(path)
		else:
			profile = StrataDeckProfile.new()
			profile.pattern = key
			profile.visual_floor_pitch = defaults[key]["pitch"]
			var err := ResourceSaver.save(profile, path)
			if err != OK:
				push_error("[TestBlockBuilder] Профиль не сохранился %s (err %d)" % [path, err])
		result[key] = profile
	return result


func _make_material(albedo: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = albedo
	if ResourceLoader.exists(TEX_PATH):
		mat.albedo_texture = load(TEX_PATH) as Texture2D
		mat.uv1_triplanar = true
	return mat


func _own(scene_root: Node, node: Node, parent: Node) -> void:
	parent.add_child(node)
	node.owner = scene_root


func _pack_and_save(root: Node, path: String) -> bool:
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err != OK:
		push_error("[TestBlockBuilder] pack() провалился для %s (err %d)" % [path, err])
		root.free()
		return false
	err = ResourceSaver.save(packed, path)
	root.free()
	if err != OK:
		push_error("[TestBlockBuilder] Не сохранилась сцена %s (err %d)" % [path, err])
		return false
	return true
