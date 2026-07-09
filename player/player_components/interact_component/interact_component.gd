extends Node3D
## Компонент игрока InteractComponent
class_name InteractComponent

## Прототип механики при обнаружение обьекта 1) выводим инфу о нем и кем он является
## Items / Button / Door / другие
## 2) если PickupItem c "can_carry" цепляем его в пространство PickupSlot (оно будет впереди игрока)
## если обьект "can_carry"/ «can_store_in_inventory»/ «can_throw»
## то можно его сложить в инвентарь из PickupSlot или выкинуть если "can_throw"

##Подбираемые и переносимые объекты:
##PickupItem﻿ (можно параметром отмечать «can_carry», «can_store_in_inventory», «can_throw»).

@onready var player: CharacterBody3D = get_parent() ## cсылка на игрока
@onready var dymamic_cursor_ui: MouseCursorUI = $"../DynamicCursorUI"
## в случае если захотим визуально что-то менять с курсором при интерактивности
@onready var player_focus_cast: ShapeCast3D = $PlayerFocusCast
## Этот шейпкаст служит для обнаружения интерактивных обьектов в фокусе
## перед игроком по группе "Interactable" и по слою "Interactable"

@onready var pickup_slot: Node3D = $"../PickupSlot"
## прототип-набросок куда цепляется предмет (потом можно сделать - аттачить к Bone руки)

@onready var debug_label: Label = $Label
## через него видем какой обьект в фокусе, name, его возможности, количество

var current_interactable: InteractableObject = null
var previous_interactable: InteractableObject = null ## Для отслеживания смены объекта
var carried_item: InteractableObject = null
var closest_distance: float = INF
var detected_count: int = 0

func _ready() -> void:
	## вкл допом программно
	player_focus_cast.enabled = true
	player_focus_cast.collision_mask = 512  # 10-й слой (Interactables)
	player_focus_cast.collide_with_areas = true
	player_focus_cast.collide_with_bodies = true
	
	## Проверка debug_label
	if debug_label:
		debug_label.visible = true
		debug_label.text = "🔍 Поиск объектов..."
	else:
		print("❌ ОШИБКА: debug_label не найден!")

	## Компонент сам решает, актуален ли он сейчас (только ON_FOOT) —
	## InputSystems лишь сообщает о нажатии, ни о чём не спрашивая.
	InputSystems.interact_pressed.connect(_on_interact_pressed)

func _on_interact_pressed() -> void:
	if PlayerState.mode != PlayerState.Mode.ON_FOOT:
		return
	try_interact()
	
func _physics_process(_delta: float) -> void:
	detect_interactable()
	update_debug_label()
	
func detect_interactable() -> void:
	var new_interactable: InteractableObject = null  # ✅ Всегда null по умолчанию
	closest_distance = INF
	detected_count = 0
	
	## Обнаружение коллайдеров
	if player_focus_cast.is_colliding():
		var collision_count = player_focus_cast.get_collision_count()
		
		for i in range(collision_count):
			var collider = player_focus_cast.get_collider(i)
			var potential_item: InteractableObject = null
			
			## 1. Если нашли сам InteractableObject (RigidBody)
			if collider is InteractableObject:
				potential_item = collider
			
			## 2. Если нашли Area, проверяем её родителя
			elif collider is Area3D:
				if collider.get_parent() is InteractableObject:
					potential_item = collider.get_parent()
			
			if potential_item:
				## ⚠️ Игнорируем объект, который уже в руках
				if potential_item == carried_item:
					continue
				
				detected_count += 1
				var distance = player.global_position.distance_to(potential_item.global_position)
				
				if distance < closest_distance:
					closest_distance = distance
					new_interactable = potential_item
	
	## 🔥 КРИТИЧНО! Этот блок теперь ВСЕГДА выполняется, даже если is_colliding() == false
	## Обработка смены объекта в фокусе
	if new_interactable != current_interactable:
		## Уведомляем старый объект, что он больше не в фокусе
		if current_interactable and current_interactable != carried_item:
			current_interactable.on_lost_by_player()
			print("🚫 Объект потерян из фокуса: ", current_interactable.name_interactable_object)
		
		## Уведомляем новый объект, что он обнаружен
		if new_interactable:
			new_interactable.on_detected_by_player()
			print("👁️ Объект обнаружен: ", new_interactable.name_interactable_object)
		
		current_interactable = new_interactable

func update_debug_label() -> void:
	if not debug_label:
		return
	
	## Статус работы ShapeCast
	var status_line = ""
	if player_focus_cast.enabled:
		var shape_detecting = player_focus_cast.is_colliding()
		status_line += "🔷 ShapeCast: " + ("✅ Активен" if shape_detecting else "⚫ Нет объектов")
		if shape_detecting:
			status_line += " (Обнар: " + str(detected_count) + ")"
			## Если обнаружено больше 1 объекта! - указываем что показываем ближайший!
			if detected_count > 1:
				status_line += " - Ближайший"
	else:
		status_line += "🔷 ShapeCast: ❌ Выключен"
	
	## Показываем инфу о предмете в руках
	if carried_item:
		status_line += "\n✋ В руках: " + carried_item.name_interactable_object
	
	## Если есть текущий интерактивный объект
	if current_interactable:
		var info_text = status_line + "\n\n"
		info_text += "📦 Объект: " + current_interactable.name_interactable_object + "\n"
		info_text += "📏 Дистанция: " + ("%.2f" % closest_distance) + " м\n"
		info_text += "🏷️ Тип: " + get_interaction_type_name(current_interactable.interaction_type) + "\n"
		
		## Показываем возможности объекта
		var abilities = []
		
		match current_interactable.interaction_type:
			InteractableObject.InteractionType.BUTTON:
				abilities.append("🔘 Активировать")
			InteractableObject.InteractionType.CARRY_ONLY:
				abilities.append("✋ Поднять")
			InteractableObject.InteractionType.INVENTORY_ONLY:
				abilities.append("🎒 Взять в инвентарь")
			InteractableObject.InteractionType.CARRY_AND_INVENTORY:
				abilities.append("✋ Поднять")
				abilities.append("🎒 В инвентарь")
			InteractableObject.InteractionType.VEHICLE:
				abilities.append("🚗 Войти в машину")
		
		if current_interactable.can_throw:
			abilities.append("💨 Бросить")
		
		if current_interactable.can_use_in_hands:
			abilities.append("⚡ Использовать")
		
		info_text += "⚙️ Действия:\n   • " + "\n   • ".join(abilities)
		
		debug_label.text = info_text
		debug_label.visible = true
	else:
		## Показываем только статус работы кастов
		debug_label.text = status_line
		debug_label.visible = true
		
		
func try_interact() -> void:
	## Если уже что-то в руках - выбрасываем
	if carried_item:
		_drop_item()
		return
	
	if not current_interactable:
		return
	
	## Проверяем тип взаимодействия
	match current_interactable.interaction_type:
		InteractableObject.InteractionType.CARRY_ONLY, \
		InteractableObject.InteractionType.CARRY_AND_INVENTORY:
			_pickup_item(current_interactable)
		InteractableObject.InteractionType.BUTTON:
			_activate_button(current_interactable)
		InteractableObject.InteractionType.VEHICLE:  # flying car
			_enter_vehicle(current_interactable)
			
func _pickup_item(item: InteractableObject) -> void:
	if carried_item: return
	
	carried_item = item
	
	## даем знать item, что он подобран
	item.on_picked_up()
	
	## 1. Отключаем физику (теперь это сам item)
	item.freeze = true
	
	## 2. Отключаем коллизии физического тела, чтобы не толкал игрока
	item.collision_layer = 0
	item.collision_mask = 0
	
	## 3. Отключаем зону детекции
	if item.interaction_area:
		item.interaction_area.monitorable = false

	## Анимация и аттач
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(item, "global_position", pickup_slot.global_position, 0.3)
	tween.parallel().tween_property(item, "global_rotation", pickup_slot.global_rotation, 0.3)
	tween.tween_callback(_attach_to_slot.bind(item))
	
func _attach_to_slot(item: InteractableObject) -> void:
	## аттачим перед игрок к ноде ПикапСлот
	item.reparent(pickup_slot)
	item.position = Vector3.ZERO
	item.rotation = Vector3.ZERO
	
func _activate_button(current_interactable):
	pass
	
func _drop_item() -> void:
	if not carried_item: return
	
	var item = carried_item
	carried_item = null
	
	item.on_dropped()
	
	## Отцепляем от игрока
	item.reparent(get_tree().current_scene)
	
	## Позиция броска
	var forward = player.global_transform.basis.z 
	item.global_position = player.global_position + forward * 1.5
	
	# Восстанавливаем слои физики (чтобы он мог стукаться)
	item.collision_layer = 8 # Physics Layer
	item.collision_mask = 10 # Physics Mask
	
	## Сила броска
	var throw_force = forward * 2.5 + Vector3.UP * 1.0 ## можно больше поставить
	var spin = Vector3(randf(), randf(), randf()) * 2.0 ## тут закрутить сильно можно
	
	## Запуск
	item.throw_self(throw_force, spin)
	
# заглушка — сюда придёт логика угона
func _enter_vehicle(vehicle: InteractableObject) -> void:
	print("🚗 Взаимодействие с транспортом: ", vehicle.name_interactable_object)
	if get_parent().visible == true:
		get_parent().visible = false
		get_parent().set_physics_process(false)
	else:
		get_parent().visible = true
		get_parent().set_physics_process(true)
	# TODO: передать управление PlayerDriver

func get_interaction_type_name(type: InteractableObject.InteractionType) -> String:
	match type:
		InteractableObject.InteractionType.BUTTON:
			return "Кнопка/Терминал"
		InteractableObject.InteractionType.CARRY_ONLY:
			return "Переносимый предмет"
		InteractableObject.InteractionType.INVENTORY_ONLY:
			return "Инвентарный предмет"
		InteractableObject.InteractionType.CARRY_AND_INVENTORY:
			return "Переносимый + Инвентарь"
		InteractableObject.InteractionType.VEHICLE:
			return "Транспортное средство"
	return "Неизвестно"
