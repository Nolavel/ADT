# =============================================================================
# WorldData.gd
# Resource — главный контейнер метаданных мира (res://data/world_data.tres).
# Загружается StreamingSystems при старте World.
#
# ИЗМЕНЕНИЕ СХЕМЫ (переезд на остров, 2026-08-25):
#   − ground_tiles: Array[GroundTileData] — сетка 3×3 плит по 2200 м держала
#     пол города. Земля теперь одна: рельеф острова, статический меш с
#     HeightMapShape3D в world.tscn. Он не стримится и данными не описывается,
#     поэтому в этом файле остались только кварталы.
# =============================================================================

extends Resource
class_name WorldData

## Все кварталы, расставленные в MapSource.
@export var blocks: Array[BlockData] = []

@export var spawn_point: Vector3 = Vector3.ZERO
