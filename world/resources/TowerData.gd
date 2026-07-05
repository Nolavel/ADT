# =============================================================================
# TowerData.gd  (был SkyscraperData.gd)
# Resource описывающий одну башню — сохраняется внутри WorldData.tres
# =============================================================================
 
extends Resource
class_name TowerData
 
@export var id:        String
@export var position:  Vector3
@export var height:    float
@export var district:  String
@export var scene_path: String
@export var strata_ids: Dictionary  # { "doggerland": "T-001-DG", ... }
 
 
