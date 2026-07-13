# =============================================================================
# WorldData.gd
# Resource — главный контейнер метаданных мира (res://data/world_data.tres).
# Загружается StreamingSystems при старте World.
#
# ИЗМЕНЕНИЕ СХЕМЫ (миграция на тайловый стриминг):
#   − city_zone: CityZoneData — монолитная плита города удалена; её заменяет
#     сетка из 9 плит (ground_tiles), участвующих в конвейере стриминга.
#   + ground_tiles / ground_tile_silhouette_path.
# =============================================================================

extends Resource
class_name WorldData

## Все кварталы, расставленные в MapSource.
@export var blocks: Array[BlockData] = []

## Плиты земли (сетка 3×3). Геометрия сетки — в константах WorldSystems.
@export var ground_tiles: Array[GroundTileData] = []

## Ring 0 всех плит: один общий силуэт (коллизия + простой меш).
## Инстанцируется StreamingSystems по одному разу на каждую запись
## ground_tiles и никогда не выгружается.
@export_file("*.tscn") var ground_tile_silhouette_path: String = \
		"res://world/silhouettes/ground_tiles/gt_silhouette.tscn"

@export var spawn_point: Vector3 = Vector3.ZERO
