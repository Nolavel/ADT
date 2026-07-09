# =============================================================================
# environment_lighting_settings.gd — EnvironmentLightingSettings (Resource)
#
# Все параметры динамического освещения. Единый входной параметр всех
# кривых/градиентов — t = час_суток / 24.0 (0.0 = полночь, 0.5 = полдень).
#
# ПОЧЕМУ Curve/Gradient, а не функции в коде: рассвет/закат/ночь рисуются
# мышкой в инспекторе. Сдвинуть закат, поменять цвет неона в тумане —
# правка .tres, ноль строк кода. Это основной инструмент итерации по
# атмосфере города.
#
# ДЕФОЛТЫ: _init() заполняет все null-поля рабочими значениями. Порядок
# загрузки ресурса в Godot: сначала _init(), затем поверх — сохранённые
# в .tres значения. Т.е. всё, что ты отредактировал и сохранил в
# environment_lighting_settings.tres, ВСЕГДА побеждает дефолты из кода;
# дефолты срабатывают только для полей, которых в .tres нет.
# =============================================================================
class_name EnvironmentLightingSettings
extends Resource

@export_group("Sun")
## Высота солнца над горизонтом в градусах по времени суток (ночью — под ним).
@export var sun_altitude_curve: Curve
## Азимут солнца в градусах (полный оборот за сутки: восток→юг→запад).
@export var sun_azimuth_curve: Curve
## Цвет солнечного/лунного света по времени суток.
@export var sun_color_gradient: Gradient
## Энергия DirectionalLight по времени суток (ночью — слабый «лунный» минимум).
@export var sun_energy_curve: Curve

@export_group("Shadows")
## Тени от солнца. Самая дорогая часть системы — выключай при просадках FPS.
@export var shadows_enabled: bool = true
## Дистанция теней. Консервативно под старое железо / mobile-рендер.
@export var shadow_max_distance: float = 150.0
## Ортогональный режим (один сплит вместо 4 PSSM) — в разы дешевле.
## Для нашей изометрии/топдауна PSSM-каскады не дают ничего: они нужны
## FPS-камерам с большой глубиной взгляда. Выключай только для TPS-тестов.
@export var shadow_orthogonal: bool = false

@export_group("Sky")
@export var sky_top_gradient: Gradient
@export var sky_horizon_gradient: Gradient
@export var sky_energy_curve: Curve

@export_group("Ambient")
## Источник — явный цвет (не небо): детерминированный контроль на mobile-рендере.
@export var ambient_color_gradient: Gradient
@export var ambient_energy_curve: Curve

@export_group("Fog")
## Обычный экспоненциальный depth-fog. Volumetric fog НЕ используем —
## он требует Forward+ и на mobile-рендере не работает.
@export var fog_enabled: bool = true
@export var fog_color_gradient: Gradient
## Плотность тумана по времени суток (ночью плотнее — дымка между башнями).
@export var fog_density_curve: Curve
## Насколько туман «съедает» небо у горизонта (0..1).
@export var fog_sky_affect: float = 0.35


func _init() -> void:
	if sun_altitude_curve == null:
		sun_altitude_curve = _make_curve(-60.0, 90.0, [
			Vector2(0.0, -30.0),   # 00:00 — глубоко под горизонтом
			Vector2(0.25, 0.0),    # 06:00 — восход
			Vector2(0.5, 55.0),    # 12:00 — зенит
			Vector2(0.75, 0.0),    # 18:00 — закат
			Vector2(1.0, -30.0),   # 24:00
		])
	if sun_azimuth_curve == null:
		# Равномерный полный оборот: 06:00 = 90° (восток), 12:00 = 180° (юг),
		# 18:00 = 270° (запад). Линейно — сэмплится без изломов.
		sun_azimuth_curve = _make_curve(0.0, 360.0, [
			Vector2(0.0, 0.0),
			Vector2(1.0, 360.0),
		])
	if sun_color_gradient == null:
		sun_color_gradient = _make_gradient([
			[0.00, Color(0.55, 0.62, 0.80)],  # ночь — холодный «лунный»
			[0.22, Color(0.55, 0.62, 0.80)],
			[0.26, Color(1.00, 0.60, 0.40)],  # рассвет — оранжевый
			[0.32, Color(1.00, 0.97, 0.93)],  # день — тёплый белый
			[0.68, Color(1.00, 0.97, 0.93)],
			[0.74, Color(1.00, 0.45, 0.30)],  # закат — красно-оранжевый
			[0.79, Color(0.55, 0.62, 0.80)],  # снова ночь
			[1.00, Color(0.55, 0.62, 0.80)],
		])
	if sun_energy_curve == null:
		sun_energy_curve = _make_curve(0.0, 1.5, [
			Vector2(0.0, 0.12),    # ночной «лунный» минимум
			Vector2(0.21, 0.12),
			Vector2(0.3, 0.7),
			Vector2(0.5, 1.0),     # полдень
			Vector2(0.7, 0.7),
			Vector2(0.79, 0.12),
			Vector2(1.0, 0.12),
		])
	if sky_top_gradient == null:
		sky_top_gradient = _make_gradient([
			[0.00, Color(0.04, 0.03, 0.10)],  # ночь — глубокий сине-фиолетовый
			[0.23, Color(0.04, 0.03, 0.10)],
			[0.28, Color(0.30, 0.22, 0.38)],  # рассветный пурпур
			[0.36, Color(0.20, 0.40, 0.75)],  # день
			[0.64, Color(0.20, 0.40, 0.75)],
			[0.73, Color(0.45, 0.22, 0.30)],  # закат
			[0.80, Color(0.04, 0.03, 0.10)],
			[1.00, Color(0.04, 0.03, 0.10)],
		])
	if sky_horizon_gradient == null:
		sky_horizon_gradient = _make_gradient([
			[0.00, Color(0.12, 0.08, 0.18)],  # ночь — неоновая дымка у горизонта
			[0.23, Color(0.12, 0.08, 0.18)],
			[0.27, Color(0.90, 0.50, 0.40)],  # рассвет
			[0.35, Color(0.60, 0.75, 0.95)],  # день
			[0.65, Color(0.60, 0.75, 0.95)],
			[0.74, Color(0.90, 0.42, 0.35)],  # закат
			[0.80, Color(0.12, 0.08, 0.18)],
			[1.00, Color(0.12, 0.08, 0.18)],
		])
	if sky_energy_curve == null:
		sky_energy_curve = _make_curve(0.0, 1.5, [
			Vector2(0.0, 0.3),
			Vector2(0.22, 0.3),
			Vector2(0.4, 1.0),
			Vector2(0.6, 1.0),
			Vector2(0.78, 0.3),
			Vector2(1.0, 0.3),
		])
	if ambient_color_gradient == null:
		ambient_color_gradient = _make_gradient([
			[0.00, Color(0.10, 0.09, 0.18)],
			[0.23, Color(0.10, 0.09, 0.18)],
			[0.35, Color(0.65, 0.75, 0.95)],
			[0.65, Color(0.65, 0.75, 0.95)],
			[0.78, Color(0.10, 0.09, 0.18)],
			[1.00, Color(0.10, 0.09, 0.18)],
		])
	if ambient_energy_curve == null:
		ambient_energy_curve = _make_curve(0.0, 1.5, [
			Vector2(0.0, 0.25),
			Vector2(0.22, 0.25),
			Vector2(0.4, 1.0),
			Vector2(0.6, 1.0),
			Vector2(0.78, 0.25),
			Vector2(1.0, 0.25),
		])
	if fog_color_gradient == null:
		fog_color_gradient = _make_gradient([
			[0.00, Color(0.09, 0.06, 0.16)],  # ночь — подкрашенная неоном дымка
			[0.24, Color(0.09, 0.06, 0.16)],
			[0.35, Color(0.55, 0.60, 0.70)],  # день — серо-голубая
			[0.65, Color(0.55, 0.60, 0.70)],
			[0.78, Color(0.09, 0.06, 0.16)],
			[1.00, Color(0.09, 0.06, 0.16)],
		])
	if fog_density_curve == null:
		fog_density_curve = _make_curve(0.0, 0.005, [
			Vector2(0.0, 0.0025),  # ночью плотнее
			Vector2(0.35, 0.0008),
			Vector2(0.65, 0.0008),
			Vector2(1.0, 0.0025),
		])

# ── Фабрики дефолтов ─────────────────────────────────────────────────────────

## points: массив Vector2(t, value). Параметр намеренно нетипизированный:
## литерал [...] в GDScript — untyped Array, в Array[Vector2] не приводится.
static func _make_curve(min_val: float, max_val: float, points: Array) -> Curve:
	var curve := Curve.new()
	curve.min_value = min_val
	curve.max_value = max_val
	for p in points:
		curve.add_point(p)
	return curve


## pairs: массив [offset: float, color: Color].
static func _make_gradient(pairs: Array) -> Gradient:
	var gradient := Gradient.new()
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	for pair in pairs:
		offsets.append(pair[0])
		colors.append(pair[1])
	gradient.offsets = offsets
	gradient.colors = colors
	return gradient
