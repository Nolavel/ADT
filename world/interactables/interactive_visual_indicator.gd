extends Node3D

## Интерактивный Визуальный Индикатор для InteractableObject (ГАЛОЧКА)
##
## Метод его работы:
## - ИВИ появляется над интерактивным объектом по установленной булевой в родителе (показ/непоказ)
## - Появляется сверху вниз над объектом по твину
## - Имеет шейк если он еще в фокусе игрока но не подобран
## - Исчезает после того как вне фокуса игрока, движение снизу вверх по твину
## - При очередных выбросах объекта в мир, если на нем установлена булевая отображать спрайт индикации,
##   включает raycasts для определения пола, так как rigid body объект может поменять свою ориентацию при выбросе

## ВИЗУАЛЬНАЯ ИНДИКАЦИЯ
@export_group("Визуальная индикация")
@export var indicator_sprite_texture: Texture2D ## Текстура спрайта-индикатора
@export var base_height_offset: float = 1.0 ## Высота над верхней точкой объекта
@export var sprite_billboard_mode: bool = true ## Billboard режим
@export var sprite_pixel_size: float = 0.01 ## Размер пикселя спрайта

## НАСТРОЙКИ АНИМАЦИИ
@export_group("Настройки анимации")
@export var fade_duration: float = 0.3 ## Длительность появления/исчезновения
@export var appear_height_offset: float = 0.5 ## На сколько выше появляется спрайт
@export var cooldown_after_throw: float = 1.0 ## Задержка показа спрайта после броска

## СИСТЕМА ТРЯСКИ
@export_group("Система тряски (Shake)")
@export var enable_shake: bool = true ## Включить тряску при долгом ожидании
@export var shake_wait_time: float = 5.0 ## Время ожидания до начала тряски
@export var shake_duration: float = 2.0 ## Длительность тряски
@export var shake_strength: float = 0.1 ## Сила тряски

## НАСТРОЙКИ RAYCAST
@export_group("Raycast Detection")
@export var raycast_length: float = 5.0 ## Длина лучей для определения пола
## CollisionLayers.GROUND (floor only). Was CollisionLayers.WALL (the
## project's own layer 3), contradicting this line's own "layer 2 = ground"
## comment — these rays exist to find the floor after a throw may have
## tumbled the object into any orientation, not a nearby wall.
@export var raycast_collision_mask: int = CollisionLayers.GROUND

## === ВНУТРЕННИЕ ПЕРЕМЕННЫЕ ===
## The node the tick hangs over. ANY Node3D, not necessarily an
## InteractableObject: the hover's DoorAnchor is a plain Marker3D under a
## CharacterBody3D, and HoverEntryTrigger drives this indicator itself the same
## way it already drives HoldPrompt and the ground decal.
var anchor: Node3D = null
## The anchor narrowed to InteractableObject, or null when the driver is
## somebody else. Only the SHAKE gate reads it — an object that knows whether
## it is detected or carried can suppress the knock by itself; a driven
## indicator's owner is responsible for that instead.
var parent_object: InteractableObject = null
var indicator_sprite: Node3D = null ## Контейнер для спрайта
var sprite_3d: Sprite3D = null      ## Сам спрайт
var can_show_sprite: bool = true    ## Блокировка после броска
var is_sprite_visible: bool = false ## Текущее состояние видимости
var ground_direction: Vector3 = Vector3.DOWN ## Направление к полу (противоположное спрайту)

## Переменные анимации
var tween_sprite: Tween
var sprite_current_height: float = 0.0  ## Текущая высота
var sprite_shake_offset: float = 0.0   ## Смещение для тряски

## Таймеры
var shake_timer: Timer = null
var throw_cooldown_timer: Timer = null
var is_shaking: bool = false
## Which shake the deferred _stop_shake() below belongs to.
##
## _start_shake() awaits a timer for shake_duration and then calls
## _stop_shake(), which kills tween_sprite — and tween_sprite is shared with
## the show and hide animations. If the lift-and-fade started inside that
## window, the late _stop_shake() killed IT instead, leaving the sprite parked
## half-transparent with is_sprite_visible still true, i.e. a tick that never
## comes back. Rare while the only way out was losing focus entirely; once
## entering reach also lifts the tick (InteractableObject.on_reach_changed)
## it is every crossing of pickup_distance. A late stop now compares this and
## returns if another shake, or a show/hide, has taken the tween since.
var shake_generation: int = 0

## Raycasts для определения направления пола
var raycasts: Array[RayCast3D] = []
var is_scanning: bool = false

func _ready() -> void:
	## Получаем ссылку на родительский объект
	anchor = get_parent() as Node3D
	parent_object = anchor as InteractableObject
	
	if not anchor:
		push_error("InteractiveVisualIndicator: parent must be a Node3D to hang over")
		return
	
	if indicator_sprite_texture:
		_setup_indicator_sprite()
		_setup_timers()
		_setup_raycasts()

func _setup_indicator_sprite() -> void:
	## Создаём контейнер для спрайта
	indicator_sprite = Node3D.new()
	indicator_sprite.visible = false
	
	## Создаём спрайт
	sprite_3d = Sprite3D.new()
	sprite_3d.texture = indicator_sprite_texture
	sprite_3d.pixel_size = sprite_pixel_size
	sprite_3d.modulate.a = 0.0
	sprite_3d.no_depth_test = true ## Всегда поверх других объектов
	
	## Настройки рендеринга
	sprite_3d.gi_mode = GeometryInstance3D.GI_MODE_DISABLED ## Отключаем GI
	sprite_3d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF ## Без теней
	sprite_3d.visibility_range_end_margin = 0.0
	sprite_3d.ignore_occlusion_culling = true ## Игнорировать окклюзию
	sprite_3d.render_priority = 1
	
	if sprite_billboard_mode:
		sprite_3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	
	indicator_sprite.add_child(sprite_3d)
	get_tree().current_scene.call_deferred("add_child", indicator_sprite)

func _setup_timers() -> void:
	## Таймер для тряски
	if enable_shake:
		shake_timer = Timer.new()
		shake_timer.wait_time = shake_wait_time
		shake_timer.one_shot = true
		shake_timer.timeout.connect(_start_shake)
		add_child(shake_timer)
	
	## Таймер кулдауна после броска
	throw_cooldown_timer = Timer.new()
	throw_cooldown_timer.wait_time = cooldown_after_throw
	throw_cooldown_timer.one_shot = true
	throw_cooldown_timer.timeout.connect(_on_throw_cooldown_finished)
	add_child(throw_cooldown_timer)

func _setup_raycasts() -> void:
	## Создаём 6 RayCast3D по всем направлениям (вверх, вниз, вперёд, назад, влево, вправо)
	var directions = [
		Vector3.UP,
		Vector3.DOWN,
		Vector3.FORWARD,
		Vector3.BACK,
		Vector3.LEFT,
		Vector3.RIGHT
	]
	
	for dir in directions:
		var raycast = RayCast3D.new()
		raycast.target_position = dir * raycast_length
		raycast.collision_mask = raycast_collision_mask
		raycast.enabled = false ## Изначально выключены
		add_child(raycast)
		raycasts.append(raycast)

func _process(_delta: float) -> void:
	if not is_sprite_visible or not indicator_sprite or not anchor:
		return
	
	## Вычисляем позицию спрайта относительно направления пола
	var sprite_pos = anchor.global_position - ground_direction * (base_height_offset + sprite_current_height + sprite_shake_offset)
	indicator_sprite.global_position = sprite_pos

func _exit_tree() -> void:
	if indicator_sprite:
		indicator_sprite.queue_free()

## ============================================================================
## ПУБЛИЧНЫЕ МЕТОДЫ (вызываются из InteractableObject)
## ============================================================================

func on_object_detected() -> void:
	if not can_show_sprite:
		return
	
	## Проверяем существование спрайтов
	if not sprite_3d or not indicator_sprite:
		if indicator_sprite_texture:
			_setup_indicator_sprite()
			await get_tree().process_frame
	
	_show_indicator_sprite()
	_start_shake_cycle()

func on_object_lost() -> void:
	if not sprite_3d:
		return
	
	_hide_indicator_sprite_with_lift()
	_stop_shake_cycle()

func on_object_picked_up() -> void:
	if not sprite_3d:
		return
	
	_hide_indicator_sprite_instant()
	_stop_shake_cycle()

func on_object_dropped() -> void:
	## Блокируем показ спрайта
	can_show_sprite = false
	
	_hide_indicator_sprite_instant()
	_stop_shake_cycle()
	
	## СНАЧАЛА ждём завершения сканирования, ПОТОМ запускаем кулдаун
	_start_ground_detection_and_cooldown()

func _on_throw_cooldown_finished() -> void:
	can_show_sprite = true
	
	## КРИТИЧНО! Проверяем и пересоздаём спрайт если он был удалён после подбора игроком
	if not sprite_3d or not indicator_sprite:
		if indicator_sprite_texture:
			_setup_indicator_sprite()
			await get_tree().process_frame
	
	## ПРИНУДИТЕЛЬНО показываем спрайт
	_show_indicator_sprite()
	
	## Запускаем тряску только если обнаружен игроком в shape cast
	if _shake_allowed():
		_start_shake_cycle()

## ============================================================================
## ОПРЕДЕЛЕНИЕ НАПРАВЛЕНИЯ ПОЛА ЧЕРЕЗ RAYCASTS
## ============================================================================

func _start_ground_detection_and_cooldown() -> void:
	if is_scanning:
		return
	
	is_scanning = true
	
	## Включаем все raycasts
	for raycast in raycasts:
		raycast.enabled = true
		raycast.force_raycast_update()
	
	## Ждём несколько кадров для стабилизации физики
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	
	## Определяем направление пола СРАЗУ
	_detect_ground_direction()
	
	## Выключаем raycasts
	for raycast in raycasts:
		raycast.enabled = false
	
	is_scanning = false
	
	## ТЕПЕРЬ запускаем кулдаун после определения направления
	if throw_cooldown_timer:
		throw_cooldown_timer.start()

func _detect_ground_direction() -> void:
	var closest_distance := INF
	var closest_direction := Vector3.DOWN
	
	## Проходим по всем raycast и находим ближайшее столкновение с полом
	for raycast in raycasts:
		if raycast.is_colliding():
			var collision_point = raycast.get_collision_point()
			var distance = anchor.global_position.distance_to(collision_point)
			
			if distance < closest_distance:
				closest_distance = distance
				## Направление К полу
				closest_direction = (collision_point - anchor.global_position).normalized()
	
	## Обновляем направление к полу
	ground_direction = closest_direction

## ============================================================================
## АНИМАЦИЯ СПРАЙТА
## ============================================================================

## Показываем спрайт с анимацией
func _show_indicator_sprite() -> void:
	if not sprite_3d or not indicator_sprite:
		return
	
	is_sprite_visible = true
	indicator_sprite.visible = true
	sprite_3d.visible = true
	sprite_shake_offset = 0.0
	shake_generation += 1   ## this tween is ours now — see shake_generation
	
	if tween_sprite:
		tween_sprite.kill()
	tween_sprite = create_tween()
	
	## Начальная позиция выше
	sprite_current_height = appear_height_offset
	sprite_3d.modulate.a = 0.0
	
	## Анимация опускания + fade in
	tween_sprite.parallel().tween_property(
		self, 
		"sprite_current_height", 
		0.0, 
		fade_duration
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BOUNCE)
	
	tween_sprite.parallel().tween_property(
		sprite_3d, 
		"modulate:a", 
		1.0, 
		fade_duration
	)

## Эффект исчезновения когда спрайт уходит из фокуса
func _hide_indicator_sprite_with_lift() -> void:
	if not sprite_3d or not indicator_sprite:
		return
	
	shake_generation += 1   ## this tween is ours now — see shake_generation
	if tween_sprite:
		tween_sprite.kill()
	tween_sprite = create_tween()
	
	## Анимация поднятия + fade out
	tween_sprite.parallel().tween_property(
		self, 
		"sprite_current_height", 
		appear_height_offset, 
		0.2
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUART)
	
	tween_sprite.parallel().tween_property(
		sprite_3d, 
		"modulate:a", 
		0.0, 
		0.2
	)
	
	tween_sprite.tween_callback(func(): 
		is_sprite_visible = false
		sprite_3d.visible = false
		indicator_sprite.visible = false
		sprite_shake_offset = 0.0
	)

## Мгновенное скрытие спрайта
func _hide_indicator_sprite_instant() -> void:
	if not sprite_3d or not indicator_sprite:
		return
	
	shake_generation += 1   ## this tween is ours now — see shake_generation
	if tween_sprite:
		tween_sprite.kill()
	
	is_sprite_visible = false
	sprite_3d.visible = false
	indicator_sprite.visible = false
	sprite_3d.modulate.a = 0.0
	sprite_current_height = 0.0
	sprite_shake_offset = 0.0

## ============================================================================
## СИСТЕМА ТРЯСКИ
## ============================================================================

## The knock. An InteractableObject suppresses it while it is not detected or
## while it is carried; a DRIVEN indicator (the hover door) has no such flags,
## and its driver decides by simply not calling on_object_detected().
func _shake_allowed() -> bool:
	if parent_object == null:
		return true
	return parent_object.is_detected and not parent_object.is_being_carried


func _start_shake_cycle() -> void:
	if not enable_shake or not shake_timer or not anchor:
		return
	
	if _shake_allowed():
		shake_timer.start()

func _stop_shake_cycle() -> void:
	if shake_timer:
		shake_timer.stop()
	_stop_shake()

func _start_shake() -> void:
	if not anchor or not sprite_3d or not is_sprite_visible:
		return
	
	## Проверяем что объект всё ещё обнаружен
	if not _shake_allowed():
		return
	
	is_shaking = true
	shake_generation += 1
	var generation: int = shake_generation
	
	if tween_sprite:
		tween_sprite.kill()
	tween_sprite = create_tween()
	tween_sprite.set_loops() ## Бесконечный цикл
	
	## Тряска через sprite_shake_offset
	tween_sprite.tween_property(self, "sprite_shake_offset", shake_strength, 0.1)
	tween_sprite.tween_property(self, "sprite_shake_offset", -shake_strength, 0.1)
	tween_sprite.tween_property(self, "sprite_shake_offset", 0.0, 0.1)
	
	## Останавливаем через shake_duration секунд
	await get_tree().create_timer(shake_duration).timeout
	## Somebody else owns tween_sprite now — see shake_generation.
	if generation != shake_generation:
		return
	_stop_shake()
	
	## Перезапускаем цикл если объект всё ещё обнаружен
	if anchor and _shake_allowed():
		_start_shake_cycle()

func _stop_shake() -> void:
	if not is_shaking:
		return
	
	is_shaking = false
	sprite_shake_offset = 0.0
	
	if tween_sprite:
		tween_sprite.kill()
