extends Node3D
class_name StaminaManager

# === СИГНАЛЫ ===
signal stamina_changed(current_stamina: float, max_stamina: float)
signal stamina_depleted()
signal stamina_recovered()
signal sprint_allowed_changed(is_allowed: bool)
signal jump_performed() 

# === ПАРАМЕТРЫ СТАМИНЫ ===
@export_group("Параметры стамины")
@export var max_stamina: float = 100.0
@export var stamina_deplete_rate: float = 5.0  # стамина в секунду при использовании
@export var stamina_recover_rate: float = 3.0  # стамина в секунду при восстановлении
@export var stamina_recover_delay: float = 5.0  # секунды до начала восстановления
@export var min_stamina_for_action: float = 1.0  # минимум стамины для выполнения действия
@export var jump_stamina_cost: float = 5.0  # 10% от максимальной стамины

# === DEBUG ===
@export_group("Debug")
@export var debug_show_stamina: bool = false
@export var debug_label_path: NodePath

# === ВНУТРЕННИЕ ПЕРЕМЕННЫЕ ===
var current_stamina: float = 1.0
var stamina_recover_timer: float = 0.0
var is_consuming_stamina: bool = false
var was_depleted: bool = false
var _debug_label: Label = null

func _ready() -> void:
	# Защита от некорректных значений
	if max_stamina <= 0.0:
		push_warning("Max stamina must be positive, setting to 1.0")
		max_stamina = 1.0
	
	if stamina_deplete_rate <= 0.0:
		push_warning("Stamina deplete rate must be positive, setting to 0.5")
		stamina_deplete_rate = 0.5
	
	if stamina_recover_rate <= 0.0:
		push_warning("Stamina recover rate must be positive, setting to 0.3")
		stamina_recover_rate = 0.3
	
	# Инициализация стамины
	current_stamina = max_stamina
	
	# Инициализация debug label
	if debug_show_stamina and debug_label_path != NodePath():
		_debug_label = get_node_or_null(debug_label_path)
		if _debug_label == null:
			push_warning("Debug stamina label path is invalid — stamina display will not work.")

func _process(delta: float) -> void:
	_update_stamina(delta)
	_update_debug_display()

func _update_stamina(delta: float) -> void:
	var previous_stamina: float = current_stamina
	var was_sprint_allowed: bool = is_sprint_allowed()
	
	if is_consuming_stamina and current_stamina > 0.0:
		# Тратим стамину
		current_stamina -= stamina_deplete_rate * delta
		current_stamina = max(current_stamina, 0.0)
		stamina_recover_timer = 0.0
		
		# Проверяем истощение стамины
		if current_stamina == 0.0 and not was_depleted:
			was_depleted = true
			stamina_depleted.emit()
	else:
		# Восстанавливаем стамину после задержки
		if current_stamina < max_stamina:
			stamina_recover_timer += delta
			
			if stamina_recover_timer >= stamina_recover_delay:
				var was_zero = current_stamina == 0.0
				current_stamina += stamina_recover_rate * delta
				current_stamina = min(current_stamina, max_stamina)
				
				# Сигнал о восстановлении стамины
				if was_zero and current_stamina > 0.0:
					was_depleted = false
					stamina_recovered.emit()
	
	# Уведомления об изменениях
	if abs(current_stamina - previous_stamina) > 0.001:
		stamina_changed.emit(current_stamina, max_stamina)
	
	var is_sprint_allowed_now: bool = is_sprint_allowed()
	if is_sprint_allowed_now != was_sprint_allowed:
		sprint_allowed_changed.emit(is_sprint_allowed_now)

func _update_debug_display() -> void:
	if debug_show_stamina and _debug_label != null:
		var percentage: float = (current_stamina / max_stamina) * 100.0
		_debug_label.text = "Stamina: %.1f%%" % percentage
		
		# Меняем цвет в зависимости от уровня стамины
		if current_stamina > max_stamina * 0.5:
			_debug_label.add_theme_color_override("font_color", Color.WHITE)
		elif current_stamina > max_stamina * 0.25:
			_debug_label.add_theme_color_override("font_color", Color.YELLOW)
		else:
			_debug_label.add_theme_color_override("font_color", Color.RED)

func try_jump() -> bool:
	var cost = max_stamina * (jump_stamina_cost / 100.0)
	if consume_stamina(cost):
		jump_performed.emit()
		return true
	return false

	
# === ПУБЛИЧНЫЕ МЕТОДЫ ===

## Начать тратить стамину
func start_consuming_stamina() -> void:
	if not is_consuming_stamina:
		is_consuming_stamina = true

## Прекратить тратить стамину
func stop_consuming_stamina() -> void:
	if is_consuming_stamina:
		is_consuming_stamina = false

## Проверить, достаточно ли стамины для действия
func has_stamina_for_action() -> bool:
	return current_stamina >= min_stamina_for_action

## Проверить, разрешен ли спринт
func is_sprint_allowed() -> bool:
	return current_stamina > 0.0

## Получить текущую стамину (0.0 - 1.0)
func get_stamina_ratio() -> float:
	return current_stamina / max_stamina

## Получить абсолютное значение стамины
func get_current_stamina() -> float:
	return current_stamina

## Получить максимальную стамину
func get_max_stamina() -> float:
	return max_stamina

## Мгновенно восстановить стамину (для читов/бонусов)
func restore_stamina(amount: float = -1.0) -> void:
	if amount < 0.0:
		current_stamina = max_stamina
	else:
		current_stamina = min(current_stamina + amount, max_stamina)
	
	if was_depleted and current_stamina > 0.0:
		was_depleted = false
		stamina_recovered.emit()
	
	stamina_changed.emit(current_stamina, max_stamina)

## Мгновенно потратить стамину
func consume_stamina(amount: float) -> bool:
	if current_stamina >= amount:
		current_stamina -= amount
		current_stamina = max(current_stamina, 0.0)
		
		if current_stamina == 0.0 and not was_depleted:
			was_depleted = true
			stamina_depleted.emit()
		
		stamina_changed.emit(current_stamina, max_stamina)
		return true
	
	return false

## Установить параметры стамины во время выполнения
func set_stamina_parameters(
	new_max_stamina: float = -1.0,
	new_deplete_rate: float = -1.0,
	new_recover_rate: float = -1.0,
	new_recover_delay: float = -1.0
) -> void:
	if new_max_stamina > 0.0:
		var ratio: float = get_stamina_ratio()
		max_stamina = new_max_stamina
		current_stamina = max_stamina * ratio
	
	if new_deplete_rate > 0.0:
		stamina_deplete_rate = new_deplete_rate
	
	if new_recover_rate > 0.0:
		stamina_recover_rate = new_recover_rate
	
	if new_recover_delay >= 0.0:
		stamina_recover_delay = new_recover_delay

## Проверить, восстанавливается ли стамина сейчас
func is_recovering() -> bool:
	return not is_consuming_stamina and current_stamina < max_stamina and stamina_recover_timer >= stamina_recover_delay
