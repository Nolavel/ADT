extends Node3D
## Wall-mounted deck-light // Настенный палубный фонарь

enum LightMode {
	OFF,           ## Не работает
	CONSTANT,      ## Работает постоянно
	EMERGENCY,     ## Работает импульсно (аварийно)
	BROKEN         ## Работает рандомно (сломанный)
}

@export_group("Light Settings")
@export var mode: LightMode = LightMode.CONSTANT
@export_range(0.0, 10.0) var light_energy: float = 1.0
@export var light_color: Color = Color.YELLOW
@export_range(0.0, 20.0) var light_range: float = 5.0

@export_group("Emergency Mode Settings")
@export_range(0.1, 2.0) var emergency_on_time: float = 0.3
@export_range(0.1, 2.0) var emergency_off_time: float = 0.3

@export_group("Broken Mode Settings")
@export_range(0.05, 1.0) var broken_min_time: float = 0.1
@export_range(0.5, 5.0) var broken_max_time: float = 2.0
@export_range(0.0, 0.5) var broken_flicker_chance: float = 0.3

@onready var light_one_side: SpotLight3D = $"Куб_004/light_1_side"
@onready var light_another_side: SpotLight3D = $"Куб_004/light_2_side"
@onready var mesh_lamp: MeshInstance3D = $"Куб_004"

var timer: float = 0.0
var is_light_on: bool = true
var mesh_material: StandardMaterial3D

func _ready() -> void:
	# Получаем материал меша
	if mesh_lamp:
		mesh_material = mesh_lamp.get_surface_override_material(0)
		if not mesh_material:
			# Если override материала нет, создаем его копию
			var base_mat = mesh_lamp.mesh.surface_get_material(0)
			if base_mat:
				mesh_material = base_mat.duplicate()
				mesh_lamp.set_surface_override_material(0, mesh_material)
	
	# Синхронизируем начальные настройки обоих источников света
	_sync_light_settings()
	_apply_mode()

func _process(delta: float) -> void:
	match mode:
		LightMode.OFF:
			_set_lights_enabled(false)
		
		LightMode.CONSTANT:
			_set_lights_enabled(true)
		
		LightMode.EMERGENCY:
			_emergency_mode(delta)
		
		LightMode.BROKEN:
			_broken_mode(delta)

## Синхронизирует настройки обоих источников света
func _sync_light_settings() -> void:
	for light in [light_one_side, light_another_side]:
		if light:
			light.light_energy = light_energy
			light.light_color = light_color
			#light.omni_range = light_range

## Включает/выключает оба источника света синхронно
func _set_lights_enabled(enabled: bool) -> void:
	is_light_on = enabled
	
	# Управляем видимостью источников света
	if light_one_side:
		light_one_side.visible = enabled
	if light_another_side:
		light_another_side.visible = enabled
	
	# Управляем emission меша (ИНВЕРСИЯ: когда НЕ горит - emission включен)
	if mesh_material:
		if not enabled:
			# Свет ВЫКЛЮЧЕН - включаем emission на UV2
			mesh_material.emission_on_uv2 = true
		else:
			# Свет ВКЛЮЧЕН - выключаем emission
			mesh_material.emission_on_uv2 = false

## Применяет начальное состояние в зависимости от режима
func _apply_mode() -> void:
	match mode:
		LightMode.OFF:
			_set_lights_enabled(false)
		LightMode.CONSTANT:
			_set_lights_enabled(true)
		LightMode.EMERGENCY:
			_set_lights_enabled(true)
			timer = 0.0
		LightMode.BROKEN:
			_set_lights_enabled(true)
			timer = randf_range(broken_min_time, broken_max_time)

## Режим аварийного освещения (ритмичное мигание)
func _emergency_mode(delta: float) -> void:
	timer += delta
	
	if is_light_on and timer >= emergency_on_time:
		_set_lights_enabled(false)
		timer = 0.0
	elif not is_light_on and timer >= emergency_off_time:
		_set_lights_enabled(true)
		timer = 0.0

## Режим сломанного фонаря (случайные мигания и перебои)
func _broken_mode(delta: float) -> void:
	timer -= delta
	
	if timer <= 0.0:
		# Случайное мерцание с шансом
		if randf() < broken_flicker_chance:
			# Быстрое мерцание (несколько раз)
			var flicker_count = randi_range(1, 4)
			for i in flicker_count:
				await get_tree().create_timer(0.05).timeout
				_set_lights_enabled(not is_light_on)
				await get_tree().create_timer(0.05).timeout
				_set_lights_enabled(not is_light_on)
		else:
			# Обычное переключение
			_set_lights_enabled(not is_light_on)
		
		# Устанавливаем новый случайный интервал
		timer = randf_range(broken_min_time, broken_max_time)

## Обновляет настройки света при изменении экспортированных параметров
func _notification(what: int) -> void:
	if what == NOTIFICATION_EDITOR_PRE_SAVE or what == NOTIFICATION_TRANSFORM_CHANGED:
		if light_one_side and light_another_side:
			_sync_light_settings()
