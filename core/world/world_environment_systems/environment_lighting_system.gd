# =============================================================================
# environment_lighting_system.gd — EnvironmentLightingSystem
#
# Динамическое освещение мира: солнце (DirectionalLight3D), небо, ambient,
# depth-fog. ТОЛЬКО подписчик: время не считает, каждую игровую минуту
# получает minute_passed(hour) от GameClockSystem и применяет визуал
# выборкой из Curve/Gradient настроек (см. environment_lighting_settings.gd).
#
# ПОДКЛЮЧЕНИЕ: одна строка в WORLD_SYSTEM_SCRIPTS (world.gd), ПОСЛЕ
# GameClockSystem (для читаемости; технически порядок не важен — все
# системы создаются до первого on_world_ready()).
#
# DirectionalLight3D и WorldEnvironment создаются кодом в _ready() —
# тот же паттерн, что компоненты камеры в camera_follow.gd. В world.tscn
# НЕ должно быть другого WorldEnvironment (активен только один на viewport).
#
# ПРОФИЛИ ПОД ЗОНЫ: сейчас намеренно один профиль на весь остров —
# естественное затенение даёт плотная застройка. Если понадобится
# надстройка (дно кальдеры против внешнего склона): бленд между двумя
# .tres по высоте или зоне. Архитектура это допускает без переделки.
#
# РЕНДЕР: рассчитано на mobile-рендер. Volumetric fog не используется
# (требует Forward+). Тени — самое дорогое: settings.shadows_enabled.
# =============================================================================
class_name EnvironmentLightingSystem
extends Node3D

const SETTINGS_PATH := "res://data/environment_lighting_settings.tres"

var _settings: EnvironmentLightingSettings
var _sun: DirectionalLight3D
var _world_env: WorldEnvironment
var _sky_material: ProceduralSkyMaterial


func _ready() -> void:
	_load_settings()
	_create_sun()
	_create_environment()
	# Сами ничего не тикаем — работаем только от сигналов часов.
	set_process(false)


func on_world_ready(context: WorldContext) -> void:
	var clock := context.get_system(GameClockSystem) as GameClockSystem
	if clock == null:
		push_error("[EnvironmentLighting] GameClockSystem не найден в WORLD_SYSTEM_SCRIPTS")
		return
	clock.minute_passed.connect(_apply_time_of_day)
	# Первичное применение — не ждём первой смены минуты.
	_apply_time_of_day(clock.get_hour_of_day())

# ── Публичный API ────────────────────────────────────────────────────────────

## Включение/выключение теней на лету (для перф-тестов и настроек графики).
func set_shadows_enabled(enabled: bool) -> void:
	if _sun:
		_sun.shadow_enabled = enabled

# ── Инициализация ────────────────────────────────────────────────────────────

func _load_settings() -> void:
	if ResourceLoader.exists(SETTINGS_PATH):
		_settings = load(SETTINGS_PATH) as EnvironmentLightingSettings
	if _settings == null:
		# .tres отсутствует/побит — работаем на дефолтах из _init() ресурса.
		push_warning("[EnvironmentLighting] Settings не найдены (%s), использую дефолты" % SETTINGS_PATH)
		_settings = EnvironmentLightingSettings.new()


func _create_sun() -> void:
	_sun = DirectionalLight3D.new()
	_sun.name = "SunLight"
	_sun.shadow_enabled = _settings.shadows_enabled
	_sun.directional_shadow_max_distance = _settings.shadow_max_distance
	_sun.directional_shadow_blend_splits = false
	if _settings.shadow_orthogonal:
		# Один сплит: геометрия рисуется в shadow-атлас 1 раз вместо 4.
		_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	add_child(_sun)


func _create_environment() -> void:
	_sky_material = ProceduralSkyMaterial.new()

	var sky := Sky.new()
	sky.sky_material = _sky_material
	# Минимальная radiance-карта: мы меняем цвета неба каждую игровую минуту,
	# и каждое изменение заставляет Godot перегенерировать radiance. Отражения
	# от неба мы не используем (см. reflected_light_source ниже), поэтому
	# держим её минимальной — иначе периодические спайки на iGPU.
	sky.radiance_size = Sky.RADIANCE_SIZE_64

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	# Явный цвет ambient (не небо): детерминированный контроль на mobile-рендере.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# Отражения неба отключены: экономия на HD-класса iGPU. Если появятся
	# металлические/зеркальные материалы и будут выглядеть мёртво — вернуть
	# REFLECTION_SOURCE_BG и замерить цену.
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.fog_enabled = _settings.fog_enabled
	env.fog_sky_affect = _settings.fog_sky_affect

	_world_env = WorldEnvironment.new()
	_world_env.name = "WorldEnvironment"
	_world_env.environment = env
	add_child(_world_env)

# ── Применение времени суток ─────────────────────────────────────────────────

## Вызывается каждую игровую минуту (~раз в 2 реальные секунды при
## 48-минутных сутках). Единственный параметр всех выборок: t = час / 24.
func _apply_time_of_day(hour_of_day: float) -> void:
	var t := hour_of_day / 24.0

	# — Солнце —
	_sun.rotation_degrees.x = -_settings.sun_altitude_curve.sample(t)
	_sun.rotation_degrees.y = _settings.sun_azimuth_curve.sample(t)
	_sun.light_color = _settings.sun_color_gradient.sample(t)
	_sun.light_energy = _settings.sun_energy_curve.sample(t)

	# — Небо —
	_sky_material.sky_top_color = _settings.sky_top_gradient.sample(t)
	_sky_material.sky_horizon_color = _settings.sky_horizon_gradient.sample(t)
	_sky_material.ground_horizon_color = _settings.sky_horizon_gradient.sample(t)
	_sky_material.sky_energy_multiplier = _settings.sky_energy_curve.sample(t)

	# — Ambient —
	var env := _world_env.environment
	env.ambient_light_color = _settings.ambient_color_gradient.sample(t)
	env.ambient_light_energy = _settings.ambient_energy_curve.sample(t)

	# — Туман —
	if _settings.fog_enabled:
		env.fog_light_color = _settings.fog_color_gradient.sample(t)
		env.fog_density = _settings.fog_density_curve.sample(t)
