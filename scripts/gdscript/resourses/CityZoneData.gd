# =============================================================================
# CityZoneData.gd
# Resource описывающий геометрию CityZone — фундамент всего города.
# Хранится как поле WorldData и инстанцируется в world.tscn через WorldBuilder.
#
# ЗАЧЕМ:
#   CityZone должна иметь идентичную геометрию в mapsource.tscn и world.tscn.
#   Храним её параметры в WorldData чтобы WorldBuilder мог создать её программно,
#   без хардкода констант в нескольких местах.
# =============================================================================
 
class_name CityZoneData
extends Resource
 
## Размер CityZone меша (XZ). Y = высота меша (origin по центру = half_y = 5).
@export var size:     Vector3 = Vector3(2100.0, 10.0, 8600.0)
 
## Мировая позиция origin ноды CityZone (центр меша по всем осям).
## При size.y=10 origin.y=5 → верхняя грань = 5 + 5 = 10 = Y_CITY_ZONE_TOP.
@export var position: Vector3 = Vector3(0.0, 5.0, 0.0)
 
## Физический материал / цвет меша (опционально, для дебага)
@export var debug_color: Color = Color(0.2, 0.22, 0.25, 1.0)
