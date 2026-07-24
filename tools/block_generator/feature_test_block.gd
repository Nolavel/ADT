# =============================================================================
# feature_test_block.gd — EditorScript (шаг B: воткнуть тестовый блок в map_source)
#
# ЗАПУСК: открыть map_source.tscn как текущую сцену редактора, открыть этот
# скрипт → File → Run (Ctrl+Shift+X). Затем Ctrl+S сцены и запустить её —
# map_source.export_data() соберёт world_data.tres, дальше стриминг покажет блок
# в world.tscn ровно как все остальные (то же кольцо-конвейер).
#
# ЧТО ДЕЛАЕТ:
#   • Удаляет прежний маркер FEATURED_3tower (повторный прогон идемпотентен).
#   • Ставит ОДИН BlockBase-маркер нашего блока block_3tower в $BLOCKS, в центр
#     города (тайл A5, позиция 0,0) — легко найти и долететь. Не GBX_-префикс,
#     так что block_placer его не трогает; и наоборот — 40 случайных блоков не
#     трогаем. Хочешь ровно «вместо одного из них» — удали любой GBX_-маркер
#     руками (маркеры авторские, двигаются/удаляются вручную по конвенции).
#   • Визуал маркера = инстанс силуэта (как у block_placer) → в map_source виден
#     футпринт кластера сверху; BlockBase возьмёт высоту из его AABB.
#
# ПОСЛЕ: если нужен спавн рядом — кнопкой «Поставить спавн» в HUD map_source
# ткни точку у центра, чтобы игрок появлялся вплотную к блоку.
# =============================================================================
@tool
extends EditorScript


const CONTENT_PATH:    String = "res://world/content/blocks/test/tower_001/tower_001.tscn"
const SILHOUETTE_PATH: String = "res://world/silhouettes/blocks/test/tower_001_silhouette.tscn"
const BLOCKBASE_SCRIPT: String = "res://core/map_source/blockbase.gd"

const MARKER_NAME: String = "tower_001"
const MARKER_ID:   String = "tower_001"
const DISTRICT:    String = "A5"

## Куда ставим блок. (0,0) = центр города (центр тайла A5). y=0 — низ блока на
## поверхности CityZone (башни идут вверх от 0).
const POSITION: Vector3 = Vector3(100.0, 0.0, 600.0)


func _run() -> void:
	var scene_root := get_scene()
	if scene_root == null or not scene_root.has_node("BLOCKS"):
		push_error("[FeatureTestBlock] Открой map_source.tscn как текущую сцену и запусти снова.")
		return
	if not ResourceLoader.exists(CONTENT_PATH) or not ResourceLoader.exists(SILHOUETTE_PATH):
		push_error("[FeatureTestBlock] Сначала прогони test_block_builder.gd — нет сцен блока.")
		return

	var blocks: Node3D = scene_root.get_node("BLOCKS")

	# Идемпотентность: убрать прежний featured-маркер.
	if blocks.has_node(MARKER_NAME):
		var old := blocks.get_node(MARKER_NAME)
		blocks.remove_child(old)
		old.free()

	var marker := Node3D.new()
	marker.set_script(load(BLOCKBASE_SCRIPT))
	marker.name = MARKER_NAME
	marker.set("id", MARKER_ID)
	marker.set("block_name", "block_3tower")
	marker.set("district", DISTRICT)
	marker.set("scene_path", CONTENT_PATH)
	marker.set("silhouette_scene_path", SILHOUETTE_PATH)

	blocks.add_child(marker)
	marker.owner = scene_root
	marker.global_position = POSITION

	# Визуал маркера = инстанс силуэта (по образцу block_placer).
	var sil := (load(SILHOUETTE_PATH) as PackedScene).instantiate()
	sil.name = "SilhouettePreview"
	marker.add_child(sil)
	sil.owner = scene_root

	print("[FeatureTestBlock] ✅ Маркер '%s' в центре города (%s). Сохрани сцену (Ctrl+S)"
			% [MARKER_NAME, str(POSITION)])
	print("[FeatureTestBlock] и запусти map_source → world_data.tres обновится, блок пойдёт в стриминг.")
