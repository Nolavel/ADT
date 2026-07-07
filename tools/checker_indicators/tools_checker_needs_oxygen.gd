extends Node3D

@onready var area_increase_oxy: Area3D = $IncreaseOxygen
@onready var area_decrease_oxy: Area3D = $DecreaseOxygen
@export var oxygen_bar: MeshInstance3D ## indicator oxygen

# Параметры Oxygen
var current_oxy: float = 1.0
var oxy_change_rate: float = 0.1 # 0.1 HP за 1 секунду

# Флаги для отслеживания зон
var is_in_increase_zone: bool = false
var is_in_decrease_zone: bool = false

# Кэш материала
var oxy_material: ShaderMaterial = null

func _ready() -> void:
	if area_increase_oxy:
		area_increase_oxy.body_entered.connect(_on_increase_zone_entered)
		area_increase_oxy.body_exited.connect(_on_increase_zone_exited)
	
	if area_decrease_oxy:
		area_decrease_oxy.body_entered.connect(_on_decrease_zone_entered)
		area_decrease_oxy.body_exited.connect(_on_decrease_zone_exited)
	
	# Получаем материал и кэшируем его
	if oxygen_bar:
		# Проверяем все поверхности меша
		for i in range(oxygen_bar.get_surface_override_material_count()):
			var mat = oxygen_bar.get_surface_override_material(i)
			if mat and mat is ShaderMaterial:
				oxy_material = mat
				print("✅ Oxy Bar материал найден на поверхности ", i)
				break
		
		# Если не нашли override material, пробуем активный материал
		if not oxy_material:
			var mat = oxygen_bar.get_active_material(0)
			if mat and mat is ShaderMaterial:
				# Создаем уникальный материал для этого меша
				oxy_material = mat.duplicate()
				oxygen_bar.set_surface_override_material(0, oxy_material)
				print("✅ Oxygen Bar материал дублирован и установлен")
		
		if not oxy_material:
			push_error("❌ Не удалось найти ShaderMaterial для Oxy Bar!")
	else:
		push_error("❌ Oxy Bar меш не назначен!")
	
	# Устанавливаем начальное значение HP
	_update_oxy_bar()
	print("🎯 Oxy Controller готов | Oxy: ", current_oxy)

func _process(delta: float) -> void:
	var oxy_changed = false
	var old_oxy = current_oxy
	
	# Увеличиваем OXY если игрок в зоне увеличения
	if is_in_increase_zone:
		current_oxy += oxy_change_rate * delta
		oxy_changed = true
	
	# Уменьшаем OXY если игрок в зоне уменьшения
	if is_in_decrease_zone:
		current_oxy -= oxy_change_rate * delta
		oxy_changed = true
	
	# Clamp значения OXY
	current_oxy = clamp(current_oxy, 0.0, 1.0)
	
	# Обновляем шейдер если Oxy изменилось
	if oxy_changed and abs(old_oxy - current_oxy) > 0.001:
		_update_oxy_bar()

func _update_oxy_bar() -> void:
	if oxy_material:
		oxy_material.set_shader_parameter("oxygen", current_oxy)
		print("💚 OXY обновлен: ", snappedf(current_oxy, 0.01))
	else:
		push_error("❌ OXY материал не найден!")

# Increase Zone
func _on_increase_zone_entered(body: Node3D) -> void:
	if body.name == "Player":
		is_in_increase_zone = true
		print("➕ Player entered increase zone - OXY restoring")

func _on_increase_zone_exited(body: Node3D) -> void:
	if body.name == "Player":
		is_in_increase_zone = false
		print("⏸️ Player exited increase zone")

# Decrease Zone
func _on_decrease_zone_entered(body: Node3D) -> void:
	if body.name == "Player":
		is_in_decrease_zone = true
		print("➖ Player entered decrease zone - OXY draining")

func _on_decrease_zone_exited(body: Node3D) -> void:
	if body.name == "Player":
		is_in_decrease_zone = false
		print("⏸️ Player exited decrease zone")

# Дополнительные методы для прямого управления OXYGEN
func set_hp(value: float) -> void:
	current_oxy = clamp(value, 0.0, 1.0)
	_update_oxy_bar()

func get_oxi() -> float:
	return current_oxy

func add_oxi(amount: float) -> void:
	current_oxy = clamp(current_oxy + amount, 0.0, 1.0)
	_update_oxy_bar()

func remove_oxi(amount: float) -> void:
	current_oxy = clamp(current_oxy - amount, 0.0, 1.0)
	_update_oxy_bar()

# Для тестирования в редакторе
func _input(event: InputEvent) -> void:
	if OS.is_debug_build():
		if event is InputEventKey and event.pressed:
			if event.keycode == KEY_KP_ADD: # Numpad +
				add_oxi(0.1)
				print("🧪 TEST: Oxy +0.1 = ", current_oxy)
			elif event.keycode == KEY_KP_SUBTRACT: # Numpad -
				remove_oxi(0.1)
				print("🧪 TEST: Oxy -0.1 = ", current_oxy)
