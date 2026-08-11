extends Node3D
class_name StaminaComponent

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

@export_group("Усталость (плавное снижение скорости бега)")
@export var fatigue_start_ratio: float = 0.4  # выше этого % стамины — бег на полной скорости
@export var fatigue_curve_power: float = 1.6  # >1 = скорость падает резче ближе к нулю, <1 = плавнее

@export_group("Health Ceiling")
## Fraction of max_stamina available while the owner's health is critical —
## a design tuning value, not something to assign from code. player.gd
## reads this export and hands it to set_capacity_ratio() when
## HealthComponent's band goes CRITICAL; this component has no idea why the
## ratio changes, only that it does.
@export var critical_capacity_ratio: float = 0.25

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

## External ceiling multiplier on max_stamina, [0,1] — see
## get_effective_max_stamina(). Set only through set_capacity_ratio(); this
## component never decides on its own to change it.
var _capacity_ratio: float = 1.0
## True while an outside system has explicitly forbidden sprinting,
## independent of _capacity_ratio — see set_sprint_blocked()'s own comment
## on why the two are kept separate rather than one being derived from the
## other.
var _sprint_blocked: bool = false

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
	current_stamina = get_effective_max_stamina()  # == max_stamina while _capacity_ratio is 1.0
	
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
		# Recovery stops at the effective ceiling, not the nominal max —
		# otherwise it would keep climbing past a lowered capacity ratio.
		var effective_max: float = get_effective_max_stamina()
		if current_stamina < effective_max:
			stamina_recover_timer += delta

			if stamina_recover_timer >= stamina_recover_delay:
				var was_zero = current_stamina == 0.0
				current_stamina += stamina_recover_rate * delta
				current_stamina = min(current_stamina, effective_max)

				# Сигнал о восстановлении стамины
				if was_zero and current_stamina > 0.0:
					was_depleted = false
					stamina_recovered.emit()
	
	# Уведомления об изменениях
	# max_stamina here on purpose, not the effective ceiling: consumers of
	# this signal (HUD, debug UI) draw the FULL bar width and let current
	# stamina visibly fall short of it while the ceiling is lowered — that
	# shortfall is the whole point of the health tie-in being visible.
	if abs(current_stamina - previous_stamina) > 0.001:
		stamina_changed.emit(current_stamina, max_stamina)
	
	var is_sprint_allowed_now: bool = is_sprint_allowed()
	if is_sprint_allowed_now != was_sprint_allowed:
		sprint_allowed_changed.emit(is_sprint_allowed_now)

func _update_debug_display() -> void:
	# Percentage against max_stamina, same UI-facing reasoning as
	# stamina_changed above: this label is a human-facing readout too, and
	# should show the shortfall against the full bar, not the current ceiling.
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
	# max_stamina on purpose: a jump's cost is a fixed quantity of stamina,
	# not a fraction of whatever ceiling currently applies — consume_stamina()
	# below already refuses correctly if that costs more than what the
	# ceiling currently allows.
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
## sprint_blocked is a separate decision from the capacity ratio (see
## set_sprint_blocked()) — checked here alongside current_stamina rather
## than folded into it.
func is_sprint_allowed() -> bool:
	return current_stamina > 0.0 and not _sprint_blocked

## Получить текущую стамину (0.0 - 1.0)
## Against the effective ceiling, not the nominal max — a ratio of 1.0
## should mean "as full as it can currently get," matching what
## get_run_capacity() (which reads this) needs to reason about sprinting.
func get_stamina_ratio() -> float:
	var effective_max: float = get_effective_max_stamina()
	if effective_max <= 0.0:
		return 0.0
	return current_stamina / effective_max

## Получить абсолютное значение стамины
func get_current_stamina() -> float:
	return current_stamina

## Получить максимальную стамину
## The nominal max, not the effective ceiling — same UI-facing reasoning as
## stamina_changed above.
func get_max_stamina() -> float:
	return max_stamina

## Мгновенно восстановить стамину (для читов/бонусов)
func restore_stamina(amount: float = -1.0) -> void:
	var effective_max: float = get_effective_max_stamina()
	if amount < 0.0:
		current_stamina = effective_max
	else:
		current_stamina = min(current_stamina + amount, effective_max)

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
	
## 1.0 = полный запас на бег, 0.0 = стамина кончилась (эффективно только ходьба).
## Снижается плавно после fatigue_start_ratio — не рывком в момент истощения.
func get_run_capacity() -> float:
	var ratio: float = get_stamina_ratio()
	if ratio >= fatigue_start_ratio:
		return 1.0
	if fatigue_start_ratio <= 0.0:
		return 0.0 if ratio <= 0.0 else 1.0
	var t: float = clamp(ratio / fatigue_start_ratio, 0.0, 1.0)
	return pow(t, fatigue_curve_power)

## Установить параметры стамины во время выполнения
func set_stamina_parameters(
	new_max_stamina: float = -1.0,
	new_deplete_rate: float = -1.0,
	new_recover_rate: float = -1.0,
	new_recover_delay: float = -1.0
) -> void:
	if new_max_stamina > 0.0:
		# Ratio against the nominal max, not get_stamina_ratio() (which is
		# now relative to the effective ceiling, not max_stamina) - this
		# rescales the whole tank, the capacity ratio aside, then still
		# clamps to whatever ceiling currently applies.
		var ratio: float = current_stamina / max_stamina
		max_stamina = new_max_stamina
		current_stamina = min(max_stamina * ratio, get_effective_max_stamina())
	
	if new_deplete_rate > 0.0:
		stamina_deplete_rate = new_deplete_rate
	
	if new_recover_rate > 0.0:
		stamina_recover_rate = new_recover_rate
	
	if new_recover_delay >= 0.0:
		stamina_recover_delay = new_recover_delay

## Проверить, восстанавливается ли стамина сейчас
## Against the effective ceiling, not max_stamina - matches
## _update_stamina()'s own recovery condition, or this would report "still
## recovering" even after current_stamina has already settled at a lowered
## ceiling with nowhere left to climb.
func is_recovering() -> bool:
	return not is_consuming_stamina and current_stamina < get_effective_max_stamina() and stamina_recover_timer >= stamina_recover_delay


## External ceiling multiplier — player.gd calls this when HealthComponent's
## band changes (see on_world_ready() there), but this component has no
## idea why: it just knows a new ratio was handed to it. See
## get_effective_max_stamina() for how it's applied.
func set_capacity_ratio(ratio: float) -> void:
	var clamped: float = clamp(ratio, 0.0, 1.0)
	if is_equal_approx(clamped, _capacity_ratio):
		return
	_capacity_ratio = clamped

	# Lowering the ceiling clamps current stamina down immediately, rather
	# than leaving it above the new ceiling until _process() next drains it
	# — is_sprint_allowed()/get_stamina_ratio() must already be correct the
	# instant the ceiling drops, not a frame later.
	var effective_max: float = get_effective_max_stamina()
	if current_stamina > effective_max:
		current_stamina = effective_max
		stamina_changed.emit(current_stamina, max_stamina)


## The ceiling current_stamina cannot exceed right now: max_stamina scaled
## by whatever _capacity_ratio was last set to. Internal — get_max_stamina()
## stays the public, nominal value (see that getter's own comment).
func get_effective_max_stamina() -> float:
	return max_stamina * _capacity_ratio


## Forbids sprinting outright, independent of _capacity_ratio: a lowered
## ceiling and a blocked sprint are two different decisions (see
## critical_capacity_ratio's own comment on the ceiling's purpose — sprint
## is refused separately so a short burst under the ceiling stays possible
## without also being a sprint). Mixing the two into one flag would lose the
## ability to tune either independently.
func set_sprint_blocked(blocked: bool) -> void:
	if blocked == _sprint_blocked:
		return
	_sprint_blocked = blocked
	sprint_allowed_changed.emit(is_sprint_allowed())
