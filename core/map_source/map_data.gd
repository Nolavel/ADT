extends Resource
class_name MapData
# MapData.gd
# Ресурс — источник правды для всей карты.
# Сохраняется как .tres и дублируется в JSON.

@export var world_zone_size:      Vector2 = Vector2(2500.0, 9200.0)
@export var island_size:          Vector2 = Vector2(2100.0, 8600.0)
@export var island_position:      Vector3 = Vector3.ZERO

# Высоты ярусов (глобальные Y)
@export var tier_doggerland_min:  float = 0.0
@export var tier_doggerland_max:  float = 566.0
@export var tier_middle_min:      float = 566.0
@export var tier_middle_max:      float = 1133.0
@export var tier_top_min:         float = 1133.0
@export var tier_top_max:         float = 1700.0

# Небоскрёбы: { "SC001": { position, height, tier_bounds } }
@export var skyscrapers:          Dictionary = {}

# Районы: { "District_01": { position, size } }
@export var districts:            Dictionary = {}

# Кварталы: { "Block_01_A": { position, size, district } }
@export var blocks:               Dictionary = {}
