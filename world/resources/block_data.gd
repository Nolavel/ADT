# =============================================================================
# BlockData.gd
# Resource — описывает один квартал (block). Хранится внутри WorldData.tres.
#
# Два пути к сценам — это два кольца стриминга:
#   silhouette_scene_path — Ring 0: лёгкий силуэт (меш + коллизия габарита),
#                           загружается при старте мира и живёт постоянно.
#   content_scene_path    — Ring 1: полный контент квартала целиком,
#                           грузится/выгружается конвейером StreamingSystems
#                           по радиусу от игрока.
# =============================================================================

extends Resource
class_name BlockData

@export var id:       String
@export var position: Vector3
@export var height:   float
@export var district: String

@export_group("Streaming Scenes")
@export_file("*.tscn") var silhouette_scene_path: String
@export_file("*.tscn") var content_scene_path:    String
