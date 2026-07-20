# =============================================================================
# WorldData.gd
# Resource — главный контейнер метаданных мира (res://data/world_data.tres).
# Загружается StreamingSystems при старте World.
#
# ИЗМЕНЕНИЕ СХЕМЫ (миграция на тайловый стриминг):
#   − city_zone: CityZoneData — монолитная плита города удалена; её заменяет
#     сетка из 9 плит (ground_tiles), участвующих в конвейере стриминга.
#   + ground_tiles.
# =============================================================================

extends Resource
class_name WorldData

## Все кварталы, расставленные в MapSource.
@export var blocks: Array[BlockData] = []

## Плиты земли (сетка 3×3). Геометрия сетки — в константах WorldSystems.
## Каждая запись несёт собственный content_scene_path/silhouette_scene_path.
@export var ground_tiles: Array[GroundTileData] = []

@export var spawn_point: Vector3 = Vector3.ZERO
