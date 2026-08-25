# =============================================================================
# block_placer.gd — EditorScript (шаг B генератора greybox-блоков)
#
# ЗАПУСК: открыть map_source.tscn как текущую сцену редактора, затем открыть
# этот скрипт и File → Run (Ctrl+Shift+X). После прогона — Ctrl+S сцены.
#
# ЧТО ДЕЛАЕТ:
#   • Собирает библиотеку блоков из world/content/blocks/greybox/ (пары
#     контент + силуэт по конвенции имён шага A).
#   • Расставляет BlockBase-маркеры в $BLOCKS открытой map_source.tscn:
#     сетка подъячеек внутри каждого из 9 тайлов + джиттер, детерминировано
#     сидом. Один и тот же блок используется в нескольких маркерах —
#     намеренный тест _packed_cache стриминга на общих scene_path.
#   • Каждому маркеру: уникальный id, district по тайлу (A1..A9),
#     scene_path (контент) и silhouette_scene_path (патч BlockBase v1),
#     позиция y = 0 — сцены шага A имеют нижнюю грань на y=0, стриминг
#     ставит корень сцены ровно в позицию маркера (bd.position).
#   • Визуал маркера — инстанс силуэта дочерней нодой: в mapsource видны
#     реальные габариты, BlockBase._compute_height() берёт высоту из его AABB.
#
# АВТОРСКИЙ КОНТРОЛЬ: после прогона маркеры — обычные ноды сцены. Двигай,
# удаляй, добавляй руками; export_data() map_source соберёт world_data.tres
# из фактического состояния $BLOCKS. Повторный прогон скрипта СНАЧАЛА удаляет
# только ноды с префиксом GBX_ (ручные маркеры не трогает).
# =============================================================================
@tool
extends EditorScript


# ── Параметры ────────────────────────────────────────────────────────────────

const SEED: int = 20260716

## Подъячейки внутри тайла (3×3 → до 9 маркеров на тайл, до 81 всего).
const SUBGRID: Vector2i = Vector2i(3, 3)

## Вероятность занять подъячейку — даёт разреженность и вариацию силуэта города.
const FILL_CHANCE: float = 0.85

## Джиттер позиции внутри подъячейки, доля её свободного пространства.
const JITTER: float = 0.6

## Префикс имён нод сгенерированных маркеров (по нему же чистка при повторе).
const MARKER_PREFIX: String = "GBX_"


# ── Пути и геометрия ─────────────────────────────────────────────────────────

const LIBRARY_CONTENT_DIR:    String = "res://world/content/blocks/greybox"
const LIBRARY_SILHOUETTE_DIR: String = "res://world/silhouettes/blocks/greybox"
const BLOCKBASE_SCRIPT_PATH:  String = "res://core/map_source/blockbase.gd"

## УСТАРЕЛ ВМЕСТЕ С ГОРОДОМ. Эти три числа описывали сетку 3×3 плит по 2200 м,
## по которой скрипт раскладывал кварталы. В `WorldSystems` их больше нет —
## земля теперь одна, рельеф острова (переезд, 2026-08-25), — и здесь они
## остались только как собственные константы этого скрипта.
##
## Прогонять его сейчас БЕССМЫСЛЕННО: он расставит кварталы по квадрату
## 6600 × 6600 м вокруг начала координат, то есть в море вокруг острова, и на
## Y 0, то есть под водой. Замена — генератор застройки по heightmap, шаг 5
## островного ТЗ. Скрипт оставлен, а не удалён, потому что его сбор библиотеки
## и очистка маркеров (`_collect_library`, `_clear_generated_markers`) новому
## генератору пригодятся как есть.
const GROUND_TILE_SIZE: float    = 2200.0
const GROUND_GRID_SIZE: Vector2i = Vector2i(3, 3)
const Y_CITY_ZONE_TOP:  float    = 0.0


# ── Точка входа ──────────────────────────────────────────────────────────────

func _run() -> void:
	var scene_root := get_scene()
	if scene_root == null or not scene_root.has_node("BLOCKS"):
		push_error("[BlockPlacer] Открой map_source.tscn как текущую сцену и запусти снова.")
		return
	var blocks_container: Node3D = scene_root.get_node("BLOCKS")

	var library := _collect_library()
	if library.is_empty():
		push_error("[BlockPlacer] Библиотека пуста: %s" % LIBRARY_CONTENT_DIR)
		return

	var removed := _clear_generated_markers(blocks_container)

	var rng := RandomNumberGenerator.new()
	rng.seed = SEED

	var placed := 0
	var cell_size := GROUND_TILE_SIZE / float(SUBGRID.x)   # подъячейки квадратные
	var city_half := GROUND_TILE_SIZE * GROUND_GRID_SIZE.x * 0.5

	for tile_row in GROUND_GRID_SIZE.y:
		for tile_col in GROUND_GRID_SIZE.x:
			var district := "A%d" % (tile_row * GROUND_GRID_SIZE.x + tile_col + 1)
			var tile_origin := Vector2(
					-city_half + tile_col * GROUND_TILE_SIZE,
					-city_half + tile_row * GROUND_TILE_SIZE)

			for sub_row in SUBGRID.y:
				for sub_col in SUBGRID.x:
					if rng.randf() > FILL_CHANCE:
						continue

					var entry: Dictionary = library[rng.randi() % library.size()]

					# Блок должен помещаться в подъячейку с запасом под джиттер.
					var footprint := maxf(entry["size"].x, entry["size"].z)
					if footprint > cell_size:
						continue   # слишком крупный для этой сетки — пропуск

					var free_space := cell_size - footprint
					var center := tile_origin + Vector2(
							(sub_col + 0.5) * cell_size,
							(sub_row + 0.5) * cell_size)
					var pos := Vector3(
							center.x + rng.randf_range(-0.5, 0.5) * free_space * JITTER,
							Y_CITY_ZONE_TOP,
							center.y + rng.randf_range(-0.5, 0.5) * free_space * JITTER)

					placed += 1
					_spawn_marker(blocks_container, scene_root, entry, pos,
							district, placed)

	print("[BlockPlacer] ✅ Удалено старых GBX-маркеров: %d, расставлено: %d (seed=%d)"
			% [removed, placed, SEED])
	print("[BlockPlacer] Сохрани сцену (Ctrl+S), затем запусти её — map_source экспортирует world_data.tres.")


# ── Библиотека ───────────────────────────────────────────────────────────────

## [{ "block_id", "content_path", "silhouette_path", "size": Vector3 }, ...]
func _collect_library() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var dir := DirAccess.open(LIBRARY_CONTENT_DIR)
	if dir == null:
		return result

	for block_id in dir.get_directories():
		var content_path := "%s/%s/%s.tscn" % [LIBRARY_CONTENT_DIR, block_id, block_id]
		var silhouette_path := "%s/%s_silhouette.tscn" % [LIBRARY_SILHOUETTE_DIR, block_id]
		if not ResourceLoader.exists(content_path) \
				or not ResourceLoader.exists(silhouette_path):
			push_warning("[BlockPlacer] Пропуск %s — нет пары контент/силуэт" % block_id)
			continue

		# Габариты читаем из меты силуэта, не инстанцируя контент.
		var sil := (load(silhouette_path) as PackedScene).instantiate()
		var size: Vector3 = sil.get_meta("gbx_size", Vector3.ZERO)
		sil.free()
		if size == Vector3.ZERO:
			push_warning("[BlockPlacer] Пропуск %s — нет меты gbx_size" % block_id)
			continue

		result.append({
			"block_id":        block_id,
			"content_path":    content_path,
			"silhouette_path": silhouette_path,
			"size":            size,
		})
	return result


# ── Маркеры ──────────────────────────────────────────────────────────────────

func _spawn_marker(container: Node3D, scene_root: Node, entry: Dictionary,
		pos: Vector3, district: String, index: int) -> void:

	var marker := Node3D.new()
	marker.set_script(load(BLOCKBASE_SCRIPT_PATH))
	marker.name = "%s%03d_%s" % [MARKER_PREFIX, index, entry["block_id"]]

	marker.set("id", "gbx_%03d" % index)
	marker.set("block_name", entry["block_id"])
	marker.set("district", district)
	marker.set("scene_path", entry["content_path"])
	marker.set("silhouette_scene_path", entry["silhouette_path"])

	container.add_child(marker)
	marker.owner = scene_root
	marker.global_position = pos

	# Визуал маркера = инстанс силуэта. BlockBase найдёт его меш и возьмёт
	# высоту из AABB (высота силуэта, ~0.82 полной — для страт-регистрации ок).
	var sil := (load(entry["silhouette_path"]) as PackedScene).instantiate()
	sil.name = "SilhouettePreview"
	marker.add_child(sil)
	sil.owner = scene_root


## Удаляет только ранее сгенерированные маркеры (по префиксу имени).
func _clear_generated_markers(container: Node3D) -> int:
	var removed := 0
	for child in container.get_children():
		if String(child.name).begins_with(MARKER_PREFIX):
			container.remove_child(child)
			child.free()
			removed += 1
	return removed
