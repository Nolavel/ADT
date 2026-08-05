# =============================================================================
# game_clock_system.gd — GameClockSystem
#
# ЕДИНСТВЕННЫЙ источник истины по игровому времени (как PlayerState — по
# режимам). Никто больше не считает время сам: все потребители (освещение,
# NPC-расписания, полиция, витрины) подписываются на сигналы этой системы.
#
# ПОДКЛЮЧЕНИЕ: одна строка в WORLD_SYSTEM_SCRIPTS (world.gd). Создаётся через
# .new(), родитель — World. Экспортов нет намеренно: настройки — константы
# ниже, т.к. систем создаётся кодом и инспектор для неё недоступен.
#
# ПРОИЗВОДИТЕЛЬНОСТЬ: _process только наращивает аккумулятор (одна float-
# операция). Вся рассылка сигналов — по факту смены ИГРОВОЙ МИНУТЫ
# (~раз в 2 реальные секунды при 48-минутных сутках), не каждый кадр.
#
# ПАУЗА: process_mode намеренно дефолтный (PROCESS_MODE_INHERIT).
# PlayerState.open_menu() ставит get_tree().paused = true — время
# останавливается вместе с деревом. Это осознанное решение: в меню
# игровое время не течёт. НЕ менять process_mode без обсуждения.
# =============================================================================
class_name GameClockSystem
extends Node

## Периоды суток. Используются потребителями для крупноблочной логики
## («вечером неон включён», «ночью полиции меньше»), когда точный час не нужен.
enum Period { MIDNIGHT, DAWN, MORNING, NOON, AFTERNOON, EVENING, DUSK, NIGHT }

## Каждый раз при смене игровой минуты. Основной сигнал для освещения.
signal minute_passed(hour_of_day: float)
## Каждый раз при смене игрового часа (0..23).
signal hour_passed(hour: int)
## При смене периода суток (см. enum Period).
signal period_changed(period: Period)
## В 06:00 — начался игровой день с этим номером (нумерация с 1).
signal day_started(day_number: int)
## В 18:00 — началась игровая ночь дня с этим номером.
signal night_started(day_number: int)

# ── Конфигурация ─────────────────────────────────────────────────────────────

## Полные игровые сутки за 48 реальных минут (1 игровой час = 2 реальные минуты).
const REAL_MINUTES_PER_GAME_DAY: float = 48.0

## Стартовое время — вечер: неон и ночная атмосфера в кадре с первого запуска.
const START_HOUR: float = 16.0

## Границы игрового «дня» (для day_started / night_started / is_day_time()).
const DAY_START_HOUR: float = 6.0
const NIGHT_START_HOUR: float = 18.0

# ── Состояние ────────────────────────────────────────────────────────────────

## Общее игровое время в часах с начала игры (не сбрасывается по суткам).
var total_game_hours: float = START_HOUR

## Множитель скорости времени. 1.0 — норма. Публичный API для будущих
## механик крафта/сна («потратить N игровых часов ускоренно»).
## Отдельного узла-акселератора не будет — надстройка поверх этого поля.
var time_scale: float = 1.0:
	set(value):
		time_scale = maxf(value, 0.0)

var _last_minute: int = -1
var _last_hour: int = -1
var _last_period: int = -1
var _was_day: bool = false

# ── Жизненный цикл ───────────────────────────────────────────────────────────

func _ready() -> void:
	# Первичная рассылка состояния подписчикам произойдёт на первой смене
	# минуты; подписчики, которым нужно состояние сразу (освещение),
	# опрашивают get_hour_of_day() в своём on_world_ready().
	_was_day = is_day_time()
	_last_minute = _current_minute_index()
	_last_hour = int(get_hour_of_day())
	_last_period = get_period()


func _process(delta: float) -> void:
	var game_hours_per_real_second := 24.0 / (REAL_MINUTES_PER_GAME_DAY * 60.0)
	total_game_hours += delta * game_hours_per_real_second * time_scale

	var minute := _current_minute_index()
	if minute != _last_minute:
		_last_minute = minute
		_on_minute_changed()

# ── Публичный API (запросы состояния) ────────────────────────────────────────

## Текущий час суток, дробный: 19.5 == 19:30.
func get_hour_of_day() -> float:
	return fmod(total_game_hours, 24.0)


## Номер игровых суток, с 1.
func get_day_number() -> int:
	return int(total_game_hours / 24.0) + 1


## День по игровой логике: [06:00 .. 18:00).
func is_day_time() -> bool:
	var hour := get_hour_of_day()
	return hour >= DAY_START_HOUR and hour < NIGHT_START_HOUR


## Текущий период суток (enum Period).
func get_period() -> Period:
	var hour := int(get_hour_of_day())
	if hour >= 22: return Period.NIGHT       # 22:00–23:59
	if hour >= 20: return Period.DUSK        # 20:00–21:59
	if hour >= 18: return Period.EVENING     # 18:00–19:59
	if hour >= 14: return Period.AFTERNOON   # 14:00–17:59
	if hour >= 10: return Period.NOON        # 10:00–13:59
	if hour >= 6:  return Period.MORNING     # 06:00–09:59
	if hour >= 4:  return Period.DAWN        # 04:00–05:59
	return Period.MIDNIGHT                   # 00:00–03:59


## "19:04" — 24-часовой формат для HUD/дебага.
func get_formatted_time() -> String:
	var hour := get_hour_of_day()
	return "%02d:%02d" % [int(hour), int(hour * 60.0) % 60]

# ── Save / Load ──────────────────────────────────────────────────────────────

func get_save_data() -> Dictionary:
	return {"total_game_hours": total_game_hours}


func load_save_data(data: Dictionary) -> void:
	total_game_hours = data.get("total_game_hours", START_HOUR)
	# Форсируем полную рассылку на следующем кадре: сбрасываем кэши сравнения.
	_last_minute = -1
	_last_hour = -1
	_last_period = -1
	_was_day = is_day_time()

# ── Внутреннее ───────────────────────────────────────────────────────────────

## Индекс текущей игровой минуты внутри суток (0..1439).
func _current_minute_index() -> int:
	return int(get_hour_of_day() * 60.0)


func _on_minute_changed() -> void:
	var hour_float := get_hour_of_day()
	minute_passed.emit(hour_float)

	var hour := int(hour_float)
	if hour != _last_hour:
		_last_hour = hour
		hour_passed.emit(hour)

	var period := get_period()
	if period != _last_period:
		_last_period = period
		period_changed.emit(period)

	var is_day := is_day_time()
	if is_day != _was_day:
		_was_day = is_day
		if is_day:
			day_started.emit(get_day_number())
		else:
			night_started.emit(get_day_number())
