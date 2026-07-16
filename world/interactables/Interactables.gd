extends RigidBody3D
class_name InteractableObject

## ВАЖНО !!! для этих объектов их обнаружения используем для area группу "interactables"
## а также слой 10 (бит 9, значение 512 = Interactables) 

## BUTTON: излучается при активации. Двери/лифты/терминалы подписываются
## на этот сигнал — сам объект не знает, кто на него реагирует.
signal activated(by: Node)

enum InteractionType {
	BUTTON,              ## просто кнопка/терминал
	CARRY_ONLY,          ## можно поднять и нести, но не класть в инвентарь
	INVENTORY_ONLY,      ## сразу в инвентарь, без переноса в руках
	CARRY_AND_INVENTORY, ## можно и нести, и положить в инвентарь
	VEHICLE
}

## ОСНОВНЫЕ ПАРАМЕТРЫ
@export_group("Настройки взаимодействия")
@export var name_interactable_object: String = "Box"
@export var interaction_type: InteractionType = InteractionType.BUTTON
@export var can_throw: bool = false        ## можно ли бросать
@export var can_use_in_hands: bool = false ## например, включать фонарик, сканер и т.п.


## Данные предмета для инвентаря (data/items/*.tres).
## Обязателен для INVENTORY_ONLY и CARRY_AND_INVENTORY, для остальных — null.
@export var item: ItemResource = null
## ВИЗУАЛЬНАЯ ИНДИКАЦИЯ
@export_group("Визуальная индикация")
@export var enable_visual_indicator: bool = true ## Показывать ли спрайт над объектом

## ВНУТРЕННИЕ ПЕРЕМЕННЫЕ
var is_being_carried: bool = false ## Находится ли объект в руках у игрока
var is_detected: bool = false      ## Обнаружен ли ShapeCast'ом



## Ссылка на дочернюю зону обнаружения
@onready var interaction_area: Area3D = $Area

## Ссылка на визуальный индикатор
@onready var visual_indicator: Node3D = $InteractiveVisualIndicator

func _ready() -> void:
	## 1. Настройка физики RigidBody
	collision_layer = 8 
	collision_mask = 10 
	contact_monitor = false
	max_contacts_reported = 0
	
	## 2. Настройка зоны взаимодействия (Area3D)
	if interaction_area:
		interaction_area.collision_layer = 512 ## Layer 10
		interaction_area.collision_mask = 0

## ============================================================================
## ПУБЛИЧНЫЕ МЕТОДЫ ДЛЯ INTERACT MANAGER
## ============================================================================

## Вызывается когда InteractManager обнаруживает объект через ShapeCast
func on_detected_by_player() -> void:
	is_detected = true
	
	## Уведомляем визуальный индикатор
	if visual_indicator and not is_being_carried and enable_visual_indicator:
		visual_indicator.on_object_detected()

## Вызывается когда объект выходит из фокуса ShapeCast
func on_lost_by_player() -> void:
	is_detected = false
	
	## Уведомляем визуальный индикатор
	if visual_indicator and not is_being_carried and enable_visual_indicator:
		visual_indicator.on_object_lost()

## Вызывается когда объект подбирается игроком
func on_picked_up() -> void:
	is_being_carried = true
	is_detected = false
	
	## Уведомляем визуальный индикатор
	if visual_indicator and enable_visual_indicator:
		visual_indicator.on_object_picked_up()

## Вызывается когда объект выброшен из рук
func on_dropped() -> void:
	is_being_carried = false
	
	## Уведомляем визуальный индикатор
	if visual_indicator and enable_visual_indicator:
		visual_indicator.on_object_dropped()

## ============================================================================
## СИСТЕМА БРОСАНИЯ
## ============================================================================

## Функция броска (вызывается менеджером)
func throw_self(velocity: Vector3, angular_vel: Vector3) -> void:
	## Отключаем зону подбора
	if interaction_area:
		interaction_area.monitorable = false
		interaction_area.monitoring = false
	
	## Включаем физику
	freeze = false
	sleeping = false
	linear_velocity = velocity
	angular_velocity = angular_vel
	
	## Включаем детектор удара
	contact_monitor = true
	max_contacts_reported = 1
	
	if not body_entered.is_connected(_on_ground_hit):
		body_entered.connect(_on_ground_hit)

## Обработка удара (об пол или другой объект)
func _on_ground_hit(_body: Node) -> void:
	## Возвращаем возможность подбора
	if interaction_area:
		interaction_area.set_deferred("monitorable", true)
		interaction_area.set_deferred("monitoring", true)
	
	## Отключаем мониторинг для оптимизации
	set_deferred("contact_monitor", false)
	
	if body_entered.is_connected(_on_ground_hit):
		body_entered.disconnect(_on_ground_hit)
