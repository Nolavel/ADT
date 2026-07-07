extends Node3D

@onready var area_increase_hp: Area3D = $IncreaseHP
@onready var area_decrease_hp: Area3D = $DecreaseHP
@export var hp_bar: MeshInstance3D ## indicator hp

# Параметры HP
var current_hp: float = 1.0
var hp_change_rate: float = 0.1 # 0.1 HP за 1 секунду

# Флаги для отслеживания зон
var is_in_increase_zone: bool = false
var is_in_decrease_zone: bool = false

# Кэш материала
var hp_material: ShaderMaterial = null

func _ready() -> void:
	if area_increase_hp:
		area_increase_hp.body_entered.connect(_on_increase_zone_entered)
		area_increase_hp.body_exited.connect(_on_increase_zone_exited)
	
	if area_decrease_hp:
		area_decrease_hp.body_entered.connect(_on_decrease_zone_entered)
		area_decrease_hp.body_exited.connect(_on_decrease_zone_exited)
	
	# Получаем материал и кэшируем его
	if hp_bar:
		# Проверяем все поверхности меша
		for i in range(hp_bar.get_surface_override_material_count()):
			var mat = hp_bar.get_surface_override_material(i)
			if mat and mat is ShaderMaterial:
				hp_material = mat
				print("✅ HP Bar материал найден на поверхности ", i)
				break
		
		# Если не нашли override material, пробуем активный материал
		if not hp_material:
			var mat = hp_bar.get_active_material(0)
			if mat and mat is ShaderMaterial:
				# Создаем уникальный материал для этого меша
				hp_material = mat.duplicate()
				hp_bar.set_surface_override_material(0, hp_material)
				print("✅ HP Bar материал дублирован и установлен")
		
		if not hp_material:
			push_error("❌ Не удалось найти ShaderMaterial для HP Bar!")
	else:
		push_error("❌ HP Bar меш не назначен!")
	
	# Устанавливаем начальное значение HP
	_update_hp_bar()
	print("🎯 HP Controller готов | HP: ", current_hp)

func _process(delta: float) -> void:
	var hp_changed = false
	var old_hp = current_hp
	
	# Увеличиваем HP если игрок в зоне увеличения
	if is_in_increase_zone:
		current_hp += hp_change_rate * delta
		hp_changed = true
	
	# Уменьшаем HP если игрок в зоне уменьшения
	if is_in_decrease_zone:
		current_hp -= hp_change_rate * delta
		hp_changed = true
	
	# Clamp значения HP
	current_hp = clamp(current_hp, 0.0, 1.0)
	
	# Обновляем шейдер если HP изменилось
	if hp_changed and abs(old_hp - current_hp) > 0.001:
		_update_hp_bar()

func _update_hp_bar() -> void:
	if hp_material:
		hp_material.set_shader_parameter("health", current_hp)
		print("💚 HP обновлен: ", snappedf(current_hp, 0.01))
	else:
		push_error("❌ HP материал не найден!")

# Increase Zone
func _on_increase_zone_entered(body: Node3D) -> void:
	if body.name == "Player":
		is_in_increase_zone = true
		print("➕ Player entered increase zone - HP restoring")

func _on_increase_zone_exited(body: Node3D) -> void:
	if body.name == "Player":
		is_in_increase_zone = false
		print("⏸️ Player exited increase zone")

# Decrease Zone
func _on_decrease_zone_entered(body: Node3D) -> void:
	if body.name == "Player":
		is_in_decrease_zone = true
		print("➖ Player entered decrease zone - HP draining")

func _on_decrease_zone_exited(body: Node3D) -> void:
	if body.name == "Player":
		is_in_decrease_zone = false
		print("⏸️ Player exited decrease zone")

# Дополнительные методы для прямого управления HP
func set_hp(value: float) -> void:
	current_hp = clamp(value, 0.0, 1.0)
	_update_hp_bar()

func get_hp() -> float:
	return current_hp

func add_hp(amount: float) -> void:
	current_hp = clamp(current_hp + amount, 0.0, 1.0)
	_update_hp_bar()

func remove_hp(amount: float) -> void:
	current_hp = clamp(current_hp - amount, 0.0, 1.0)
	_update_hp_bar()

# Для тестирования в редакторе
func _input(event: InputEvent) -> void:
	if OS.is_debug_build():
		if event is InputEventKey and event.pressed:
			if event.keycode == KEY_KP_ADD: # Numpad +
				add_hp(0.1)
				print("🧪 TEST: HP +0.1 = ", current_hp)
			elif event.keycode == KEY_KP_SUBTRACT: # Numpad -
				remove_hp(0.1)
				print("🧪 TEST: HP -0.1 = ", current_hp)
