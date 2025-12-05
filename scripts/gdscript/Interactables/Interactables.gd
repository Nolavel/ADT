extends RigidBody3D
class_name InteractableObject
## ВАЖНО !!! для этих обьектов их обноружения используем для area группу "interactables"
## а также слой 10 (бит 9, значение 512 = Interactables) 
enum InteractionType {
	BUTTON,             ## просто кнопка/терминал
	CARRY_ONLY,         ## можно поднять и нести, но не класть в инвентарь
	INVENTORY_ONLY,     ## сразу в инвентарь, без переноса в руках
	CARRY_AND_INVENTORY ## можно и нести, и положить в инвентарь
}
@export var name_interactable_object: String = "Box"
@export var interaction_type: InteractionType = InteractionType.BUTTON
@export var can_throw: bool = false        # можно ли бросать (актуально, если есть перенос)
@export var can_use_in_hands: bool = false # например, включать фонарик, сканер и т.п.

## Ссылка на дочернюю зону обнаружения (чтобы отключать её при подборе)
@onready var interaction_area: Area3D = $Area

func _ready() -> void:
	## 1. Настройка самого RigidBody (Self)
	## Layer 4 (Physics Objects), Mask 2 (Ground) + 4 
	collision_layer = 8 
	collision_mask = 10 
	
	## Включаем мониторинг ударов
	contact_monitor = false
	max_contacts_reported = 0
	
	## 2. Настройка зоны взаимодействия (Area3D)
	if interaction_area:
		interaction_area.collision_layer = 512 # Layer 10
		interaction_area.collision_mask = 0

## Функция броска (вызывается менеджером)
func throw_self(velocity: Vector3, angular_vel: Vector3) -> void:
	## Отключаем зону подбора, чтобы сразу не поймать обратно
	if interaction_area:
		interaction_area.monitorable = false
		interaction_area.monitoring = false
	
	## Включаем физику
	freeze = false
	sleeping = false
	linear_velocity = velocity
	angular_velocity = angular_vel
	
	## Включаем детектор удара, чтобы вернуть возможность подбора
	contact_monitor = true
	max_contacts_reported = 1
	
	if not body_entered.is_connected(_on_ground_hit):
		body_entered.connect(_on_ground_hit)

## Обработка удара (об пол или другой ящик)
func _on_ground_hit(_body: Node) -> void:
	print("✅ Упал и ударился: ", name_interactable_object)
	
	## Возвращаем возможность подбора (через Area3D)
	if interaction_area:
		interaction_area.set_deferred("monitorable", true)
		interaction_area.set_deferred("monitoring", true)
	
	## Отключаем мониторинг для оптимизации
	set_deferred("contact_monitor", false)
	
	if body_entered.is_connected(_on_ground_hit):
		body_entered.disconnect(_on_ground_hit)
