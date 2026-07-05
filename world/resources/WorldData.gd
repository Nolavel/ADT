# =============================================================================
# WorldData.gd
# Resource — главный контейнер метаданных мира.
# Сохраняется MapSource в res://data/world_data.tres
# Загружается StreamingSystems при старте World.
# =============================================================================

extends Resource
class_name WorldData

## Все башни расставленные в MapSource
@export var blocks: Array[BlockData] = []

## Параметры CityZone — фундамент города.
## Задаётся один раз в MapSource и воспроизводится в World через WorldBuilder.
@export var city_zone: CityZoneData = CityZoneData.new()
@export var spawn_point: Vector3 = Vector3.ZERO
