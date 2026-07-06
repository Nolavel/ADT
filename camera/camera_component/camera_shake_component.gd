# =============================================================================
# camera_shake_component.gd
# Node — полностью изолированный компонент тряски камеры.
#
# КОНТРАКТ (важно не нарушать при доработках):
#   - Этот компонент НИКОГДА не трогает Camera3D/Node3D напрямую.
#   - Он не хранит и не знает "базовую" позицию/поворот камеры.
#   - Единственный способ повлиять на камеру — через ЧИСТЫЕ геттеры
#     get_offset() / get_rotation_offset(), которые хост-камера сама
#     складывает со своей уже посчитанной базовой трансформацией
#     КАЖДЫЙ кадр заново.
#   - Из этого следует: компонент физически не может оставить
#     остаточное смещение камеры — ему нечем это сделать, он не пишет
#     ни в одно свойство камеры. Если геттеры вызывать перестали
#     (например камера сменила режим) — последнее, что они возвращали,
#     просто больше никогда не прибавляется. Ничего "зависнуть" не может.
#
# Использование хостом:
#   var shake := CameraShakeComponent.new()
#   add_child(shake)
#   ...
#   func _process(delta):
#       shake.update(delta)
#       var base_transform := _compute_base_transform()  # без shake
#       global_position = base_transform.origin + shake.get_offset()
#       global_rotation  = base_transform.basis.get_euler() + shake.get_rotation_offset()
# =============================================================================
extends Node
class_name CameraShakeComponent

## Экспоненциальное затухание (2.0-3.0 = реалистичнее, выше = резче спад)
@export var trauma_power: float = 2.0

## Максимальный угол наклона камеры от тряски, в градусах
@export var max_rotation_deg: float = 10.0

## Частота вибрации (Hz) — выше = более "нервная" тряска
@export var frequency: float = 20.0

## true = trauma плавно уходит в 0 при stop(), false = мгновенный обрыв
@export var smooth_recovery_default: bool = true

## --- Внутреннее состояние (не трогать снаружи напрямую) ---
var _trauma: float = 0.0
var _duration: float = 0.0      # длительность текущего запуска (для decay_rate)
var _amplitude: float = 0.0
var _noise_offset: float = 0.0
var _active: bool = false

const AMPLITUDE_NORMALIZATION: float = 5.0
const IMPULSE_DURATION: float = 0.5


## Запуск тряски заданной силы на заданное время.
## amplitude: множитель силы смещения (не 0..1 — реальные "метры/градусы")
## duration: секунд, за которые trauma сама выйдет в 0 при равномерном спаде
func start(amplitude: float, duration: float) -> void:
	if duration <= 0.0:
		push_warning("[CameraShakeComponent] duration <= 0, тряска не запущена")
		return

	_amplitude = amplitude
	_duration = duration
	_trauma = clamp(amplitude / AMPLITUDE_NORMALIZATION, 0.0, 1.0)
	_active = true


## Импульсная тряска (для взрывов/ударов) — короткая, добавляется
## поверх текущей trauma, а не заменяет её.
func add_impulse(strength: float = 1.0) -> void:
	_trauma = clamp(_trauma + strength, 0.0, 1.0)
	_duration = IMPULSE_DURATION
	_active = true


## Остановить тряску. smooth=true — доиграет плавным спадом (по умолчанию),
## smooth=false — обрывает мгновенно (trauma и offset сразу в 0).
func stop(smooth: bool = smooth_recovery_default) -> void:
	if smooth:
		# Ничего не обнуляем резко — просто больше не продлеваем trauma,
		# и она сама уйдёт в 0 через update() на текущей duration.
		pass
	else:
		_trauma = 0.0
		_active = false


func is_active() -> bool:
	return _active and _trauma > 0.0


## Вызывать из хоста каждый кадр ДО чтения get_offset()/get_rotation_offset().
func update(delta: float) -> void:
	if not _active:
		return

	if _duration > 0.0:
		var decay_rate: float = 1.0 / _duration
		_trauma = max(0.0, _trauma - decay_rate * delta)

	if _trauma <= 0.001:
		_trauma = 0.0
		_active = false
		return

	_noise_offset += delta * frequency


## Чистый геттер — линейное смещение позиции. Не мутирует состояние.
func get_offset() -> Vector3:
	if not is_active():
		return Vector3.ZERO

	var power: float = pow(_trauma, trauma_power)
	var x := sin(_noise_offset * 1.3) * _amplitude * power
	var y := sin(_noise_offset * 1.7) * _amplitude * power * 0.5
	var z := sin(_noise_offset * 1.1) * _amplitude * power
	return Vector3(x, y, z)


## Чистый геттер — угловое смещение (радианы), для сложения с базовым rotation.
func get_rotation_offset() -> Vector3:
	if not is_active():
		return Vector3.ZERO

	var power: float = pow(_trauma, trauma_power)
	var max_rad := deg_to_rad(max_rotation_deg)
	var rx := sin(_noise_offset * 2.1) * max_rad * power
	var ry := sin(_noise_offset * 1.9) * max_rad * power * 0.7
	var rz := sin(_noise_offset * 2.3) * max_rad * power * 0.5
	return Vector3(rx, ry, rz)
