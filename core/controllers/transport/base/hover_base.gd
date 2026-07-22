# =============================================================================
# hover_base.gd — HoverBase, базовое движение всего hover-транспорта.
#
# CharacterBody3D намеренно (решение 2026-07: RigidBody3D показал статтеры
# и плохую физику на целевом железе). Вся "физика" — кинематическая
# псевдофизика: инерция через lerp к целевой скорости, yaw со сглаживанием,
# визуальный крен корпуса без влияния на коллизии.
#
# ГОРИЗОНТАЛЬ — экспоненциальное сглаживание velocity.lerp(target, k) вместо
# move_toward с переключаемым rate. Причина (2026-07, после разбора дрожи):
# move_toward + выбор rate по сравнению длин target/current — это bang-bang
# без гистерезиса; у max_speed current колеблется вокруг target в пределах
# float-погрешности, rate дёргается accel↔braking каждый кадр → видимая
# конвульсия. lerp — система первого порядка, критически задемпфирована by
# design, вокруг цели колебаться не может. Модель подтверждена рабочим
# mech-контроллером (ZoE-подобный "feel"): один коэффициент, выбираемый по
# наличию ввода, а не по сравнению скоростей.
#
# ВЕРТИКАЛЬ — полуавтомат ("игроку проще простого"):
#   • hover_up / hover_down удерживаются — набор/сброс высоты;
#   • отпущены — текущая высота удерживается автоматически (без дрейфа),
#     игрок КОРРЕКТИРУЕТ высоту, а не борется с ней.
#
# РАЗДЕЛЕНИЕ ОТВЕТСТВЕННОСТИ:
#   hover_base        — только движение; откуда пришли намерения, не знает.
#   input_hover_controller — читает намерения игрока из InputSystems.
#   ai_hover_controller    — позже, тот же интерфейс set_move_intent()
#                            (условие NPC-трафика к вертикальному срезу).
#
# Контроллер каждый кадр вызывает set_move_intent(); если не вызвал —
# намерения затухают (intent сбрасывается), ховер плавно останавливается.
# =============================================================================

extends CharacterBody3D
class_name HoverBase

@export_group("Horizontal")
## Максимальная горизонтальная скорость, м/с.
@export var max_speed: float = 60.0
## Отзывчивость разгона (1/с): выше — быстрее выходит на скорость. Это
## коэффициент экспоненты в lerp, а не м/с² — ощущение массы задаётся тем,
## насколько он НИЖЕ braking (медленный разгон, резкий стоп).
@export var acceleration: float = 6.0
## Отзывчивость торможения при отсутствии ввода (1/с). Выше разгона =
## отпустил газ, ховер тормозит резче, чем разгонялся.
@export var braking: float = 8.0

@export_group("Turning")
## Скорость доворота корпуса к направлению движения, рад/с.
@export var yaw_speed: float = 2.2

@export_group("Vertical")
## Скорость набора/сброса высоты, м/с.
@export var vertical_speed: float = 12.0
## Жёсткость удержания высоты (1/с): выше — резче возврат к удерживаемой.
@export var altitude_hold_stiffness: float = 4.0

@export_group("Visual")
## Меш корпуса для визуального крена (не коллизия). Опционально.
@export var body_mesh_path: NodePath
## Максимальный крен в повороте, рад.
@export var max_bank_angle: float = 0.35

## Намерения текущего кадра. move: x=вправо, y=вперёд, в диапазоне [-1..1];
## vertical: [-1..1] (вверх/вниз), 0 = удержание высоты.
var _intent_move: Vector2 = Vector2.ZERO
var _intent_vertical: float = 0.0
var _intent_fresh: bool = false

## Управляет ли кто-то ховером (триггер включает на SEATED).
var _controlled: bool = false

var _hold_altitude: float = 0.0
var _body_mesh: Node3D = null

## Мировое направление разворота у границы (WorldBorderGuardSystem) и его сила
## (0..1). НЕ трогает velocity напрямую — подмешивается в wish_dir до расчёта
## инерции, тем же принципом, что TPSMovementSystem → player.gd через
## set_direct_move_input(): HoverBase остаётся единственным писателем velocity.
var _border_bias_dir:      Vector3 = Vector3.ZERO
var _border_bias_strength: float   = 0.0


func _ready() -> void:
	_hold_altitude = global_position.y
	if body_mesh_path != NodePath():
		_body_mesh = get_node_or_null(body_mesh_path)


## Интерфейс контроллеров (input_* и позже ai_*). Вызывать каждый кадр.
func set_move_intent(move: Vector2, vertical: float) -> void:
	_intent_move = move.limit_length(1.0)
	_intent_vertical = clampf(vertical, -1.0, 1.0)
	_intent_fresh = true


func set_controlled(controlled: bool) -> void:
	_controlled = controlled
	if controlled:
		_hold_altitude = global_position.y   # не дёргаться к старой высоте
	else:
		_intent_move = Vector2.ZERO
		_intent_vertical = 0.0


## Разворот у границы мира. Подмешивается в желаемое направление, не в velocity.
func set_border_steering_bias(world_dir: Vector3, strength: float) -> void:
	_border_bias_dir      = world_dir
	_border_bias_strength = clampf(strength, 0.0, 1.0)


func _physics_process(delta: float) -> void:
	if not _intent_fresh:
		_intent_move = Vector2.ZERO
		_intent_vertical = 0.0
	_intent_fresh = false

	_process_horizontal(delta)
	_process_vertical(delta)
	move_and_slide()
	_process_banking(delta)


# ── Горизонталь: экспоненциальное сглаживание ────────────────────────────────

func _process_horizontal(delta: float) -> void:
	# Намерение в локальных осях корпуса → мировое направление.
	var forward := -global_transform.basis.z
	var right   :=  global_transform.basis.x
	var wish_dir := (forward * _intent_move.y + right * _intent_move.x)
	wish_dir.y = 0.0

	# Разворот у границы — доворачиваем ЖЕЛАЕМОЕ направление, а не результат.
	if _border_bias_strength > 0.0 and wish_dir.length() > 0.01:
		var wish_len := wish_dir.length()
		wish_dir = wish_dir.normalized().lerp(_border_bias_dir, _border_bias_strength) \
				.normalized() * wish_len

	# Целевая горизонтальная скорость. wish_dir.length() (0..1) сохраняет
	# аналоговый ввод — половина стика = половина макс. скорости.
	var target_h := wish_dir * max_speed if wish_dir.length() > 0.01 else Vector3.ZERO

	# Один коэффициент, выбираемый по НАЛИЧИЮ ввода, а не по сравнению длин —
	# именно это убирает bang-bang дрожь у max_speed. lerp никогда не
	# перелетает цель, поэтому колебаться вокруг неё не может.
	var k := acceleration if _intent_move.length() > 0.1 else braking

	var current_h := Vector3(velocity.x, 0.0, velocity.z)
	# Framerate-независимое сглаживание: 1 - exp(-k*dt) вместо k*dt даёт
	# одинаковое ощущение при любом FPS (важно на нестабильном Forward+).
	current_h = current_h.lerp(target_h, 1.0 - exp(-k * delta))

	velocity.x = current_h.x
	velocity.z = current_h.z

	# Корпус доворачивается к направлению движения (не мгновенно).
	if current_h.length() > 1.0:
		var target_yaw := atan2(-current_h.x, -current_h.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, yaw_speed * delta)


# ── Вертикаль: полуавтомат ───────────────────────────────────────────────────

func _process_vertical(delta: float) -> void:
	if absf(_intent_vertical) > 0.01:
		velocity.y = _intent_vertical * vertical_speed
		_hold_altitude = global_position.y + velocity.y * delta
	else:
		# Удержание: демпфированный возврат к _hold_altitude, без дрейфа.
		var error := _hold_altitude - global_position.y
		velocity.y = error * altitude_hold_stiffness


# ── Визуальный крен ──────────────────────────────────────────────────────────

func _process_banking(delta: float) -> void:
	if _body_mesh == null:
		return
	var target_bank := -_intent_move.x * max_bank_angle
	_body_mesh.rotation.z = lerpf(_body_mesh.rotation.z, target_bank, 6.0 * delta)
